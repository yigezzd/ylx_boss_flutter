import 'dart:convert';
import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/data/businessReport/cashStatistics/cash_statistics_router.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 收银统计页面
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\cashStatistics\cashStatistics.vue
class CashStatisticsPage extends StatefulWidget {
  const CashStatisticsPage({super.key});

  @override
  State<CashStatisticsPage> createState() => _CashStatisticsPageState();
}

class _CashStatisticsPageState extends State<CashStatisticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  // ── 门店 ──
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';

  // ── 日期 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  // ── 收银员统计状态 ──
  bool _syLoading = false;
  bool _syHasMore = true;
  int _syPage = 1;
  List<Map<String, dynamic>> _syList = [];
  Map<String, dynamic> _sySumData = {};
  List<Map<String, dynamic>> _syPayColumns = [];

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时表格闪屏）
  bool _syHasLoadedOnce = false;

  // ── 币种统计状态 ──
  bool _bzLoading = false;
  List<Map<String, dynamic>> _payWays = [];
  List<Map<String, dynamic>> _vipaddWays = [];
  List<Map<String, dynamic>> _vipcardWays = [];

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时闪屏）
  bool _bzHasLoadedOnce = false;

  // ── 交班统计状态 ──
  bool _jbLoading = false;
  bool _jbHasMore = true;
  int _jbPage = 1;
  List<Map<String, dynamic>> _jbList = [];
  Map<String, dynamic> _jbSumData = {};

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时表格闪屏）
  bool _jbHasLoadedOnce = false;

  // ── 水平滚动同步 ──
  // 注：不再给 DataTable2 传外部 horizontalScrollController（data_table_2 插件在
  // 重建/卸载时会访问已 dispose 的外部控制器导致崩溃），
  // 改用 ScrollNotification 捕获表格横向偏移同步合计行
  final ScrollController _sySummaryHScrollController = ScrollController();
  final ScrollController _jbSummaryHScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _onTabChanged(_tabController.index);
      }
    });
    final now = DateTime.now();
    _endDate = now;
    _startDate = now; // 默认当天
    _activeQuickTimeId = 1; // 默认今日
    _loadStore();
    _loadSyData();
  }

  /// 根据表格横向滚动偏移同步合计行（带安全守卫与越界保护）
  void _syncSummaryScroll(ScrollController summaryCtrl, double offset) {
    if (!summaryCtrl.hasClients) return;
    try {
      final target = offset.clamp(0.0, summaryCtrl.position.maxScrollExtent);
      if (summaryCtrl.offset != target) summaryCtrl.jumpTo(target);
    } catch (_) {}
  }

  void _onTabChanged(int index) {
    setState(() => _tabIndex = index);
    // 切 tab 前将合计行横向滚动重置到起点，避免旧 tab 的滚动残留状态
    _safeJumpToStart(_sySummaryHScrollController);
    _safeJumpToStart(_jbSummaryHScrollController);
    // 每次切换 tab 都重新请求接口获取最新数据
    if (index == 0) {
      _syPage = 1;
      _syHasMore = true;
      _loadSyData();
    } else if (index == 1) {
      _loadBzData();
    } else if (index == 2) {
      _jbPage = 1;
      _jbHasMore = true;
      _loadJbData();
    }
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
        }
      }
    } catch (_) {}
  }

  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _activeStoreId,
    );
    if (result != null && mounted) {
      setState(() {
        _storeName = result['storename']?.toString() ?? '';
        _activeStoreId = result['storeid']?.toString() ?? '';
        _sids = _activeStoreId.isNotEmpty ? [int.tryParse(_activeStoreId) ?? 0] : [];
      });
      _onRefresh();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtAmt(dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(2);
  }

  Map<String, dynamic> _baseParams() => {
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'sids': _sids,
      };

  Future<void> _onRefresh() async {
    if (_tabIndex == 0) {
      _syPage = 1;
      _syHasMore = true;
      await _loadSyData();
    } else if (_tabIndex == 1) {
      await _loadBzData();
    } else {
      _jbPage = 1;
      _jbHasMore = true;
      await _loadJbData();
    }
  }

  // ==================== 收银员统计 Tab 0 ====================
  Future<void> _loadSyData() async {
    if (_syLoading) return;
    setState(() => _syLoading = true);
    try {
      final result = await request(HttpApi.cashreconGetCasherForDaySummerybyname, {
        'is_page': 1,
        'page': _syPage,
        'pagesize': 20,
        ..._baseParams(),
      });
      final map = result['data'] is Map<String, dynamic>
          ? result['data'] as Map<String, dynamic>
          : <String, dynamic>{};
      final list = (map['list'] is List)
          ? (map['list'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final sumdata = map['sumdata'];
      if (sumdata is Map<String, dynamic>) {
        _sySumData = sumdata['sumdata'] is Map<String, dynamic>
            ? sumdata['sumdata'] as Map<String, dynamic>
            : {};
        final paylist = sumdata['paylist'];
        if (paylist is List && paylist.isNotEmpty) {
          _syPayColumns = paylist.cast<Map<String, dynamic>>();
        }
      }
      if (mounted) {
        setState(() {
          if (_syPage == 1) {
            _syList = list;
          } else {
            _syList.addAll(list);
          }
          _syHasMore = list.length >= 20;
          if (_syHasMore) _syPage++;
          _syHasLoadedOnce = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _syHasMore = false);
    } finally {
      if (mounted) setState(() => _syLoading = false);
    }
  }

  // ==================== 币种统计 Tab 1 ====================

  /// 按占比降序排序（payrate 可能是数字或带 % 的字符串）
  static List<Map<String, dynamic>> _sortByRate(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      double parseRate(dynamic v) {
        final s = v?.toString().replaceAll('%', '') ?? '';
        return double.tryParse(s) ?? 0;
      }

      return parseRate(b['payrate']).compareTo(parseRate(a['payrate']));
    });
    return list;
  }

  Future<void> _loadBzData() async {
    if (_bzLoading) return;
    setState(() => _bzLoading = true);
    try {
      final result = await request(HttpApi.cashreconFindAccountPayTotal, _baseParams());
      final map = result['data'] is Map<String, dynamic>
          ? result['data'] as Map<String, dynamic>
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          _payWays = _sortByRate((map['payWays'] is List)
              ? (map['payWays'] as List).cast<Map<String, dynamic>>()
              : []);
          _vipaddWays = _sortByRate((map['vipaddWays'] is List)
              ? (map['vipaddWays'] as List).cast<Map<String, dynamic>>()
              : []);
          _vipcardWays = _sortByRate((map['vipcardWays'] is List)
              ? (map['vipcardWays'] as List).cast<Map<String, dynamic>>()
              : []);
          _bzHasLoadedOnce = true;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _bzLoading = false);
    }
  }

  // ==================== 交班统计 Tab 2 ====================
  Future<void> _loadJbData() async {
    if (_jbLoading) return;
    setState(() => _jbLoading = true);
    try {
      final result = await request(HttpApi.cashreconFindSaleJkd, {
        'is_page': 1,
        'page': _jbPage,
        'pagesize': 20,
        'field': 'createtime',
        'type': 'desc',
        ..._baseParams(),
      });
      final map = result['data'] is Map<String, dynamic>
          ? result['data'] as Map<String, dynamic>
          : <String, dynamic>{};
      final list = (map['list'] is List)
          ? (map['list'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final sumdata = map['sumdata'];
      if (sumdata is Map<String, dynamic>) {
        _jbSumData = sumdata;
      }
      if (mounted) {
        setState(() {
          if (_jbPage == 1) {
            _jbList = list;
          } else {
            _jbList.addAll(list);
          }
          _jbHasMore = list.length >= 20;
          if (_jbHasMore) _jbPage++;
          _jbHasLoadedOnce = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _jbHasMore = false);
    } finally {
      if (mounted) setState(() => _jbLoading = false);
    }
  }

  /// 安全滚动到起点（控制器未挂载时跳过）
  void _safeJumpToStart(ScrollController controller) {
    if (!controller.hasClients) return;
    try {
      if (controller.offset != 0) controller.jumpTo(0);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sySummaryHScrollController.dispose();
    _jbSummaryHScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('收银统计', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Column(
        children: [
          _buildTabs(),
          _buildHeader(),
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  // ==================== 顶部区域 ====================
  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // 门店选择
          GestureDetector(
            onTap: _selectStore,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _storeName.isNotEmpty ? _storeName : '全部机构',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20, color: Color(0xFF666666)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          // 时间筛选
          _buildTimeSelector(),
        ],
      ),
    );
  }

  // ==================== 时间选择器（对齐 cash_flow_page 风格）====================
  Widget _buildTimeSelector() {
    final labels = ['昨天', '今日', '本周', '本月', '自定义'];
    final activeId = _activeQuickTimeId ?? 1;
    const primary = Color(0xFF006EFF);
    const onSurface = Color(0xFF333333);
    const borderColor = Color(0xFFD1D5DB);

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      child: Column(
        children: [
          // ── 分段控制器 ──
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
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? Colors.white : onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          // ── 日期导航行 ──
          _buildDateNavigation(),
        ],
      ),
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
        break;
      case 1: // 今天
        start = DateTime(now.year, now.month, now.day);
        end = now;
        break;
      case 2: // 本周
        final wd = now.weekday;
        start = DateTime(now.year, now.month, now.day - (wd - 1));
        end = now;
        break;
      case 3: // 本月
        start = DateTime(now.year, now.month);
        end = now;
        break;
      default: // 自定义
        start = _startDate;
        end = _endDate;
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _activeQuickTimeId = id;
    });
    _onRefresh();
  }

  Widget _buildDateNavigation() {
    final isRange = _activeQuickTimeId == 2 || _activeQuickTimeId == 4;
    final isMonth = _activeQuickTimeId == 3;
    final showArrows = _activeQuickTimeId != 4;

    return Row(
      children: [
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
          child: Row(
            children: [
              if (isRange) ...[
                Expanded(child: _buildDatePart(_startDate, isStart: true)),
                _buildDateToSeparator(),
                Expanded(child: _buildDatePart(_endDate, isEnd: true)),
              ] else
                Expanded(
                  child: _buildDatePart(_startDate, isMonth: isMonth),
                ),
            ],
          ),
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
      ],
    );
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
          _onRefresh();
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
        _onRefresh();
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        margin: EdgeInsets.only(
          left: isStart ? 0 : 4,
          right: isEnd ? 0 : 4,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
        ),
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
    DateTime start = _startDate;
    DateTime end = _endDate;
    switch (id) {
      case 0: // 昨天 → ±1 day
      case 1: // 今天 → ±1 day
        start = start.add(Duration(days: direction));
        end = start;
        break;
      case 2: // 本周 → ±7 days
        start = start.add(Duration(days: 7 * direction));
        end = end.add(Duration(days: 7 * direction));
        break;
      case 3: // 本月 → ±1 month
        start = DateTime(_startDate.year, _startDate.month + direction);
        end = DateTime(start.year, start.month + 1, 0);
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    _onRefresh();
  }

  // ==================== Tabs ====================
  Widget _buildTabs() {
    return ColoredBox(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF006EFF),
        unselectedLabelColor: const Color(0xFF666666),
        indicatorColor: const Color(0xFF006EFF),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        tabs: const [
          Tab(text: '收银员统计'),
          Tab(text: '币种统计'),
          Tab(text: '交班统计'),
        ],
      ),
    );
  }

  // ==================== 加载提示 ====================
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

  // ==================== Tab 内容 ====================
  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return _buildCashierTab();
      case 1:
        return _buildCurrencyTab();
      case 2:
        return _buildShiftTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ==================== 空状态 ====================
  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
          SizedBox(height: 12),
          Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  // ==================== Tab 0: 收银员统计 ====================
  Widget _buildCashierTab() {
    if (_syList.isEmpty && (!_syLoading || _syHasLoadedOnce)) {
      // 空态：加载完成无数据，或已加载过刷新中（保留空态+图标卡片，避免表格骨架闪屏）
      return Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: () async {
            _syPage = 1;
            _syHasMore = true;
            await _loadSyData();
          },
          child: ListView(children: [
            const SizedBox(height: 200),
            _buildEmptyState(),
          ]),
        ),
        if (_syLoading) _loadingCard,
      ]);
    }
    final columns = _buildCashierColumns();
    return Stack(children: [
      Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // 表格横向滚动时同步合计行
                if (n.metrics.axis == Axis.horizontal) {
                  _syncSummaryScroll(_sySummaryHScrollController, n.metrics.pixels);
                }
                if (n is ScrollEndNotification &&
                    n.metrics.axis == Axis.vertical &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
                    _syHasMore &&
                    !_syLoading) {
                  _loadSyData();
                }
                return false;
              },
              child: RefreshIndicator(
                color: const Color(0xFF006EFF),
                onRefresh: () async {
                  _syPage = 1;
                  _syHasMore = true;
                  await _loadSyData();
                },
                child: DataTable2(
                  fixedLeftColumns: 2,
                  minWidth: columns.length * 100.0 + 100,
                  horizontalMargin: 0,
                  columnSpacing: 0,
                  dataRowHeight: 56,
                  headingRowHeight: 44,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
                    verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
                  ),
                  columns: columns,
                  rows: [
                    ..._syList.asMap().entries.map((e) => _buildCashierRow(e.value, e.key)),
                    // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
                    if (_syLoading && (_syPage > 1 || !_syHasLoadedOnce))
                      DataRow2(cells: [
                        const DataCell(SizedBox(
                            height: 44,
                            child: Center(
                                child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Color(0xFF006EFF)))))),
                        for (int i = 1; i < columns.length; i++) DataCell.empty,
                      ]),
                  ],
                ),
              ),
            ),
          ),
          if (_sySumData.isNotEmpty) _buildCashierSummaryRow(),
        ],
      ),
      if (_syLoading && _syHasLoadedOnce && _syPage == 1) _loadingCard,
    ]);
  }

  List<DataColumn2> _buildCashierColumns() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    final list = <DataColumn2>[
      DataColumn2(
        fixedWidth: 120,
        label: Container(
          padding: const EdgeInsets.only(left: 5, right: 12),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('收银员', style: headerStyle),
          ]),
        ),
      ),
      const DataColumn2(
        fixedWidth: 130,
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('总收银金额', textAlign: TextAlign.right, style: headerStyle),
        ),
        numeric: true,
      ),
    ];
    if (_syPayColumns.isNotEmpty) {
      for (final col in _syPayColumns) {
        final label = col['payname']?.toString() ?? '';
        list.add(DataColumn2(
          label: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, textAlign: TextAlign.right, style: headerStyle),
          ),
          numeric: true,
        ));
      }
    } else {
      for (final label in ['现金', '微信', '支付宝', '会员卡', '抹零']) {
        list.add(DataColumn2(
          label: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, textAlign: TextAlign.right, style: headerStyle),
          ),
          numeric: true,
        ));
      }
    }
    return list;
  }

  DataRow2 _buildCashierRow(Map<String, dynamic> row, int index) {
    final isOdd = index.isOdd;
    final cells = <DataCell>[
      DataCell(Center(
        child: Text(row['cashname']?.toString() ?? '--',
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
      )),
      DataCell(Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(_fmtAmt(row['sumpayamt']),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF333333))),
        ),
      )),
    ];
    // 动态支付列
    if (_syPayColumns.isNotEmpty) {
      for (final col in _syPayColumns) {
        final code = col['code']?.toString() ?? '';
        cells.add(DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_fmtAmt(row['pay$code'] ?? 0),
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
        )));
      }
    } else {
      // 填充 5 个默认备付列（与 _buildCashierColumns 默认列对齐）
      for (int i = 0; i < 5; i++) {
        cells.add(const DataCell(SizedBox.shrink()));
      }
    }
    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: cells,
    );
  }

  /// 收银员统计合计行（固定在表格底部，横向滚动与表格同步）
  Widget _buildCashierSummaryRow() {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const borderRight = BorderSide(color: Color(0xFFE1E9F3));

    // 动态列宽度：与 DataTable2 minWidth 对齐（columns * 100 + 100，减去冻结列250）
    final payCount = _syPayColumns.isNotEmpty ? _syPayColumns.length : 5;
    final totalCols = 2 + payCount;
    final minWidth = totalCols * 100.0 + 100;
    const frozenWidth = 250.0;
    final scrollWidth = minWidth - frozenWidth;
    final colW = scrollWidth / payCount;

    final scrollCells = <Widget>[];
    if (_syPayColumns.isNotEmpty) {
      for (final col in _syPayColumns) {
        final code = col['code']?.toString() ?? '';
        scrollCells.add(SizedBox(
          width: colW,
          child: Container(
            height: 48,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 12),
            decoration: const BoxDecoration(border: Border(right: borderRight)),
            child: Text(_fmtAmt(_sySumData['pay$code'] ?? 0), style: boldStyle),
          ),
        ));
      }
    } else {
      for (int i = 0; i < 5; i++) {
        scrollCells.add(SizedBox(
          width: colW,
          child: Container(
            height: 48,
            decoration: const BoxDecoration(border: Border(right: borderRight)),
          ),
        ));
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        border: Border(top: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      child: Row(
        children: [
          // 冻结列：收银员（120） + 总收银金额（130）
          SizedBox(
            width: frozenWidth,
            child: Row(
              children: [
                Container(
                  width: 120,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(border: Border(right: borderRight)),
                  child: const Text('合计', style: boldStyle),
                ),
                Container(
                  width: 130,
                  height: 48,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 12),
                  decoration: const BoxDecoration(border: Border(right: borderRight)),
                  child: Text(_fmtAmt(_sySumData['sumpayamt'] ?? 0), style: boldStyle),
                ),
              ],
            ),
          ),
          // 可滚动列（与表格横向滚动同步）
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              controller: _sySummaryHScrollController,
              child: Row(children: scrollCells),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Tab 1: 币种统计 ====================
  Widget _buildCurrencyTab() {
    if (_bzLoading && !_bzHasLoadedOnce) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)));
    }
    if (_payWays.isEmpty && _vipaddWays.isEmpty && _vipcardWays.isEmpty) {
      return Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: _loadBzData,
          child: ListView(children: [
            const SizedBox(height: 200),
            _buildEmptyState(),
          ]),
        ),
        if (_bzLoading) _loadingCard,
      ]);
    }
    return Stack(children: [
      RefreshIndicator(
        color: const Color(0xFF006EFF),
        onRefresh: _loadBzData,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildCurrencyTable('收银明细', _payWays),
            const SizedBox(height: 12),
            _buildCurrencyTable('充值币种明细', _vipaddWays),
            const SizedBox(height: 12),
            _buildCurrencyTable('售卡币种明细', _vipcardWays),
          ],
        ),
      ),
      if (_bzLoading) _loadingCard,
    ]);
  }

  Widget _buildCurrencyTable(String title, List<Map<String, dynamic>> data) {
    final sumPayAmt =
        data.fold<num>(0, (s, e) => s + (num.tryParse(e['payamt']?.toString() ?? '0') ?? 0));
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          const SizedBox(height: 8),
          SizedBox(
            height: math.min(44.0 + 57.0 * (data.length + 1), 350.0),
            child: DataTable2(
              minWidth: 350,
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
                    label: Padding(
                  padding: EdgeInsets.only(left: 5, right: 12),
                  child: Text('序号', style: headerStyle),
                )),
                DataColumn2(
                    label: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('币种', style: headerStyle),
                )),
                DataColumn2(
                    label: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('收银金额', textAlign: TextAlign.right, style: headerStyle),
                    ),
                    numeric: true),
                DataColumn2(
                    label: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('占比', textAlign: TextAlign.right, style: headerStyle),
                    ),
                    numeric: true),
              ],
              rows: [
                ...data.asMap().entries.map((e) {
                  final i = e.key;
                  final row = e.value;
                  final isOdd = i.isOdd;
                  final payAmt = num.tryParse(row['payamt']?.toString() ?? '0') ?? 0;
                  final payRate = row['payrate']?.toString() ?? '--';
                  return DataRow2(
                    decoration: BoxDecoration(
                      color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
                      border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
                    ),
                    cells: [
                      DataCell(
                          Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 13)))),
                      DataCell(Center(
                          child: Text(row['payname']?.toString() ?? '--',
                              style: const TextStyle(fontSize: 13)))),
                      DataCell(Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(_fmtAmt(payAmt), style: const TextStyle(fontSize: 13))))),
                      DataCell(Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(payRate, style: const TextStyle(fontSize: 13))))),
                    ],
                  );
                }),
                // 合计行
                DataRow2(
                  color: WidgetStateProperty.all(const Color(0xFFF0F4FF)),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0xFFE1E9F3))),
                  ),
                  cells: [
                    const DataCell(Center(
                        child: Text('合计',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))),
                    const DataCell(SizedBox.shrink()),
                    DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(_fmtAmt(sumPayAmt),
                                style:
                                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))))),
                    const DataCell(SizedBox.shrink()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Tab 2: 交班统计 ====================
  Widget _buildShiftTab() {
    if (_jbList.isEmpty && (!_jbLoading || _jbHasLoadedOnce)) {
      // 空态：加载完成无数据，或已加载过刷新中（保留空态+图标卡片，避免表格骨架闪屏）
      return Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: () async {
            _jbPage = 1;
            _jbHasMore = true;
            await _loadJbData();
          },
          child: ListView(children: [
            const SizedBox(height: 200),
            _buildEmptyState(),
          ]),
        ),
        if (_jbLoading) _loadingCard,
      ]);
    }
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    return Stack(children: [
      Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // 表格横向滚动时同步合计行
                if (n.metrics.axis == Axis.horizontal) {
                  _syncSummaryScroll(_jbSummaryHScrollController, n.metrics.pixels);
                }
                if (n is ScrollEndNotification &&
                    n.metrics.axis == Axis.vertical &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
                    _jbHasMore &&
                    !_jbLoading) {
                  _loadJbData();
                }
                return false;
              },
              child: RefreshIndicator(
                color: const Color(0xFF006EFF),
                onRefresh: () async {
                  _jbPage = 1;
                  _jbHasMore = true;
                  await _loadJbData();
                },
                child: DataTable2(
                  fixedLeftColumns: 1,
                  minWidth: 650,
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
                      fixedWidth: 120,
                      label: Padding(
                        padding: EdgeInsets.only(left: 5, right: 12),
                        child: Text('收银员', style: headerStyle),
                      ),
                    ),
                    DataColumn2(
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('应交金额', textAlign: TextAlign.right, style: headerStyle),
                      ),
                      numeric: true,
                    ),
                    DataColumn2(
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('收款金额', textAlign: TextAlign.right, style: headerStyle),
                      ),
                      numeric: true,
                    ),
                    DataColumn2(
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('实交金额', textAlign: TextAlign.right, style: headerStyle),
                      ),
                      numeric: true,
                    ),
                    DataColumn2(
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('时间', textAlign: TextAlign.right, style: headerStyle),
                      ),
                    ),
                  ],
                  rows: [
                    ..._jbList.asMap().entries.map((e) => _buildShiftRow(e.value, e.key)),
                    // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
                    if (_jbLoading && (_jbPage > 1 || !_jbHasLoadedOnce))
                      const DataRow2(cells: [
                        DataCell(SizedBox(
                            height: 44,
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
          ),
          if (_jbSumData.isNotEmpty) _buildShiftSummaryRow(),
        ],
      ),
      if (_jbLoading && _jbHasLoadedOnce && _jbPage == 1) _loadingCard,
    ]);
  }

  /// 交班统计合计行（固定在表格底部，横向滚动与表格同步）
  Widget _buildShiftSummaryRow() {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const borderRight = BorderSide(color: Color(0xFFE1E9F3));

    // 非冻结列宽度：(minWidth 650 - 冻结120) / 4列 = 132.5
    const colW = 132.5;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        border: Border(top: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      child: Row(
        children: [
          // 冻结列：收银员（120）
          Container(
            width: 120,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(border: Border(right: borderRight)),
            child: const Text('合计', style: boldStyle),
          ),
          // 可滚动列（与表格横向滚动同步）
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              controller: _jbSummaryHScrollController,
              child: Row(
                children: [
                  SizedBox(
                    width: colW,
                    child: Container(
                      height: 48,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(border: Border(right: borderRight)),
                      child: Text(_fmtAmt(_jbSumData['payableamt'] ?? 0), style: boldStyle),
                    ),
                  ),
                  SizedBox(
                    width: colW,
                    child: Container(
                      height: 48,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(border: Border(right: borderRight)),
                      child: Text(_fmtAmt(_jbSumData['saleamt'] ?? 0), style: boldStyle),
                    ),
                  ),
                  SizedBox(
                    width: colW,
                    child: Container(
                      height: 48,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(border: Border(right: borderRight)),
                      child: Text(_fmtAmt(_jbSumData['payamt'] ?? 0), style: boldStyle),
                    ),
                  ),
                  SizedBox(
                    width: colW,
                    child: Container(
                      height: 48,
                      decoration: const BoxDecoration(border: Border(right: borderRight)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  DataRow2 _buildShiftRow(Map<String, dynamic> row, int index) {
    final isOdd = index.isOdd;
    const amtStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        DataCell(GestureDetector(
          onTap: () {
            NavigatorUtils.push(context, CashStatisticsRouter.jbtjBill, arguments: row);
          },
          child: Center(
            child: Text(row['opername']?.toString() ?? '--',
                style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
          ),
        )),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(_fmtAmt(row['payableamt']), style: amtStyle)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(_fmtAmt(row['saleamt']), style: amtStyle)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(_fmtAmt(row['payamt']), style: amtStyle)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(row['createtime']?.toString() ?? '--',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF999999)))))),
      ],
    );
  }
}
