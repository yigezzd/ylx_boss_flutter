import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/purchase/cgzc/add.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/review_config_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

class CgzcListPage extends StatefulWidget {
  const CgzcListPage({super.key});

  @override
  State<CgzcListPage> createState() => _CgzcListPageState();
}

class _CgzcListPageState extends State<CgzcListPage>
    with TickerProviderStateMixin, LogPageMixin<CgzcListPage> {
  @override
  String get logPageName => '自采申请单列表';

  TabController? _tabController;

  /// 是否显示"已驳回" tab：统一从 controller 长度派生，
  /// 保证与 TabBar 的 tabs 数量永远一致，杜绝两者失步报错
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

  // ── 筛选参数 ──
  String _storeName = '';
  List<int> _sids = [];

  String _filterCreateid = '';
  String _filterCreatename = '';
  String _filterSupid = '';
  String _filterSupname = '';
  String _filterDhflag = ''; // 收货状态

  int? _activeQuickTimeId = 4; // 对齐小程序 selectTime 组件 timeIndex 默认值 4（自定义）
  String _activeStoreId = '';

  @override
  void initState() {
    super.initState();

    // 同步创建默认3个Tab（不含"已驳回"），确保首次 build 时 TabBar 的 controller 非空，
    // 避免 TabBar 隐式使用 DefaultTabController 触发 _dependencies 断言失败
    _tabController = TabController(length: 3, vsync: this);
    _tabController!.addListener(_onTabChanged);

    final now = DateTime.now();
    _endDate = now;
    _startDate = now.subtract(const Duration(days: 30));

    _scrollController.addListener(_onScroll);
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

  /// 对齐 Vue reviewBillTypeList 动态判断是否显示"已驳回" tab
  Future<void> _loadReviewConfig() async {
    final show = await ReviewConfigUtils.shouldShowRejectedTab('自采申请单');
    // 页面可能已销毁，避免 dispose 后调用 setState
    if (!mounted) return;
    if (show) _applyTabCount(4);
    _startLoadData();
  }

  /// 按需重建 TabController（调整 Tab 数量的唯一入口）
  ///
  /// 数量未变时直接跳过，避免无谓重建；重建时保持当前选中 tab，
  /// 若选中"已驳回"且 tab 被移除则回到"全部"
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

  /// 刷新时重评审批配置，配置变化时自动补上/移除"已驳回" tab
  ///
  /// 对齐 Vue 端依赖 tabbar 切换刷新 reviewBillTypeList 的机制：
  /// 页面停留期间后台开启审批或新增驳回数据时，无需重建页面即可更新 Tab；
  /// 数据加载由调用方（_onRefresh）随后执行
  ///
  /// force 强制拉取最新配置（绕过节流），避免 10s 节流窗口内读到过期缓存
  /// 导致后台新开启审批/新产生驳回数据后，下拉刷新仍看不到"已驳回" tab
  Future<void> _refreshReviewConfig() async {
    final show = await ReviewConfigUtils.shouldShowRejectedTab('自采申请单', force: true);
    if (!mounted) return;
    _applyTabCount(show ? 4 : 3);
  }

  /// 权限校验后加载列表数据
  void _startLoadData() {
    // 查看权限校验
    if (!PermissionUtils.checkPermission('011401', showTip: false)) {
      Toast.show('你无权查看自采申请单，请在后台修改权限');
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

    return request(HttpApi.cgzcFindList, {
      'is_page': 1,
      'cond': '',
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'pagesize': 20,
      'billno': _searchController.text.trim(),
      'datetype': '1',
      'billtype': '1',
      'signflag': signflag,
      'buyerid': '',
      'signid': '',
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'sids': _sids,
      if (_filterCreateid.isNotEmpty) 'createid': _filterCreateid,
      if (_filterSupid.isNotEmpty) 'supid': _filterSupid,
      if (_filterDhflag.isNotEmpty) 'dhflag': _filterDhflag,
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

  // ── 机构选择 ──
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _activeStoreId,
    );
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

  // ── 收货状态选项 ──
  static const List<_DhFlagOption> _dhFlagOptions = [
    _DhFlagOption('全部', ''),
    _DhFlagOption('待处理', '0'),
    _DhFlagOption('待收货', '1'),
    _DhFlagOption('部分收货', '2'),
    _DhFlagOption('已收货', '3'),
    _DhFlagOption('已终止', '4'),
    _DhFlagOption('已过期', '5'),
  ];

  // ── 筛选抽屉 ──
  void _openFilterSheet() {
    DateTime tmpStart = _startDate;
    DateTime tmpEnd = _endDate;
    int? tmpActiveQuickTimeId = _activeQuickTimeId;
    String tmpCreateid = _filterCreateid;
    String tmpCreatename = _filterCreatename;
    String tmpSupid = _filterSupid;
    String tmpSupname = _filterSupname;
    String tmpDhflag = _filterDhflag;

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
                                    setSheetState(() => tmpActiveQuickTimeId = 4);
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
                                        color: active
                                            ? const Color(0xFF006EFF)
                                            : const Color(0xFFDEDEDE)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(tag.label,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: active ? Colors.white : const Color(0xFF333333))),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                          // ── 时间范围 ──
                          const Text('时间范围',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151))),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDateChip(
                                  label: '开始：${_fmtDate(tmpStart)}',
                                  onTap: () async {
                                    final picked =
                                        await showCommonDatePicker(ctx, initial: tmpStart);
                                    if (picked != null) {
                                      setSheetState(() {
                                        tmpStart = picked;
                                        tmpActiveQuickTimeId = 4;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text('—', style: TextStyle(color: Color(0xFF9CA3AF))),
                              ),
                              Expanded(
                                child: _buildDateChip(
                                  label: '结束：${_fmtDate(tmpEnd)}',
                                  onTap: () async {
                                    final picked = await showCommonDatePicker(ctx, initial: tmpEnd);
                                    if (picked != null) {
                                      setSheetState(() {
                                        tmpEnd = picked;
                                        tmpActiveQuickTimeId = 4;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // ── 供应商 ──
                          _buildFilterRow(
                            label: '供应商',
                            value: tmpSupname.isNotEmpty ? tmpSupname : '全部供应商',
                            onTap: () async {
                              final result =
                                  await SelectSupplierPage.show(ctx, initialSelectedId: tmpSupid);
                              if (result != null) {
                                setSheetState(() {
                                  tmpSupid = result['supid']?.toString() ?? '';
                                  tmpSupname = result['supname']?.toString() ?? '';
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
                          const SizedBox(height: 20),
                          // ── 收货状态 ──
                          const Text('收货状态',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151))),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _dhFlagOptions.map((opt) {
                              final active = tmpDhflag == opt.value;
                              return GestureDetector(
                                onTap: () {
                                  setSheetState(() => tmpDhflag = opt.value);
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
                                  child: Text(opt.label,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: active ? Colors.white : const Color(0xFF333333))),
                                ),
                              );
                            }).toList(),
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
                                tmpActiveQuickTimeId = 4; // 对齐默认值：重置后选回"自定义"
                                tmpCreateid = '';
                                tmpCreatename = '';
                                tmpSupid = '';
                                tmpSupname = '';
                                tmpDhflag = '';
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
                                _filterCreateid = tmpCreateid;
                                _filterCreatename = tmpCreatename;
                                _filterSupid = tmpSupid;
                                _filterSupname = tmpSupname;
                                _filterDhflag = tmpDhflag;
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

  static Widget _buildDateChip({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            overflow: TextOverflow.ellipsis),
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
        title: const Text('自采申请单',
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
                      // 机构选择
                      GestureDetector(
                        onTap: _selectStore,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 110),
                          height: 36,
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
                                  _storeName.isNotEmpty ? _storeName : '全部机构',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                      const SizedBox(width: 6),
                      // 新增按钮
                      GestureDetector(
                        onTap: () async {
                          if (!PermissionUtils.checkPermission('011402', showTip: false)) {
                            Toast.show('你无权新增自采申请单，请在后台修改权限');
                            return;
                          }
                          logAdd();
                          await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CgzcAddPage(),
                            ),
                          );
                          _onRefresh();
                        },
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
                    child: _CgzcCard(
                      item: _list[index],
                      onTap: () {
                        if (!PermissionUtils.checkPermission('011402', showTip: false)) {
                          Toast.show('你无权查看单据明细，请在后台修改权限');
                          return;
                        }
                        logView(_list[index]['billno']?.toString());
                        Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CgzcAddPage(billData: _list[index]),
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

/// 快速时间选择标签
class _QuickTimeTag {
  const _QuickTimeTag(this.label, this.id);
  final String label;
  final int id;
}

/// 收货状态选项
class _DhFlagOption {
  const _DhFlagOption(this.label, this.value);
  final String label;
  final String value;
}

/// 列表卡片
class _CgzcCard extends StatelessWidget {
  const _CgzcCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static Color _statusColor(String? signflag) {
    if (signflag == '1') return const Color(0xFF00A870);
    if (signflag == '2') return const Color(0xFFFF9900);
    return const Color(0xFFD54B5A);
  }

  static String _statusLabel(String? signflag) {
    if (signflag == '1') return '已审核';
    if (signflag == '2') return '已驳回';
    return '待审核';
  }

  static String _fmtAmt(dynamic value) {
    final v = double.tryParse(value?.toString() ?? '0') ?? 0.0;
    return v.toStringAsFixed(3);
  }

  static Color _dhFlagColor(String? dhflagname) {
    if (dhflagname == '已收货' || dhflagname == '已终止') {
      return const Color(0xFF4D4D4D);
    }
    return const Color(0xFF006EFF);
  }

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '-';
    final String createname = item['createname']?.toString() ?? '-';
    final String storename = item['storename']?.toString() ?? '';
    final String supname = item['supname']?.toString() ?? '';
    final String billamt = _fmtAmt(item['billamt']);
    final String createtime = item['createtime']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
    final String dhflagname = item['dhflagname']?.toString() ?? '';
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
                            fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                  ),
                  Text(statusLabel,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
                ],
              ),
              const SizedBox(height: 8),
              // 第2行：制单人 + 自采机构
              Row(
                children: [
                  Expanded(
                    child: Text('制单人：$createname',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Text('自采机构：$storename',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 第3行：供应商 + 单据金额
              Row(
                children: [
                  Expanded(
                    child: supname.isNotEmpty
                        ? Text('供应商：$supname',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                            overflow: TextOverflow.ellipsis)
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: Text('单据金额：$billamt',
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
              // 第4行：制单时间 + 收货状态标签
              Row(
                children: [
                  Expanded(
                    child: Text('制单时间：$createtime',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                  ),
                  if (dhflagname.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: _dhFlagColor(dhflagname), width: 0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(dhflagname,
                          style: TextStyle(fontSize: 10, color: _dhFlagColor(dhflagname))),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
