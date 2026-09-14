import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/purchase/supplier/add.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 供应商证照过期提醒页（对齐 Vue /subs/comPages/supFileWarn）
class SupFileWarnPage extends StatefulWidget {
  const SupFileWarnPage({super.key});

  @override
  State<SupFileWarnPage> createState() => _SupFileWarnPageState();
}

class _SupFileWarnPageState extends State<SupFileWarnPage> {
  List<Map<String, dynamic>> _list = [];
  int _totalCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 过期总数来自 getIndexTipTotal 的 supfilescount（对齐 Vue）
      final res = await request(HttpApi.getIndexTipTotal, <String, dynamic>{});
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        _totalCount = int.tryParse(data['supfilescount']?.toString() ?? '0') ?? 0;
      }
      // 过期证照列表（对齐 Vue findSupplierFilesList，参数 bsid = 门店 id）
      final storeStr = SpUtil.getString('store');
      String bsid = '';
      if (storeStr != null && storeStr.isNotEmpty) {
        final store = jsonDecode(storeStr);
        if (store is Map<String, dynamic>) {
          bsid = store['id']?.toString() ?? '';
        }
      }
      final fileRes = await request(HttpApi.supplierFindSupplierFilesList, {'bsid': bsid});
      final fileData = fileRes['data'];
      if (fileData is List) {
        _list = _castList(fileData);
      } else if (fileData is Map<String, dynamic>) {
        final raw = fileData['list'];
        if (raw is List) {
          _list = _castList(raw);
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  static List<Map<String, dynamic>> _castList(List<dynamic> raw) {
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        result.add(item);
      }
    }
    return result;
  }

  /// 点击跳转供应商详情页查看证照（对齐 Vue goEdit → supRecord/edit?isAdd=0）
  void _goEdit(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) {
      Toast.show('供应商不存在');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupplierAddPage(supplierId: id, mode: 0),
      ),
    );
  }

  /// 供应商名称展示：[code]name（参照供应商列表展示格式）
  static String _formatSupName(Map<String, dynamic> item) {
    final code = item['code']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    return code.isNotEmpty ? '[$code]$name' : name;
  }

  /// 兼容完整时间戳，统一输出 YYYY-MM-DD（无法解析时原样返回）
  static String _fmtDate(dynamic val) {
    if (val == null) {
      return '';
    }
    final raw = val.toString().trim();
    if (raw.isEmpty) {
      return '';
    }
    final dt = DateTime.tryParse(raw);
    if (dt == null) {
      return raw;
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('供应商过期提醒'),
        backgroundColor: const Color(0xFF006EFF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('暂无数据', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
          ],
        ),
      );
    }
    return ListView.builder(
      cacheExtent: 800,
      padding: const EdgeInsets.all(12),
      itemCount: _list.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummary();
        }
        final item = _list[index - 1];
        return RepaintBoundary(
          child: _WarnCard(
            item: item,
            onTap: () => _goEdit(item),
          ),
        );
      },
    );
  }

  /// 过期总数摘要卡（对齐 Vue 顶部 tm-sheet 摘要）
  Widget _buildSummary() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          text: '共 ',
          style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
          children: [
            TextSpan(
              text: '$_totalCount',
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFFFF4400),
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(text: ' 条供应商证照7天内过期，请及时处理'),
          ],
        ),
      ),
    );
  }
}

class _WarnCard extends StatelessWidget {
  const _WarnCard({required this.item, this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final supName = _SupFileWarnPageState._formatSupName(item);
    final documentname = item['documentname']?.toString() ?? '';
    final validtime = _SupFileWarnPageState._fmtDate(item['validtime']);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '供应商：$supName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF333333),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: Color(0xFF999999)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '证照名称：$documentname',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
            ),
            const SizedBox(height: 6),
            Text(
              '有效期：$validtime',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
            ),
          ],
        ),
      ),
    );
  }
}
