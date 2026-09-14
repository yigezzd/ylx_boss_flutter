import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/businessReport/cashierMonitoring/cashier_monitoring_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

/// 收银监控路由
class CashierMonitoringRouter implements IRouterProvider {
  static const String root = '/cashierMonitoring';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const CashierMonitoringPage()));
  }
}
