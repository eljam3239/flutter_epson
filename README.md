# test_epson

Flutter wrapper for Epson iOS SDK.

## Setup

1. Agree to the software license and download the Epson ePOS SDK for iOS from https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II
2. Add the libepos2.xcframework and libeposeasyselect.xcframework folders to packages/epson_printer_ios/ios/Frameworks

Tested:

| Device      | TM-m30III |
|-------------|--------|
| iOS         |   LAN, Bluetooth, usb     | 
| Android     |  LAN      |


## TODO
1. Need a cash drawer to test. 
2. Going to bundle all bluetooth connection into one button, as opposed to seperate flows for pre-connected vs disconnect printers.
3. Generic discovery/connecting button for all 3 interfaces. 