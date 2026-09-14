import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/data/inventory/inventoryWarn/inventory_warn_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class InventoryWarnRouter implements IRouterProvider {
  static const String root = '/inventoryWarn';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (context, params) {
      String? currTab;
      if (context != null) {
        final route = ModalRoute.of(context);
        final args = route?.settings.arguments;
        if (args is Map<String, dynamic>) {
          currTab = args['currTab']?.toString();
        }
      }
      return InventoryWarnPage(currTab: currTab);
    }));
  }
}
