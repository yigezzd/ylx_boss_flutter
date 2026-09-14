import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/wms/restock/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class WmsRestockRouter implements IRouterProvider {
  static const String wmsRestockList = '/wms/restock/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      wmsRestockList,
      handler: Handler(
        handlerFunc: (_, __) => const WmsRestockListPage(),
      ),
    );
  }
}
