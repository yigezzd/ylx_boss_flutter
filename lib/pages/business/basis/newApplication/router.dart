import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/basis/newApplication/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class NewApplicationRouter implements IRouterProvider {
  static const String newApplicationList = '/basis/newApplication/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      newApplicationList,
      handler: Handler(
        handlerFunc: (_, __) => const NewApplicationListPage(),
      ),
    );
  }
}
