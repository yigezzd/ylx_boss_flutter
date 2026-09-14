import 'dart:convert';
import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 收银监控页面
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\cashierMonitoring\cashierMonitoring.vue
class CashierMonitoringPage extends StatefulWidget {
  const CashierMonitoringPage({super.key});

  @override
  State<CashierMonitoringPage> createState() => _CashierMonitoringPageState();
}

class _CashierMonitoringPageState extends State<CashierMonitoringPage> {
  // ── 门店 ──
  String _storeName = '';
  String _activeStoreId = '';
  List<int> _sids = [];
  bool _isZd = false; // 是否总店（决定是否显示区域选择）

  // ── 区域选择 ──
  List<Map<String, dynamic>> _areaTree = [];
  String _areaId = '0';
  String _areaName = '';

  /// 当前区域下所有机构 ID（选择区域后获取，用于 sids 传参）
  List<int> _areaStoreIds = [];

  // ── 日期 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  // ── 经营概况 ──
  bool _overviewLoading = true;

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免刷新时内容隐藏闪屏）
  bool _hasLoadedOnce = false;
  Map<String, dynamic> _business = {};
  List<Map<String, dynamic>> _businessList = [];

  // ── 支付方式 ──
  List<Map<String, dynamic>> _payList = [];
  bool _showPayAll = false;

