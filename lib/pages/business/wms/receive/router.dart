import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/wms/receive/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class WmsReceiveRouter implements IRouterProvider {
  static const String wmsReceiveList = '/wms/receive/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      wmsReceiveList,
      handler: Handler(
        handlerFunc: (_, __) => const WmsReceiveListPage(),
      ),
    );
  }
}
