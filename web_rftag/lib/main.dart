// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:serial/serial.dart';

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

  final TextEditingController groupIdController = TextEditingController();

  final List<String> frequencies = ['923875000', '923375000', '924875000'];

  String selectedFrequency = '923875000';
  String status = 'Not connected';

  /// -----------------------------
  /// CONNECT SERIAL PORT
  /// -----------------------------
  Future<void> connectPort() async {
    try {
      final port = await web.window.navigator.serial.requestPort().toDart;
      await port.open(baudRate: 9600).toDart;

      _port = port;

      setState(() {
        status = 'Device connected';
      });
    } catch (e) {
      setState(() {
        status = 'Connection failed';
      });
    }
  }

  /// -----------------------------
  /// LOW-LEVEL WRITE (SAFE)
  /// -----------------------------
  Future<void> _write(String text) async {
    final port = _port;
    if (port == null) return;

    final writer = port.writable?.getWriter();
    if (writer == null) return;

    final data = Uint8List.fromList(text.codeUnits);

    await writer.write(data.toJS).toDart;
    await writer.close().toDart; // force flush
    writer.releaseLock();
  }

  /// -----------------------------
  /// APPLY SETTINGS (ROBUST)
  /// -----------------------------
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

    try {
      // 1️⃣ Clear / wake up device (ENTER)
      await _write('\r\n');
      await Future.delayed(const Duration(milliseconds: 150));

      // 2️⃣ Set Group ID
      await _write('rftag settings groupid set $groupId\r\n');
      await Future.delayed(const Duration(milliseconds: 150));

      // 3️⃣ Set Frequency
      await _write('rftag settings lora freq $selectedFrequency\r\n');

      setState(() {
        status = 'Settings sent successfully';
      });
    } catch (e) {
      setState(() {
        status = 'Failed to send commands';
      });
    }
  }

  /// -----------------------------
  /// UI
  /// -----------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RFTag Config'),
        actions: [
          IconButton(
            icon: const Icon(Icons.usb),
            tooltip: 'Connect device',
            onPressed: connectPort,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: $status'),

            const SizedBox(height: 16),
            TextField(
              controller: groupIdController,
              decoration: const InputDecoration(
                labelText: 'Group ID',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedFrequency,
              items: frequencies
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) => setState(() => selectedFrequency = v!),
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: applySettings,
              child: const Text('Apply Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
