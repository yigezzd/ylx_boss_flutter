import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 会员分析
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\businessAnalysis\subpage\hyfx.vue
class HyfxPage extends StatefulWidget {
  const HyfxPage({super.key});
  @override
  State<HyfxPage> createState() => _HyfxPageState();
}

class _HyfxPageState extends State<HyfxPage> {
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';
  bool _isZd = false;

  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  bool _loading = true;
  bool _loadingMore = false;
  List<Map<String, dynamic>> _list = [];
  Map<String, dynamic> _sumData = {};

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时闪屏）
  bool _hasLoadedOnce = false;
  Map<String, dynamic> _totalData = {};
  Map<String, dynamic> _vipHeadData = {};

  bool _selectViptypeFlag = false;
  int _page = 1;
  bool _hasMore = true;

  final ScrollController _hScrollController = ScrollController();
  final ScrollController _summaryHScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = now.subtract(const Duration(days: 1));
    _startDate = _endDate; // 默认昨天
    _activeQuickTimeId = 0; // 默认昨天
    _hScrollController.addListener(_syncHScroll);
    _loadStore();
    _fetchHeadData();
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
          _fetchHeadData();
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
      _fetchHeadData();
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

  // ==================== VIP 等级抽屉 ====================
  Future<void> _fetchHeadData() async {
    try {
      final r = await request(HttpApi.bossJyfxGetHyfxHead, {
        'is_page': 0,
        'bsid': _sids.isNotEmpty ? _sids.first : 0,
      });
      if (!mounted) return;
      final data = r['data'];
      if (data is Map<String, dynamic>) {
        setState(() => _totalData = data);
      }
    } catch (_) {}
  }

