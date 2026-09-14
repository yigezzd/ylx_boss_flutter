import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/basis/storeChangePrice/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class StoreChangePriceRouter implements IRouterProvider {
  static const String storeChangePriceList = '/basis/storeChangePrice/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      storeChangePriceList,
      handler: Handler(
        handlerFunc: (_, __) => const StoreChangePriceListPage(),
      ),
    );
  }
}
