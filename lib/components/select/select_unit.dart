import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/common_select_page.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';

/// 单位选择页面
/// 接口: bi/unit/getUnitList，字段 name 为单位名（如：个、箱、KG）
class SelectUnitPage extends StatelessWidget {
  const SelectUnitPage({
    super.key,
    this.onTap,
    this.excludedUnit = '',
  });

  /// 选中回调，返回 {'name': 'xxx'}
  final void Function(Map<String, dynamic>)? onTap;

  /// 需要排除的单位名称（如商品基本单位）
  final String excludedUnit;

  /// 以底部抽屉方式打开单位选择（对齐小程序 selectCom bi/unit/getUnitList）
  /// 返回 {'name': 'xxx'}（单位名即 id，对齐小程序 idKey/nameKey 均为 name）
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    String title = '选择单位',
    String? initialSelectedId,
  }) {
    Future<Map<String, dynamic>?> fetchData(String searchText, int page) {
      return request(HttpApi.unitGetList, {
        'is_page': 1,
        'page': page,
        'pagesize': 50,
        'name': searchText,
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      });
    }

    return CommonSelectSheet.show(
      context,
      title: title,
      searchHint: '输入单位名称',
      fetchData: fetchData,
      idField: 'name',
      initialSelectedId: initialSelectedId,
      mapResult: (item) {
        return {
          'name': item['name']?.toString() ?? '',
        };
      },
    );
  }

  Future<Map<String, dynamic>?> _fetchData(String searchText, int page) {
    return request(HttpApi.unitGetList, {
      'is_page': 1,
      'page': page,
      'pagesize': 50,
      'name': searchText,
    }).then((result) {
      final data = result['data'];
      if (data is! Map<String, dynamic>) return null;
      final list = data['list'] as List? ?? [];
      // 过滤掉基本单位
      if (excludedUnit.isNotEmpty) {
        data['list'] = list.where((e) {
          final name = e is Map<String, dynamic> ? e['name']?.toString() ?? '' : e.toString();
          return name != excludedUnit;
        }).toList();
      }
      return data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CommonSelectPage(
      title: '选择单位',
      searchHint: '输入单位名称',
      fetchData: _fetchData,
      mapResult: (item) {
        final selected = {
          'name': item['name']?.toString() ?? '',
        };
        onTap?.call(selected);
        return selected;
      },
    );
  }
}
