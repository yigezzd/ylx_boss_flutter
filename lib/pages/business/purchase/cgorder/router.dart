import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/cgorder/add.dart';
import 'package:flutter_deer/pages/business/purchase/cgorder/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CgorderRouter implements IRouterProvider {
  static const String purchaseCgorderList = '/purchase/cgorder/list';
  static const String purchaseCgorderAdd = '/purchase/cgorder/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      purchaseCgorderList,
      handler: Handler(
        handlerFunc: (_, __) => const PurchaseCgorderListPage(),
      ),
    );
    router.define(
      purchaseCgorderAdd,
      handler: Handler(
        handlerFunc: (_, __) => const PurchaseCgorderAddPage(),
      ),
    );
  }
}
