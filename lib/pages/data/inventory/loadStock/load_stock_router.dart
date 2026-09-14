import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/inventory/loadStock/load_stock_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class LoadStockRouter implements IRouterProvider {
  static const String root = '/loadStock';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const LoadStockPage()));
  }
}
