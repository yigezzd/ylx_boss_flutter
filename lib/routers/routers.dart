import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/business/basis/commodity/router.dart';
import 'package:flutter_deer/pages/business/basis/newApplication/router.dart';
import 'package:flutter_deer/pages/business/basis/prepackPrice/router.dart';
import 'package:flutter_deer/pages/business/basis/printing/router.dart';
import 'package:flutter_deer/pages/business/basis/productChangePrice/router.dart';
import 'package:flutter_deer/pages/business/basis/promotionPlan/router.dart';
import 'package:flutter_deer/pages/business/basis/storeChangePrice/router.dart';
import 'package:flutter_deer/pages/business/finance/router.dart';
import 'package:flutter_deer/pages/business/inventory/router.dart';
import 'package:flutter_deer/pages/business/member/account_router.dart';
import 'package:flutter_deer/pages/business/purchase/cgorder/router.dart';
import 'package:flutter_deer/pages/business/purchase/cgother/router.dart';
import 'package:flutter_deer/pages/business/purchase/cgothercd/router.dart';
import 'package:flutter_deer/pages/business/purchase/cgplan/router.dart';
import 'package:flutter_deer/pages/business/purchase/cgth/router.dart';
import 'package:flutter_deer/pages/business/purchase/cgthsq/router.dart'; // TODO: 暂时屏蔽
import 'package:flutter_deer/pages/business/purchase/cgzc/router.dart';
import 'package:flutter_deer/pages/business/purchase/instore/router.dart';
import 'package:flutter_deer/pages/business/purchase/supplier/router.dart';
import 'package:flutter_deer/pages/business/wholesale/router.dart';
import 'package:flutter_deer/pages/business/wms/launch/router.dart';
import 'package:flutter_deer/pages/business/wms/receive/router.dart';
import 'package:flutter_deer/pages/business/wms/restock/router.dart';
import 'package:flutter_deer/pages/business/wms/stockQuery/router.dart';
import 'package:flutter_deer/pages/business/wms/wmsSet/router.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/business_analysis_router.dart';
import 'package:flutter_deer/pages/data/businessReport/cashFlow/cash_flow_router.dart';
import 'package:flutter_deer/pages/data/businessReport/cashStatistics/cash_statistics_router.dart';
import 'package:flutter_deer/pages/data/businessReport/cashierMonitoring/cashier_monitoring_router.dart';
import 'package:flutter_deer/pages/data/businessReport/exceptionMonitoring/exception_monitoring_router.dart';
import 'package:flutter_deer/pages/data/businessReport/productABC/product_abc_router.dart';
import 'package:flutter_deer/pages/data/businessReport/salesRateAnalysis/sales_rate_analysis_router.dart';
import 'package:flutter_deer/pages/data/businessReport/typeABC/type_abc_router.dart';
import 'package:flutter_deer/pages/data/inventory/changQue/chang_que_router.dart';
import 'package:flutter_deer/pages/data/inventory/enterUnsold/enter_unsold_router.dart';
import 'package:flutter_deer/pages/data/inventory/inventoryWarn/inventory_warn_router.dart';
import 'package:flutter_deer/pages/data/inventory/loadStock/load_stock_router.dart';
import 'package:flutter_deer/pages/data/inventory/unsalable/unsalable_router.dart';
import 'package:flutter_deer/pages/data/inventory/vaildWarn/vaild_warn_router.dart';
import 'package:flutter_deer/pages/data/inventory/zeroStock/zero_stock_router.dart';
import 'package:flutter_deer/pages/data/member/addVipAnalysis/add_vip_analysis_router.dart';
import 'package:flutter_deer/pages/data/member/consumptionTop/consumption_top_router.dart';
import 'package:flutter_deer/pages/data/member/couponAnalysis/coupon_analysis_router.dart';
import 'package:flutter_deer/pages/home/custom/card_setting_page.dart';
import 'package:flutter_deer/pages/home/custom/stock_warning_page.dart';
import 'package:flutter_deer/pages/home/home_page.dart';
import 'package:flutter_deer/pages/home/webview_page.dart';
import 'package:flutter_deer/pages/login/login_router.dart';
import 'package:flutter_deer/pages/system/management/management_router.dart';
import 'package:flutter_deer/routers/i_router.dart';
import 'package:flutter_deer/routers/not_found_page.dart';
import 'package:flutter_deer/setting/setting_router.dart';