  // ── 门店分析列表 ──
  bool _storeLoading = false;
  List<Map<String, dynamic>> _storeList = [];

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
        final spId = storeMap['spid']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _storeName = storeMap['name']?.toString() ?? '';
            _activeStoreId = storeId;
            _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
            _isZd = storeId == spId && storeId.isNotEmpty;
          });
          if (_isZd) _loadAreaList();
          _loadAll();
        }
      }
    } catch (_) {}
  }

  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _activeStoreId,
      areaid: _areaId != '0' ? _areaId : null,
    );
    if (result != null && mounted) {
      setState(() {
        _storeName = result['storename']?.toString() ?? '';
        _activeStoreId = result['storeid']?.toString() ?? '';
        _sids = _activeStoreId.isNotEmpty ? [int.tryParse(_activeStoreId) ?? 0] : [];
      });
      _loadAll();
    }
  }

  // ==================== 区域选择（对齐 list.dart 树形分类选择） ====================

  Future<void> _loadAreaList() async {
    try {
      final result =
          await request(HttpApi.areaGetSysAreaList, {'is_page': 0, 'field': 'code', 'type': 'asc'});
      final data = result['data']['children'];
      if (mounted) {
        setState(() {
          List<Map<String, dynamic>> rawList = [];
          if (data is List) {
            rawList = data.cast<Map<String, dynamic>>();
          } else if (data is Map<String, dynamic>) {
            rawList = [data];
          }
          _areaTree = [
            {
              'name': '全部区域',
              'label': '全部区域',
              'areaid': '0',
              'children': rawList,
            }
          ];
        });
      }
    } catch (_) {}
  }

  /// 根据区域 ID 获取该区域下所有机构 ID（用于 sids 传参）
  Future<void> _fetchAreaStoreIds(String areaId) async {
    if (areaId == '0') {
      _areaStoreIds = [];
      return;
    }
    try {
      final result = await request(HttpApi.storeGetList, {
        'areaid': areaId,
        'is_page': 0,
      });
      final data = result['data'];
      final list = (data is Map && data['list'] is List)
          ? (data['list'] as List).cast<Map<String, dynamic>>()
          : (data is List)
              ? data.cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[];
      final allIds = <int>[];
      for (final item in list) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id != null) allIds.add(id);
      }
      _areaStoreIds = allIds;
    } catch (_) {
      _areaStoreIds = [];
    }
  }

  /// 将树形数据展平为带深度的列表（对齐 list.dart _flattenPickerTree）
  List<_AreaPickerNode> _flattenAreaTree(List<Map<String, dynamic>> nodes, int depth) {
    final result = <_AreaPickerNode>[];
    for (final node in nodes) {
      result.add(_AreaPickerNode(node: node, depth: depth));
      final children = node['children'] as List? ?? [];
      if (children.isNotEmpty) {
        result.addAll(_flattenAreaTree(children.cast<Map<String, dynamic>>(), depth + 1));
      }
    }
    return result;
  }

  /// 区域选择弹窗（对齐 list.dart _showTreeClassPicker）
  void _showAreaPicker() {
    final Set<String> expandedIds = {};
    final treeData = _areaTree.isNotEmpty
        ? (_areaTree[0]['children'] as List?)?.cast<Map<String, dynamic>>() ?? []
        : <Map<String, dynamic>>[];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final flatNodes = _flattenAreaTree(treeData, 0);

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
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
                          child: Text(
                            '选择区域',
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
                  // 全部区域
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _areaId = '0';
                        _areaName = '全部区域';
                        _storeName = '';
                        _sids = [];
                        _activeStoreId = '';
                        _areaStoreIds = [];
                      });
                      Navigator.pop(ctx);
                      _loadAll();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: _areaId == '0' ? const Color(0xFFF0F7FF) : Colors.white,
                        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '全部区域',
                              style: TextStyle(
                                fontSize: 14,
                                color: _areaId == '0'
                                    ? const Color(0xFF006EFF)
                                    : const Color(0xFF333333),
                                fontWeight: _areaId == '0' ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          _buildRadio(_areaId == '0'),
                        ],
                      ),
                    ),
                  ),
                  // 树形区域列表
                  if (flatNodes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child:
                          Text('暂无区域数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        cacheExtent: 800,
                        shrinkWrap: true,
                        itemCount: flatNodes.length,
                        itemBuilder: (_, i) {
                          final data = flatNodes[i];
                          final node = data.node;
                          final id = node['areaid']?.toString() ?? '';
                          final name = node['name']?.toString() ?? '';
                          final code = node['code']?.toString() ?? '';
                          final children = node['children'] as List? ?? [];
                          final hasChildren = children.isNotEmpty;
                          final isExpanded = expandedIds.contains(id);
                          final selected = _areaId == id && id != '0';

                          return RepaintBoundary(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                final areaId = id;
                                debugPrint('[Area] onTap node: id=$id, areaId=$areaId, name=$name');
                                setState(() {
                                  _areaId = areaId;
                                  _areaName = code.isNotEmpty ? '[$code]$name' : name;
                                  _storeName = '';
                                  _activeStoreId = '';
                                  debugPrint('[Area] setState done: _areaId=$_areaId');
                                });
                                Navigator.pop(ctx);
                                // 获取该区域下所有机构 ID
                                await _fetchAreaStoreIds(areaId);
                                setState(() {
                                  _sids = List.from(_areaStoreIds);
                                });
                                _loadAll();
                              },
                              child: Container(
                                padding: EdgeInsets.only(
                                  left: 16.0 + data.depth * 28.0,
                                  right: 16,
                                  top: 12,
                                  bottom: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                                  border:
                                      const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                                ),
                                child: Row(
                                  children: [
                                    if (hasChildren)
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setSheetState(() {
                                            if (isExpanded) {
                                              expandedIds.remove(id);
                                            } else {
                                              expandedIds.add(id);
                                            }
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(
                                            isExpanded
                                                ? Icons.keyboard_arrow_down
                                                : Icons.chevron_right,
                                            size: 18,
                                            color: const Color(0xFF6B7280),
                                          ),
                                        ),
                                      )
                                    else
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: SizedBox(width: 18),
                                      ),
                                    Expanded(
                                      child: Text(
                                        code.isNotEmpty ? '[$code]$name' : name,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: selected
                                              ? const Color(0xFF006EFF)
                                              : const Color(0xFF333333),
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : (data.depth == 0
                                                  ? FontWeight.w500
                                                  : FontWeight.normal),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
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
      },
    );
  }

  /// 构建单选框（对齐 list.dart _buildRadio）
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

  Map<String, dynamic> _baseParams() {
    // 优先级：选了具体机构 > 选了区域 > 默认
    List<int> effectiveSids;
    if (_activeStoreId.isNotEmpty) {
      // 选了具体机构，用该机构 ID
      effectiveSids = _sids;
    } else if (_areaId != '0' && _areaStoreIds.isNotEmpty) {
      // 选了区域但未选具体机构，用区域下全部机构 ID
      effectiveSids = _areaStoreIds;
    } else {
      // 全部区域 / 未选择
      effectiveSids = _sids;
    }
    final params = {
      'daytype': 6,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'sids': effectiveSids,
      if (_areaId != '0') 'areaid': _areaId,
    };
    debugPrint(
        '[Area] _baseParams: _areaId=$_areaId, activeStore=$_activeStoreId, sids=$effectiveSids');
    return params;
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtAmt(dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(2);
  }

  // ==================== 数据加载 ====================

  Future<void> _loadAll() async {
    await Future.wait([
      _loadBusinessOverview(),
      _loadPaySum(),
      _loadStoreList(),
    ]);
    if (mounted) setState(() => _hasLoadedOnce = true);
  }

  Future<void> _loadBusinessOverview() async {
    setState(() => _overviewLoading = true);
    try {
      final result = await request(HttpApi.homeGetBusinessOverview, _baseParams());
      final data = result['data'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() {
          _business = data;
          _businessList = [
            {'text': '经营金额', 'amt': _fmtAmt(data['saleamt']), 'key': 'saleamt'},
            {'text': '收银金额', 'amt': _fmtAmt(data['rramt']), 'key': 'rramt'},
            {'text': '充值金额', 'amt': _fmtAmt(data['vipaddamt']), 'key': 'vipaddamt'},
            {'text': '售卡金额', 'amt': _fmtAmt(data['vipcardsaleamt']), 'key': 'vipcardsaleamt'},
            {'text': '退款金额', 'amt': _fmtAmt(data['returnamt']), 'key': 'returnamt'},
          ];
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _overviewLoading = false);
    }
  }

  Future<void> _loadPaySum() async {
    try {
      final params = _baseParams();
      params['daytype'] = 6;
      params['isorttype'] = 0; //按金额 按数量
      params['showopertype'] = 1;
      final result = await request(HttpApi.homeGetPaySum, params);
      final list = (result['data'] is List)
          ? (result['data'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _payList = List.from(list)
            ..sort((a, b) {
              final aVal = num.tryParse(a['payamt']?.toString() ?? '0') ?? 0;
              final bVal = num.tryParse(b['payamt']?.toString() ?? '0') ?? 0;
              return bVal.compareTo(aVal);
            });
          // 客户端自行计算比例，避免服务端四舍五入导致极小值显示为 0
          final total = _payList.fold<num>(
              0, (sum, item) => sum + (num.tryParse(item['payamt']?.toString() ?? '0') ?? 0));
          for (final item in _payList) {
            final amt = num.tryParse(item['payamt']?.toString() ?? '0') ?? 0;
            item['_proportion'] = total > 0 ? (amt / total * 100) : 0.0;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadStoreList() async {
    setState(() => _storeLoading = true);
    try {
      final params = _baseParams();
      params['is_page'] = 0;
      params['billtype'] = 1;
      final result = await request(HttpApi.summaryStoreStoreSale, params);
      final data = result['data'];
      final list = (data is Map && data['list'] is List)
          ? (data['list'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() => _storeList = list);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _storeLoading = false);
    }
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
    });
    _loadAll();
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
          });
          _loadAll();
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
        _loadAll();
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
    _loadAll();
  }

  // ==================== 经营概况 ====================

  Widget _buildBusinessOverview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('经营概况',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          const SizedBox(height: 12),
          if (_overviewLoading && !_hasLoadedOnce)
            const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
            ))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _businessList.length,
              itemBuilder: (ctx, i) {
                final item = _businessList[i];
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDEDEDE)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item['text'] as String,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                      const SizedBox(height: 4),
                      Text(item['amt'] as String,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ==================== 支付方式 ====================

  Widget _buildPayMethodSection() {
    if (_payList.isEmpty) return const SizedBox.shrink();
    final displayList = _payList.length > 4 && !_showPayAll ? _payList.take(4).toList() : _payList;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        children: [
          ...displayList.map((item) {
            final proportion = (item['_proportion'] as num?)?.toDouble() ?? 0.0;
            // 小值保留 1 位小数避免显示为 0%，进度条设最小值保证视觉可见
            final displayText = proportion > 0 && proportion < 1
                ? '${proportion.toStringAsFixed(1)}%'
                : '${proportion.toStringAsFixed(0)}%';
            final barValue = proportion > 0 && proportion < 0.5 ? 0.005 : proportion / 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item['payname']?.toString() ?? '--',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
                      Text('¥ ${_fmtAmt(item['payamt'])}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
                      Text(displayText,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: barValue,
                      minHeight: 12,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF49A4FF)),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_payList.length > 4)
            GestureDetector(
              onTap: () => setState(() => _showPayAll = !_showPayAll),
              child: Icon(
                _showPayAll ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 28,
                color: const Color(0xFF333333),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 会员分析 ====================

  Widget _buildMemberAnalysis() {
    final v = _business;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('会员分析',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildVipCard('新增数量', _fmtAmt(v['vipcardnum']))),
              const SizedBox(width: 10),
              Expanded(child: _buildVipCard('售卡金额', _fmtAmt(v['vipcardsaleamt']))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildVipCard('充值金额', _fmtAmt(v['vipaddamt']))),
              const SizedBox(width: 10),
              Expanded(child: _buildVipCard('赠送金额', _fmtAmt(v['vipgiveamt']))),
              const SizedBox(width: 10),
              Expanded(child: _buildVipCard('消费金额', _fmtAmt(v['vipasaleamt']))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVipCard(String label, String value) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDEDEDE)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ],
      ),
    );
  }

  // ==================== 门店分析表格（对齐 cash_flow_page 表格样式） ====================

  Widget _buildStoreTable() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text('门店分析',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          ),
          if (_storeLoading && !_hasLoadedOnce)
            const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
            ))
          else if (_storeList.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Column(children: [
                  Icon(Icons.inbox_outlined, size: 40, color: Color(0xFFD1D5DB)),
                  SizedBox(height: 8),
                  Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                ]),
              ),
            )
          else
            SizedBox(
              height: math.min(44.0 + 57.0 * (_storeList.length + 1), 400.0),
              child: RefreshIndicator(
                color: const Color(0xFF006EFF),
                onRefresh: _loadStoreList,
                child: DataTable2(
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
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('门店', style: headerStyle),
                      ),
                    ),
                    DataColumn2(
                      numeric: true,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('销售金额', textAlign: TextAlign.right, style: headerStyle),
                      ),
                    ),
                    DataColumn2(
                      numeric: true,
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('销售毛利', textAlign: TextAlign.right, style: headerStyle),
                      ),
                    ),
                  ],
                  rows: _storeList
                      .asMap()
                      .entries
                      .map((e) => _buildStoreRow(e.value, e.key))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  DataRow2 _buildStoreRow(Map<String, dynamic> row, int index) {
    final isOdd = index.isOdd;
    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        DataCell(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(row['storename']?.toString() ?? '--',
              style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
        )),
        DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_fmtAmt(row['rramt'] ?? 0),
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
        )),
        DataCell(Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_fmtAmt(row['grossamt'] ?? 0),
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
        )),
      ],
    );
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('销售监控', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: _loadAll,
          child: ListView(
            children: [
              // 区域 + 门店选择（总店时显示区域选择）
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    if (_isZd) ...[
                      Expanded(
                        child: GestureDetector(
                          onTap: _showAreaPicker,
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).dividerColor),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _areaName.isNotEmpty ? _areaName : '全部区域',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: GestureDetector(
                        onTap: _selectStore,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _storeName.isNotEmpty ? _storeName : '全部机构',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                ),
                              ),
                              if (_isZd)
                                Icon(Icons.arrow_drop_down,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 时间选择器
              _buildTimeSelector(),
              // 经营概况
              _buildBusinessOverview(),
              // 支付方式
              _buildPayMethodSection(),
              // 会员分析
              _buildMemberAnalysis(),
              // 门店分析表格
              _buildStoreTable(),
              const SizedBox(height: 20),
            ],
          ),
        ),
        // 刷新时仅居中图标卡片，内容保持可见（避免各区块闪屏）
        if ((_overviewLoading || _storeLoading) && _hasLoadedOnce) _loadingCard,
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
}

class _AreaPickerNode {
  _AreaPickerNode({required this.node, required this.depth});
  final Map<String, dynamic> node;
  final int depth;
}
