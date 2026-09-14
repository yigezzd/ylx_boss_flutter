import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 盘点计划选择页
/// 与 boss 项目 `subs/business/inventory/inventoryPlan/search` 对齐：
/// 支持按单号搜索、昨天/今日/本周/本月/自定义日期筛选，返回选中计划的 getInfo 完整数据。
class SelectInventoryPlanPage extends StatefulWidget {
  final String? bsid;

  const SelectInventoryPlanPage({super.key, this.bsid});

  @override
  State<SelectInventoryPlanPage> createState() =>
      _SelectInventoryPlanPageState();
}

class _SelectInventoryPlanPageState extends State<SelectInventoryPlanPage> {
  static const List<String> _timeTabs = ['昨天', '今日', '本周', '本月', '自定义'];
  static const int _primaryColorValue = 0xFF006EFF;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  int _timeIndex = 4; // 默认自定义，与 boss 端选择盘点计划一致
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _applyTimeTab(4);
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _formatMonth(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  void _applyTimeTab(int index) {
    final now = DateTime.now();
    switch (index) {
      case 0: // 昨天
        final y = now.subtract(const Duration(days: 1));
        _startDate = y;
        _endDate = y;
        break;
      case 1: // 今日
        _startDate = now;
        _endDate = now;
        break;
      case 2: // 本周（周一到周日）
        final dayOfWeek = now.weekday; // 1=周一 ... 7=周日
        _startDate = now.subtract(Duration(days: dayOfWeek - 1));
        _endDate = now.add(Duration(days: 7 - dayOfWeek));
        break;
      case 3: // 本月
        _startDate = DateTime(now.year, now.month);
        _endDate = DateTime(now.year, now.month + 1, 0);
        break;
      case 4: // 自定义
        _startDate = now;
        _endDate = now;
        break;
    }
    _timeIndex = index;
  }

  void _onTimeTabChanged(int index) {
    if (index == _timeIndex) {
      return;
    }
    setState(() {
      _applyTimeTab(index);
      _page = 1;
      _hasMore = true;
      _list = [];
    });
    _loadData();
  }

  void _shiftDate(int direction) {
    // direction: -1 左移，1 右移
    setState(() {
      switch (_timeIndex) {
        case 0:
        case 1:
          final d = _startDate.add(Duration(days: direction));
          _startDate = d;
          _endDate = d;
          break;
        case 2:
          _startDate = _startDate.add(Duration(days: 7 * direction));
          _endDate = _endDate.add(Duration(days: 7 * direction));
          break;
        case 3:
          final newMonth = DateTime(_startDate.year, _startDate.month + direction);
          _startDate = newMonth;
          _endDate = DateTime(newMonth.year, newMonth.month + 1, 0);
          break;
        case 4:
          // 自定义模式下左右箭头不处理
          break;
      }
    });
    _onRefresh();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    DateTime tempDate = initial;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (c) {
        return SizedBox(
          height: 300,
          child: Column(children: [
            SizedBox(
              height: 50,
              child: Row(children: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('取消',
                      style: TextStyle(color: Color(0xFF6B7280))),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(c, tempDate),
                  child: const Text('确定',
                      style: TextStyle(color: Color(_primaryColorValue))),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                        initialItem: tempDate.year - 2020),
                    itemExtent: 36,
                    onSelectedItemChanged: (i) {
                      tempDate = DateTime(2020 + i, tempDate.month,
                          tempDate.day);
                    },
                    children: List.generate(
                        20,
                        (i) => Center(
                            child: Text('${2020 + i}年',
                                style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF333333))))),
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                        initialItem: tempDate.month - 1),
                    itemExtent: 36,
                    onSelectedItemChanged: (i) {
                      tempDate = DateTime(tempDate.year, i + 1, tempDate.day);
                    },
                    children: List.generate(
                        12,
                        (i) => Center(
                            child: Text('${i + 1}月',
                                style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF333333))))),
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                        initialItem: tempDate.day - 1),
                    itemExtent: 36,
                    onSelectedItemChanged: (i) {
                      tempDate = DateTime(tempDate.year, tempDate.month, i + 1);
                    },
                    children: List.generate(
                        31,
                        (i) => Center(
                            child: Text('${i + 1}日',
                                style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF333333))))),
                  ),
                ),
              ]),
            ),
          ]),
        );
      },
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_timeIndex == 4 && _endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked;
        if (_timeIndex == 4 && _startDate.isAfter(_endDate)) {
          _startDate = _endDate;
        }
      }
    });
    _onRefresh();
  }

  Future<void> _loadData() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);

    final params = <String, dynamic>{
      'is_page': 1,
      'field': 'createtime',
      'type': 'desc',
      'billno': _searchController.text.trim(),
      'page': _page,
      'pagesize': 20,
      'signflag': '0',
      'checkyw': 1,
      'starttime': '${_formatDate(_startDate)} 00:00:00',
      'endtime': '${_formatDate(_endDate)} 23:59:59',
      if (widget.bsid != null && widget.bsid!.isNotEmpty)
        'sids': [int.tryParse(widget.bsid!) ?? 0],
    };

    request(HttpApi.stockplanFindList, params).then((result) {
      if (!mounted) {
        return;
      }
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null)
              as List? ??
          [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= 20;
      });
    }).catchError((_) {
      if (mounted) setState(() => _hasMore = false);
    }).whenComplete(() {
      if (mounted) {
        setState(() => _loading = false);
      }
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _onSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _page = 1;
      _hasMore = true;
      _list = [];
    });
    _loadData();
  }

  void _onSelectItem(Map<String, dynamic> item) {
    final billid = item['billid']?.toString();
    if (billid == null || billid.isEmpty) {
      return;
    }
    // 与 boss 项目保持一致：选择后返回列表行原始数据
    Navigator.pop(context, Map<String, dynamic>.from(item));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('选择盘点计划',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827))),
      ),
      body: Column(children: [
        // 搜索 + 日期筛选
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(children: [
            // 搜索框
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.search,
                    size: 18, color: Color(0xFF8B8B8B)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _onSearch(),
                    onChanged: (_) {
                      setState(() {});
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                          const Duration(milliseconds: 350), _onSearch);
                    },
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: '请输入单号',
                      hintStyle: TextStyle(
                          fontSize: 14, color: Color(0xFF8B8B8B)),
                    ),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _onSearch();
                    },
                    child: const Icon(Icons.clear,
                        size: 18, color: Color(0xFF8B8B8B)),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            // 时间 tabs
            Row(
              children: _timeTabs.asMap().entries.map((entry) {
                final index = entry.key;
                final label = entry.value;
                final selected = index == _timeIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onTimeTabChanged(index),
                    child: Container(
                      height: 34,
                      margin: EdgeInsets.only(
                          right: index < _timeTabs.length - 1 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(_primaryColorValue)
                            : Colors.white,
                        border: Border.all(
                            color: selected
                                ? const Color(_primaryColorValue)
                                : const Color(0xFFDEDEDE)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 13,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFF333333))),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            // 日期显示/选择
            _buildDateBar(),
          ]),
        ),
        // 列表
        Expanded(
          child: RefreshIndicator(
            color: const Color(_primaryColorValue),
            onRefresh: _onRefresh,
            child: _loading && _list.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(_primaryColorValue)))
                : _list.isEmpty
                    ? const Center(
                        child: Text('暂无数据',
                            style: TextStyle(
                                fontSize: 14, color: Color(0xFF9CA3AF))))
                    : ListView.builder(
                    controller: _scrollController,
                    cacheExtent: 800,
                    padding: const EdgeInsets.all(12),
                    itemCount: _list.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _list.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(_primaryColorValue)),
                            ),
                          ),
                        );
                      }
                      return RepaintBoundary(
                        child: _PlanItemCard(
                          item: _list[index],
                          onTap: () => _onSelectItem(_list[index]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _buildDateBar() {
    final showRange = _timeIndex == 2 || _timeIndex == 4;
    final singleText = _timeIndex == 3
        ? _formatMonth(_startDate)
        : _formatDate(_startDate);

    if (showRange) {
      return Row(children: [
        _buildArrowButton(Icons.chevron_left, () => _shiftDate(-1)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _pickDate(isStart: true),
            child: _buildDateBox(_formatDate(_startDate)),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('至',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF333333))),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => _pickDate(isStart: false),
            child: _buildDateBox(_formatDate(_endDate)),
          ),
        ),
        const SizedBox(width: 8),
        _buildArrowButton(Icons.chevron_right, () => _shiftDate(1)),
      ]);
    }

    return Row(children: [
      _buildArrowButton(Icons.chevron_left, () => _shiftDate(-1)),
      const SizedBox(width: 8),
      Expanded(
        child: GestureDetector(
          onTap: () => _pickDate(isStart: true),
          child: _buildDateBox(singleText),
        ),
      ),
      const SizedBox(width: 8),
      _buildArrowButton(Icons.chevron_right, () => _shiftDate(1)),
    ]);
  }

  static Widget _buildArrowButton(
      IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: const Color(0xFF464646)),
      ),
    );
  }

  static Widget _buildDateBox(String text) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDEDEDE)),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(
              fontSize: 14, color: Color(_primaryColorValue))),
    );
  }
}

