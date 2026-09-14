import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 货架编号选择组件（对齐小程序 more.vue selectCom location）
///
/// 接口: bi/location/getList，字段 locationcode / locationid。
/// 传参: storeid（当前门店）、zonetype=1。
class SelectLocationPage extends StatelessWidget {
  const SelectLocationPage({super.key});

  /// 以底部抽屉方式打开货位选择
  ///
  /// [zonetype] 货位区域类型：1=货架编号（默认），2=存货位（上架），3=收货暂存区（WMS收货）；
  /// 传 null 时不限制区域类型（货位库存查询/移货场景）。
  /// [title] 自定义标题；[withStopflag] 额外传 stopflag=''；
  /// [counterid] 仓库筛选；[zonetypenot] 排除的区域类型；[locationIdnot] 排除的货位 id。
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    String? initialSelectedId,
    int? zonetype = 1,
    String? title,
    bool withStopflag = false,
    String? counterid,
    String? zonetypenot,
    String? locationIdnot,
  }) {
    // 获取当前门店 ID
    String storeid = '';
    final storeStr = SpUtil.getString('store') ?? '';
    if (storeStr.isNotEmpty) {
      try {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        storeid = storeMap['id']?.toString() ?? '';
      } catch (_) {}
    }

    Future<Map<String, dynamic>?> fetchData(String searchText, int page) {
      final params = <String, dynamic>{
        'cond': searchText, // 对齐 Vue selectCom：搜索字段为 cond（非 name）
        'storeid': storeid,
        'is_page': 1,
        'page': page,
        'pagesize': 20,
      };
      if (zonetype != null) params['zonetype'] = zonetype;
      // 对齐 Vue：收货暂存区选择额外传 stopflag
      if (zonetype == 3 || withStopflag) params['stopflag'] = '';
      if (counterid != null && counterid.isNotEmpty) {
        params['counterid'] = counterid;
      }
      if (zonetypenot != null && zonetypenot.isNotEmpty) {
        params['zonetypenot'] = zonetypenot;
      }
      if (locationIdnot != null && locationIdnot.isNotEmpty) {
        params['locationIdnot'] = locationIdnot;
      }
      return request(HttpApi.locationGetList, params).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      });
    }

    final bool isWms = zonetype != 1;
    return CommonSelectSheet.show(
      context,
      title: title ?? (isWms ? '选择货位号' : '选择货架编号'),
      searchHint: isWms ? '输入货位号名称/编码' : '输入货架编号',
      fetchData: fetchData,
      nameField: 'locationname',
      codeField: 'locationcode',
      idField: 'locationid',
      initialSelectedId: initialSelectedId,
      mapResult: (item) {
        return {
          'locationcode': item['locationcode']?.toString() ?? '',
          'locationid': item['locationid']?.toString() ?? '',
          'locationname': item['locationname']?.toString() ?? '',
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
