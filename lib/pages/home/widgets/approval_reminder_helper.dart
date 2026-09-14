import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/chain/allot_apply/list.dart';
import 'package:flutter_deer/pages/business/chain/allot_delivery/list.dart';
import 'package:flutter_deer/pages/business/chain/allot_entry/list.dart';
import 'package:flutter_deer/pages/business/chain/deliver/list.dart';
import 'package:flutter_deer/pages/business/chain/enquiry/list.dart';
import 'package:flutter_deer/pages/business/chain/receivingnote/list.dart';
import 'package:flutter_deer/pages/business/chain/returentakedelivery/list.dart';
import 'package:flutter_deer/pages/business/chain/returnapplication/list.dart';
import 'package:flutter_deer/pages/business/chain/returndeliver/list.dart';
import 'package:flutter_deer/pages/home/widgets/approval_reminder_dialog.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 单据审批提醒助手 —— 统一管理数据获取、合并、弹窗逻辑
/// 供首页和库存预警页共用（对齐 Vue approvalReminder.vue 组件）
class ApprovalReminderHelper {
  ApprovalReminderHelper._();

  /// 单据类型 → Flutter 路由映射（对齐 Vue billRouteMap，仅含已注册 Fluro 路由的页面）
  static const _routeMap = <String, String>{
    // 采购
    '0501': '/purchase/cgplan/list', // 采购计划
    '0502': '/purchase/cgorder/list', // 采购订货
    '0503': '/purchase/cgzc/list', // 自采申请单
    '0504': '/purchase/cgother/list', // 直配订单
    '0505': '/purchase/cgothercd/list', // 越库订单
    '0506': '/purchase/instore/list', // 采购入库
    '0507': '/purchase/cgth/list', // 采购退货
    '0508': '/purchase/cgthsq/list', // 退货申请
    // 批发
    '0601': '/wholesale/pf_order/list', // 批发订货
    '0602': '/wholesale/pf_sale/list', // 批发销售
    '0603': '/wholesale/pf_return/list', // 批发退货
    // 库存
    '0802': '/inventory/otherout/list', // 其他出库单
    '0803': '/inventory/otherin/list', // 其他入库单
    '0804': '/inventory/movewarehouse/list', // 移仓单
    '0806': '/inventory/costchange/list', // 成本变更单
    '0807': '/inventory/plan/list', // 盘点计划
    '0808': '/inventory/precheck/list', // 预盘单
    '0810': '/inventory/quickcheck/list', // 快速盘点
    // 财务
    '1003': '/finance/costRevenue/list', // 费用收支单
    '1006': '/finance/supplierPay/list', // 供应商结算
    '1017': '/finance/customerPay/list', // 客户结算
    '1023': '/finance/storePay/list', // 门店结算
  };

  /// 单据类型 → 页面构造器映射（连锁模块页面未注册 Fluro 路由，
  /// 与 business_page 的进入方式保持一致，直接构造页面跳转）
  static final _pageMap = <String, Widget Function()>{
    '0712': () => const EnquiryListPage(), // 要货申请
    '0713': () => const DeliverListPage(), // 配送发货
    '0714': () => const ReceivingnoteListPage(), // 配送收货
    '0715': () => const ReturnApplicationListPage(), // 配退申请
    '0716': () => const ReturnDeliverListPage(), // 配退发货
    '0717': () => const ReturnTakeDeliveryListPage(), // 配退收货
    '0718': () => const AllotApplyListPage(), // 调拨申请
    '0719': () => const AllotDeliveryListPage(), // 调拨出库
    '0720': () => const AllotEntryListPage(), // 调拨入库
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
        // 只显示已有对应页面的单据（无对应页面时跳过）
        if (!_routeMap.containsKey(billtypeid) && !_pageMap.containsKey(billtypeid)) continue;
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
    }
    // 连锁模块等未注册 Fluro 路由的页面：直接构造页面跳转
    final pageBuilder = _pageMap[billtypeid];
    if (pageBuilder != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => pageBuilder()),
      );
      return true;
    }
    Toast.show('「$name」功能开发中');
    return false;
  }
}
