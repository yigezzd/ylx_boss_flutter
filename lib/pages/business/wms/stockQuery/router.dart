import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/wms/stockQuery/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class WmsStockQueryRouter implements IRouterProvider {
  static const String wmsStockQueryList = '/wms/stockQuery/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      wmsStockQueryList,
      handler: Handler(
        handlerFunc: (_, __) => const WmsStockQueryPage(),
      ),
    );
  }
}
