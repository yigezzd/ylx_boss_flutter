import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 采购分析
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\businessAnalysis\subpage\cgfx.vue
class CgfxPage extends StatefulWidget {
  const CgfxPage({super.key});
  @override
  State<CgfxPage> createState() => _CgfxPageState();
}

class _CgfxPageState extends State<CgfxPage> {
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';
  bool _isZd = false;

  String _supName = '全部供应商';
  String _supId = '';

  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  bool _loading = true;
  bool _loadingMore = false;
  List<Map<String, dynamic>> _list = [];
  Map<String, dynamic> _sumData = {};

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时闪屏）
  bool _hasLoadedOnce = false;

  int _page = 1;
  bool _hasMore = true;

  String _sortField = '';
  String _sortType = 'desc';

  final ScrollController _hScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = now;
    _startDate = now; // 默认当天
    _activeQuickTimeId = 1; // 默认今日
    _loadStore();
  }

  @override
  void dispose() {
    _hScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    try {
      final s = SpUtil.getString(Constant.store) ?? '';
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

  Future<void> _selectSupplier() async {
    final result = await SelectSupplierPage.show(context, initialSelectedId: _supId);
    if (result != null && mounted) {
      setState(() {
        _supId = result['supid']?.toString() ?? '';
        _supName = result['supname']?.toString() ?? '全部供应商';
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

  static String _fmtNum(int digits, dynamic v) {
    final num n = v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
    return n.toStringAsFixed(digits);
  }

  void _onSort(String field, String type) {
    setState(() {
      _sortField = field;
      _sortType = type;
    });
    _loadData();
  }

  Future<void> _loadData() async {
    if (!_hasLoadedOnce) {
      setState(() {
        _loading = true;
        _list = [];
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _loading = true);
      _page = 1;
      _hasMore = true;
    }
    try {
      final r = await request(HttpApi.bossJyfxGetCgfx, {
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': _sids,
        'sidsname': _storeName,
        'supid': _supId,
        'supname': _supName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'selectdatetype': _selectdatetype,
        'field': _sortField,
        'type': _sortType,
      });
      if (!mounted) return;
      final data = r['data'];
      if (data is Map<String, dynamic>) {
        final newList = (data['list'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _list = newList;
          _sumData = (data['sumdata'] is Map<String, dynamic>)
              ? data['sumdata'] as Map<String, dynamic>
              : {};
          _hasMore = newList.length >= 20;
          if (_hasMore) _page = 2;
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

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final r = await request(HttpApi.bossJyfxGetCgfx, {
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': _sids,
        'sidsname': _storeName,
        'supid': _supId,
        'supname': _supName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'selectdatetype': _selectdatetype,
        'field': _sortField,
        'type': _sortType,
      });
      if (!mounted) return;
      final data = r['data'];
      if (data is Map<String, dynamic>) {
        final newList = (data['list'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _list.addAll(newList);
          _hasMore = newList.length >= 20;
          if (_hasMore) _page++;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

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
              final sel = activeId == i;
              return Expanded(
                  child: GestureDetector(
                onTap: () => _onQuickTimeSelect(i),
                child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: sel ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 13, color: sel ? Colors.white : const Color(0xFF333333)))),
              ));
            }))),
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
          Expanded(child: _buildDatePart(_endDate, isEnd: true))
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
    final label =
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
        title: const Text('采购分析', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Column(children: [
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Expanded(
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
                                    style:
                                        const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
                            if (_isZd)
                              const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                          ])))),
              const SizedBox(width: 8),
              Expanded(
                  child: GestureDetector(
                      onTap: _selectSupplier,
                      child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFDEDEDE)),
                              borderRadius: BorderRadius.circular(5)),
                          child: Row(children: [
                            Expanded(
                                child: Text(_supName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                          ])))),
            ])),
        _buildTimeSelector(),
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              Expanded(child: _buildMetricCard('采购总数', _fmtNum(1, _sumData['cgqty']))),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard('采购金额', _fmtNum(3, _sumData['cgamt']))),
            ])),
        if (_loading && _list.isEmpty && !_hasLoadedOnce)
          const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF006EFF))))
        else if (_list.isEmpty)
          Expanded(
              child: Stack(children: [
            const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
              SizedBox(height: 12),
              Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
            ])),
            if (_loading)
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
                          child:
                              CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]))
        else
          Expanded(
            child: Stack(children: [
              _buildTable(),
              if (_loading)
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
                            child:
                                CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _buildMetricCard(String label, String value) {
    return Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFDEDEDE))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ]));
  }

  // ==================== 表格 ====================
  DataColumn2 _buildSortCol(String name, String label, TextStyle hs, {bool compact = false}) {
    final isActive = _sortField == name;
    final isAsc = _sortType == 'asc';
    final w = GestureDetector(
      onTap: () {
        final newType = isActive ? (isAsc ? 'desc' : 'asc') : 'desc';
        _onSort(name, newType);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(label, textAlign: TextAlign.right, style: hs)),
          if (isActive)
            Icon(isAsc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14, color: const Color(0xFF006EFF))
          else
            const Icon(Icons.unfold_more, size: 14, color: Color(0xFF9CA3AF)),
        ]),
      ),
    );
    if (compact) {
      return DataColumn2(numeric: true, size: ColumnSize.S, label: w);
    }
    return DataColumn2(numeric: true, label: w);
  }

  Widget _buildTable() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    final sw = MediaQuery.of(context).size.width;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('采购明细',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333)))),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification &&
                n.metrics.axis == Axis.vertical &&
                n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
                _hasMore &&
                !_loadingMore) {
              _loadMore();
            }
            return false;
          },
          child: DataTable2(
            horizontalScrollController: _hScrollController,
            fixedLeftColumns: 2,
            minWidth: sw,
            horizontalMargin: 0,
            columnSpacing: 0,
            dataRowHeight: 40,
            headingRowHeight: 44,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
            border: const TableBorder(
                horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
                verticalInside: BorderSide(color: Color(0xFFE1E9F3))),
            columns: [
              const DataColumn2(
                  fixedWidth: 40,
                  label: Padding(
                      padding: EdgeInsets.only(left: 5), child: Text('序号', style: headerStyle))),
              const DataColumn2(
                  fixedWidth: 130,
                  label: Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Text('商品名称/条码', style: headerStyle))),
              _buildSortCol('cgqty', '采购数量', headerStyle),
              _buildSortCol('cgprice', '进价', headerStyle, compact: true),
              _buildSortCol('cgamt', '采购金额', headerStyle),
            ],
            rows: [
              for (var i = 0; i < _list.length; i++)
                DataRow2(
                    decoration:
                        BoxDecoration(color: i.isOdd ? const Color(0xFFF9F9F9) : Colors.white),
                    cells: _buildCells(i, cellStyle)),
              if (_loadingMore)
                const DataRow2(cells: [
                  DataCell(SizedBox(
                      height: 40,
                      child: Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF006EFF)))))),
                  DataCell.empty,
                  DataCell.empty,
                  DataCell.empty,
                  DataCell.empty,
                ]),
            ],
          ),
        ),
      ),
    ]);
  }

  List<DataCell> _buildCells(int i, TextStyle cs) {
    final row = _list[i];
    final name = row['name']?.toString() ?? '';
    final barcode = row['barcode']?.toString() ?? '';
    return [
      DataCell(
          Padding(padding: const EdgeInsets.only(left: 5), child: Text('${i + 1}', style: cs))),
      DataCell(Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: cs, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (barcode.isNotEmpty)
                  Text(barcode,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ]))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(1, row['cgqty']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(2, row['cgprice']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(3, row['cgamt']), style: cs)))),
    ];
  }
}
