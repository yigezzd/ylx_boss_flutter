import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:sp_util/sp_util.dart';

/// 登录相关数据刷新工具 —— 对齐 boss 项目 App.vue onLaunch（57-84 行）
///
/// 调用时机：首页 [HomePage] 启动后（与 PermissionUtils.fetchRoleInfoRetMap 同一链路），
/// App 运行期间仅执行一次（对齐 Vue onLaunch 语义，静态标记防重复）。
///
/// Vue 端行为：
/// 1. 启动时若已登录（存在 token），调用 getParamsList
///    （实际请求 /updateEmployeeStorePermission 接口，custom.indata = true 解包 data）；
/// 2. 接口返回 data 中若存在 user / store / rolemap，则以接口数据为准覆盖缓存；
/// 3. 参数部分优先取 loginParamResp 字段，否则取其余参数；
/// 4. 将一级嵌套对象解构合并到顶层（与登录页处理保持一致）；
/// 5. 与缓存的 loginParamResp 合并（接口数据覆盖缓存）；
/// 6. 全程静默：不显示 loading、失败不弹提示。
class LoginParamsUtils {
  LoginParamsUtils._();

  /// 本次 App 运行是否已执行过刷新（对齐 Vue onLaunch：运行期间不重复拉取）
  static bool _refreshed = false;

  // ──────────── 启动刷新 ────────────────────────────────────────────

  /// 启动时静默刷新登录相关数据（user / store / rolemap / loginParamResp）。
  ///
  /// 由首页启动后调用（App 运行期间仅执行一次），未登录时不请求。
  /// 后台静默执行，失败不影响启动流程，下次启动自动重试。
  static void refreshLoginParams() {
    if (_refreshed) {
      return;
    }
    _refreshed = true;
    unawaited(_doRefresh());
  }

  /// 强制刷新登录相关数据（忽略 App 运行期间“仅执行一次”标记）。
  ///
  /// 供席位解绑等需要立即同步 user / store / rolemap / sysSeat 的场景调用
  /// （对齐 Vue：解绑成功后重新请求 /updateEmployeeStorePermission）。
  /// 未登录时不请求；静默执行，失败不弹提示。
  static Future<void> forceRefresh() => _doRefresh();

  static Future<void> _doRefresh() async {
    // 未登录时不请求（对齐 Vue：if (getCookie("token"))）
    final String token = SpUtil.getString(Constant.token) ?? '';
    if (token.isEmpty) {
      debugPrint('[LoginParams] 未登录，跳过登录相关数据刷新');
      return;
    }

    FileLogWriter.instance.writeOperationLog('登录数据', '开始刷新');
    try {
      // 静默请求：不显示 loading、失败不弹提示（对齐 Vue custom: { toast: false }）
      final result = await request(
        HttpApi.updateEmployeeStorePermission,
        <String, dynamic>{},
        false, // showLoading
        false, // showError（启动刷新静默失败，不弹错误提示）
      );

      // 对齐 Vue custom.indata：取返回的 data 字段（data 缺省时视为空对象）
      final dynamic rawData = result['data'];
      final Map<String, dynamic> paramsData =
          rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};

      // 重新存登录相关数据：接口返回为准，存在则覆盖缓存
      _saveIfPresent(Constant.user, paramsData['user']);
      _saveIfPresent(Constant.store, paramsData['store']);
      _saveIfPresent(Constant.rolemap, paramsData['rolemap']);
      // 席位信息（对齐 boss 项目 App.vue 66 行：接口返回为准覆盖缓存）
      _saveIfPresent(Constant.sysSeat, paramsData['sysSeat']);

      // 参数部分：优先取接口返回的 loginParamResp 字段，否则取其余参数
      final dynamic loginParamResp = paramsData['loginParamResp'];
      final Map<String, dynamic> params = loginParamResp is Map
          ? Map<String, dynamic>.from(loginParamResp)
          : (Map<String, dynamic>.from(paramsData)
            ..remove('user')
            ..remove('store')
            ..remove('rolemap')
            ..remove('loginParamResp'));

      // 把 loginParamResp 里的一级嵌套对象解构合并到顶层（与登录页处理保持一致）
      // 例: { "moduleA": { "dynamicsCodeFlushTime": 60 } } => { "dynamicsCodeFlushTime": 60 }
      final keysToRemove = <String>[];
      final extras = <String, dynamic>{};
      for (final entry in params.entries) {
        if (entry.value is Map) {
          extras.addAll(Map<String, dynamic>.from(entry.value as Map));
          keysToRemove.add(entry.key);
        }
      }
      keysToRemove.forEach(params.remove);
      params.addAll(extras);

      // 与缓存的 loginParamResp 合并：接口数据覆盖缓存
      final merged = _readCachedLoginParams();
      merged.addAll(params);
      SpUtil.putString(Constant.loginParamResp, json.encode(merged));

      debugPrint('[LoginParams] 登录相关数据刷新成功，参数项数: ${merged.length}');
      FileLogWriter.instance.writeOperationLog('登录数据', '刷新成功');
    } catch (e) {
      // 静默失败（对齐 Vue .catch(() => {})），下次启动自动重试
      debugPrint('[LoginParams] 登录相关数据刷新失败: $e');
      FileLogWriter.instance.writeOperationLog('登录数据', '刷新失败', '$e');
    }
  }

  // ──────────── 缓存读写 ───────────────────────────────────────────

  /// 接口字段存在时按 JSON 覆盖写入对应缓存（与登录页存储格式保持一致）
  static void _saveIfPresent(String key, dynamic value) {
    if (value == null) {
      return;
    }
    try {
      SpUtil.putString(key, json.encode(value));
    } catch (e) {
      debugPrint('[LoginParams] 缓存写入失败 ($key): $e');
    }
  }

  /// 读取本地缓存的 loginParamResp（无缓存或解析失败时返回空 Map）
  static Map<String, dynamic> _readCachedLoginParams() {
    try {
      final String cachedStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cachedStr.isNotEmpty) {
        final cached = json.decode(cachedStr);
        if (cached is Map) {
          return Map<String, dynamic>.from(cached);
        }
      }
    } catch (_) {}
    return <String, dynamic>{};
  }
}
