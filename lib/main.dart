// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:serial/serial.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SerialPort? _port;
  bool _keepReading = false;

  final TextEditingController groupIdController = TextEditingController();
  final List<String> terminalLines = [];

  final List<String> frequencies = ['923875000', '923375000', '924875000'];
  String selectedFrequency = '923875000';

  final TextEditingController spreadingFactorController =
      TextEditingController();
  final TextEditingController updateIntervalController =
      TextEditingController();

  String status = 'Not connected';

  late final MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();

    _scannerController = MobileScannerController(
      facing: CameraFacing.front,
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    groupIdController.dispose();
    spreadingFactorController.dispose();
    updateIntervalController.dispose();
    super.dispose();
  }

  // -----------------------------
  // CONNECT SERIAL
  // -----------------------------
  Future<void> connectPort() async {
    try {
      final port = await web.window.navigator.serial.requestPort().toDart;
      await port.open(baudRate: 9600).toDart;

      _port = port;
      _keepReading = true;
      _startReading(port);

      setState(() {
        status = 'Device connected';
        terminalLines.add('> Connected to device');
      });
    } catch (_) {
      setState(() => status = 'Connection failed');
    }
  }

  // -----------------------------
  // READ SERIAL
  // -----------------------------
  Future<void> _startReading(SerialPort port) async {
    String buffer = '';

    while (port.readable != null && _keepReading) {
      final reader =
          port.readable!.getReader() as web.ReadableStreamDefaultReader;

      try {
        while (_keepReading) {
          final result = await reader.read().toDart;
          if (result.done) break;

          final value = result.value;
          if (value != null && value.isA<JSUint8Array>()) {
            final data = (value as JSUint8Array).toDart;
            buffer += String.fromCharCodes(data);

            final lines = buffer.split(RegExp(r'\r\n|\n|\r'));
            buffer = lines.removeLast();

            for (final line in lines) {
              final clean = line.replaceAll(
                RegExp(r'\x1B\[[0-9;]*[A-Za-z]'),
                '',
              );
              setState(() => terminalLines.add(clean));
            }
          }
        }
      } catch (_) {
        // ignore
      } finally {
        reader.releaseLock();
      }
    }
  }

  // -----------------------------
  // WRITE SERIAL
  // -----------------------------
  Future<void> _write(String text) async {
    final port = _port;
    if (port == null) return;

    final writer = port.writable?.getWriter();
    if (writer == null) return;

    await writer.write(Uint8List.fromList(text.codeUnits).toJS).toDart;
    await writer.close().toDart;
    writer.releaseLock();

    setState(() => terminalLines.add('> $text'.trim()));
  }

  // -----------------------------
  // APPLY SETTINGS
  // -----------------------------
  Future<void> applySettings() async {
    if (_port == null) {
      setState(() => status = 'No device connected');
      return;
    }

    final groupId = groupIdController.text.trim();
    if (groupId.isEmpty) {
      setState(() => status = 'Group ID required');
      return;
    }

    final spreadingFactor = spreadingFactorController.text.trim();
    final updateInterval = updateIntervalController.text.trim();

    try {
      setState(() => terminalLines.add('> Sending commands with QR values...'));

      await _write('\r\n');
      await Future.delayed(const Duration(milliseconds: 150));
      // set the rftag group id to a random value first

      // Generate a random 8-digit number (10000000 to 99999999)
      final randomGroupId =
          (Random().nextDouble() * 90000000).floor() + 10000000;
      setState(() {
        terminalLines.add('> CMD: rftag settings groupid set $randomGroupId');
      });
      await _write('rftag settings groupid set $randomGroupId\r\n');
      await Future.delayed(const Duration(milliseconds: 150));
      setState(() => terminalLines.add('> CMD: rftag loc clear_history'));
      await _write('rftag loc clear_history\r\n');
      await Future.delayed(const Duration(milliseconds: 150));

      // add this command rftag msg incoming clear
      setState(() => terminalLines.add('> CMD: rftag msg incoming clear'));
      await _write('rftag msg incoming clear\r\n');
      await Future.delayed(const Duration(milliseconds: 150));
      setState(() => terminalLines.add('> CMD: rftag msg outgoing clear'));
      await _write('rftag msg outgoing clear\r\n');
      await Future.delayed(const Duration(milliseconds: 150));
      setState(
        () => terminalLines.add('> CMD: rftag settings groupid set $groupId'),
      );
      await _write('rftag settings groupid set $groupId\r\n');
      await Future.delayed(const Duration(milliseconds: 150));

      setState(
        () => terminalLines.add(
          '> CMD: rftag settings lora freq $selectedFrequency',
        ),
      );
      await _write('rftag settings lora freq $selectedFrequency\r\n');
      await Future.delayed(const Duration(milliseconds: 150));

      if (spreadingFactor.isNotEmpty) {
        setState(
          () => terminalLines.add(
            '> CMD: rftag settings lora sf $spreadingFactor',
          ),
        );
        await _write('rftag settings lora sf $spreadingFactor\r\n');
        await Future.delayed(const Duration(milliseconds: 150));
      } else {
        setState(() => terminalLines.add('> SKIP: SF not provided in QR'));
      }

      if (updateInterval.isNotEmpty) {
        setState(
          () => terminalLines.add(
            '> CMD: rftag settings timing interval $updateInterval',
          ),
        );
        await _write('rftag settings timing interval $updateInterval\r\n');
        await Future.delayed(const Duration(milliseconds: 150));
      } else {
        setState(
          () => terminalLines.add('> SKIP: Interval not provided in QR'),
        );
      }
      // add last command kernel reboot cold
      setState(() => terminalLines.add('> CMD: kernel reboot cold'));

      await _write('kernel reboot cold\r\n');

      setState(() => status = 'Commands sent');
    } catch (_) {
      setState(() => status = 'Failed to send commands');
    }
  }

  // -----------------------------
  // QR SCAN (JSON PARSE)
  // -----------------------------
  Future<void> _scanQr() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scannerController.start();
        });

        return Dialog(
          child: SizedBox(
            width: 500,
            height: 500,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Scan QR Code'),
                ),
                Expanded(
                  child: MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        final value = barcode.rawValue;
                        if (value != null) {
                          _scannerController.stop();
                          Navigator.of(context).pop(value);
                          break;
                        }
                      }
                    },
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _scannerController.stop();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;

    try {
      final Map<String, dynamic> data = jsonDecode(result);

      final String groupId = data['groupId'].toString();

      final loraConfig = data['loraConfig'] as Map<String, dynamic>?;

      final double freqMHz =
          (loraConfig?['frequency'] as num?)?.toDouble() ?? 923.875;
      final String freqHz = (freqMHz * 1000000).round().toString();

      // Parse spreading factor - handle both "SF10" format and numeric 10
      String spreadingFactor = '10';
      if (loraConfig?['spreading_factor'] != null) {
        final sfValue = loraConfig!['spreading_factor'].toString();
        // Remove "SF" prefix if present
        spreadingFactor = sfValue.toUpperCase().replaceFirst('SF', '');
      }

      // Parse location update interval
      String updateInterval = '60';
      if (loraConfig?['location_update_interval'] != null) {
        updateInterval = loraConfig!['location_update_interval'].toString();
      }

      setState(() {
        groupIdController.text = groupId;

        if (!frequencies.contains(freqHz)) {
          frequencies.add(freqHz);
        }

        selectedFrequency = freqHz;
        spreadingFactorController.text = spreadingFactor;
        updateIntervalController.text = updateInterval;

        terminalLines.add(
          '> Scanned QR → groupId=$groupId freq=$freqHz sf=$spreadingFactor interval=$updateInterval',
        );
      });

      applySettings();
    } catch (e) {
      setState(() {
        terminalLines.add('> QR parse error: $e');
        status = 'Invalid QR data';
      });
    }
  }

  // -----------------------------
  // UI
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RFTag Config'),
        actions: [
          IconButton(icon: const Icon(Icons.usb), onPressed: connectPort),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: $status'),
            const SizedBox(height: 12),
            TextField(
              controller: groupIdController,
              decoration: const InputDecoration(
                labelText: 'Group ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedFrequency,
              items: frequencies
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) => setState(() => selectedFrequency = v!),
              decoration: const InputDecoration(
                labelText: 'Frequency (Hz)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: spreadingFactorController,
              decoration: const InputDecoration(
                labelText: 'Spreading Factor',
                hintText: 'e.g. 10',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: updateIntervalController,
              decoration: const InputDecoration(
                labelText: 'Update Interval (seconds)',
                hintText: 'e.g. 60',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: applySettings,
              child: const Text('Apply Settings'),
            ),
            const SizedBox(height: 16),
            const Text('Terminal'),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: ListView(
                  children: terminalLines
                      .map(
                        (line) => Text(
                          line,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
