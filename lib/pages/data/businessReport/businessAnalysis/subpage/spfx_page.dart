import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

import 'sp_bill_page.dart';
import 'top_bill_page.dart';

/// 商品分析
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\businessAnalysis\subpage\spfx\index.vue
class SpfxPage extends StatefulWidget {
  const SpfxPage({super.key});
  @override
  State<SpfxPage> createState() => _SpfxPageState();
}

class _SpfxPageState extends State<SpfxPage> with SingleTickerProviderStateMixin {
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';
  bool _isZd = false;

  String _sortField = 'qty';
  String _sortType = 'desc';

  String get _rankField => _sortField;
  String get _rankStr {
    const labels = {
      'qty': '按销量',
      'rramt': '按金额',
      'grossamt': '按毛利额',
      'grossrate': '按毛利率',
      'avgprice': '按均价',
    };
    final base = labels[_sortField] ?? '按销量';
    final arrow = _sortType == 'asc' ? '↑' : '↓';
    return '$base排行$arrow';
  }

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
  int _tabIndex = 0;
  String _level = '';

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchText = '';

  late TabController _tabController;
  final ScrollController _hScrollController = ScrollController();
  final ScrollController _summaryHScrollController = ScrollController();

  String get _api {
    switch (_tabIndex) {
      case 0:
        return HttpApi.bossJyfxGetSpfx;
      case 1:
        return HttpApi.bossJyfxGetFlfx;
      case 2:
        return HttpApi.bossJyfxGetPpfx;
      default:
        return HttpApi.bossJyfxGetHsfx;
    }
  }

