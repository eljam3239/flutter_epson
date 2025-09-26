import 'package:flutter/material.dart';
import 'package:epson_printer/epson_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  List<String> _discoveredPrinters = [];
  bool _isConnected = false;
  String _printerStatus = 'Unknown';
  String? _selectedPrinter; // Add selected printer tracking
  bool _openDrawerAfterPrint = true; // Option to auto-open drawer after printing

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    // Only check Bluetooth permissions on Android - iOS handles this differently
    if (Platform.isAndroid) {
      // Check if we need to request Bluetooth permissions
      final bluetoothStatus = await Permission.bluetoothConnect.status;
      final bluetoothScanStatus = await Permission.bluetoothScan.status;
      
      if (!bluetoothStatus.isGranted || !bluetoothScanStatus.isGranted) {
        print('DEBUG: Bluetooth permissions not granted, requesting...');
        
        // Request permissions
        final results = await [
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          Permission.location, // Also needed for Bluetooth discovery on some devices
        ].request();
        
        results.forEach((permission, status) {
          print('DEBUG: Permission $permission: $status');
        });
        
        if (results[Permission.bluetoothConnect]?.isGranted == true) {
          print('DEBUG: Bluetooth permissions granted');
        } else {
          print('DEBUG: Bluetooth permissions still denied');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth permissions are required for printer discovery. Please enable them in settings.'),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        print('DEBUG: Bluetooth permissions already granted');
      }
    } else {
      // iOS - Bluetooth permissions are handled automatically by the system
      print('DEBUG: Running on iOS - Bluetooth permissions handled by system');
    }
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future<void> _discoverPrinters() async {
    try {
      print('DEBUG: Starting printer discovery...');
      print('DEBUG: Looking for printers on network.');
      // Check permissions first - only on Android
      if (Platform.isAndroid) {
        final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
        final bluetoothScanStatus = await Permission.bluetoothScan.status;
        
        if (!bluetoothConnectStatus.isGranted || !bluetoothScanStatus.isGranted) {
          print('DEBUG: Bluetooth permissions not granted, requesting again...');
          await _checkAndRequestPermissions();
          
          // Check again after request
          final newBluetoothConnectStatus = await Permission.bluetoothConnect.status;
          if (!newBluetoothConnectStatus.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Bluetooth permissions required. Please enable in Android Settings > Apps > test_star > Permissions'),
                  action: SnackBarAction(
                    label: 'Open Settings',
                    onPressed: () => openAppSettings(),
                  ),
                  duration: const Duration(seconds: 8),
                ),
              );
            }
            return;
          }
        }
      }
      final printers = await EpsonPrinter.discoverPrinters();
      print('DEBUG: Discovery result: $printers');
      setState(() {
        _discoveredPrinters = printers;
        // Auto-select first printer if none selected or if current selection is no longer available
        if (_selectedPrinter == null || !printers.contains(_selectedPrinter)) {
          _selectedPrinter = printers.isNotEmpty ? printers.first : null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} printers')),
      );
    } catch (e) {
      print('DEBUG: Discovery error: $e');
      String message = 'Discovery failed: $e';
      
      if (e.toString().contains('BLUETOOTH_PERMISSION_DENIED')) {
        message = 'Bluetooth permissions required. Please grant permissions and try again.';
      } else if (e.toString().contains('BLUETOOTH_UNAVAILABLE')) {
        message = 'Bluetooth is not available or disabled. Please enable Bluetooth.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _connectToPrinter() async {
    if (_discoveredPrinters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No printers discovered. Please discover printers first.')),
      );
      return;
    }

    if (_selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a printer first.')),
      );
      return;
    }

    try {
      if (_isConnected) {
        await EpsonPrinter.disconnect();
        setState(() { _isConnected = false; });
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final printerString = _selectedPrinter!;
      final lastColonIndex = printerString.lastIndexOf(':');
      String target = lastColonIndex != -1 ? printerString.substring(0, lastColonIndex) : printerString;

      // Determine interface type, fixing bare MAC handling
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
        // Bare MAC -> Classic BT
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
      setState(() { _isConnected = true; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to: ${_selectedPrinter!.split(':').last}')),
      );
    } catch (e) {
      setState(() { _isConnected = false; });
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
        // Add paired target to list and select it
        setState(() {
          final entry = '$target:PairedPrinter';
          if (!_discoveredPrinters.contains(entry)) {
            _discoveredPrinters.add(entry);
          }
          _selectedPrinter = entry;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paired: $target (code=$code)')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed (code=$code)')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pairing error: $e')),
      );
    }
  }

  Future<void> _printReceipt() async {
    print('DEBUG: Print receipt button pressed');
    
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }
    
    try {
      print('DEBUG: Creating Epson print job...');
      
      final printJob = EpsonPrintJob(
        commands: [
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': 'EPSON PRINTER TEST\n'},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': '================\n'},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.feed,
            parameters: {'line': 1},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': 'Counter: $_counter\n'},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': 'Test Print Success!\n'},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.feed,
            parameters: {'line': 2},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': 'Thank you!\n'},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': '''⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
            ⢀⣀⣀⣤⣤⣄⣄⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡴⠊⠉⠉⠉⠉⠉⣩⡷⠋⠉⠹⡛⢽⠢⣀⣀⡀⠀
⢀⣀⣤⣴⠶⣾⣿⡿⠯⠯⣍⣙⣒⣲⠶⠶⠶⡿⢴⠧⠷⠒⣿⣏⠡⡤⠤⠯⡆
⣿⣶⣒⡒⠛⠽⢯⣥⣶⣯⠭⡵⢊⣩⣭⣲⡂⡗⠈⠉⠉⠉⠉⡇⣼⣷⣿⣧⡇
⣮⣍⣛⡛⠛⠛⠛⠛⠛⠘⡾⣴⣿⣿⣿⣿⣧⡇⠀⠀⠀⢀⣰⣠⡽⣿⣿⠟⠀
⠾⠿⣶⣦⣭⣍⣹⣷⡄⡸⣹⣿⡿⣿⣻⣿⡿⠷⠶⠟⠛⠛⠉⠉⠓⠻⠟⠀⠀
⠀⠀⠀⠉⠉⠁⠉⠛⠛⠛⠳⠿⢿⡿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\n'''},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.feed,
            parameters: {'line': 1},
          ),
          EpsonPrintCommand(
            type: EpsonCommandType.cut,
            parameters: {},
          ),
        ],
      );
      
      print('DEBUG: Sending print job to Epson printer...');
      await EpsonPrinter.printReceipt(printJob);
      
      print('DEBUG: Print job completed successfully');
      
      // Optionally open cash drawer after successful print
      if (_openDrawerAfterPrint && _isConnected) {
        try {
          print('DEBUG: Auto-opening cash drawer after print...');
          await EpsonPrinter.openCashDrawer();
          print('DEBUG: Auto cash drawer opened successfully');
        } catch (drawerError) {
          print('DEBUG: Auto cash drawer failed: $drawerError');
          // Don't fail the whole operation if drawer fails
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_openDrawerAfterPrint 
            ? 'Print job sent and drawer opened' 
            : 'Print job sent successfully')),
      );
    } catch (e) {
      print('DEBUG: Print failed with error: $e');
      print('DEBUG: Error type: ${e.runtimeType}');
      print('DEBUG: Error details: ${e.toString()}');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _disconnectFromPrinter() async {
    try {
      await EpsonPrinter.disconnect();
      setState(() {
        _isConnected = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from printer')),
      );
    } catch (e) {
      print('DEBUG: Disconnect error: $e');
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      print('DEBUG: Opening cash drawer...');
      await EpsonPrinter.openCashDrawer();
      print('DEBUG: Cash drawer command sent successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash drawer opened')),
      );
    } catch (e) {
      print('DEBUG: Cash drawer error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cash drawer failed: $e')),
      );
    }
  }

  Future<void> _discoverBluetoothPrinters() async {
    try {
      print('DEBUG: Starting Bluetooth printer discovery...');
      print('DEBUG: Looking for Bluetooth printers.');
      
      // Check permissions first - only on Android
      if (Platform.isAndroid) {
        final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
        final bluetoothScanStatus = await Permission.bluetoothScan.status;
        
        if (!bluetoothConnectStatus.isGranted || !bluetoothScanStatus.isGranted) {
          print('DEBUG: Bluetooth permissions not granted, requesting again...');
          await _checkAndRequestPermissions();
          
          // Check again after request
          final newBluetoothConnectStatus = await Permission.bluetoothConnect.status;
          if (!newBluetoothConnectStatus.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Bluetooth permissions required for Bluetooth discovery'),
                  action: SnackBarAction(
                    label: 'Open Settings',
                    onPressed: () => openAppSettings(),
                  ),
                  duration: const Duration(seconds: 8),
                ),
              );
            }
            return;
          }
        }
      }
      
      final printers = await EpsonPrinter.discoverBluetoothPrinters();
      print('DEBUG: Bluetooth discovery result: $printers');
      
      setState(() {
        // Add Bluetooth printers to the existing list (or replace if you prefer)
        final bluetoothPrinters = printers.where((p) => p.startsWith('BT:') || p.startsWith('BLE:')).toList();
        
        // Create a new mutable list from existing printers, removing Bluetooth ones
        final updatedPrinters = List<String>.from(_discoveredPrinters);
        updatedPrinters.removeWhere((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
        updatedPrinters.addAll(bluetoothPrinters);
        
        _discoveredPrinters = updatedPrinters;
        
        // Auto-select first Bluetooth printer if none selected
        if (_selectedPrinter == null || !_discoveredPrinters.contains(_selectedPrinter)) {
          _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} Bluetooth printers')),
      );
    } catch (e) {
      print('DEBUG: Bluetooth discovery error: $e');
      String message = 'Bluetooth discovery failed: $e';
      
      if (e.toString().contains('BLUETOOTH_PERMISSION_DENIED')) {
        message = 'Bluetooth permissions required. Please grant permissions and try again.';
      } else if (e.toString().contains('BLUETOOTH_UNAVAILABLE')) {
        message = 'Bluetooth is not available or disabled. Please enable Bluetooth.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _testDirectBluetoothConnection() async {
    try {
      print('DEBUG: Looking for already paired Bluetooth printer TM-m30III_004541...');
      
      // Disconnect from current printer if connected
      if (_isConnected) {
        print('DEBUG: Disconnecting from current printer before new connection...');
        await EpsonPrinter.disconnect();
        setState(() {
          _isConnected = false;
        });
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // First, try to find already paired Bluetooth devices (this runs on background thread)
      print('DEBUG: Searching for paired Bluetooth printers...');
      
      final pairedPrinters = await EpsonPrinter.findPairedBluetoothPrinters();
      
      print('DEBUG: Found ${pairedPrinters.length} paired Bluetooth printers: $pairedPrinters');
      
      // Look for our specific printer
      String? targetPrinter;
      for (final printer in pairedPrinters) {
        print('DEBUG: Checking paired printer: $printer');
        if (printer.contains('TM-m30III') || printer.contains('004541')) {
          targetPrinter = printer;
          print('DEBUG: Found target printer: $targetPrinter');
          break;
        }
      }
      
      if (targetPrinter == null) {
        // If not found in paired devices, try manual connection with BD address format
        print('DEBUG: Printer not found in paired devices, trying direct BD/BLE connection...');
        
        // Try known identifiers in order: BLE by name (iOS-friendly), then BD address variants
        final possibleIdentifiers = [
          'BLE:TM-m30III_004541',      // BLE by advertised device name (iOS typically requires name for BLE)
          'TM-m30III_004541',          // Name without prefix (we'll try as BLE below)
          'A6:D7:3C:AA:CA:01',         // BD address from self-print (Classic BT)
          'BT:A6:D7:3C:AA:CA:01',      // Classic BT with prefix
          'BLE:A6:D7:3C:AA:CA:01',     // BLE with BD (may fail on iOS)
        ];
        
        bool connected = false;
        
        for (final identifier in possibleIdentifiers) {
          try {
            print('DEBUG: Trying connection with identifier: $identifier');
            
            EpsonPortType portType;
            String cleanIdentifier;
            
            if (identifier.startsWith('BT:')) {
              portType = EpsonPortType.bluetooth;
              cleanIdentifier = identifier.substring(3);
            } else if (identifier.startsWith('BLE:')) {
              portType = EpsonPortType.bluetoothLe;
              cleanIdentifier = identifier.substring(4);
            } else {
              // If no prefix provided, try BLE by name first
              portType = EpsonPortType.bluetoothLe;
              cleanIdentifier = identifier;
            }
            
            final settings = EpsonConnectionSettings(
              portType: portType,
              identifier: cleanIdentifier,
              timeout: 15000,
            );
            
            print('DEBUG: Connection settings - Port: $portType, Target: ${settings.targetString}');
            
            await EpsonPrinter.connect(settings);
            connected = true;
            
            setState(() {
              _isConnected = true;
              // Add to discovered printers list
              final directPrinter = '${settings.targetString}:TM-m30III_004541';
              if (!_discoveredPrinters.contains(directPrinter)) {
                _discoveredPrinters.add(directPrinter);
                _selectedPrinter = directPrinter;
              }
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Direct connection successful: ${settings.targetString}')),
            );
            
            return;
            
          } catch (e) {
            print('DEBUG: Connection failed with $identifier: $e');
            continue;
          }
        }
        
        if (!connected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not find or connect. Ensure printer is paired/on and BLE mode if using BLE.')),
          );
        }
        
      } else {
        // Found in paired devices, try to connect
        print('DEBUG: Attempting to connect to paired printer: $targetPrinter');
        
        // Parse the target from the paired printer string
        final lastColonIndex = targetPrinter.lastIndexOf(':');
        String target;
        if (lastColonIndex != -1) {
          target = targetPrinter.substring(0, lastColonIndex);
        } else {
          target = targetPrinter;
        }
        
        // Determine port type
        EpsonPortType portType;
        if (target.startsWith('BT:')) {
          portType = EpsonPortType.bluetooth;
        } else if (target.startsWith('BLE:')) {
          portType = EpsonPortType.bluetoothLe;
        } else {
          portType = EpsonPortType.bluetoothLe; // Default to BLE
        }
        
        try {
          final settings = EpsonConnectionSettings(
            portType: portType,
            identifier: target,
            timeout: 15000,
          );
          
          await EpsonPrinter.connect(settings);
          
          setState(() {
            _isConnected = true;
            if (!_discoveredPrinters.contains(targetPrinter!)) {
              _discoveredPrinters.add(targetPrinter);
              _selectedPrinter = targetPrinter;
            }
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully connected to paired printer: ${targetPrinter.split(':').last}')),
          );
          
        } catch (e) {
          print('DEBUG: Connection to paired printer failed: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection to paired printer failed: $e')),
          );
        }
      }
      
    } catch (e) {
      print('DEBUG: Paired Bluetooth search error: $e');
      setState(() {
        _isConnected = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paired Bluetooth search failed: $e')),
      );
    }
  }

  Future<void> _discoverUsbPrinters() async {
    try {
      final printers = await EpsonPrinter.discoverUsbPrinters();
      print('DEBUG: USB discovery result: $printers');
      setState(() {
        // Remove existing USB entries then add new ones
        final updated = List<String>.from(_discoveredPrinters);
        updated.removeWhere((p) => p.startsWith('USB:'));
        updated.addAll(printers.where((p) => p.startsWith('USB:')));
        _discoveredPrinters = updated;
        if (_selectedPrinter == null && _discoveredPrinters.isNotEmpty) {
          _selectedPrinter = _discoveredPrinters.first;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} USB printers')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB discovery failed: $e')),
      );
    }
  }

  // Future<void> _testDirectConnection() async {
  //   try {
  //     print('DEBUG: Testing direct connection to TSP100 at 10.20.30.125...');
      
  //     // Disconnect from current printer if connected
  //     if (_isConnected) {
  //       await StarPrinter.disconnect();
  //       setState(() {
  //         _isConnected = false;
  //       });
  //       await Future.delayed(const Duration(milliseconds: 500));
  //     }
      
  //     final settings = StarConnectionSettings(
  //       interfaceType: StarInterfaceType.lan,
  //       identifier: '10.20.30.125',
  //     );
      
  //     await StarPrinter.connect(settings);
  //     setState(() {
  //       _isConnected = true;
  //       // Add to discovered printers list if not already there
  //       final directPrinter = 'LAN:10.20.30.125:TSP100';
  //       if (!_discoveredPrinters.contains(directPrinter)) {
  //         _discoveredPrinters.add(directPrinter);
  //         _selectedPrinter = directPrinter;
  //       }
  //     });
      
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text('Direct connection to TSP100 successful!')),
  //     );
  //   } catch (e) {
  //     print('DEBUG: Direct connection failed: $e');
  //     setState(() {
  //       _isConnected = false;
  //     });
      
  //     String message = 'Direct connection failed: $e';
  //     if (e.toString().contains('network') || e.toString().contains('timeout')) {
  //       message = 'Network error: Cannot reach TSP100 at 10.20.30.125. Check if tablet and printer are on same network.';
  //     }
      
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text(message)),
  //     );
  //   }
  // }

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
                  children: [
                    Text(
                      'Counter Demo',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('You have pushed the button this many times:'),
                    Text(
                      '$_counter',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _incrementCounter,
                      child: const Text('Increment Counter'),
                    ),
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
                  children: [
                    Text(
                      'Epson Printer Controls',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
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
                              // Extract model name for display
                              final parts = printer.split(':');
                              final model = parts.length > 2 ? parts[2] : 'Unknown';
                              final mac = parts.length > 1 ? parts[1] : 'Unknown';
                              // Safely truncate MAC address to avoid range errors
                              final displayMac = mac.length > 8 ? '${mac.substring(0, 8)}...' : mac;
                              return DropdownMenuItem<String>(
                                value: printer,
                                child: Text('$model ($displayMac)'),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedPrinter = newValue;
                                _isConnected = false; // Reset connection status when changing printer
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedPrinter != null)
                        Text('Selected: ${_selectedPrinter!}', 
                             style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
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
                        const Expanded(
                          child: Text('Auto-open cash drawer after printing'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: _checkAndRequestPermissions,
                          child: const Text('Check Permissions'),
                        ),
                        ElevatedButton(
                          onPressed: _discoverPrinters,
                          child: const Text('Discover LAN'),
                        ),
                        ElevatedButton(
                          onPressed: _discoverBluetoothPrinters,
                          child: const Text('Discover Bluetooth'),
                        ),
                        ElevatedButton(
                          onPressed: _discoverUsbPrinters,
                          child: const Text('Discover USB'),
                        ),
                        ElevatedButton(
                          onPressed: _pairBluetooth,
                          child: const Text('Pair Bluetooth'),
                        ),
                        ElevatedButton(
                          onPressed: _testDirectBluetoothConnection,
                          child: const Text('Find Paired BT'),
                        ),
                        ElevatedButton(
                          onPressed: _selectedPrinter != null && !_isConnected
                              ? _connectToPrinter
                              : null,
                          child: const Text('Connect'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _disconnectFromPrinter : null,
                          child: const Text('Disconnect'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _printReceipt : null,
                          child: const Text('Print Test Receipt'),
                        ),
                        ElevatedButton(
                          onPressed: _getStatus,
                          child: const Text('Get Status'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _openCashDrawer : null,
                          child: const Text('Open Cash Drawer'),
                        ),
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
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
