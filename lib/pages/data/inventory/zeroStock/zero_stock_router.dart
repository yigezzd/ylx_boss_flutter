import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/inventory/zeroStock/zero_stock_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class ZeroStockRouter implements IRouterProvider {
  static const String root = '/zeroStock';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const ZeroStockPage()));
  }
}
