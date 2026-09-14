import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_return/edit.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_customer.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_salesperson.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';

class PfReturnListPage extends StatefulWidget {
  const PfReturnListPage({super.key});

  @override
  State<PfReturnListPage> createState() => _PfReturnListPageState();
}

class _PfReturnListPageState extends State<PfReturnListPage>
    with SingleTickerProviderStateMixin, LogPageMixin<PfReturnListPage> {
  @override
  String get logPageName => '批发退货列表';

  late TabController _tabController;

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

  String _filterCustid = '';
  String _filterCustname = '';
  String _filterSalesid = '';
  String _filterSalesname = '';
  String _filterCounterid = '';
  String _filterCountername = '';
  String _filterPaystatus = '';

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
    logEnter();
    if (!PermissionUtils.checkPermission('012401', showTip: false)) {
      Toast.show('你无权查看批发退货，请在后台修改权限');
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

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    logQuery(_page);

    final String signflag =
        _statusIndex == 1 ? '0' : (_statusIndex == 2 ? '1' : (_statusIndex == 3 ? '2' : ''));

    return request(HttpApi.pfSellFindList, {
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'billno': _searchController.text.trim(),
      'datetype': '1',
      'signflag': signflag,
      'billtype': 2,
      'notwx': 1,
      'sids': _sids,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      if (_filterCustid.isNotEmpty) 'custid': _filterCustid,
      if (_filterSalesid.isNotEmpty) 'salesid': _filterSalesid,
      if (_filterCounterid.isNotEmpty) 'counterid': _filterCounterid,
      if (_filterPaystatus.isNotEmpty) 'paystatus': _filterPaystatus,
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
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

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
    String tmpCustid = _filterCustid;
    String tmpCustname = _filterCustname;
    String tmpSalesid = _filterSalesid;
    String tmpSalesname = _filterSalesname;
    String tmpCounterid = _filterCounterid;
    String tmpCountername = _filterCountername;
    String tmpPaystatus = _filterPaystatus;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
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
                          // 快速时间选择
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
                                  isFocused: isStartFocused,
                                  onTap: () async {
                                    setSheetState(() => isStartFocused = true);
                                    final picked = await _pickDate(ctx, initial: tmpStart);
                                    if (picked != null) {
                                      if (picked.isAfter(
                                          DateTime(tmpEnd.year, tmpEnd.month, tmpEnd.day))) {
                                        Toast.show('开始日期不能晚于结束日期');
                                      } else {
                                        setSheetState(() {
                                          tmpStart = picked;
                                          tmpActiveQuickTimeId = 4;
                                        });
                                      }
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
                                      if (picked.isBefore(
                                          DateTime(tmpStart.year, tmpStart.month, tmpStart.day))) {
                                        Toast.show('结束日期不能早于开始日期');
                                      } else {
                                        setSheetState(() {
                                          tmpEnd = picked;
                                          tmpActiveQuickTimeId = 4;
                                        });
                                      }
                                    }
                                    setSheetState(() => isEndFocused = false);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildFilterRow(
                            label: '客户名称',
                            value: tmpCustname.isNotEmpty ? tmpCustname : '全部客户',
                            onTap: () async {
                              final result =
                                  await SelectCustomerPage.show(ctx, initialSelectedId: tmpCustid);
                              if (result != null) {
                                setSheetState(() {
                                  tmpCustid = result['custid']?.toString() ?? '';
                                  tmpCustname = result['custname']?.toString() ?? '';
                                });
                              }
                            },
                          ),
                          _buildFilterRow(
                            label: '业务员',
                            value: tmpSalesname.isNotEmpty ? tmpSalesname : '全部业务员',
                            onTap: () async {
                              final result = await SelectSalespersonPage.show(ctx,
                                  initialSelectedId: tmpSalesid);
                              if (result != null) {
                                setSheetState(() {
                                  tmpSalesid = result['salesid']?.toString() ?? '';
                                  tmpSalesname = result['salesname']?.toString() ?? '';
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text('结算状态',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151))),
                          const SizedBox(height: 8),
                          _buildTagGroup(
                            values: ['全部', '待结算', '部分结算', '已结算'],
                            dataValues: ['', '0', '1', '2'],
                            current: tmpPaystatus,
                            onChanged: (v) => setSheetState(() => tmpPaystatus = v),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
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
                                tmpActiveQuickTimeId = 4;
                                tmpCustid = '';
                                tmpCustname = '';
                                tmpSalesid = '';
                                tmpSalesname = '';
                                tmpCounterid = '';
                                tmpCountername = '';
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
                                _filterCustid = tmpCustid;
                                _filterCustname = tmpCustname;
                                _filterSalesid = tmpSalesid;
                                _filterSalesname = tmpSalesname;
                                _filterCounterid = tmpCounterid;
                                _filterCountername = tmpCountername;
                                _filterPaystatus = tmpPaystatus;
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

  Widget _buildTagGroup({
    required List<String> values,
    required List<String> dataValues,
    required String current,
    required ValueChanged<String> onChanged,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: List.generate(values.length, (i) {
        final active = current == dataValues[i];
        return GestureDetector(
          onTap: () => onChanged(dataValues[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF006EFF) : Colors.white,
              border: Border.all(
                color: active ? const Color(0xFF006EFF) : const Color(0xFF999999),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              values[i],
              style: TextStyle(
                fontSize: 13,
                color: active ? Colors.white : const Color(0xFF333333),
              ),
            ),
          ),
        );
      }),
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
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
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

  Future<DateTime?> _pickDate(BuildContext ctx, {required DateTime initial}) async {
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
                        children: List.generate(20, (i) => Center(child: Text('${2020 + i}年'))),
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
                        children: List.generate(12, (i) => Center(child: Text('${i + 1}月'))),
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
                        children: List.generate(31, (i) => Center(child: Text('${i + 1}日'))),
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
          '批发退货',
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
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
                      GestureDetector(
                        onTap: () async {
                          if (!PermissionUtils.checkPermission('012402', showTip: false)) {
                            Toast.show('你无权新增批发退货，请在后台修改权限');
                            return;
                          }
                          logAdd();
                          await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PfReturnEditPage(),
                            ),
                          );
                          if (mounted) _onRefresh();
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
                    Tab(text: '已驳回'),
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
                    child: _PfReturnCard(
                      item: _list[index],
                      onTap: () async {
                        if (!PermissionUtils.checkPermission('012402', showTip: false)) {
                          Toast.show('你无权查看单据明细，请在后台修改权限');
                          return;
                        }
                        logView(_list[index]['billno']?.toString());
                        await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PfReturnEditPage(billData: _list[index]),
                          ),
                        );
                        if (mounted) _onRefresh();
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

/// 批发退货列表卡片
class _PfReturnCard extends StatelessWidget {
  const _PfReturnCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static Color _statusColor(String? signflag) {
    if (signflag == '1') return const Color(0xFF00A870);
    if (signflag == '2') return const Color(0xFFFF9900);
    return const Color(0xFF006EFF);
  }

  static String _statusLabel(String? signflag) {
    if (signflag == '1') return '已审核';
    if (signflag == '2') return '已驳回';
    return '待审核';
  }

  static String _fmtAmt(dynamic v) {
    final num val = v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
    return val.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '-';
    final String custname = item['custname']?.toString() ?? '-';
    final String storename = item['storename']?.toString() ?? '-';
    final String billamt = _fmtAmt(item['billamt']);
    final String createtime = item['createtime']?.toString() ?? '-';
    final String createname = item['createname']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
    final String countername = item['countername']?.toString() ?? '';
    final String paystatusname = item['paystatusname']?.toString() ?? '';

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
              // Row 1: 机构 + 审核状态
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '机构：$storename',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _statusLabel(signflag),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _statusColor(signflag),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Row 2: [退] 单号 + 付款状态
              Row(
                children: [
                  const Text(
                    '[退]',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFF4D4F)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '单号：$billno',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (paystatusname.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF006EFF)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        paystatusname,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF006EFF),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // Row 3: 客户名称
              Text(
                '客户名称：$custname',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Row 4: 仓库
              if (countername.isNotEmpty)
                Text(
                  '仓库：$countername',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              // Row 5: 单据金额
              Text(
                '单据金额：$billamt',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
              ),
              const SizedBox(height: 4),
              // Row 6: 制单人
              Text(
                '制单人：$createname',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Row 7: 制单时间
              Text(
                '制单时间：$createtime',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
