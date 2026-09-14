import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/business/members/recharge/recharge_edit.dart';
import 'package:flutter_deer/pages/business/members/shared/vip_select_list.dart';

/// 会员充值列表页 —— 对齐 boss 项目 subs/member/recharge/index.vue
///
/// 与积分管理/会员收款列表结构一致，额外显示右上角新增按钮（权限 010702）。
class RechargeListPage extends StatelessWidget {
  const RechargeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return VipSelectListPage(
      title: '会员充值',
      showAdd: true,
      editRouteName: '/业务/会员/会员充值',
      buildEditPage: (item) => MemberRechargeEditPage(vipInfo: item),
    );
  }
}
