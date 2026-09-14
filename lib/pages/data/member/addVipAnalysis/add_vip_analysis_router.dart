import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/member/addVipAnalysis/add_vip_analysis_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class AddVipAnalysisRouter implements IRouterProvider {
  static const String root = '/addVipAnalysis';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const AddVipAnalysisPage()));
  }
}
