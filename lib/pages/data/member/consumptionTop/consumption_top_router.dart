import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/member/consumptionTop/consumption_top_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class ConsumptionTopRouter implements IRouterProvider {
  static const String root = '/consumptionTop';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const ConsumptionTopPage()));
  }
}
