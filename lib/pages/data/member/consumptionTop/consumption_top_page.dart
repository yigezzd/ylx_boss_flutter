import 'dart:async';
import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 消费排行
/// 参考 D:\VUE\ylx-boss\src\subs\data\member\consumptionTop\consumptionTop.vue
class ConsumptionTopPage extends StatefulWidget {
  const ConsumptionTopPage({super.key});
  @override
  State<ConsumptionTopPage> createState() => _ConsumptionTopPageState();
}

class _ConsumptionTopPageState extends State<ConsumptionTopPage> {
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

  // ── 排序（默认按销售金额降序）──
  String _sortField = 'rramt';
  String _sortType = 'desc';

  // ── 汇总 ──
  Map<String, dynamic> _sumData = {};

  // ── 筛选参数 ──
  String _cond = '';
  String _typeid = '';
  String _typename = '';
  String _labelname = '';
  List<String> _labelcodes = [];

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
      final s = SpUtil.getString('store') ?? '';
      if (s.isNotEmpty) {
        final m = jsonDecode(s);
        final id = m['id']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _storeName = m['name']?.toString() ?? '';
            _activeStoreId = id;
            _sids = id.isNotEmpty ? [int.tryParse(id) ?? 0] : [];
          });
          _loadData();
        }
      }
    } catch (_) {}
  }

  Future<void> _selectStore() async {
    final r = await SelectStorePage.show(context, showAll: true, initialSelectedId: _activeStoreId);
    if (r != null && mounted) {
      setState(() {
        final storeId = r['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
        _storeName = r['storename']?.toString() ?? '';
        _page = 1;
        _hasMore = true;
        if (!_hasLoadedOnce) _list = [];
      });
      _loadData();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _formatDecimal(int digits, dynamic v) {
    final num n = v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
    return n.toStringAsFixed(digits);
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final r = await request(HttpApi.vipSaleRankingList, {
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': _sids,
        'sidsname': _storeName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        if (_sortField.isNotEmpty) 'field': _sortField,
        if (_sortType.isNotEmpty) 'type': _sortType,
        if (_cond.isNotEmpty) 'cond': _cond,
        if (_typeid.isNotEmpty) 'typeid': _typeid,
        if (_labelcodes.isNotEmpty) 'labelcodes': _labelcodes,
      });
      final data = r['data'];
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
          _hasLoadedOnce = true;
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

  void _onSort(String f, String t) {
    setState(() {
      _sortField = f;
      _sortType = t;
    });
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  // ==================== 时间选择器（参考 cash_flow_page） ====================

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
                        style: TextStyle(
                            fontSize: 13,
                            color: selected ? Colors.white : const Color(0xFF333333))),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 10),
        _buildDateNavigation(),
      ]),
    );
  }

  void _onQuickTimeSelect(int id) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (id) {
      case 0:
        start = now.subtract(const Duration(days: 1));
        end = start;
      case 1:
        start = now;
        end = now;
      case 2:
        final weekday = now.weekday;
        start = now.subtract(Duration(days: weekday - 1));
        end = start.add(const Duration(days: 6));
      case 3:
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
      default:
        start = _startDate;
        end = _endDate;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _activeQuickTimeId = id;
      _page = 1;
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
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(Icons.chevron_left,
                size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      if (showArrows) const SizedBox(width: 8),
      Expanded(
        child: Row(children: [
          if (isRange) ...[
            Expanded(child: _buildDatePart(_startDate, isStart: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('至', style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
            ),
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
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(Icons.chevron_right,
                size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
    ]);
  }

  Widget _buildDatePart(DateTime date,
      {bool isStart = false, bool isEnd = false, bool isMonth = false}) {
    final String label =
        isMonth ? '${date.year}-${date.month.toString().padLeft(2, '0')}' : _fmtDate(date);
    Future<void> onTap() async {
      if (isMonth) {
        final picked = await showCommonMonthPicker(context, initial: date);
        if (picked != null && mounted) {
          setState(() {
            _startDate = DateTime(picked.year, picked.month);
            _endDate = DateTime(picked.year, picked.month + 1, 0);
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
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
      ),
    );
  }

  void _timeShift(int direction) {
    final id = _activeQuickTimeId ?? 1;
    final originalStart = _startDate;
    DateTime start, end;
    switch (id) {
      case 0:
      case 1:
        start = originalStart.add(Duration(days: direction));
        end = start;
      case 2:
        start = originalStart.add(Duration(days: 7 * direction));
        end = start.add(const Duration(days: 6));
      case 3:
        start = DateTime(originalStart.year, originalStart.month + direction);
        end = DateTime(start.year, start.month + 1, 0);
      default:
        return;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    _loadData();
  }

  // ==================== 筛选弹窗 ====================

  void _openFilterSheet() {
    String tmpCond = _cond;
    String tmpTypeid = _typeid;
    String tmpTypename = _typename;
    String tmpLabelname = _labelname;
    List<String> tmpLabelcodes = List.from(_labelcodes);

    final condCtrl = TextEditingController(text: _cond);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.72,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(children: [
              SizedBox(
                height: 50,
                child: Row(children: [
                  const SizedBox(width: 48),
                  const Expanded(
                    child: Text('筛选',
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
                ]),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // 搜索
                    TextField(
                      controller: condCtrl,
                      onChanged: (v) => tmpCond = v,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '请输入会员卡号/名称/手机号码',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 10, right: 6),
                          child: Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                        ),
                        prefixIconConstraints: const BoxConstraints(),
                        suffixIcon: tmpCond.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  condCtrl.clear();
                                  setSheetState(() => tmpCond = '');
                                },
                                child: const Icon(Icons.clear, size: 18, color: Color(0xFF999999)),
                              )
                            : null,
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                            borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                            borderSide: const BorderSide(color: Color(0xFF006EFF))),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // 会员分类
                    _buildFilterLabel('会员分类'),
                    const SizedBox(height: 8),
                    _buildFilterSelectorRow(
                      label: tmpTypename.isNotEmpty ? tmpTypename : '全部',
                      onTap: () async {
                        final result = await CommonSelectSheet.show(
                          ctx,
                          title: '选择会员分类',
                          searchHint: '输入会员分类名称/编码',
                          fetchData: (search, page) async {
                            final r = await request('vipType/getVipTypeList', {
                              'is_page': 1,
                              'page': page,
                              'pagesize': 50,
                              'sids': _sids,
                              if (search.isNotEmpty) 'cond': search,
                            });
                            final data = r['data'];
                            return data is Map<String, dynamic> ? data : null;
                          },
                          idField: 'typeid',
                          showAll: true,
                          initialSelectedId: tmpTypeid,
                          mapResult: (item) {
                            final code = item['code']?.toString() ?? '';
                            final name = item['name']?.toString() ?? '';
                            return {
                              'typeid': item['typeid']?.toString() ?? '',
                              'name': code.isNotEmpty ? '[$code]$name' : name,
                            };
                          },
                        );
                        if (result != null) {
                          setSheetState(() {
                            tmpTypeid = result['typeid']?.toString() ?? '';
                            tmpTypename = result['name']?.toString() ?? '';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 22),
                    // 会员标签
                    _buildFilterLabel('会员标签'),
                    const SizedBox(height: 8),
                    _buildFilterSelectorRow(
                      label: tmpLabelname.isNotEmpty ? tmpLabelname : '全部标签',
                      onTap: () =>
                          _showLabelPicker(ctx, setSheetState, tmpLabelcodes, (codes, name) {
                        setSheetState(() {
                          tmpLabelcodes = codes;
                          tmpLabelname = name;
                        });
                      }),
                    ),
                  ]),
                ),
              ),
              // 底部按钮
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setSheetState(() {
                          tmpCond = '';
                          tmpTypeid = '';
                          tmpTypename = '';
                          tmpLabelname = '';
                          tmpLabelcodes = [];
                          condCtrl.clear();
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF333333),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                      ),
                      child: const Text('重置', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _cond = tmpCond;
                          _typeid = tmpTypeid;
                          _typename = tmpTypename;
                          _labelname = tmpLabelname;
                          _labelcodes = tmpLabelcodes;
                          _page = 1;
                          _hasMore = true;
                        });
                        _loadData();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006EFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                      ),
                      child: const Text('确定', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        });
      },
    );
  }

  Future<void> _showLabelPicker(BuildContext parentCtx, StateSetter setSheetState,
      List<String> currentCodes, void Function(List<String> codes, String name) onSelected) async {
    try {
      final r = await request('labelSet/getLabelSetList', {'is_page': 0, 'type': -1});
      final data = r['data'];
      final list = (r['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: parentCtx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final selected = List<String>.from(currentCodes);
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.65,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: StatefulBuilder(builder: (ctx, setState2) {
              return Column(children: [
                SizedBox(
                  height: 50,
                  child: Row(children: [
                    const SizedBox(width: 48),
                    const Expanded(
                      child: Text('选择会员标签',
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
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(children: [
                    // 全部标签
                    InkWell(
                      onTap: () {
                        if (selected.isEmpty) {
                          // 已经是全部 => 取消
                          Navigator.pop(ctx);
                        } else {
                          setState2(() => selected.clear());
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          _buildCheckbox(selected.isEmpty),
                          const SizedBox(width: 12),
                          Text('全部标签',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: selected.isEmpty
                                      ? const Color(0xFF006EFF)
                                      : const Color(0xFF333333))),
                        ]),
                      ),
                    ),
                    for (final item in list)
                      InkWell(
                        onTap: () {
                          final code = item['code']?.toString() ?? '';
                          setState2(() {
                            selected.remove(''); // 去掉"全部"空字符串
                            if (selected.contains(code)) {
                              selected.remove(code);
                            } else {
                              selected.add(code);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(children: [
                            _buildCheckbox(selected.contains(item['code']?.toString() ?? '')),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(item['name']?.toString() ?? '',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: selected.contains(item['code']?.toString() ?? '')
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFF333333))),
                            ),
                          ]),
                        ),
                      ),
                  ]),
                ),
                // 底部按钮
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF333333),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        child: const Text('取消', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          final names = selected
                              .map((c) =>
                                  list
                                      .firstWhere((e) => (e['code']?.toString() ?? '') == c,
                                          orElse: () => {})['name']
                                      ?.toString() ??
                                  c)
                              .join('|');
                          onSelected(List.from(selected), selected.isEmpty ? '全部标签' : names);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF006EFF),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('确定', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                  ]),
                ),
              ]);
            }),
          );
        },
      );
    } catch (_) {}
  }

  Widget _buildCheckbox(bool checked) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
            color: checked ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB), width: 2),
        color: checked ? const Color(0xFF006EFF) : Colors.white,
      ),
      child: checked ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
    );
  }

  Widget _buildFilterLabel(String text) {
    return Text(text,
        style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)));
  }

  Widget _buildFilterSelectorRow({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('消费排行', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Column(children: [
        // 门店选择 + 筛选按钮
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 3),
          child: Row(children: [
            Expanded(
              child: _buildDropBtn(
                  label: _storeName.isNotEmpty ? _storeName : '全部机构', onTap: _selectStore),
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
                        borderRadius: BorderRadius.circular(5)),
                    child: const BossSvgIcon(
                        svgFile: 'fliter.svg', size: 22, color: Color(0xFF666666)))),
          ]),
        ),
        _buildTimeSelector(),
        // 表格
        Expanded(child: _buildTableContent()),
      ]),
    );
  }

  Widget _buildDropBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
        ]),
      ),
    );
  }

  Widget _buildTableContent() {
    if (_list.isEmpty && (!_loading || _hasLoadedOnce)) {
      // 空态：加载完成无数据，或已加载过刷新中（保留空态+图标卡片，避免表格骨架闪屏）
      return Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: _onRefresh,
          child: ListView(children: const [
            SizedBox(height: 200),
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                SizedBox(height: 12),
                Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
              ]),
            ),
          ]),
        ),
        if (_loading) _loadingCard,
      ]);
    }
    return Stack(children: [
      Column(children: [
        if (_sumData.isNotEmpty) _buildSummaryRow(),
        Expanded(child: _buildTable()),
      ]),
      if (_loading && _hasLoadedOnce && _page == 1) _loadingCard,
    ]);
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

  Widget _buildSummaryRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: RichText(
        text: TextSpan(style: const TextStyle(fontSize: 13, color: Color(0xFF666666)), children: [
          const TextSpan(text: '总消费次数：'),
          TextSpan(
              text: _formatDecimal(0, _sumData['billnum']),
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          const TextSpan(text: '   总消费金额：'),
          TextSpan(
              text: _formatDecimal(2, _sumData['rramt']),
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ]),
      ),
    );
  }

  Widget _buildTable() {
    const hs = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.axis == Axis.vertical &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
            _hasMore &&
            !_loading) {
          _loadData();
        }
        return false;
      },
      child: RefreshIndicator(
        color: const Color(0xFF006EFF),
        onRefresh: _onRefresh,
        child: DataTable2(
          horizontalMargin: 0,
          columnSpacing: 0,
          dataRowHeight: 52,
          headingRowHeight: 44,
          minWidth: 600,
          fixedLeftColumns: 2,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
          border: const TableBorder(
            horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
            verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
          ),
          columns: [
            const DataColumn2(
                fixedWidth: 40,
                label: Padding(
                    padding: EdgeInsets.only(left: 5, right: 4), child: Text('排行', style: hs))),
            const DataColumn2(
                fixedWidth: 140,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8), child: Text('卡号/姓名', style: hs))),
            const DataColumn2(
                size: ColumnSize.S,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8), child: Text('手机号', style: hs))),
            DataColumn2(
                numeric: true,
                size: ColumnSize.S,
                label: _sortHeader('消费次数', 'billnum'),
                onSort: (_, __) => _onSort(
                    'billnum', _sortField == 'billnum' && _sortType == 'asc' ? 'desc' : 'asc')),
            DataColumn2(
                numeric: true,
                size: ColumnSize.S,
                label: _sortHeader('销售金额', 'rramt'),
                onSort: (_, __) =>
                    _onSort('rramt', _sortField == 'rramt' && _sortType == 'asc' ? 'desc' : 'asc')),
          ],
          rows: [
            for (var i = 0; i < _list.length; i++) _buildRow(_list[i], i),
            // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
            if (_loading && (_page > 1 || !_hasLoadedOnce))
              DataRow(cells: [
                const DataCell(SizedBox(
                    height: 44,
                    child: Center(
                        child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF006EFF)))))),
                for (int j = 1; j < 5; j++) DataCell.empty,
              ]),
          ],
        ),
      ),
    );
  }

  DataRow2 _buildRow(Map<String, dynamic> row, int index) {
    const cs = TextStyle(fontSize: 13, color: Color(0xFF333333));
    const csSmall = TextStyle(fontSize: 11, color: Color(0xFF999999));
    return DataRow2(
      decoration: BoxDecoration(
        color: index.isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        DataCell(Center(child: Text('${index + 1}', style: cs))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row['vipno']?.toString() ?? '',
                      style: cs, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if ((row['vipname']?.toString() ?? '').isNotEmpty)
                    Text(row['vipname']!.toString(),
                        style: csSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['mobile']?.toString() ?? '', style: cs))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_formatDecimal(0, row['billnum']), style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_formatDecimal(2, row['rramt']), style: cs)))),
      ],
    );
  }

  Widget _sortHeader(String label, String field) {
    final isActive = _sortField == field;
    final isAsc = _sortType == 'asc';
    return GestureDetector(
      onTap: () {
        final t = isActive ? (isAsc ? 'desc' : 'asc') : 'desc';
        _onSort(field, t);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
              child: Text(label,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)))),
          const SizedBox(width: 6),
          Icon(isActive ? (isAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
              size: 14, color: isActive ? const Color(0xFF006EFF) : const Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }
}
