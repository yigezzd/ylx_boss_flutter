import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart' as classify;
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

import 'num_moving_item_page.dart';

/// 动销率分析页面
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\salesRateAnalysis\salesRateAnalysis.vue
class SalesRateAnalysisPage extends StatefulWidget {
  const SalesRateAnalysisPage({super.key});

  @override
  State<SalesRateAnalysisPage> createState() => _SalesRateAnalysisPageState();
}

class _SalesRateAnalysisPageState extends State<SalesRateAnalysisPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  // ── 门店 ──
  String _storeName = '';
  String _activeStoreId = '';
  List<int> _sids = [];

  // ── 分类 ──
  List<Map<String, dynamic>> _typeList = [];

  // ── 日期 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  // ── 筛选参数 ──
  String _supid = '';
  String _supname = '';
  String _brandid = '';
  String _brandname = '';
  List<String> _itemstatus = [];
  String _level = '1';

  // ── Tab 0: 门店动销率 ──
  bool _mdLoading = false;
  bool _mdHasMore = true;
  int _mdPage = 1;
  List<Map<String, dynamic>> _mdList = [];
  final Map<String, double> _mdSum = {};

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时表格闪屏）
  bool _mdHasLoadedOnce = false;

  // ── Tab 1: 商品类别动销率 ──
  bool _lbLoading = false;
  bool _lbHasMore = true;
  int _lbPage = 1;
  List<Map<String, dynamic>> _lbList = [];
  Map<String, dynamic> _lbSumData = {};

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时表格闪屏）
  bool _lbHasLoadedOnce = false;

  // ── 横滚同步 ──
  final ScrollController _mdTableHCtrl = ScrollController();
  final ScrollController _mdSummaryHCtrl = ScrollController();
  final ScrollController _lbTableHCtrl = ScrollController();
  final ScrollController _lbSummaryHCtrl = ScrollController();

  void _syncMdScroll() {
    if (_mdSummaryHCtrl.hasClients) {
      _mdSummaryHCtrl.jumpTo(_mdTableHCtrl.offset);
    }
  }

  void _syncLbScroll() {
    if (_lbSummaryHCtrl.hasClients) {
      _lbSummaryHCtrl.jumpTo(_lbTableHCtrl.offset);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
        _onTabChanged();
      }
    });
    _mdTableHCtrl.addListener(_syncMdScroll);
    _lbTableHCtrl.addListener(_syncLbScroll);
    final now = DateTime.now();
    _endDate = now;
    _startDate = now.subtract(const Duration(days: 30)); // 默认近30天
    _activeQuickTimeId = 4; // 默认自定义：近一个月
    _loadStore();
  }

  @override
  void dispose() {
    _mdTableHCtrl.removeListener(_syncMdScroll);
    _lbTableHCtrl.removeListener(_syncLbScroll);
    _mdTableHCtrl.dispose();
    _mdSummaryHCtrl.dispose();
    _lbTableHCtrl.dispose();
    _lbSummaryHCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ==================== 门店加载 ====================

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
      _resetAndLoad();
    }
  }

  // ==================== 分类选择 ====================

  Future<void> _selectCategory() async {
    final initialIds =
        _typeList.map((e) => e['typeid']?.toString() ?? '').where((id) => id.isNotEmpty).toList();

    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => classify.CategoryListPage(
          isSelect: true,
          isMultiSelect: true,
          showAll: true,
          initialSelectedIds: initialIds,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _typeList = result);
      _resetAndLoad();
    }
  }

  String get _categoryLabel {
    if (_typeList.isEmpty) return '全部分类';
    return _typeList.map((e) => e['name']?.toString() ?? '').join('|');
  }

  // ==================== 日期工具 ====================

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtQty(dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(1);
  }

  // ==================== 基础参数 ====================

  Map<String, dynamic> _baseParams() => {
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'sids': _sids,
        'typeid': _typeList
            .map((e) => e['typeid']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
        if (_supid.isNotEmpty) 'supid': _supid,
        if (_brandname.isNotEmpty) 'brandname': _brandname.replaceAll('|', ','),
        if (_itemstatus.isNotEmpty) 'itemstatusin': _itemstatus.join(','),
        if (_tabIndex == 1) 'level': _level,
      };

  void _resetAndLoad() {
    if (_tabIndex == 0) {
      _mdPage = 1;
      _mdHasMore = true;
    } else {
      _lbPage = 1;
      _lbHasMore = true;
    }
    _loadData();
  }

  void _onTabChanged() {
    _resetAndLoad();
  }

  // ==================== 数据加载 ====================

  Future<void> _loadData() {
    if (_tabIndex == 0) return _loadMdData();
    return _loadLbData();
  }

  Future<void> _loadMdData() async {
    if (_mdLoading) return;
    setState(() => _mdLoading = true);
    try {
      final result = await request(HttpApi.sellthroughStoreSellThrough, {
        'is_page': 1,
        'page': _mdPage,
        'pagesize': 20,
        'field': 'saleqty',
        'type': 'desc',
        ..._baseParams(),
      });
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];

      if (mounted) {
        setState(() {
          if (_mdPage == 1) {
            _mdList = list;
          } else {
            _mdList.addAll(list);
          }
          _mdHasMore = list.length >= 20;
          if (_mdHasMore) _mdPage++;
          _mdHasLoadedOnce = true;
          _mdSum.clear();
          _mdSum['allqty'] =
              _mdList.fold<double>(0, (s, e) => s + (_parseDouble(e['allqty']) ?? 0));
          _mdSum['saleqty'] =
              _mdList.fold<double>(0, (s, e) => s + (_parseDouble(e['saleqty']) ?? 0));
          _mdSum['nosaleqty'] =
              _mdList.fold<double>(0, (s, e) => s + (_parseDouble(e['nosaleqty']) ?? 0));
        });
      }
    } catch (_) {
      if (mounted) setState(() => _mdHasMore = false);
    } finally {
      if (mounted) setState(() => _mdLoading = false);
    }
  }

  Future<void> _loadLbData() async {
    if (_lbLoading) return;
    setState(() => _lbLoading = true);
    try {
      final result = await request(HttpApi.sellthroughTypeSellThrough, {
        'is_page': 1,
        'page': _lbPage,
        'pagesize': 20,
        'field': 'saleqty',
        'type': 'desc',
        ..._baseParams(),
      });
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      final sumdata = map['sumdata'];

      if (mounted) {
        setState(() {
          if (_lbPage == 1) {
            _lbList = list;
          } else {
            _lbList.addAll(list);
          }
          _lbHasMore = list.length >= 20;
          if (_lbHasMore) _lbPage++;
          _lbHasLoadedOnce = true;
          if (sumdata is Map<String, dynamic>) {
            _lbSumData = sumdata;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _lbHasMore = false);
    } finally {
      if (mounted) setState(() => _lbLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    if (_tabIndex == 0) {
      _mdPage = 1;
      _mdHasMore = true;
    } else {
      _lbPage = 1;
      _lbHasMore = true;
    }
    await _loadData();
  }

  static double? _parseDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  /// 打开动销/未动销品项数详情页
  void _openNumMovingItem(Map<String, dynamic> row, bool isSaleQty) {
    // —— 对齐 Vue cellClick 逻辑 ——
    // 1. 清洗行数据：删除 typeid1/2/3，typeid 包装为数组
    final cleanedRow = Map<String, dynamic>.from(row);
    cleanedRow.remove('typeid1');
    cleanedRow.remove('typeid2');
    cleanedRow.remove('typeid3');
    if (cleanedRow.containsKey('typeid') && cleanedRow['typeid'] != null) {
      cleanedRow['typeid'] = [cleanedRow['typeid']];
    }

    // 2. typeid 空则传空字符串（对齐 Vue: typeid.length > 0 ? typeid : ""）
    final typeidList =
        _typeList.map((e) => e['typeid']?.toString() ?? '').where((id) => id.isNotEmpty).toList();

    // 3. 基础参数（sids 始终用父页面的，不用行 storeid 覆盖）
    final params = <String, dynamic>{
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'sids': _sids,
      'typeid': typeidList.isNotEmpty ? typeidList : '',
      if (_supid.isNotEmpty) 'supid': _supid,
      if (_brandname.isNotEmpty) 'brandname': _brandname.replaceAll('|', ','),
      if (_itemstatus.isNotEmpty) 'itemstatusin': _itemstatus.join(','),
      if (_tabIndex == 1) 'level': _level,
      // 4. 合并行数据（对齐 Vue: { ...data, ...newRow }）
      ...cleanedRow,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NumMovingItemPage(
          params: params,
          selectflag: isSaleQty ? 1 : 0,
          title: isSaleQty ? '动销品项数' : '未动销品项数',
        ),
      ),
    );
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('动销率分析', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Column(
        children: [
          _buildTabs(),
          _buildHeader(),
          _buildTimeSelector(),
          Expanded(
              child: IndexedStack(
            index: _tabIndex,
            children: [
              _buildMdTab(),
              _buildLbTab(),
            ],
          )),
        ],
      ),
    );
  }

  // ==================== Tabs ====================

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
          Tab(text: '门店动销率'),
          Tab(text: '商品类别动销率'),
        ],
      ),
    );
  }

  // ==================== 顶部选择区 ====================

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
      child: Row(
        children: [
          // 门店
          Expanded(
            child: _buildDropBtn(
              label: _storeName.isNotEmpty ? _storeName : '全部机构',
              onTap: _selectStore,
            ),
          ),
          const SizedBox(width: 8),
          // 分类
          Expanded(
            child: _buildDropBtn(
              label: _categoryLabel,
              onTap: _selectCategory,
            ),
          ),
          const SizedBox(width: 8),
          // Tab 0: 供应商 | Tab 1: 分类级别
          Expanded(
            child: _tabIndex == 0
                ? _buildDropBtn(
                    label: _supname.isNotEmpty ? _supname : '全部供应商',
                    onTap: _openSupplierSelector,
                  )
                : _buildDropBtn(
                    label: _levelLabel,
                    onTap: _showLevelPicker,
                  ),
          ),
          const SizedBox(width: 8),
          // 筛选按钮
          GestureDetector(
            onTap: _openFilterSheet,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const BossSvgIcon(
                svgFile: 'fliter.svg',
                size: 22,
                color: Color(0xFF666666),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropBtn({
    required String label,
    required VoidCallback onTap,
    int maxLines = 1,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
          ],
        ),
      ),
    );
  }

  String get _levelLabel {
    switch (_level) {
      case '1':
        return '一级分类';
      case '2':
        return '二级分类';
      case '3':
        return '三级分类';
      default:
        return '全部分类级别';
    }
  }

  void _showLevelPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      const SizedBox(width: 48),
                      const Expanded(
                        child: Text(
                          '选择分类级别',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                            },
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                ...['1', '2', '3'].map((v) {
                  final selected = _level == v;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _level = v);
                      Navigator.pop(ctx);
                      _resetAndLoad();
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
                            child: Text(
                              v == '1'
                                  ? '一级分类'
                                  : v == '2'
                                      ? '二级分类'
                                      : '三级分类',
                              style: TextStyle(
                                fontSize: 14,
                                color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                              ),
                            ),
                          ),
                          if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== 时间选择器 ====================

  Widget _buildTimeSelector() {
    final labels = ['昨天', '今日', '本周', '本月', '自定义'];
    final activeId = _activeQuickTimeId ?? 4;
    const primary = Color(0xFF006EFF);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        children: [
          Container(
            height: 37,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
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
                          color: selected ? Colors.white : const Color(0xFF333333),
                        ),
                      ),
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
    });
    _resetAndLoad();
  }

  Widget _buildDateNavigation() {
    final isRange = _activeQuickTimeId == 2 || _activeQuickTimeId == 4;
    final isMonth = _activeQuickTimeId == 3;
    final showArrows = _activeQuickTimeId != 4;
    final theme = Theme.of(context);

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
            child: Icon(Icons.chevron_left, size: 18, color: theme.colorScheme.onSurfaceVariant),
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
            child: Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
    ]);
  }

  Widget _buildDatePart(DateTime date,
      {bool isStart = false, bool isEnd = false, bool isMonth = false}) {
    final theme = Theme.of(context);
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
          _resetAndLoad();
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
        _resetAndLoad();
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
            borderRadius: BorderRadius.circular(5)),
        child: Text(label, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface)),
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
    final id = _activeQuickTimeId ?? 4;
    DateTime start = _startDate;
    DateTime end = _endDate;
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
    });
    _resetAndLoad();
  }

  // ==================== Tab 0: 门店动销率 ====================

  Widget _buildMdTab() {
    if (_mdList.isEmpty && (!_mdLoading || _mdHasLoadedOnce)) {
      // 空态：加载完成无数据，或已加载过刷新中（保留空态+图标卡片，避免表格骨架闪屏）
      return Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: _onRefresh,
          child: ListView(children: [
            const SizedBox(height: 200),
            _emptyState(),
          ]),
        ),
        if (_mdLoading) _loadingCard,
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
                // 竖向滚动加载更多
                if (n is ScrollEndNotification &&
                    n.metrics.axis == Axis.vertical &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
                    _mdHasMore &&
                    !_mdLoading) {
                  _loadMdData();
                }
                // 横向滚动同步到合计行（DataTable2 水平滚动在嵌套深度 >=1 处）
                if (n is ScrollUpdateNotification && n.metrics.axis == Axis.horizontal) {
                  if (_mdSummaryHCtrl.hasClients) {
                    _mdSummaryHCtrl.jumpTo(n.metrics.pixels);
                  }
                }
                return false;
              },
              child: RefreshIndicator(
                color: const Color(0xFF006EFF),
                onRefresh: _onRefresh,
                child: DataTable2(
                  horizontalScrollController: _mdTableHCtrl,
                  fixedLeftColumns: 2,
                  minWidth: 560,
                  horizontalMargin: 0,
                  columnSpacing: 0,
                  dataRowHeight: 52,
                  headingRowHeight: 44,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
                    verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
                  ),
                  columns: const [
                    DataColumn2(
                      fixedWidth: 40,
                      label: Padding(
                        padding: EdgeInsets.only(left: 5, right: 4),
                        child: Text('序号', style: headerStyle),
                      ),
                    ),
                    DataColumn2(
                      fixedWidth: 120,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('机构名称', style: headerStyle),
                      ),
                    ),
                    DataColumn2(
                      numeric: true,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('动销品项数', textAlign: TextAlign.right, style: headerStyle),
                      ),
                    ),
                    DataColumn2(
                      numeric: true,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('未动销品项数', textAlign: TextAlign.right, style: headerStyle),
                      ),
                    ),
                    DataColumn2(
                      numeric: true,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('品项总数', textAlign: TextAlign.right, style: headerStyle),
                      ),
                    ),
                    DataColumn2(
                      numeric: true,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('动销率', textAlign: TextAlign.right, style: headerStyle),
                      ),
                    ),
                  ],
                  rows: [
                    for (var i = 0; i < _mdList.length; i++) _buildMdRow(_mdList[i], i),
                    // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
                    if (_mdLoading && (_mdPage > 1 || !_mdHasLoadedOnce))
                      const DataRow(cells: [
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
                        DataCell.empty,
                      ]),
                  ],
                ),
              ),
            ),
          ),
          if (_mdList.isNotEmpty) _buildMdSummaryRow(),
        ],
      ),
      if (_mdLoading && _mdHasLoadedOnce && _mdPage == 1) _loadingCard,
    ]);
  }

  DataRow2 _buildMdRow(Map<String, dynamic> row, int index) {
    final isOdd = index.isOdd;
    final allqty = _parseDouble(row['allqty']) ?? 0;
    final saleqty = _parseDouble(row['saleqty']) ?? 0;
    final nosaleqty = _parseDouble(row['nosaleqty']) ?? 0;
    final throughprop = allqty > 0 ? (saleqty / allqty * 100) : 0.0;

    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    const blueStyle = TextStyle(fontSize: 13, color: Color(0xFF006EFF));

    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        DataCell(Center(child: Text('${index + 1}', style: cellStyle))),
        DataCell(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(row['storename']?.toString() ?? '--', style: cellStyle),
        )),
        DataCell(GestureDetector(
          onTap: () => _openNumMovingItem(row, true),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtQty(saleqty), style: blueStyle),
            ),
          ),
        )),
        DataCell(GestureDetector(
          onTap: () => _openNumMovingItem(row, false),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_fmtQty(nosaleqty), style: blueStyle),
            ),
          ),
        )),
        DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_fmtQty(allqty), style: cellStyle),
          ),
        )),
        DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text('${_fmtQty(throughprop)}%', style: cellStyle),
          ),
        )),
      ],
    );
  }

  Widget _buildMdSummaryRow() {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    final allqty = _mdSum['allqty'] ?? 0;
    final saleqty = _mdSum['saleqty'] ?? 0;
    final nosaleqty = _mdSum['nosaleqty'] ?? 0;
    final throughprop = allqty > 0 ? (saleqty / allqty * 100) : 0.0;

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        border: Border(top: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      child: Row(
        children: [
          // 冻结列：序号(40) + 机构名称(120)
          const SizedBox(
            width: 160,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('合计', style: boldStyle),
            ),
          ),
          // 可滚动数据列：4 × 100
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              controller: _mdSummaryHCtrl,
              child: SizedBox(
                width: 400,
                child: Row(
                  children: [
                    _mdSumCell(saleqty, boldStyle),
                    _mdSumCell(nosaleqty, boldStyle),
                    _mdSumCell(allqty, boldStyle),
                    _mdSumCell(throughprop, boldStyle, suffix: '%'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mdSumCell(double value, TextStyle style, {String suffix = ''}) {
    return SizedBox(
      width: 100,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text('${_fmtQty(value)}$suffix', style: style),
        ),
      ),
    );
  }

  // ==================== Tab 1: 商品类别动销率 ====================

  List<DataColumn2> _buildLbColumns() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));

    final cols = <DataColumn2>[
      const DataColumn2(
        fixedWidth: 40,
        label: Padding(
          padding: EdgeInsets.only(left: 5, right: 4),
          child: Text('序号', style: headerStyle),
        ),
      ),
    ];

    // 动态级别列
    if (_level == '1' || int.tryParse(_level) == null) {
      cols.add(const DataColumn2(
        fixedWidth: 100,
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('一级类别', style: headerStyle),
        ),
      ));
    }
    if (_level == '2' || int.tryParse(_level) == null) {
      cols.add(const DataColumn2(
        fixedWidth: 100,
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('二级类别', style: headerStyle),
        ),
      ));
    }
    if (_level == '3' || int.tryParse(_level) == null) {
      cols.add(const DataColumn2(
        fixedWidth: 100,
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('三级类别', style: headerStyle),
        ),
      ));
    }

    cols.addAll(const [
      DataColumn2(
        numeric: true,
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('动销品项数', textAlign: TextAlign.right, style: headerStyle),
        ),
      ),
      DataColumn2(
        numeric: true,
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('未动销品项数', textAlign: TextAlign.right, style: headerStyle),
        ),
      ),
      DataColumn2(
        numeric: true,
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('品项总数', textAlign: TextAlign.right, style: headerStyle),
        ),
      ),
      DataColumn2(
        numeric: true,
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('动销率', textAlign: TextAlign.right, style: headerStyle),
        ),
      ),
    ]);
    return cols;
  }

  /// 类别列数（不含序号，含后面4个数字列）
  int get _lbCategoryCols {
    if (_level == '1') return 1;
    if (_level == '2') return 2;
    if (_level == '3') return 3;
    return 3;
  }

  Widget _buildLbTab() {
    if (_lbList.isEmpty && (!_lbLoading || _lbHasLoadedOnce)) {
      // 空态：加载完成无数据，或已加载过刷新中（保留空态+图标卡片，避免表格骨架闪屏）
      return Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: _onRefresh,
          child: ListView(children: [
            const SizedBox(height: 200),
            _emptyState(),
          ]),
        ),
        if (_lbLoading) _loadingCard,
      ]);
    }

    final columns = _buildLbColumns();
    final categoryCols = _lbCategoryCols;

    return Stack(children: [
      Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // 竖向滚动加载更多
                if (n is ScrollEndNotification &&
                    n.metrics.axis == Axis.vertical &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
                    _lbHasMore &&
                    !_lbLoading) {
                  _loadLbData();
                }
                // 横向滚动同步到合计行（DataTable2 水平滚动在嵌套深度 >=1 处）
                if (n is ScrollUpdateNotification && n.metrics.axis == Axis.horizontal) {
                  if (_lbSummaryHCtrl.hasClients) {
                    _lbSummaryHCtrl.jumpTo(n.metrics.pixels);
                  }
                }
                return false;
              },
              child: RefreshIndicator(
                color: const Color(0xFF006EFF),
                onRefresh: _onRefresh,
                child: DataTable2(
                  horizontalScrollController: _lbTableHCtrl,
                  fixedLeftColumns: categoryCols + 1,
                  minWidth: 40 + categoryCols * 100 + 400,
                  horizontalMargin: 0,
                  columnSpacing: 0,
                  dataRowHeight: 52,
                  headingRowHeight: 44,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
                    verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
                  ),
                  columns: columns,
                  rows: [
                    for (var i = 0; i < _lbList.length; i++) _buildLbRow(_lbList[i], i),
                    // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
                    if (_lbLoading && (_lbPage > 1 || !_lbHasLoadedOnce))
                      DataRow(cells: [
                        const DataCell(SizedBox(
                            height: 44,
                            child: Center(
                                child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Color(0xFF006EFF)))))),
                        for (int j = 1; j < columns.length; j++) DataCell.empty,
                      ]),
                  ],
                ),
              ),
            ),
          ),
          if (_lbSumData.isNotEmpty) _buildLbSummaryRow(),
        ],
      ),
      if (_lbLoading && _lbHasLoadedOnce && _lbPage == 1) _loadingCard,
    ]);
  }

  DataRow2 _buildLbRow(Map<String, dynamic> row, int index) {
    final isOdd = index.isOdd;
    final allqty = _parseDouble(row['allqty']) ?? 0;
    final saleqty = _parseDouble(row['saleqty']) ?? 0;
    final nosaleqty = _parseDouble(row['nosaleqty']) ?? 0;
    final throughprop = allqty > 0 ? (saleqty / allqty * 100) : 0.0;

    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    const blueStyle = TextStyle(fontSize: 13, color: Color(0xFF006EFF));

    final cells = <DataCell>[
      DataCell(Center(child: Text('${index + 1}', style: cellStyle))),
    ];

    // 动态类别列
    if (_level == '1' || int.tryParse(_level) == null) {
      cells.add(DataCell(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(row['typeid1']?.toString() ?? '--', style: cellStyle),
      )));
    }
    if (_level == '2' || int.tryParse(_level) == null) {
      cells.add(DataCell(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(row['typeid2']?.toString() ?? '--', style: cellStyle),
      )));
    }
    if (_level == '3' || int.tryParse(_level) == null) {
      cells.add(DataCell(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(row['typeid3']?.toString() ?? '--', style: cellStyle),
      )));
    }

    cells.addAll([
      DataCell(GestureDetector(
        onTap: () => _openNumMovingItem(row, true),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(_fmtQty(saleqty), style: blueStyle),
          ),
        ),
      )),
      DataCell(GestureDetector(
        onTap: () => _openNumMovingItem(row, false),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(_fmtQty(nosaleqty), style: blueStyle),
          ),
        ),
      )),
      DataCell(Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(_fmtQty(allqty), style: cellStyle),
        ),
      )),
      DataCell(Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text('${_fmtQty(throughprop)}%', style: cellStyle),
        ),
      )),
    ]);

    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: cells,
    );
  }

  Widget _buildLbSummaryRow() {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    final allqty = _parseDouble(_lbSumData['allqty']) ?? 0;
    final saleqty = _parseDouble(_lbSumData['saleqty']) ?? 0;
    final nosaleqty = _parseDouble(_lbSumData['nosaleqty']) ?? 0;
    final throughprop = allqty > 0 ? (saleqty / allqty * 100) : 0.0;
    final categoryCols = _lbCategoryCols;
    final frozenWidth = 40 + categoryCols * 100.0;

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        border: Border(top: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      child: Row(
        children: [
          // 冻结列：序号(40) + N个类别列(各100)
          SizedBox(
            width: frozenWidth,
            child: Row(
              children: [
                const SizedBox(
                  width: 40,
                  child: Text('合计', style: boldStyle, textAlign: TextAlign.center),
                ),
                for (int i = 0; i < categoryCols; i++) const SizedBox(width: 100),
              ],
            ),
          ),
          // 可滚动数据列：4 × 100
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              controller: _lbSummaryHCtrl,
              child: SizedBox(
                width: 400,
                child: Row(
                  children: [
                    _lbSumCell(saleqty, boldStyle),
                    _lbSumCell(nosaleqty, boldStyle),
                    _lbSumCell(allqty, boldStyle),
                    _lbSumCell(throughprop, boldStyle, suffix: '%'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lbSumCell(double value, TextStyle style, {String suffix = ''}) {
    return SizedBox(
      width: 100,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text('${_fmtQty(value)}$suffix', style: style),
        ),
      ),
    );
  }

  // ==================== 供应商选择器 ====================

  Future<void> _openSupplierSelector() async {
    final result = await SelectSupplierPage.show(context, initialSelectedId: _supid);
    if (result != null && mounted) {
      setState(() {
        _supid = result['supid']?.toString() ?? '';
        _supname = result['supname']?.toString() ?? '';
      });
      _resetAndLoad();
    }
  }

  // ==================== 筛选弹窗 ====================

  void _openFilterSheet() {
    String tmpSupid = _supid;
    String tmpSupname = _supname;
    String tmpBrandid = _brandid;
    String tmpBrandname = _brandname;
    List<String> tmpItemstatus = List.from(_itemstatus);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // 标题栏
                  SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        const SizedBox(width: 48),
                        const Expanded(
                          child: Text(
                            '筛选',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827)),
                          ),
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
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tab 1 才显示供应商
                          if (_tabIndex == 0) ...[
                            _buildFilterLabel('供应商'),
                            const SizedBox(height: 8),
                            _buildFilterSelectorRow(
                              label: tmpSupname.isNotEmpty ? tmpSupname : '全部供应商',
                              onTap: () {
                                _showSupplierPicker(ctx, setSheetState, (id, name) {
                                  setSheetState(() {
                                    tmpSupid = id;
                                    tmpSupname = name;
                                  });
                                });
                              },
                            ),
                            const SizedBox(height: 22),
                          ],
                          // 品牌
                          _buildFilterLabel('品牌'),
                          const SizedBox(height: 8),
                          _buildFilterSelectorRow(
                            label: tmpBrandname.isNotEmpty ? tmpBrandname : '全部品牌',
                            onTap: () {
                              _showBrandPicker(ctx, setSheetState, (id, name) {
                                setSheetState(() {
                                  tmpBrandid = id;
                                  tmpBrandname = name;
                                });
                              });
                            },
                          ),
                          const SizedBox(height: 22),
                          // 商品状态
                          _buildFilterLabel('商品状态'),
                          const SizedBox(height: 8),
                          _buildItemStatusChips(
                            selectedValues: tmpItemstatus,
                            onChanged: (v) => setSheetState(() => tmpItemstatus = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 底部按钮
                  Container(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(ctx).padding.bottom + 12,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setSheetState(() {
                                tmpSupid = '';
                                tmpSupname = '';
                                tmpBrandid = '';
                                tmpBrandname = '';
                                tmpItemstatus = [];
                              });
                            },
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFCCCCCC)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '重置',
                                style: TextStyle(fontSize: 15, color: Color(0xFF333333)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _supid = tmpSupid;
                                _supname = tmpSupname;
                                _brandid = tmpBrandid;
                                _brandname = tmpBrandname;
                                _itemstatus = tmpItemstatus;
                              });
                              Navigator.pop(ctx);
                              _resetAndLoad();
                            },
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF006EFF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '确定',
                                style: TextStyle(fontSize: 15, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildFilterLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
    );
  }

  Future<void> _showSupplierPicker(
    BuildContext parentCtx,
    StateSetter setSheetState,
    void Function(String id, String name) onSelected,
  ) async {
    final result = await SelectSupplierPage.show(parentCtx, initialSelectedId: _supid);
    if (result != null) {
      onSelected(
        result['supid']?.toString() ?? '',
        result['supname']?.toString() ?? '',
      );
    }
  }

  void _showBrandPicker(
    BuildContext parentCtx,
    StateSetter setSheetState,
    void Function(String id, String name) onSelected,
  ) {
    showModalBottomSheet<void>(
      context: parentCtx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SelectorSheet(
          title: '选择品牌',
          apiPath: HttpApi.brandList,
          nameKey: 'name',
          idKey: 'id',
          onSelected: (id, name) {
            onSelected(id, name);
            Navigator.pop(ctx);
          },
        );
      },
    );
  }

  // ==================== 筛选弹窗辅助组件 ====================

  static Widget _buildFilterSelectorRow({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemStatusChips({
    required List<String> selectedValues,
    required void Function(List<String>) onChanged,
  }) {
    const statuses = [
      {'label': '全部', 'value': ''},
      {'label': '正常', 'value': '1'},
      {'label': '新品', 'value': '2'},
      {'label': '冻结', 'value': '3'},
      {'label': '停购', 'value': '4'},
      {'label': '停用', 'value': '5'},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: statuses.map((s) {
        final val = s['value']!;
        final label = s['label']!;
        final selected = val.isEmpty ? selectedValues.isEmpty : selectedValues.contains(val);
        return GestureDetector(
          onTap: () {
            final newList = List<String>.from(selectedValues);
            if (val.isEmpty) {
              onChanged([]);
            } else if (selected) {
              newList.remove(val);
              onChanged(newList);
            } else {
              newList.add(val);
              onChanged(newList);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF006EFF) : Colors.white,
              border: Border.all(
                color: selected ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : const Color(0xFF333333),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ==================== 空状态 ====================

  Widget _emptyState() {
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
}

// ==================== 通用选择器底部弹窗 ====================

class _SelectorSheet extends StatefulWidget {
  const _SelectorSheet({
    required this.title,
    required this.apiPath,
    required this.nameKey,
    required this.idKey,
    this.codeKey,
    this.params,
    required this.onSelected,
  });

  final String title;
  final String apiPath;
  final String nameKey;
  final String idKey;
  final String? codeKey;
  final Map<String, dynamic>? params;
  final void Function(String id, String name) onSelected;

  @override
  State<_SelectorSheet> createState() => _SelectorSheetState();
}

class _SelectorSheetState extends State<_SelectorSheet> {
  List<Map<String, dynamic>> _list = [];
  List<Map<String, dynamic>> _filteredList = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final params = <String, dynamic>{
      'is_page': 1,
      'pagesize': 999,
      if (widget.params != null) ...widget.params!,
    };
    try {
      final result = await request(widget.apiPath, params);
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?) ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _list = rows;
          _filteredList = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String v) {
    setState(() {
      if (v.isEmpty) {
        _filteredList = _list;
      } else {
        _filteredList = _list.where((item) {
          final name = (item[widget.nameKey] ?? '').toString();
          final code = widget.codeKey != null ? (item[widget.codeKey!] ?? '').toString() : '';
          return name.contains(v) || code.contains(v);
        }).toList();
      }
    });
  }

  String _displayName(Map<String, dynamic> item) {
    final name = (item[widget.nameKey] ?? '').toString();
    final code = widget.codeKey != null ? (item[widget.codeKey!] ?? '').toString() : '';
    if (code.isNotEmpty) return '[$code]$name';
    return name;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 标题栏
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '输入名称/编码',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 10, right: 6),
                  child: Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                ),
                prefixIconConstraints: const BoxConstraints(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF006EFF)),
                ),
              ),
            ),
          ),
          // 全部选项
          GestureDetector(
            onTap: () {
              widget.onSelected('', '');
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      '全部',
                      style: TextStyle(fontSize: 14, color: Color(0xFF006EFF)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
                : _filteredList.isEmpty
                    ? const Center(
                        child: Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF))),
                      )
                    : ListView.builder(
                        itemCount: _filteredList.length,
                        itemExtent: 48,
                        cacheExtent: 800,
                        itemBuilder: (ctx, i) {
                          final item = _filteredList[i];
                          final id = (item[widget.idKey] ?? '').toString();
                          final display = _displayName(item);
                          return RepaintBoundary(
                            child: GestureDetector(
                              onTap: () {
                                widget.onSelected(id, display);
                                Navigator.pop(context);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.centerLeft,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Color(0xFFF0F0F0)),
                                  ),
                                ),
                                child: Text(
                                  display,
                                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
