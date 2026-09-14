import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/finance/cost_revenue/edit.dart';
import 'package:flutter_deer/pages/business/finance/cost_revenue/list.dart';
import 'package:flutter_deer/pages/business/finance/customer_pay/edit.dart';
import 'package:flutter_deer/pages/business/finance/customer_pay/list.dart';
import 'package:flutter_deer/pages/business/finance/store_pay/edit.dart';
import 'package:flutter_deer/pages/business/finance/store_pay/list.dart';
import 'package:flutter_deer/pages/business/finance/supplier_pay/edit.dart';
import 'package:flutter_deer/pages/business/finance/supplier_pay/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class FinanceRouter implements IRouterProvider {
  static const String supplierPayList = '/finance/supplierPay/list';
  static const String supplierPayEdit = '/finance/supplierPay/edit';
  static const String customerPayList = '/finance/customerPay/list';
  static const String customerPayEdit = '/finance/customerPay/edit';
  static const String storePayList = '/finance/storePay/list';
  static const String storePayEdit = '/finance/storePay/edit';
  static const String costRevenueList = '/finance/costRevenue/list';
  static const String costRevenueEdit = '/finance/costRevenue/edit';

  @override
  void initRouter(FluroRouter router) {
    router.define(supplierPayList,
        handler: Handler(handlerFunc: (_, __) => const SupplierPayListPage()));
    router.define(supplierPayEdit, handler: Handler(handlerFunc: (_, params) {
      final billid = params['billid']?.first ?? '';
      return SupplierPayEditPage(billid: billid);
    }));
    router.define(customerPayList,
        handler: Handler(handlerFunc: (_, __) => const CustomerPayListPage()));
    router.define(customerPayEdit, handler: Handler(handlerFunc: (_, params) {
      final billid = params['billid']?.first ?? '';
      return CustomerPayEditPage(billid: billid);
    }));
    router.define(storePayList, handler: Handler(handlerFunc: (_, __) => const StorePayListPage()));
    router.define(storePayEdit, handler: Handler(handlerFunc: (_, params) {
      final billid = params['billid']?.first ?? '';
      return StorePayEditPage(billid: billid);
    }));
    router.define(costRevenueList,
        handler: Handler(handlerFunc: (_, __) => const CostRevenueListPage()));
    router.define(costRevenueEdit, handler: Handler(handlerFunc: (_, params) {
      final billid = params['billid']?.first ?? '';
      return CostRevenueEditPage(billid: billid);
    }));
  }
}
