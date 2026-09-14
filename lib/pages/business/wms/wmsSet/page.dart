import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 设置页（对齐 Vue wms/wmsSet/index.vue）
class WmsSetPage extends StatefulWidget {
  const WmsSetPage({super.key});

  @override
  State<WmsSetPage> createState() => _WmsSetPageState();
}

class _WmsSetPageState extends State<WmsSetPage> {
  /// 默认仓库 id（对齐 Vue query.wmscounterid）
  String _wmscounterid = '';
  String _wmscountername = '';

  String _storeId = '';
  dynamic _storetype;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLocalInfo();
    _loadWmsSet();
  }

  void _loadLocalInfo() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeId = storeMap['id']?.toString() ?? '';
        _storetype = storeMap['storetype'];
      }
    } catch (_) {}
  }

  /// 获取当前 WMS 设置（对齐 Vue getwmsSet）
  Future<void> _loadWmsSet() async {
    try {
      final result = await request(HttpApi.wmsSetGet, <String, dynamic>{});
      if (!mounted) return;
      final res = result['data'];
      final wmscounterid =
          (res is Map<String, dynamic> ? res['wmscounterid'] : null)?.toString() ?? '';
      if (wmscounterid.isEmpty) return;
      _wmscounterid = wmscounterid;
      // 反查仓库名称用于展示
      final counterResult = await request(HttpApi.counterGetList, {
        'wmsflag': 1,
        'sids': [_storeId],
        'nosidsflag': 1,
        'stopflag': 0,
        'pscounterflag': _storetype == 0 ? 1 : '',
      });
      if (!mounted) return;
      final counterData = counterResult['data'];
      final list =
          (counterData is Map<String, dynamic> ? counterData['list'] : null) as List? ?? [];
      for (final c in list.whereType<Map<String, dynamic>>()) {
        if (c['counterid']?.toString() == wmscounterid) {
          _wmscountername = c['countername']?.toString() ?? '';
          break;
        }
      }
      setState(() {});
    } catch (_) {}
  }

  /// 选择默认仓库（对齐 Vue ep-select change）
  Future<void> _openCounterSelect() async {
    Future<Map<String, dynamic>?> fetchData(String searchText, int page) {
      return request(HttpApi.counterGetList, {
        'wmsflag': 1,
        'sids': [_storeId],
        'nosidsflag': 1,
        'stopflag': 0,
        'pscounterflag': _storetype == 0 ? 1 : '',
        'cond': searchText,
        'is_page': 1,
        'page': page,
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      });
    }

    final result = await CommonSelectSheet.show(
      context,
      title: '选择默认仓库',
      searchHint: '输入仓库名称/编码',
      fetchData: fetchData,
      nameField: 'countername',
      codeField: 'countercode',
      idField: 'counterid',
      initialSelectedId: _wmscounterid.isNotEmpty ? _wmscounterid : null,
      mapResult: (item) => {
        'counterid': item['counterid']?.toString() ?? '',
        'countername': item['countername']?.toString() ?? '',
      },
    );
    if (result == null || !mounted) return;
    final counterid = result['counterid']?.toString() ?? '';
    if (counterid.isEmpty || counterid == _wmscounterid) return;
    setState(() {
      _wmscounterid = counterid;
      _wmscountername = result['countername']?.toString() ?? '';
    });
    _saveWmsSet();
  }

  /// 保存 WMS 设置（对齐 Vue setwmsSet，Vue 在页面卸载时保存，
  /// Flutter 端改为选择后立即保存，交互结果一致）
  Future<void> _saveWmsSet() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await request(HttpApi.wmsSetSave, {
        'paramType': 17,
        'data': {'wmscounterid': _wmscounterid},
      });
      if (!mounted) return;
      Toast.show('设置成功');
    } catch (_) {
      // 请求层已统一提示错误
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'WMS设置',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GestureDetector(
              onTap: _openCounterSelect,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    const Text(
                      '默认仓库',
                      style: TextStyle(fontSize: 14, color: Color(0xFF707070)),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        _wmscountername.isNotEmpty ? _wmscountername : '请选择',
                        style: TextStyle(
                          fontSize: 14,
                          color: _wmscountername.isNotEmpty
                              ? const Color(0xFF111827)
                              : const Color(0xFF999999),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFF999999)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
