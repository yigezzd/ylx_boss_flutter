import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/business/members/point/point_edit.dart';
import 'package:flutter_deer/pages/business/members/shared/vip_select_list.dart';

/// 积分管理列表页 —— 对齐 boss 项目 subs/member/point/index.vue
class PointListPage extends StatelessWidget {
  const PointListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return VipSelectListPage(
      title: '积分管理',
      editRouteName: '/业务/会员/积分操作',
      buildEditPage: (item) => MemberPointEditPage(vipInfo: item),
    );
  }
}
