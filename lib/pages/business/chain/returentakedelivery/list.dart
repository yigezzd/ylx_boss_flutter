import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/chain/returentakedelivery/edit.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/review_config_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 配退收货单列表页（对齐 Vue chain/returentakeDelivery/returentakeDelivery.vue）
class ReturnTakeDeliveryListPage extends StatefulWidget {
  const ReturnTakeDeliveryListPage({super.key});

  @override
  State<ReturnTakeDeliveryListPage> createState() => _ReturnTakeDeliveryListPageState();
}

class _ReturnTakeDeliveryListPageState extends State<ReturnTakeDeliveryListPage>
    with TickerProviderStateMixin, LogPageMixin<ReturnTakeDeliveryListPage> {
  static const _quickLabels = ['昨天', '今天', '本周', '本月', '自定义'];

  /// 配退状态（对齐 Vue dhflagList）
  static const _dhflagLabels = ['全部', '待收货', '全部收货'];
  static const _dhflagValues = ['', '1', '3'];

  @override
  String get logPageName => '配退收货单列表';

  TabController? _tabController;

  /// 是否显示"已驳回" tab：统一从 controller 长度派生
  bool get _showRejectedTab => (_tabController?.length ?? 3) > 3;
  int _statusIndex = 0; // 0=全部 1=待审核 2=已审核 3=已驳回
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];

  late DateTime _startDate;
  late DateTime _endDate;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ── 筛选参数（对齐 Vue params） ──
  String _filterDhflag = ''; // 配退状态
  String _filterCreateid = '';
  String _filterCreatename = '';
  String _filterInsid = ''; // 配送中心
  String _filterInname = '';
  String _filterOutsid = ''; // 退货门店
  String _filterOutname = '';

  // ── 机构范围（对齐 Vue paramsD：sids/nosidsflag） ──
  List<int> _sids = [];
  int _nosidsflag = 0;

  int? _activeQuickTimeId = 4;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);
    _tabController!.addListener(_onTabChanged);

    final now = DateTime.now();
    _endDate = now;
    _startDate = now.subtract(const Duration(days: 30));

    _scrollController.addListener(_onScroll);
    _loadStoreScope();
    logEnter();
    _loadReviewConfig();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

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

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  /// 对齐 Vue paramsD：sids = storetype==4 ? [store.id] : []，nosidsflag = isStore ? 1 : 0
  void _loadStoreScope() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        final storeId = storeMap['id']?.toString() ?? '';
        final spid = storeMap['spid']?.toString() ?? '';
        final storetype = int.tryParse(storeMap['storetype']?.toString() ?? '');
        _sids = (storetype == 4 && storeId.isNotEmpty) ? [int.tryParse(storeId) ?? 0] : [];
        _nosidsflag = (storeId.isNotEmpty && storeId != spid) ? 1 : 0;
      }
    } catch (_) {}
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 对齐 Vue reviewBillTypeList 动态判断是否显示"已驳回" tab
  Future<void> _loadReviewConfig() async {
    final show = await ReviewConfigUtils.shouldShowRejectedTab('配退收货单');
    if (!mounted) return;
    if (show) _applyTabCount(4);
    _startLoadData();
  }

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

  Future<void> _refreshReviewConfig() async {
    final show = await ReviewConfigUtils.shouldShowRejectedTab('配退收货单', force: true);
    if (!mounted) return;
    _applyTabCount(show ? 4 : 3);
  }

  /// 权限校验后加载列表数据（对齐 Vue permissionMsg('013508')）
  void _startLoadData() {
    if (!PermissionUtils.checkPermission('013508', showTip: false)) {
      Toast.show('你无权查看配退收货单，请在后台修改权限');
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    logQuery(_page);
    String signflag = '';
    if (_statusIndex == 1) {
      signflag = '0';
    } else if (_statusIndex == 2) {
      signflag = '1';
    } else if (_showRejectedTab && _statusIndex == 3) {
      signflag = '2';
    }

    return request(HttpApi.psrefundinFindList, {
      'is_page': 1,
      'billno': _searchController.text.trim(),
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'pagesize': 20,
      'datetype': '1',
      'signflag': signflag,
      'nosidsflag': _nosidsflag,
      'sids': _sids,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      if (_filterDhflag.isNotEmpty) 'dhflag': _filterDhflag,
      if (_filterCreateid.isNotEmpty) 'createid': _filterCreateid,
      if (_filterCreatename.isNotEmpty) 'createname': _filterCreatename,
      if (_filterInsid.isNotEmpty) 'insid': _filterInsid,
      if (_filterOutsid.isNotEmpty) 'outsid': _filterOutsid,
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
        _hasMore = rows.length >= 20;
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

  // ── 搜索 ──
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

  // ── 筛选抽屉 ──
  void _openFilterSheet() {
    DateTime tmpStart = _startDate;
    DateTime tmpEnd = _endDate;
    int? tmpActiveQuickTimeId = _activeQuickTimeId;
    int tmpDhflagIndex = _dhflagValues.indexOf(_filterDhflag);
    if (tmpDhflagIndex < 0) tmpDhflagIndex = 0;
    String tmpCreateid = _filterCreateid;
    String tmpCreatename = _filterCreatename;
    String tmpInid = _filterInsid;
    String tmpInname = _filterInname;
    String tmpOutid = _filterOutsid;
    String tmpOutname = _filterOutname;

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
                  SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        const SizedBox(width: 48),
                        const Expanded(
                          child: Text('筛选',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
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
                          // ── 配退状态 ──
                          Container(
                            height: 37,
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFD1D5DB)),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(
                              children: List.generate(_dhflagLabels.length, (i) {
                                final selected = tmpDhflagIndex == i;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => setSheetState(() => tmpDhflagIndex = i),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color:
                                            selected ? const Color(0xFF006EFF) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(_dhflagLabels[i],
                                          style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                selected ? Colors.white : const Color(0xFF333333),
                                          )),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // ── 快速时间选择 ──
                          Container(
                            height: 37,
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFD1D5DB)),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(
                              children: List.generate(_quickLabels.length, (i) {
                                final selected = tmpActiveQuickTimeId == i;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      if (i == 4) {
                                        setSheetState(() => tmpActiveQuickTimeId = 4);
                                        return;
                                      }
                                      final now = DateTime.now();
                                      DateTime start = now;
                                      DateTime end = now;
                                      switch (i) {
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
                                        tmpStart = start;
                                        tmpEnd = end;
                                        tmpActiveQuickTimeId = i;
                                      });
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color:
                                            selected ? const Color(0xFF006EFF) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(_quickLabels[i],
                                          style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                selected ? Colors.white : const Color(0xFF333333),
                                          )),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildSheetDateNav(
                            ctx,
                            setSheetState,
                            tmpActiveQuickTimeId ?? 1,
                            tmpStart,
                            tmpEnd,
                            (d) => setSheetState(() => tmpStart = d),
                            (d) => setSheetState(() => tmpEnd = d),
                            (dir) {
                              final r =
                                  _sheetTimeShift(tmpActiveQuickTimeId ?? 1, tmpStart, tmpEnd, dir);
                              setSheetState(() {
                                tmpStart = r[0];
                                tmpEnd = r[1];
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          // ── 退货门店（outsid） ──
                          _buildFilterRow(
                            label: '退货门店',
                            value: tmpOutname.isNotEmpty ? tmpOutname : '全部',
                            onTap: () async {
                              final result = await SelectStorePage.show(
                                ctx,
                                showAll: true,
                                initialSelectedId: tmpOutid,
                                storetypes: const [1, 2],
                              );
                              if (result != null) {
                                setSheetState(() {
                                  tmpOutid = result['storeid']?.toString() ?? '';
                                  tmpOutname = result['storename']?.toString() ?? '';
                                });
                              }
                            },
                          ),
                          // ── 配送中心（insid） ──
                          _buildFilterRow(
                            label: '配送中心',
                            value: tmpInname.isNotEmpty ? tmpInname : '全部',
                            onTap: () async {
                              final result = await SelectStorePage.show(
                                ctx,
                                showAll: true,
                                initialSelectedId: tmpInid,
                                storetypes: const [3],
                              );
                              if (result != null) {
                                setSheetState(() {
                                  tmpInid = result['storeid']?.toString() ?? '';
                                  tmpInname = result['storename']?.toString() ?? '';
                                });
                              }
                            },
                          ),
                          // ── 制单人 ──
                          _buildFilterRow(
                            label: '制单人',
                            value: tmpCreatename.isNotEmpty ? tmpCreatename : '全部制单人',
                            onTap: () async {
                              final result =
                                  await SelectBuyerPage.show(ctx, initialSelectedId: tmpCreateid);
                              if (result != null) {
                                setSheetState(() {
                                  tmpCreateid = result['buyerid']?.toString() ?? '';
                                  tmpCreatename = result['buyername']?.toString() ?? '';
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  // ── 底部按钮 ──
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
                                final now = DateTime.now();
                                tmpStart = now.subtract(const Duration(days: 30));
                                tmpEnd = now;
                                tmpActiveQuickTimeId = null;
                                tmpDhflagIndex = 0;
                                tmpCreateid = '';
                                tmpCreatename = '';
                                tmpInid = '';
                                tmpInname = '';
                                tmpOutid = '';
                                tmpOutname = '';
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
                            onTap: () {
                              setState(() {
                                _startDate = tmpStart;
                                _endDate = tmpEnd;
                                _activeQuickTimeId = tmpActiveQuickTimeId;
                                _filterDhflag = _dhflagValues[tmpDhflagIndex];
                                _filterCreateid = tmpCreateid;
                                _filterCreatename = tmpCreatename;
                                _filterInsid = tmpInid;
                                _filterInname = tmpInname;
                                _filterOutsid = tmpOutid;
                                _filterOutname = tmpOutname;
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
              setSheetState(() => _activeQuickTimeId = 4);
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
              setSheetState(() => _activeQuickTimeId = 4);
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

  static Widget _buildFilterRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
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
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('配退收货',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                // ── 工具栏 ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      // 搜索框
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _searchController,
                            onSubmitted: (_) => _onSearch(),
                            onChanged: (_) => _onSearchChanged(),
                            decoration: InputDecoration(
                              hintText: '请输入单号',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                              prefixIcon:
                                  const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
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
                                          child: Icon(Icons.close, size: 10, color: Colors.white),
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
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                              svgFile: 'fliter.svg', size: 22, color: Color(0xFF666666)),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Tab 栏 ──
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF006EFF),
                  unselectedLabelColor: const Color(0xFF6B7280),
                  indicatorColor: const Color(0xFF006EFF),
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 14),
                  tabs: [
                    const Tab(text: '全部'),
                    const Tab(text: '待审核'),
                    const Tab(text: '已审核'),
                    if (_showRejectedTab) const Tab(text: '已驳回'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF006EFF),
        onRefresh: _onRefresh,
        child: _list.isEmpty && !_loading
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                        SizedBox(height: 12),
                        Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                ],
              )
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
                                  strokeWidth: 2,
                                  color: Color(0xFF006EFF),
                                ),
                              ),
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text('没有更多数据',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                            ),
                          );
                  }
                  return RepaintBoundary(
                    child: _ReturnTakeDeliveryCard(
                      item: _list[index],
                      onTap: () {
                        // 查看权限校验（对齐 Vue permissionMsg('013508')）
                        if (!PermissionUtils.checkPermission('013508', showTip: false)) {
                          Toast.show('你无权查看配退收货单，请在后台修改权限');
                          return;
                        }
                        logView(_list[index]['billno']?.toString());
                        Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReturnTakeDeliveryEditPage(billData: _list[index]),
                          ),
                        ).then((_) => _onRefresh());
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// 列表卡片（对齐 Vue returentakeDelivery.vue 卡片布局）
class _ReturnTakeDeliveryCard extends StatelessWidget {
  const _ReturnTakeDeliveryCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static Color _statusColor(String? signflag) {
    if (signflag == '1') return const Color(0xFF00A870);
    if (signflag == '2') return const Color(0xFFFF9900);
    if (signflag == '-1') return const Color(0xFFAAAAAA);
    return const Color(0xFFD54B5A);
  }

  static String _statusLabel(String? signflag) {
    if (signflag == '1') return '已审核';
    if (signflag == '2') return '已驳回';
    if (signflag == '-1') return '已作废';
    return '待审核';
  }

  static String _fmtAmt(dynamic value) {
    final v = double.tryParse(value?.toString() ?? '0') ?? 0.0;
    return v.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '-';
    final String outstorename = item['outstorename']?.toString() ?? '';
    final String instorename = item['instorename']?.toString() ?? '';
    final String billamt = _fmtAmt(item['billamt']);
    final String createname = item['createname']?.toString() ?? '-';
    final String createtime = item['createtime']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
    final Color statusColor = _statusColor(signflag);
    final String statusLabel = _statusLabel(signflag);

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
              // 第1行：单号 + 审核状态
              Row(
                children: [
                  Expanded(
                    child: Text(billno,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text(statusLabel,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
                ],
              ),
              const SizedBox(height: 8),
              // 第2行：退货门店 + 配送中心
              Row(
                children: [
                  Expanded(
                    child: Text('退货门店：$outstorename',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Text('配送中心：$instorename',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 第3行：单据金额 + 制单人
              Row(
                children: [
                  Expanded(
                    child: Text('单据金额：$billamt',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Text('制单人：$createname',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              Container(
                height: 1,
                color: const Color(0xFFEBEBEB),
                margin: const EdgeInsets.symmetric(vertical: 8),
              ),
              // 第4行：制单时间
              Text('制单时间：$createtime',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            ],
          ),
        ),
      ),
    );
  }
}
