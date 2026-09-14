import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/cgzc/add.dart';
import 'package:flutter_deer/pages/business/purchase/cgzc/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CgzcRouter implements IRouterProvider {
  static const String cgzcList = '/purchase/cgzc/list';
  static const String cgzcAdd = '/purchase/cgzc/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      cgzcList,
      handler: Handler(
        handlerFunc: (_, __) => const CgzcListPage(),
      ),
    );
    router.define(
      cgzcAdd,
      handler: Handler(
        handlerFunc: (_, __) => const CgzcAddPage(),
      ),
    );
  }
}
