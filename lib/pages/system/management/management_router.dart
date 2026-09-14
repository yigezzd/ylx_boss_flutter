import 'package:fluro/fluro.dart';
import 'package:flutter_deer/pages/system/management/sys_seat_list_page.dart';
import 'package:flutter_deer/pages/system/management/sys_user_edit_page.dart';
import 'package:flutter_deer/pages/system/management/sys_user_list_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

class ManagementRouter implements IRouterProvider {
  static const String sysSeatList = '/system/sysSeatList';
  static const String sysUserList = '/system/sysUserList';
  static const String sysUserEdit = '/system/sysUser/edit';

  @override
  void initRouter(FluroRouter router) {
    router.define(sysSeatList, handler: Handler(handlerFunc: (_, __) => const SysSeatListPage()));
    router.define(sysUserList, handler: Handler(handlerFunc: (_, __) => const SysUserListPage()));
    router.define(sysUserEdit,
        handler: Handler(
            handlerFunc: (_, params) => SysUserEditPage(
                  user: params['user']?.first,
                )));
  }
}
