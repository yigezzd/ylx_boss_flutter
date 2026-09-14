import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/cgthsq/add.dart';
import 'package:flutter_deer/pages/business/purchase/cgthsq/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CgthsqRouter implements IRouterProvider {
  static const String cgthsqList = '/purchase/cgthsq/list';
  static const String cgthsqAdd = '/purchase/cgthsq/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      cgthsqList,
      handler: Handler(
        handlerFunc: (_, __) => const CgthsqListPage(),
      ),
    );
    router.define(
      cgthsqAdd,
      handler: Handler(
        handlerFunc: (_, __) => const CgthsqAddPage(),
      ),
    );
  }
}
