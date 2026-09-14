import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/cgother/add.dart';
import 'package:flutter_deer/pages/business/purchase/cgother/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CgotherRouter implements IRouterProvider {
  static const String cgotherList = '/purchase/cgother/list';
  static const String cgotherAdd = '/purchase/cgother/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      cgotherList,
      handler: Handler(
        handlerFunc: (_, __) => const CgotherListPage(),
      ),
    );
    router.define(
      cgotherAdd,
      handler: Handler(
        handlerFunc: (_, __) => const CgotherAddPage(),
      ),
    );
  }
}