  String get _nameField {
    switch (_tabIndex) {
      case 0:
        return '商品名称/条码';
      case 1:
        return '分类';
      case 2:
        return '品牌';
      default:
        return '供货商';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
        _loadData();
      }
    });
    _hScrollController.addListener(_syncHScroll);
    final now = DateTime.now();
    _endDate = now;
    _startDate = now; // 默认当天
    _activeQuickTimeId = 1; // 默认今日
    _loadStore();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hScrollController.removeListener(_syncHScroll);
    _hScrollController.dispose();
    _summaryHScrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
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
        }
      }
    } catch (_) {}
  }

  Future<void> _selectStore() async {
    if (!_isZd) return;
    final r = await SelectStorePage.show(context, showAll: true, initialSelectedId: _activeStoreId);
    if (r != null && mounted) {
      setState(() {
        _storeName = r['storename']?.toString() ?? '';
        final storeId = r['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
      });
      _loadData();
    }
  }

  void _showRankPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height / 2.2,
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
          _buildRankOpt(ctx, 'grossamt', '按毛利额排行'),
          _buildRankOpt(ctx, 'grossrate', '按毛利率排行'),
          _buildRankOpt(ctx, 'avgprice', '按均价排行'),
        ])),
      ),
    );
  }

  Widget _buildRankOpt(BuildContext ctx, String val, String label) {
    final sel = _sortField == val;
    return ListTile(
      title: Text(label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: sel ? const Color(0xFF006EFF) : const Color(0xFF333333))),
      trailing: _buildRadio(sel),
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          _sortField = val;
          _sortType = 'desc';
        });
        _loadData();
      },
    );
  }

  Widget _buildRadio(bool s) {
    return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: s ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB), width: 2)),
        child: s
            ? Center(
                child: Container(
                    width: 10,
                    height: 10,
                    decoration:
                        const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF006EFF))))
            : null);
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
    // 首次加载才清空列表；已加载过（含空数据）的后续刷新保留当前内容避免闪屏
    if (!_hasLoadedOnce) {
      setState(() {
        _loading = true;
        _list = [];
      });
    } else {
      setState(() => _loading = true);
    }
    _page = 1;
    _hasMore = true;
    try {
      final params = <String, dynamic>{
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': _sids,
        'sidsname': _storeName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'field': _sortField,
        'type': _sortType,
        'barcode': _searchText,
      };
      if (_tabIndex == 1) params['level'] = _level;
      final r = await request(_api, params);
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
          _loading = false;
          _hasLoadedOnce = true;
        });
      }
    } catch (_) {
      if (mounted) {
        // 刷新失败时保留旧数据，不清空
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
        'sids': _sids,
        'sidsname': _storeName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'field': _sortField,
        'type': _sortType,
        'barcode': _searchText,
      };
      if (_tabIndex == 1) params['level'] = _level;
      final r = await request(_api, params);
      if (!mounted) return;
      final data = r['data'];
      if (data is Map<String, dynamic>) {
        _list.addAll((data['list'] as List?)?.cast<Map<String, dynamic>>() ?? []);
        setState(() {
          _hasMore = (_list.length % 20 == 0);
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

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
            title: const Text('商品分析', style: TextStyle(fontSize: 17)),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF333333),
            elevation: 0.5),
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
                                const Icon(Icons.arrow_drop_down,
                                    size: 18, color: Color(0xFF666666)),
                            ])))),
                const SizedBox(width: 8),
                Expanded(
                    child: GestureDetector(
                        onTap: _showRankPicker,
                        child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFDEDEDE)),
                                borderRadius: BorderRadius.circular(5)),
                            child: Row(children: [
                              Expanded(
                                  child: Text(_rankStr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                            ])))),
              ])),
          _buildTimeSelector(),
          ColoredBox(
              color: Colors.white,
              child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: const Color(0xFF006EFF),
                  unselectedLabelColor: const Color(0xFF333333),
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  indicatorColor: const Color(0xFF006EFF),
                  tabs: const [
                    Tab(text: '商品分析'),
                    Tab(text: '类别分析'),
                    Tab(text: '品牌分析'),
                    Tab(text: '供应商分析')
                  ])),
          // 搜索框（仅 Tab 0）
          if (_tabIndex == 0)
            Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onSubmitted: (v) {
                      setState(() => _searchText = v);
                      _loadData();
                    },
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '输入条码/自编码/商品名称/拼音简码/辅助条码',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF999999)),
                      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_searchController.text.isNotEmpty)
                          GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchText = '');
                                _loadData();
                              },
                              child: const Icon(Icons.cancel, size: 18, color: Color(0xFF999999))),
                        GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchText = '');
                              FocusScope.of(context).requestFocus(_searchFocus);
                            },
                            child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: BossSvgIcon(svgFile: 'scan.svg', size: 20))),
                      ]),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Color(0xFFDEDEDE))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Color(0xFFDEDEDE))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(color: Color(0xFF006EFF))),
                    ))),
          // 类别筛选（仅 Tab 1）
          if (_tabIndex == 1)
            Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _buildLevelCard('全部', '')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildLevelCard('大类', '1'))
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _buildLevelCard('中类', '2')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildLevelCard('小类', '3'))
                  ]),
                ])),
          // 品牌/供应商排行卡片（Tab 2/3，有数据时显示）
          if ((_tabIndex == 2 || _tabIndex == 3) && _list.length >= 3)
            Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Expanded(child: _buildTopCard(0)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildTopCard(1)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildTopCard(2)),
                ])),
          // 首次加载（无数据）→ 全屏 loading；有数据则表格常驻（刷新仅叠加细 loading 条）
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
              child: Stack(
                children: [
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
                ],
              ),
            ),
        ]));
  }

  Widget _buildLevelCard(String label, String val) {
    final sel = _level == val;
    return GestureDetector(
      onTap: () {
        setState(() => _level = val);
        _loadData();
      },
      child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: sel ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: sel ? const Color(0xFF006EFF) : const Color(0xFF7A7A7A))),
            if (sel) ...[
              const SizedBox(height: 2),
              Text(_fmtNum(1, _sumData['qty']),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF006EFF)))
            ],
          ])),
    );
  }

  // ==================== 表格 ====================
  DataColumn2 _buildSortCol(String name, String label, TextStyle hs) {
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
    return DataColumn2(numeric: true, label: w);
  }

  Widget _buildTopCard(int i) {
    final row = _list[i];
    final name =
        _tabIndex == 2 ? row['brandname']?.toString() ?? '' : row['supname']?.toString() ?? '';
    final svg = 'top${i + 1}.svg';
    return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFDEDEDE))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          BossSvgIcon(svgFile: svg, size: 32),
          const SizedBox(height: 4),
          Text(name,
              style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(_fmtNum(1, row['qty']),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ]));
  }

  Widget _buildTable() {
    const hs = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const cs = TextStyle(fontSize: 13, color: Color(0xFF333333));
    // minWidth 保证排序列至少 140px（(875-45-130)/5=140），屏幕不足时横向滚动

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
            minWidth: 875,
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
                  fixedWidth: 45,
                  label: Padding(padding: EdgeInsets.only(left: 12), child: Text('排行', style: hs))),
              DataColumn2(
                  fixedWidth: 130,
                  label: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(_nameField, style: hs))),
              _buildSortCol('qty', '销量', hs),
              _buildSortCol('rramt', '金额', hs),
              _buildSortCol('grossamt', '毛利额', hs),
              _buildSortCol('grossrate', '毛利率', hs),
              _buildSortCol('avgprice', '均价', hs),
            ],
            rows: [
              for (var i = 0; i < _list.length; i++)
                DataRow2(
                    decoration: BoxDecoration(
                        color: i.isOdd ? const Color(0xFFF9F9F9) : Colors.white,
                        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3)))),
                    onSelectChanged: (_) => _onRowTap(i),
                    cells: _buildCells(i, cs)),
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
        ),
      ),
      if (_sumData.isNotEmpty) _buildSummaryRow(),
    ]);
  }

  List<DataCell> _buildCells(int i, TextStyle cs) {
    final row = _list[i];
    String name;
    String barcode = '';
    switch (_tabIndex) {
      case 0:
        name = row['name']?.toString() ?? '';
        barcode = row['barcode']?.toString() ?? '';
        break;
      case 1:
        name = row['typename']?.toString() ?? '';
        break;
      case 2:
        name = row['brandname']?.toString() ?? '';
        break;
      default:
        name = row['supname']?.toString() ?? '';
    }
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
              child: Text(_fmtNum(1, row['qty']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(3, row['rramt']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(3, row['grossamt']), style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('${_fmtNum(3, row['grossrate'])}%', style: cs)))),
      DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtNum(3, row['avgprice']), style: cs)))),
    ];
  }

  void _onRowTap(int i) {
    final row = _list[i];
    final startTime = _fmtDate(_startDate);
    final endTime = _fmtDate(_endDate);
    if (_tabIndex == 0) {
      Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: '/businessAnalysis/spfx/sp_bill'),
          builder: (_) => SpBillPage(
                productData: row,
                sids: _sids,
                startTime: startTime,
                endTime: endTime,
                timeIndex: _activeQuickTimeId ?? 1,
              )));
    } else {
      String module;
      switch (_tabIndex) {
        case 1:
          module = 'flfx';
          break;
        case 2:
          module = 'ppfx';
          break;
        default:
          module = 'gysfx';
      }
      Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: '/businessAnalysis/spfx/top_bill'),
          builder: (_) => TopBillPage(
                module: module,
                item: row,
                sids: _sids,
                startTime: startTime,
                endTime: endTime,
                field: _rankField,
                timeIndex: _activeQuickTimeId ?? 1,
              )));
    }
  }

  Widget _buildSummaryRow() {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const borderSide = BorderSide(color: Color(0xFFE1E9F3));
    final sum = _sumData;
    const fixW1 = 45.0, fixW2 = 130.0;
    const colW = (875.0 - fixW1 - fixW2) / 5;

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
                        child: Text(_fmtNum(1, sum['qty']), style: boldStyle))),
                SizedBox(
                    width: colW,
                    child: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 12),
                        decoration: const BoxDecoration(border: Border(right: borderSide)),
                        child: Text(_fmtNum(3, sum['rramt']), style: boldStyle))),
                SizedBox(
                    width: colW,
                    child: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 12),
                        decoration: const BoxDecoration(border: Border(right: borderSide)),
                        child: Text(_fmtNum(3, sum['grossamt']), style: boldStyle))),
                SizedBox(
                    width: colW,
                    child: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 12),
                        decoration: const BoxDecoration(border: Border(right: borderSide)),
                        child: Text('${_fmtNum(3, sum['grossrate'])}%', style: boldStyle))),
                SizedBox(
                    width: colW,
                    child: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 12),
                        decoration: const BoxDecoration(border: Border(right: borderSide)),
                        child: Text(_fmtNum(3, sum['avgprice']), style: boldStyle))),
              ])),
        )),
      ]),
    );
  }
}
