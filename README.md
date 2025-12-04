# Flutter Epson Printer SDK Demo

A comprehensive Flutter application demonstrating thermal receipt and label printing using the Epson ePOS2 SDK. This app showcases cross-platform (iOS/Android) printer discovery, connection management, and advanced printing features.

## Features

- **Cross-platform printer discovery** (TCP, USB, Bluetooth/BLE)
- **Automatic paper width detection** with manual override
- **Receipt printing** with dynamic formatting based on paper width
- **Label printing** with barcode generation and text styling
- **Multi-label printing** with quantity control
- **Logo/image printing** support
- **Cash drawer integration**

## Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- iOS development: Xcode 14+
- Android development: Android Studio with SDK 21+
- Physical Epson thermal printer (TM series recommended)

You'll need Flutter and its dependencies installed [here](https://docs.flutter.dev/get-started/quick) to run this code in an emulator or physical device. 
If you run:
```zsh
$ flutter doctor
```
without errors, you're good to proceed to [Setup](#setup).

### Setup



### Installation

1. Clone the repository
```bash
git clone git@github.com:eljam3239/flutter_epson.git
cd test_epson
```
##
#### iOS:
1. Agree to the software license and download the Epson ePOS SDK for iOS from https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II
2. Add the libepos2.xcframework and libeposeasyselect.xcframework folders to packages/epson_printer_ios/ios/Frameworks

#### Android:
1. Agree to the software license and download the Epson ePOS SDK for Android from https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II
2. Add ePOS2.jar and ePOSEasySelect.jar to packages/epson_printer_android/android/libs.
3. Add the arm64-v8a, armeabi-v7a, x86 and x86_64 folders and their contents to packages/epson_printer_android/android/src/main/jniLibs.
##

2. Install dependencies
```bash
flutter pub get
```

3. Run the application
```bash
flutter run
```

## Epson SDK Integration

### Core Models

#### EpsonPrintCommand
The fundamental building block for creating print jobs:

```dart
EpsonPrintCommand(
  type: EpsonCommandType.text,
  parameters: {
    'data': 'Hello World\n',
    'align': 'center'  // Optional alignment
  }
)
```

#### Command Types
- `EpsonCommandType.text` - Print text
- `EpsonCommandType.barcode` - Print barcodes
- `EpsonCommandType.feed` - Line feeds
- `EpsonCommandType.cut` - Cut paper
- `EpsonCommandType.image` - Print images
- `EpsonCommandType.textStyle` - Text formatting

#### EpsonPrintJob
Container for multiple commands:

```dart
final printJob = EpsonPrintJob(commands: [
  EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'Receipt\n'}),
  EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}),
]);
```

### Basic Printing Workflow

#### 1. Printer Discovery
```dart
Future<void> _discoverPrinters() async {
  try {
    final printers = await EpsonPrinter.discoverPrinters(); // TCP/LAN
    // or
    final btPrinters = await EpsonPrinter.discoverBluetoothPrinters();
    final usbPrinters = await EpsonPrinter.discoverUsbPrinters();
  } catch (e) {
    print('Discovery failed: $e');
  }
}
```

#### 2. Connection
```dart
Future<void> _connect(String printerTarget) async {
  final settings = EpsonConnectionSettings(
    portType: EpsonPortType.tcp, // or .bluetooth, .usb, .bluetoothLe
    identifier: printerTarget,
    timeout: 15000,
  );
  
  await EpsonPrinter.connect(settings);
}
```

#### 3. Print Job Creation
```dart
List<EpsonPrintCommand> _buildReceiptCommands() {
  return [
    // Header
    EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'align': 'center'}
    ),
    EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': 'RECEIPT\n'}
    ),
    
    // Content
    EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'align': 'left'}
    ),
    EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': 'Item: Coffee\nPrice: \$3.50\n'}
    ),
    
    // Cut
    EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}),
  ];
}
```

