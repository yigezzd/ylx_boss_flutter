package com.weilu.deer;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.gainscha.sdk2.ConnectionListener;
import com.gainscha.sdk2.Printer;
import com.gainscha.sdk2.PrinterFinder;
import com.gainscha.sdk2.PrinterReadDataListener;
import com.gainscha.sdk2.PrinterResponse;
import com.gainscha.sdk2.command.Tspl;
import com.gainscha.sdk2.model.BluetoothPrinterDevice;
import com.gainscha.sdk2.model.Instruction;
import com.gainscha.sdk2.model.PrinterDevice;
import com.gainscha.sdk2.model.SerialPortPrinterDevice;
import com.gainscha.sdk2.model.UsbAccessoryPrinterDevice;
import com.gainscha.sdk2.model.UsbPrinterDevice;
import com.gainscha.sdk2.model.WifiPrinterDevice;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * 蓝牙标签打印插件（基于佳博 SDK2，双指令集：佳博 TSPL / 汉印 CPCL）
 *
 * 提供蓝牙打印机扫描、连接、标签打印能力。
 * 品牌识别路由：名称匹配（零成本）→ 响应式指令探测（SDK PrinterResponse 机制，防误判带缓存）；
 * 汉印（HPRT）走 CPCL 路径，佳博/未知走 TSPL 原路径（保持既有行为不变）。
 * 标签内容与小程序 blePrintLabels 保持一致（商品名称/折后单价/小计/零售价/折扣/CODE128条码）。
 */
