import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/purchase/supplier/add.dart';
import 'package:flutter_deer/pages/business/purchase/supplier/list.dart';
import 'package:flutter_deer/routers/i_router.dart';

class SupplierRouter implements IRouterProvider {
  static const String supplierList = '/purchase/supplier/list';
  static const String supplierAdd = '/purchase/supplier/add';

  @override
  void initRouter(FluroRouter router) {
    router.define(
      supplierList,
      handler: Handler(
        handlerFunc: (_, __) => const SupplierListPage(),
      ),
    );
    router.define(
      supplierAdd,
      handler: Handler(
        handlerFunc: (_, __) => const SupplierAddPage(),
      ),
    );
  }
}
