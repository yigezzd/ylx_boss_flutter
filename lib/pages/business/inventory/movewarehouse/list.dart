import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/inventory/movewarehouse/add.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

class InventoryMovewarehouseListPage extends StatefulWidget {
  const InventoryMovewarehouseListPage({super.key});

  @override
  State<InventoryMovewarehouseListPage> createState() => _InventoryMovewarehouseListPageState();
}

class _InventoryMovewarehouseListPageState extends State<InventoryMovewarehouseListPage>
    with SingleTickerProviderStateMixin, LogPageMixin<InventoryMovewarehouseListPage> {
  @override
  String get logPageName => '移仓单列表';

  late TabController _tabController;

  int _statusIndex = 0;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];

  late DateTime _startDate;
  late DateTime _endDate;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  String _storeName = '';
  List<int> _sids = [];
  String _filterCreateid = '';
  String _filterCreatename = '';

  int? _activeQuickTimeId;
  String _activeStoreId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _statusIndex = _tabController.index;
          _page = 1;
          _hasMore = true;
          _list = [];
        });
        _loadData();
      }
    });

    final now = DateTime.now();
    _endDate = now;
    _startDate = now.subtract(const Duration(days: 30));

    _scrollController.addListener(_onScroll);
    _loadStoreName();
    logEnter();
    if (!PermissionUtils.checkPermission('014101', showTip: false)) {
      Toast.show('你无权查看移仓单，请在后台修改权限');
      return;
    }
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _loadStoreName() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        final storeId = storeMap['id']?.toString() ?? '';
        _activeStoreId = storeId;
        _storeName = storeMap['name']?.toString() ?? '';
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
      }
    } catch (_) {}
  }

  String get _signflag {
    if (_statusIndex == 1) return '0';
    if (_statusIndex == 2) return '1';
    if (_statusIndex == 3) return '2';
    return '';
  }

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    logQuery(_page);

    return request(HttpApi.stockRollFindList, {
      'is_page': 1,
      'cond': '',
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'billno': _searchController.text.trim(),
      'datetype': '1',
      'billtype': 3,
      'signflag': _signflag,
      'sids': _sids,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      if (_filterCreateid.isNotEmpty) 'createid': _filterCreateid,
    }).then((result) {
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1)
          _list = rows;
        else
          _list.addAll(rows);
        _hasMore = rows.isNotEmpty;
      });
    }).catchError((_) {
      setState(() => _hasMore = false);
    }).whenComplete(() {
      setState(() => _loading = false);
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  Future<void> _selectStore() async {
    final result =
        await SelectStorePage.show(context, showAll: true, initialSelectedId: _activeStoreId);
    if (result != null && mounted) {
      setState(() {
        final storeId = result['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
        _storeName = result['storename']?.toString() ?? '';
        _page = 1;
        _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

  void _onSearch() {
    FocusScope.of(context).unfocus();
    _page = 1;
    _list = [];
    _hasMore = true;
    _loadData();
  }

  void _onSearchChanged() {
    setState(() {}); // 刷新清除按钮显示状态（对齐采购入库）
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _page = 1;
      _list = [];
      _hasMore = true;
      _loadData();
    });
  }

  void _openFilterSheet() {
    DateTime tmpStart = _startDate;
    DateTime tmpEnd = _endDate;
    int? tmpActiveQuickTimeId = _activeQuickTimeId ?? 4; // 初始化默认选中「自定义」（对齐 lxAss），已选过则保持
    bool isStartFocused = false;
    bool isEndFocused = false;
    String tmpCreateid = _filterCreateid;
    String tmpCreatename = _filterCreatename;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827)))),
                      SizedBox(
                          width: 48,
                          child: Center(
                            child: GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                            ),
                          )),
                    ])),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                Expanded(
                    child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                                setSheetState(() => tmpActiveQuickTimeId = 4);
                                return;
                              }
                              final now = DateTime.now();
                              DateTime start = now, end = now;
                              switch (tag.id) {
                                case 0:
                                  start = now.subtract(const Duration(days: 1));
                                  end = start;
                                  break;
                                case 2:
                                  final w = now.weekday;
                                  start = now.subtract(Duration(days: w - 1));
                                  end = start.add(const Duration(days: 6));
                                  break;
                                case 3:
                                  start = DateTime(now.year, now.month);
                                  end = DateTime(now.year, now.month + 1, 0);
                                  break;
                              }
                              setSheetState(() {
                                tmpStart = start;
                                tmpEnd = end;
                                tmpActiveQuickTimeId = tag.id;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: active ? const Color(0xFF006EFF) : Colors.white,
                                border: Border.all(
                                    color:
                                        active ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(tag.label,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: active ? Colors.white : const Color(0xFF333333))),
                            ),
                          );
                        }).toList()),
                    const SizedBox(height: 10),
                    const Text('时间范围',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: _buildDateChip(
                              label: '开始：${_fmtDate(tmpStart)}',
                              isFocused: isStartFocused,
                              onTap: () async {
                                setSheetState(() => isStartFocused = true);
                                final p = await showCommonDatePicker(ctx, initial: tmpStart);
                                if (p != null) {
                                  if (p.isAfter(DateTime(tmpEnd.year, tmpEnd.month, tmpEnd.day))) {
                                    Toast.show('开始日期不能晚于结束日期');
                                  } else {
                                    setSheetState(() {
                                      tmpStart = p;
                                      tmpActiveQuickTimeId = 4;
                                    });
                                  }
                                }
                                setSheetState(() => isStartFocused = false);
                              })),
                      const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('—', style: TextStyle(color: Color(0xFF9CA3AF)))),
                      Expanded(
                          child: _buildDateChip(
                              label: '结束：${_fmtDate(tmpEnd)}',
                              isFocused: isEndFocused,
                              onTap: () async {
                                setSheetState(() => isEndFocused = true);
                                final p = await showCommonDatePicker(ctx, initial: tmpEnd);
                                if (p != null) {
                                  if (p.isBefore(
                                      DateTime(tmpStart.year, tmpStart.month, tmpStart.day))) {
                                    Toast.show('结束日期不能早于开始日期');
                                  } else {
                                    setSheetState(() {
                                      tmpEnd = p;
                                      tmpActiveQuickTimeId = 4;
                                    });
                                  }
                                }
                                setSheetState(() => isEndFocused = false);
                              })),
                    ]),
                    const SizedBox(height: 20),
                    _buildFilterRow(
                        label: '制单人',
                        value: tmpCreatename.isNotEmpty ? tmpCreatename : '全部制单人',
                        onTap: () async {
                          final r = await SelectBuyerPage.show(ctx,
                              initialSelectedId: tmpCreateid, showAll: true);
                          if (r != null)
                            setSheetState(() {
                              tmpCreateid = r['buyerid']?.toString() ?? '';
                              tmpCreatename = r['buyername']?.toString() ?? '';
                            });
                        }),
                    const SizedBox(height: 24),
                  ]),
                )),
                Container(
                  padding: EdgeInsets.only(
                      left: 16, right: 16, top: 12, bottom: MediaQuery.of(ctx).padding.bottom + 12),
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
                  child: Row(children: [
                    Expanded(
                        child: GestureDetector(
                            onTap: () {
                              setSheetState(() {
                                final n = DateTime.now();
                                tmpStart = n.subtract(const Duration(days: 30));
                                tmpEnd = n;
                                tmpActiveQuickTimeId = 4;
                                tmpCreateid = '';
                                tmpCreatename = '';
                              });
                            },
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFCCCCCC)),
                                  borderRadius: BorderRadius.circular(6)),
                              alignment: Alignment.center,
                              child: const Text('重置',
                                  style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
                            ))),
                    const SizedBox(width: 16),
                    Expanded(
                        child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _startDate = tmpStart;
                                _endDate = tmpEnd;
                                _activeQuickTimeId = tmpActiveQuickTimeId;
                                _filterCreateid = tmpCreateid;
                                _filterCreatename = tmpCreatename;
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
                                  borderRadius: BorderRadius.circular(6)),
                              alignment: Alignment.center,
                              child: const Text('确定',
                                  style: TextStyle(fontSize: 15, color: Colors.white)),
                            ))),
                  ]),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  static Widget _buildDateChip(
      {required String label, required VoidCallback onTap, bool isFocused = false}) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              border:
                  Border.all(color: isFocused ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(6)),
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              overflow: TextOverflow.ellipsis),
        ));
  }

  static Widget _buildFilterRow(
      {required String label, required String value, required VoidCallback onTap}) {
    return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration:
              const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
          child: Row(children: [
            SizedBox(
                width: 80,
                child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333)))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
          ]),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
            onPressed: () => Navigator.pop(context)),
        title: const Text('移仓单',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(88),
            child: ColoredBox(
                color: Colors.white,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(children: [
                        GestureDetector(
                            onTap: _selectStore,
                            child: Container(
                                constraints: const BoxConstraints(maxWidth: 110),
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFDEDEDE)),
                                    borderRadius: BorderRadius.circular(5)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Flexible(
                                      child: Text(_storeName.isNotEmpty ? _storeName : '全部机构',
                                          style: const TextStyle(
                                              fontSize: 13, color: Color(0xFF333333)),
                                          overflow: TextOverflow.ellipsis)),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_drop_down,
                                      size: 18, color: Color(0xFF666666)),
                                ]))),
                        const SizedBox(width: 6),
                        Expanded(
                            child: SizedBox(
                                height: 36,
                                child: TextField(
                                    controller: _searchController,
                                    onSubmitted: (_) => _onSearch(),
                                    onChanged: (_) => _onSearchChanged(),
                                    decoration: InputDecoration(
                                      hintText: '请输入单号',
                                      hintStyle:
                                          const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                                      prefixIcon: const Icon(Icons.search,
                                          size: 18, color: Color(0xFF8B8B8B)),
                                      prefixIconConstraints: const BoxConstraints(minWidth: 32),
                                      suffixIcon: _searchController.text.isNotEmpty
                                          ? GestureDetector(
                                              onTap: () {
                                                _searchController.clear();
                                                _onSearchChanged();
                                              },
                                              child: Container(
                                                width: 16,
                                                height: 16,
                                                margin: const EdgeInsets.only(right: 8),
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF6B7280),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Center(
                                                  child: Icon(Icons.close,
                                                      size: 10, color: Colors.white),
                                                ),
                                              ),
                                            )
                                          : null,
                                      suffixIconConstraints: const BoxConstraints(minWidth: 24),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                                      filled: true,
                                      fillColor: const Color(0xFFF5F5F5),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(5),
                                          borderSide: const BorderSide(color: Color(0xFFDEDEDE))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(5),
                                          borderSide: const BorderSide(color: Color(0xFFDEDEDE))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(5),
                                          borderSide: const BorderSide(color: Color(0xFF006EFF))),
                                    )))),
                        const SizedBox(width: 6),
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
                        const SizedBox(width: 6),
                        GestureDetector(
                            onTap: () async {
                              if (!PermissionUtils.checkPermission('014102', showTip: false)) {
                                Toast.show('你无权新增移仓单，请在后台修改权限');
                                return;
                              }
                              logAdd();
                              await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const InventoryMovewarehouseAddPage()));
                              _onRefresh();
                            },
                            child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFDEDEDE)),
                                    borderRadius: BorderRadius.circular(5)),
                                child: const Icon(Icons.add, size: 24, color: Color(0xFF333333)))),
                      ])),
                  TabBar(
                      controller: _tabController,
                      labelColor: const Color(0xFF006EFF),
                      unselectedLabelColor: const Color(0xFF6B7280),
                      indicatorColor: const Color(0xFF006EFF),
                      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      unselectedLabelStyle: const TextStyle(fontSize: 14),
                      tabs: const [
                        Tab(text: '全部'),
                        Tab(text: '待审核'),
                        Tab(text: '已审核'),
                        Tab(text: '已驳回')
                      ]),
                ]))),
      ),
      body: RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: _onRefresh,
          child: _list.isEmpty && !_loading
              ? ListView(children: const [
                  SizedBox(height: 120),
                  Center(
                      child: Column(children: [
                    Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                    SizedBox(height: 12),
                    Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)))
                  ]))
                ])
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  cacheExtent: 800,
                  itemCount: _list.length + (_loading ? 1 : (_hasMore ? 0 : 1)),
                  itemBuilder: (context, index) {
                    if (index == _list.length) {
                      return _loading
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                  child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Color(0xFF006EFF)))))
                          : const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                  child: Text('没有更多数据',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))));
                    }
                    return RepaintBoundary(
                        child: _MovewarehouseCard(
                            item: _list[index],
                            onTap: () async {
                              if (!PermissionUtils.checkPermission('014102', showTip: false)) {
                                Toast.show('你无权查看单据明细，请在后台修改权限');
                                return;
                              }
                              logView(_list[index]['billno']?.toString());
                              await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          InventoryMovewarehouseAddPage(billData: _list[index])));
                              _onRefresh();
                            }));
                  })),
    );
  }
}

