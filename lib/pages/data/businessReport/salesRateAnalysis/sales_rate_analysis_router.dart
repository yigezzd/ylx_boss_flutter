import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/businessReport/salesRateAnalysis/sales_rate_analysis_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class SalesRateAnalysisRouter implements IRouterProvider {
  static const String root = '/salesRateAnalysis';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const SalesRateAnalysisPage()));
  }
}
