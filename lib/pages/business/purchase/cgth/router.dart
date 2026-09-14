import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/cgth/add.dart';
import 'package:flutter_deer/pages/business/purchase/cgth/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CgthRouter implements IRouterProvider {
  static const String purchaseCgthList = '/purchase/cgth/list';
  static const String purchaseCgthAdd = '/purchase/cgth/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      purchaseCgthList,
      handler: Handler(
        handlerFunc: (_, __) => const PurchaseCgthListPage(),
      ),
    );
    router.define(
      purchaseCgthAdd,
      handler: Handler(
        handlerFunc: (_, __) => const PurchaseCgthAddPage(),
      ),
    );
  }
}