class _QuickTimeTag {
  const _QuickTimeTag(this.label, this.id);
  final String label;
  final int id;
}

class _MovewarehouseCard extends StatelessWidget {
  const _MovewarehouseCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String storename = item['storename']?.toString() ?? '-';
    final String billno = item['billno']?.toString() ?? '-';
    final String createname = item['createname']?.toString() ?? '-';
    final String createtime = item['createtime']?.toString() ?? '-';
    final String outcountername = item['outcountername']?.toString() ?? '-';
    final String incountername = item['incountername']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
    // signflag: 0/空→待审核, 1→已审核, 2→已驳回（对齐 lxAss）
    final String statusLabel = signflag == '1' ? '已审核' : (signflag == '2' ? '已驳回' : '待审核');
    final Color statusColor = signflag == '1'
        ? const Color(0xFF00A870)
        : (signflag == '2' ? const Color(0xFFE0620D) : const Color(0xFFD54B5A));

    return GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5)),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text('移仓机构：$storename',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                          overflow: TextOverflow.ellipsis)),
                  Text(statusLabel,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
                ]),
                const SizedBox(height: 8),
                Text('单号：$billno',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('移出仓库：$outcountername',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('移入仓库：$incountername',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('制单人：$createname',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis),
                Container(
                    height: 1,
                    color: const Color(0xFFEBEBEB),
                    margin: const EdgeInsets.symmetric(vertical: 8)),
                Text('制单时间：$createtime',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis),
              ])),
        ));
  }
}
