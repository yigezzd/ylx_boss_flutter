import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 权限工具类 —— 对齐 boss 项目 setConfig.ts 中的 permission / navPath / fetchRoleInfoRetMap
///
/// 权限数据来源：
/// - 登录成功后 lxlogin 接口返回 rolemap 字段，存入 SpUtil（Constant.rolemap）
/// - 切换底部 tabbar 时调用 /role/getInfoRetMap 接口刷新权限缓存
///
/// 权限校验规则（与 boss 项目一致）：
/// 1. rolemap 和 user 均不存在 → 放行（兼容无权限管控场景）
/// 2. rolemap[menuId] 存在且值非显式 falsy → 放行（值可能是 true / '查看' / 其他权限名）
/// 3. user.roleid == '1001' 或 user.code == '1001' → 超级管理员放行
/// 4. 其他情况 → 拦截并提示
class PermissionUtils {
  PermissionUtils._();

  // ──────────── 权限接口节流（对齐 boss 项目 10s 节流策略）────────────

  /// 节流间隔：10 秒内不重复请求
  static const int _throttleMs = 10 * 1000;

  /// 上次成功请求时间戳
  static int _lastFetchAt = 0;

  /// 不重入标记（避免并发重复请求）
  static Future<Map<String, dynamic>?>? _pending;

  // ──────────── 权限校验 ────────────────────────────────────────────

  /// 检查当前用户是否拥有 [menuId] 对应的权限。
  ///
  /// - [showTip] 为 true 时无权限会弹 Toast 提示（默认 true）
  /// - 返回 true 表示有权限，false 表示无权限
  static bool checkPermission(String menuId, {bool showTip = true}) {
    if (menuId.isEmpty) return true;

    // 读取 rolemap 缓存
    Map<String, dynamic>? rolemap;
    try {
      final rolemapStr = SpUtil.getString(Constant.rolemap, defValue: '') ?? '';
      if (rolemapStr.isNotEmpty) {
        rolemap = jsonDecode(rolemapStr) as Map<String, dynamic>;
      }
    } catch (_) {}

    // 读取 user 缓存
    Map<String, dynamic>? user;
    try {
      final userStr = SpUtil.getString(Constant.user, defValue: '') ?? '';
      if (userStr.isNotEmpty) {
        user = jsonDecode(userStr) as Map<String, dynamic>;
      }
    } catch (_) {}

    // 规则 1：rolemap 和 user 均不存在 → 放行
    if (rolemap == null && user == null) return true;

    // 规则 2：rolemap 中包含该 menuId → 放行
    // rolemap 的值可能是 true / 'true' / 1 / '查看' 等，
    // 只要不是显式的 falsy 值（false / 'false' / 0 / '0' / null / ''）即视为有权限
    if (rolemap != null && rolemap.containsKey(menuId)) {
      final val = rolemap[menuId];
      if (val != null &&
          val != false &&
          val != 'false' &&
          val != 0 &&
          val != '0' &&
          val != '') {
        return true;
      }
    }

    // 规则 3：超级管理员放行
    if (user != null) {
      final roleid = user['roleid']?.toString() ?? '';
      final code = user['code']?.toString() ?? '';
      if (roleid == '1001' || code == '1001') return true;
    }

    // 规则 4：无权限 → 拦截
    if (showTip) {
      Toast.show('你无权访问此模块，请在后台修改权限');
    }
    return false;
  }

  /// 从本地缓存快速判断是否有权限（不弹提示，用于 UI 状态控制）
  static bool hasPermission(String menuId) {
    return checkPermission(menuId, showTip: false);
  }

  // ──────────── 权限数据刷新 ─────────────────────────────────────────

  /// 调用 /role/getInfoRetMap 接口获取最新权限 map 并更新本地缓存。
  ///
  /// 内置 10s 节流：距上次成功调用不足 10s 则跳过本次请求。
  /// [force] = true 可强制刷新（绕过节流）。
  ///
  /// 对齐 boss 项目 store/user.ts fetchRoleInfoRetMap 实现。
  static Future<Map<String, dynamic>?> fetchRoleInfoRetMap({bool force = false}) async {
    // 未登录时不请求
    final token = SpUtil.getString(Constant.token, defValue: '') ?? '';
    if (token.isEmpty) return null;

    // 节流：10s 内不重复请求
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && (now - _lastFetchAt) < _throttleMs) {
      return _getCachedRolemap();
    }

    // 避免并发重复请求
    if (_pending != null) return _pending;

    _pending = _doFetch();
    return _pending;
  }

  static Future<Map<String, dynamic>?> _doFetch() async {
    try {
      // 从 user 缓存中取 roleid / operid 注入请求参数
      final Map<String, dynamic> params = <String, dynamic>{
        'clientflag': 9,
      };
      try {
        final userStr = SpUtil.getString(Constant.user, defValue: '') ?? '';
        if (userStr.isNotEmpty) {
          final user = jsonDecode(userStr) as Map<String, dynamic>;
          final roleid = user['roleid']?.toString();
          final operid = user['operid']?.toString();
          if (roleid != null && roleid.isNotEmpty) params['roleid'] = roleid;
          if (operid != null && operid.isNotEmpty) params['operid'] = operid;
        }
      } catch (_) {}

      final result = await request(
        HttpApi.roleGetInfoRetMap,
        params,
        false, // showLoading
        false, // showError（权限接口静默失败，不弹错误提示）
      );

      // 接口返回的 data 字段即为权限 map
      Map<String, dynamic>? rolemap;
      final data = result['data'];
      if (data is Map) {
        rolemap = Map<String, dynamic>.from(data);
      } else {
        // 兼容扁平结构：result 本身即为 rolemap（去除 retcode/retmsg 等元字段）
        rolemap = Map<String, dynamic>.from(result)
          ..remove('retcode')
          ..remove('retmsg');
      }

      // 写入本地缓存
      SpUtil.putString(Constant.rolemap, json.encode(rolemap));
      _lastFetchAt = DateTime.now().millisecondsSinceEpoch;

      debugPrint('[PermissionUtils] fetchRoleInfoRetMap 成功，权限项数: ${rolemap.length}');
      return rolemap;
    } catch (e) {
      debugPrint('[PermissionUtils] fetchRoleInfoRetMap 失败: $e');
      return null;
    } finally {
      _pending = null;
    }
  }

  static Map<String, dynamic>? _getCachedRolemap() {
    try {
      final rolemapStr = SpUtil.getString(Constant.rolemap, defValue: '') ?? '';
      if (rolemapStr.isNotEmpty) {
        return jsonDecode(rolemapStr) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
