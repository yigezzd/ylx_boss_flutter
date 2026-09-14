import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/businessReport/typeABC/type_abc_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class TypeAbcRouter implements IRouterProvider {
  static const String root = '/typeABC';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const TypeAbcPage()));
  }
}
