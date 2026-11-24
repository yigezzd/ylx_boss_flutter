import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 增值服务（席位）工具 —— 对齐 boss 项目 userStore.fetchVasList + business.vue 席位机制
///
/// Vue 端行为（E:\VUE\ylx-boss）：
/// 1. 业务 / 我的 / 数据页 tabbar 切换（onShow）时调用 vas/getVasList
///    （参数 { verid: "701,704,712" }，App 环境注入 clientflag = 7），
///    未登录不请求 + 10s 节流 + 并发不重入；
/// 2. 响应解析兼容两种结构：Array.isArray(data) ? data : (data?.list || [])；
/// 3. 席位信息 = vasList 中 verid = 712 的项 与 sysSeat 缓存合并（sysSeat 优先；
///    sysSeat 来源 login / updateEmployeeStorePermission 接口，见 Constant.sysSeat）；
/// 4. 是否专业版：expiretime 未过期 且 vertype >= 0；
/// 5. 席位到期提醒窗口：距到期时间 ±15 天内；
/// 6. 商户增值服务列表（addverList）：登录后调用 vas/getVasList + { bsid }，
///    用于 WMS 等模块开关判断（对齐 Vue business.vue isOpenVas(711)）。
class VasUtils {
  VasUtils._();

  /// 专业版移动店务席位对应的增值服务 ID（对齐 Vue verid == 712）
  static const String _proSeatVerId = '712';

  /// tabbar 切换刷新时查询的增值服务版本 ID 列表（对齐 Vue { verid: "701,704,712" }）
  static const String _queryVerIds = '701,704,712';

  /// 席位到期提醒窗口：±15 天（对齐 Vue SEAT_EXPIRE_TIP_MS）
  static const int _expireTipWindowMs = 15 * 24 * 60 * 60 * 1000;

  /// 10s 节流（对齐 Vue VAS_THROTTLE_MS）
  static const int _throttleMs = 10 * 1000;
  static int _lastFetchAt = 0;
  static Future<void>? _pending;

  // ──────────── 临时屏蔽开关（恢复版本区分时改回 false 即可）────────────

  /// 临时屏蔽版本区分：为 true 时 [isPro] 恒返回 true，
  /// 业务 / 报表页始终按专业版展示（不做席位校验、不灰显功能）
  static const bool forcePro = true;

  /// 临时屏蔽席位到期提醒：为 true 时 [isNearExpire] 恒返回 false，
  /// 业务 / 报表页不显示席位到期提醒条（续费弹窗入口随提醒条一并隐藏）
  static const bool hideSeatExpireTip = true;

  /// 临时屏蔽“我的”页账户信息卡片中的“绑定席位”行（含解绑入口）
  static const bool hideSeatBind = true;

  // ──────────── 数据刷新 ────────────────────────────────────────────

