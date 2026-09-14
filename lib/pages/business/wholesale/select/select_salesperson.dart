import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';

class SelectSalespersonPage extends StatelessWidget {
  final void Function(Map<String, dynamic>)? onTap;

  const SelectSalespersonPage({super.key, this.onTap});

  static Future<Map<String, dynamic>?> _fetchData(String searchText, int page) {
    return request(HttpApi.sysUserList, {
      'cond': searchText,
      'stopflag': 0,
    }).then((result) {
      final data = result['data'];
      return data is Map<String, dynamic> ? data : null;
    });
  }

  static Future<Map<String, dynamic>?> show(BuildContext context, {String? initialSelectedId}) {
    return CommonSelectSheet.show(
      context,
      title: '选择业务员',
      searchHint: '输入业务员名称/编码',
      fetchData: _fetchData,
      nameField: 'name',
      codeField: 'code',
      idField: 'userid',
      showAll: true,
      initialSelectedId: initialSelectedId,
      mapResult: (item) {
        final name = item['name']?.toString() ?? '';
        final code = item['code']?.toString() ?? '';
        final displayName = code.isNotEmpty ? '[$code]$name' : name;
        return {
          'salesid': item['userid']?.toString() ?? '',
          'salesname': displayName,
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CommonSelectSheet(
        title: '选择业务员',
        searchHint: '输入业务员名称/编码',
        fetchData: _fetchData,
        nameField: 'name',
        codeField: 'code',
        idField: 'userid',
        mapResult: (item) {
          final name = item['name']?.toString() ?? '';
          final code = item['code']?.toString() ?? '';
          final displayName = code.isNotEmpty ? '[$code]$name' : name;
          final selected = {
            'salesid': item['userid']?.toString() ?? '',
            'salesname': displayName,
          };
          onTap?.call(selected);
          return selected;
        },
      ),
    );
  }
}
