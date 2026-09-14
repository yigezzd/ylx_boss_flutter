import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/inventory/enterUnsold/enter_unsold_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class EnterUnsoldRouter implements IRouterProvider {
  static const String root = '/enterUnsold';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const EnterUnsoldPage()));
  }
}
