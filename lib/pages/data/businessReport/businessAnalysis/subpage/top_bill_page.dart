import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

import 'sp_bill_page.dart';

/// 类别/品牌/供应商详情页
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\businessAnalysis\subpage\spfx\spfxBubpage\topBill.vue
class TopBillPage extends StatefulWidget {
  const TopBillPage({
    super.key,
    required this.module,
    required this.item,
    required this.sids,
    required this.startTime,
    required this.endTime,
    required this.field,
    this.timeIndex = 1,
  });
  final String module; // flfx / ppfx / gysfx
  final Map<String, dynamic> item;
  final List<int> sids;
  final String startTime;
  final String endTime;
  final String field;
  final int timeIndex;

  @override
  State<TopBillPage> createState() => _TopBillPageState();
}

class _TopBillPageState extends State<TopBillPage> {
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

  String _rankField = 'qty';
  String _rankStr = '按销量排行';

  final ScrollController _hScrollController = ScrollController();
  final ScrollController _summaryHScrollController = ScrollController();

  String get _title {
    switch (widget.module) {
      case 'flfx':
        return '分类详情';
      case 'ppfx':
        return '品牌详情';
      default:
        return '供应商详情';
    }
  }

  String get _titleCom {
    switch (widget.module) {
      case 'flfx':
        return '${widget.item['typename'] ?? ''}-商品排行';
      case 'ppfx':
        return '${widget.item['brandname'] ?? ''}-商品排行';
      default:
        return '${widget.item['supname'] ?? ''}-商品排行';
    }
  }

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.tryParse(widget.startTime) ?? DateTime.now();
    _endDate = DateTime.tryParse(widget.endTime) ?? DateTime.now();
    _activeQuickTimeId = widget.timeIndex;
    _rankField = widget.field;
    switch (widget.field) {
      case 'rramt':
        _rankStr = '按金额排行';
        break;
      case 'grossamt':
        _rankStr = '按毛利排行';
        break;
      default:
        _rankStr = '按销量排行';
        break;
    }
    _hScrollController.addListener(_syncHScroll);
    _loadData();
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

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmt(int digits, dynamic v) {
    final n = v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
    return n.toStringAsFixed(digits);
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
      final params = <String, dynamic>{
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': widget.sids,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'field': _rankField,
        'type': 'desc',
      };
      switch (widget.module) {
        case 'flfx':
          params['typeid'] = widget.item['typeid']?.toString();
          break;
        case 'ppfx':
          params['brandname'] = widget.item['brandname']?.toString();
          break;
        default:
          params['supid'] = widget.item['supid']?.toString();
      }
      final r = await request(HttpApi.bossJyfxGetSpfx, params);
      if (!mounted) return;
      final data = r['data'];
      if (data is Map<String, dynamic>) {
        final newList = (data['list'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _list = newList;
          _sumData = (data['sumdata'] is Map<String, dynamic>)
              ? data['sumdata'] as Map<String, dynamic>
              : {};
          _sumData['total'] = data['total'] ?? 0;
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
      final params = <String, dynamic>{
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': widget.sids,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'field': _rankField,
        'type': 'desc',
      };
      switch (widget.module) {
        case 'flfx':
          params['typeid'] = widget.item['typeid']?.toString();
          break;
        case 'ppfx':
          params['brandname'] = widget.item['brandname']?.toString();
          break;
        default:
          params['supid'] = widget.item['supid']?.toString();
      }
      final r = await request(HttpApi.bossJyfxGetSpfx, params);
      if (!mounted) return;
      final data = r['data'];
      if (data is Map<String, dynamic>) {
        _list.addAll((data['list'] as List?)?.cast<Map<String, dynamic>>() ?? []);
        setState(() {
          _hasMore = _list.length % 20 == 0;
          if (_hasMore) _page++;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _showRankPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height / 3,
        decoration: const BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: SafeArea(
            child: Column(children: [
          SizedBox(
              height: 50,
              child: Row(children: [
                const SizedBox(width: 48),
                const Expanded(
                    child: Text('选择排行',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
                SizedBox(
                    width: 48,
                    child: Center(
                        child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280))))),
              ])),
          const Divider(height: 1),
          _buildRankOpt(ctx, 'qty', '按销量排行'),
          _buildRankOpt(ctx, 'rramt', '按金额排行'),
          _buildRankOpt(ctx, 'grossamt', '按毛利排行'),
        ])),
      ),
    );
  }

  Widget _buildRankOpt(BuildContext ctx, String val, String label) {
    final sel = _rankField == val;
    return ListTile(
      title: Text(label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: sel ? const Color(0xFF006EFF) : const Color(0xFF333333))),
      trailing: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: sel ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB), width: 2)),
          child: sel
              ? Center(
                  child: Container(
                      width: 10,
                      height: 10,
                      decoration:
                          const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF006EFF))))
              : null),
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          _rankField = val;
          _rankStr = label;
        });
        _loadData();
      },
    );
  }

  // ==================== 时间选择器 ====================
  Widget _buildTimeSelector() {
    final labels = ['昨天', '今日', '本周', '本月', '自定义'];
    final activeId = _activeQuickTimeId ?? 1;
    const borderColor = Color(0xFFD1D5DB);
    const primary = Color(0xFF006EFF);
    return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
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
        ]));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
            title: Text(_title, style: const TextStyle(fontSize: 17)),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF333333),
            elevation: 0.5),
        body: Column(children: [
          _buildTimeSelector(),
          // 指标卡片
          Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(children: [
                Row(children: [
                  Expanded(child: _buildMetricCard('商品总数', _fmt(1, _sumData['total']))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('累计数量', _fmt(1, _sumData['qty']))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('累计金额', _fmt(3, _sumData['rramt'])))
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _buildMetricCard('毛利额', _fmt(3, _sumData['grossamt']))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('毛利率', '${_fmt(3, _sumData['grossrate'])}%')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('均价', _fmt(3, _sumData['avgprice'])))
                ]),
              ])),
          // 标题行 + 排行选择
          Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(
                    child: Text(_titleCom,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333)))),
                GestureDetector(
                    onTap: _showRankPicker,
                    child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFDEDEDE)),
                            borderRadius: BorderRadius.circular(5)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_rankStr,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF333333))),
                          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                        ]))),
              ])),
          // 表格
          if (_loading && _list.isEmpty && !_hasLoadedOnce)
            const Expanded(
                child: Center(child: CircularProgressIndicator(color: Color(0xFF006EFF))))
          else if (_list.isEmpty)
            Expanded(
                child: Stack(children: [
              const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                SizedBox(height: 12),
                Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)))
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
                              child: CircularProgressIndicator(
                                  strokeWidth: 3, color: Color(0xFF006EFF)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
        ]));
  }

  Widget _buildMetricCard(String label, String value) {
    return Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFDEDEDE)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))
            ]),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A))),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ]));
  }

  Widget _buildTable() {
    const hs = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const cs = TextStyle(fontSize: 13, color: Color(0xFF333333));

    return Column(children: [
      Expanded(
          child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollEndNotification &&
              n.metrics.axis == Axis.vertical &&
              n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
              _hasMore &&
              !_loadingMore) _loadMore();
          return false;
        },
        child: DataTable2(
          horizontalScrollController: _hScrollController,
          showCheckboxColumn: false,
          fixedLeftColumns: 2,
          minWidth: 700,
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
                fixedWidth: 45,
                label: Padding(padding: EdgeInsets.only(left: 12), child: Text('排行', style: hs))),
            DataColumn2(
                fixedWidth: 130,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('商品名称/条码', style: hs))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12), child: Text('销量', style: hs))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12), child: Text('金额', style: hs))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12), child: Text('毛利额', style: hs))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12), child: Text('毛利率', style: hs))),
            DataColumn2(
                numeric: true,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12), child: Text('均价', style: hs))),
          ],
          rows: [
            for (var i = 0; i < _list.length; i++)
              DataRow2(
                decoration: BoxDecoration(
                    color: i.isOdd ? const Color(0xFFF9F9F9) : Colors.white,
                    border: const Border(right: BorderSide(color: Color(0xFFE1E9F3)))),
                cells: _buildCells(i, cs),
                onSelectChanged: (_) => _onRowTap(i),
              ),
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
                DataCell.empty,
                DataCell.empty,
              ]),
          ],
        ),
      )),
      if (_sumData.isNotEmpty) _buildSummaryRow(),
    ]);
  }

  List<DataCell> _buildCells(int i, TextStyle cs) {
    final row = _list[i];
    final name = row['name']?.toString() ?? '';
    final barcode = row['barcode']?.toString() ?? '';
    return [
      DataCell(
          Padding(padding: const EdgeInsets.only(left: 12), child: Text('${i + 1}', style: cs))),
      DataCell(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
              child: Text(_fmt(1, row['qty']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmt(3, row['rramt']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmt(3, row['grossamt']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('${_fmt(3, row['grossrate'])}%', style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmt(3, row['avgprice']), style: cs)))),
    ];
  }

  void _onRowTap(int i) {
    final row = _list[i];
    Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: '/businessAnalysis/spfx/sp_bill'),
        builder: (_) => SpBillPage(
              productData: row,
              sids: widget.sids,
              startTime: _fmtDate(_startDate),
              endTime: _fmtDate(_endDate),
              timeIndex: _activeQuickTimeId ?? 1,
            )));
  }

  Widget _buildSummaryRow() {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const borderSide = BorderSide(color: Color(0xFFE1E9F3));
    final sum = _sumData;
    const fixW1 = 45.0, fixW2 = 130.0;
    const colW = (700.0 - fixW1 - fixW2) / 5;

    return Container(
        height: 44,
        decoration: const BoxDecoration(
            color: Color(0xFFF0F4FF), border: Border(top: borderSide, bottom: borderSide)),
        child: Row(children: [
          SizedBox(
              width: fixW1,
              child: Container(decoration: const BoxDecoration(border: Border(right: borderSide)))),
          SizedBox(
              width: fixW2,
              child: Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(border: Border(right: borderSide)),
                  child: const Text('合计', style: boldStyle))),
          Expanded(
              child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            controller: _summaryHScrollController,
            child: SizedBox(
                width: 5 * colW,
                child: Row(children: [
                  SizedBox(
                      width: colW,
                      child: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 12),
                          decoration: const BoxDecoration(border: Border(right: borderSide)),
                          child: Text(_fmt(1, sum['qty']), style: boldStyle))),
                  SizedBox(
                      width: colW,
                      child: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 12),
                          decoration: const BoxDecoration(border: Border(right: borderSide)),
                          child: Text(_fmt(3, sum['rramt']), style: boldStyle))),
                  SizedBox(
                      width: colW,
                      child: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 12),
                          decoration: const BoxDecoration(border: Border(right: borderSide)),
                          child: Text(_fmt(3, sum['grossamt']), style: boldStyle))),
                  SizedBox(
                      width: colW,
                      child: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 12),
                          decoration: const BoxDecoration(border: Border(right: borderSide)),
                          child: Text('${_fmt(3, sum['grossrate'])}%', style: boldStyle))),
                  SizedBox(
                      width: colW,
                      child: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 12),
                          decoration: const BoxDecoration(border: Border(right: borderSide)),
                          child: Text(_fmt(3, sum['avgprice']), style: boldStyle))),
                ])),
          )),
        ]));
  }
}
