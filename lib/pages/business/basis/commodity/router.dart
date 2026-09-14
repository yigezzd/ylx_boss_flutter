import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/basis/commodity/add.dart';
import 'package:flutter_deer/pages/business/basis/commodity/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class CommodityRouter implements IRouterProvider {
  static const String commodityList = '/basis/commodity/list';
  static const String commodityAdd = '/basis/commodity/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      commodityList,
      handler: Handler(
        handlerFunc: (_, __) => const CommodityListPage(),
      ),
    );
    router.define(
      commodityAdd,
      handler: Handler(
        handlerFunc: (_, __) => const CommodityAddPage(),
      ),
    );
  }
}
