import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

class SelectWarehousePage extends StatelessWidget {
  /// 入库机构ID，由调用方传入
  final int? bsid;
  final void Function(Map<String, dynamic>)? onTap;

  const SelectWarehousePage({super.key, this.bsid, this.onTap});

  int _getBsid() {
    // 优先使用传入的 bsid，否则从 SpUtil 获取
    if (bsid != null) return bsid!;
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap['id'] as int? ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<Map<String, dynamic>?> _fetchData(String searchText, int page) {
    final int bsidValue = _getBsid();
    return request(HttpApi.counterGetList, {
      'sids': bsidValue.toString(),
      'stopflag': 0,
      'cond': searchText,
      'is_page': 1,
      'page': page,
    }).then((result) {
      final data = result['data'];
      return data is Map<String, dynamic> ? data : null;
    });
  }

  /// 以底部抽屉方式打开仓库选择
  static Future<Map<String, dynamic>?> show(BuildContext context, {int? bsid, String? initialSelectedId, bool showAll = false}) {
    int getBsid() {
      if (bsid != null) return bsid;
      try {
        final String storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          final Map<String, dynamic> storeMap =
              jsonDecode(storeStr) as Map<String, dynamic>;
          return storeMap['id'] as int? ?? 0;
        }
      } catch (_) {}
      return 0;
    }

    Future<Map<String, dynamic>?> fetchData(String searchText, int page) {
      return request(HttpApi.counterGetList, {
        'sids': getBsid().toString(),
        'stopflag': 0,
        'cond': searchText,
        'is_page': 1,
        'page': page,
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      });
    }

    return CommonSelectSheet.show(
      context,
      title: '选择入库仓库',
      searchHint: '输入仓库名称/编码',
      fetchData: fetchData,
      nameField: 'countername',
      codeField: 'countercode',
      idField: 'counterid',
      showAll: showAll,
      initialSelectedId: initialSelectedId,
      mapResult: (item) {
        final name = item['countername']?.toString() ?? '';
        return {
          'counterid': item['counterid']?.toString() ?? '',
          'countername': name,
          'countertype': item['countertype']?.toString() ?? '',
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CommonSelectSheet(
        title: '选择入库仓库',
        searchHint: '输入仓库名称/编码',
        fetchData: _fetchData,
        nameField: 'countername',
        codeField: 'countercode',
        idField: 'counterid',
        mapResult: (item) {
          final name = item['countername']?.toString() ?? '';
          final selected = {
            'counterid': item['counterid']?.toString() ?? '',
            'countername': name,
            'countertype': item['countertype']?.toString() ?? '',
          };
          onTap?.call(selected);
          return selected;
        },
      ),
    );
  }
}
