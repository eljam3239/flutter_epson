import Foundation
import Flutter
import ExternalAccessory
import UIKit

public class EpsonPrinterIosPlugin: NSObject, FlutterPlugin {
    private let BLE_CONNECTION_TIMEOUT_MILLIS: Int = 30000 // Set BLE connection timeout to 30 seconds
    
    private var discoveryResult: FlutterResult?
    private var epsonWrapper: EpsonSDKWrapper
    private var target: String?
    private var printerSeries: Int32 = 29 // EPOS2_TM_M30III (based on the discovery result)
    private var printerLang: Int32 = 0 // EPOS2_MODEL_ANK
    private var currentBluetoothDeviceNames: Set<String> = [] // Track CURRENT Bluetooth-connected devices
    private var usbWasConnectedThisSession: Bool = false // Track if USB was ever connected (BT hardware turns off on iOS)
    private var connectedAccessories: Set<String> = [] // Track currently connected EAAccessory devices
    
    override init() {
        epsonWrapper = EpsonSDKWrapper()
        super.init()
        
        // Register for EAAccessory connect/disconnect notifications for logging
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidConnect(_:)),
            name: .EAAccessoryDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidDisconnect(_:)),
            name: .EAAccessoryDidDisconnect,
            object: nil
        )
        EAAccessoryManager.shared().registerForLocalNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        EAAccessoryManager.shared().unregisterForLocalNotifications()
    }
    
    @objc private func accessoryDidConnect(_ notification: Notification) {
        if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
            print("DEBUG: EAAccessory connected: \(accessory.name)")
            
            // If this device is NOT already in our connected set, it means a cable was just plugged in
            // (Bluetooth devices are already connected at app launch)
            if !connectedAccessories.contains(accessory.name) {
                print("DEBUG: NEW accessory connection detected - USB cable was just plugged in!")
                print("DEBUG: Bluetooth hardware on printer is now OFF - disabling BT discovery for session")
                usbWasConnectedThisSession = true
                
                // Cancel any pending Bluetooth timeout to prevent SDK corruption
                // Note: The timeout is managed in Objective-C, so we call the wrapper to cancel it
                epsonWrapper.cancelBluetoothTimeout()
            }
            
            connectedAccessories.insert(accessory.name)
        }
    }
    
    @objc private func accessoryDidDisconnect(_ notification: Notification) {
        if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
            print("DEBUG: EAAccessory disconnected: \(accessory.name)")
            connectedAccessories.remove(accessory.name)
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "epson_printer", binaryMessenger: registrar.messenger())
        let instance = EpsonPrinterIosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "discoverPrinters":
            discoverPrinters(call: call, result: result)
        case "discoverBluetoothPrinters":
            // Clear previous Bluetooth tracking before new discovery
            currentBluetoothDeviceNames.removeAll()
            
            // Debug: list currently connected ExternalAccessory devices and protocol strings
            let accessories = EAAccessoryManager.shared().connectedAccessories
            if accessories.isEmpty {
                print("EAAccessory: No connected accessories found.")
            } else {
                for acc in accessories {
                    print("EAAccessory connected: name=\(acc.name), manufacturer=\(acc.manufacturer), model=\(acc.modelNumber), serial=\(acc.serialNumber), protocols=\(acc.protocolStrings)")
                }
            }
            discoverBluetoothPrinters(call: call, result: result)
        case "discoverUsbPrinters":
            discoverUsbPrinters(result: result)
        case "findPairedBluetoothPrinters":
            findPairedBluetoothPrinters(call: call, result: result)
        case "pairBluetoothDevice":
            pairBluetoothDevice(result: result)
        case "usbDiagnostics":
            usbDiagnostics(result: result)
        case "connect":
            connect(call: call, result: result)
        case "disconnect":
            disconnect(result: result)
        case "printReceipt":
            printReceipt(call: call, result: result)
        case "getStatus":
            getStatus(result: result)
        case "openCashDrawer":
            openCashDrawer(result: result)
        case "isConnected":
            isConnected(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func discoverPrinters(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: Starting Epson printer discovery...")
        
        // Start with TCP discovery (most common for network printers)
        let filterOption: Int32 = 1 // EPOS2_PORTTYPE_TCP
        
        print("DEBUG: Using TCP filter option: \(filterOption)")
        
        // Add error handling wrapper
        do {
            epsonWrapper.startDiscovery(withFilter: filterOption) { [weak self] printers in
                print("DEBUG: Discovery callback received with \(printers.count) printers")
                
                // Deduplicate: if both TCP: and TCPS: exist for same MAC, keep only TCP:
                var seenMacs: [String: String] = [:] // MAC -> target
                var printerStrings: [String] = []
                
                for printer in printers {
                    guard let target = printer["target"] as? String,
                          let deviceName = printer["deviceName"] as? String else {
                        print("DEBUG: Skipping printer with invalid data: \(printer)")
                        continue
                    }
                    
                    // Extract MAC address from target (e.g., "TCP:A4:D7:3C:AA:CA:01" or "TCPS:A4:D7:3C:AA:CA:01[...]")
                    let mac = self?.extractMacAddress(from: target) ?? ""
                    
                    if !mac.isEmpty {
                        if let existingTarget = seenMacs[mac] {
                            // Prefer TCP over TCPS (TCP is standard, TCPS is secure/paired variant)
                            if target.starts(with: "TCP:") && existingTarget.starts(with: "TCPS:") {
                                print("DEBUG: Replacing TCPS with TCP for MAC \(mac)")
                                if let index = printerStrings.firstIndex(where: { $0.starts(with: existingTarget) }) {
                                    printerStrings.remove(at: index)
                                }
                                seenMacs[mac] = target
                                printerStrings.append("\(target):\(deviceName)")
                            } else if target.starts(with: "TCPS:") && existingTarget.starts(with: "TCP:") {
                                print("DEBUG: Skipping TCPS duplicate, already have TCP for MAC \(mac)")
                                continue
                            }
                        } else {
                            seenMacs[mac] = target
                            printerStrings.append("\(target):\(deviceName)")
                        }
                    } else {
                        // No MAC, add as-is
                        printerStrings.append("\(target):\(deviceName)")
                    }
                    
                    print("DEBUG: Found printer: \(target):\(deviceName)")
                }
                
                print("DEBUG: Discovery completed. Found \(printerStrings.count) unique printers: \(printerStrings)")
                
                DispatchQueue.main.async {
                    result(printerStrings)
                }
            }
        } catch {
            print("DEBUG: Discovery threw error: \(error)")
            DispatchQueue.main.async {
                result([])
            }
        }
    }
    
    private func extractMacAddress(from target: String) -> String {
        // Extract MAC from "TCP:A4:D7:3C:AA:CA:01" or "TCPS:A4:D7:3C:AA:CA:01[local_printer]"
        // Remove any bracketed suffix first
        var cleanTarget = target
        if let bracketIndex = target.firstIndex(of: "[") {
            cleanTarget = String(target[..<bracketIndex])
        }
        
        let parts = cleanTarget.split(separator: ":")
        if parts.count >= 7 {
            // Join the MAC parts (last 6 components after protocol)
            return parts[1...6].joined(separator: ":")
        }
        return ""
    }
    
    private func discoverBluetoothPrinters(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: Starting Bluetooth printer discovery...")
        
        // iOS hardware limitation: When USB cable connects, BT radio on printer physically turns off
        // and cannot re-enable until manual reconnect in iOS Settings + app restart
        if usbWasConnectedThisSession {
            print("DEBUG: Skipping Bluetooth discovery - USB was connected this session")
            print("DEBUG: iOS limitation: Printer's BT hardware disabled when USB connected")
            print("DEBUG: User must manually reconnect in iOS Settings after unplugging USB")
            currentBluetoothDeviceNames.removeAll()
            DispatchQueue.main.async { result([]) }
            return
        }
        
        // Clear previous Bluetooth device tracking
        currentBluetoothDeviceNames.removeAll()
        
        // Optimized: single discovery pass (Classic BT finds paired devices quickly)
        do {
            epsonWrapper.startBluetoothDiscovery { [weak self] printers in
                print("DEBUG: Bluetooth discovery callback received with \(printers.count) printers")
                
                let printerStrings = printers.compactMap { printer -> String? in
                    guard let target = printer["target"] as? String,
                          let deviceName = printer["deviceName"] as? String else {
                        print("DEBUG: Skipping printer with missing target or deviceName")
                        return nil
                    }
                    print("DEBUG: Found Bluetooth printer - Target: \(target), Name: \(deviceName)")
                    
                    // Track device name for USB filtering ONLY if it's actually Bluetooth
                    // TCPS: targets are local USB connections masquerading as network, not Bluetooth
                    if target.starts(with: "BT:") || target.starts(with: "BLE:") {
                        self?.currentBluetoothDeviceNames.insert(deviceName)
                    }
                    
                    return "\(target):\(deviceName)"
                }
                
                print("DEBUG: Bluetooth discovery found \(printerStrings.count) printers: \(printerStrings)")
                DispatchQueue.main.async { result(printerStrings) }
            }
        } catch {
            print("DEBUG: Bluetooth discovery threw error: \(error)")
            DispatchQueue.main.async { result([]) }
        }
    }
    
    private func findPairedBluetoothPrinters(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: Starting paired Bluetooth printer discovery...")
        
        do {
            epsonWrapper.findPairedBluetoothPrinters { [weak self] printers in
                print("DEBUG: Paired Bluetooth discovery callback received with \(printers.count) printers")
                
                // Convert to legacy string format for backwards compatibility
                let printerStrings = printers.compactMap { printer -> String? in
                    guard let target = printer["target"] as? String,
                          let deviceName = printer["deviceName"] as? String else {
                        print("DEBUG: Skipping paired printer with missing target or deviceName")
                        return nil
                    }
                    
                    // Log the MAC address if available
                    if let macAddress = printer["macAddress"] as? String, !macAddress.isEmpty {
                        print("DEBUG: Found paired Bluetooth printer - Target: \(target), Name: \(deviceName), MAC: \(macAddress)")
                    } else {
                        print("DEBUG: Found paired Bluetooth printer - Target: \(target), Name: \(deviceName)")
                    }
                    
                    return "\(target):\(deviceName)"
                }
                
                print("DEBUG: Paired Bluetooth discovery completed. Found \(printerStrings.count) printers: \(printerStrings)")
                
                DispatchQueue.main.async {
                    result(printerStrings)
                }
            }
        } catch {
            print("DEBUG: Paired Bluetooth discovery threw error: \(error)")
            DispatchQueue.main.async {
                result([])
            }
        }
    }

    private func usbDiagnostics(result: @escaping FlutterResult) {
        print("DEBUG: usbDiagnostics called")
        result(["status": "not_implemented", "message": "USB diagnostics not yet implemented"])
    }
    
    private func pairBluetoothDevice(result: @escaping FlutterResult) {
        print("DEBUG: pairBluetoothDevice called")
        epsonWrapper.pairBluetoothDevice { target, ret in
            print("DEBUG: pairBluetoothDevice completed with ret=\(ret), target=\(String(describing: target))")
            if let target = target {
                result(["target": target, "resultCode": ret])
            } else {
                result(["target": NSNull(), "resultCode": ret])
            }
        }
    }

    private func connect(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: connect called with arguments: \(String(describing: call.arguments))")
        
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        guard let targetString = args["targetString"] as? String else {
            result(FlutterError(code: "MISSING_TARGET", message: "Target string required", details: nil))
            return
        }
        
        self.target = targetString
        
        // Parse printer series and language if provided
        if let series = args["printerSeries"] as? Int {
          self.printerSeries = Int32(series)
        }
        if let lang = args["printerLanguage"] as? Int {
          self.printerLang = Int32(lang)
        }
        
        let timeout = args["timeout"] as? Int ?? 15000
        
        // Use background QoS to avoid QoS inversion with Epson internals
        DispatchQueue.global(qos: .background).async {
          let success = self.epsonWrapper.connect(toPrinter: targetString, 
                                                          withSeries: self.printerSeries, 
                                                          language: self.printerLang, 
                                                          timeout: Int32(timeout))
          DispatchQueue.main.async {
            if success {
              print("DEBUG: Connected successfully to \(targetString)")
              result(nil)
            } else {
              print("DEBUG: Connection failed")
              result(FlutterError(code: "CONNECTION_FAILED", 
                                message: "Connection failed. Make sure your printer isn't connected to any other device via Bluetooth and try again.", 
                                details: nil))
            }
          }
        }
    }
    
    private func disconnect(result: @escaping FlutterResult) {
        print("DEBUG: disconnect called")
        
        DispatchQueue.global(qos: .userInitiated).async {
          self.epsonWrapper.disconnect()
          DispatchQueue.main.async {
            print("DEBUG: Disconnected successfully")
            result(nil)
          }
        }
    }
    
    private func printReceipt(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: printReceipt called")
        print("DEBUG: Arguments: \(call.arguments ?? "nil")")
        
        guard let args = call.arguments as? [String: Any] else {
          print("DEBUG: Invalid arguments - not a dictionary")
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments must be a dictionary", details: nil))
          return
        }
        
        guard let commands = args["commands"] as? [[String: Any]] else {
          print("DEBUG: Commands not found or invalid format")
          print("DEBUG: Available keys: \(args.keys)")
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Commands are required and must be an array", details: nil))
          return
        }
        
        print("DEBUG: Processing \(commands.count) print commands")
        for (index, command) in commands.enumerated() {
            print("DEBUG: Command \(index): \(command)")
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
          let success = self.epsonWrapper.print(withCommands: commands)
          
          DispatchQueue.main.async {
            if success {
              print("DEBUG: Print job sent successfully")
              result(nil)
            } else {
              print("DEBUG: Print failed")
              result(FlutterError(code: "PRINT_FAILED", 
                                message: "Failed to print", 
                                details: nil))
            }
          }
        }
    }
    
    private func getStatus(result: @escaping FlutterResult) {
        print("DEBUG: getStatus called")
        
        let statusDict = epsonWrapper.getPrinterStatus()
        result(statusDict)
    }
    
    private func openCashDrawer(result: @escaping FlutterResult) {
        print("DEBUG: openCashDrawer called")
        
        DispatchQueue.global(qos: .userInitiated).async {
          let success = self.epsonWrapper.openCashDrawer()
          
          DispatchQueue.main.async {
            if success {
              print("DEBUG: Cash drawer pulse sent successfully")
              result(nil)
            } else {
              print("DEBUG: Cash drawer failed")
              result(FlutterError(code: "DRAWER_FAILED", 
                                message: "Failed to open cash drawer", 
                                details: nil))
            }
          }
        }
    }
    
    private func isConnected(result: @escaping FlutterResult) {
        let connected = (epsonWrapper.printer != nil)
        print("DEBUG: isConnected called - returning \(connected)")
        result(connected)
    }
    
    private func discoverUsbPrinters(result: @escaping FlutterResult) {
        print("DEBUG: Starting USB printer discovery...")
        
        // IMPORTANT: Skip Epson SDK entirely for USB discovery
        // The SDK's USB discovery internally triggers BLE finder which causes threading issues
        // EAAccessory provides direct hardware enumeration without SDK overhead
        print("DEBUG: Using EAAccessory-only mode (bypassing SDK to avoid BLE threading issues)")
        
        let accessories = EAAccessoryManager.shared().connectedAccessories
        let epsonAccessories = accessories.filter { acc in
            acc.protocolStrings.contains("com.epson.escpos") || acc.protocolStrings.contains("com.epson.posprinter")
        }
        
        if !epsonAccessories.isEmpty {
            print("DEBUG: Found \(epsonAccessories.count) EAAccessory devices")
            print("DEBUG: Current Bluetooth device names: \(currentBluetoothDeviceNames)")
            
            // Filter out devices that are Bluetooth connections
            // EAAccessory shows BOTH USB and Bluetooth Classic devices
            let usbPrinters = epsonAccessories.compactMap { acc -> String? in
                print("DEBUG: EAAccessory device: \(acc.name), connectionID: \(acc.connectionID), protocols: \(acc.protocolStrings)")
                
                // If this device was discovered via Bluetooth, it's a BT connection, not USB
                if currentBluetoothDeviceNames.contains(acc.name) {
                    print("DEBUG: Skipping '\(acc.name)' - this is a Bluetooth connection, not USB")
                    return nil
                }
                
                print("DEBUG: Including '\(acc.name)' as USB device")
                return "USB::\(acc.name)"
            }
            
            print("DEBUG: USB discovery completed. Found \(usbPrinters.count) USB printers: \(usbPrinters)")
            result(usbPrinters)
        } else {
            print("DEBUG: No Epson EAAccessory devices found")
            result([])
        }
    }
}
