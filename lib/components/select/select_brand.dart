import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';

/// 品牌选择组件 —— 统一收口在 components/select
///
/// 支持底部抽屉方式和全页路由方式两种打开模式。
/// 接口: bi/brand/getBrandList，返回 name 字段为品牌名称。
class SelectBrandPage extends StatelessWidget {
  const SelectBrandPage({super.key, this.onTap});
  final void Function(Map<String, dynamic>)? onTap;

  static Future<Map<String, dynamic>?> _fetchData(String searchText, int page) {
    return request(HttpApi.brandList, {
      'name': searchText,
      'is_page': 1,
      'page': page,
      'pagesize': 20,
    }).then((result) {
      final data = result['data'];
      return data is Map<String, dynamic> ? data : null;
    });
  }

  /// 以底部抽屉方式打开品牌选择
  ///
  /// [showAll] 是否展示“全部”选项，默认 true
  static Future<Map<String, dynamic>?> show(BuildContext context,
      {String? initialSelectedId, bool showAll = true}) {
    return CommonSelectSheet.show(
      context,
      title: '选择品牌',
      searchHint: '输入品牌名称',
      fetchData: _fetchData,
      idField: 'name',
      showAll: showAll,
      initialSelectedId: initialSelectedId,
      mapResult: (item) {
        final name = item['name']?.toString() ?? '';
        final code = item['code']?.toString() ?? '';
        final displayName = code.isNotEmpty ? '[$code]$name' : name;
        return {
          'name': displayName,
          'brandname': displayName,
          'rawName': name,
          'code': code,
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CommonSelectSheet(
        title: '选择品牌',
        searchHint: '输入品牌名称',
        fetchData: _fetchData,
        idField: 'name',
        showAll: true,
        mapResult: (item) {
          final name = item['name']?.toString() ?? '';
          final code = item['code']?.toString() ?? '';
          final displayName = code.isNotEmpty ? '[$code]$name' : name;
          final selected = {
            'name': displayName,
            'brandname': displayName,
            'rawName': name,
            'code': code,
          };
          onTap?.call(selected);
          return selected;
        },
      ),
    );
  }
}
