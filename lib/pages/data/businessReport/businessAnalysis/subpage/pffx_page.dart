import 'dart:async';
import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/analysis_chart.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 批发分析
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\businessAnalysis\subpage\pffx.vue
class PffxPage extends StatefulWidget {
  const PffxPage({super.key});
  @override
  State<PffxPage> createState() => _PffxPageState();
}

class _PffxPageState extends State<PffxPage> {
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';
  bool _isZd = false;

  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  bool _loading = true;
  List<Map<String, dynamic>> _list = [];
  Map<String, dynamic> _sumData = {};

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时闪屏）
  bool _hasLoadedOnce = false;

  String _listType = 'rramt';

  final ScrollController _hScrollController = ScrollController();
  final ScrollController _summaryHScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = now;
    _startDate = now; // 默认当天
    _activeQuickTimeId = 1; // 默认今日
    _hScrollController.addListener(_syncHScroll);
    _loadStore();
  }

  @override
  void dispose() {
    _hScrollController.removeListener(_syncHScroll);
    _hScrollController.dispose();
    _summaryHScrollController.dispose();
    super.dispose();
  }

  void _syncHScroll() {
    if (_summaryHScrollController.hasClients) {
      _summaryHScrollController.jumpTo(_hScrollController.offset);
    }
  }

  Future<void> _loadStore() async {
    try {
      final s = SpUtil.getString('store') ?? '';
      if (s.isNotEmpty) {
        final m = jsonDecode(s);
        final id = m['id']?.toString() ?? '';
        final spid = m['spid']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _storeName = m['name']?.toString() ?? '';
            _activeStoreId = id;
            _sids = id.isNotEmpty ? [int.tryParse(id) ?? 0] : [];
            _isZd = id == spid;
          });
          _loadData();
        }
      }
    } catch (_) {}
  }

  Future<void> _selectStore() async {
    if (!_isZd) return;
    final r = await SelectStorePage.show(context, showAll: true, initialSelectedId: _activeStoreId);
    if (r != null && mounted) {
      setState(() {
        final storeId = r['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
        _storeName = r['storename']?.toString() ?? '';
      });
      _loadData();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get _selectdatetype {
    switch (_activeQuickTimeId) {
      case 0:
      case 1:
        return 1;
      default:
        return 3;
    }
  }

  static String _formatDecimal(int digits, dynamic v) {
    final num n = v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
    return n.toStringAsFixed(digits);
  }

  Future<void> _loadData() async {
    // 刷新时保留旧数据避免闪烁；首次加载才清空
    // 首次加载才清空列表；已加载过（含空数据）的后续刷新保留当前内容避免闪屏
    if (!_hasLoadedOnce) setState(() => _list = []);
    setState(() => _loading = true);
    try {
      final r = await request(HttpApi.bossJyfxGetPffx, {
        'is_page': 0,
        'sids': _sids,
        'sidsname': _storeName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'selectdatetype': _selectdatetype,
      });
      if (!mounted) return;
      final data = r['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _list = (data['list'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _sumData = (data['sumdata'] is Map<String, dynamic>)
              ? data['sumdata'] as Map<String, dynamic>
              : {};
          _hasLoadedOnce = true;
        });
      }
    } catch (_) {
      if (mounted) {
        if (!_hasLoadedOnce) {
          setState(() {
            _list = [];
            _sumData = {};
          });
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==================== 图 ====================

  List<({String label, double value})> get _chartData {
    if (_selectdatetype == 1) {
      final map = <int, double>{};
      for (final row in _list) {
        final raw = row['billdate']?.toString() ?? '';
        final time = raw.contains(' ') ? raw.split(' ').last : raw;
        final hour = int.tryParse(time.split(':').first) ?? 0;
        final val = double.tryParse(row[_listType]?.toString() ?? '0') ?? 0;
        map[hour] = val;
      }
      return List.generate(24, (h) => (label: '$h', value: map[h] ?? 0));
    }
    if (_activeQuickTimeId == 2) {
      const weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final dayMap = <String, double>{};
      for (final row in _list) {
        final raw = row['billdate']?.toString() ?? '';
        final dateKey = raw.length >= 10 ? raw.substring(0, 10) : raw;
        final val = double.tryParse(row[_listType]?.toString() ?? '0') ?? 0;
        dayMap[dateKey] = val;
      }
      return List.generate(7, (i) {
        final date = _startDate.add(Duration(days: i));
        final key = _fmtDate(date);
        return (label: weekLabels[i], value: dayMap[key] ?? 0);
      });
    }
    return _list.map((row) {
      final raw = row['billdate']?.toString() ?? '';
      String label;
      if (raw.contains('周')) {
        label = raw;
      } else {
        label = raw.replaceAll(RegExp(r'^\d{4}-'), '');
      }
      final val = double.tryParse(row[_listType]?.toString() ?? '0') ?? 0;
      return (label: label, value: val);
    }).toList();
  }

  List<String> get _chartTooltipLabels {
    if (_selectdatetype == 1) {
      final datePrefix = _fmtDate(_startDate).substring(5);
      return List.generate(24, (h) => '$datePrefix ${h.toString().padLeft(2, '0')}:00');
    }
    if (_activeQuickTimeId == 2) {
      const weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return List.generate(7, (i) {
        final date = _startDate.add(Duration(days: i));
        return '${_fmtDate(date).substring(5)} ${weekLabels[i]}';
      });
    }
    return _chartData.map((d) => d.label).toList();
  }

  String get _chartLabel => _listType == 'rramt'
      ? '销售额'
      : _listType == 'grossamt'
          ? '毛利额'
          : '毛利率';

  int get _tooltipDecimals => 2;

  String get _tooltipSuffix => _listType == 'grossrate' ? '%' : '';

  // ==================== 时间选择器 ====================
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
              border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(5)),
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
                    borderRadius: BorderRadius.circular(4)),
                child: Text(labels[i],
                    style: TextStyle(
                        fontSize: 13, color: selected ? Colors.white : const Color(0xFF333333))),
              ),
            ));
          })),
        ),
        const SizedBox(height: 10),
        _buildDateNavigation(),
      ]),
    );
  }

  void _onQuickTimeSelect(int id) {
    final now = DateTime.now();
    DateTime start, end;
    switch (id) {
      case 0:
        start = now.subtract(const Duration(days: 1));
        end = start;
        break;
      case 1:
        start = now;
        end = now;
        break;
      case 2:
        final wd = now.weekday;
        start = now.subtract(Duration(days: wd - 1));
        end = start.add(const Duration(days: 6));
        break;
      case 3:
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      default:
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
                    borderRadius: BorderRadius.circular(5)),
                child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF666666)))),
      if (showArrows) const SizedBox(width: 8),
      Expanded(
          child: Row(children: [
        if (isRange) ...[
          Expanded(child: _buildDatePart(_startDate, isStart: true)),
          _buildDateToSeparator(),
          Expanded(child: _buildDatePart(_endDate, isEnd: true)),
        ] else
          Expanded(child: _buildDatePart(_startDate, isMonth: isMonth)),
      ])),
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
                    borderRadius: BorderRadius.circular(5)),
                child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF666666)))),
    ]);
  }

  Widget _buildDatePart(DateTime date,
      {bool isStart = false, bool isEnd = false, bool isMonth = false}) {
    final String label =
        isMonth ? '${date.year}-${date.month.toString().padLeft(2, '0')}' : _fmtDate(date);
    Future<void> onTap() async {
      if (isMonth) {
        final p = await showCommonMonthPicker(context, initial: date);
        if (p != null && mounted) {
          setState(() {
            _startDate = DateTime(p.year, p.month);
            _endDate = DateTime(p.year, p.month + 1, 0);
          });
          _loadData();
        }
        return;
      }
      final p = await showCommonDatePicker(context, initial: date);
      if (p != null && mounted) {
        setState(() {
          if (isEnd)
            _endDate = p;
          else if (isStart)
            _startDate = p;
          else {
            _startDate = p;
            _endDate = p;
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
                borderRadius: BorderRadius.circular(5)),
            child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))));
  }

  void _timeShift(int direction) {
    final id = _activeQuickTimeId ?? 1;
    DateTime start = _startDate, end = _endDate;
    switch (id) {
      case 0:
      case 1:
        start = start.add(Duration(days: direction));
        end = start;
        break;
      case 2:
        start = start.add(Duration(days: 7 * direction));
        end = end.add(Duration(days: 7 * direction));
        break;
      case 3:
        start = DateTime(_startDate.year, _startDate.month + direction);
        end = DateTime(start.year, start.month + 1, 0);
        break;
      default:
        return;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    _loadData();
  }

  Widget _buildDateToSeparator() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Text('至', style: TextStyle(fontSize: 13, color: Color(0xFF666666))));

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('批发分析', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Stack(children: [
        Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: GestureDetector(
              onTap: _selectStore,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDEDEDE)),
                    borderRadius: BorderRadius.circular(5)),
                child: Row(children: [
                  Expanded(
                      child: Text(_storeName.isNotEmpty ? _storeName : '全部机构',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
                  if (_isZd) const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                ]),
              ),
            ),
          ),
          _buildTimeSelector(),
          if (_loading && _list.isEmpty && !_hasLoadedOnce)
            const Expanded(
                child: Center(child: CircularProgressIndicator(color: Color(0xFF006EFF))))
          else ...[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(
                    child: _buildMetricCard('销售额', _formatDecimal(3, _sumData['rramt']), 'rramt')),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildMetricCard(
                        '毛利额', _formatDecimal(3, _sumData['grossamt']), 'grossamt')),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildMetricCard(
                        '毛利率', '${_formatDecimal(3, _sumData['grossrate'])}%', 'grossrate')),
              ]),
            ),
            if (_chartData.isNotEmpty && _activeQuickTimeId != 4) ...[
              const SizedBox(height: 10),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: AnalysisChart(
                    data: _chartData,
                    valueLabel: _chartLabel,
                    showAllBottomLabels: _selectdatetype == 1 || _activeQuickTimeId == 2,
                    tooltipLabels: _chartTooltipLabels,
                    valueDecimals: _tooltipDecimals,
                    valueSuffix: _tooltipSuffix,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_list.isEmpty)
              const Expanded(
                  child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                SizedBox(height: 12),
                Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
              ])))
            else
              Expanded(child: _buildTable()),
          ],
        ]),
        // 加载提示：仅居中图标卡片，无全屏遮罩（避免加载中页面泛白如白屏）
        if (_loading && _hasLoadedOnce)
          const Positioned.fill(
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
          ),
      ]),
    );
  }

  Widget _buildMetricCard(String label, String value, String type) {
    final selected = _listType == type;
    return GestureDetector(
      onTap: () => setState(() => _listType = type),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: selected ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: selected ? const Color(0xFF006EFF) : const Color(0xFF7A7A7A))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333))),
        ]),
      ),
    );
  }

  Widget _buildTable() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    final sum = _sumData;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('批发销售明细',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333)))),
      Expanded(
        child: DataTable2(
          horizontalScrollController: _hScrollController,
          minWidth: 650,
          horizontalMargin: 0,
          columnSpacing: 0,
          dataRowHeight: 40,
          headingRowHeight: 44,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
          border: const TableBorder(
              horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
              verticalInside: BorderSide(color: Color(0xFFE1E9F3))),
          columns: const [
            DataColumn2(
                label: Padding(
                    padding: EdgeInsets.only(left: 5, right: 12),
                    child: Text('日期', style: headerStyle))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('销售额', style: headerStyle))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('成本额', style: headerStyle))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('毛利额', style: headerStyle))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('毛利率', style: headerStyle))),
          ],
          rows: [
            for (var i = 0; i < _list.length; i++)
              DataRow2(
                  decoration:
                      BoxDecoration(color: i.isOdd ? const Color(0xFFF9F9F9) : Colors.white),
                  cells: [
                    DataCell(Padding(
                        padding: const EdgeInsets.only(left: 5, right: 12),
                        child: Text(_list[i]['billdate']?.toString() ?? '', style: cellStyle))),
                    DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(_formatDecimal(3, _list[i]['rramt']), style: cellStyle)))),
                    DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child:
                                Text(_formatDecimal(3, _list[i]['costamt']), style: cellStyle)))),
                    DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child:
                                Text(_formatDecimal(3, _list[i]['grossamt']), style: cellStyle)))),
                    DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text('${_formatDecimal(3, _list[i]['grossrate'])}%',
                                style: cellStyle)))),
                  ]),
          ],
        ),
      ),
      if (sum.isNotEmpty) _buildSummaryRow(sum),
    ]);
  }

  Widget _buildSummaryRow(Map<String, dynamic> sum) {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const borderSide = BorderSide(color: Color(0xFFE1E9F3));
    const minW = 650.0, colW = 650.0 / 5;

    return Container(
      height: 44,
      decoration: const BoxDecoration(
          color: Color(0xFFF0F4FF), border: Border(top: borderSide, bottom: borderSide)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        controller: _summaryHScrollController,
        child: SizedBox(
            width: minW,
            child: Row(children: [
              SizedBox(
                  width: colW,
                  child: Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(border: Border(right: borderSide)),
                      child: const Text('合计', style: boldStyle))),
              SizedBox(
                  width: colW,
                  child: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(border: Border(right: borderSide)),
                      child: Text(_formatDecimal(3, sum['rramt']), style: boldStyle))),
              SizedBox(
                  width: colW,
                  child: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(border: Border(right: borderSide)),
                      child: Text(_formatDecimal(3, sum['costamt']), style: boldStyle))),
              SizedBox(
                  width: colW,
                  child: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(border: Border(right: borderSide)),
                      child: Text(_formatDecimal(3, sum['grossamt']), style: boldStyle))),
              SizedBox(
                  width: colW,
                  child: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(border: Border(right: borderSide)),
                      child: Text('${_formatDecimal(3, sum['grossrate'])}%', style: boldStyle))),
            ])),
      ),
    );
  }
}
