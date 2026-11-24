import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/business/members/vippay/vippay_record.dart';
import 'package:flutter_deer/pages/business/members/vippay/vippay_record_amplify.dart';
import 'package:flutter_deer/routers/i_router.dart';

/// 收款记录路由 —— 对齐 boss 项目 subs/member/vippay/record.vue + comPages/amplifyTable.vue
class VippayRecordRouter implements IRouterProvider {
  /// 收款记录列表页
  static const String vippayRecord = '/member/vippay/record';

  /// 收款记录放大表格页（params 经 arguments 透传）
  static const String vippayRecordAmplify = '/member/vippay/record/amplify';

  @override
  void initRouter(FluroRouter router) {
    router.define(vippayRecord, handler: Handler(handlerFunc: (_, __) => const VippayRecordPage()));
    router.define(vippayRecordAmplify, handler: Handler(handlerFunc: (context, params) {
      final dynamic args = context?.settings?.arguments;
      final Map<String, dynamic> recordParams =
          args is Map<String, dynamic> ? args : const <String, dynamic>{};
      return VippayRecordAmplifyPage(params: recordParams);
    }));
  }
}
