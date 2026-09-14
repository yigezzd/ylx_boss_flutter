import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/home/widgets/approval_reminder_dialog.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 单据审批提醒助手 —— 统一管理数据获取、合并、弹窗逻辑
/// 供首页和库存预警页共用（对齐 Vue approvalReminder.vue 组件）
class ApprovalReminderHelper {
  ApprovalReminderHelper._();

  /// 单据类型 → Flutter 路由映射（对齐 Vue billRouteMap）
  static const _routeMap = <String, String>{
    '0501': '/purchase/cgplan/list', // 采购计划
    '0502': '/purchase/cgorder/list', // 采购订货
    '0503': '/purchase/cgzc/list', // 自采申请单
    '0506': '/purchase/instore/list', // 采购入库
    '0507': '/purchase/cgth/list', // 采购退货
    '0601': '/wholesale/pf_order/list', // 批发订货
    '0602': '/wholesale/pf_sale/list', // 批发销售
    '0603': '/wholesale/pf_return/list', // 批发退货
    '0807': '/inventory/plan/list', // 盘点计划
    '0808': '/inventory/precheck/list', // 预盘单
    '0810': '/inventory/quickcheck/list', // 快速盘点
  };

  /// 获取待审批总数量（对齐 Vue getCount()）
  static Future<int> fetchCount() async {
    try {
      final res = await request(HttpApi.getReviewBillStatusFlowResp, {});
      final data = res['data'];
      if (data is! Map<String, dynamic>) return 0;
      final rawList = (data['reviewBillStatusFlowDetail'] as List?) ?? [];
      int count = 0;
      for (final item in rawList) {
        if (item['signflag'] == 1) continue;
        count += int.tryParse(item['statuscount']?.toString() ?? '0') ?? 0;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// 检查并显示审批提醒弹窗（对齐 Vue fetchData + openApproval）
  /// 返回 true 表示弹窗已显示，false 表示无数据或已忽略
  static Future<bool> checkAndShow(BuildContext context) async {
    // 检查是否已"不再提醒"
    final dismissed = SpUtil.getBool('approvalReminderDismissed') ?? false;
    if (dismissed) return false;

    try {
      final res = await request(HttpApi.getReviewBillStatusFlowResp, {});
      if (!context.mounted) return false;
      final data = res['data'];
      if (data is! Map<String, dynamic>) return false;
      final rawList = (data['reviewBillStatusFlowDetail'] as List?) ?? [];
      final merged = <String, int>{};
      final mergedBill = <String, String>{};
      for (final item in rawList) {
        if (item['signflag'] == 1) continue;
        final count = int.tryParse(item['statuscount']?.toString() ?? '0') ?? 0;
        if (count <= 0) continue;
        final name = item['billtypename']?.toString() ?? '';
        if (name.isEmpty) continue;
        final billtypeid = item['billtypeid']?.toString() ?? '';
        merged[name] = (merged[name] ?? 0) + count;
        mergedBill[name] = billtypeid;
      }
      if (merged.isEmpty || !context.mounted) return false;
      final items = merged.entries
          .map(
              (e) => ApprovalItem(billtypeid: mergedBill[e.key] ?? '', name: e.key, count: e.value))
          .toList();
      final result = await showDialog<dynamic>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ApprovalReminderDialog(
          items: items,
          onItemTap: (item) => _navigateTo(context, item.billtypeid, item.name),
        ),
      );
      if (!context.mounted) return false;
      if (result is bool && result) {
        SpUtil.putBool('approvalReminderDismissed', true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 根据 billtypeid 跳转到对应页面（对齐 Vue goDetail）
  static bool _navigateTo(BuildContext context, String billtypeid, String name) {
    final route = _routeMap[billtypeid];
    if (route != null) {
      Routes.router.navigateTo(context, route, transition: TransitionType.cupertino);
      return true;
    } else {
      Toast.show('「$name」功能开发中');
      return false;
    }
  }
}
