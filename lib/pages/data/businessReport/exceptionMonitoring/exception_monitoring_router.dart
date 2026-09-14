import 'dart:convert';

import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/data/businessReport/exceptionMonitoring/exception_monitoring_detail_page.dart';
import 'package:flutter_deer/pages/data/businessReport/exceptionMonitoring/exception_monitoring_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class ExceptionMonitoringRouter implements IRouterProvider {
  static const String root = '/exceptionMonitoring';
  static const String bill = '/exceptionMonitoring/bill';

  @override
  void initRouter(FluroRouter router) {
    router.define(root, handler: Handler(handlerFunc: (_, __) => const ExceptionMonitoringPage()));
    router.define(bill, handler: Handler(handlerFunc: (context, params) {
      final rowJson = params['row']?.first ?? '{}';
      final row = jsonDecode(rowJson) as Map<String, dynamic>;
      return ExceptionMonitoringDetailPage(row: row);
    }));
  }
}