  /// 拉取增值服务列表并写入本地缓存（对齐 Vue fetchVasList）
  ///
  /// 未登录不请求；10s 节流；并发不重入；静默失败（接口异常时保留旧缓存）。
  /// [force] 为 true 时绕过节流强制刷新（对齐 Vue force 参数）。
  static Future<void> fetchVasList({bool force = false}) async {
    // 未登录不请求（对齐 Vue：if (getCookie('token'))）
    final String token = SpUtil.getString(Constant.token) ?? '';
    if (token.isEmpty) {
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (!force && (now - _lastFetchAt) < _throttleMs) {
      return;
    }
    if (_pending != null) {
      return _pending;
    }

    _pending = _doFetch().whenComplete(() => _pending = null);
    return _pending;
  }

  static Future<void> _doFetch() async {
    try {
      final result = await request(
        HttpApi.vasGetVasList,
        <String, dynamic>{
          'verid': _queryVerIds,
          'clientflag': 7, // App 环境（对齐 Vue #ifdef APP-PLUS clientflag = 7）
        },
        false, // showLoading
        false, // showError（静默失败，不弹错误提示）
      );
      final dynamic data = result['data'];
      // 对齐 Vue Array.isArray(data) ? data : (data?.list || [])
      final dynamic rawList = data is List ? data : (data is Map ? data['list'] : null);
      if (rawList is List) {
        SpUtil.putString(Constant.vasList, json.encode(rawList));
        _lastFetchAt = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[VasUtils] 增值服务列表刷新成功，共 ${rawList.length} 项');
      }
    } catch (e) {
      // 静默失败，保留旧缓存（对齐 Vue catch 分支）
      debugPrint('[VasUtils] 增值服务列表刷新失败: $e');
    }
  }

  // ──────────── 商户增值服务列表（对齐 Vue userStore.getAddVerList）────────────

  /// WMS 模块对应的增值服务 ID（对齐 Vue business.vue isOpenVas(711)）
  static const String wmsVerId = '711';

  static int _lastAddVerFetchAt = 0;
  static Future<void>? _pendingAddVer;

  /// 拉取商户增值服务列表（对齐 Vue getAddVerList：vas/getVasList + { bsid }）
  ///
  /// 未登录 / 无门店时不请求；10s 节流；并发不重入；静默失败（保留旧缓存）。
  static Future<void> fetchAddVerList({bool force = false}) async {
    // 未登录不请求（对齐 Vue：if (getCookie('token'))）
    final String token = SpUtil.getString(Constant.token) ?? '';
    if (token.isEmpty) {
      return;
    }
    final String bsid = _readStoreField('id');
    if (bsid.isEmpty) {
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (!force && (now - _lastAddVerFetchAt) < _throttleMs) {
      return;
    }
    if (_pendingAddVer != null) {
      return _pendingAddVer;
    }

    _pendingAddVer = _doFetchAddVer(bsid).whenComplete(() => _pendingAddVer = null);
    return _pendingAddVer;
  }

  static Future<void> _doFetchAddVer(String bsid) async {
    try {
      final result = await request(
        HttpApi.vasGetVasList,
        <String, dynamic>{'bsid': bsid},
        false, // showLoading
        false, // showError（静默失败，不弹错误提示）
      );
      final dynamic data = result['data'];
      // 对齐 Vue `this.addverList = res ?? []`，兼容数组 / { list: [] } 两种结构
      final dynamic rawList = data is List ? data : (data is Map ? data['list'] : null);
      final List<Map<String, dynamic>> list = rawList is List
          ? rawList
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      SpUtil.putString(Constant.addverList, json.encode(list));
      _lastAddVerFetchAt = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[VasUtils] 商户增值服务列表刷新成功，共 ${list.length} 项');
    } catch (e) {
      // 静默失败，保留旧缓存（对齐 Vue getAddVerList catch 分支）
      debugPrint('[VasUtils] 商户增值服务列表刷新失败: $e');
    }
  }

  /// 读取本地缓存的商户增值服务列表（对齐 Vue userStore.addverList）
  static List<Map<String, dynamic>> getCachedAddVerList() {
    try {
      final String s = SpUtil.getString(Constant.addverList) ?? '';
      if (s.isNotEmpty) {
        final dynamic decoded = json.decode(s);
        if (decoded is List) {
          return decoded
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  /// 是否已开通指定增值服务（对齐 Vue business.vue isOpenVas）
  ///
  /// vertype == 2（永久有效）或 vertype > -1 且 expiretime 未过期
  static bool isOpenVas(String verid) {
    final List<Map<String, dynamic>> list = getCachedAddVerList();
    if (list.isEmpty) {
      return false;
    }
    final int idx = list.indexWhere((e) => e['verid']?.toString() == verid);
    if (idx == -1) {
      return false;
    }
    final Map<String, dynamic> obj = list[idx];
    final num? vertype = num.tryParse(obj['vertype']?.toString() ?? '');
    if (vertype == null) {
      return false;
    }
    if (vertype == 2) {
      return true;
    }
    final DateTime? expireAt = parseExpireTime(obj['expiretime']);
    return vertype > -1 && expireAt != null && expireAt.isAfter(DateTime.now());
  }

  /// 读取登录门店 JSON 字段（对齐 Vue cookie store）
  static String _readStoreField(String key) {
    try {
      final String s = SpUtil.getString(Constant.store) ?? '';
      if (s.isNotEmpty) {
        final dynamic decoded = json.decode(s);
        if (decoded is Map) {
          return decoded[key]?.toString() ?? '';
        }
      }
    } catch (_) {}
    return '';
  }

  // ──────────── 席位读取 ────────────────────────────────────────────

  /// 席位信息（对齐 Vue business.vue vasObj =
  /// { ...vasList[verid==712], ...sysSeat }：sysSeat 优先覆盖）
  static Map<String, dynamic> getSeatInfo() {
    final Map<String, dynamic> seat = <String, dynamic>{};
    for (final item in getCachedVasList()) {
      if (item['verid']?.toString() == _proSeatVerId) {
        seat.addAll(item);
        break;
      }
    }
    seat.addAll(readSysSeat());
    return seat;
  }

  /// 读取本地缓存的增值服务列表（对齐 Vue cookie 'vasList'）
  static List<Map<String, dynamic>> getCachedVasList() {
    try {
      final String s = SpUtil.getString(Constant.vasList) ?? '';
      if (s.isNotEmpty) {
        final dynamic decoded = json.decode(s);
        if (decoded is List) {
          return decoded
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  /// 读取登录相关接口返回的席位缓存（sysSeat）
  static Map<String, dynamic> readSysSeat() {
    try {
      final String s = SpUtil.getString(Constant.sysSeat) ?? '';
      if (s.isNotEmpty) {
        final dynamic decoded = json.decode(s);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  // ──────────── 版本判断 ────────────────────────────────────────────

  /// 是否专业版（对齐 Vue isPro）：expiretime 未过期 且 vertype >= 0
  ///
  /// [forcePro] 为 true 时临时跳过席位校验，恒为专业版
  static bool isPro(Map<String, dynamic> seat) {
    if (forcePro) {
      return true;
    }
    final DateTime? expireAt = parseExpireTime(seat['expiretime']);
    if (expireAt == null || !expireAt.isAfter(DateTime.now())) {
      return false;
    }
    final num? vertype = num.tryParse(seat['vertype']?.toString() ?? '');
    return vertype != null && vertype >= 0;
  }

  /// 是否处于席位到期提醒窗口：距到期时间 ±15 天内
  /// （对齐 Vue showSeatExpireTip，模板中与 isPro 同时成立才显示）
  ///
  /// [hideSeatExpireTip] 为 true 时临时屏蔽到期提醒，恒返回 false
  static bool isNearExpire(Map<String, dynamic> seat) {
    if (hideSeatExpireTip) {
      return false;
    }
    final DateTime? expireAt = parseExpireTime(seat['expiretime']);
    if (expireAt == null) {
      return false;
    }
    final int diff =
        (expireAt.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch).abs();
    return diff <= _expireTipWindowMs;
  }

  /// 席位到期日期（YYYY-MM-DD，对齐 Vue DayJs(expiretime).format("YYYY-MM-DD")；
  /// 无有效时间时返回空串）
  static String formatExpireDate(Map<String, dynamic> seat) {
    final DateTime? expireAt = parseExpireTime(seat['expiretime']);
    if (expireAt == null) {
      return '';
    }
    final String m = expireAt.month.toString().padLeft(2, '0');
    final String d = expireAt.day.toString().padLeft(2, '0');
    return '${expireAt.year}-$m-$d';
  }

  /// 解析 expiretime（兼容毫秒/秒时间戳、"yyyy-MM-dd HH:mm:ss"、ISO8601 等格式）
  static DateTime? parseExpireTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return _fromTimestamp(value.toInt());
    }
    final String s = value.toString().trim();
    if (s.isEmpty) {
      return null;
    }
    final int? ts = int.tryParse(s);
    if (ts != null) {
      return _fromTimestamp(ts);
    }
    // "yyyy-MM-dd HH:mm:ss"（空格分隔）在部分平台解析不兼容，统一替换为 ISO 的 'T'
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  static DateTime _fromTimestamp(int ts) {
    // 10 位为秒级时间戳，13 位为毫秒级
    return DateTime.fromMillisecondsSinceEpoch(ts < 100000000000 ? ts * 1000 : ts);
  }
}
