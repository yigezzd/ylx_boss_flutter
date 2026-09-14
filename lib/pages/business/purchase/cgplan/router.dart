import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/cgplan/add.dart';
import 'package:flutter_deer/pages/business/purchase/cgplan/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CgplanRouter implements IRouterProvider {
  static const String cgplanList = '/purchase/cgplan/list';
  static const String cgplanAdd = '/purchase/cgplan/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      cgplanList,
      handler: Handler(
        handlerFunc: (_, __) => const CgplanListPage(),
      ),
    );
    router.define(
      cgplanAdd,
      handler: Handler(
        handlerFunc: (_, __) => const CgplanAddPage(),
      ),
    );
  }
}
