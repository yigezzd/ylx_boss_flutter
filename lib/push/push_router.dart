import 'package:flutter/material.dart';
import 'package:flutter_deer/main.dart';
import 'package:flutter_deer/pages/business/chain/allot_apply/list.dart';
import 'package:flutter_deer/pages/business/chain/allot_delivery/list.dart';
import 'package:flutter_deer/pages/business/chain/allot_entry/list.dart';
import 'package:flutter_deer/pages/business/chain/deliver/list.dart';
import 'package:flutter_deer/pages/business/chain/enquiry/list.dart';
import 'package:flutter_deer/pages/business/chain/receivingnote/list.dart';
import 'package:flutter_deer/pages/business/chain/returentakedelivery/list.dart';
import 'package:flutter_deer/pages/business/chain/returnapplication/list.dart';
import 'package:flutter_deer/pages/business/chain/returndeliver/list.dart';
import 'package:flutter_deer/push/push_message.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/log_utils.dart';

/// 推送点击跳转
///
/// 约定：通知的附加字段（extras）中可携带以下跳转信息（由后端下发）：
/// - `route`      ：目标页面路由（如 `/purchase/cgorder/list`），优先级最高
/// - `url`        ：网页地址，跳转内置 WebView
/// - `billtypeid` ：单据类型 id，映射到对应单据列表页
/// 以上均未提供时，默认回到首页。
class PushRouter {
  PushRouter._();

  static const String _tag = 'PUSH';

  /// 单据类型 → fluro 路由（与 ApprovalReminderHelper 的映射保持一致）
  static const Map<String, String> billRouteMap = <String, String>{
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

  /// 单据类型 → 页面构造器（连锁模块未注册 fluro 路由，直接构造页面跳转）
  static final Map<String, Widget Function()> billPageMap =
      <String, Widget Function()>{
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

  /// 处理通知点击后的跳转。
  /// 延迟到下一帧，避免冷启动点击通知时 Navigator 尚未挂载。
  static void handle(PushMessage message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInternal(message);
    });
  }

  static void _handleInternal(PushMessage message) {
    final String? route = message.route;
    if (route != null && route.isNotEmpty) {
      _navigate(route, args: message.extras);
      return;
    }

    final String? url = message.url;
    if (url != null && url.isNotEmpty) {
      _openWebView(message.title ?? '详情', url);
      return;
    }

    final String? billTypeId = message.billTypeId;
    if (billTypeId != null && billRouteMap.containsKey(billTypeId)) {
      _navigate(billRouteMap[billTypeId]!);
      return;
    }
    if (billTypeId != null && billPageMap.containsKey(billTypeId)) {
      _pushWidget(billPageMap[billTypeId]!());
      return;
    }

    // 默认回到首页
    _navigate(Routes.home);
  }

  static void _navigate(String path, {Map<String, dynamic>? args, int attempt = 0}) {
    final BuildContext? context = _context();
    if (context == null) {
      _retry(() => _navigate(path, args: args, attempt: attempt + 1), attempt);
      return;
    }
    NavigatorUtils.push(context, path, arguments: args);
    Log.d('推送跳转路由: $path', tag: _tag);
  }

  static void _openWebView(String title, String url, {int attempt = 0}) {
    final BuildContext? context = _context();
    if (context == null) {
      _retry(() => _openWebView(title, url, attempt: attempt + 1), attempt);
      return;
    }
    NavigatorUtils.goWebViewPage(context, title, url);
    Log.d('推送跳转 WebView: $url', tag: _tag);
  }

  static void _pushWidget(Widget page, {int attempt = 0}) {
    final BuildContext? context = _context();
    if (context == null) {
      _retry(() => _pushWidget(page, attempt: attempt + 1), attempt);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  static BuildContext? _context() => MyApp.navigatorKey.currentState?.context;

  /// 冷启动点击通知时 Navigator 尚未挂载，延迟重试（带次数上限）
  static void _retry(VoidCallback action, int attempt) {
    if (attempt >= 10) {
      Log.e('推送跳转失败：Navigator 长时间未就绪', tag: _tag);
      return;
    }
    Future.delayed(const Duration(milliseconds: 300), action);
  }
}
