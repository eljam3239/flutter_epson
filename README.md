# Flutter Epson

Flutter wrapper for Epson's iOS and Android SDKs.

See lib/main.dart for a mock POS label and receipt templating app for example use of discovery, connection and print command use.

You'll need Flutter and its dependencies installed [here](https://docs.flutter.dev/get-started/quick) to run this code in an emulator or physical device. 
If you run:
```zsh
$ flutter doctor
```
without errors, you're good to proceed to [Setup](#setup).
## Setup
iOS:
1. Agree to the software license and download the Epson ePOS SDK for iOS from https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II
2. Add the libepos2.xcframework and libeposeasyselect.xcframework folders to packages/epson_printer_ios/ios/Frameworks

Android:
1. Agree to the software license and download the Epson ePOS SDK for Android from https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II
2.  Add ePOS2.jar and ePOSEasySelect.jar to packages/epson_printer_android/android/libs.
3.  Add the arm64-v8a, armeabi-v7a, x86 and x86_64 folders and their contents to packages/epson_printer_android/android/src/main/jniLibs.


### Tested:

| Device      | TM-m30III | Cash Drawer |
|-------------|--------|--------|
| iOS         |   LAN, Bluetooth (pre-connected, in-app pairing), usb     | yes |
| Android     |  LAN, Bluetooth (pre-connected), usb   | yes |

### A Note on Paper Width:
Only 58mm and 80mm paper has been tested. Paper width autodetection upon connecting to a printer works for those 2 widths. Label and receipt printing to those widths works too. Do not ship support for other widths using this SDK unless you've tested those widths for printing/autodection. 

### Swapping between Bluetooth and USB on iOS vs Android:
On iOS, the plugging in of a usb cable prohibits any future discovery or connection to that same printer via Bluetooth.
On Android, the device and the printer cannot form a Bluetooth connection after a usb cable connection has been made, but if the cable is removed and Discover Printers is called again, then the tablet can connect with that printer over Bluetooth again.

The Discover Printers button mirrors the functionality of the Epson TM app's printer discover based on which platform the app is run from.
