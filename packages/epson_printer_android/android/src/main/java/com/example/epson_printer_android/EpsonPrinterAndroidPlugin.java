package com.example.epson_printer_android;

import android.app.Activity;
import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

// Epson SDK imports
import com.epson.epos2.Epos2Exception;
import com.epson.epos2.discovery.DeviceInfo;
import com.epson.epos2.discovery.Discovery;
import com.epson.epos2.discovery.DiscoveryListener;
import com.epson.epos2.discovery.FilterOption;
import com.epson.epos2.printer.Printer;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** EpsonPrinterAndroidPlugin */
public class EpsonPrinterAndroidPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
  private MethodChannel channel;
  private Context context;
  private Activity activity;

  // Connection state
  private Printer mPrinter;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "epson_printer");
    channel.setMethodCallHandler(this);
    context = flutterPluginBinding.getApplicationContext();
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "discoverPrinters":
        discoverLanPrinters(result);
        break;
      case "discoverBluetoothPrinters":
        result.success(Collections.emptyList());
        break;
      case "discoverUsbPrinters":
        result.success(Collections.emptyList());
        break;
      case "pairBluetoothDevice":
        java.util.Map<String, Object> payload = new java.util.HashMap<>();
        payload.put("target", null);
        payload.put("resultCode", -1);
        result.success(payload);
        break;
      case "connect":
        connectPrinter(call, result);
        break;
      case "disconnect":
        disconnectPrinter(result);
        break;
      case "printReceipt":
        printReceipt(call, result);
        break;
      case "getStatus":
        // Minimal status until full mapping is implemented
        java.util.Map<String, Object> status = new java.util.HashMap<>();
        status.put("isOnline", mPrinter != null);
        status.put("status", mPrinter != null ? "connected" : "disconnected");
        result.success(status);
        break;
      case "openCashDrawer":
        result.error("UNIMPLEMENTED", "openCashDrawer not implemented on Android yet", null);
        break;
      case "isConnected":
        result.success(mPrinter != null);
        break;
      default:
        result.notImplemented();
    }
  }

  private void discoverLanPrinters(@NonNull Result result) {
    final List<String> found = new ArrayList<>();
    final FilterOption filter = new FilterOption();
    filter.setDeviceType(Discovery.TYPE_PRINTER);
    filter.setPortType(Discovery.PORTTYPE_TCP);
    filter.setEpsonFilter(Discovery.FILTER_NAME);

    final DiscoveryListener listener = new DiscoveryListener() {
      @Override
      public void onDiscovery(final DeviceInfo deviceInfo) {
        synchronized (found) {
          String target = deviceInfo.getTarget();
          String ip = deviceInfo.getIpAddress();
          String name = deviceInfo.getDeviceName();
          String prefixTarget;
          if (target != null && target.startsWith("TCP:")) {
            prefixTarget = target;
          } else if (ip != null && !ip.isEmpty()) {
            prefixTarget = "TCP:" + ip;
          } else if (target != null && !target.isEmpty()) {
            prefixTarget = target.startsWith("TCP:") ? target : ("TCP:" + target);
          } else {
            return;
          }
          String entry = prefixTarget + ":" + (name != null ? name : "Printer");
          if (!found.contains(entry)) {
            found.add(entry);
          }
        }
      }
    };

    try {
      Discovery.start(context, filter, listener);
    } catch (Exception e) {
      result.success(Collections.emptyList());
      return;
    }

    // Stop after a short window and return results
    new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
      while (true) {
        try {
          Discovery.stop();
          break;
        } catch (Epos2Exception e) {
          if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
            break;
          }
        }
      }
      synchronized (found) {
        result.success(new ArrayList<>(found));
      }
    }, 5000);
  }

  private void connectPrinter(@NonNull MethodCall call, @NonNull Result result) {
    try {
      @SuppressWarnings("unchecked")
      Map<String, Object> args = (Map<String, Object>) call.arguments;
      if (args == null) {
        result.error("INVALID_ARGS", "Missing connection settings", null);
        return;
      }

      // Determine target
      String target = (String) args.get("targetString");
      if (target == null || target.isEmpty()) {
        // Build from identifier + portType
        String identifier = (String) args.get("identifier");
        Number portTypeNum = (Number) args.get("portType");
        int portType = portTypeNum != null ? portTypeNum.intValue() : 1; // default tcp
        String prefix;
        switch (portType) {
          case 1: prefix = "TCP:"; break; // tcp
          case 2: prefix = "BT:"; break;  // bluetooth
          case 3: prefix = "USB:"; break; // usb
          case 4: prefix = "BLE:"; break; // ble
          default: prefix = "TCP:"; break;
        }
        target = (identifier != null && identifier.startsWith("TCP:")) ? identifier : (prefix + identifier);
      }

      // Only implement TCP for now
      if (!target.startsWith("TCP:")) {
        result.error("UNSUPPORTED", "Only TCP connection is implemented on Android right now", null);
        return;
      }

      // Disconnect any existing connection
      safeDisposePrinter();

      // Map series/lang (fallback to TM_M30III + ANK if not provided)
      int seriesIdx = getInt(args.get("printerSeries"), 29); // tmM30III index in enum
      int langIdx = getInt(args.get("modelLang"), 0); // ank
      int seriesConst = mapSeries(seriesIdx);
      int langConst = mapLang(langIdx);

      mPrinter = new Printer(seriesConst, langConst, context);
      // Optional: mPrinter.setReceiveEventListener((printerObj, code, status, printJobId) -> {});

      // Connect (PARAM_DEFAULT == 0)
      mPrinter.connect(target, Printer.PARAM_DEFAULT);

      result.success(null);
    } catch (Epos2Exception e) {
      safeDisposePrinter();
      result.error("CONNECT_FAILED", "Epson SDK error: " + e.getMessage(), e.getErrorStatus());
    } catch (Exception ex) {
      safeDisposePrinter();
      result.error("CONNECT_FAILED", ex.getMessage(), null);
    }
  }

  private void disconnectPrinter(@NonNull Result result) {
    try {
      if (mPrinter != null) {
        try {
          mPrinter.disconnect();
        } catch (Exception ignored) {}
        try {
          mPrinter.clearCommandBuffer();
        } catch (Exception ignored) {}
        try {
          mPrinter.setReceiveEventListener(null);
        } catch (Exception ignored) {}
      }
      mPrinter = null;
      result.success(null);
    } catch (Exception e) {
      mPrinter = null;
      result.success(null);
    }
  }

  // Build commands and send print job
  private void printReceipt(@NonNull MethodCall call, @NonNull Result result) {
    if (mPrinter == null) {
      result.error("NOT_CONNECTED", "Printer is not connected", null);
      return;
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> args = (Map<String, Object>) call.arguments;
    if (args == null) {
      result.error("INVALID_ARGS", "Missing print job", null);
      return;
    }

    @SuppressWarnings("unchecked")
    List<Object> commands = (List<Object>) args.get("commands");
    if (commands == null) {
      result.error("INVALID_ARGS", "Missing commands", null);
      return;
    }

    // Run on a background thread to avoid blocking the platform channel
    new Thread(() -> {
      try {
        synchronized (EpsonPrinterAndroidPlugin.this) {
          mPrinter.clearCommandBuffer();

          for (Object item : commands) {
            if (!(item instanceof Map)) continue;
            @SuppressWarnings("unchecked")
            Map<String, Object> cmd = (Map<String, Object>) item;
            String type = String.valueOf(cmd.get("type"));
            @SuppressWarnings("unchecked")
            Map<String, Object> params = (Map<String, Object>) cmd.get("parameters");
            if (params == null) params = new HashMap<>();

            switch (type) {
              case "text":
              case "addText": {
                String data = String.valueOf(params.getOrDefault("data", ""));
                if (data != null) {
                  mPrinter.addText(data);
                }
                break;
              }
              case "feed": {
                int line = getInt(params.get("line"), getInt(params.get("lines"), 1));
                if (line < 1) line = 1;
                mPrinter.addFeedLine(line);
                break;
              }
              case "cut": {
                mPrinter.addCut(Printer.CUT_FEED);
                break;
              }
              // Additional commands (barcode/qrCode/image/pulse/beep/layout) can be added later
              default:
                // Ignore unknown commands for now
                break;
            }
          }

          // Send data
          mPrinter.sendData(Printer.PARAM_DEFAULT);
        }
        runOnMain(() -> result.success(null));
      } catch (Epos2Exception e) {
        runOnMain(() -> result.error("PRINT_FAILED", "Epson SDK error: " + e.getMessage(), e.getErrorStatus()));
      } catch (Exception ex) {
        runOnMain(() -> result.error("PRINT_FAILED", ex.getMessage(), null));
      }
    }).start();
  }

  private void safeDisposePrinter() {
    if (mPrinter != null) {
      try { mPrinter.disconnect(); } catch (Exception ignored) {}
      try { mPrinter.clearCommandBuffer(); } catch (Exception ignored) {}
      try { mPrinter.setReceiveEventListener(null); } catch (Exception ignored) {}
      mPrinter = null;
    }
  }

  private int getInt(Object obj, int def) {
    if (obj instanceof Number) return ((Number) obj).intValue();
    try { return Integer.parseInt(String.valueOf(obj)); } catch (Exception ignored) {}
    return def;
  }

  private void runOnMain(Runnable r) {
    new android.os.Handler(android.os.Looper.getMainLooper()).post(r);
  }

  // Map platform enum EpsonPrinterSeries -> Epson Android Printer series constant
  private int mapSeries(int idx) {
    switch (idx) {
      case 1:  return Printer.TM_M30;      // tmM30
      case 21: return Printer.TM_M30II;    // tmM30II
      case 29: return Printer.TM_M30III;   // tmM30III
      case 12: return Printer.TM_T88;      // tmT88 (generic)
      case 24: return Printer.TM_T88VII;   // tmT88VII
      case 15: return Printer.TM_U220;     // tmU220
      case 23: return Printer.TM_M50;      // tmM50
      case 30: return Printer.TM_M50II;    // tmM50II
      default: return Printer.TM_M30III;   // sensible default for modern models
    }
  }

  // Map platform enum EpsonModelLang -> Epson Android Printer language constant
  private int mapLang(int idx) {
    switch (idx) {
      case 0:  return Printer.MODEL_ANK;       // ank
      case 1:  return Printer.MODEL_JAPANESE;  // japanese
      case 2:  return Printer.MODEL_CHINESE;   // chinese
      case 3:  return Printer.MODEL_TAIWAN;    // taiwan
      case 4:  return Printer.MODEL_KOREAN;    // korean
      case 5:  return Printer.MODEL_THAI;      // thai
      case 6:  return Printer.MODEL_SOUTHASIA; // southasia
      default: return Printer.MODEL_ANK;
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    channel = null;
    context = null;
  }

  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    activity = binding.getActivity();
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    activity = null;
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    activity = binding.getActivity();
  }

  @Override
  public void onDetachedFromActivity() {
    activity = null;
  }
}