  Future<void> _openVipLevel() async {
    final r = await request(HttpApi.bossJyfxGetHyfxHead, {
      'is_page': 0,
      'bsid': _sids.isNotEmpty ? _sids.first : 0,
    });
    if (!mounted) return;
    final data = r['data'];
    if (data is Map<String, dynamic>) {
      final types = (data['bossHyfxTypeLists'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      types.sort((a, b) {
        final pa = double.tryParse(a['vipprop']?.toString() ?? '0') ?? 0;
        final pb = double.tryParse(b['vipprop']?.toString() ?? '0') ?? 0;
        return pb.compareTo(pa);
      });
      setState(() {
        _totalData = data;
        _vipHeadData = data;
      });
      _showVipLevelSheet(types, data);
    }
  }

  void _showVipLevelSheet(List<Map<String, dynamic>> types, Map<String, dynamic> total) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) {
        final w = MediaQuery.of(context).size.width - 32;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('会员等级', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                    onTap: () => Navigator.pop(context), child: const Icon(Icons.close, size: 20)),
              ]),
              const SizedBox(height: 12),
              for (final t in types)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                            flex: 5,
                            child: Text(t['viptypename']?.toString() ?? '',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
                        SizedBox(
                            width: w * 0.25,
                            child: Text('¥ ${_fmtNum(3, t['vipcount'])}',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
                        SizedBox(
                            width: w * 0.25,
                            child: Text('${_fmtNum(3, t['vipprop'])}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF9B9B9B)))),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (double.tryParse(t['vipprop']?.toString() ?? '0') ?? 0) / 100,
                          minHeight: 10,
                          backgroundColor: const Color(0xFFE8E8E8),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF006EFF)),
                        ),
                      ),
                    ])),
            ]),
          ),
        );
      },
    );
  }

  // ==================== 数据加载 ====================
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
      final r = await request(HttpApi.bossJyfxGetHyfx, {
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': _sids,
        'sidsname': _storeName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'selectdatetype': _selectdatetype,
        'selectviptypeflag': _selectViptypeFlag ? 1 : 0,
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
      final r = await request(HttpApi.bossJyfxGetHyfx, {
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': _sids,
        'sidsname': _storeName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'selectdatetype': _selectdatetype,
        'selectviptypeflag': _selectViptypeFlag ? 1 : 0,
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
        title: const Text('会员分析', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Column(children: [
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
                      if (_isZd)
                        const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                    ])))),
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Expanded(
                  child: _buildTopCard('会员总数', _fmtNum(1, _totalData['vipcount']),
                      showInfo: true, onInfoTap: _openVipLevel)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildPopoverCard('会员储卡余额', _fmtNum(3, _totalData['nowmoney']),
                      detail:
                          '本金：${_fmtNum(3, _totalData['capitalmoney'])}\n赠金：${_fmtNum(3, _totalData['givemoney'])}')),
              const SizedBox(width: 8),
              Expanded(child: _buildTopCard('会员积分', _fmtNum(3, _totalData['nowpoint']))),
            ])),
        _buildTimeSelector(),
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Row(children: [
              Expanded(child: _buildMetricCard('新增会员', _fmtNum(3, _sumData['vipcardnum']))),
              const SizedBox(width: 4),
              Expanded(child: _buildMetricCard('开卡金额', _fmtNum(3, _sumData['vipcardsaleamt']))),
              const SizedBox(width: 4),
              Expanded(child: _buildMetricCard('充值金额', _fmtNum(3, _sumData['vipaddamt']))),
              const SizedBox(width: 4),
              Expanded(child: _buildMetricCard('储卡消费', _fmtNum(3, _sumData['vipasaleamt']))),
            ])),
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() => _selectViptypeFlag = !_selectViptypeFlag);
                  _loadData();
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_selectViptypeFlag ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18, color: const Color(0xFF006EFF)),
                  const SizedBox(width: 4),
                  const Text('分类统计', style: TextStyle(fontSize: 12, color: Color(0xFF333333))),
                ]),
              ),
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

  Widget _buildTopCard(String label, String value,
      {bool showInfo = false, VoidCallback? onInfoTap}) {
    return Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFDEDEDE))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                if (showInfo) ...[
                  const SizedBox(width: 2),
                  GestureDetector(
                      onTap: onInfoTap,
                      child: Icon(Icons.info_outline, size: 12, color: Colors.grey.shade400))
                ],
              ]),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ]));
  }

  Widget _buildPopoverCard(String label, String value, {required String detail}) {
    return GestureDetector(
      onTap: () {
        showDialog(
            context: context,
            builder: (_) => Dialog(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(detail,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF333333))))));
      },
      child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFDEDEDE))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                  const SizedBox(width: 2),
                  Icon(Icons.info_outline, size: 12, color: Colors.grey.shade400),
                ]),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          ])),
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
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A))),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ]));
  }

  // ==================== 表格（固定表头 + 可滚动内容 + 固定合计行）====================
  Widget _buildTable() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    final sum = _sumData;

    return Column(children: [
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
            minWidth: _selectViptypeFlag ? 700 : 650,
            horizontalMargin: 0,
            columnSpacing: 0,
            dataRowHeight: 40,
            headingRowHeight: 44,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
            border: const TableBorder(
                horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
                verticalInside: BorderSide(color: Color(0xFFE1E9F3))),
            columns: _buildD2Columns(headerStyle),
            rows: _buildD2Rows(cellStyle),
          ),
        ),
      ),
      if (sum.isNotEmpty) _buildSummaryRow(),
    ]);
  }

  List<DataColumn2> _buildD2Columns(TextStyle hs) {
    if (_selectViptypeFlag) {
      return [
        DataColumn2(
            label: Padding(
                padding: const EdgeInsets.only(left: 5, right: 12), child: Text('日期', style: hs))),
        DataColumn2(
            label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('会员分类', style: hs))),
        DataColumn2(
            numeric: true,
            label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('新增会员', style: hs))),
        DataColumn2(
            numeric: true,
            label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('充值金额', style: hs))),
        DataColumn2(
            numeric: true,
            label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('消费金额', style: hs))),
      ];
    }
    return [
      DataColumn2(
          label: Padding(
              padding: const EdgeInsets.only(left: 5, right: 12), child: Text('日期', style: hs))),
      DataColumn2(
          numeric: true,
          label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('新增会员', style: hs))),
      DataColumn2(
          numeric: true,
          label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('开卡金额', style: hs))),
      DataColumn2(
          numeric: true,
          label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('充值金额', style: hs))),
      DataColumn2(
          numeric: true,
          label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('消费金额', style: hs))),
    ];
  }

  List<DataRow2> _buildD2Rows(TextStyle cs) {
    final rows = <DataRow2>[];
    for (var i = 0; i < _list.length; i++) {
      final row = _list[i];
      rows.add(DataRow2(
        decoration: BoxDecoration(color: i.isOdd ? const Color(0xFFF9F9F9) : Colors.white),
        cells: _buildCells(row, cs),
      ));
    }
    if (_loadingMore) {
      rows.add(const DataRow2(cells: [
        DataCell(SizedBox(
            height: 40,
            child: Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))))),
        DataCell.empty,
        DataCell.empty,
        DataCell.empty,
        DataCell.empty,
      ]));
    }
    return rows;
  }

  List<DataCell> _buildCells(Map<String, dynamic> row, TextStyle cs) {
    if (_selectViptypeFlag) {
      return [
        DataCell(Padding(
            padding: const EdgeInsets.only(left: 5, right: 12),
            child: Text(row['billdate']?.toString() ?? '', style: cs))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(row['viptypename']?.toString() ?? '', style: cs))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(_fmtNum(1, row['vipcardnum']), style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(_fmtNum(3, row['vipaddamt']), style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(_fmtNum(3, row['vipasaleamt']), style: cs)))),
      ];
    }
    return [
      DataCell(Padding(
          padding: const EdgeInsets.only(left: 5, right: 12),
          child: Text(row['billdate']?.toString() ?? '', style: cs))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(1, row['vipcardnum']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(3, row['vipcardsaleamt']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(3, row['vipaddamt']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(3, row['vipasaleamt']), style: cs)))),
    ];
  }

  // ==================== 固定的底部合计行 ====================
  Widget _buildSummaryRow() {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const borderSide = BorderSide(color: Color(0xFFE1E9F3));
    final sum = _sumData;
    final minW = _selectViptypeFlag ? 700.0 : 650.0;
    const colCount = 5;
    final colW = minW / colCount;

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        border: Border(top: borderSide, bottom: borderSide),
      ),
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
            if (_selectViptypeFlag)
              SizedBox(
                  width: colW,
                  child: Container(
                      decoration: const BoxDecoration(border: Border(right: borderSide)))),
            SizedBox(
                width: colW,
                child: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 12),
                    decoration: const BoxDecoration(border: Border(right: borderSide)),
                    child: Text(_fmtNum(1, sum['vipcardnum']), style: boldStyle))),
            if (!_selectViptypeFlag)
              SizedBox(
                  width: colW,
                  child: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(border: Border(right: borderSide)),
                      child: Text(_fmtNum(3, sum['vipcardsaleamt']), style: boldStyle))),
            SizedBox(
                width: colW,
                child: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 12),
                    decoration: const BoxDecoration(border: Border(right: borderSide)),
                    child: Text(_fmtNum(3, sum['vipaddamt']), style: boldStyle))),
            SizedBox(
                width: colW,
                child: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 12),
                    decoration: const BoxDecoration(border: Border(right: borderSide)),
                    child: Text(_fmtNum(3, sum['vipasaleamt']), style: boldStyle))),
          ]),
        ),
      ),
    );
  }
}
