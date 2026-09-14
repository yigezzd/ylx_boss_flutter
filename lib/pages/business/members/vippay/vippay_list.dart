import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/business/members/shared/vip_select_list.dart';
import 'package:flutter_deer/pages/business/members/vippay/vippay_edit.dart';

/// 会员收款列表页 —— 对齐 boss 项目 subs/member/vippay/index.vue
class VippayListPage extends StatelessWidget {
  const VippayListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return VipSelectListPage(
      title: '会员收款',
      editRouteName: '/业务/会员/会员收款',
      buildEditPage: (item) => MemberVippayEditPage(vipInfo: item),
    );
  }
}
