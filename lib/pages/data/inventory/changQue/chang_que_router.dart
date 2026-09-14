import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/inventory/changQue/chang_que_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class ChangQueRouter implements IRouterProvider {
  static const String root = '/changQue';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const ChangQuePage()));
  }
}
