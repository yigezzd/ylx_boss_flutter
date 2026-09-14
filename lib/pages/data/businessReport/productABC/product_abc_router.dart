import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/businessReport/productABC/product_abc_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class ProductAbcRouter implements IRouterProvider {
  static const String root = '/productABC';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const ProductAbcPage()));
  }
}
