import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/receive/edit.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 收货任务列表页（对齐 Vue wms/receiveTakList/index.vue）
class WmsReceiveListPage extends StatefulWidget {
  const WmsReceiveListPage({super.key});

  @override
  State<WmsReceiveListPage> createState() => _WmsReceiveListPageState();
}

class _WmsReceiveListPageState extends State<WmsReceiveListPage>
    with SingleTickerProviderStateMixin, LogPageMixin<WmsReceiveListPage> {
  @override
  String get logPageName => 'WMS收货列表';

  late TabController _tabController;

  /// 0=全部 1=待收货 2=已收货
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

  // ── 筛选参数（对齐 Vue params）──
  String _filterSupid = '';
  String _filterSupname = '';
  String _filterCreateid = '';
  String _filterCreatename = '';
  final List<Map<String, dynamic>> _filterProducts = [];

  /// 当前选中的快捷时间（0=昨天 1=今天 2=本周 3=本月 4=自定义）
  /// 默认 4（自定义）：对齐 Vue selectTime.vue 组件 prop timeIndex 默认值，
  /// 进入页面/筛选面板时“自定义”高亮并展示近 30 天区间
  int? _activeQuickTimeId = 4;

  /// 当前门店信息
  String _storeId = '';
  String _storeName = '';

  /// 用户是否有查看供应商权限（user.supflag == 1）
  bool _supflag = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    _loadLocalInfo();
    logEnter();
    // 查看权限校验（对齐 Vue permission('011901')）
    if (!PermissionUtils.checkPermission('011901', showTip: false)) {
      Toast.show('你无权查看WMS收货，请在后台修改权限');
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

  /// 读取当前门店 / 用户信息
  void _loadLocalInfo() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeId = storeMap['id']?.toString() ?? '';
        _storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _supflag = userMap['supflag']?.toString() == '1';
      }
    } catch (_) {}
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
    logQuery(_page);

    // signflag：全部=''，待收货='0'，已收货='1'（对齐 Vue tabs key）
    final String signflag = _statusIndex == 1 ? '0' : (_statusIndex == 2 ? '1' : '');

    final params = <String, dynamic>{
      'is_page': 1,
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'billnoflag': '1',
      'billno': _searchController.text.trim(),
      'datetype': '1',
      'signflag': signflag,
      'sids': [_storeId],
      'sidsname': _storeName,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
    };
    if (_filterSupid.isNotEmpty) params['supid'] = _filterSupid;
    if (_filterCreateid.isNotEmpty) params['createid'] = _filterCreateid;
    if (_filterProducts.isNotEmpty) {
      params['productname'] = _filterProducts
          .map((e) => e['productname']?.toString() ?? e['name']?.toString() ?? '')
          .join(',');
      params['prolist'] =
          _filterProducts.map((e) => {'productid': e['productid']?.toString() ?? ''}).toList();
    }

    return request(HttpApi.wmsReceiveTakList, params).then((result) {
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
    await _loadData();
  }

  void _onSearch() {
    FocusScope.of(context).unfocus();
    logSearch(_searchController.text.trim());
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
    logOpenFilter();
    DateTime tmpStart = _startDate;
    DateTime tmpEnd = _endDate;
    int? tmpActiveQuickTimeId = _activeQuickTimeId;
    bool isStartFocused = false;
    bool isEndFocused = false;
    String tmpSupid = _filterSupid;
    String tmpSupname = _filterSupname;
    String tmpCreateid = _filterCreateid;
    String tmpCreatename = _filterCreatename;
    List<Map<String, dynamic>> tmpProducts = List.from(_filterProducts);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
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
                                    final picked = await _pickDate(ctx, initial: tmpStart);
                                    if (picked != null) {
                                      setSheetState(() {
                                        tmpStart = picked;
                                        tmpActiveQuickTimeId = 4;
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
                                    final picked = await _pickDate(ctx, initial: tmpEnd);
                                    if (picked != null) {
                                      setSheetState(() {
                                        tmpEnd = picked;
                                        tmpActiveQuickTimeId = 4;
                                      });
                                    }
                                    setSheetState(() => isEndFocused = false);
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
                              // 对齐 Vue：无查看货商权限时提示
                              if (!_supflag) {
                                Toast.show('没有查看货商权限');
                                return;
                              }
                              final result =
                                  await SelectSupplierPage.show(ctx, initialSelectedId: tmpSupid);
                              if (result != null) {
                                setSheetState(() {
                                  tmpSupid = result['supid']?.toString() ?? '';
                                  // 对齐 Vue selectSupFn：展示纯名称
                                  tmpSupname = result['name']?.toString() ??
                                      result['supname']?.toString() ??
                                      '';
                                });
                              }
                            },
                          ),

                          // ── 商品（多选）──
                          _buildFilterRow(
                            label: '商品',
                            value: tmpProducts.isNotEmpty
                                ? tmpProducts
                                    .map((e) =>
                                        e['productname']?.toString() ?? e['name']?.toString() ?? '')
                                    .join(',')
                                : '全部商品',
                            onTap: () async {
                              final result = await Navigator.push<List<Map<String, dynamic>>>(
                                ctx,
                                MaterialPageRoute(
                                  builder: (_) => SelectProductPage(
                                    multiple: true,
                                    checkboxMode: true,
                                    selectList: tmpProducts,
                                    // 对齐 Vue mergDataFn
                                    mergData: const {
                                      'stockflag': 1,
                                      'cgpriceflag': 1,
                                      'itemstatusin': '1,2,3,4',
                                      'itemtypenot': '5,8',
                                    },
                                  ),
                                ),
                              );
                              if (result != null) {
                                setSheetState(() {
                                  tmpProducts = result;
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
                                  final userid = result['buyerid']?.toString() ?? '';
                                  // 对齐 Vue：userid==0 视为全部
                                  tmpCreateid = userid == '0' ? '' : userid;
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
                              // 对齐 Vue resetFn：恢复默认参数后 selectTimeFn(4) 选中自定义
                              setSheetState(() {
                                final now = DateTime.now();
                                tmpStart = now.subtract(const Duration(days: 30));
                                tmpEnd = now;
                                tmpActiveQuickTimeId = 4;
                                tmpSupid = '';
                                tmpSupname = '';
                                tmpCreateid = '';
                                tmpCreatename = '';
                                tmpProducts = [];
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
                                _filterSupid = tmpSupid;
                                _filterSupname = tmpSupname;
                                _filterCreateid = tmpCreateid;
                                _filterCreatename = tmpCreatename;
                                _filterProducts
                                  ..clear()
                                  ..addAll(tmpProducts);
                                _page = 1;
                                _list = [];
                                _hasMore = true;
                              });
                              Navigator.pop(ctx);
                              logApplyFilter([
                                if (tmpSupname.isNotEmpty) '供应商:$tmpSupname',
                                if (tmpProducts.isNotEmpty) '商品:${tmpProducts.length}项',
                                if (tmpCreatename.isNotEmpty) '制单人:$tmpCreatename',
                              ]);
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

  static Widget _buildDateChip({
    required String label,
    required VoidCallback onTap,
    bool isFocused = false,
  }) {
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
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickDate(
    BuildContext ctx, {
    required DateTime initial,
  }) async {
    DateTime tempDate = initial;
    return showModalBottomSheet<DateTime>(
      context: ctx,
      builder: (c) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              SizedBox(
                height: 50,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(c, tempDate),
                      child: const Text('确定', style: TextStyle(color: Color(0xFF006EFF))),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: tempDate.year - 2020,
                        ),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) {
                          tempDate = DateTime(2020 + i, tempDate.month, tempDate.day);
                        },
                        children: List.generate(
                            20,
                            (i) => Center(
                                child: Text('${2020 + i}年',
                                    style:
                                        const TextStyle(fontSize: 16, color: Color(0xFF333333))))),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: tempDate.month - 1,
                        ),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) {
                          tempDate = DateTime(tempDate.year, i + 1, tempDate.day);
                        },
                        children: List.generate(
                            12,
                            (i) => Center(
                                child: Text('${i + 1}月',
                                    style:
                                        const TextStyle(fontSize: 16, color: Color(0xFF333333))))),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: tempDate.day - 1,
                        ),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) {
                          final maxDay = DateTime(tempDate.year, tempDate.month + 1, 0).day;
                          tempDate =
                              DateTime(tempDate.year, tempDate.month, (i + 1).clamp(1, maxDay));
                        },
                        children: List.generate(
                            31,
                            (i) => Center(
                                child: Text('${i + 1}日',
                                    style:
                                        const TextStyle(fontSize: 16, color: Color(0xFF333333))))),
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
          '收货',
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
                              hintText: '请输入单号/供应商',
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
                  tabs: const [
                    Tab(text: '全部'),
                    Tab(text: '待收货'),
                    Tab(text: '已收货'),
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
                    child: _ReceiveCard(
                      item: _list[index],
                      showSup: _supflag,
                      onTap: () async {
                        // 对齐 Vue：permission('011901', 'tip') && selectItemFn(item)
                        if (!PermissionUtils.checkPermission('011901')) {
                          return;
                        }
                        logView(_list[index]['billno']?.toString());
                        await Navigator.push(
                          context,
                          MaterialPageRoute<dynamic>(
                            builder: (_) => WmsReceiveEditPage(
                              billid: _list[index]['billid']?.toString() ?? '',
                            ),
                          ),
                        );
                        _onRefresh();
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _QuickTimeTag {
  const _QuickTimeTag(this.label, this.id);
  final String label;
  final int id;
}

/// 列表卡片（对齐 Vue index.vue 卡片布局）
class _ReceiveCard extends StatelessWidget {
  const _ReceiveCard({
    required this.item,
    required this.showSup,
    required this.onTap,
  });
  final Map<String, dynamic> item;
  final bool showSup;
  final VoidCallback onTap;

  /// 状态：signflag==1 已收货；billreceiptqty>0 部分收货；否则待收货
  static (String, Color) _status(Map<String, dynamic> item) {
    final signflag = item['signflag']?.toString() ?? '';
    final billreceiptqty = double.tryParse(item['billreceiptqty']?.toString() ?? '') ?? 0;
    if (signflag == '1') return ('已收货', const Color(0xFF00A870));
    if (billreceiptqty > 0) return ('部分收货', const Color(0xFFD54B5A));
    return ('待收货', const Color(0xFFD54B5A));
  }

  @override
  Widget build(BuildContext context) {
    final String supname = item['supname']?.toString() ?? '-';
    final String billno = item['billno']?.toString() ?? '-';
    final String createname = item['createname']?.toString() ?? '-';
    final String createtime = item['createtime']?.toString() ?? '-';
    final String receiptQty = MathUtils.formatDecimal(1, item['billreceiptqty'] ?? 0);
    final String billQty = MathUtils.formatDecimal(1, item['billqty'] ?? 0);
    final (String statusLabel, Color statusColor) = _status(item);

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
                    child: showSup
                        ? Text(
                            '供应商：$supname',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                            overflow: TextOverflow.ellipsis,
                          )
                        : const SizedBox.shrink(),
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
                      '单号：$billno',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '制单人：$createname',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
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
                  Text(
                    '$receiptQty/$billQty',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
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
