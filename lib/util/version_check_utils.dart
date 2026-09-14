import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/home/widgets/app_update_dialog.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sp_util/sp_util.dart';

/// 版本检查更新工具类
///
/// 支持两个调用场景：
/// 1. 应用启动时（用户未登录，operid/opername/account 为空）
/// 2. 个人中心"检查更新"（用户已登录，可获取完整信息）
class VersionCheckUtils {
  VersionCheckUtils._();

  /// 构建时通过 --dart-define=FULL_VERSION 注入的完整版本号（保留前导零）
  static const _kFullVersion = String.fromEnvironment('FULL_VERSION');

  /// 获取当前应用版本号
  static Future<String> _getAppVersion() async {
    if (_kFullVersion.isNotEmpty) {
      return _kFullVersion;
    }
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber;
    return build.isNotEmpty ? '${info.version}.$build' : info.version;
  }

  /// 从本地缓存中读取用户/商户信息
  static Map<String, String> _getUserInfo() {
    String operid = '';
    String opername = '';
    String account = '';

    try {
      final userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final userMap = jsonDecode(userStr) as Map<String, dynamic>;
        operid = userMap['userid']?.toString() ?? userMap['operid']?.toString() ?? '';
        opername = userMap['name']?.toString() ?? userMap['opername']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        account = storeMap['account']?.toString() ?? '';
      }
    } catch (_) {}

