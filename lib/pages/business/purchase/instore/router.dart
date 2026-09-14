import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/instore/add.dart';
import 'package:flutter_deer/pages/business/purchase/instore/list.dart';
import 'package:flutter_deer/pages/business/purchase/instore/search.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_refbill.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
import 'package:flutter_deer/routers/i_router.dart';

class PurchaseRouter implements IRouterProvider {
  static const String purchaseInstoreList = '/purchase/instore/list';
  static const String purchaseInstoreAdd = '/purchase/instore/add';
  static const String purchaseInstoreSearch = '/purchase/instore/search';
  static const String selectSupplier = '/purchase/select/supplier';
  static const String selectStore = '/purchase/select/store';
  static const String selectWarehouse = '/purchase/select/warehouse';
  static const String selectRefbill = '/purchase/select/refbill';
  static const String selectProduct = '/purchase/select/product';
  static const String selectBuyer = '/purchase/select/buyer';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      purchaseInstoreList,
      handler: Handler(
        handlerFunc: (_, __) => const PurchaseInstoreListPage(),
      ),
    );
    router.define(
      purchaseInstoreAdd,
      handler: Handler(
        handlerFunc: (_, __) => const PurchaseInstoreAddPage(),
      ),
    );
    router.define(
      purchaseInstoreSearch,
      handler: Handler(
        handlerFunc: (_, __) => const PurchaseInstoreSearchPage(),
      ),
    );
    router.define(selectSupplier, handler: Handler(handlerFunc: (_, __) => const SelectSupplierPage()));
    router.define(selectStore, handler: Handler(handlerFunc: (_, __) => const SelectStorePage()));
    router.define(selectWarehouse, handler: Handler(handlerFunc: (_, __) => const SelectWarehousePage()));
    router.define(selectRefbill, handler: Handler(handlerFunc: (_, __) => const SelectRefbillPage()));
    router.define(selectProduct, handler: Handler(handlerFunc: (_, __) => const SelectProductPage()));
    router.define(selectBuyer, handler: Handler(handlerFunc: (_, __) => const SelectBuyerPage()));
  }
}
