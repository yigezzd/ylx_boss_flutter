import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/inventory/vaildWarn/vaild_warn_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class VaildWarnRouter implements IRouterProvider {
  static const String root = '/vaildWarn';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const VaildWarnPage()));
  }
}