    return {
      'operid': operid,
      'opername': opername,
      'account': account,
    };
  }

  /// 执行版本检查
  ///
  /// [context] 用于显示更新弹窗的 BuildContext，若为 null 则使用全局 navigatorKey
  /// [silent] 静默模式（启动时使用），接口异常时不弹错误提示
  static Future<void> checkUpdate({
    BuildContext? context,
    bool silent = false,
  }) async {
    final ctx = context ?? _getNavigatorContext();
    if (ctx == null) {
      debugPrint('⚠️ VersionCheckUtils: 无法获取 BuildContext，跳过版本检查');
      return;
    }

    try {
      // 1. 获取应用版本号
      final String vcode = await _getAppVersion();

      // 2. 获取设备信息（需确保 Device.initDeviceInfo() 已调用）
      final String machserial = Device.getDeviceSerial();
      final String clientName = Device.getDeviceName();

      // 3. 获取用户/商户信息（未登录时为空）
      final userInfo = _getUserInfo();

      // 4. 构建请求参数
      final params = <String, dynamic>{
        'appid': '10000',
        'clienttype': '9',
        'vcode': vcode.replaceAll('.', ''),
        'machserial': machserial,
        'machserialnew': machserial,
        'clientName': clientName,
        'operid': userInfo['operid'] ?? '',
        'opername': userInfo['opername'] ?? '',
        'account': userInfo['account'] ?? '',
        'oemid': '',
      };

      // 5. 调用接口
      final result = await request(
        HttpApi.appCheckVersion,
        params,
        false, // showLoading
        !silent, // showError（静默模式不弹错误）
      );

      // 6. 解析响应 —— data 可能是数组 [{...}] 或 Map {...}
      final rawData = result['data'];
      if (rawData == null || (rawData is List && rawData.isEmpty)) {
        if (!silent) Toast.show('当前已是最新版本');
        return;
      }

      final Map<String, dynamic> versionInfo = rawData is List
          ? (rawData.first as Map<String, dynamic>)
          : (rawData is Map<String, dynamic> ? rawData : {});

      // 兼容多种字段名（优先匹配服务端实际字段 appver / allupdateinfo / updateaddress）
      final String newVersion = versionInfo['appver']?.toString() ??
          versionInfo['version']?.toString() ??
          versionInfo['newVersion']?.toString() ??
          versionInfo['vcode']?.toString() ??
          '';

      // 后端 appver 为去点后的纯数字（如 101105），按当前版本段位还原为点分格式显示（如 1.0.1.105）
      final String displayVersion = _formatVersionDisplay(newVersion, vcode);

      // allupdateinfo 格式示例："v1.0.1.101 20260630 # #1、首次发包"
      // 提取 "#" 分隔后的描述部分，若无法解析则回退到原始值
      String updateDesc = '';
      final String rawUpdateInfo = versionInfo['allupdateinfo']?.toString() ??
          versionInfo['updateinfo']?.toString() ??
          versionInfo['updateDesc']?.toString() ??
          versionInfo['description']?.toString() ??
          versionInfo['memo']?.toString() ??
          versionInfo['remark']?.toString() ??
          '';
      if (rawUpdateInfo.contains('#')) {
        final parts = rawUpdateInfo.split('#');
        // 取 "#" 后面的部分作为更新描述
        final descParts = parts.skip(1).where((s) => s.trim().isNotEmpty);
        updateDesc = descParts.join('\n').trim();
      }
      if (updateDesc.isEmpty) {
        updateDesc = rawUpdateInfo.isNotEmpty ? rawUpdateInfo : '修复了若干问题，优化了使用体验。';
      }

      final String downloadUrl = versionInfo['updateaddress']?.toString() ??
          versionInfo['downloadUrl']?.toString() ??
          versionInfo['url']?.toString() ??
          versionInfo['apkUrl']?.toString() ??
          versionInfo['updateUrl']?.toString() ??
          '';

      final String updateTime = versionInfo['updatetime']?.toString() ?? '';

      final String cname = versionInfo['cname']?.toString() ?? '';

      final bool forceUpdate = versionInfo['forceupdate'] == true ||
          versionInfo['forceupdate'] == 1 ||
          versionInfo['forceUpdate'] == true ||
          versionInfo['forceUpdate'] == 1 ||
          versionInfo['isForce'] == true ||
          versionInfo['isForce'] == 1;

      if (newVersion.isEmpty || downloadUrl.isEmpty) {
        if (!silent) Toast.show('当前已是最新版本');
        return;
      }

      // 7. 版本号比较
      if (_isNewerVersion(vcode, newVersion)) {
        if (!ctx.mounted) return;
        showDialog<void>(
          context: ctx,
          barrierDismissible: !forceUpdate,
          builder: (_) => AppUpdateDialog(
            newVersion: displayVersion,
            updateDesc: updateDesc,
            downloadUrl: downloadUrl,
            forceUpdate: forceUpdate,
            updateTime: updateTime,
            cname: cname,
          ),
        );
      } else {
        if (!silent) Toast.show('当前已是最新版本');
      }
    } catch (_) {
      // 静默模式下忽略异常；非静默模式由 http_helper 已 Toast 提示
    }
  }

  /// 获取全局 navigator 的 context
  static BuildContext? _getNavigatorContext() {
    // 延迟导入避免循环依赖
    try {
      // ignore: depend_on_referenced_packages
      final navigatorState = _navigatorKey?.currentState;
      if (navigatorState != null && navigatorState.mounted) {
        return navigatorState.context;
      }
    } catch (_) {}
    return null;
  }

  /// 全局 navigator key 引用（通过 setNavigatorKey 注入）
  static GlobalKey<NavigatorState>? _navigatorKey;

  /// 注入全局 navigatorKey（在 main.dart 中调用）
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// 将后端返回的纯数字版本号还原为点分格式（如 101105 -> 1.0.1.105）
  ///
  /// 后端 appver 是 vcode 去掉 "." 后的值，按当前版本各段的位数切分还原；
  /// 若已包含 "." 或长度不匹配，则直接返回原值。
  static String _formatVersionDisplay(String newVersion, String currentVersion) {
    if (newVersion.contains('.')) return newVersion;
    final segLens = currentVersion.split('.').map((s) => s.length).toList();
    if (segLens.isEmpty) return newVersion;
    final totalLen = segLens.fold<int>(0, (sum, len) => sum + len);
    if (totalLen != newVersion.length) return newVersion;
    final sb = StringBuffer();
    var pos = 0;
    for (var i = 0; i < segLens.length; i++) {
      if (i > 0) sb.write('.');
      sb.write(newVersion.substring(pos, pos + segLens[i]));
      pos += segLens[i];
    }
    return sb.toString();
  }

  /// 比较版本号：target > current 返回 true
  static bool _isNewerVersion(String current, String target) {
    final List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final List<int> targetParts = target.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final int maxLen =
        currentParts.length > targetParts.length ? currentParts.length : targetParts.length;

    for (int i = 0; i < maxLen; i++) {
      final int c = i < currentParts.length ? currentParts[i] : 0;
      final int t = i < targetParts.length ? targetParts[i] : 0;
      if (t > c) return true;
      if (t < c) return false;
    }
    return false;
  }
}