public class GPrinterPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private static final String CHANNEL_NAME = "com.weilu.deer/gprinter";
    private static final String TAG = "GPrinterPlugin";
    private static final int REQ_PERMS = 2001;
    private static final int REQ_ENABLE_BT = 2002;
    private static final int CONNECT_TIMEOUT = 15000;
    /** CPCL 文本字体编号：24 = TSS24 点阵（与佳博 TSPL 的 TSS24 字号一致） */
    private static final int CPCL_FONT = 24;
    /** CPCL 小号字体编号：55 = 16 点阵（对应佳博 TSS16 降号） */
    private static final int CPCL_FONT_SMALL = 55;
    /** 品牌探测指令：ESC/POS 厂商查询 GS I B（汉印/佳博 ESC 系打印机均响应） */
    private static final byte[] PROBE_GS_I_B = new byte[]{0x1D, 0x49, 0x42};
    /** 响应式探测等待回包超时(ms) */
    private static final int PROBE_TIMEOUT = 1500;
    /** SDK 指令集查询 API 等待超时(ms) */
    private static final int PROBE_API_TIMEOUT = 2500;
    /** 探测失败负缓存时长(ms)：期间不重复探测，避免每张标签都等待超时 */
    private static final int PROBE_NEG_TTL = 8000;

    private MethodChannel channel;
    private Context appContext;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private PrinterFinder finder;
    private MethodChannel.Result scanResult;
    private Map<String, Map<String, String>> scanDevices;
    private Runnable scanStopRunnable;

    private MethodChannel.Result connectResult;
    private Runnable connectTimeoutRunnable;
    private MethodChannel.Result permResult;
    private MethodChannel.Result enableBtResult;

    /** 品牌缓存（MAC → brand；探测成功后写入，按 MAC 键控避免设备错配） */
    private final Map<String, String> brandCache = new ConcurrentHashMap<>();
    /** 探测失败负缓存（MAC → 可重试时间戳） */
    private final Map<String, Long> brandNegCache = new ConcurrentHashMap<>();
    /** 设备名缓存（MAC → 扫描到的名称），connect 时记录，供品牌名称匹配 */
    private final Map<String, String> deviceNameCache = new ConcurrentHashMap<>();
    /** 当前连接设备 MAC（connect 时记录，打印时用于查询品牌） */
    private volatile String currentConnectedMac;

    /** SDK 连接状态监听（连接成功/失败回调） */
    private final ConnectionListener connectionListener = new ConnectionListener() {
        @Override
        public void onPrinterConnected(Printer printer) {
            mainHandler.post(() -> {
                if (connectResult != null) {
                    connectResult.success(true);
                    connectResult = null;
                }
                cancelConnectTimeout();
            });
        }

        @Override
        public void onPrinterConnectFail(Printer printer) {
            mainHandler.post(() -> {
                if (connectResult != null) {
                    connectResult.success(false);
                    connectResult = null;
                }
                cancelConnectTimeout();
            });
        }

        @Override
        public void onPrinterDisconnect(Printer printer) {
        }
    };

    /** 权限申请结果监听 */
    private final PluginRegistry.RequestPermissionsResultListener permListener =
            (requestCode, permissions, grantResults) -> {
                if (requestCode == REQ_PERMS && permResult != null) {
                    boolean allGranted = true;
                    for (int r : grantResults) {
                        if (r != PackageManager.PERMISSION_GRANTED) {
                            allGranted = false;
                            break;
                        }
                    }
                    permResult.success(allGranted);
                    permResult = null;
                    return true;
                }
                return false;
            };

    /** 系统蓝牙开启弹窗（ACTION_REQUEST_ENABLE）结果监听 */
    private final PluginRegistry.ActivityResultListener activityResultListener =
            (requestCode, resultCode, data) -> {
                if (requestCode == REQ_ENABLE_BT && enableBtResult != null) {
                    enableBtResult.success(resultCode == Activity.RESULT_OK);
                    enableBtResult = null;
                    return true;
                }
                return false;
            };

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        appContext = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);
        Printer.setLogEnable(false, null);
        Printer.addConnectionListener(connectionListener);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        Printer.removeConnectionListener(connectionListener);
        stopScanInternal();
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(permListener);
        binding.addActivityResultListener(activityResultListener);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(permListener);
            activityBinding.removeActivityResultListener(activityResultListener);
            activityBinding = null;
        }
        activity = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "requestPermissions":
                requestPermissions(result);
                break;
            case "isBluetoothEnabled": {
                BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
                result.success(adapter != null && adapter.isEnabled());
                break;
            }
            case "enableBluetooth":
                enableBluetooth(result);
                break;
            case "scanPrinters": {
                int timeout = call.hasArgument("timeout") ? (int) call.argument("timeout") : 10000;
                scanPrinters(timeout, result);
                break;
            }
            case "connect": {
                String mac = call.argument("mac");
                String name = call.argument("name");
                connect(mac, name, result);
                break;
            }
            case "disconnect":
                disconnect();
                result.success(true);
                break;
            case "isConnected":
                result.success(!Printer.getConnectedPrinters().isEmpty());
                break;
            case "printLabels": {
                List<Map<String, Object>> items = call.argument("items");
                int template = call.hasArgument("template") ? (int) call.argument("template") : 1;
                printLabels(items, template, result);
                break;
            }
            case "printPrepackLabels": {
                List<Map<String, Object>> items = call.argument("items");
                int template = call.hasArgument("template") ? (int) call.argument("template") : 1;
                printPrepackLabels(items, template, result);
                break;
            }
            case "printTestLabel":
                printTestLabel(result);
                break;
            default:
                result.notImplemented();
        }
    }

    // ─── 权限 ───

    private void requestPermissions(@NonNull MethodChannel.Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity 不可用", null);
            return;
        }
        String[] perms;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            perms = new String[]{
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.ACCESS_FINE_LOCATION
            };
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            perms = new String[]{
                    Manifest.permission.ACCESS_FINE_LOCATION
            };
        } else {
            result.success(true);
            return;
        }
        List<String> missing = new ArrayList<>();
        for (String p : perms) {
            if (ContextCompat.checkSelfPermission(activity, p) != PackageManager.PERMISSION_GRANTED) {
                missing.add(p);
            }
        }
        if (missing.isEmpty()) {
            result.success(true);
            return;
        }
        permResult = result;
        ActivityCompat.requestPermissions(activity, missing.toArray(new String[0]), REQ_PERMS);
    }

    // ─── 扫描 ───

    @SuppressLint("MissingPermission")
    private void scanPrinters(int timeout, @NonNull MethodChannel.Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity 不可用", null);
            return;
        }
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "设备不支持蓝牙", null);
            return;
        }
        if (!adapter.isEnabled()) {
            result.error("BT_DISABLED", "请先开启蓝牙", null);
            return;
        }
        // 上一次扫描未结束时先终止
        stopScanInternal();

        scanResult = result;
        scanDevices = new LinkedHashMap<>();
        finder = new PrinterFinder();
        finder.searchPrinters(new PrinterFinder.SearchPrinterResultListener() {
            @Override
            public void onSearchBluetoothPrinter(BluetoothPrinterDevice device) {
                if (scanDevices == null) return;
                try {
                    String mac = device.getBluetoothDevice().getAddress();
                    String name = device.getPrinterName();
                    if (name == null || name.isEmpty()) name = mac;
                    if (!scanDevices.containsKey(mac)) {
                        Map<String, String> item = new LinkedHashMap<>();
                        item.put("name", name);
                        item.put("mac", mac);
                        scanDevices.put(mac, item);
                    }
                } catch (Exception ignored) {
                }
            }

            @Override
            public void onSearchUsbPrinter(UsbPrinterDevice device) {
            }

            @Override
            public void onSearchUsbPrinter(UsbAccessoryPrinterDevice device) {
            }

            @Override
            public void onSearchNetworkPrinter(WifiPrinterDevice device) {
            }

            @Override
            public void onSearchSerialPortPrinter(SerialPortPrinterDevice device) {
            }

            @Override
            public void onSearchCompleted() {
                mainHandler.post(GPrinterPlugin.this::finishScan);
            }
        });

        scanStopRunnable = this::finishScan;
        mainHandler.postDelayed(scanStopRunnable, Math.max(3000, timeout));
    }

    private void finishScan() {
        stopScanInternal();
        if (scanResult != null) {
            scanResult.success(new ArrayList<>(scanDevices.values()));
            scanResult = null;
        }
    }

    private void stopScanInternal() {
        if (scanStopRunnable != null) {
            mainHandler.removeCallbacks(scanStopRunnable);
            scanStopRunnable = null;
        }
        if (finder != null) {
            try {
                finder.stopSearchDevice();
            } catch (Exception ignored) {
            }
            finder = null;
        }
    }

    // ─── 连接 ───

    @SuppressLint("MissingPermission")
    private void connect(String mac, String name, @NonNull MethodChannel.Result result) {
        if (mac == null || mac.isEmpty()) {
            result.error("INVALID_MAC", "打印机地址为空", null);
            return;
        }
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "设备不支持蓝牙", null);
            return;
        }
        if (!adapter.isEnabled()) {
            result.error("BT_DISABLED", "请先开启蓝牙", null);
            return;
        }
        // 记录设备名与当前设备（品牌名称匹配 / 探测缓存依据）
        String target = mac.toUpperCase(Locale.ROOT);
        currentConnectedMac = target;
        if (name != null && !name.isEmpty()) {
            deviceNameCache.put(target, name);
        }
        android.util.Log.i(TAG, "connect: mac=" + target + ", name=" + (name == null ? "null" : "'" + name + "'"));
        // 已连接同一设备直接返回
        for (Printer p : Printer.getConnectedPrinters()) {
            PrinterDevice d = p.getPrinterDevice();
            if (d instanceof BluetoothPrinterDevice) {
                try {
                    if (target.equals(((BluetoothPrinterDevice) d).getBluetoothDevice().getAddress())) {
                        result.success(true);
                        return;
                    }
                } catch (Exception ignored) {
                }
            }
        }

        BluetoothDevice device;
        try {
            device = adapter.getRemoteDevice(target);
        } catch (IllegalArgumentException e) {
            result.error("INVALID_MAC", "打印机地址格式错误", null);
            return;
        }

        if (connectResult != null) {
            connectResult.success(false);
        }
        connectResult = result;
        connectTimeoutRunnable = () -> {
            if (connectResult != null) {
                connectResult.success(false);
                connectResult = null;
            }
        };
        mainHandler.postDelayed(connectTimeoutRunnable, CONNECT_TIMEOUT);
        try {
            Printer.connect(new BluetoothPrinterDevice(device, 0));
        } catch (Exception e) {
            // 连接异常（如蓝牙被占用、设备不可达）直接返回失败，避免平台线程未捕获异常
            cancelConnectTimeout();
            connectResult = null;
            result.success(false);
        }
    }

    /**
     * 开启系统蓝牙：
     * Android 13 以下弹出系统一键开启弹窗（ACTION_REQUEST_ENABLE），
     * Android 13+ 限制应用直接开启，跳转系统蓝牙设置页由用户手动开启。
     */
    private void enableBluetooth(@NonNull MethodChannel.Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity 不可用", null);
            return;
        }
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "设备不支持蓝牙", null);
            return;
        }
        if (adapter.isEnabled()) {
            result.success(true);
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            if (enableBtResult != null) {
                enableBtResult.success(false);
            }
            enableBtResult = result;
            activity.startActivityForResult(
                    new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQ_ENABLE_BT);
        } else {
            activity.startActivity(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
            result.success(false);
        }
    }

    private void cancelConnectTimeout() {
        if (connectTimeoutRunnable != null) {
            mainHandler.removeCallbacks(connectTimeoutRunnable);
            connectTimeoutRunnable = null;
        }
    }

    private void disconnect() {
        for (Printer p : Printer.getConnectedPrinters()) {
            try {
                p.disconnect();
            } catch (Exception ignored) {
            }
        }
    }

    // ─── 品牌识别（佳博 TSPL / 汉印 CPCL 双路径）───

    /** 汉印特征关键词（名称匹配与探测回包共用；E3PLUS/E3 PLUS/iDPRT 为汉印常见系列名/子品牌） */
    private static final String[] HPRT_KEYS = {"HPRT", "HANIN", "汉印", "E3PLUS", "E3 PLUS", "IDPRT"};
    /** 佳博特征关键词 */
    private static final String[] GPRINTER_KEYS = {"GPRINTER", "GAINSCHA", "佳博"};

    /**
     * 根据设备名识别品牌（零成本，一级）
     * 汉印默认 HM- 前缀或含 HPRT/HANIN/汉印；佳博默认 Printer_ 前缀或含 GPRINTER/GAINSCHA/佳博
     */
    private static String identifyBrandByName(String name) {
        if (name == null) return "unknown";
        String n = name.toUpperCase(Locale.ROOT);
        if (n.isEmpty()) return "unknown";
        for (String k : HPRT_KEYS) {
            if (n.contains(k.toUpperCase(Locale.ROOT))) return "hprt";
        }
        if (n.startsWith("HM-")) return "hprt";
        for (String k : GPRINTER_KEYS) {
            if (n.contains(k.toUpperCase(Locale.ROOT))) return "gprinter";
        }
        if (n.startsWith("PRINTER_")) return "gprinter";
        return "unknown";
    }

    /**
     * 解析当前打印机品牌（多级：名称匹配 → 探测缓存 → GS I B 探测 → 回退 gprinter）
     * 回退 gprinter 即走 TSPL 原路径，保持佳博既有行为不变
     */
    private String resolveBrand(Printer printer) {
        String mac = currentConnectedMac;
        String name = mac == null ? null : deviceNameCache.get(mac);
        String byName = identifyBrandByName(name);
        if (!"unknown".equals(byName)) {
            android.util.Log.i(TAG, "品牌识别: " + byName + " (来源: name, " + name + ")");
            return byName;
        }
        if (mac == null || mac.isEmpty()) {
            android.util.Log.i(TAG, "品牌识别: gprinter (来源: default, 无设备信息)");
            return "gprinter";
        }
        String cached = brandCache.get(mac);
        if (cached != null) {
            android.util.Log.i(TAG, "品牌识别: " + cached + " (来源: cache, " + mac + ")");
            return cached;
        }
        Long negUntil = brandNegCache.get(mac);
        if (negUntil != null && System.currentTimeMillis() < negUntil) {
            android.util.Log.i(TAG, "品牌识别: gprinter (来源: negCache, 跳过探测)");
            return "gprinter";
        }
        String probed = probeBrand(printer);
        if (!"unknown".equals(probed)) {
            android.util.Log.i(TAG, "品牌识别: " + probed + " (来源: probe, " + mac + ")");
            brandCache.put(mac, probed);
            brandNegCache.remove(mac);
            return probed;
        }
        android.util.Log.i(TAG, "品牌识别: gprinter (来源: fallback, 探测未命中)");
        brandNegCache.put(mac, System.currentTimeMillis() + PROBE_NEG_TTL);
        return "gprinter";
    }

    /** 品牌探测（多机制阶梯，见 probeBrandOnce） */
    private String probeBrand(Printer printer) {
        return probeBrandOnce(printer);
    }

    /**
     * 探测阶梯（任一命中即返回，全部失败返回 unknown）：
     * ① print + PrinterResponse 响应机制：发送 GS I B 并等待回包（与小程序 BLE 探测同语义）
     * ② getPrinterInstruction 官方指令集查询：返回 CPCL 判定为汉印
     */
    private String probeBrandOnce(Printer printer) {
        String byResponse = probeByPrintResponse(printer);
        if (!"unknown".equals(byResponse)) return byResponse;
        return probeByInstructionApi(printer);
    }

    /** ① 响应式打印探测：SDK print(data, PrinterResponse) 机制等待打印机回包 */
    private String probeByPrintResponse(Printer printer) {
        final CountDownLatch latch = new CountDownLatch(1);
        final ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try {
            PrinterResponse<byte[]> response = data -> {
                if (data != null && data.length > 0) {
                    buffer.write(data, 0, data.length);
                    latch.countDown();
                }
            };
            printer.print(PROBE_GS_I_B, response);
            latch.await(PROBE_TIMEOUT, TimeUnit.MILLISECONDS);
            if (buffer.size() == 0) {
                android.util.Log.i(TAG, "响应式探测无回包（超时 " + PROBE_TIMEOUT + "ms）");
                return "unknown";
            }
            byte[] data = buffer.toByteArray();
            String result = interpretProbeResponse(data);
            android.util.Log.i(TAG, "响应式探测回包: " + hex(data) + " → " + result);
            return result;
        } catch (Exception e) {
            android.util.Log.i(TAG, "响应式探测异常: " + e.getMessage());
            return "unknown";
        }
    }

    /** ② SDK 官方指令集查询：getPrinterInstruction 返回 CPCL 判定为汉印 */
    private String probeByInstructionApi(Printer printer) {
        final CountDownLatch latch = new CountDownLatch(1);
        final String[] result = {null};
        try {
            PrinterResponse<Instruction> response = inst -> {
                result[0] = String.valueOf(inst);
                latch.countDown();
            };
            printer.getPrinterInstruction(response);
            boolean done = latch.await(PROBE_API_TIMEOUT, TimeUnit.MILLISECONDS);
            android.util.Log.i(TAG, "指令集查询: " + (done ? result[0] : "无回调（超时 " + PROBE_API_TIMEOUT + "ms）"));
            if (done && result[0] != null && result[0].toUpperCase(Locale.ROOT).contains("CPCL")) {
                return "hprt";
            }
            return "unknown";
        } catch (Exception e) {
            android.util.Log.i(TAG, "指令集查询异常: " + e.getMessage());
            return "unknown";
        }
    }

    /** 字节数组转 hex 字符串（日志用） */
    private static String hex(byte[] data) {
        StringBuilder hex = new StringBuilder();
        for (byte b : data) {
            hex.append(String.format(Locale.US, "%02X ", b));
        }
        return hex.toString().trim();
    }

    /**
     * 解析探测回包：依次尝试 ASCII 与 GBK 解码（部分机型回中文厂商名），
     * 任一编码命中关键词即返回；均未命中返回 unknown
     */
    private static String interpretProbeResponse(byte[] data) {
        String[] texts = new String[2];
        texts[0] = new String(data, StandardCharsets.US_ASCII);
        try {
            texts[1] = new String(data, "GBK");
        } catch (Exception ignored) {
            texts[1] = null;
        }
        for (String text : texts) {
            if (text == null || text.isEmpty()) continue;
            String s = text.toUpperCase(Locale.ROOT);
            for (String k : HPRT_KEYS) {
                if (s.contains(k.toUpperCase(Locale.ROOT))) return "hprt";
            }
            for (String k : GPRINTER_KEYS) {
                if (s.contains(k.toUpperCase(Locale.ROOT))) return "gprinter";
            }
        }
        return "unknown";
    }

    // ─── 打印 ───

    private void printLabels(final List<Map<String, Object>> items, final int template,
                             @NonNull final MethodChannel.Result result) {
        if (items == null || items.isEmpty()) {
            result.error("EMPTY_ITEMS", "没有可打印的明细", null);
            return;
        }
        if (Printer.getConnectedPrinters().isEmpty()) {
            result.error("NOT_CONNECTED", "打印机未连接", null);
            return;
        }
        new Thread(() -> {
            try {
                Printer printer = Printer.getConnectedPrinters().get(0);
                // 品牌识别路由：汉印 → CPCL；佳博/未知 → TSPL 原路径（保持既有行为不变）
                boolean useCpcl = "hprt".equals(resolveBrand(printer));
                android.util.Log.i(TAG, "打印标签路由: " + (useCpcl ? "CPCL" : "TSPL")
                        + ", items=" + items.size() + ", template=" + template);
                for (Map<String, Object> item : items) {
                    int copies = toInt(item.get("copies"), 1);
                    byte[] data = useCpcl
                            ? buildLabelCpcl(item, copies, template)
                            : buildLabel(item, copies, template);
                    printer.print(data, null);
                    // 多张标签间隔短暂等待，避免打印机缓冲区溢出
                    Thread.sleep(200);
                }
                mainHandler.post(() -> result.success(items.size()));
            } catch (final Exception e) {
                mainHandler.post(() -> result.error("PRINT_FAIL",
                        e.getMessage() != null ? e.getMessage() : "打印失败", null));
            }
        }).start();
    }

    /**
     * 打印预包装改价标签（含包装数量/包装金额/包装折扣/包装条码）
     */
    private void printPrepackLabels(final List<Map<String, Object>> items, final int template,
                                    @NonNull final MethodChannel.Result result) {
        if (items == null || items.isEmpty()) {
            result.error("EMPTY_ITEMS", "没有可打印的明细", null);
            return;
        }
        if (Printer.getConnectedPrinters().isEmpty()) {
            result.error("NOT_CONNECTED", "打印机未连接", null);
            return;
        }
        new Thread(() -> {
            try {
                Printer printer = Printer.getConnectedPrinters().get(0);
                // 品牌识别路由：汉印 → CPCL；佳博/未知 → TSPL 原路径（保持既有行为不变）
                boolean useCpcl = "hprt".equals(resolveBrand(printer));
                android.util.Log.i(TAG, "打印预包装路由: " + (useCpcl ? "CPCL" : "TSPL")
                        + ", items=" + items.size() + ", template=" + template);
                for (Map<String, Object> item : items) {
                    int copies = toInt(item.get("copies"), 1);
                    byte[] data = useCpcl
                            ? buildPrepackLabelCpcl(item, copies, template)
                            : buildPrepackLabel(item, copies, template);
                    printer.print(data, null);
                    // 多张标签间隔短暂等待，避免打印机缓冲区溢出
                    Thread.sleep(200);
                }
                mainHandler.post(() -> result.success(items.size()));
            } catch (final Exception e) {
                mainHandler.post(() -> result.error("PRINT_FAIL",
                        e.getMessage() != null ? e.getMessage() : "打印失败", null));
            }
        }).start();
    }

    /**
     * 打印测试标签（58×30mm 标准测试布局，对齐小程序 bluetooth.vue testPrint）
     * 品牌识别路由：汉印 → CPCL；佳博/未知 → TSPL
     */
    private void printTestLabel(@NonNull final MethodChannel.Result result) {
        if (Printer.getConnectedPrinters().isEmpty()) {
            result.error("NOT_CONNECTED", "打印机未连接", null);
            return;
        }
        new Thread(() -> {
            try {
                Printer printer = Printer.getConnectedPrinters().get(0);
                boolean useCpcl = "hprt".equals(resolveBrand(printer));
                android.util.Log.i(TAG, "测试标签路由: " + (useCpcl ? "CPCL" : "TSPL"));
                byte[] data = useCpcl ? buildTestLabelCpcl() : buildTestLabelTspl();
                printer.print(data, null);
                mainHandler.post(() -> result.success(true));
            } catch (final Exception e) {
                mainHandler.post(() -> result.error("PRINT_FAIL",
                        e.getMessage() != null ? e.getMessage() : "打印失败", null));
            }
        }).start();
    }

    /** 测试标签 TSPL 指令（佳博/未知路径，58×30mm） */
    private byte[] buildTestLabelTspl() throws Exception {
        int labelW = 58;
        int labelH = 30;

        Tspl cmd = new Tspl();
        cmd.addSize(labelW, labelH);
        cmd.addGap(2);
        cmd.addCls();

        // 标题（名称 + 价格）
        cmd.addText(150, 20, Tspl.FONT_TSS24, 0, 2, 2, "测试标签");
        cmd.addText(340, 20, Tspl.FONT_TSS24, 0, 2, 2, "88 元");
        // 商品信息
        cmd.addText(50, 100, Tspl.FONT_TSS24, 0, 1, 1, "名称：蓝牙打印机");
        cmd.addText(50, 140, Tspl.FONT_TSS24, 0, 1, 1, "条码：12345678");
        // CODE128 条码
        cmd.add1DBarcode(50, 175, Tspl.BARCODE_CODE_128, 48, true, Tspl.ROTATION_0, 2, 2, "12345678");

        cmd.addPrint(1);
        return cmd.getBytes();
    }

    /**
     * 生成单个商品的 TSPL 标签指令
     * 布局与小程序 buildLabelCommand 保持一致：
     * 商品名称(大字) / 折后单价+小计 / 零售价+折扣 / CODE128 条码
     */
    private byte[] buildLabel(Map<String, Object> item, int copies, int template) throws Exception {
        int labelW;
        int labelH;
        int gap = 2;
        switch (template) {
            case 2:
                labelW = 50;
                labelH = 30;
                break;
            case 3:
                labelW = 40;
                labelH = 30;
                break;
            case 4:
                labelW = 45;
                labelH = 20;
                break;
            default:
                labelW = 60;
                labelH = 40;
        }
        int dotW = labelW * 8;
        int dotH = labelH * 8;
        final float sx = labelW / 60f;

        String name = str(item.get("name"));
        String size = str(item.get("size"));
        if (!size.isEmpty()) name = name + "(" + size + ")";

        double mprice1 = toDouble(item.get("mprice1"));
        double sellprice = toDouble(item.get("sellprice"));
        double packDiscount = toDouble(item.get("packDiscount"));
        double packQty = toDouble(item.get("packQty"));
        if (packQty <= 0) packQty = 1;
        double price = mprice1 > 0 ? mprice1 : sellprice;
        int qty = toInt(item.get("qty"), 1);
        String barcode = str(item.get("barcode"));

        Tspl cmd = new Tspl();
        cmd.addSize(labelW, labelH);
        cmd.addGap(gap);
        cmd.addCls();

        if (template == 4) {
            String originalPrice = "原价：" + format2(sellprice * packQty);
            String discountPriceStr = "折扣价：" + format2(sellprice);
            // packDiscount <= 0 时不打印折扣
            String discountText = "";
            if (packDiscount > 0) {
                discountText = format1(packDiscount) + "折";
            }
            appendTemplate4(cmd, dotW, name, barcode, originalPrice, discountPriceStr, discountText);
        } else {
            // 商品名称（大字体 2×；小标签降为 1×）
            int nameScale = labelH >= 40 ? 2 : 1;
            cmd.addText(fx(15, sx), Math.round(dotH * 0.05f), Tspl.FONT_TSS24, 0, nameScale, nameScale, name);

            // 折后单价（左）+ 小计（右）
            cmd.addText(fx(15, sx), Math.round(dotH * 0.22f), Tspl.FONT_TSS24, 0, 1, 1,
                    "折后单价: " + format2(price));
            cmd.addText(fx(280, sx), Math.round(dotH * 0.22f), Tspl.FONT_TSS24, 0, 1, 1,
                    "小计: " + format2(price * qty));

            // 零售价（左）+ 折扣（右）
        
            String discount = (sellprice > 0 && mprice1 > 0)
                    ? format2(mprice1 / sellprice * 100)
                    : "100.00";
            cmd.addText(fx(15, sx), Math.round(dotH * 0.37f), Tspl.FONT_TSS24, 0, 1, 1,
                    "零售价: " + format2(sellprice));
            cmd.addText(fx(280, sx), Math.round(dotH * 0.37f), Tspl.FONT_TSS24, 0, 1, 1,
                    "折扣: " + discount + "%");

            // CODE128 条码（自适应宽度，约占标签宽度的 90%）
            if (!barcode.isEmpty()) {
                int totalModules = barcode.length() * 11 + 35;
                int targetWidth = Math.round(dotW * 0.9f);
                int narrow = targetWidth / totalModules;
                narrow = Math.max(1, Math.min(narrow, 4));
                int barcodeH = Math.round(dotH * 0.25f);
                cmd.add1DBarcode(fx(15, sx), Math.round(dotH * 0.52f), Tspl.BARCODE_CODE_128,
                        barcodeH, true, Tspl.ROTATION_0, narrow, narrow, barcode);
            }
        }

        cmd.addPrint(Math.max(1, copies));
        return cmd.getBytes();
    }

    /**
     * 生成预包装改价的 TSPL 标签指令
     * 布局与小程序 prepackPrice buildLabelCommand 保持一致：
     * 名称+零售价 / 商品条码+包装数量 / 包装折扣+包装金额 / 包装条码图形
     */
    private byte[] buildPrepackLabel(Map<String, Object> item, int copies, int template) throws Exception {
        int labelW;
        int labelH;
        int gap = 2;
        switch (template) {
            case 2:
                labelW = 50;
                labelH = 30;
                break;
            case 3:
                labelW = 40;
                labelH = 30;
                break;
            case 4:
                labelW = 50;
                labelH = 20;
                break;
            default:
                labelW = 60;
                labelH = 40;
        }
        int dotW = labelW * 8;
        int dotH = labelH * 8;
        final float sx = labelW / 60f;

        String name = str(item.get("name"));
        String size = str(item.get("size")).trim();
        if (!size.isEmpty()) name = name + "(" + size + ")";

        double sellprice = toDouble(item.get("sellprice"));
        double packQty = toDouble(item.get("packQty"));
        if (packQty <= 0) packQty = 1;
        double packDiscount = toDouble(item.get("packDiscount"));
        if (packDiscount <= 0) packDiscount = 100;
        double packAmount = toDouble(item.get("packAmount"));
        String barcode = str(item.get("packBarcode"));
        if (barcode.isEmpty()) barcode = str(item.get("barcode"));

        Tspl cmd = new Tspl();
        cmd.addSize(labelW, labelH);
        cmd.addGap(gap);
        cmd.addCls();

        if (template == 4) {
            String originalPrice = "原价：" + format2(sellprice * packQty);
            String discountPriceStr = "折扣价：" + packAmount;
             String discountText = "";
            if (packDiscount > 0 && packDiscount < 100) {
                discountText = format1(packDiscount / 10) + "折";
            }
            appendTemplate4(cmd, dotW, name, barcode, originalPrice, discountPriceStr, discountText);
        } else {
            // 小尺寸标签（50mm 及以下）使用紧凑前缀，避免两列文字重叠
            boolean compact = dotW < 440;
            int leftX = fx(15, sx);
            int margin = compact ? 3 : fx(10, sx);

            // 商品名称（左） + 零售价（右）
            int y0 = Math.round(dotH * 0.05f);
            String left0 = name;
            String right0 = (compact ? "售价:" : "零售价: ") + format2(sellprice);
            int rightX0 = fitRightColumn(right0, leftX, dotW, margin);
            cmd.addText(leftX, y0, Tspl.FONT_TSS24, 0, 1, 1, left0);
            cmd.addText(rightX0, y0, Tspl.FONT_TSS24, 0, 1, 1, right0);

            // 商品条码（左） + 包装数量（右）
            int y1 = Math.round(dotH * 0.22f);
            String left1 = (compact ? "条码:" : "商品条码: ") + str(item.get("barcode"));
            String right1 = (compact ? "数量:" : "包装数量: ") + format1(packQty);
            int rightX1 = dotW - textWidth(right1) - margin;
            cmd.addText(leftX, y1, Tspl.FONT_TSS24, 0, 1, 1, left1);
            cmd.addText(rightX1, y1, Tspl.FONT_TSS24, 0, 1, 1, right1);

            // 包装折扣（左） + 包装金额（右）
            int y2 = Math.round(dotH * 0.35f);
            String left2 = (compact ? "折扣:" : "包装折扣: ") + format2(packDiscount) + "%";
            String right2 = (compact ? "金额:" : "包装金额: ") + format2(packAmount);
            int rightX2 = fitRightColumn(right2, leftX, dotW, margin);
            cmd.addText(leftX, y2, Tspl.FONT_TSS24, 0, 1, 1, left2);
            cmd.addText(rightX2, y2, Tspl.FONT_TSS24, 0, 1, 1, right2);

            // 包装条码图形（自适应宽度，约占标签宽度的 90%）
            if (!barcode.isEmpty()) {
                int totalModules = barcode.length() * 11 + 35;
                int targetWidth = Math.round(dotW * 0.9f);
                int narrow = targetWidth / totalModules;
                narrow = Math.max(1, Math.min(narrow, 4));
                int barcodeH = Math.round(dotH * 0.25f);
                cmd.add1DBarcode(fx(15, sx), Math.round(dotH * 0.6f), Tspl.BARCODE_CODE_128,
                        barcodeH, true, Tspl.ROTATION_0, narrow, narrow, barcode);
            }
        }

        cmd.addPrint(Math.max(1, copies));
        return cmd.getBytes();
    }

    private static int fx(int v, float sx) {
        return Math.round(v * sx);
    }

    /**
     * 模板 4（45/50×20mm 紧凑样式）公共布局：时间/原价/折扣 + 折扣价 + 名称 + 条码
     * buildLabel 和 buildPrepackLabel 共用，只改这一处即可
     */
    private void appendTemplate4(Tspl cmd, int dotW, String name, String barcode,
            String originalPrice, String discountPriceStr, String discountText) {
        Calendar cal = Calendar.getInstance();
        String dateTime = String.format(Locale.US, "%02d-%02d %02d:%02d",
                cal.get(Calendar.MONTH) + 1,
                cal.get(Calendar.DAY_OF_MONTH),
                cal.get(Calendar.HOUR_OF_DAY),
                cal.get(Calendar.MINUTE));

        int margin = 8;
        int dateTimeWidth = textWidth(dateTime);
        int y0 = 2;
        int y1 = 32;
        int y2 = 64;
        int barcodeY = 92;
        int barcodeH = 40;

        // Row 1: 时间(粗体) | 原价(粗体) | 折扣(逐字加大)
        cmd.addText(margin, y0, Tspl.FONT_TSS24, 0, 1, 1, dateTime);
        cmd.addText(margin + 1, y0, Tspl.FONT_TSS24, 0, 1, 1, dateTime);
        cmd.addText(margin, y0 + 1, Tspl.FONT_TSS24, 0, 1, 1, dateTime);
        cmd.addText(margin + 1, y0 + 1, Tspl.FONT_TSS24, 0, 1, 1, dateTime);
        int origPriceX = dateTimeWidth + margin * 2;
        cmd.addText(origPriceX, y0, Tspl.FONT_TSS24, 0, 1, 1, originalPrice);
        cmd.addText(origPriceX + 1, y0, Tspl.FONT_TSS24, 0, 1, 1, originalPrice);
        cmd.addText(origPriceX, y0 + 1, Tspl.FONT_TSS24, 0, 1, 1, originalPrice);
        cmd.addText(origPriceX + 1, y0 + 1, Tspl.FONT_TSS24, 0, 1, 1, originalPrice);
        if (discountText != null && !discountText.isEmpty()) {
            // 逐字绘制：数字/汉字 2×2 + 描边加粗，小数点 1×2 紧挨两侧
            int totalW = 0;
            for (int i = 0; i < discountText.length(); i++) {
                char c = discountText.charAt(i);
                totalW += (c == '.') ? 12 : (c < 128 ? 12 : 24) * 2;
            }
            int cx = Math.max(origPriceX + textWidth(originalPrice) + margin,
                    dotW - totalW - margin);
            for (int i = 0; i < discountText.length(); i++) {
                char c = discountText.charAt(i);
                String s = String.valueOf(c);
                if (c == '.') {
                    // 小数点：1×2（窄而高）
                    cmd.addText(cx, y0, Tspl.FONT_TSS24, 0, 1, 2, s);
                    cx += 12;
                } else {
                    int cw = (c < 128 ? 12 : 24) * 2;
                    // 2×2 放大 + 2像素描边加粗
                    for (int dx = 0; dx <= 1; dx++) {
                        for (int dy = 0; dy <= 1; dy++) {
                            cmd.addText(cx + dx, y0 + dy, Tspl.FONT_TSS24, 0, 2, 2, s);
                        }
                    }
                    cx += cw;
                }
            }
        }

        // Row 2: 折扣价（居中，粗体）
        int discountPriceX = Math.max(margin, (dotW - textWidth(discountPriceStr)) / 2);
        cmd.addText(discountPriceX, y1, Tspl.FONT_TSS24, 0, 1, 1, discountPriceStr);
        cmd.addText(discountPriceX + 1, y1, Tspl.FONT_TSS24, 0, 1, 1, discountPriceStr);
        cmd.addText(discountPriceX, y1 + 1, Tspl.FONT_TSS24, 0, 1, 1, discountPriceStr);
        cmd.addText(discountPriceX + 1, y1 + 1, Tspl.FONT_TSS24, 0, 1, 1, discountPriceStr);

        // Row 3: 商品名称（粗体）
        cmd.addText(margin, y2, Tspl.FONT_TSS24, 0, 1, 1, name);
        cmd.addText(margin + 1, y2, Tspl.FONT_TSS24, 0, 1, 1, name);

        // Row 4: CODE128 条码（手动绘制，精确控制宽度为标签 70%，居中放置）
        if (barcode != null && !barcode.isEmpty()) {
            int[] pattern = encodeCode128B(barcode);
            int totalModules = 0;
            for (int m : pattern) totalModules += m;
            // 目标宽度 = 标签宽度 × 70%
            int targetWidth = dotW * 7 / 10;
            int baseNarrow = Math.max(1, Math.min(6, targetWidth / totalModules));
            // 剩余 dots 均匀分配到各模块单元（Bresenham 分布）
            int remainder = targetWidth - baseNarrow * totalModules;
            if (remainder < 0) remainder = 0;
            int actualWidth = 0;
            int[] widths = new int[pattern.length];
            int cumUnits = 0;
            for (int i = 0; i < pattern.length; i++) {
                int extraUnits = 0;
                if (remainder > 0) {
                    int newCum = cumUnits + pattern[i];
                    extraUnits = newCum * remainder / totalModules - cumUnits * remainder / totalModules;
                    cumUnits = newCum;
                }
                widths[i] = baseNarrow * pattern[i] + extraUnits;
                actualWidth += widths[i];
            }
            int barcodeX = (dotW - actualWidth) / 2;
            if (barcodeX < 0) barcodeX = 0;
            // 逐条绘制
            int x = barcodeX;
            for (int i = 0; i < pattern.length; i++) {
                if (i % 2 == 0) {
                    cmd.addBar(x, barcodeY, widths[i], barcodeH);
                }
                x += widths[i];
            }
            // 条码文字居中
            int numW = textWidth(barcode);
            int textX = (dotW - numW) / 2;
            cmd.addText(textX, barcodeY + barcodeH + 2, Tspl.FONT_TSS24, 0, 1, 1, barcode);
        }
    }

    // ─── CPCL 构建器（汉印路径，布局对齐小程序三页 CPCL 版）───

    /** CPCL 指令追加（GBK 编码，中文标签必需） */
    private static void cpclCmd(ByteArrayOutputStream out, String cmd) {
        try {
            out.write(cmd.getBytes("GBK"));
        } catch (Exception e) {
            byte[] fallback = cmd.getBytes(StandardCharsets.US_ASCII);
            out.write(fallback, 0, fallback.length);
        }
    }

    /** 普通文本（TEXT font 0 x y text） */
    private static void cpclText(ByteArrayOutputStream out, String text, int x, int y, int font) {
        cpclCmd(out, "TEXT " + font + " 0 " + x + " " + y + " " + text + "\r\n");
    }

    /** 加粗文本（SETBOLD 成对，对应 TSC 版描粗） */
    private static void cpclTextBold(ByteArrayOutputStream out, String text, int x, int y, int font) {
        cpclCmd(out, "SETBOLD 1\r\n");
        cpclCmd(out, "TEXT " + font + " 0 " + x + " " + y + " " + text + "\r\n");
        cpclCmd(out, "SETBOLD 0\r\n");
    }

    /** 倍率文本（SETMAG 成对，必须复位避免污染后续指令） */
    private static void cpclTextMag(ByteArrayOutputStream out, String text, int x, int y, int font, int xMul, int yMul) {
        cpclCmd(out, "SETMAG " + xMul + " " + yMul + "\r\n");
        cpclCmd(out, "TEXT " + font + " 0 " + x + " " + y + " " + text + "\r\n");
        cpclCmd(out, "SETMAG 0 0\r\n");
    }

    /** 倍率 + 加粗文本 */
    private static void cpclTextMagBold(ByteArrayOutputStream out, String text, int x, int y, int font, int xMul, int yMul) {
        cpclCmd(out, "SETBOLD 1\r\n");
        cpclCmd(out, "SETMAG " + xMul + " " + yMul + "\r\n");
        cpclCmd(out, "TEXT " + font + " 0 " + x + " " + y + " " + text + "\r\n");
        cpclCmd(out, "SETBOLD 0\r\n");
        cpclCmd(out, "SETMAG 0 0\r\n");
    }

    /** CODE128 条码（无可读文本；可读文本需手工绘制在下方，避免与上方字段冲突） */
    private static void cpclBarcode(ByteArrayOutputStream out, String data, int x, int y, int width, int height) {
        cpclCmd(out, "BARCODE 128 " + width + " 1 " + height + " " + x + " " + y + " " + data + "\r\n");
    }

    /** 二维码（BARCODE QR 命令块） */
    private static void cpclQr(ByteArrayOutputStream out, String data, int x, int y, int ecc, int size) {
        cpclCmd(out, "BARCODE QR " + x + " " + y + " M " + ecc + " U " + size + "\r\n");
        cpclCmd(out, "MA," + data + "\r\n");
        cpclCmd(out, "ENDQR\r\n");
    }

    /** 文本宽度估算（16 点阵：ASCII 8dots，中文 16dots） */
    private static int textWidth16(String text) {
        int width = 0;
        for (int i = 0; i < text.length(); i++) {
            width += text.charAt(i) < 0x80 ? 8 : 16;
        }
        return width;
    }

    /** 右列定位的文本行（left/right 为相邻两列文本；noLeftCheck 行不参与防压字约束） */
    private static final class CpclRow {
        final String left;
        final String right;
        final boolean noLeftCheck;

        CpclRow(String left, String right) {
            this(left, right, false);
        }

        CpclRow(String left, String right, boolean noLeftCheck) {
            this.left = left;
            this.right = right;
            this.noLeftCheck = noLeftCheck;
        }
    }

    /** 右列整列定位结果（mode: normal / smallRight / allSmall） */
    private static final class CpclColumn {
        final String mode;
        final int x;

        CpclColumn(String mode, int x) {
            this.mode = mode;
            this.x = x;
        }
    }

    /** 求解右列可行区间 [lo, hi]（wl/wr 分别为左右列宽度函数选择） */
    private static int[] solveCpcl(int rightEdge, int leftX, CpclRow[] rows, boolean leftSmall, boolean rightSmall) {
        final int GAP = 12;
        int lo = 0;
        int hi = rightEdge;
        for (CpclRow r : rows) {
            if (!r.noLeftCheck) {
                int lw = leftSmall ? textWidth16(r.left) : textWidth(r.left);
                lo = Math.max(lo, leftX + lw + GAP);
            }
            int rw = rightSmall ? textWidth16(r.right) : textWidth(r.right);
            hi = Math.min(hi, rightEdge - rw);
        }
        return new int[]{lo, hi};
    }

    /**
     * 模板 1/2/3 右列整列定位（汉印，整列统一，对齐小程序 calcRightColumnCpcl）
     * 1) 默认 x0 全行 24 号；2) 右缘超界时整列左移；
     * 3) 24 号右列放不下时仅右列降 16 号（55）；仍放不下时整版降 16 号
     */
    private static CpclColumn calcRightColumnCpcl(int dotW, int x0, int leftX, CpclRow[] rows) {
        final int rightEdge = dotW - 36; // 汉印右侧不可打印区（比佳博窄），防裁切
        int[] a = solveCpcl(rightEdge, leftX, rows, false, false);
        if (a[0] <= x0 && x0 <= a[1]) return new CpclColumn("normal", x0);
        if (a[0] <= a[1]) return new CpclColumn("normal", Math.min(Math.max(x0, a[0]), a[1]));
        int[] b = solveCpcl(rightEdge, leftX, rows, false, true);
        if (b[0] <= b[1]) return new CpclColumn("smallRight", Math.min(Math.max(x0, b[0]), b[1]));
        int[] c = solveCpcl(rightEdge, leftX, rows, true, true);
        int x = c[0] <= c[1] ? Math.min(Math.max(x0, c[0]), c[1]) : Math.max(0, c[1]);
        return new CpclColumn("allSmall", x);
    }

    /**
     * 生成单个商品的 CPCL 标签指令（汉印路径，对齐小程序 printing/unprinted 页 CPCL 版）
     * 名称（2 倍，右缘放不下时降 1 倍）/ 两列数据行（整列定位降号）/ CODE128 条码
     */
    private byte[] buildLabelCpcl(Map<String, Object> item, int copies, int template) {
        int labelW;
        int labelH;
        switch (template) {
            case 2:
                labelW = 50;
                labelH = 30;
                break;
            case 3:
                labelW = 40;
                labelH = 30;
                break;
            case 4:
                labelW = 45;
                labelH = 20;
                break;
            default:
                labelW = 60;
                labelH = 40;
        }
        int dotW = labelW * 8;
        int dotH = labelH * 8;
        final float sx = labelW / 60f;

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        // 标签头：! offset 200 200 height qty（qty 即打印份数）
        cpclCmd(out, "! 0 200 200 " + dotH + " " + Math.max(1, copies) + "\r\n");

        String name = str(item.get("name"));
        String size = str(item.get("size"));
        if (!size.isEmpty()) name = name + "(" + size + ")";
        String barcode = str(item.get("barcode"));

        if (template == 4) {
            double sellprice = toDouble(item.get("sellprice"));
            double mprice1 = toDouble(item.get("mprice1"));
            int qty = toInt(item.get("qty"), 1);
            if (qty <= 0) qty = 1;
            double price = mprice1 > 0 ? mprice1 : sellprice;
            String originalPrice = "原价：" + format2(sellprice * qty);
            String discountPriceStr = "折扣价：" + format2(price);
            String discountText = "";
            double discountVal = sellprice > 0 && mprice1 > 0 ? (mprice1 / sellprice) * 100 : 0;
            if (discountVal > 0 && discountVal < 100) {
                discountText = format1(discountVal / 10) + "折";
            }
            appendTemplate4Cpcl(out, dotW, name, barcode, originalPrice, discountPriceStr, discountText);
        } else {
            int nameScale = labelH >= 40 ? 2 : 1;
            double mprice = toDouble(item.get("mprice1"));
            double sellprice = toDouble(item.get("sellprice"));
            int qty = toInt(item.get("qty"), 1);
            if (qty <= 0) qty = 1;
            double price = mprice > 0 ? mprice : sellprice;
            String priceLine = "折后单价: " + format2(price);
            String subtotalLine = "小计: " + format2(price * qty);
            String retailLine = "零售价: " + format2(sellprice);
            String discountLine = "折扣: "
                    + (sellprice > 0 && mprice > 0 ? format1(mprice / sellprice * 100) : "100.0") + "%";
            // 名称与佳博一致按 2 倍放大（高≥40mm 模板）；汉印右缘放不下 2 倍时降为 1 倍防长名称被裁
            int rightEdge = dotW - 36;
            int nameW = textWidth(name) * nameScale;
            int ns = nameScale == 2 && fx(15, sx) + nameW > rightEdge ? 1 : nameScale;
            cpclTextMag(out, name, fx(15, sx), Math.round(dotH * 0.05f), CPCL_FONT, ns, ns);
            // 右列整列统一定位（默认 fx(280)；必要时整列左移；24 号放不下时先降右列 16 号、再整版降号）
            CpclColumn rc = calcRightColumnCpcl(dotW, fx(280, sx), fx(15, sx), new CpclRow[]{
                    new CpclRow(priceLine, subtotalLine),
                    new CpclRow(retailLine, discountLine)
            });
            int leftFont = "allSmall".equals(rc.mode) ? CPCL_FONT_SMALL : CPCL_FONT;
            int rightFont = "normal".equals(rc.mode) ? CPCL_FONT : CPCL_FONT_SMALL;
            cpclText(out, priceLine, fx(15, sx), Math.round(dotH * 0.22f), leftFont);
            cpclText(out, subtotalLine, rc.x, Math.round(dotH * 0.22f), rightFont);
            cpclText(out, retailLine, fx(15, sx), Math.round(dotH * 0.37f), leftFont);
            cpclText(out, discountLine, rc.x, Math.round(dotH * 0.37f), rightFont);
            if (!barcode.isEmpty()) {
                // 条码宽度估算与 TSC 版一致（总模块数 ≈ 数据位数 × 11 + 35），右缘不超 rightEdge
                int totalModules = barcode.length() * 11 + 35;
                int barcodeX = fx(15, sx);
                int targetWidth = rightEdge - barcodeX;
                int narrow = Math.max(1, Math.min(targetWidth / totalModules, 4));
                int barcodeH = Math.round(dotH * 0.25f);
                int barcodeY = Math.round(dotH * 0.52f);
                cpclBarcode(out, barcode, barcodeX, barcodeY, narrow, barcodeH);
                // 可读文本手工绘制在条码下方（CPCL 默认绘制在条码上方，会与上方字段冲突）
                cpclText(out, barcode, barcodeX, barcodeY + barcodeH + 2, CPCL_FONT);
            }
        }

        // 标签定位 + 打印（官方 demo 流程：FORM 定位当前标签，PRINT 触发打印）
        cpclCmd(out, "FORM\r\n");
        cpclCmd(out, "PRINT\r\n");
        return out.toByteArray();
    }

    /**
     * 生成预包装改价的 CPCL 标签指令（汉印路径，对齐小程序 prepackPrice 页 CPCL 版）
     * 名称+零售价（noLeftCheck）/ 商品条码+包装数量 / 包装折扣+包装金额 / 包装条码图形
     */
    private byte[] buildPrepackLabelCpcl(Map<String, Object> item, int copies, int template) {
        int labelW;
        int labelH;
        switch (template) {
            case 2:
                labelW = 50;
                labelH = 30;
                break;
            case 3:
                labelW = 40;
                labelH = 30;
                break;
            case 4:
                labelW = 50;
                labelH = 20;
                break;
            default:
                labelW = 60;
                labelH = 40;
        }
        int dotW = labelW * 8;
        int dotH = labelH * 8;
        final float sx = labelW / 60f;

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        cpclCmd(out, "! 0 200 200 " + dotH + " " + Math.max(1, copies) + "\r\n");

        String name = str(item.get("name"));
        String size = str(item.get("size")).trim();
        if (!size.isEmpty()) name = name + "(" + size + ")";
        String barcode = str(item.get("packBarcode"));
        if (barcode.isEmpty()) barcode = str(item.get("barcode"));

        double sellprice = toDouble(item.get("sellprice"));
        double packQty = toDouble(item.get("packQty"));
        if (packQty <= 0) packQty = 1;
        double packDiscount = toDouble(item.get("packDiscount"));
        if (packDiscount <= 0) packDiscount = 100;
        double packAmount = toDouble(item.get("packAmount"));

        if (template == 4) {
            String originalPrice = "原价：" + format2(sellprice * packQty);
            String discountPriceStr = "折扣价：" + format2(packAmount);
            String discountText = "";
            if (packDiscount > 0 && packDiscount < 100) {
                discountText = format1(packDiscount / 10) + "折";
            }
            appendTemplate4Cpcl(out, dotW, name, barcode, originalPrice, discountPriceStr, discountText);
        } else {
            String barcodeLine = "商品条码: " + str(item.get("barcode"));
            String discountLine = "包装折扣: " + format2(packDiscount) + "%";
            String sellPriceText = "零售价: " + format2(sellprice);
            String packQtyText = "包装数量: " + format1(packQty);
            String packAmountText = "包装金额: " + format2(packAmount);
            int rightEdge = dotW - 36;
            // 名称行 noLeftCheck（长名称不参与防压字约束），数据行参与
            CpclColumn rc = calcRightColumnCpcl(dotW, fx(280, sx), fx(15, sx), new CpclRow[]{
                    new CpclRow(name, sellPriceText, true),
                    new CpclRow(barcodeLine, packQtyText),
                    new CpclRow(discountLine, packAmountText)
            });
            int leftFont = "allSmall".equals(rc.mode) ? CPCL_FONT_SMALL : CPCL_FONT;
            int rightFont = "normal".equals(rc.mode) ? CPCL_FONT : CPCL_FONT_SMALL;
            cpclText(out, name, fx(15, sx), Math.round(dotH * 0.05f), CPCL_FONT);
            cpclText(out, sellPriceText, rc.x, Math.round(dotH * 0.05f), rightFont);
            cpclText(out, barcodeLine, fx(15, sx), Math.round(dotH * 0.22f), leftFont);
            cpclText(out, packQtyText, rc.x, Math.round(dotH * 0.22f), rightFont);
            cpclText(out, discountLine, fx(15, sx), Math.round(dotH * 0.35f), leftFont);
            cpclText(out, packAmountText, rc.x, Math.round(dotH * 0.35f), rightFont);
            if (!barcode.isEmpty()) {
                int totalModules = barcode.length() * 11 + 35;
                int barcodeX = fx(15, sx);
                int targetWidth = rightEdge - barcodeX;
                int narrow = Math.max(1, Math.min(targetWidth / totalModules, 4));
                int barcodeH = Math.round(dotH * 0.25f);
                int barcodeY = Math.round(dotH * 0.6f);
                cpclBarcode(out, barcode, barcodeX, barcodeY, narrow, barcodeH);
                cpclText(out, barcode, barcodeX, barcodeY + barcodeH + 2, CPCL_FONT);
            }
        }

        cpclCmd(out, "FORM\r\n");
        cpclCmd(out, "PRINT\r\n");
        return out.toByteArray();
    }

    /**
     * 模板 4（45/50×20mm）CPCL 版公共布局：时间/原价/折扣 + 折扣价 + 名称 + 条码
     * 对应小程序 printing/prepackPrice 页 appendTemplate4Cpcl；加粗用 CPCL 原生 SETBOLD
     */
    private static void appendTemplate4Cpcl(ByteArrayOutputStream out, int dotW, String name, String barcode,
            String originalPrice, String discountPriceStr, String discountText) {
        Calendar cal = Calendar.getInstance();
        String dateTime = String.format(Locale.US, "%02d-%02d %02d:%02d",
                cal.get(Calendar.MONTH) + 1,
                cal.get(Calendar.DAY_OF_MONTH),
                cal.get(Calendar.HOUR_OF_DAY),
                cal.get(Calendar.MINUTE));

        int margin = 8;
        int dateTimeWidth = textWidth(dateTime);
        int y0 = 2;
        int y1 = 32;
        int y2 = 64;
        int barcodeY = 92;
        int barcodeH = 40;

        // Row 1: 时间（粗体）| 原价（粗体）| 折扣（逐字放大，小数点仅纵向放大不加粗）
        cpclTextBold(out, dateTime, margin, y0, CPCL_FONT);
        int origPriceX = dateTimeWidth + margin * 2;
        cpclTextBold(out, originalPrice, origPriceX, y0, CPCL_FONT);
        if (discountText != null && !discountText.isEmpty()) {
            int totalW = 0;
            for (int i = 0; i < discountText.length(); i++) {
                char c = discountText.charAt(i);
                totalW += c == '.' ? 12 : (c < 128 ? 12 : 24) * 2;
            }
            int cx = Math.max(origPriceX + textWidth(originalPrice) + margin,
                    dotW - totalW - margin);
            for (int i = 0; i < discountText.length(); i++) {
                char c = discountText.charAt(i);
                String s = String.valueOf(c);
                if (c == '.') {
                    cpclTextMag(out, s, cx, y0, CPCL_FONT, 1, 2);
                    cx += 12;
                } else {
                    int cw = (c < 128 ? 12 : 24) * 2;
                    cpclTextMagBold(out, s, cx, y0, CPCL_FONT, 2, 2);
                    cx += cw;
                }
            }
        }

        // Row 2: 折扣价（居中，粗体）
        int discountPriceX = Math.max(margin, (dotW - textWidth(discountPriceStr)) / 2);
        cpclTextBold(out, discountPriceStr, discountPriceX, y1, CPCL_FONT);

        // Row 3: 商品名称（粗体）
        cpclTextBold(out, name, margin, y2, CPCL_FONT);

        // Row 4: CODE128 条码（宽度约标签 70%，居中；文字居中于条码下方）
        if (barcode != null && !barcode.isEmpty()) {
            int[] pattern = encodeCode128B(barcode);
            int totalModules = 0;
            for (int m : pattern) totalModules += m;
            int targetWidth = dotW * 7 / 10;
            int width = Math.max(1, Math.min(4, targetWidth / totalModules));
            int actualWidth = width * totalModules;
            int barcodeX = Math.max(0, (dotW - actualWidth) / 2);
            cpclBarcode(out, barcode, barcodeX, barcodeY, width, barcodeH);
            int numW = textWidth(barcode);
            cpclText(out, barcode, (dotW - numW) / 2, barcodeY + barcodeH + 2, CPCL_FONT);
        }
    }

    /** 测试标签 CPCL 指令（汉印路径，58×30mm，对齐小程序 bluetooth.vue renderTestLabelCpcl） */
    private byte[] buildTestLabelCpcl() {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        int dotW = 456; // 58mm ≈ 456 dots @200dpi
        int dotH = 236; // 30mm ≈ 236 dots @200dpi

        cpclCmd(out, "! 0 200 200 " + dotH + " 1\r\n");
        // 外边框（预留 8 dots 边距）
        cpclCmd(out, "BOX 8 8 " + (dotW - 8) + " " + (dotH - 8) + " 2\r\n");
        // 标题栏分隔线
        cpclCmd(out, "LINE 8 76 " + (dotW - 8) + " 76 2\r\n");
        // 标题：手工计算居中（x = (456 - 4字×24点×2倍) / 2 = 132），不依赖 CENTER 命令
        cpclTextMag(out, "测试标签", 132, 10, CPCL_FONT, 2, 2);
        // 商品信息（左对齐，宽度控制在竖线左侧）
        cpclText(out, "名称：蓝牙打印机", 20, 88, CPCL_FONT);
        // 条码（含可读文本，绘制在条码下方）
        cpclCmd(out, "BARCODE-TEXT 7 0 2\r\n");
        cpclBarcode(out, "12345678", 20, 126, 2, 32);
        cpclCmd(out, "BARCODE-TEXT OFF\r\n");
        // 竖向分隔线（位于文字区右侧，不与任何元素交叉）
        cpclCmd(out, "LINE 296 84 296 224 2\r\n");
        // 二维码（右侧区域，与竖线保持间距）
        cpclQr(out, "https://test.example.com", 316, 84, 2, 4);

        cpclCmd(out, "FORM\r\n");
        cpclCmd(out, "PRINT\r\n");
        return out.toByteArray();
    }

    /**
     * CODE128B 编码：返回交替条/空宽度数组（条、空、条、空...）
     * 包含起始符(Start B=104) + 数据 + 校验符 + 终止符(Stop=106)
     */
    private static int[] encodeCode128B(String data) {
        // CODE128B 模式表：每个字符 6 个模块宽度（条、空、条、空、条、空）
        int[][] patterns = {
            {2,1,2,2,2,2},{2,2,2,1,2,2},{2,2,2,2,2,1},{1,2,1,2,2,3},{1,2,1,3,2,2},
            {1,3,1,2,2,2},{1,2,2,2,1,3},{1,2,2,3,1,2},{1,3,2,2,1,2},{2,2,1,2,1,3},
            {2,2,1,3,1,2},{2,3,1,2,1,2},{1,1,2,2,3,2},{1,2,2,1,3,2},{1,2,2,2,3,1},
            {1,1,3,2,2,2},{1,2,3,1,2,2},{1,2,3,2,2,1},{2,2,3,2,1,1},{2,2,1,1,3,2},
            {2,2,1,2,3,1},{2,1,3,2,1,2},{2,2,3,1,1,2},{3,1,2,1,3,1},{3,1,1,2,2,2},
            {3,2,1,1,2,2},{3,2,1,2,2,1},{3,1,2,2,1,2},{3,2,2,1,1,2},{3,2,2,2,1,1},
            {2,1,2,1,2,3},{2,1,2,3,2,1},{2,3,2,1,2,1},{1,1,1,3,2,3},{1,3,1,1,2,3},
            {1,3,1,3,2,1},{1,1,2,3,1,3},{1,3,2,1,1,3},{1,3,2,3,1,1},{2,1,1,3,1,3},
            {2,3,1,1,1,3},{2,3,1,3,1,1},{1,1,2,1,3,3},{1,1,2,3,3,1},{1,3,2,1,3,1},
            {1,1,3,1,2,3},{1,1,3,3,2,1},{1,3,3,1,2,1},{3,1,3,1,2,1},{2,1,1,3,3,1},
            {2,3,1,1,3,1},{2,1,3,1,1,3},{2,1,3,3,1,1},{2,1,3,1,3,1},{3,1,1,1,2,3},
            {3,1,1,3,2,1},{3,3,1,1,2,1},{3,1,2,1,1,3},{3,1,2,3,1,1},{3,3,2,1,1,1},
            {3,1,4,1,1,1},{2,2,1,4,1,1},{4,3,1,1,1,1},{1,1,1,2,2,4},{1,1,1,4,2,2},
            {1,2,1,1,2,4},{1,2,1,4,2,1},{1,4,1,1,2,2},{1,4,1,2,2,1},{1,1,2,2,1,4},
            {1,1,2,4,1,2},{1,2,2,1,1,4},{1,2,2,4,1,1},{1,4,2,1,1,2},{1,4,2,2,1,1},
            {2,4,1,2,1,1},{2,2,1,1,1,4},{4,1,3,1,1,1},{2,4,1,1,1,2},{1,3,4,1,1,1},
            {1,1,1,2,4,2},{1,2,1,1,4,2},{1,2,1,2,4,1},{1,1,4,2,1,2},{1,2,4,1,1,2},
            {1,2,4,2,1,1},{4,1,1,2,1,2},{4,2,1,1,1,2},{4,2,1,2,1,1},{2,1,2,1,4,1},
            {2,1,4,1,2,1},{4,1,2,1,2,1},{1,1,1,1,4,3},{1,1,1,3,4,1},{1,3,1,1,4,1},
            {1,1,4,1,1,3},{1,1,4,3,1,1},{4,1,1,1,1,3},{4,1,1,3,1,1},{1,1,3,1,4,1},
            {1,1,4,1,3,1},{3,1,1,1,4,1},{4,1,1,1,3,1},{2,1,1,4,1,2},{2,1,1,2,1,4},
            {2,1,1,2,3,2}
        };
        int[] stop = {2,3,3,1,1,1,2}; // Stop pattern (7 modules)

        int len = data.length();
        int[] values = new int[len + 3]; // start + data + checksum + stop
        values[0] = 104; // Start B
        int checksum = 104; // start code weighted
        for (int i = 0; i < len; i++) {
            int v = data.charAt(i) - 32;
            if (v < 0) v = 0;
            if (v > 95) v = 95;
            values[i + 1] = v;
            checksum += v * (i + 1);
        }
        values[len + 1] = checksum % 103;
        values[len + 2] = 106; // Stop

        // Convert to flat module array
        int totalBars = (len + 3) * 6 + 1; // +1 for stop extra bar
        int[] result = new int[totalBars];
        int idx = 0;
        for (int i = 0; i < len + 3; i++) {
            int v = values[i];
            int[] p = (v == 106) ? stop : patterns[v];
            for (int m : p) {
                result[idx++] = m;
            }
        }
        // Trim to actual size
        int[] trimmed = new int[idx];
        System.arraycopy(result, 0, trimmed, 0, idx);
        return trimmed;
    }

    /**
     * 估算 TSS24 字体 1×1 缩放下的文本宽度（ASCII≈12点，中文≈24点）
     */
    private static int textWidth(String text) {
        int width = 0;
        for (int i = 0; i < text.length(); i++) {
            width += text.charAt(i) < 0x80 ? 12 : 24;
        }
        return width;
    }

    /**
     * 计算右列起始 x：靠标签右缘对齐（空间不足时不做处理，保持完整展示）
     */
    private static int fitRightColumn(String right, int leftX, int dotW, int margin) {
        return Math.max(leftX, dotW - textWidth(right) - margin);
    }

    private static String format2(double value) {
        return String.format(Locale.US, "%.2f", value);
    }

    private static String format1(double value) {
        return String.format(Locale.US, "%.1f", value);
    }

    private static String str(Object value) {
        return value == null ? "" : value.toString();
    }

    private static int toInt(Object value, int def) {
        try {
            if (value == null) return def;
            if (value instanceof Number) return ((Number) value).intValue();
            return (int) Double.parseDouble(value.toString());
        } catch (Exception e) {
            return def;
        }
    }

    private static double toDouble(Object value) {
        try {
            if (value == null) return 0;
            if (value instanceof Number) return ((Number) value).doubleValue();
            String s = value.toString();
            if (s.isEmpty()) return 0;
            return Double.parseDouble(s);
        } catch (Exception e) {
            return 0;
        }
    }
}
