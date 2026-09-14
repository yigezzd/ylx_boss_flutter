import 'package:flutter/services.dart';

/// 蓝牙打印机设备
class GPrinterDevice {
  const GPrinterDevice({required this.name, required this.mac});

  /// 打印机名称
  final String name;

  /// 蓝牙 MAC 地址
  final String mac;
}

/// 佳博蓝牙标签打印（Android 原生 MethodChannel，基于佳博 SDK2）
///
/// 标签内容与小程序 blePrintLabels 保持一致：
/// 商品名称 / 折后单价 / 小计 / 零售价 / 折扣 / CODE128 条码
class GPrinter {
  GPrinter._();

  static const MethodChannel _channel = MethodChannel('com.weilu.deer/gprinter');

  /// 请求蓝牙相关运行时权限（返回是否全部授权）
  static Future<bool> requestPermissions() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestPermissions');
      return res ?? false;
    } on MissingPluginException {
      return true;
    }
  }

  /// 系统蓝牙是否已开启
  static Future<bool> get isBluetoothEnabled async {
    try {
      final res = await _channel.invokeMethod<bool>('isBluetoothEnabled');
      return res ?? false;
    } on MissingPluginException {
      return true;
    }
  }

  ///
  /// 开启系统蓝牙
  ///
  /// Android 13 以下弹出系统一键开启弹窗；Android 13+ 跳转系统蓝牙设置页。
  /// 返回操作后蓝牙是否已开启（跳设置页场景需用户手动开启后才会为 true）。
  ///
  static Future<bool> enableBluetooth() async {
    final res = await _channel.invokeMethod<bool>('enableBluetooth');
    return res ?? false;
  }

  /// 扫描蓝牙打印机（默认 10 秒）
  static Future<List<GPrinterDevice>> scanPrinters({int timeout = 10000}) async {
    final res = await _channel.invokeMethod<List<dynamic>>(
      'scanPrinters',
      {'timeout': timeout},
    );
    return (res ?? []).map((e) {
      final device = e as Map;
      return GPrinterDevice(
        name: device['name']?.toString() ?? '',
        mac: device['mac']?.toString() ?? '',
      );
    }).toList();
  }

  /// 连接指定 MAC 的蓝牙打印机
  static Future<bool> connect(String mac) async {
    final res = await _channel.invokeMethod<bool>('connect', {'mac': mac});
    return res ?? false;
  }

  /// 断开当前打印机连接
  static Future<void> disconnect() async {
    await _channel.invokeMethod<void>('disconnect');
  }

  /// 是否已连接打印机
  static Future<bool> get isConnected async {
    final res = await _channel.invokeMethod<bool>('isConnected');
    return res ?? false;
  }

  ///
  /// 打印标签
  ///
  /// [items] 每条明细需包含 name/size/mprice1/sellprice/qty/barcode/copies
  /// [template] 模板：1=60×40mm，2=50×30mm，3=40×30mm，4=45×20mm
  ///
  static Future<int> printLabels(
    List<Map<String, dynamic>> items, {
    int template = 1,
  }) async {
    final res = await _channel.invokeMethod<int>(
      'printLabels',
      {'items': items, 'template': template},
    );
    return res ?? 0;
  }

  ///
  /// 打印预包装改价标签
  ///
  /// [items] 每条明细需包含 name/size/barcode/sellprice/packQty/packAmount/packDiscount/packBarcode/copies
  /// [template] 模板：1=60×40mm，2=50×30mm，3=40×30mm，4=45×20mm
  ///
  static Future<int> printPrepackLabels(
    List<Map<String, dynamic>> items, {
    int template = 1,
  }) async {
    final res = await _channel.invokeMethod<int>(
      'printPrepackLabels',
      {'items': items, 'template': template},
    );
    return res ?? 0;
  }

  /// 打印测试标签（打印机设置页验证连接用，58×30mm）
  static Future<void> printTestLabel() async {
    await _channel.invokeMethod<void>('printTestLabel');
  }
}
