import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/businessReport/cashFlow/bill.dart';
import 'package:flutter_deer/pages/data/businessReport/cashFlow/cash_flow_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CashFlowRouter implements IRouterProvider {
  static const String cashFlowList = '/cashflow/list';
  static const String cashFlowBill = '/cashflow/bill';

  @override
  void initRouter(FluroRouter router) {
    router.define(cashFlowList, handler: Handler(handlerFunc: (_, __) => const CashFlowPage()));
    router.define(cashFlowBill, handler: Handler(handlerFunc: (context, params) {
      final saleid = params['saleid']?.first ?? '';
      final sid = params['sid']?.first ?? '';
      return CashFlowBillPage(saleid: saleid, sid: sid);
    }));
  }
}
