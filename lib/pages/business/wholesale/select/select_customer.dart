import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';

class SelectCustomerPage extends StatelessWidget {
  final void Function(Map<String, dynamic>)? onTap;

  const SelectCustomerPage({super.key, this.onTap});

  static Future<Map<String, dynamic>?> _fetchData(String searchText, int page) {
    return request(HttpApi.customerFindList, {
      'notwx': 1,
      'cond': searchText,
      'is_page': 1,
      'page': page,
      'pagesize': 20,
    }).then((result) {
      final data = result['data'];
      return data is Map<String, dynamic> ? data : null;
    });
  }

  static Future<Map<String, dynamic>?> show(BuildContext context, {String? initialSelectedId}) {
    return CommonSelectSheet.show(
      context,
      title: '选择客户',
      searchHint: '输入客户名称/编码',
      fetchData: _fetchData,
      nameField: 'name',
      codeField: 'code',
      idField: 'custid',
      showAll: true,
      initialSelectedId: initialSelectedId,
      mapResult: (item) {
        final name = item['name']?.toString() ?? '';
        final code = item['code']?.toString() ?? '';
        return {
          'custid': item['custid']?.toString() ?? item['id']?.toString() ?? '',
          'custname': name,
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
        title: '选择客户',
        searchHint: '输入客户名称/编码',
        fetchData: _fetchData,
        nameField: 'name',
        codeField: 'code',
        idField: 'custid',
        mapResult: (item) {
          final name = item['name']?.toString() ?? '';
          final code = item['code']?.toString() ?? '';
          final selected = {
            'custid': item['custid']?.toString() ?? item['id']?.toString() ?? '',
            'custname': name,
            'code': code,
          };
          onTap?.call(selected);
          return selected;
        },
      ),
    );
  }
}
