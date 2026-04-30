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

/// Expected success responses from firmware for each command
class CommandExpectation {
  final String command;
  final String successPattern; // Exact substring to look for in response

  const CommandExpectation(this.command, this.successPattern);
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
  final TextEditingController usernameController = TextEditingController();
  bool randomUsernameEnabled = false;

  String status = 'Not connected';

  late final MobileScannerController _scannerController;

  // Stream controller for serial responses
  final StreamController<String> _responseController =
      StreamController<String>.broadcast();

  String _generateRandomUsername() {
    const prefixes = [
      'tag',
      'ranger',
      'trail',
      'summit',
      'ember',
      'scout',
      'nova',
      'echo',
      'atlas',
      'pixel',
      'orbit',
      'quantum',
      'lunar',
      'solar',
      'storm',
      'frost',
      'blaze',
      'drift',
      'shadow',
      'vivid',
      'rapid',
      'wild',
      'alpha',
      'bravo',
      'charlie',
      'delta',
      'vector',
      'zen',
      'turbo',
      'neon',
      'sage',
      'cobalt',
      'ruby',
      'onyx',
      'jade',
      'amber',
      'iron',
      'steel',
      'titan',
      'cosmo',
      'zenith',
      'apex',
      'rift',
      'pulse',
      'comet',
      'glider',
      'terra',
      'aero',
      'radar',
      'signal',
      'cipher',
      'phantom',
      'spectra',
      'aurora',
      'ember',
      'sparrow',
      'falconer',
    ];
    const suffixes = [
      'fox',
      'hawk',
      'bear',
      'wolf',
      'lynx',
      'orca',
      'otter',
      'falcon',
      'eagle',
      'panther',
      'tiger',
      'viper',
      'cobra',
      'raven',
      'sparrow',
      'heron',
      'badger',
      'buffalo',
      'yak',
      'bison',
      'rhino',
      'jaguar',
      'puma',
      'cougar',
      'shark',
      'marlin',
      'ray',
      'kraken',
      'whale',
      'dolphin',
      'seal',
      'walrus',
      'moose',
      'stag',
      'mammoth',
      'griffin',
      'phoenix',
      'dragon',
      'hydra',
      'pegasus',
      'saber',
      'hammer',
      'anvil',
      'bolt',
      'arrow',
      'blade',
      'shield',
      'beacon',
      'anchor',
      'rocket',
      'meteor',
      'saturn',
      'neptune',
      'mars',
      'venus',
      'pluto',
      'comet',
      'nova',
      'zen',
    ];

    final prefix = prefixes[Random().nextInt(prefixes.length)];
    final suffix = suffixes[Random().nextInt(suffixes.length)];
    final number = 100 + Random().nextInt(900);
    return '$prefix-$suffix-$number';
  }

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
    _responseController.close();
    _scannerController.dispose();
    groupIdController.dispose();
    spreadingFactorController.dispose();
    updateIntervalController.dispose();
    usernameController.dispose();
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
              if (clean.trim().isNotEmpty) {
                _responseController.add(clean);
              }
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
  // WRITE SERIAL (raw, no logging)
  // -----------------------------
  Future<void> _writeRaw(String text) async {
    final port = _port;
    if (port == null) return;

    final writer = port.writable?.getWriter();
    if (writer == null) return;

    await writer.write(Uint8List.fromList(text.codeUnits).toJS).toDart;
    await writer.close().toDart;
    writer.releaseLock();
  }

