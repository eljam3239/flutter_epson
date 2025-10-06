# test_epson

Flutter wrapper for Epson's iOS and Android SDKs.

## Setup

1. Agree to the software license and download the Epson ePOS SDK for iOS from https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II
2. Add the libepos2.xcframework and libeposeasyselect.xcframework folders to packages/epson_printer_ios/ios/Frameworks

Tested:

| Device      | TM-m30III | Cash Drawer |
|-------------|--------|--------|
| iOS         |   LAN, Bluetooth (pre-connected, in-app pairing), usb     | yes |
| Android     |  LAN, Bluetooth (pre-connected), usb   | yes |

Cannot connect to Bluetooth while printer is wired via USB -- even if the user Disconnects from the usb connection in-app


## TODO
1. Generic discovery/connecting button for all 3 interfaces. 
