import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 新增会员分析
/// 参考 D:\VUE\ylx-boss\src\subs\data\member\addVipAnalysis\index.vue
class AddVipAnalysisPage extends StatefulWidget {
  const AddVipAnalysisPage({super.key});
  @override
  State<AddVipAnalysisPage> createState() => _AddVipAnalysisPageState();
}

class _AddVipAnalysisPageState extends State<AddVipAnalysisPage> {
  // ── 门店 ──
  String _storeName = '';
  String _activeStoreId = '';
  int _bsid = 0;

  // ── 日期 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  // ── 数据 ──
  bool _loading = false;
  Map<String, dynamic> _vipInfo = {};

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时闪屏）
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = now;
    _startDate = now; // 默认当天
    _activeQuickTimeId = 1; // 默认今日
    _loadStore();
  }

  Future<void> _loadStore() async {
    try {
      final s = SpUtil.getString('store') ?? '';
      if (s.isNotEmpty) {
        final m = jsonDecode(s);
        final id = m['id']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _storeName = m['name']?.toString() ?? '';
            _activeStoreId = id;
            _bsid = int.tryParse(id) ?? 0;
          });
          _loadData();
        }
      }
    } catch (_) {}
  }

  Future<void> _selectStore() async {
    final r = await SelectStorePage.show(context, showAll: true, initialSelectedId: _activeStoreId);
    if (r != null && mounted) {
      setState(() {
        _storeName = r['storename']?.toString() ?? '';
        _activeStoreId = r['storeid']?.toString() ?? '';
        _bsid = int.tryParse(_activeStoreId) ?? 0;
      });
      _loadData();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final r = await request(HttpApi.addVipAnalysisList, {
        'bsid': _bsid,
        'sidsname': _storeName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'datetype': 1,
      });
      final data = r['data'];
      if (mounted) {
        setState(() {
          _vipInfo = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
          _hasLoadedOnce = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _vipInfo = {});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==================== 时间选择器（参考 cash_flow_page） ====================

  Widget _buildTimeSelector() {
    final labels = ['昨天', '今日', '本周', '本月', '自定义'];
    final activeId = _activeQuickTimeId ?? 1;
    const borderColor = Color(0xFFD1D5DB);
    const primary = Color(0xFF006EFF);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(children: [
        Container(
          height: 37,
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: List.generate(labels.length, (i) {
              final selected = activeId == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _onQuickTimeSelect(i),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 13,
                            color: selected ? Colors.white : const Color(0xFF333333))),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 10),
        _buildDateNavigation(),
      ]),
    );
  }

  void _onQuickTimeSelect(int id) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (id) {
      case 0: // 昨天
        start = now.subtract(const Duration(days: 1));
        end = start;
      case 1: // 今日
        start = now;
        end = now;
      case 2: // 本周
        final weekday = now.weekday;
        start = now.subtract(Duration(days: weekday - 1));
        end = start.add(const Duration(days: 6));
      case 3: // 本月
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
      default: // 自定义
        start = _startDate;
        end = _endDate;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _activeQuickTimeId = id;
    });
    _loadData();
  }

  Widget _buildDateNavigation() {
    final isRange = _activeQuickTimeId == 2 || _activeQuickTimeId == 4;
    final isMonth = _activeQuickTimeId == 3;
    final showArrows = _activeQuickTimeId != 4;

    return Row(children: [
      if (showArrows)
        GestureDetector(
          onTap: () => _timeShift(-1),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(Icons.chevron_left,
                size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      if (showArrows) const SizedBox(width: 8),
      Expanded(
        child: Row(children: [
          if (isRange) ...[
            Expanded(child: _buildDatePart(_startDate, isStart: true)),
            _buildDateToSeparator(),
            Expanded(child: _buildDatePart(_endDate, isEnd: true)),
          ] else
            Expanded(child: _buildDatePart(_startDate, isMonth: isMonth)),
        ]),
      ),
      if (showArrows) const SizedBox(width: 8),
      if (showArrows)
        GestureDetector(
          onTap: () => _timeShift(1),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(Icons.chevron_right,
                size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
    ]);
  }

  Widget _buildDatePart(DateTime date,
      {bool isStart = false, bool isEnd = false, bool isMonth = false}) {
    String label;
    if (isMonth) {
      label = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    } else {
      label = _fmtDate(date);
    }
    Future<void> onTap() async {
      if (isMonth) {
        final picked = await showCommonMonthPicker(context, initial: date);
        if (picked != null && mounted) {
          setState(() {
            _startDate = DateTime(picked.year, picked.month);
            _endDate = DateTime(picked.year, picked.month + 1, 0);
          });
          _loadData();
        }
        return;
      }
      final picked = await showCommonDatePicker(context, initial: date);
      if (picked != null && mounted) {
        setState(() {
          if (isEnd) {
            _endDate = picked;
          } else if (isStart) {
            _startDate = picked;
          } else {
            _startDate = picked;
            _endDate = picked;
          }
        });
        _loadData();
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
      ),
    );
  }

  Widget _buildDateToSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Text('至', style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
    );
  }

  void _timeShift(int direction) {
    final id = _activeQuickTimeId ?? 1;
    DateTime start = _startDate;
    DateTime end = _endDate;
    final originalStart = _startDate;
    switch (id) {
      case 0: // 昨天 ±1 day
      case 1: // 今日 ±1 day
        start = originalStart.add(Duration(days: direction));
        end = start;
      case 2: // 本周 ±7 days
        start = originalStart.add(Duration(days: 7 * direction));
        end = start.add(const Duration(days: 6));
      case 3: // 本月 ±1 month
        start = DateTime(originalStart.year, originalStart.month + direction);
        end = DateTime(start.year, start.month + 1, 0);
      default:
        return;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    _loadData();
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('新增会员', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Column(children: [
        // 门店选择
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _buildDropBtn(
              label: _storeName.isNotEmpty ? _storeName : '全部机构', onTap: _selectStore),
        ),
        // 时间选择器
        _buildTimeSelector(),
        // 内容
        Expanded(
          child: Stack(children: [
            if (_loading && _vipInfo.isEmpty && !_hasLoadedOnce)
              const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
            else
              ListView(padding: const EdgeInsets.all(12), children: [
                _buildSummaryCards(),
                const SizedBox(height: 12),
                _buildDonutChart(),
                const SizedBox(height: 12),
                _buildSourceTable(),
                const SizedBox(height: 12),
                _buildStoreTable(),
              ]),
            // 刷新时仅居中图标卡片，内容保持可见（避免闪屏）
            if (_loading && _hasLoadedOnce) _loadingCard,
          ]),
        ),
      ]),
    );
  }

  /// 居中加载图标卡片（无全屏遮罩，避免加载中页面泛白）
  static const Widget _loadingCard = Positioned.fill(
    child: Center(
      child: SizedBox(
        width: 72,
        height: 72,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border.fromBorderSide(BorderSide(color: Color(0xFFE1E9F3))),
          ),
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF)),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildDropBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
        ]),
      ),
    );
  }

  // ──────────── 汇总卡片 ────────────
  Widget _buildSummaryCards() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
      child: Row(children: [
        Expanded(
          child: Column(children: [
            const Text('新增会员总数', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            const SizedBox(height: 6),
            Text('${_vipInfo['vipcardnum'] ?? 0}',
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          ]),
        ),
        Container(width: 1, height: 48, color: const Color(0xFFE0E0E0)),
        Expanded(
          child: Column(children: [
            const Text('累计会员数', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            const SizedBox(height: 6),
            Text('${_vipInfo['count'] ?? 0}',
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          ]),
        ),
      ]),
    );
  }

  // ──────────── 来源渠道列表 ────────────
  Widget _buildSourceTable() {
    final list =
        (_vipInfo['sourceList'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('新增会员来源',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
                child: Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)))),
          )
        else ...[
          _buildTableHeader(const ['来源名称', '会员数', '占比']),
          for (var i = 0; i < list.length; i++)
            _buildTableRow(
              [
                list[i]['clienttype']?.toString() ?? '',
                list[i]['vipcardnum']?.toString() ?? '0',
                list[i]['proportion']?.toString() ?? '0%',
              ],
              isOdd: i.isOdd,
            ),
        ],
      ]),
    );
  }

  // ──────────── 门店列表 ────────────
  Widget _buildStoreTable() {
    final list =
        (_vipInfo['storeList'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('新增会员占比',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
                child: Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)))),
          )
        else ...[
          _buildTableHeader(const ['序号', '门店', '新增会员数', '占比']),
          for (var i = 0; i < list.length; i++)
            _buildTableRow(
              [
                '${i + 1}',
                list[i]['storeName']?.toString() ?? '',
                list[i]['vipcardnum']?.toString() ?? '0',
                list[i]['proportion']?.toString() ?? '0%',
              ],
              isOdd: i.isOdd,
            ),
        ],
      ]),
    );
  }

  Widget _buildTableHeader(List<String> labels) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFE1E9F3),
        border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
      ),
      child: Row(children: [
        for (final label in labels)
          Expanded(
            child: Text(label,
                textAlign: label == '占比' ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          ),
      ]),
    );
  }

  Widget _buildTableRow(List<String> cells, {required bool isOdd}) {
    return RepaintBoundary(
      child: Container(
        height: 40,
        decoration: isOdd
            ? const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFCFCFCF), width: 0.5),
                  bottom: BorderSide(color: Color(0xFFCFCFCF), width: 0.5),
                ),
                color: Color(0xFFF8F7FF),
              )
            : null,
        child: Row(children: [
          for (var ci = 0; ci < cells.length; ci++)
            Expanded(
              child: Text(cells[ci],
                  textAlign: ci == cells.length - 1 ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
            ),
        ]),
      ),
    );
  }

  /// 环形饼图
  Widget _buildDonutChart() {
    final storeList = (_vipInfo['storeList'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (storeList.isEmpty) return const SizedBox.shrink();
    final total = storeList.fold<int>(
        0, (s, e) => s + (int.tryParse(e['vipcardnum']?.toString() ?? '0') ?? 0));
    return _DonutChart(data: storeList, total: total);
  }
}

// ==================== 环形饼图（ECharts，对齐 Vue total-chart 组件） ====================

class _DonutChart extends StatefulWidget {
  const _DonutChart({required this.data, required this.total});
  final List<Map<String, dynamic>> data;
  final int total;

  @override
  State<_DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<_DonutChart> {
  int _touchedIndex = -1;
  final Set<int> _hiddenIndices = {};

  static const _colors = [
    Color(0xFF3764FF),
    Color(0xFF49A4FF),
    Color(0xFFFF8C49),
    Color(0xFFFFC849),
    Color(0xFF49D1FF),
    Color(0xFFB449FF),
    Color(0xFF49BFA0),
    Color(0xFFFF4973),
  ];

  @override
  Widget build(BuildContext context) {
    final list = widget.data.map((item) {
      return {
        'name': item['storeName']?.toString() ?? '',
        'value': num.tryParse(item['vipcardnum']?.toString() ?? '0') ?? 0,
      };
    }).toList();
    if (list.isEmpty) return const SizedBox.shrink();

    // 可见项索引映射
    final visibleIndices = <int>[];
    int visibleTotal = 0;
    for (var i = 0; i < list.length; i++) {
      if (!_hiddenIndices.contains(i)) {
        visibleIndices.add(i);
        visibleTotal += (list[i]['value']! as num).toInt();
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
      child: Column(children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('门店分布',
              style:
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(
              PieChartData(
                centerSpaceRadius: 55,
                sectionsSpace: 2,
                borderData: FlBorderData(show: false),
                sections: _buildSections(list, visibleIndices),
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.touchedSection == null) {
                      return;
                    }
                    final vi = response.touchedSection!.touchedSectionIndex;
                    if (vi >= 0 && vi < visibleIndices.length) {
                      setState(() => _touchedIndex = visibleIndices[vi]);
                    }
                  },
                ),
              ),
            ),
            // 中心文字（对齐 Vue）
            IgnorePointer(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$visibleTotal',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF333333))),
                const Text('所有', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        _buildLegend(list),
      ]),
    );
  }

  List<PieChartSectionData> _buildSections(
      List<Map<String, dynamic>> list, List<int> visibleIndices) {
    final total = list.fold<num>(0, (s, e) => s + (e['value'] as num));
    if (total <= 0) return [];

    return List.generate(visibleIndices.length, (vi) {
      final i = visibleIndices[vi];
      final value = (list[i]['value'] as num).toDouble();
      final pct = (value / total * 100).toStringAsFixed(1);
      final clicked = i == _touchedIndex;
      final name = list[i]['name'] as String;

      return PieChartSectionData(
        color: _colors[i % _colors.length],
        value: value,
        title: clicked ? '$name $pct%' : '$pct%',
        radius: 50,
        titlePositionPercentageOffset: 0.85,
        titleStyle: TextStyle(
            fontSize: clicked ? 13 : 10,
            color: Colors.black,
            fontWeight: clicked ? FontWeight.w700 : FontWeight.w400),
      );
    });
  }

  Widget _buildLegend(List<Map<String, dynamic>> list) {
    return Wrap(
        spacing: 16,
        runSpacing: 6,
        children: List.generate(list.length, (i) {
          final hidden = _hiddenIndices.contains(i);
          return GestureDetector(
            onTap: () => setState(() {
              if (hidden) {
                _hiddenIndices.remove(i);
              } else {
                _hiddenIndices.add(i);
                if (_touchedIndex == i) _touchedIndex = -1;
              }
            }),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: hidden
                          ? _colors[i % _colors.length].withOpacity(0.25)
                          : _colors[i % _colors.length],
                      shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('${list[i]['name']}（${list[i]['value']}）',
                  style: TextStyle(
                      fontSize: 12,
                      color: hidden ? const Color(0xFFCCCCCC) : const Color(0xFF666666),
                      decoration: hidden ? TextDecoration.lineThrough : TextDecoration.none)),
            ]),
          );
        }));
  }
}
