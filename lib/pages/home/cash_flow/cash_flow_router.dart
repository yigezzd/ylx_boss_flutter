import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/home/cash_flow/cash_flow_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CashFlowRouter implements IRouterProvider {
  static const String cashFlowList = '/cashflow/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(cashFlowList, handler: Handler(handlerFunc: (_, __) => const CashFlowPage()));
  }
}
