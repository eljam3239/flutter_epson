import 'package:flutter/material.dart';
import 'package:epson_printer/epson_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  List<String> _discoveredPrinters = [];
  bool _isConnected = false;
  String _printerStatus = 'Unknown';
  String? _selectedPrinter;
  bool _openDrawerAfterPrint = true;

  @override
  void initState() {
    super.initState();
    // Defer Bluetooth permission requests to Bluetooth actions.
  }

  Future<void> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final bluetoothStatus = await Permission.bluetoothConnect.status;
      final bluetoothScanStatus = await Permission.bluetoothScan.status;

      if (!bluetoothStatus.isGranted || !bluetoothScanStatus.isGranted) {
        final results = await [
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          Permission.location,
        ].request();

        if (results[Permission.bluetoothConnect]?.isGranted != true ||
            results[Permission.bluetoothScan]?.isGranted != true) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth permissions are required for printer discovery. Please enable them in settings.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future<void> _discoverPrinters() async {
    try {
      final printers = await EpsonPrinter.discoverPrinters();
      setState(() {
        _discoveredPrinters = printers;
        if (_selectedPrinter == null || !printers.contains(_selectedPrinter)) {
          _selectedPrinter = printers.isNotEmpty ? printers.first : null;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} printers')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Discovery failed: $e')),
      );
    }
  }

  Future<void> _connectToPrinter() async {
    if (_discoveredPrinters.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No printers discovered. Please discover printers first.')),
      );
      return;
    }
    if (_selectedPrinter == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a printer first.')),
      );
      return;
    }

    try {
      if (_isConnected) {
        await EpsonPrinter.disconnect();
        setState(() => _isConnected = false);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final printerString = _selectedPrinter!;
      final lastColonIndex = printerString.lastIndexOf(':');
      String target = lastColonIndex != -1
          ? printerString.substring(0, lastColonIndex)
          : printerString;

      EpsonPortType interfaceType;
      final macRegex = RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$');
      if (target.startsWith('TCP:') || target.startsWith('TCPS:')) {
        interfaceType = EpsonPortType.tcp;
      } else if (target.startsWith('BT:')) {
        interfaceType = EpsonPortType.bluetooth;
      } else if (target.startsWith('BLE:')) {
        interfaceType = EpsonPortType.bluetoothLe;
      } else if (target.startsWith('USB:')) {
        interfaceType = EpsonPortType.usb;
      } else if (macRegex.hasMatch(target)) {
        interfaceType = EpsonPortType.bluetooth;
        target = 'BT:$target';
      } else {
        interfaceType = EpsonPortType.tcp;
      }

      final settings = EpsonConnectionSettings(
        portType: interfaceType,
        identifier: target,
        timeout: interfaceType == EpsonPortType.bluetoothLe ? 30000 : 15000,
      );

      await EpsonPrinter.connect(settings);
      setState(() => _isConnected = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to: ${_selectedPrinter!.split(':').last}')),
      );
    } catch (e) {
      setState(() => _isConnected = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  Future<void> _pairBluetooth() async {
    try {
      final res = await EpsonPrinter.pairBluetoothDevice();
      final target = res['target'] as String?;
      final code = res['resultCode'];
      if (target != null && target.isNotEmpty) {
        setState(() {
          final entry = '$target:PairedPrinter';
          if (!_discoveredPrinters.contains(entry)) {
            _discoveredPrinters.add(entry);
          }
          _selectedPrinter = entry;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paired: $target (code=$code)')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed (code=$code)')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pairing error: $e')),
      );
    }
  }

  Future<void> _printReceipt() async {
    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      final printJob = EpsonPrintJob(
        commands: [
          EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'EPSON PRINTER TEST\n'}),
          EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': '================\n'}),
          EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 1}),
          EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'Counter: $_counter\n'}),
          EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'Test Print Success!\n'}),
          EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 2}),
          EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'Thank you!\n'}),
          EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 1}),
          EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}),
        ],
      );

      await EpsonPrinter.printReceipt(printJob);

      if (_openDrawerAfterPrint && _isConnected) {
        try {
          await EpsonPrinter.openCashDrawer();
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_openDrawerAfterPrint ? 'Print job sent and drawer opened' : 'Print job sent successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _disconnectFromPrinter() async {
    try {
      await EpsonPrinter.disconnect();
      setState(() => _isConnected = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from printer')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnect failed: $e')),
      );
    }
  }

  Future<void> _getStatus() async {
    try {
      final status = await EpsonPrinter.getStatus();
      setState(() {
        _printerStatus = 'Online: ${status.isOnline}, Status: ${status.status}';
      });
    } catch (e) {
      setState(() {
        _printerStatus = 'Error: $e';
      });
    }
  }

  Future<void> _openCashDrawer() async {
    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }
    try {
      await EpsonPrinter.openCashDrawer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash drawer opened')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cash drawer failed: $e')),
      );
    }
  }

  Future<void> _discoverBluetoothPrinters() async {
    try {
      if (Platform.isAndroid) {
        final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
        final bluetoothScanStatus = await Permission.bluetoothScan.status;
        if (!bluetoothConnectStatus.isGranted || !bluetoothScanStatus.isGranted) {
          await _checkAndRequestPermissions();
          final newConnect = await Permission.bluetoothConnect.status;
          final newScan = await Permission.bluetoothScan.status;
          if (!newConnect.isGranted || !newScan.isGranted) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Bluetooth permissions required for Bluetooth discovery'),
                action: SnackBarAction(label: 'Open Settings', onPressed: () => openAppSettings()),
                duration: const Duration(seconds: 8),
              ),
            );
            return;
          }
        }
      }

      final printers = await EpsonPrinter.discoverBluetoothPrinters();
      setState(() {
        final bluetoothPrinters = printers.where((p) => p.startsWith('BT:') || p.startsWith('BLE:')).toList();
        final updatedPrinters = List<String>.from(_discoveredPrinters);
        updatedPrinters.removeWhere((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
        updatedPrinters.addAll(bluetoothPrinters);
        _discoveredPrinters = updatedPrinters;
        if (_selectedPrinter == null || !_discoveredPrinters.contains(_selectedPrinter)) {
          _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} Bluetooth printers')),
      );
    } catch (e) {
      var message = 'Bluetooth discovery failed: $e';
      if (e.toString().contains('BLUETOOTH_PERMISSION_DENIED')) {
        message = 'Bluetooth permissions required. Please grant permissions and try again.';
      } else if (e.toString().contains('BLUETOOTH_UNAVAILABLE')) {
        message = 'Bluetooth is not available or disabled. Please enable Bluetooth.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _discoverUsbPrinters() async {
    try {
      final printers = await EpsonPrinter.discoverUsbPrinters();
      setState(() {
        final updated = List<String>.from(_discoveredPrinters);
        updated.removeWhere((p) => p.startsWith('USB:'));
        updated.addAll(printers.where((p) => p.startsWith('USB:')));
        _discoveredPrinters = updated;
        if (_selectedPrinter == null && _discoveredPrinters.isNotEmpty) {
          _selectedPrinter = _discoveredPrinters.first;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} USB printers')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB discovery failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Counter Demo', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text('You have pushed the button this many times:'),
                    Text('$_counter', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _incrementCounter, child: const Text('Increment Counter')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Epson Printer Controls', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    Text('Discovered Printers: ${_discoveredPrinters.length}'),
                    if (_discoveredPrinters.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Select Printer:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPrinter,
                            hint: const Text('Select a printer'),
                            isExpanded: true,
                            items: _discoveredPrinters.map((printer) {
                              final parts = printer.split(':');
                              final model = parts.length > 2 ? parts[2] : 'Unknown';
                              final mac = parts.length > 1 ? parts[1] : 'Unknown';
                              final displayMac = mac.length > 8 ? '${mac.substring(0, 8)}...' : mac;
                              return DropdownMenuItem<String>(
                                value: printer,
                                child: Text('$model ($displayMac)'),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedPrinter = newValue;
                                _isConnected = false;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedPrinter != null)
                        Text('Selected: ${_selectedPrinter!}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 16),
                    Text('Connection Status: ${_isConnected ? "Connected" : "Disconnected"}'),
                    const SizedBox(height: 8),
                    Text('Printer Status: $_printerStatus'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _openDrawerAfterPrint,
                          onChanged: (bool? value) {
                            setState(() {
                              _openDrawerAfterPrint = value ?? true;
                            });
                          },
                        ),
                        const Expanded(child: Text('Auto-open cash drawer after printing')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ElevatedButton(onPressed: _checkAndRequestPermissions, child: const Text('Check Permissions')),
                        ElevatedButton(onPressed: _discoverPrinters, child: const Text('Discover LAN')),
                        ElevatedButton(onPressed: _discoverBluetoothPrinters, child: const Text('Discover Bluetooth')),
                        ElevatedButton(onPressed: _discoverUsbPrinters, child: const Text('Discover USB')),
                        ElevatedButton(onPressed: _pairBluetooth, child: const Text('Pair Bluetooth')),
                        ElevatedButton(onPressed: _selectedPrinter != null && !_isConnected ? _connectToPrinter : null, child: const Text('Connect')),
                        ElevatedButton(onPressed: _isConnected ? _disconnectFromPrinter : null, child: const Text('Disconnect')),
                        ElevatedButton(onPressed: _isConnected ? _printReceipt : null, child: const Text('Print Test Receipt')),
                        ElevatedButton(onPressed: _getStatus, child: const Text('Get Status')),
                        ElevatedButton(onPressed: _isConnected ? _openCashDrawer : null, child: const Text('Open Cash Drawer')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
