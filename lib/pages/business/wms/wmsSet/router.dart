import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/wms/wmsSet/page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class WmsSetRouter implements IRouterProvider {
  static const String wmsSetPage = '/wms/set';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      wmsSetPage,
      handler: Handler(
        handlerFunc: (_, __) => const WmsSetPage(),
      ),
    );
  }
}