class _PlanItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _PlanItemCard({required this.item, required this.onTap});

  static String _statusText(String? signflag) {
    switch (signflag) {
      case '0':
        return '待盘点';
      case '1':
        return '已盘点';
      case '2':
        return '盘点中';
      default:
        return '';
    }
  }

  static Color _statusColor(String? signflag) {
    switch (signflag) {
      case '0':
        return const Color(0xFFD54B5A);
      case '1':
        return const Color(0xFF00A870);
      case '2':
        return const Color(0xFF09B8EE);
      default:
        return const Color(0xFF7A7A7A);
    }
  }

  static Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text('$label$value',
          style: const TextStyle(
              fontSize: 12, color: Color(0xFF7A7A7A))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planname = item['planname']?.toString() ?? '';
    final storename = item['storename']?.toString() ?? '';
    final billno = item['billno']?.toString() ?? '';
    final createname = item['createname']?.toString() ?? '';
    final createtime = item['createtime']?.toString() ?? '';
    final signflag = item['signflag']?.toString();
    final status = _statusText(signflag);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text('盘点名称：$planname',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827))),
                ),
                if (status.isNotEmpty)
                  Text(status,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _statusColor(signflag))),
              ],
            ),
            _infoLine('盘点机构：', storename),
            _infoLine('盘点单号：', billno),
            _infoLine('制单人：', createname),
            _infoLine('制单时间：', createtime),
          ],
        ),
      ),
    );
  }
}
