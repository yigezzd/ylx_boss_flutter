import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/purchase/instore/add.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/review_config_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

class PurchaseInstoreListPage extends StatefulWidget {
  const PurchaseInstoreListPage({super.key});

  @override
  State<PurchaseInstoreListPage> createState() => _PurchaseInstoreListPageState();
}

class _PurchaseInstoreListPageState extends State<PurchaseInstoreListPage>
    with TickerProviderStateMixin {
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

  String _filterCounterid = '';
  String _filterCountername = '';
  String _filterSupid = '';
  String _filterSupname = '';
  String _filterCreateid = '';
  String _filterCreatename = '';
  String _filterRetstatus = '';
  String _filterPaystatus = '';

  int? _activeQuickTimeId = 4; // 快速时间标签选中状态，对齐小程序 selectTime 组件 timeIndex 默认值 4（自定义）
  String _activeStoreId = ''; // 当前机构ID（用于机构选择回显）

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
    _loadStoreName();

    // 操作审计：进入页面（先于列表查询，保证轨迹顺序）
    FileLogWriter.instance.writeOperationLog('采购入库列表', '进入页面');
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

  /// 默认选中"全部机构"，不从本地存储加载
  void _loadStoreName() {
    _storeName = '';
    _sids = [];
  }

  /// 对齐 Vue reviewBillTypeList 动态判断是否显示"已驳回" tab
  Future<void> _loadReviewConfig() async {
    final show = await ReviewConfigUtils.shouldShowRejectedTab('采购入库单');
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
    final show = await ReviewConfigUtils.shouldShowRejectedTab('采购入库单', force: true);
    if (!mounted) return;
    _applyTabCount(show ? 4 : 3);
  }

  /// 权限校验后加载列表数据
  void _startLoadData() {
    // 查看权限校验
    if (!PermissionUtils.checkPermission('011701', showTip: false)) {
      Toast.show('你无权查看采购入库，请在后台修改权限');
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);

    // 操作审计：查询列表（记录页码，便于追踪翻页操作）
    FileLogWriter.instance.writeOperationLog('采购入库列表', '查询列表', '第$_page页');

    // 审核状态：0=待审核 1=已审核 2=已驳回，空=全部
    String signflag = '';
    if (_statusIndex == 1) {
      signflag = '0';
    } else if (_statusIndex == 2) {
      signflag = '1';
    } else if (_showRejectedTab && _statusIndex == 3) {
      signflag = '2';
    }

    return request('/cgstockin/findList', {
      'is_page': 1,
      'cond': '',
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'billno': _searchController.text.trim(),
      'datetype': '1',
      'signflag': signflag,
      'supid': _filterSupid,
      'suptype': '',
      'retstatus': _filterRetstatus,
      'clienttype': '',
      'paystatus': _filterPaystatus,
      'buyerid': '',
      'signid': '',
      'billtype': 1,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'sids': _sids,
      if (_filterCounterid.isNotEmpty) 'counterid': _filterCounterid,
      if (_filterCreateid.isNotEmpty) 'createid': _filterCreateid,
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
    await _refreshReviewConfig();
    await _loadData();
  }

  // ── 机构选择（底部抽屉）──
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
    setState(() {}); // 刷新清除按钮显示状态
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
    // 操作审计：打开筛选
    FileLogWriter.instance.writeOperationLog('采购入库列表', '打开筛选');

    // 临时变量，确认后才写入
    DateTime tmpStart = _startDate;
    DateTime tmpEnd = _endDate;
    int? tmpActiveQuickTimeId = _activeQuickTimeId;
    bool isStartFocused = false;
    bool isEndFocused = false;
    String tmpCounterid = _filterCounterid;
    String tmpCountername = _filterCountername;
    String tmpSupid = _filterSupid;
    String tmpSupname = _filterSupname;
    String tmpCreateid = _filterCreateid;
    String tmpCreatename = _filterCreatename;
    String tmpRetstatus = _filterRetstatus;
    String tmpPaystatus = _filterPaystatus;

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
                              color: Color(0xFF111827),
                            ),
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
                  // 内容
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
                                    // 自定义：高亮"自定义"按钮，不改变日期
                                    setSheetState(() {
                                      tmpActiveQuickTimeId = 4;
                                    });
                                    return;
                                  }
                                  final now = DateTime.now();
                                  DateTime start = now;
                                  DateTime end = now;
                                  switch (tag.id) {
                                    case 0: // 昨天
                                      start = now.subtract(const Duration(days: 1));
                                      end = start;
                                      break;
                                    case 1: // 今天
                                      break;
                                    case 2: // 本周
                                      final weekday = now.weekday;
                                      start = now.subtract(Duration(days: weekday - 1));
                                      end = start.add(const Duration(days: 6));
                                      break;
                                    case 3: // 本月
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
                          const SizedBox(height: 10),
                          // ── 时间范围 ──
                          const Text(
                            '时间范围',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDateChip(
                                  label: '开始：${_fmtDate(tmpStart)}',
                                  isFocused: isStartFocused,
                                  onTap: () async {
                                    setSheetState(() => isStartFocused = true);
                                    final picked = await showCommonDatePicker(
                                      ctx,
                                      initial: tmpStart,
                                    );
                                    if (picked != null) {
                                      setSheetState(() {
                                        tmpStart = picked;
                                        tmpActiveQuickTimeId = 4; // 手动选日期→高亮"自定义"
                                      });
                                    }
                                    setSheetState(() => isStartFocused = false);
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
                                  isFocused: isEndFocused,
                                  onTap: () async {
                                    setSheetState(() => isEndFocused = true);
                                    final picked = await showCommonDatePicker(
                                      ctx,
                                      initial: tmpEnd,
                                    );
                                    if (picked != null) {
                                      setSheetState(() {
                                        tmpEnd = picked;
                                        tmpActiveQuickTimeId = 4; // 手动选日期→高亮"自定义"
                                      });
                                    }
                                    setSheetState(() => isEndFocused = false);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── 仓库（底部抽屉） ──
                          _buildFilterRow(
                            label: '仓库',
                            value: tmpCountername.isNotEmpty ? tmpCountername : '全部仓库',
                            onTap: () async {
                              final result = await SelectWarehousePage.show(ctx,
                                  bsid: _sids.isNotEmpty ? _sids.first : null,
                                  initialSelectedId: tmpCounterid);
                              if (result != null) {
                                setSheetState(() {
                                  tmpCounterid = result['counterid']?.toString() ?? '';
                                  tmpCountername = result['countername']?.toString() ?? '';
                                });
                              }
                            },
                          ),

                          // ── 供应商（底部抽屉） ──
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

                          // ── 制单人（底部抽屉） ──
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

                          // ── 入库状态 ──
                          const Text(
                            '入库状态',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              const _FilterTag('全部', ''),
                              const _FilterTag('待处理', '0'),
                              const _FilterTag('已入库', '1'),
                              const _FilterTag('部分退货', '2'),
                              const _FilterTag('全部退货', '3'),
                            ].map((tag) {
                              final active = tmpRetstatus == tag.value;
                              return GestureDetector(
                                onTap: () => setSheetState(() => tmpRetstatus = tag.value),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active ? const Color(0xFF006EFF) : Colors.white,
                                    border: Border.all(
                                      color: active
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFF999999),
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tag.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: active ? Colors.white : const Color(0xFF333333),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),

                          // ── 结算状态 ──
                          const Text(
                            '结算状态',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              const _FilterTag('全部', ''),
                              const _FilterTag('待结算', '0'),
                              const _FilterTag('部分结算', '1'),
                              const _FilterTag('已结清', '2'),
                            ].map((tag) {
                              final active = tmpPaystatus == tag.value;
                              return GestureDetector(
                                onTap: () => setSheetState(() => tmpPaystatus = tag.value),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active ? const Color(0xFF006EFF) : Colors.white,
                                    border: Border.all(
                                      color: active
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFF999999),
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tag.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: active ? Colors.white : const Color(0xFF333333),
                                    ),
                                  ),
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
                                tmpCounterid = '';
                                tmpCountername = '';
                                tmpSupid = '';
                                tmpSupname = '';
                                tmpCreateid = '';
                                tmpCreatename = '';
                                tmpRetstatus = '';
                                tmpPaystatus = '';
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
                                _startDate = tmpStart;
                                _endDate = tmpEnd;
                                _activeQuickTimeId = tmpActiveQuickTimeId;
                                _filterCounterid = tmpCounterid;
                                _filterCountername = tmpCountername;
                                _filterSupid = tmpSupid;
                                _filterSupname = tmpSupname;
                                _filterCreateid = tmpCreateid;
                                _filterCreatename = tmpCreatename;
                                _filterRetstatus = tmpRetstatus;
                                _filterPaystatus = tmpPaystatus;
                                _page = 1;
                                _list = [];
                                _hasMore = true;
                              });
                              // 操作审计：应用筛选（仅记录非默认条件）
                              final conditions = <String>[];
                              if (tmpCountername.isNotEmpty) conditions.add('仓库=$tmpCountername');
                              if (tmpSupname.isNotEmpty) conditions.add('供应商=$tmpSupname');
                              if (tmpCreatename.isNotEmpty) conditions.add('制单人=$tmpCreatename');
                              if (tmpRetstatus.isNotEmpty) conditions.add('入库状态=$tmpRetstatus');
                              if (tmpPaystatus.isNotEmpty) conditions.add('结算状态=$tmpPaystatus');
                              FileLogWriter.instance.writeOperationLog(
                                '采购入库列表',
                                conditions.isEmpty ? '重置筛选' : '应用筛选',
                                conditions.isEmpty ? null : conditions.join(' '),
                              );
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

  static Widget _buildDateChip(
      {required String label, required VoidCallback onTap, bool isFocused = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: isFocused ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          overflow: TextOverflow.ellipsis,
        ),
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
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
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
        title: const Text(
          '采购入库',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                // ── 工具栏：机构选择 + 搜索 + 筛选 + 新增 ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      // 机构选择下拉
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
                          if (!PermissionUtils.checkPermission('011702', showTip: false)) {
                            Toast.show('你无权新增采购入库，请在后台修改权限');
                            return;
                          }
                          // 操作审计：点击新增
                          FileLogWriter.instance.writeOperationLog('采购入库列表', '点击新增');
                          await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PurchaseInstoreAddPage(),
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
                // ── Tab 栏
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
                        Text(
                          '暂无数据',
                          style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                        ),
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
                              child: Text(
                                '没有更多数据',
                                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                              ),
                            ),
                          );
                  }
                  return RepaintBoundary(
                    child: _InstoreCard(
                      item: _list[index],
                      onTap: () {
                        // 操作审计：查看单据详情
                        if (!PermissionUtils.checkPermission('011702', showTip: false)) {
                          Toast.show('你无权查看单据明细，请在后台修改权限');
                          return;
                        }
                        final billno = _list[index]['billno']?.toString() ?? '';
                        FileLogWriter.instance.writeOperationLog(
                          '采购入库列表',
                          '查看单据',
                          billno.isNotEmpty ? '单号: $billno' : null,
                        );
                        Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PurchaseInstoreAddPage(billData: _list[index]),
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

/// 筛选标签数据
class _FilterTag {
  const _FilterTag(this.label, this.value);
  final String label;
  final String value;
}

/// 快速时间选择标签
class _QuickTimeTag {
  const _QuickTimeTag(this.label, this.id);
  final String label;
  final int id;
}

/// 列表卡片
class _InstoreCard extends StatelessWidget {
  const _InstoreCard({required this.item, required this.onTap});
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

  static Color _retStatusColor(String? retstatusname) {
    if (retstatusname == '待处理' || retstatusname == '部分退货' || retstatusname == '全部退货') {
      return const Color(0xFF4D4D4D);
    }
    return const Color(0xFF006EFF);
  }

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '-';
    final String createname = item['createname']?.toString() ?? '-';
    final String storename = item['storename']?.toString() ?? '-';
    final String supname = item['supname']?.toString() ?? '-';
    final String billamt = item['billamt']?.toString() ?? '0.00';
    final String createtime = item['createtime']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
    final String retstatusname = item['retstatusname']?.toString() ?? '';
    final Color statusColor = _statusColor(signflag);
    final String statusLabel = _statusLabel(signflag);
    final Color retColor = _retStatusColor(retstatusname);

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
                      billno,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '制单人：$createname',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '入库机构：$storename',
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
                      '供应商：$supname',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '单据金额：$billamt',
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '制单时间：$createtime',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (retstatusname.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: retColor),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        retstatusname,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: retColor,
                        ),
                      ),
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
