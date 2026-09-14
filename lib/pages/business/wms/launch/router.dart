import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/wms/launch/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class WmsLaunchRouter implements IRouterProvider {
  static const String wmsLaunchList = '/wms/launch/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      wmsLaunchList,
      handler: Handler(
        handlerFunc: (_, __) => const WmsLaunchListPage(),
      ),
    );
  }
}