  // -----------------------------
  // SEND COMMAND AND WAIT FOR EXPECTED RESPONSE
  // -----------------------------
  Future<({bool success, String response})> _sendCommand(
    String command,
    String expectedSuccessPattern, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final port = _port;
    if (port == null) {
      return (success: false, response: 'No port connected');
    }

    final completer = Completer<({bool success, String response})>();
    final responses = <String>[];

    // Listen for response lines
    final subscription = _responseController.stream.listen((line) {
      responses.add(line);

      // Check for the exact expected success pattern from firmware
      if (line.contains(expectedSuccessPattern)) {
        if (!completer.isCompleted) {
          completer.complete((success: true, response: line));
        }
      }
      // Check for error pattern: "(rc=-" indicates failure
      else if (line.contains('(rc=-')) {
        if (!completer.isCompleted) {
          completer.complete((success: false, response: line));
        }
      }
    });

    // Log and send the command
    setState(() => terminalLines.add('> CMD: $command'));
    await _writeRaw('$command\r\n');

    // Wait for response or timeout
    try {
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          return (
            success: false,
            response: responses.isEmpty ? 'Timeout' : responses.join('\n'),
          );
        },
      );
      return result;
    } finally {
      await subscription.cancel();
    }
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
    String username = usernameController.text.trim();

    if (randomUsernameEnabled) {
      username = _generateRandomUsername();
      setState(() {
        usernameController.text = username;
        terminalLines.add('> Random username generated: $username');
      });
    }

    try {
      setState(() {
        status = 'Sending commands...';
        terminalLines.add('> Sending commands with QR values...');
      });

      // Wake up the terminal
      await _writeRaw('\r\n');
      await Future.delayed(const Duration(milliseconds: 100));

      // Generate a random 8-digit number (10000000 to 99999999)
      final randomGroupId =
          (Random().nextDouble() * 90000000).floor() + 10000000;

      // Command list with exact expected success patterns from firmware:
      // - "Group ID set to:" from settings_shell.c line 338
      // - "Location history cleared" from location_repo_shell.c line 396
      // - "Incoming messages cleared" from message_repo_shell.c line 169
      // - "Outgoing messages cleared" from message_repo_shell.c line 277
      // - "Frequency set to:" from settings_shell.c line 451
      // - "Spreading factor set to:" from settings_shell.c line 529
      // - "location_update_interval set to:" from settings_shell.c line 1099

      final commands = <CommandExpectation>[
        CommandExpectation(
          'rftag settings groupid set $randomGroupId',
          'Group ID set to:',
        ),
        CommandExpectation(
          'rftag loc clear_history',
          'Location history cleared',
        ),
        CommandExpectation(
          'rftag msg incoming clear',
          'Incoming messages cleared',
        ),
        CommandExpectation(
          'rftag msg outgoing clear',
          'Outgoing messages cleared',
        ),
        CommandExpectation(
          'rftag settings groupid set $groupId',
          'Group ID set to:',
        ),
        CommandExpectation(
          'rftag settings lora freq $selectedFrequency',
          'Frequency set to:',
        ),
      ];

      // Add optional commands
      if (spreadingFactor.isNotEmpty) {
        commands.add(
          CommandExpectation(
            'rftag settings lora sf $spreadingFactor',
            'Spreading factor set to:',
          ),
        );
      }

      if (updateInterval.isNotEmpty) {
        commands.add(
          CommandExpectation(
            'rftag settings timing interval $updateInterval',
            'location_update_interval set to:',
          ),
        );
      }

      if (username.isNotEmpty) {
        commands.add(
          CommandExpectation(
            'rftag settings username set $username',
            'Username set to:',
          ),
        );
      }

      // Execute commands sequentially and count successes
      int successCount = 0;
      int failedCount = 0;
      final int totalCommands = commands.length;

      for (final cmd in commands) {
        final result = await _sendCommand(cmd.command, cmd.successPattern);
        if (!result.success) {
          failedCount++;
          setState(() {
            terminalLines.add('> FAILED: ${cmd.command}');
            terminalLines.add('> Response: ${result.response}');
            status = 'Command failed: ${cmd.command}';
          });
          // Print summary before returning on failure
          setState(() {
            terminalLines.add('');
            terminalLines.add(
              '> ✓ Success: $successCount | ✗ Failed: $failedCount | Total: $totalCommands',
            );
            terminalLines.add('> ✗ Failed command: ${cmd.command}');
            terminalLines.add('');
          });
          return; // Stop on failure
        }
        successCount++;
        setState(() => terminalLines.add('> OK: ${result.response}'));
      }

      // Print success count summary (not counting kernel reboot)
      setState(() {
        terminalLines.add('');
        terminalLines.add(
          '> ✓ Success: $successCount/$totalCommands commands completed successfully',
        );
        terminalLines.add('');
      });

      // Reboot command - send without waiting (device will reboot)
      setState(() => terminalLines.add('> CMD: kernel reboot cold'));
      await _writeRaw('kernel reboot cold\r\n');

      setState(
        () => status =
            'All commands sent successfully ($successCount/$totalCommands OK)',
      );
    } catch (e) {
      setState(() => status = 'Failed to send commands: $e');
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
            TextField(
              controller: usernameController,
              enabled: !randomUsernameEnabled,
              decoration: const InputDecoration(
                labelText: 'Username (optional)',
                hintText: 'e.g. Alice',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  randomUsernameEnabled = !randomUsernameEnabled;
                  if (randomUsernameEnabled) {
                    usernameController.text = _generateRandomUsername();
                  }
                });
              },
              icon: Icon(
                randomUsernameEnabled ? Icons.shuffle_on : Icons.shuffle,
              ),
              label: Text(
                randomUsernameEnabled
                    ? 'Random Username: ON'
                    : 'Random Username: OFF',
              ),
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
