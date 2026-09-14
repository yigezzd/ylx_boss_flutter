import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/finance/router.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/review_config_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

/// 门店结算单列表页 —— 对齐 boss 项目 storePlierpay.vue
class StorePayListPage extends StatefulWidget {
  const StorePayListPage({super.key});

  @override
  State<StorePayListPage> createState() => _StorePayListPageState();
}

class _StorePayListPageState extends State<StorePayListPage> with TickerProviderStateMixin {
  TabController? _tabController;

  int _statusIndex = 0; // 0=全部 1=待审核 2=已审核 3=已驳回

  /// 是否显示"已驳回" tab：统一从 controller 长度派生，
  /// 保证与 TabBar 的 tabs 数量永远一致，杜绝两者失步报错（对齐采购入库列表）
  bool get _showRejectedTab => (_tabController?.length ?? 3) > 3;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];

  late DateTime _startDate;
  late DateTime _endDate;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ── 筛选参数 ──
  String _filterOutsid = '';
  String _filterOutsidname = '';
  String _filterInsid = '';
  String _filterInsidname = '';
  String _filterCreateid = '';
  String _filterCreatename = '';
  String _filterHandlerid = '';
  String _filterHandlername = '';
  String _filterPayway = '';
  String _filterPaywayname = '';
  String _filterBankid = '';
  String _filterBankname = '';
  String _filterBankidother = '';
  String _filterBankidothername = '';
  int? _activeQuickTimeId;

  @override
  void initState() {
    super.initState();

    // 同步创建默认3个Tab（不含"已驳回"），确保首次 build 时 TabBar 的 controller 非空，
    // 避免 TabBar 隐式使用 DefaultTabController 触发 _dependencies 断言失败（对齐采购入库列表）
    _tabController = TabController(length: 3, vsync: this);
    _tabController!.addListener(_onTabChanged);

    final now = DateTime.now();
    _endDate = now;
    _startDate = now.subtract(const Duration(days: 30));
    _activeQuickTimeId = 4; // 默认自定义：近30天

    _scrollController.addListener(_onScroll);
    if (!PermissionUtils.checkPermission('014601', showTip: false)) {
      Toast.show('你无权查看门店结算，请在后台修改权限');
      return;
    }
    _loadReviewConfig();
  }

  /// 对齐 Vue reviewBillTypeList 动态判断是否显示“已驳回” tab（对齐采购入库列表）
  Future<void> _loadReviewConfig() async {
    final show = await ReviewConfigUtils.shouldShowRejectedTab('门店结算单');
    // 页面可能已销毁，避免 dispose 后调用 setState
    if (!mounted) return;
    _applyTabCount(show ? 4 : 3);
    _loadData();
  }

  /// 按需重建 TabController（调整 Tab 数量的唯一入口）
  ///
  /// 数量未变时直接跳过，避免无谓重建；重建时保持当前选中 tab，
  /// 若选中"已驳回"且 tab 被移除则回到"全部"（对齐采购入库列表）
  void _applyTabCount(int length) {
    final old = _tabController;
    if (old != null && old.length == length) return;
    _tabController = TabController(length: length, vsync: this);
    if (_statusIndex >= length) _statusIndex = 0;
    _tabController!.index = _statusIndex;
    _tabController!.addListener(_onTabChanged);
    old?.dispose();
    setState(() {});
  }

  /// 刷新时重评审批配置，配置变化时自动补上/移除"已驳回" tab（对齐采购入库列表）
  Future<void> _refreshReviewConfig() async {
    final show = await ReviewConfigUtils.shouldShowRejectedTab('门店结算单', force: true);
    if (!mounted) return;
    _applyTabCount(show ? 4 : 3);
  }

  /// Tab 切换监听：切换状态时重置分页并重新加载
  void _onTabChanged() {
    if (!_tabController!.indexIsChanging) {
      setState(() {
        _statusIndex = _tabController!.index;
        _page = 1;
        _hasMore = true;
        _list = [];
      });
      _loadData();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
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

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);

    final String signflag =
        _statusIndex == 1 ? '0' : (_statusIndex == 2 ? '1' : (_statusIndex == 3 ? '2' : ''));

    return request(HttpApi.financeStorePayGetList, {
      'is_page': 1,
      'field': 'createtime',
      'type': 'desc',
      'cond': '',
      'page': _page,
      'pagesize': 20,
      'signflag': signflag,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'billno': _searchController.text.trim(),
      if (_filterOutsid.isNotEmpty) 'outsid': _filterOutsid,
      if (_filterInsid.isNotEmpty) 'insid': _filterInsid,
      if (_filterCreateid.isNotEmpty) 'createid': _filterCreateid,
      if (_filterHandlerid.isNotEmpty) 'handlerid': _filterHandlerid,
      if (_filterPayway.isNotEmpty) 'payway': _filterPayway,
      if (_filterBankid.isNotEmpty) 'bankid': _filterBankid,
      if (_filterBankidother.isNotEmpty) 'bankidother': _filterBankidother,
    }).then((result) {
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.isNotEmpty && rows.length >= 20;
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
    await _refreshReviewConfig();
    await _loadData();
  }

  void _onSearch() {
    FocusScope.of(context).unfocus();
    _page = 1;
    _list = [];
    _hasMore = true;
    _loadData();
  }

  void _onSearchChanged() {
    setState(() {});
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
    String tmpOutsid = _filterOutsid;
    String tmpOutsidname = _filterOutsidname;
    String tmpInsid = _filterInsid;
    String tmpInsidname = _filterInsidname;
    String tmpCreateid = _filterCreateid;
    String tmpCreatename = _filterCreatename;
    String tmpHandlerid = _filterHandlerid;
    String tmpHandlername = _filterHandlername;
    String tmpPayway = _filterPayway;
    String tmpPaywayname = _filterPaywayname;
    String tmpBankid = _filterBankid;
    String tmpBankname = _filterBankname;
    String tmpBankidother = _filterBankidother;
    String tmpBankidothername = _filterBankidothername;
    int tmpActiveQuickTimeId = _activeQuickTimeId ?? 1;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
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
                                  child: const Icon(Icons.close,
                                      size: 22, color: Color(0xFF6B7280))))),
                    ]),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSheetTimeSelector(
                              ctx,
                              setSheetState,
                              tmpActiveQuickTimeId,
                              tmpStart,
                              tmpEnd,
                              (id) => setSheetState(() => tmpActiveQuickTimeId = id),
                              (d) => setSheetState(() => tmpStart = d),
                              (d) => setSheetState(() => tmpEnd = d)),
                          const SizedBox(height: 10),
                          _buildSheetDateNav(
                            ctx,
                            setSheetState,
                            tmpActiveQuickTimeId,
                            tmpStart,
                            tmpEnd,
                            (d) => setSheetState(() => tmpStart = d),
                            (d) => setSheetState(() => tmpEnd = d),
                            (dir) {
                              final r =
                                  _sheetTimeShift(tmpActiveQuickTimeId, tmpStart, tmpEnd, dir);
                              setSheetState(() {
                                tmpStart = r[0];
                                tmpEnd = r[1];
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          _FilterSelectRow(
                              label: '应付门店',
                              value: tmpOutsidname.isEmpty ? '应付门店' : tmpOutsidname,
                              onTap: () => _openStoreOutSelector(ctx, setSheetState,
                                      initialSelectedId: tmpOutsid,
                                      onSelected: (String id, String name) {
                                    setSheetState(() {
                                      tmpOutsid = id;
                                      tmpOutsidname = name;
                                    });
                                  })),
                          _FilterSelectRow(
                              label: '应收门店',
                              value: tmpInsidname.isEmpty ? '应收门店' : tmpInsidname,
                              onTap: () => _openStoreInSelector(ctx, setSheetState,
                                      initialSelectedId: tmpInsid,
                                      onSelected: (String id, String name) {
                                    setSheetState(() {
                                      tmpInsid = id;
                                      tmpInsidname = name;
                                    });
                                  })),
                          _FilterSelectRow(
                              label: '制单人',
                              value: tmpCreatename.isEmpty ? '全部制单人' : tmpCreatename,
                              onTap: () => _openUserSelector(ctx, setSheetState,
                                      initialSelectedId: tmpCreateid,
                                      onSelected: (String id, String name) {
                                    setSheetState(() {
                                      tmpCreateid = id;
                                      tmpCreatename = name;
                                    });
                                  })),
                          _FilterSelectRow(
                              label: '经手人',
                              value: tmpHandlername.isEmpty ? '全部经手人' : tmpHandlername,
                              onTap: () => _openHandlerSelector(ctx, setSheetState,
                                      initialSelectedId: tmpHandlerid,
                                      onSelected: (String id, String name) {
                                    setSheetState(() {
                                      tmpHandlerid = id;
                                      tmpHandlername = name;
                                    });
                                  })),
                          _FilterSelectRow(
                              label: '付款方式',
                              value: tmpPaywayname.isEmpty ? '全部付款方式' : tmpPaywayname,
                              onTap: () => _openPaywaySelector(ctx, setSheetState,
                                      initialSelectedId: tmpPayway,
                                      onSelected: (String id, String name) {
                                    setSheetState(() {
                                      tmpPayway = id;
                                      tmpPaywayname = name;
                                    });
                                  })),
                          _FilterSelectRow(
                              label: '付款账户',
                              value: tmpBankidothername.isEmpty ? '全部付款账户' : tmpBankidothername,
                              onTap: () => _openBankOtherSelector(ctx, setSheetState,
                                      initialSelectedId: tmpBankidother,
                                      onSelected: (String id, String name) {
                                    setSheetState(() {
                                      tmpBankidother = id;
                                      tmpBankidothername = name;
                                    });
                                  })),
                          _FilterSelectRow(
                              label: '收款账户',
                              value: tmpBankname.isEmpty ? '全部收款账户' : tmpBankname,
                              onTap: () => _openBankSelector(ctx, setSheetState,
                                      initialSelectedId: tmpBankid,
                                      onSelected: (String id, String name) {
                                    setSheetState(() {
                                      tmpBankid = id;
                                      tmpBankname = name;
                                    });
                                  })),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setSheetState(() {
                              final now = DateTime.now();
                              tmpStart = now.subtract(const Duration(days: 30));
                              tmpEnd = now;
                              tmpActiveQuickTimeId = 4;
                              tmpOutsid = '';
                              tmpOutsidname = '';
                              tmpInsid = '';
                              tmpInsidname = '';
                              tmpCreateid = '';
                              tmpCreatename = '';
                              tmpHandlerid = '';
                              tmpHandlername = '';
                              tmpPayway = '';
                              tmpPaywayname = '';
                              tmpBankid = '';
                              tmpBankname = '';
                              tmpBankidother = '';
                              tmpBankidothername = '';
                            });
                          },
                          style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF374151),
                              side: const BorderSide(color: Color(0xFFD1D5DB)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape:
                                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: const Text('重置', style: TextStyle(fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _startDate = tmpStart;
                              _endDate = tmpEnd;
                              _activeQuickTimeId = tmpActiveQuickTimeId;
                              _filterOutsid = tmpOutsid;
                              _filterOutsidname = tmpOutsidname;
                              _filterInsid = tmpInsid;
                              _filterInsidname = tmpInsidname;
                              _filterCreateid = tmpCreateid;
                              _filterCreatename = tmpCreatename;
                              _filterHandlerid = tmpHandlerid;
                              _filterHandlername = tmpHandlername;
                              _filterPayway = tmpPayway;
                              _filterPaywayname = tmpPaywayname;
                              _filterBankid = tmpBankid;
                              _filterBankname = tmpBankname;
                              _filterBankidother = tmpBankidother;
                              _filterBankidothername = tmpBankidothername;
                              _page = 1;
                              _list = [];
                              _hasMore = true;
                            });
                            _loadData();
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF006EFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape:
                                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: const Text('确定', style: TextStyle(fontSize: 15)),
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

  Widget _buildSheetTimeSelector(
      BuildContext ctx,
      void Function(void Function()) setSheetState,
      int activeId,
      DateTime tmpStart,
      DateTime tmpEnd,
      void Function(int) onTapId,
      void Function(DateTime) onStartChanged,
      void Function(DateTime) onEndChanged) {
    const labels = ['昨天', '今日', '本周', '本月', '自定义'];
    return Container(
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
              onTap: () {
                final r = _sheetQuickTimeSelect(i, tmpStart, tmpEnd);
                setSheetState(() {
                  onTapId(i);
                  onStartChanged(r[0]);
                  onEndChanged(r[1]);
                });
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF006EFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          selected ? Theme.of(ctx).colorScheme.onPrimary : const Color(0xFF333333),
                    )),
              ),
            ),
          );
        }),
      ),
    );
  }

  List<DateTime> _sheetQuickTimeSelect(int id, DateTime curStart, DateTime curEnd) {
    final now = DateTime.now();
    switch (id) {
      case 0:
        final s = now.subtract(const Duration(days: 1));
        return [s, s];
      case 1:
        return [DateTime(now.year, now.month, now.day), now];
      case 2:
        final wd = now.weekday;
        return [DateTime(now.year, now.month, now.day - (wd - 1)), now];
      case 3:
        return [DateTime(now.year, now.month), now];
      default:
        return [curStart, curEnd];
    }
  }

  List<DateTime> _sheetTimeShift(int id, DateTime curStart, DateTime curEnd, int direction) {
    DateTime start = curStart;
    DateTime end = curEnd;
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
        start = DateTime(curStart.year, curStart.month + direction);
        end = DateTime(start.year, start.month + 1, 0);
        break;
    }
    return [start, end];
  }

  Widget _buildSheetDateNav(
    BuildContext ctx,
    void Function(void Function()) setSheetState,
    int activeId,
    DateTime tmpStart,
    DateTime tmpEnd,
    void Function(DateTime) onStartChanged,
    void Function(DateTime) onEndChanged,
    void Function(int dir) onShift,
  ) {
    final isRange = activeId == 2 || activeId == 4;
    final isMonth = activeId == 3;
    final showArrows = activeId != 4;
    return Row(children: [
      if (showArrows)
        GestureDetector(
          onTap: () => onShift(-1),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF6B7280)),
          ),
        ),
      if (showArrows) const SizedBox(width: 8),
      Expanded(
        child: Row(children: [
          if (isRange) ...[
            Expanded(
                child: _buildSheetDatePart(ctx, tmpStart, onChanged: (d) {
              onStartChanged(d);
            })),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('至',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface)),
            ),
            Expanded(
                child: _buildSheetDatePart(ctx, tmpEnd, onChanged: (d) {
              onEndChanged(d);
            })),
          ] else
            Expanded(
                child: _buildSheetDatePart(ctx, tmpStart, isMonth: isMonth, onChanged: (d) {
              onStartChanged(d);
              if (!isMonth) onEndChanged(d);
            })),
        ]),
      ),
      if (showArrows) const SizedBox(width: 8),
      if (showArrows)
        GestureDetector(
          onTap: () => onShift(1),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF6B7280)),
          ),
        ),
    ]);
  }

  Widget _buildSheetDatePart(
    BuildContext ctx,
    DateTime date, {
    bool isMonth = false,
    required void Function(DateTime) onChanged,
  }) {
    final label =
        isMonth ? '${date.year}-${date.month.toString().padLeft(2, '0')}' : _fmtDate(date);
    return GestureDetector(
      onTap: () async {
        if (isMonth) {
          final picked = await showCommonMonthPicker(ctx, initial: date);
          if (picked != null) {
            onChanged(DateTime(picked.year, picked.month));
          }
          return;
        }
        final picked = await showCommonDatePicker(ctx, initial: date);
        if (picked != null) onChanged(picked);
      },
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(5),
        ),
        child:
            Text(label, style: TextStyle(fontSize: 14, color: Theme.of(ctx).colorScheme.onSurface)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('门店结算单',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFDEDEDE))),
                  child: Row(children: [
                    const SizedBox(width: 10),
                    const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => _onSearchChanged(),
                        onSubmitted: (_) => _onSearch(),
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                            hintText: '请输入单号',
                            hintStyle: TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _onSearch();
                          },
                          child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.cancel, size: 16, color: Color(0xFFBFBFBF)))),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                  onTap: _openFilterSheet,
                  child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.tune, size: 18, color: Color(0xFF374151)))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (!PermissionUtils.checkPermission('014602', showTip: false)) {
                    Toast.show('你无权新增门店结算，请在后台修改权限');
                    return;
                  }
                  NavigatorUtils.pushResult(
                    context,
                    FinanceRouter.storePayEdit,
                    // 对齐采购入库：返回后重评审批配置（已驳回 tab 及时出现/消失）
                    (_) => _onRefresh(),
                  );
                },
                child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDEDEDE)),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.add, size: 20, color: Color(0xFF374151))),
              ),
            ]),
          ),
          if (_tabController == null)
            const SizedBox(
                height: 48,
                child: Center(
                    child: SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            ColoredBox(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                tabs: [
                  const Tab(text: '全部'),
                  const Tab(text: '待审核'),
                  const Tab(text: '已审核'),
                  if (_showRejectedTab) const Tab(text: '已驳回'),
                ],
                labelColor: const Color(0xFF006EFF),
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                unselectedLabelColor: const Color(0xFF6B7280),
                indicatorColor: const Color(0xFF006EFF),
                indicatorSize: TabBarIndicatorSize.label,
              ),
            ),
          Expanded(
            child: _list.isEmpty && !_loading
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('暂无数据', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                  ]))
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: ListView.builder(
                      controller: _scrollController,
                      cacheExtent: 800,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      itemCount: _list.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _list.length) {
                          return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                  child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2))));
                        }
                        return RepaintBoundary(
                          child: _StorePayCard(
                            item: _list[index],
                            onTap: () {
                              if (!PermissionUtils.checkPermission('014608', showTip: false)) {
                                Toast.show('你无权查看单据明细，请在后台修改权限');
                                return;
                              }
                              final billid = _list[index]['billid']?.toString() ?? '';
                              NavigatorUtils.pushResult(
                                context,
                                '${FinanceRouter.storePayEdit}?billid=$billid',
                                // 对齐采购入库：返回后重评审批配置（已驳回 tab 及时出现/消失）
                                (_) => _onRefresh(),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── 选择器 ──
  Future<void> _openStoreOutSelector(
    BuildContext parentCtx,
    StateSetter setSheetState, {
    required void Function(String id, String name) onSelected,
    String? initialSelectedId,
  }) async {
    final result = await CommonSelectSheet.show(
      parentCtx,
      title: '选择应付门店',
      searchHint: '输入门店名称',
      // 对齐 Vue storePlierpay.vue：storetypes=[0,1,2]，排除已选应收门店
      fetchData: (search, page) => request(HttpApi.storeGetList, {
        'storetypes': [0, 1, 2],
        'cond': search,
        'is_page': 1,
        'page': page,
        'pagesize': 20,
        if (_filterInsid.isNotEmpty) 'nostoreid': _filterInsid,
      }).then((r) {
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      codeField: '',
      initialSelectedId: initialSelectedId,
    );
    if (result != null) {
      onSelected(result['id']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }

  Future<void> _openStoreInSelector(
    BuildContext parentCtx,
    StateSetter setSheetState, {
    required void Function(String id, String name) onSelected,
    String? initialSelectedId,
  }) async {
    // 对齐 Vue storePlierpay.vue：storetypes=[0,3] + psselecttype=2 + nosidsflag，排除已选应付门店
    final nosidsflag =
        SelectStorePage.loginStoreField('id') == SelectStorePage.loginStoreField('spid')
            ? '1'
            : '0';
    final result = await CommonSelectSheet.show(
      parentCtx,
      title: '选择应收门店',
      searchHint: '输入门店名称',
      fetchData: (search, page) => request(HttpApi.storeGetList, {
        'storetypes': [0, 3],
        'psselecttype': 2,
        'nosidsflag': nosidsflag,
        'cond': search,
        'is_page': 1,
        'page': page,
        'pagesize': 20,
        if (_filterOutsid.isNotEmpty) 'nostoreid': _filterOutsid,
      }).then((r) {
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      codeField: '',
      initialSelectedId: initialSelectedId,
    );
    if (result != null) {
      onSelected(result['id']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }

  Future<void> _openUserSelector(
    BuildContext parentCtx,
    StateSetter setSheetState, {
    required void Function(String id, String name) onSelected,
    String? initialSelectedId,
  }) async {
    final result = await CommonSelectSheet.show(
      parentCtx,
      title: '选择制单人',
      searchHint: '输入姓名/编码',
      fetchData: (search, page) => request(HttpApi.sysUserList, {
        'cond': search,
        'is_page': 1,
        'page': page,
        'pagesize': 20,
      }).then((r) {
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      idField: 'userid',
      showAll: true,
      initialSelectedId: initialSelectedId,
    );
    if (result != null) {
      onSelected(result['userid']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }

  Future<void> _openHandlerSelector(
    BuildContext parentCtx,
    StateSetter setSheetState, {
    required void Function(String id, String name) onSelected,
    String? initialSelectedId,
  }) async {
    final result = await CommonSelectSheet.show(
      parentCtx,
      title: '选择经手人',
      searchHint: '输入姓名/编码',
      fetchData: (search, page) => request(HttpApi.sysUserList, {
        'cond': search,
        'is_page': 1,
        'page': page,
        'pagesize': 20,
      }).then((r) {
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      idField: 'userid',
      showAll: true,
      initialSelectedId: initialSelectedId,
    );
    if (result != null) {
      onSelected(result['userid']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }

  Future<void> _openPaywaySelector(
    BuildContext parentCtx,
    StateSetter setSheetState, {
    required void Function(String id, String name) onSelected,
    String? initialSelectedId,
  }) async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      parentCtx,
      title: '选择付款方式',
      searchHint: '输入付款方式名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.pluginsGet, {
            'buseflag': 1,
            'paywayParams': {'name': ''},
            'plugins': ['payway'],
          });
          final data = r['data'];
          if (data is Map<String, dynamic> && data['payway'] is Map<String, dynamic>) {
            final pw = data['payway'] as Map<String, dynamic>;
            cache = ((pw['list'] as List?) ?? []).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'payid',
      showAll: true,
      initialSelectedId: initialSelectedId,
    );
    if (result != null) {
      onSelected(result['payid']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }

  Future<void> _openBankOtherSelector(
    BuildContext parentCtx,
    StateSetter setSheetState, {
    required void Function(String id, String name) onSelected,
    String? initialSelectedId,
  }) async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      parentCtx,
      title: '选择付款账户',
      searchHint: '输入账户名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.pluginsGet, {
            'plugins': ['bank'],
          });
          final data = r['data'];
          if (data is Map<String, dynamic> && data['bank'] is Map<String, dynamic>) {
            final bk = data['bank'] as Map<String, dynamic>;
            cache = ((bk['list'] as List?) ?? []).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'bankid',
      showAll: true,
      initialSelectedId: initialSelectedId,
    );
    if (result != null) {
      onSelected(result['bankid']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }

  Future<void> _openBankSelector(
    BuildContext parentCtx,
    StateSetter setSheetState, {
    required void Function(String id, String name) onSelected,
    String? initialSelectedId,
  }) async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      parentCtx,
      title: '选择收款账户',
      searchHint: '输入账户名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.pluginsGet, {
            'plugins': ['bank'],
          });
          final data = r['data'];
          if (data is Map<String, dynamic> && data['bank'] is Map<String, dynamic>) {
            final bk = data['bank'] as Map<String, dynamic>;
            cache = ((bk['list'] as List?) ?? []).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'bankid',
      showAll: true,
      initialSelectedId: initialSelectedId,
    );
    if (result != null) {
      onSelected(result['bankid']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }
}

class _StorePayCard extends StatelessWidget {
  const _StorePayCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final signflag = int.tryParse(item['signflag']?.toString() ?? '') ?? 0;
    String statusText;
    Color statusColor;
    if (signflag == 1) {
      statusText = '已审核';
      statusColor = const Color(0xFF00A870);
    } else if (signflag == 2) {
      statusText = '已驳回';
      statusColor = const Color(0xFFFF9900);
    } else if (signflag == -1) {
      statusText = '已作废';
      statusColor = const Color(0xFFAAAAAA);
    } else {
      statusText = '待审核';
      statusColor = const Color(0xFFD54B5A);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item['billno']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                  ),
                  Text(statusText,
                      style:
                          TextStyle(fontSize: 14, color: statusColor, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '制单人：${item['createname']?.toString() ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '应收门店：${item['storename']?.toString() ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '应付门店：${item['bstorename']?.toString() ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '已结金额：${item['billamt']?.toString() ?? '0.000'}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Container(
                height: 1,
                color: const Color(0xFFEBEBEB),
                margin: const EdgeInsets.symmetric(vertical: 8),
              ),
              Text(
                '制单时间：${item['createtime']?.toString() ?? ''}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSelectRow extends StatelessWidget {
  const _FilterSelectRow({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration:
            const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(children: [
          SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 14,
                      color: (value.startsWith('全部') || value == '应付门店' || value == '应收门店')
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF374151)))),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE)),
        ]),
      ),
    );
  }
}
