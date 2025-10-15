# test_epson

Flutter wrapper for Epson's iOS and Android SDKs.

## Setup

iOS:
1. Agree to the software license and download the Epson ePOS SDK for iOS from https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II
2. Add the libepos2.xcframework and libeposeasyselect.xcframework folders to packages/epson_printer_ios/ios/Frameworks

Android:
1. Agree to the software license and download the Epson ePOS SDK for Android from https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II
2.  Add ePOS2.jar and ePOSEasySelect.jar to packages/epson_printer_android/android/libs.
3.  Add the arm64-v8a, armeabi-v7a, x86 and x86_64 folders to packages/epson_printer_android/android/src/main.


Tested:

| Device      | TM-m30III | Cash Drawer |
|-------------|--------|--------|
| iOS         |   LAN, Bluetooth (pre-connected, in-app pairing), usb     | yes |
| Android     |  LAN, Bluetooth (pre-connected), usb   | yes |

The Discover Printers button mirrors the functionality of the Epson TM app's printer discover based on which platform the app is run from.
On iOS, the plugging in of a usb cable prohibits any future discovery or connection to that same printer via Bluetooth.
On Android, the device and the printer cannot form a Bluetooth connection after a usb cable connection has been made, but if the cable is removed and Discover Printers is called again, then the tablet can connect with that printer over Bluetooth again.



## TODO
1. Generic discovery/connecting button for all 3 interfaces. 