class Routes {
  static String home = '/home';
  static String webViewPage = '/webView';
  static String cardSetting = '/home/cardSetting';
  static String stockWarning = '/stockWarning';

  static final List<IRouterProvider> _listRouter = [];

  static final FluroRouter router = FluroRouter();

  static void initRoutes() {
    /// 指定路由跳转错误返回页
    router.notFoundHandler =
        Handler(handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      debugPrint('未找到目标页');
      return const NotFoundPage();
    });

    router.define(home,
        handler: Handler(
            handlerFunc: (BuildContext? context, Map<String, List<String>> params) =>
                const Home()));

    router.define(cardSetting,
        handler: Handler(
            handlerFunc: (BuildContext? context, Map<String, List<String>> params) =>
                const CardSettingPage()));

    router.define(stockWarning,
        handler: Handler(
            handlerFunc: (BuildContext? context, Map<String, List<String>> params) =>
                const StockWarningPage()));

    router.define(webViewPage, handler: Handler(handlerFunc: (_, params) {
      final String title = params['title']?.first ?? '';
      final String url = params['url']?.first ?? '';
      final String isAsset = params['isAsset']?.first ?? 'false';
      return WebViewPage(title: title, url: url, isAsset: isAsset == 'true');
    }));

    _listRouter.clear();

    /// 各自路由由各自模块管理，统一在此添加初始化
    _listRouter.add(LoginRouter());
    _listRouter.add(AccountRouter());
    _listRouter.add(SettingRouter());
    _listRouter.add(PurchaseRouter());
    _listRouter.add(CgorderRouter());
    _listRouter.add(CgplanRouter());
    _listRouter.add(CgzcRouter());
    _listRouter.add(CgthsqRouter()); 
    _listRouter.add(CgotherRouter());
    _listRouter.add(CgothercdRouter());
    _listRouter.add(CgthRouter());
    _listRouter.add(SupplierRouter());
    _listRouter.add(CommodityRouter());
    _listRouter.add(ProductChangePriceRouter());
    _listRouter.add(NewApplicationRouter());
    _listRouter.add(PromotionPlanRouter());
    _listRouter.add(StoreChangePriceRouter());
    _listRouter.add(PrintingRouter());
    _listRouter.add(PrepackPriceRouter());
    _listRouter.add(InventoryRouter());
    _listRouter.add(WholesaleRouter());
    _listRouter.add(FinanceRouter());
    _listRouter.add(WmsReceiveRouter());
    _listRouter.add(WmsLaunchRouter());
    _listRouter.add(WmsRestockRouter());
    _listRouter.add(WmsStockQueryRouter());
    _listRouter.add(WmsSetRouter());

    _listRouter.add(CashFlowRouter());
    _listRouter.add(CashStatisticsRouter());
    _listRouter.add(CashierMonitoringRouter());
    _listRouter.add(ExceptionMonitoringRouter());
    _listRouter.add(SalesRateAnalysisRouter());
    _listRouter.add(BusinessAnalysisRouter());
    _listRouter.add(ProductAbcRouter());
    _listRouter.add(TypeAbcRouter());

    _listRouter.add(ChangQueRouter());
    _listRouter.add(UnsalableRouter());
    _listRouter.add(ZeroStockRouter());
    _listRouter.add(LoadStockRouter());
    _listRouter.add(EnterUnsoldRouter());
    _listRouter.add(InventoryWarnRouter());
    _listRouter.add(VaildWarnRouter());

    _listRouter.add(ManagementRouter());

    _listRouter.add(AddVipAnalysisRouter());
    _listRouter.add(ConsumptionTopRouter());
    _listRouter.add(CouponAnalysisRouter());

    /// 初始化路由
    void initRouter(IRouterProvider routerProvider) {
      routerProvider.initRouter(router);
    }

    _listRouter.forEach(initRouter);
  }
}
