import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/cgothercd/add.dart';
import 'package:flutter_deer/pages/business/purchase/cgothercd/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CgothercdRouter implements IRouterProvider {
  static const String cgothercdList = '/purchase/cgothercd/list';
  static const String cgothercdAdd = '/purchase/cgothercd/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      cgothercdList,
      handler: Handler(
        handlerFunc: (_, __) => const CgothercdListPage(),
      ),
    );
    router.define(
      cgothercdAdd,
      handler: Handler(
        handlerFunc: (_, __) => const CgothercdAddPage(),
      ),
    );
  }
}
