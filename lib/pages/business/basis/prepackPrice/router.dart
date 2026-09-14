import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/basis/prepackPrice/prepack_price_home.dart';
import 'package:flutter_deer/routers/i_router.dart';

class PrepackPriceRouter implements IRouterProvider {
  static const String prepackPriceHome = '/basis/prepackPrice/home';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      prepackPriceHome,
      handler: Handler(
        handlerFunc: (_, __) => const PrepackPriceHomePage(),
      ),
    );
  }
}
