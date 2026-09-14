import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/inventory/plan/list.dart';
import 'package:flutter_deer/pages/business/inventory/plan/add.dart';
import 'package:flutter_deer/pages/business/inventory/precheck/list.dart';
import 'package:flutter_deer/pages/business/inventory/precheck/add.dart';
import 'package:flutter_deer/pages/business/inventory/quickcheck/list.dart';
import 'package:flutter_deer/pages/business/inventory/quickcheck/add.dart';
import 'package:flutter_deer/pages/business/inventory/otherout/list.dart';
import 'package:flutter_deer/pages/business/inventory/otherout/add.dart';
import 'package:flutter_deer/pages/business/inventory/otherin/list.dart';
import 'package:flutter_deer/pages/business/inventory/otherin/add.dart';
import 'package:flutter_deer/pages/business/inventory/movewarehouse/list.dart';
import 'package:flutter_deer/pages/business/inventory/movewarehouse/add.dart';
import 'package:flutter_deer/pages/business/inventory/costchange/list.dart';
import 'package:flutter_deer/pages/business/inventory/costchange/add.dart';
import 'package:flutter_deer/pages/business/inventory/search/list.dart';
import 'package:flutter_deer/pages/business/inventory/search/detail.dart';
import 'package:flutter_deer/routers/i_router.dart';

class InventoryRouter implements IRouterProvider {
  static const String inventoryPlanList = '/inventory/plan/list';
  static const String inventoryPlanAdd = '/inventory/plan/add';
  static const String inventoryPrecheckList = '/inventory/precheck/list';
  static const String inventoryPrecheckAdd = '/inventory/precheck/add';
  static const String inventoryQuickcheckList = '/inventory/quickcheck/list';
  static const String inventoryQuickcheckAdd = '/inventory/quickcheck/add';
  static const String inventoryOtheroutList = '/inventory/otherout/list';
  static const String inventoryOtheroutAdd = '/inventory/otherout/add';
  static const String inventoryOtherinList = '/inventory/otherin/list';
  static const String inventoryOtherinAdd = '/inventory/otherin/add';
  static const String inventoryMovewarehouseList = '/inventory/movewarehouse/list';
  static const String inventoryMovewarehouseAdd = '/inventory/movewarehouse/add';
  static const String inventoryCostchangeList = '/inventory/costchange/list';
  static const String inventoryCostchangeAdd = '/inventory/costchange/add';
  static const String inventorySearchList = '/inventory/search/list';
  static const String inventorySearchDetail = '/inventory/search/detail';

  @override
  void initRouter(FluroRouter router) {
    router.define(inventoryPlanList, handler: Handler(handlerFunc: (_, __) => const InventoryPlanListPage()));
    router.define(inventoryPlanAdd, handler: Handler(handlerFunc: (_, __) => const InventoryPlanAddPage()));
    router.define(inventoryPrecheckList, handler: Handler(handlerFunc: (_, __) => const InventoryPrecheckListPage()));
    router.define(inventoryPrecheckAdd, handler: Handler(handlerFunc: (_, __) => const InventoryPrecheckAddPage()));
    router.define(inventoryQuickcheckList, handler: Handler(handlerFunc: (_, __) => const InventoryQuickcheckListPage()));
    router.define(inventoryQuickcheckAdd, handler: Handler(handlerFunc: (_, __) => const InventoryQuickcheckAddPage()));
    router.define(inventoryOtheroutList, handler: Handler(handlerFunc: (_, __) => const InventoryOtheroutListPage()));
    router.define(inventoryOtheroutAdd, handler: Handler(handlerFunc: (_, __) => const InventoryOtheroutAddPage()));
    router.define(inventoryOtherinList, handler: Handler(handlerFunc: (_, __) => const InventoryOtherinListPage()));
    router.define(inventoryOtherinAdd, handler: Handler(handlerFunc: (_, __) => const InventoryOtherinAddPage()));
    router.define(inventoryMovewarehouseList, handler: Handler(handlerFunc: (_, __) => const InventoryMovewarehouseListPage()));
    router.define(inventoryMovewarehouseAdd, handler: Handler(handlerFunc: (_, __) => const InventoryMovewarehouseAddPage()));
    router.define(inventoryCostchangeList, handler: Handler(handlerFunc: (_, __) => const InventoryCostchangeListPage()));
    router.define(inventoryCostchangeAdd, handler: Handler(handlerFunc: (_, __) => const InventoryCostchangeAddPage()));
    router.define(inventorySearchList, handler: Handler(handlerFunc: (_, __) => const InventorySearchListPage()));
    router.define(inventorySearchDetail, handler: Handler(handlerFunc: (_, __) => const InventorySearchDetailPage(item: {})));
  }
}
