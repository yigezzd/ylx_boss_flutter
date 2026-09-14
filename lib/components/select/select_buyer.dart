import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';

class SelectBuyerPage extends StatelessWidget {
  const SelectBuyerPage({super.key});

  static Future<Map<String, dynamic>?> _fetchData(String searchText, int page) {
    return request(HttpApi.sysUserList, {
      'cond': searchText,
    }).then((result) {
      final data = result['data'];
      return data is Map<String, dynamic> ? data : null;
    });
  }

  /// 以底部抽屉方式打开经手人选择
  static Future<Map<String, dynamic>?> show(BuildContext context, {String? initialSelectedId, bool showAll = false}) {
    return CommonSelectSheet.show(
      context,
      title: '选择经手人',
      searchHint: '输入经手人名称/编码',
      fetchData: _fetchData,
      nameField: 'name',
      codeField: 'code',
      idField: 'userid',
      showAll: showAll,
      initialSelectedId: initialSelectedId,
      mapResult: (item) {
        final name = item['name']?.toString() ?? '';
        return {
          'buyerid': item['userid']?.toString() ?? '',
          'buyername': name,
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CommonSelectSheet(
        title: '选择经手人',
        searchHint: '输入经手人名称/编码',
        fetchData: _fetchData,
        nameField: 'name',
        codeField: 'code',
        idField: 'userid',
        mapResult: (item) {
          final name = item['name']?.toString() ?? '';
          return {
            'buyerid': item['userid']?.toString() ?? '',
            'buyername': name,
          };
        },
      ),
    );
  }
}
