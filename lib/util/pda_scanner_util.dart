import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PDA 硬件扫描枪工具类
///
/// 通过 EventChannel 监听 Android PDA 设备（商米、优博音、新大陆等）的硬件扫描广播，
/// 将条码数据以 Stream 方式暴露给 Flutter 层使用。
///
/// 使用方式：
/// ```dart
/// final scanner = PdaScannerUtil();
/// scanner.startListening((barcode) {
///   print('扫描到: $barcode');
/// });
/// // 不再使用时
/// scanner.stopListening();
/// ```
class PdaScannerUtil {
  static const EventChannel _eventChannel =
      EventChannel('com.weilu.deer/pda_scanner');

  StreamSubscription<dynamic>? _subscription;

  /// 当前是否正在监听
  bool get isListening => _subscription != null;

  /// 开始监听 PDA 扫描事件
  ///
  /// [onBarcode] 扫描到条码时的回调，参数为条码字符串
  /// [onError] 发生错误时的回调（可选）
  void startListening(
    void Function(String barcode) onBarcode, {
    void Function(Object error)? onError,
  }) {
    stopListening();
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final barcode = event?.toString().trim() ?? '';
        if (barcode.isNotEmpty) {
          onBarcode(barcode);
        }
      },
      onError: (Object error) {
        debugPrint('PDA 扫描监听错误: $error');
        onError?.call(error);
      },
    );
    debugPrint('PDA 扫描监听已启动');
  }

  /// 停止监听
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// 释放资源
  void dispose() {
    stopListening();
  }

  /// 当前平台是否支持 PDA 扫描（仅 Android 支持）
  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
