import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 数据卡片设置页（对齐 Vue /subs/home/custom/index.vue）
class CardSettingPage extends StatefulWidget {
  const CardSettingPage({super.key});

  @override
  State<CardSettingPage> createState() => _CardSettingPageState();
}

class _CardSettingPageState extends State<CardSettingPage> {
  List<Map<String, dynamic>> _cardList = [];
  List<Map<String, dynamic>> _topList = [];
  dynamic _rawHomeCardData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    setState(() => _loading = true);
    try {
      String storeId = '';
      String spId = '';
      try {
        final storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          final store = jsonDecode(storeStr) as Map<String, dynamic>;
          storeId = store['id']?.toString() ?? '';
          spId = store['spid']?.toString() ?? '';
        }
      } catch (_) {}
      final params = <String, dynamic>{
        'sids': storeId.isEmpty || storeId == '0' ? <String>[] : <String>[storeId],
        'spid': spId,
      };
      final res = await request(HttpApi.homeGetHomeCard, params);
      final data = res['data'];
      if (data is List && data.isNotEmpty && data[0] is Map<String, dynamic>) {
        _rawHomeCardData = data;
        final details =
            (data[0]['getHomeCardDetailList'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        // 过滤掉营业数据和预警信息（常驻顶部，不可管理）
        _topList = details.where((e) => e['fieldid'] == 'yysj' || e['fieldid'] == 'yjxx').toList();
        _cardList = details.where((e) => e['fieldid'] != 'yysj' && e['fieldid'] != 'yjxx').toList()
          ..sort((a, b) => (a['isort'] as int?)?.compareTo(b['isort'] as int? ?? 0) ?? 0);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _handleSave() async {
    final list = <Map<String, dynamic>>[
      ..._topList,
      ..._cardList,
    ];
    int showCount = 0;
    for (int i = 0; i < list.length; i++) {
      list[i]['isort'] = i + 1;
      list[i]['datatype'] = 4;
      if (list[i]['show'] == 1) showCount++;
    }

    try {
      await request(HttpApi.homeSaveHomeCard, [
        {
          'clienttype': 'WEBAPP',
          'datatype': 4,
          'getHomeCardDetailList': list,
          'maxshowcount': showCount,
        }
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功'), duration: Duration(seconds: 1)),
        );
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  /// 默认卡片配置（对齐 Vue modeListDef）
  static const _defaultList = [
    {'fieldname': '付款方式', 'fieldid': 'fkfs', 'show': 1, 'isort': 3},
    {'fieldname': '营业额/客流量趋势', 'fieldid': 'qs', 'show': 1, 'isort': 4},
    {'fieldname': '分类/单品销售榜', 'fieldid': 'xsb', 'show': 1, 'isort': 5},
  ];

  void _handleReset() {
    setState(() {
      _cardList = _defaultList.map((e) => Map<String, dynamic>.from(e)..['datatype'] = 4).toList();
    });
  }

  void _moveItem(int oldIdx, int newIdx) {
    setState(() {
      if (newIdx > oldIdx) newIdx--;
      final item = _cardList.removeAt(oldIdx);
      _cardList.insert(newIdx, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('数据卡片设置'),
        backgroundColor: const Color(0xFF006EFF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 提示
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: const Color(0xFFFFF8E1),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Color(0xFFF59E0B)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '长按可拖动排序，开关控制显示和隐藏',
                          style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
                // 卡片列表
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _cardList.length,
                    itemExtent: 45,
                    onReorder: _moveItem,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) {
                          return ColoredBox(
                            color: const Color(0xFFF0F0F0),
                            child: child,
                          );
                        },
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final item = _cardList[index];
                      final show = item['show'] == 1;
                      return _CardSettingItem(
                        key: ValueKey('${item['fieldid']}_$index'),
                        index: index,
                        name: item['fieldname']?.toString() ?? '',
                        show: show,
                        onToggle: (v) => setState(() => item['show'] = v ? 1 : 0),
                      );
                    },
                  ),
                ),
                // 底部按钮
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _handleReset,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF333333),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('恢复默认'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006EFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CardSettingItem extends StatelessWidget {
  const _CardSettingItem({
    super.key,
    required this.index,
    required this.name,
    required this.show,
    required this.onToggle,
  });
  final int index;
  final String name;
  final bool show;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: Container(
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggle(!show),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  show ? Icons.visibility : Icons.visibility_off,
                  size: 22,
                  color: show ? const Color(0xFF666666) : const Color(0xFFFF4444),
                ),
              ),
            ),
            const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.drag_handle, size: 22, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }
}
