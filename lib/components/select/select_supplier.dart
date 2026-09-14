import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

class SelectSupplierPage extends StatelessWidget {
  const SelectSupplierPage({super.key, this.onTap});
  final void Function(Map<String, dynamic>)? onTap;

  static int _getStoreId() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap['id'] as int? ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  static Future<Map<String, dynamic>?> _fetchData(
    String searchText,
    int page, {
    Map<String, dynamic>? extraParams,
  }) {
    final int storeId = _getStoreId();
    final params = <String, dynamic>{
      'stopflag': extraParams?['stopflag'] ?? '0,3',
      'bsid': storeId,
      'supselltypes': extraParams?['supselltypes'] ?? '1,3,4',
      'cond': searchText,
      'is_page': 1,
      'page': page,
    };
    return request(HttpApi.supplierList, params).then((result) {
      final data = result['data'];
      return data is Map<String, dynamic> ? data : null;
    });
  }

  /// 以底部抽屉方式打开供应商选择
  ///
  /// [extraParams] 额外接口参数，可覆盖默认的 supselltypes / stopflag
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    String? initialSelectedId,
    Map<String, dynamic>? extraParams,
  }) {
    return CommonSelectSheet.show(
      context,
      title: '选择供应商',
      searchHint: '输入供应商名称/编码',
      fetchData: (text, page) => _fetchData(text, page, extraParams: extraParams),
      idField: 'supid',
      showAll: true, // 支持"全部"选项
      initialSelectedId: initialSelectedId,
      mapResult: (item) {
        final name = item['name']?.toString() ?? '';
        final code = item['code']?.toString() ?? '';
        final displayName = code.isNotEmpty ? '[$code]$name' : name;
        return {
          'supid': item['supid']?.toString() ?? '',
          'supname': displayName,
          'name': name,
          'selltype': item['supselltype']?.toString() ?? '',
          'joinrate': item['joinrate']?.toString() ?? '',
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 路由兼容：用 Scaffold 包裹抽屉内容
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CommonSelectSheet(
        title: '选择供应商',
        searchHint: '输入供应商名称/编码',
        fetchData: _fetchData,
        idField: 'supid',
        mapResult: (item) {
          final name = item['name']?.toString() ?? '';
          final code = item['code']?.toString() ?? '';
          final displayName = code.isNotEmpty ? '[$code]$name' : name;
          final selected = {
            'supid': item['supid']?.toString() ?? '',
            'supname': displayName,
            'name': name,
            'selltype': item['supselltype']?.toString() ?? '',
          };
          onTap?.call(selected);
          return selected;
        },
      ),
    );
  }
}
