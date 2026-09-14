import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/inventory/unsalable/unsalable_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class UnsalableRouter implements IRouterProvider {
  static const String root = '/unsalable';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const UnsalablePage()));
  }
}
