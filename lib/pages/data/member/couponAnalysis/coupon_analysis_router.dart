import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/member/couponAnalysis/coupon_analysis_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CouponAnalysisRouter implements IRouterProvider {
  static const String root = '/couponAnalysis';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const CouponAnalysisPage()));
  }
}
