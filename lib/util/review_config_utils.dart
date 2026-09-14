import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:sp_util/sp_util.dart';

/// 多级审批配置工具（对齐 Vue userStore.reviewBillTypeList 机制）
///
/// Vue 端行为（E:\xcx\ylx-boss\src\store\user.ts）：
/// 1. 登录 / tabbar 切换时调用 reviewTypeConfig/getReviewBillTypeList，
///    微信小程序端注入 clientflag=3；
/// 2. 响应解析兼容两种结构：Array.isArray(data) ? data : (data?.list || [])；
/// 3. 将嵌套 children 扁平化为 { billtypename: stopflag } 映射并持久化（pinia persist + cookie）；
/// 4. 各页面同步读取 reviewBillTypeList["xxx"] === "0" 动态显示"已驳回" tab，
///    接口失败时依赖持久化缓存兜底。
///
/// APP 端对齐上述全部行为：SpUtil 持久化 + 失败兜底缓存 + 10s 节流（避免多页面重复请求），
/// 并输出诊断日志便于排查后端配置差异。
class ReviewConfigUtils {
  ReviewConfigUtils._();

  static const String _cacheKey = 'reviewBillTypeList';

  /// 10s 节流（对齐 Vue fetchReviewBillTypeList 的 REVIEW_THROTTLE_MS）
  static const int _throttleMs = 10 * 1000;
  static int _lastFetchAt = 0;
  static Future<Map<String, dynamic>>? _pending;

  /// 判断指定单据类型是否应显示"已驳回" tab（stopflag == '0'，对齐 Vue === "0"）
  ///
  /// [force] 为 true 时绕过节流强制拉取最新配置（对齐 Vue fetchReviewBillTypeList 的 force 参数）
  static Future<bool> shouldShowRejectedTab(String billtypename, {bool force = false}) async {
    final map = await _fetch(force: force);
    final show = map[billtypename]?.toString() == '0';
    _log('$billtypename stopflag=${map[billtypename]} => 已驳回tab: $show');
    return show;
  }

  /// 全局预刷新审批配置（对齐 Vue business.vue onLoad → userStore.fetchReviewBillTypeList()）
  ///
  /// 进入业务首页时调用，提前更新缓存；受 10s 节流保护，不产生多余请求。
  /// [force] 为 true 时强制刷新（对齐 Vue 切换账号后 fetchReviewBillTypeList({}, true)）
  static void refreshConfig({bool force = false}) {
    unawaited(_fetch(force: force));
  }

  /// 诊断日志：debugPrint + 落地 crash_log（release 包可通过"上传日志"排查）
  static void _log(String msg) {
    debugPrint('[ReviewConfig] $msg');
    try {
      FileLogWriter.instance.writeErrorLog(null, 'ReviewConfig', '', msg);
    } catch (_) {}
  }

  /// 获取 {billtypename: stopflag} 映射：节流窗口外发起请求并写缓存；请求失败/窗口内读本地缓存兜底
  ///
  /// 注意：_lastFetchAt 仅在请求成功后才更新，失败不占用节流窗口，下次调用可重试
  /// [force] 为 true 时绕过节流窗口强制发起请求（对齐 Vue force 参数）
  static Future<Map<String, dynamic>> _fetch({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_pending == null && (force || now - _lastFetchAt >= _throttleMs)) {
      _pending = _doFetch().whenComplete(() => _pending = null);
    }
    final pending = _pending;
    if (pending != null) {
      try {
        final map = await pending;
        _lastFetchAt = DateTime.now().millisecondsSinceEpoch;
        return map;
      } catch (e) {
        // 接口失败，落入下方缓存兜底；不更新 _lastFetchAt，下次调用可重试
        _log('接口失败: $e');
      }
    }
    return _readCache();
  }

  /// 调用接口并解析为映射，成功写入 SpUtil 持久化缓存
  static Future<Map<String, dynamic>> _doFetch() async {
    // 对齐 Vue getReviewBillTypeList：注入 clientflag=3（微信小程序端）；静默失败不弹提示
    final result = await request(
      HttpApi.getReviewBillTypeList,
      <String, dynamic>{'clientflag': 3},
      false,
      false,
    );
    final data = result['data'];
    // 对齐 Vue Array.isArray(data) ? data : (data?.list || [])，兼容 List 与 {list: [...]} 两种返回结构
    final dynamic rawList = data is List ? data : (data is Map ? data['list'] : null);
    final mapped = <String, dynamic>{};
    if (rawList is List) {
      for (final group in rawList) {
        if (group is Map<dynamic, dynamic> && group['children'] is List) {
          for (final child in group['children'] as List) {
            if (child is Map<dynamic, dynamic> && child['billtypename'] != null) {
              mapped[child['billtypename'].toString()] = child['stopflag'];
            }
          }
        }
      }
    }
    debugPrint('[ReviewConfig] 接口成功 data类型=${data.runtimeType} 解析${mapped.length}项: $mapped');
    try {
      FileLogWriter.instance.writeErrorLog(
        null,
        'ReviewConfig',
        '',
        '接口成功 解析${mapped.length}项',
        data: mapped,
      );
    } catch (_) {}
    if (mapped.isNotEmpty) {
      // 写缓存失败不影响本次解析结果，避免 SpUtil 异常导致已解析数据被丢弃
      try {
        SpUtil.putString(_cacheKey, json.encode(mapped));
      } catch (e) {
        _log('缓存写入失败: $e');
      }
    }
    return mapped;
  }

  /// 读取本地持久化缓存（对齐 Vue pinia persist 兜底）
  static Map<String, dynamic> _readCache() {
    try {
      final s = SpUtil.getString(_cacheKey) ?? '';
      if (s.isNotEmpty) {
        final m = json.decode(s);
        if (m is Map) {
          _log('使用本地缓存 ${m.length}项');
          return Map<String, dynamic>.from(m);
        }
      }
    } catch (_) {}
    _log('无可用缓存，返回空配置');
    return <String, dynamic>{};
  }
}
