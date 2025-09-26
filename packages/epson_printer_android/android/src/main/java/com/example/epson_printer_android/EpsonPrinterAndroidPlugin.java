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

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;

/** EpsonPrinterAndroidPlugin */
public class EpsonPrinterAndroidPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
  private MethodChannel channel;
  private Context context;
  private Activity activity;

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
        result.error("UNIMPLEMENTED", "connect not implemented on Android yet", null);
        break;
      case "disconnect":
        result.success(null);
        break;
      case "printReceipt":
        result.error("UNIMPLEMENTED", "printReceipt not implemented on Android yet", null);
        break;
      case "getStatus":
        java.util.Map<String, Object> status = new java.util.HashMap<>();
        status.put("isOnline", false);
        status.put("status", "unknown");
        result.success(status);
        break;
      case "openCashDrawer":
        result.error("UNIMPLEMENTED", "openCashDrawer not implemented on Android yet", null);
        break;
      case "isConnected":
        result.success(false);
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