#### 4. Execute Print Job
```dart
Future<void> _printReceipt() async {
  final commands = _buildReceiptCommands();
  final printJob = EpsonPrintJob(commands: commands);
  await EpsonPrinter.printReceipt(printJob);
}
```

### Advanced Features

#### Paper Width Detection
```dart
try {
  String detectedWidth = await EpsonPrinter.detectPaperWidth();
  // Returns: '58mm', '60mm', '70mm', '76mm', or '80mm'
} catch (e) {
  // Fallback to manual selection
}
```

#### Text Styling
```dart
EpsonPrintCommand(
  type: EpsonCommandType.textStyle,
  parameters: {
    'bold': 'true',
    'underline': 'false',
    'reverse': 'false',
    'color': '1'
  }
)
```

#### Barcode Printing
```dart
EpsonPrintCommand(
  type: EpsonCommandType.barcode,
  parameters: {
    'data': '123456789',
    'type': 'CODE128_AUTO',
    'hri': 'below',     // Human readable interpretation
    'width': 2,         // Module width
    'height': 35,       // Height in dots
    'font': 'A'         // Font for HRI
  }
)
```

#### Dynamic Text Alignment
```dart
// Center alignment
EpsonPrintCommand(
  type: EpsonCommandType.text,
  parameters: {'align': 'center'}
)

// Reset to left
EpsonPrintCommand(
  type: EpsonCommandType.text,
  parameters: {'align': 'left'}
)
```

### Text Formatting Utilities

#### Character Width Calculation
```dart
int getCharacterWidth(String paperWidth) {
  switch (paperWidth) {
    case '58mm': return 35;
    case '60mm': return 34;
    case '70mm': return 42;
    case '76mm': return 45;
    case '80mm': return 48;
    default: return 48;
  }
}
```

#### Text Wrapping
```dart
List<String> wrapText(String text, int maxWidth) {
  final words = text.split(' ');
  final List<String> lines = [];
  String currentLine = '';
  
  for (String word in words) {
    final testLine = currentLine.isEmpty ? word : '$currentLine $word';
    if (testLine.length <= maxWidth) {
      currentLine = testLine;
    } else {
      if (currentLine.isNotEmpty) {
        lines.add(currentLine);
        currentLine = word;
      } else {
        lines.add(word);
      }
    }
  }
  
  if (currentLine.isNotEmpty) {
    lines.add(currentLine);
  }
  
  return lines;
}
```

## Platform-Specific Considerations

### iOS
- USB connections disable Bluetooth hardware on printer
- Requires NSBluetoothAlwaysUsageDescription in Info.plist
- Background app refresh affects discovery state

### Android
- Requires Bluetooth permissions (BLUETOOTH_CONNECT, BLUETOOTH_SCAN)
- Location permission needed for Bluetooth discovery
- Handle permission requests gracefully

### Permission Handling
```dart
Future<void> _checkPermissions() async {
  if (Platform.isAndroid) {
    final status = await Permission.bluetoothConnect.status;
    if (!status.isGranted) {
      await Permission.bluetoothConnect.request();
    }
  }
}
```

## Tested Hardware & Compatibility

| Device      | TM-m30III | Cash Drawer |
|-------------|-----------|-------------|
| iOS         | LAN, Bluetooth (pre-connected, in-app pairing), USB | Yes |
| Android     | LAN, Bluetooth (pre-connected), USB | Yes |

### Paper Width Support:
Only 58mm and 80mm paper has been tested. Paper width autodetection upon connecting to a printer works for those 2 widths. Label and receipt printing to those widths works too. Do not ship support for other widths using this SDK unless you've tested those widths for printing/autodetection.

### Bluetooth vs USB Behavior:
- **iOS**: Plugging in a USB cable prohibits any future discovery or connection to that same printer via Bluetooth.
- **Android**: The device and printer cannot form a Bluetooth connection after a USB cable connection has been made, but if the cable is removed and "Discover Printers" is called again, the tablet can connect with that printer over Bluetooth again.

The "Discover Printers" button mirrors the functionality of the Epson TM app's printer discovery based on which platform the app is run from.