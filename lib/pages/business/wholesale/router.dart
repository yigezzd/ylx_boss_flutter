import 'package:flutter_deer/pages/business/wholesale/cust_manage/list.dart';
import 'package:flutter_deer/pages/business/wholesale/cust_manage/edit.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_order/list.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_order/edit.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_order/search.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_sale/list.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_sale/edit.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_sale/search.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_return/list.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_return/edit.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_return/search.dart';
import 'package:flutter_deer/pages/business/wholesale/order_sum/list.dart';
import 'package:flutter_deer/pages/business/wholesale/receive_sum/list.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_customer.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_salesperson.dart';
import 'package:flutter_deer/routers/i_router.dart';
import 'package:fluro/fluro.dart';

class WholesaleRouter implements IRouterProvider {
  static const String custManageList = '/wholesale/cust_manage/list';
  static const String custManageEdit = '/wholesale/cust_manage/edit';
  static const String pfOrderList = '/wholesale/pf_order/list';
  static const String pfOrderEdit = '/wholesale/pf_order/edit';
  static const String pfOrderSearch = '/wholesale/pf_order/search';
  static const String pfSaleList = '/wholesale/pf_sale/list';
  static const String pfSaleEdit = '/wholesale/pf_sale/edit';
  static const String pfSaleSearch = '/wholesale/pf_sale/search';
  static const String pfReturnList = '/wholesale/pf_return/list';
  static const String pfReturnEdit = '/wholesale/pf_return/edit';
  static const String pfReturnSearch = '/wholesale/pf_return/search';
  static const String orderSumList = '/wholesale/order_sum/list';
  static const String receiveSumList = '/wholesale/receive_sum/list';
  static const String selectCustomer = '/wholesale/select/customer';
  static const String selectSalesperson = '/wholesale/select/salesperson';

  @override
  void initRouter(FluroRouter router) {
    router.define(custManageList, handler: Handler(handlerFunc: (_, __) => const CustManageListPage()));
    router.define(custManageEdit, handler: Handler(handlerFunc: (_, __) => const CustManageEditPage()));
    router.define(pfOrderList, handler: Handler(handlerFunc: (_, __) => const PfOrderListPage()));
    router.define(pfOrderEdit, handler: Handler(handlerFunc: (_, __) => const PfOrderEditPage()));
    router.define(pfOrderSearch, handler: Handler(handlerFunc: (_, __) => const PfOrderSearchPage()));
    router.define(pfSaleList, handler: Handler(handlerFunc: (_, __) => const PfSaleListPage()));
    router.define(pfSaleEdit, handler: Handler(handlerFunc: (_, __) => const PfSaleEditPage()));
    router.define(pfSaleSearch, handler: Handler(handlerFunc: (_, __) => const PfSaleSearchPage()));
    router.define(pfReturnList, handler: Handler(handlerFunc: (_, __) => const PfReturnListPage()));
    router.define(pfReturnEdit, handler: Handler(handlerFunc: (_, __) => const PfReturnEditPage()));
    router.define(pfReturnSearch, handler: Handler(handlerFunc: (_, __) => const PfReturnSearchPage()));
    router.define(orderSumList, handler: Handler(handlerFunc: (_, __) => const OrderSumListPage()));
    router.define(receiveSumList, handler: Handler(handlerFunc: (_, __) => const ReceiveSumListPage()));
    router.define(selectCustomer, handler: Handler(handlerFunc: (_, __) => const SelectCustomerPage()));
    router.define(selectSalesperson, handler: Handler(handlerFunc: (_, __) => const SelectSalespersonPage()));
  }
}
