import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_deer/res/constant.dart';

/// https://medium.com/gskinner-team/flutter-simplify-platform-screen-size-detection-4cb6fc4f7ed1
class Device {
  static bool get isMobile => isAndroid || isIOS;
  static bool get isWeb => kIsWeb;

  static bool get isAndroid => !isWeb && Platform.isAndroid;
  static bool get isIOS => !isWeb && Platform.isIOS;

  static late AndroidDeviceInfo _androidInfo;
  static late IosDeviceInfo _iosInfo;
  static late WebBrowserInfo _webInfo;

  static Future<void> initDeviceInfo() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (isWeb) {
      _webInfo = await deviceInfo.webBrowserInfo;
    } else if (isAndroid) {
      _androidInfo = await deviceInfo.androidInfo;
    } else if (isIOS) {
      _iosInfo = await deviceInfo.iosInfo;
    }
  }

  /// 使用前记得初始化
  static int getAndroidSdkInt() {
    if (Constant.isDriverTest) {
      return -1;
    }
    if (isAndroid) {
      return _androidInfo.version.sdkInt;
    } else {
      return -1;
    }
  }

  /// 获取设备唯一标识（machserial）
  /// - Android: 使用 serialNumber（Build.SERIAL），降级用 id（Build.ID）
  /// - iOS: 使用 identifierForVendor
  /// - Web: 使用 userAgent 作为标识
  static String getDeviceSerial() {
    if (Constant.isDriverTest) return '';
    try {
      if (isWeb) {
        return _webInfo.userAgent ?? '';
      } else if (isAndroid) {
        final serial = _androidInfo.serialNumber;
        // Android 10+ 无 READ_PHONE_STATE 权限时 serialNumber 为 "unknown"
        if (serial.isNotEmpty && serial.toLowerCase() != 'unknown') {
          return serial;
        }
        return _androidInfo.id;
      } else if (isIOS) {
        return _iosInfo.identifierForVendor ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// 获取设备名称（clientName）
  /// - Android: brand + model
  /// - iOS: name
  /// - Web: 从 userAgent 解析浏览器名称
  static String getDeviceName() {
    if (Constant.isDriverTest) return 'Test';
    try {
      if (isWeb) {
        final ua = _webInfo.userAgent ?? '';
        return _parseBrowserName(ua);
      } else if (isAndroid) {
        final brand = _androidInfo.brand;
        final model = _androidInfo.model;
        return '$brand $model';
      } else if (isIOS) {
        return _iosInfo.name;
      }
    } catch (_) {}
    return 'Unknown';
  }

  /// 从 UserAgent 字符串中解析浏览器名称
  static String _parseBrowserName(String ua) {
    if (ua.isEmpty) return 'Web Browser';
    if (ua.contains('Edg/')) return 'Microsoft Edge';
    if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
    if (ua.contains('Chrome/')) return 'Google Chrome';
    if (ua.contains('Firefox/')) return 'Mozilla Firefox';
    if (ua.contains('Safari/') && !ua.contains('Chrome')) return 'Safari';
    return 'Web Browser';
  }
}
