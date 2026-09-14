import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/data/businessReport/exceptionMonitoring/exception_monitoring_detail_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 异常监控页面
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\exceptionMonitoring\exceptionMonitoring.vue
class ExceptionMonitoringPage extends StatefulWidget {
  const ExceptionMonitoringPage({super.key});

  @override
  State<ExceptionMonitoringPage> createState() => _ExceptionMonitoringPageState();
}

class _ExceptionMonitoringPageState extends State<ExceptionMonitoringPage> {
  // ── 列表状态 ──
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时表格闪屏）
  bool _hasLoadedOnce = false;

  // ── 门店 ──
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';

  // ── 日期 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  // ── 汇总 ──
  int _totalCount = 0;
  double _totalAmount = 0;

  // ── 操作类型 ──
  String _opertype = '';
  String _opertypeName = '';

  static const _opertypeOptions = [
    {'label': '全部操作类型', 'value': ''},
    {'label': '单品改价', 'value': '1'},
    {'label': '单品删除', 'value': '2'},
    {'label': '商品退货', 'value': '3'},
    {'label': '整单折扣', 'value': '4'},
    {'label': '整单删除', 'value': '5'},
    {'label': '商品赠送', 'value': '6'},
    {'label': '挂单', 'value': '7'},
    {'label': '删除挂单', 'value': '8'},
  ];

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
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        final storeId = storeMap['id']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _storeName = storeMap['name']?.toString() ?? '';
            _activeStoreId = storeId;
            _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
          });
          _loadData();
        }
      }
    } catch (_) {}
  }

  // ── 门店选择 ──
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _activeStoreId,
    );
    if (result != null && mounted) {
      setState(() {
        final storeId = result['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
        _storeName = result['storename']?.toString() ?? '';
        _page = 1;
        if (!_hasLoadedOnce) _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

  // ── 操作类型选择 ──
  void _showOpertypePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 50,
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    const Expanded(
                      child: Text('选择操作类型',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                    ),
                    SizedBox(
                      width: 48,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Flexible(
                child: ListView.builder(
                  cacheExtent: 800,
                  shrinkWrap: true,
                  itemCount: _opertypeOptions.length,
                  itemBuilder: (_, i) {
                    final opt = _opertypeOptions[i];
                    final name = opt['label']!;
                    final val = opt['value']!;
                    final selected = _opertype == val;
                    return RepaintBoundary(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _opertype = val;
                            _opertypeName = name;
                            _page = 1;
                            if (!_hasLoadedOnce) _list = [];
                            _hasMore = true;
                          });
                          Navigator.pop(ctx);
                          _loadData();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                            border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(name,
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: selected
                                            ? const Color(0xFF006EFF)
                                            : const Color(0xFF333333),
                                        fontWeight:
                                            selected ? FontWeight.w600 : FontWeight.normal)),
                              ),
                              _buildRadio(selected),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRadio(bool isSelected) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
          width: 2,
        ),
        color: isSelected ? const Color(0xFF006EFF) : Colors.white,
      ),
      child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
    );
  }

  // ==================== 数据加载 ====================

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtAmt(dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(2);
  }

  Future<void> _loadData() {
    if (_loading) {
      return Future.value();
    }
    setState(() => _loading = true);

    final params = <String, dynamic>{
      'field': 'billdate',
      'type': 'desc',
      'is_page': 1,
      'page': _page,
      'pagesize': 20,
      'sids': _sids,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      if (_opertype.isNotEmpty) 'opertype': _opertype,
    };

    return request(HttpApi.saleCashMonitorGetCashMonitor, params).then((result) {
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?) ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= 20;
        _hasLoadedOnce = true;
        _totalCount = int.tryParse(map['total']?.toString() ?? '') ?? 0;
        final sumdata = map['sumdata'];
        _totalAmount =
            double.tryParse((sumdata is Map ? sumdata['amt']?.toString() : '') ?? '') ?? 0;
      });
    }).catchError((_) {
      setState(() => _hasMore = false);
    }).whenComplete(() {
      setState(() => _loading = false);
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  // ==================== 时间选择器（对齐 cash_flow_page） ====================

  Widget _buildTimeSelector() {
    final labels = ['昨天', '今日', '本周', '本月', '自定义'];
    final activeId = _activeQuickTimeId ?? 1;
    final theme = Theme.of(context);
    const primary = Color(0xFF006EFF);
    const onSurface = Color(0xFF333333);
    const borderColor = Color(0xFFD1D5DB);

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        children: [
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
                          style:
                              TextStyle(fontSize: 13, color: selected ? Colors.white : onSurface)),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          _buildDateNavigation(),
        ],
      ),
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
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _activeQuickTimeId = id;
      _page = 1;
      if (!_hasLoadedOnce) _list = [];
      _hasMore = true;
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
                borderRadius: BorderRadius.circular(5)),
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
            _page = 1;
            if (!_hasLoadedOnce) _list = [];
            _hasMore = true;
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
          _page = 1;
          if (!_hasLoadedOnce) _list = [];
          _hasMore = true;
        });
        _loadData();
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        margin: EdgeInsets.only(left: isStart ? 0 : 4, right: isEnd ? 0 : 4),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(5)),
        child: Text(label,
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
      ),
    );
  }

  Widget _buildDateToSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('至',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface)),
    );
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
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _page = 1;
      if (!_hasLoadedOnce) _list = [];
      _hasMore = true;
    });
    _loadData();
  }

  // ==================== 汇总栏 ====================

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

  Widget _buildSummaryBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
          children: [
            const TextSpan(text: '异常总笔数：'),
            TextSpan(
                text: '$_totalCount',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333))),
            const TextSpan(text: '   异常总金额：'),
            TextSpan(
                text: _totalAmount.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          ],
        ),
      ),
    );
  }

  // ==================== 表格 ====================

  Widget _buildTableArea() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));

    if (_list.isEmpty && !_loading) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification &&
                  notification.metrics.axis == Axis.vertical &&
                  notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100 &&
                  !_loading &&
                  _hasMore) {
                _page++;
                _loadData();
              }
              return false;
            },
            child: RefreshIndicator(
              color: const Color(0xFF006EFF),
              onRefresh: _onRefresh,
              child: DataTable2(
                minWidth: 600,
                fixedLeftColumns: 1,
                horizontalMargin: 0,
                columnSpacing: 0,
                dataRowHeight: 56,
                headingRowHeight: 44,
                headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
                border: const TableBorder(
                  horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
                  verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
                ),
                columns: const [
                  DataColumn2(
                    fixedWidth: 150,
                    label: Padding(
                      padding: EdgeInsets.only(left: 5, right: 12),
                      child: Text('单号', style: headerStyle),
                    ),
                  ),
                  DataColumn2(
                      size: ColumnSize.L,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('操作类型', style: headerStyle),
                      )),
                  DataColumn2(
                    size: ColumnSize.L,
                    numeric: true,
                    label: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('操作金额', textAlign: TextAlign.right, style: headerStyle),
                    ),
                  ),
                  DataColumn2(
                      size: ColumnSize.L,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('操作员', style: headerStyle),
                      )),
                  DataColumn2(
                      size: ColumnSize.L,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('门店', style: headerStyle),
                      )),
                ],
                rows: [
                  for (var i = 0; i < _list.length; i++) _buildRow(_list[i], i),
                  // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
                  if (_loading && (_page > 1 || !_hasLoadedOnce))
                    const DataRow(cells: [
                      DataCell(SizedBox(
                        height: 44,
                        child: Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF006EFF))),
                        ),
                      )),
                      DataCell.empty,
                      DataCell.empty,
                      DataCell.empty,
                      DataCell.empty,
                    ]),
                ],
              ),
            ),
          ),
        ),
        _buildNoMoreFooter(),
      ],
    );
  }

  /// 表格底部 — 没有更多了
  Widget _buildNoMoreFooter() {
    if (_loading || _hasMore || _list.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 44,
      color: Colors.white,
      alignment: Alignment.center,
      child: const Text('没有更多了', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
    );
  }

  DataRow2 _buildRow(Map<String, dynamic> row, int index) {
    final billno = (row['billno'] ?? '-').toString();
    final billdate = (row['billdate'] ?? '-').toString();
    final opertypename = (row['opertypename'] ?? '-').toString();
    final amt = _fmtAmt(row['amt']);
    final cashname = (row['cashname'] ?? '-').toString();
    final storename = (row['storename'] ?? '-').toString();

    const smallGrey = TextStyle(fontSize: 11, color: Color(0xFF999999));
    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    const fixedStyle = TextStyle(fontSize: 13, color: Color(0xFF006EFF));
    const amountStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF333333));
    const cellPad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final isOdd = index.isOdd;

    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        DataCell(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<ExceptionMonitoringDetailPage>(
                  builder: (_) => ExceptionMonitoringDetailPage(row: row),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(billno, maxLines: 1, overflow: TextOverflow.ellipsis, style: fixedStyle),
                  const SizedBox(height: 4),
                  Text(billdate, maxLines: 1, overflow: TextOverflow.ellipsis, style: smallGrey),
                ],
              ),
            ),
          ),
        ),
        DataCell(Padding(padding: cellPad, child: Text(opertypename, style: cellStyle))),
        DataCell(Padding(
          padding: cellPad,
          child: Align(alignment: Alignment.centerRight, child: Text(amt, style: amountStyle)),
        )),
        DataCell(Padding(
            padding: cellPad, child: SizedBox(width: 96, child: Text(cashname, style: cellStyle)))),
        DataCell(Padding(
            padding: cellPad,
            child: SizedBox(width: 96, child: Text(storename, style: cellStyle)))),
      ],
    );
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('异常监控',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                children: [
                  // 门店选择
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStore,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Text(_storeName.isNotEmpty ? _storeName : '全部机构',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 操作类型选择
                  Expanded(
                    child: GestureDetector(
                      onTap: _showOpertypePicker,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Text(_opertypeName.isNotEmpty ? _opertypeName : '全部操作类型',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildTimeSelector(),
          if (_list.isEmpty && !_loading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                    SizedBox(height: 12),
                    Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
            )
          else if (_list.isEmpty && _hasLoadedOnce)
            // 已加载过、无数据且刷新中：保留空态 + 居中图标卡片，避免表格骨架闪屏
            const Expanded(
              child: Stack(children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                      SizedBox(height: 12),
                      Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
                _loadingCard,
              ]),
            )
          else ...[
            _buildSummaryBar(),
            Expanded(
              child: Stack(children: [
                _buildTableArea(),
                if (_loading && _hasLoadedOnce && _page == 1) _loadingCard,
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
