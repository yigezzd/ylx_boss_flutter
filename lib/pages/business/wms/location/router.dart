import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/wms/location/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class WmsLocationRouter implements IRouterProvider {
  static const String wmsLocationList = '/wms/location/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      wmsLocationList,
      handler: Handler(
        handlerFunc: (_, __) => const WmsLocationListPage(),
      ),
    );
  }
}
