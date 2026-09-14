package com.weilu.deer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;

/**
 * PDA 硬件扫描插件
 *
 * 监听主流 PDA 手持机（商米、优博音、新大陆、iData、东大集成等）的扫描广播，
 * 通过 EventChannel 将扫描结果推送到 Flutter 层。
 */
public class PdaScannerPlugin implements FlutterPlugin, EventChannel.StreamHandler {

    private EventChannel eventChannel;
    private EventChannel.EventSink eventSink;
    private BroadcastReceiver scanReceiver;
    private Context appContext;

    /** 主流 PDA 扫描广播 Action 列表 */
    private static final String[] SCAN_ACTIONS = {
        "android.intent.action.SCAN_RESULT",          // 商米 / 通用
        "android.intent.action.SCAN",                  // 通用
        "android.intent.action.DATA_AVAILABLE",        // 新大陆 / 通用
        "android.intent.action.DECODE",                // 优博音
        "android.intent.action.BARCODE_RESULT",        // 部分机型
        "com.sunmi.scanner.SCAN",                      // 商米旧版
        "com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED", // 商米 L2/V2/Z1
        "nlscan.action.SCANNER_RESULT",                // 新大陆
        "UROVO_SCANNER_ACTION",                        // 优博音
        "idata.scanner.ACTION_BARCODE",                // iData
        "android.intent.action.HONEYWELL_SCAN",        // Honeywell
        "com.android.server.WMS_SCAN_RESULT",          // WMS 定制
        "barcode_broadcast_action",                    // 部分国产定制 PDA
        "com.android.server.scannerservice.broadcast", // 东大集成 / 优博讯 / 肖邦
        "android.intent.ACTION_DECODE_DATA",           // 优博讯 i6200
        "android.intent.action.SCANRESULT",            // 智联天地 / 盈达
        "android.intent.action.RECEIVE_SCANDATA_BROADCAST", // 新大陆 N5/MT60 / 智联天地
        "com.barcode.sendBroadcast",                   // 优博讯 CRUISE
        "com.android.receive_scan_action",             // 凯立 KAICOM
        "com.honeywell.scan.broadcast",                // 霍尼韦尔 EDA
        "com.jb.action.GET_SCANDATA",                  // 捷宝
        "ACTION_BAR_SCAN",                             // 新大陆 MT60E
    };

    /** 主流 PDA 扫描结果 Extra Key 列表 */
    private static final String[] EXTRA_KEYS = {
        "barcode",             // 商米 / 新大陆
        "barcode_string",      // 商米
        "data",                // 通用 / 商米 L2/V2/Z1 / 霍尼韦尔 / 凯立 / 捷宝
        "SCAN_BARCODE",        // 优博音 / Honeywell
        "scan_result",         // 通用
        "result",              // 部分机型
        "BARCODE",             // 通用大写 / 优博讯
        "scanData",            // iData
        "DECODE_DATA_MODE",    // 新大陆
        "KEY_SCAN_DATA",       // 东大集成
        "scan_barcode_data",   // 定制 PDA
        "scannerdata",         // 东大 / 优博讯
        "SCAN_BARCODE1",       // 智联天地 N7e / 新大陆
        "value",               // 智联天地 / 盈达
        "EXTRA_SCAN_DATA",     // 新大陆 MT60E
        "android.intent.extra.SCAN_BROADCAST_DATA", // 智联天地 / 新大陆 N5
    };

    @Override
    public void onAttachedToEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        appContext = binding.getApplicationContext();
        eventChannel = new EventChannel(binding.getBinaryMessenger(), "com.weilu.deer/pda_scanner");
        eventChannel.setStreamHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        unregisterReceiver();
        if (eventChannel != null) {
            eventChannel.setStreamHandler(null);
            eventChannel = null;
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        this.eventSink = events;
        registerReceiver();
    }

    @Override
    public void onCancel(Object arguments) {
        this.eventSink = null;
        unregisterReceiver();
    }

    private void registerReceiver() {
        if (appContext == null) return;
        unregisterReceiver();

        scanReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (eventSink == null) return;
                String barcode = extractBarcode(intent);
                if (barcode != null && !barcode.isEmpty()) {
                    eventSink.success(barcode);
                }
            }
        };

        IntentFilter filter = new IntentFilter();
        for (String action : SCAN_ACTIONS) {
            filter.addAction(action);
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                appContext.registerReceiver(scanReceiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                appContext.registerReceiver(scanReceiver, filter);
            }
        } catch (Exception ignored) {}
    }

    private void unregisterReceiver() {
        if (scanReceiver != null && appContext != null) {
            try {
                appContext.unregisterReceiver(scanReceiver);
            } catch (Exception ignored) {}
            scanReceiver = null;
        }
    }

    /**
     * 从 Intent 中提取条码数据
     * 遍历所有常见 Extra Key，返回第一个非空值
     */
    private String extractBarcode(Intent intent) {
        // 优先尝试常见 key
        for (String key : EXTRA_KEYS) {
            String value = intent.getStringExtra(key);
            if (value != null && !value.isEmpty()) {
                return value.trim();
            }
        }
        // 兜底：尝试 Bundle 里所有 String 类型的值
        try {
            android.os.Bundle extras = intent.getExtras();
            if (extras != null) {
                for (String key : extras.keySet()) {
                    Object val = extras.get(key);
                    if (val instanceof String && !((String) val).isEmpty()) {
                        return ((String) val).trim();
                    }
                }
            }
        } catch (Exception ignored) {}
        return null;
    }
}
