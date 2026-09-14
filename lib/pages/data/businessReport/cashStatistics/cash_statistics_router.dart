import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/businessReport/cashStatistics/cash_statistics_page.dart';
import 'package:flutter_deer/pages/data/businessReport/cashStatistics/jbtj_bill_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CashStatisticsRouter implements IRouterProvider {
  static const String list = '/cashStatistics/list';
  static const String jbtjBill = '/cashStatistics/jbtjBill';

  @override
  void initRouter(FluroRouter router) {
    router.define(list, handler: Handler(handlerFunc: (_, __) => const CashStatisticsPage()));
    router.define(jbtjBill, handler: Handler(handlerFunc: (context, params) {
      final args = context?.settings?.arguments;
      if (args is Map<String, dynamic>) {
        return JbtjBillPage(rowData: args);
      }
      return const JbtjBillPage(rowData: {});
    }));
  }
}
