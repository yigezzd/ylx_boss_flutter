import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart' as classify;
import 'package:flutter_deer/pages/data/businessReport/abcAnalysis/abc_table_widget.dart';
import 'package:flutter_deer/pages/data/businessReport/abcAnalysis/prop_input_widget.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 类别ABC分析页面
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\typeABC\typeABC.vue
class TypeAbcPage extends StatefulWidget {
  const TypeAbcPage({super.key});

  @override
  State<TypeAbcPage> createState() => _TypeAbcPageState();
}

class _TypeAbcPageState extends State<TypeAbcPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  // ── 门店 ──
  String _storeName = '';
  String _activeStoreId = '';
  List<int> _sids = [];

  // ── 分类 ──
  List<Map<String, dynamic>> _typeList = [];

  // ── 分类级别 ──
  String _level = '';

  // ── 日期 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  // ── ABC 占比 ──
  int _aprop = 70;
  int _bprop = 20;
  int _cprop = 10;

  // ── 筛选参数（弹窗内） ──
  int _storeflag = 1;
  String _supid = '';
  String _supname = '';
  String _brandid = '';
  String _brandname = '';
  List<String> _itemstatus = [];

  // ── 数据 ──
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  List<Map<String, dynamic>> _list = [];
  Map<String, dynamic> _sumData = {};
  String _sortField = 'rramt';
  String _sortType = 'desc';

  static const _tabApis = [
    HttpApi.productabcGetTypeAmtABC,
    HttpApi.productabcGetTypeQtyABC,
    HttpApi.productabcGetTypeGrossABC,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
        _onTabChanged();
      }
    });
    final now = DateTime.now();
    _endDate = now;
    _startDate = now; // 默认当天
    _activeQuickTimeId = 1; // 默认今日
    _loadStore();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ==================== 门店 ====================

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

  // ==================== 分类 ====================

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

  // ==================== 分类级别 ====================

  String get _levelLabel {
    switch (_level) {
      case '1':
        return '一级分类';
      case '2':
        return '二级分类';
      case '3':
        return '三级分类';
      case '4':
        return '四级分类';
      default:
        return '全部级别';
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
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                ...['', '1', '2', '3', '4'].map((v) {
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
                              v.isEmpty
                                  ? '全部级别'
                                  : '${v == '1' ? '一' : v == '2' ? '二' : v == '3' ? '三' : '四'}级分类',
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

  // ==================== 日期 ====================

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ==================== 基础参数 ====================

  Map<String, dynamic> _baseParams() => {
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'sids': _sids,
        'typeid': _typeList
            .map((e) => e['typeid']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
        if (_level.isNotEmpty) 'level': _level,
        if (_supid.isNotEmpty) 'supid': _supid,
        if (_brandname.isNotEmpty) 'brandname': _brandname.replaceAll('|', ','),
        if (_itemstatus.isNotEmpty) 'itemstatusin': _itemstatus.join(','),
        'aprop': _aprop,
        'bprop': _bprop,
        'cprop': _cprop,
        'storeflag': _storeflag,
        'field': _sortField,
        'type': _sortType,
      };

  void _resetAndLoad() {
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  // 各 tab 默认排序字段：销售金额ABC→销售金额，销售数量ABC→销售数量，毛利ABC→毛利额
  static const _tabSortFields = ['rramt', 'qty', 'grossamt'];

  void _onTabChanged() {
    // 切 tab 时按 tab 类型切换默认排序（降序）
    setState(() {
      _sortField = _tabSortFields[_tabIndex];
      _sortType = 'desc';
    });
    _resetAndLoad();
  }

  // ==================== 数据加载 ====================

  Future<void> _loadData() async {
    if (_loading) return;
    if (_aprop + _bprop + _cprop != 100) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A类、B类、C类占比之和必须等于100%')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await request(_tabApis[_tabIndex], {
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        ..._baseParams(),
      });
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      final sumdata = map['sumdata'];

      if (mounted) {
        setState(() {
          if (_page == 1) {
            _list = list;
          } else {
            _list.addAll(list);
          }
          _hasMore = list.length >= 20;
          if (_hasMore) _page++;
          if (sumdata is Map<String, dynamic>) {
            _sumData = sumdata;
          } else {
            _sumData = {};
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _onSort(String field, String type) {
    setState(() {
      _sortField = field;
      _sortType = type;
    });
    _resetAndLoad();
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('类别ABC分析', style: TextStyle(fontSize: 17)),
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
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

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
          Tab(text: '销售金额ABC'),
          Tab(text: '销售数量ABC'),
          Tab(text: '毛利ABC'),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
      child: Row(
        children: [
          Expanded(
            child: _buildDropBtn(
              label: _storeName.isNotEmpty ? _storeName : '全部机构',
              onTap: _selectStore,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildDropBtn(
              label: _categoryLabel,
              onTap: _selectCategory,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildDropBtn(
              label: _levelLabel,
              onTap: _showLevelPicker,
            ),
          ),
          const SizedBox(width: 8),
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
                maxLines: 1,
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
    final showArrows = _activeQuickTimeId != 4;
    final isRange = _activeQuickTimeId == 2 || _activeQuickTimeId == 4;
    final isMonth = _activeQuickTimeId == 3;
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

  // ==================== Tab 内容 ====================

  Widget _buildTabContent() {
    return AbcTableWidget(
      mode: AbcTableMode.type,
      dataList: _list,
      sumData: _sumData,
      isLoading: _loading,
      isRefreshLoading: _loading && _page == 1,
      hasMore: _hasMore,
      onLoadMore: () {
        _loadData();
      },
      onRefresh: _onRefresh,
      onSort: _onSort,
      sortField: _sortField,
      sortType: _sortType,
    );
  }

  // ==================== 筛选弹窗 ====================

  void _openFilterSheet() {
    int tmpStoreflag = _storeflag;
    int tmpAprop = _aprop;
    int tmpBprop = _bprop;
    int tmpCprop = _cprop;
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
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
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
                          // 机构独立汇总显示
                          Row(
                            children: [
                              const Expanded(
                                child: Text('机构独立汇总显示',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF111827))),
                              ),
                              Switch(
                                value: tmpStoreflag == 1,
                                activeColor: const Color(0xFF006EFF),
                                onChanged: (v) {
                                  setSheetState(() => tmpStoreflag = v ? 1 : 0);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          PropInputWidget(
                            label: 'A类占比',
                            value: tmpAprop,
                            onChanged: (v) => setSheetState(() => tmpAprop = v),
                          ),
                          const SizedBox(height: 16),
                          PropInputWidget(
                            label: 'B类占比',
                            value: tmpBprop,
                            onChanged: (v) => setSheetState(() => tmpBprop = v),
                          ),
                          const SizedBox(height: 16),
                          PropInputWidget(
                            label: 'C类占比',
                            value: tmpCprop,
                            onChanged: (v) => setSheetState(() => tmpCprop = v),
                          ),
                          const SizedBox(height: 22),
                          // 供应商
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
                                tmpStoreflag = 1;
                                tmpAprop = 70;
                                tmpBprop = 20;
                                tmpCprop = 10;
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
                              child: const Text('重置',
                                  style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (tmpAprop + tmpBprop + tmpCprop != 100) {
                                await showDialog<void>(
                                  context: ctx,
                                  builder: (_) => AlertDialog(
                                    title: const Text('提示', style: TextStyle(fontSize: 16)),
                                    content: Text(
                                        'A类、B类、C类占比之和必须等于100%，当前合计为 ${tmpAprop + tmpBprop + tmpCprop}%'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('知道了'),
                                      ),
                                    ],
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _storeflag = tmpStoreflag;
                                _aprop = tmpAprop;
                                _bprop = tmpBprop;
                                _cprop = tmpCprop;
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
                              child: const Text('确定',
                                  style: TextStyle(fontSize: 15, color: Colors.white)),
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
    return Text(text,
        style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)));
  }

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
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
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
                    child: Text('全部', style: TextStyle(fontSize: 14, color: Color(0xFF006EFF))),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
                : _filteredList.isEmpty
                    ? const Center(child: Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF))))
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
                                  border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
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
