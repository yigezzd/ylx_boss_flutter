import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/basis/productChangePrice/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class ProductChangePriceRouter implements IRouterProvider {
  static const String changePriceList = '/basis/productChangePrice/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      changePriceList,
      handler: Handler(
        handlerFunc: (_, __) => const ChangePriceListPage(),
      ),
    );
  }
}
