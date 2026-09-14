import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/basis/promotionPlan/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class PromotionPlanRouter implements IRouterProvider {
  static const String promotionPlanList = '/basis/promotionPlan/list';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      promotionPlanList,
      handler: Handler(
        handlerFunc: (_, __) => const PromotionPlanListPage(),
      ),
    );
  }
}
