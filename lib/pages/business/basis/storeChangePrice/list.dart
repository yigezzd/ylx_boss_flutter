import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/storeChangePrice/edit.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

/// 门店调价单 - 列表页
/// 参考 Vue boss 项目 storeChangePrice/index.vue + search.vue
class StoreChangePriceListPage extends StatefulWidget {
  const StoreChangePriceListPage({super.key});

  @override
  State<StoreChangePriceListPage> createState() => _StoreChangePriceListPageState();
}

class _StoreChangePriceListPageState extends State<StoreChangePriceListPage>
    with SingleTickerProviderStateMixin {
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // Tab 控制器
  late TabController _tabController;

  // Tab 选项（对齐 Vue tabsTitle：signflag）
  static const List<Map<String, String>> _tabs = [
    {'key': '', 'title': '全部'},
    {'key': '0', 'title': '待审核'},
    {'key': '1', 'title': '已审核'},
    {'key': '2', 'title': '已驳回'},
  ];

  // ── 筛选参数（对齐 Vue paramsdef）──
  String _signflag = '';
  String _storeId = '';
  String _storeName = '';
  String _startDate = '';
  String _endDate = '';
  String _executetype = ''; // 调价类型
  int? _activeQuickTimeId = 4;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);

    // 默认时间范围：近30天（对齐 Vue DayJs().subtract(29, "day")）
    final now = DateTime.now();
    _endDate = _formatDate(now);
    _startDate = _formatDate(now.subtract(const Duration(days: 29)));

    // 查看权限校验
    if (!PermissionUtils.checkPermission('010501', showTip: false)) {
      Toast.show('你无权查看门店调价，请在后台修改权限');
    } else {
      _loadData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _signflag = _tabs[_tabController.index]['key']!;
    _page = 1;
    _list = [];
    _hasMore = true;
    _loadData();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);

    final params = <String, dynamic>{
      'is_page': 1,
      'page': _page,
      'pagesize': 20,
      'field': 'createtime',
      'type': 'desc',
      'cond': _searchController.text.trim(),
      if (_signflag.isNotEmpty) 'signflag': _signflag,
      if (_storeId.isNotEmpty) 'sids': _storeId,
      if (_startDate.isNotEmpty) 'starttime': '$_startDate 00:00:00',
      if (_endDate.isNotEmpty) 'endtime': '$_endDate 23:59:59',
      if (_executetype.isNotEmpty) 'executetype': _executetype,
    };

    try {
      final result = await request(HttpApi.storeChangePriceFindList, params);
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= 20;
      });
    } catch (_) {
      setState(() => _hasMore = false);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 1;
      _list = [];
      _hasMore = true;
      _loadData();
    });
  }

  // ── 门店选择 ──
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _storeId,
    );
    if (result != null && mounted) {
      setState(() {
        _storeId = result['storeid']?.toString() ?? '';
        _storeName = result['storename']?.toString() ?? '';
      });
      _page = 1;
      _list = [];
      _hasMore = true;
      _loadData();
    }
  }

  // ── 新增 ──
  Future<void> _add() async {
    if (!PermissionUtils.checkPermission('010502', showTip: false)) {
      Toast.show('你无权新增门店调价，请在后台修改权限');
      return;
    }
    final refresh = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const StoreChangePriceEditPage()),
    );
    if ((refresh ?? false) && mounted) {
      _onRefresh();
    }
  }

  // ── 打开编辑页 ──
  Future<void> _openEdit(Map<String, dynamic> item) async {
    if (!PermissionUtils.checkPermission('010507', showTip: false)) {
      Toast.show('你无权查看单据明细，请在后台修改权限');
      return;
    }
    final refresh = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StoreChangePriceEditPage(
          billid: item['billid']?.toString() ?? '',
        ),
      ),
    );
    if ((refresh ?? false) && mounted) {
      _onRefresh();
    }
  }

  // ── 筛选抽屉 ──
  void _openFilterSheet() {
    String tmpStart = _startDate;
    String tmpEnd = _endDate;
    int? tmpActiveQuickTimeId = _activeQuickTimeId;
    String tmpExecutetype = _executetype;

    // 调价类型选项（对齐 Vue searchlist）
    const executetypeOptions = [
      {'label': '全部', 'value': ''},
      {'label': '立即执行调价', 'value': '1'},
      {'label': '指定日期调价', 'value': '2'},
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final screenHeight = MediaQuery.of(context).size.height;
            return Container(
              height: screenHeight * 2 / 3,
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
                          child: Text('筛选',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                  // 内容区（可滚动）
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── 快速时间选择 ──
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              const _QuickTimeTag('昨天', 0),
                              const _QuickTimeTag('今天', 1),
                              const _QuickTimeTag('本周', 2),
                              const _QuickTimeTag('本月', 3),
                              const _QuickTimeTag('自定义', 4),
                            ].map((tag) {
                              final active = tmpActiveQuickTimeId == tag.id;
                              return GestureDetector(
                                onTap: () {
                                  if (tag.id == 4) {
                                    setSheetState(() {
                                      tmpActiveQuickTimeId = 4;
                                    });
                                    return;
                                  }
                                  final now = DateTime.now();
                                  DateTime start = now;
                                  DateTime end = now;
                                  switch (tag.id) {
                                    case 0:
                                      start = now.subtract(const Duration(days: 1));
                                      end = start;
                                      break;
                                    case 1:
                                      break;
                                    case 2:
                                      final weekday = now.weekday;
                                      start = now.subtract(Duration(days: weekday - 1));
                                      end = start.add(const Duration(days: 6));
                                      break;
                                    case 3:
                                      start = DateTime(now.year, now.month);
                                      end = DateTime(now.year, now.month + 1, 0);
                                      break;
                                  }
                                  setSheetState(() {
                                    tmpStart = _formatDate(start);
                                    tmpEnd = _formatDate(end);
                                    tmpActiveQuickTimeId = tag.id;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: active ? const Color(0xFF006EFF) : Colors.white,
                                    border: Border.all(
                                        color: active
                                            ? const Color(0xFF006EFF)
                                            : const Color(0xFFDEDEDE)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tag.label,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: active ? Colors.white : const Color(0xFF333333)),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          // 日期范围
                          const Text('日期范围',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final picked = await showCommonDatePicker(
                                    ctx,
                                    initial: DateTime.tryParse(tmpStart) ?? DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setSheetState(() {
                                      tmpStart = _formatDate(picked);
                                      tmpActiveQuickTimeId = 4;
                                    });
                                  }
                                },
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFDEDEDE)),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.calendar_today,
                                        size: 16, color: Color(0xFF6B7280)),
                                    const SizedBox(width: 6),
                                    Text(tmpStart.isNotEmpty ? tmpStart : '开始日期',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: tmpStart.isNotEmpty
                                              ? const Color(0xFF333333)
                                              : const Color(0xFF9CA3AF),
                                        )),
                                  ]),
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('至',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final picked = await showCommonDatePicker(
                                    ctx,
                                    initial: DateTime.tryParse(tmpEnd) ?? DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setSheetState(() {
                                      tmpEnd = _formatDate(picked);
                                      tmpActiveQuickTimeId = 4;
                                    });
                                  }
                                },
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFDEDEDE)),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.calendar_today,
                                        size: 16, color: Color(0xFF6B7280)),
                                    const SizedBox(width: 6),
                                    Text(tmpEnd.isNotEmpty ? tmpEnd : '结束日期',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: tmpEnd.isNotEmpty
                                              ? const Color(0xFF333333)
                                              : const Color(0xFF9CA3AF),
                                        )),
                                  ]),
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 20),
                          // 调价类型
                          const Text('调价类型',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: executetypeOptions.map((opt) {
                              final isSelected = tmpExecutetype == opt['value'];
                              return GestureDetector(
                                onTap: () => setSheetState(() => tmpExecutetype = opt['value']!),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF006EFF) : Colors.white,
                                    border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF006EFF)
                                            : const Color(0xFFDEDEDE)),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(opt['label']!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isSelected ? Colors.white : const Color(0xFF333333),
                                      )),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  // 底部按钮
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                    child: Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              final now = DateTime.now();
                              tmpStart = _formatDate(now.subtract(const Duration(days: 29)));
                              tmpEnd = _formatDate(now);
                              tmpActiveQuickTimeId = 4;
                              tmpExecutetype = '';
                            });
                          },
                          child: Container(
                            height: 42,
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFDEDEDE)),
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
                          onTap: () {
                            setState(() {
                              _startDate = tmpStart;
                              _endDate = tmpEnd;
                              _activeQuickTimeId = tmpActiveQuickTimeId;
                              _executetype = tmpExecutetype;
                              _page = 1;
                              _list = [];
                              _hasMore = true;
                            });
                            Navigator.pop(ctx);
                            _loadData();
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
                    ]),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

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
        title: const Text('门店调价单',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 门店 + 搜索栏 ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    // 门店选择
                    GestureDetector(
                      onTap: _selectStore,
                      child: Container(
                        height: 36,
                        constraints: const BoxConstraints(maxWidth: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _storeName.isNotEmpty ? _storeName : '全部',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF999999)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 搜索输入框
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchController,
                          builder: (context, value, _) {
                            return TextField(
                              controller: _searchController,
                              onChanged: (_) => _onSearch(),
                              decoration: InputDecoration(
                                hintText: '请输入单号',
                                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                                prefixIcon:
                                    const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                                // 有输入内容时显示清空按钮
                                suffixIcon: value.text.isNotEmpty
                                    ? GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          _debounce?.cancel();
                                          _searchController.clear();
                                          _onSearch();
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 6),
                                          child: Icon(Icons.cancel,
                                              size: 16, color: Color(0xFFBFBFBF)),
                                        ),
                                      )
                                    : null,
                                contentPadding: EdgeInsets.zero,
                                filled: true,
                                fillColor: const Color(0xFFF5F5F5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(5),
                                  borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(5),
                                  borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(5),
                                  borderSide: const BorderSide(color: Color(0xFF006EFF)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 筛选按钮
                    GestureDetector(
                      onTap: _openFilterSheet,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(Icons.tune, size: 20, color: Color(0xFF666666)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 新增按钮
                    GestureDetector(
                      onTap: _add,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(Icons.add, size: 24, color: Color(0xFF333333)),
                      ),
                    ),
                  ]),
                ),
                // ── Tab 栏 ──
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: const Color(0xFF006EFF),
                  unselectedLabelColor: const Color(0xFF374151),
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 14),
                  indicatorColor: const Color(0xFF006EFF),
                  tabAlignment: TabAlignment.start,
                  tabs: _tabs.map((t) => Tab(text: t['title'])).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _list.isEmpty && !_loading
          ? const Center(
              child: Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))))
          : RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                cacheExtent: 800,
                itemCount: _list.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _list.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  return RepaintBoundary(
                    child: _StoreChangePriceCard(
                      item: _list[index],
                      onTap: () => _openEdit(_list[index]),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// 门店调价单列表项卡片（对齐 Vue index.vue 列表布局）
class _StoreChangePriceCard extends StatelessWidget {
  const _StoreChangePriceCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static String _statusLabel(dynamic signflag) {
    final s = signflag?.toString() ?? '';
    if (s.isEmpty || s == '0') return '待审核';
    if (s == '2') return '已驳回';
    return '已审核';
  }

  static Color _statusColor(dynamic signflag) {
    final s = signflag?.toString() ?? '';
    if (s.isEmpty || s == '0') return const Color(0xFFD54B5A);
    if (s == '2') return const Color(0xFFE0620D);
    return const Color(0xFF00A870);
  }

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '';
    final dynamic signflag = item['signflag'];
    final String mdstorename = item['mdstorename']?.toString() ?? '';
    final String createname = item['createname']?.toString() ?? '';
    final String createtime = item['createtime']?.toString() ?? '';
    final String statusLabel = _statusLabel(signflag);
    final Color statusColor = _statusColor(signflag);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 单号 + 状态
            Row(children: [
              Expanded(
                child: Text('单号$billno',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: statusColor),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: statusColor)),
              ),
            ]),
            const SizedBox(height: 8),
            // 生效门店
            if (mdstorename.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('生效门店：$mdstorename',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ),
            // 制单人
            if (createname.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('制单人：$createname',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ),
            // 制单时间
            if (createtime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('制单时间：$createtime',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ),
          ],
        ),
      ),
    );
  }
}

/// 快速时间选择标签
class _QuickTimeTag {
  const _QuickTimeTag(this.label, this.id);
  final String label;
  final int id;
}
