import 'dart:async';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_customer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/cust_category_picker.dart';

class OrderSumListPage extends StatefulWidget {
  const OrderSumListPage({super.key});

  @override
  State<OrderSumListPage> createState() => _OrderSumListPageState();
}

class _OrderSumListPageState extends State<OrderSumListPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int _currentTab = 0;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];

  late DateTime _startDate;
  late DateTime _endDate;

  Timer? _debounce;

  // ── 筛选参数 ──
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';

  String _filterCusttypeid = '';
  String _filterCusttypename = '';
  String _filterCustid = '';
  String _filterCustname = '';
  String _filterName = '';
  String _filterTypeid = '';
  String _filterTypename = '';

  int? _activeQuickTimeId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index;
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

    if (!PermissionUtils.checkPermission('012501', showTip: false)) {
      Toast.show('你无权查看订货汇总，请在后台修改权限');
      return;
    }
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtNum(dynamic value, int n) {
    final v = double.tryParse(value?.toString() ?? '0') ?? 0.0;
    return v.toStringAsFixed(n);
  }

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);

    final api = _currentTab == 0 ? HttpApi.pfSelectOrderStoreTotal : HttpApi.pfSelectOrderTotal;

    return request(api, {
      'page': _page,
      'pagesize': 20,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'field': 'barcode',
      'type': 'asc',
      if (_sids.isNotEmpty) 'sids': _sids,
      if (_currentTab == 0 && _filterCusttypeid.isNotEmpty) 'custtypeid': _filterCusttypeid,
      if (_currentTab == 0 && _filterCusttypename.isNotEmpty) 'custtypename': _filterCusttypename,
      if (_currentTab == 0 && _filterCustid.isNotEmpty) 'custid': _filterCustid,
      if (_currentTab == 0 && _filterCustname.isNotEmpty) 'custname': _filterCustname,
      'name': _filterName,
      if (_currentTab == 1 && _filterTypeid.isNotEmpty) 'typeid': _filterTypeid,
      if (_currentTab == 1 && _filterTypename.isNotEmpty) 'typename': _filterTypename,
    }).then((result) {
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?) ?? [];
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

  void _openFilterSheet() {
    DateTime tmpStart = _startDate;
    DateTime tmpEnd = _endDate;
    int? tmpActiveQuickTimeId = _activeQuickTimeId ?? 4; // 初始化默认选中「自定义」（对齐 lxAss），已选过则保持
    bool isStartFocused = false;
    bool isEndFocused = false;
    String tmpCusttypeid = _filterCusttypeid;
    String tmpCusttypename = _filterCusttypename;
    String tmpCustid = _filterCustid;
    String tmpCustname = _filterCustname;
    String tmpStoreName = _storeName;
    List<int> tmpSids = List.from(_sids);
    String tmpTypeid = _filterTypeid;
    String tmpTypename = _filterTypename;
    String tmpName = _filterName;

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
                          // 时间
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
                          // 门店
                          _buildFilterRow(
                            label: '门店',
                            value: tmpStoreName.isNotEmpty ? tmpStoreName : '全部',
                            onTap: () async {
                              final result = await SelectStorePage.show(
                                ctx,
                                showAll: true,
                                initialSelectedId:
                                    tmpSids.isNotEmpty ? tmpSids.first.toString() : '',
                              );
                              if (result != null) {
                                setSheetState(() {
                                  final storeId = result['storeid']?.toString() ?? '';
                                  tmpSids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
                                  tmpStoreName = result['storename']?.toString() ?? '';
                                });
                              }
                            },
                          ),
                          if (_currentTab == 0) ...[
                            // 客户分类
                            _buildFilterRow(
                              label: '客户分类',
                              value: tmpCusttypename.isNotEmpty ? tmpCusttypename : '全部',
                              onTap: () {
                                _selectCustType(ctx, (id, name) {
                                  setSheetState(() {
                                    tmpCusttypeid = id;
                                    tmpCusttypename = name;
                                  });
                                });
                              },
                            ),
                            // 客户
                            _buildFilterRow(
                              label: '客户',
                              value: tmpCustname.isNotEmpty ? tmpCustname : '全部',
                              onTap: () async {
                                final result = await SelectCustomerPage.show(ctx,
                                    initialSelectedId: tmpCustid);
                                if (result != null) {
                                  setSheetState(() {
                                    tmpCustid = result['custid']?.toString() ?? '';
                                    tmpCustname = result['custname']?.toString() ?? '';
                                  });
                                }
                              },
                            ),
                          ],
                          if (_currentTab == 1) ...[
                            // 商品分类
                            _buildFilterRow(
                              label: '商品分类',
                              value: tmpTypename.isNotEmpty ? tmpTypename : '全部',
                              onTap: () {
                                _selectProType(ctx, (id, name) {
                                  setSheetState(() {
                                    tmpTypeid = id;
                                    tmpTypename = name;
                                  });
                                });
                              },
                            ),
                          ],
                          // 商品搜索（两个Tab共用）
                          _buildInputRow(
                            label: '商品搜索',
                            value: tmpName,
                            onChanged: (v) => tmpName = v,
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
                                tmpCusttypeid = '';
                                tmpCusttypename = '';
                                tmpCustid = '';
                                tmpCustname = '';
                                tmpStoreName = '';
                                tmpSids = [];
                                tmpTypeid = '';
                                tmpTypename = '';
                                tmpName = '';
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
                                _filterCusttypeid = tmpCusttypeid;
                                _filterCusttypename = tmpCusttypename;
                                _filterCustid = tmpCustid;
                                _filterCustname = tmpCustname;
                                _filterTypeid = tmpTypeid;
                                _filterTypename = tmpTypename;
                                _filterName = tmpName;
                                _storeName = tmpStoreName;
                                _sids = tmpSids;
                                _activeStoreId = tmpSids.isNotEmpty ? tmpSids.first.toString() : '';
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

  Future<void> _selectCustType(BuildContext ctx, void Function(String, String) onResult) async {
    final result = await CustCategoryPicker.show(ctx);
    if (result != null) {
      onResult(result['custtypeid'] ?? '', result['custtypename'] ?? '');
    }
  }

  Future<void> _selectProType(BuildContext ctx, void Function(String, String) onResult) async {
    final result = await CustCategoryPicker.show(
      ctx,
      apiPath: 'bi/type/getTypeListandCode',
      title: '选择商品分类',
      idKey: 'typeid',
      nameKey: 'typename',
    );
    if (result != null) {
      onResult(result['typeid'] ?? '', result['typename'] ?? '');
    }
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

  static Widget _buildInputRow({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
            child: TextField(
              controller: TextEditingController.fromValue(
                TextEditingValue(text: value),
              ),
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: '输入商品名称/编码',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
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
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '订货汇总',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Align(
              child: GestureDetector(
                onTap: _openFilterSheet,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDEDEDE)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child:
                      const BossSvgIcon(svgFile: 'fliter.svg', size: 22, color: Color(0xFF666666)),
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF006EFF),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFF006EFF),
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: const [
            Tab(text: '按客户'),
            Tab(text: '按商品'),
          ],
        ),
      ),
      body: Column(children: [
        Expanded(
          child: _buildTableArea(),
        ),
      ]),
    );
  }

  // ──────────────────── 表格区域 ────────────────────
  Widget _buildTableArea() {
    const headerStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF374151),
    );

    if (_list.isEmpty && !_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }

    const cellPad = EdgeInsets.symmetric(horizontal: 12);
    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    const amountStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF333333));

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100 &&
            !_loading &&
            _hasMore) {
          _page++;
          _loadData();
        }
        return false;
      },
      child: RefreshIndicator(
        color: const Color(0xFF006EFF),
        onRefresh: _onRefresh,
        child: DataTable2(
          fixedLeftColumns: 1,
          minWidth: _currentTab == 0 ? 680 : 550,
          horizontalMargin: 0,
          columnSpacing: 0,
          dataRowHeight: 52,
          headingRowHeight: 44,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
          border: const TableBorder(
            horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
            verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
          ),
          columns: _currentTab == 0
              ? [
                  const DataColumn2(
                    fixedWidth: 130,
                    label: Padding(
                      padding: cellPad,
                      child: Text('客户名称', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    size: ColumnSize.L,
                    label: Padding(
                      padding: cellPad,
                      child: Text('商品信息', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    fixedWidth: 100,
                    numeric: true,
                    label: Padding(
                      padding: cellPad,
                      child: Text('订货数量', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    fixedWidth: 110,
                    numeric: true,
                    label: Padding(
                      padding: cellPad,
                      child: Text('订货金额', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    fixedWidth: 90,
                    numeric: true,
                    label: Padding(
                      padding: cellPad,
                      child: Text('现库存', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    fixedWidth: 90,
                    numeric: true,
                    label: Padding(
                      padding: cellPad,
                      child: Text('差异数量', style: headerStyle),
                    ),
                  ),
                ]
              : [
                  const DataColumn2(
                    size: ColumnSize.L,
                    label: Padding(
                      padding: cellPad,
                      child: Text('商品信息', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    fixedWidth: 100,
                    numeric: true,
                    label: Padding(
                      padding: cellPad,
                      child: Text('订货数量', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    fixedWidth: 110,
                    numeric: true,
                    label: Padding(
                      padding: cellPad,
                      child: Text('订货金额', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    fixedWidth: 90,
                    numeric: true,
                    label: Padding(
                      padding: cellPad,
                      child: Text('现库存', style: headerStyle),
                    ),
                  ),
                  const DataColumn2(
                    fixedWidth: 90,
                    numeric: true,
                    label: Padding(
                      padding: cellPad,
                      child: Text('差异数量', style: headerStyle),
                    ),
                  ),
                ],
          rows: _buildDataRows(cellPad, cellStyle, amountStyle),
        ),
      ),
    );
  }

  // ──────────────────── 数据行构建 ────────────────────
  List<DataRow> _buildDataRows(
    EdgeInsets cellPad,
    TextStyle cellStyle,
    TextStyle amountStyle,
  ) {
    final rows = <DataRow>[];
    for (var i = 0; i < _list.length; i++) {
      final item = _list[i];
      final isOdd = i.isOdd;

      final custname = item['custname']?.toString() ?? '';
      final productname = item['productname']?.toString() ?? '';
      final qty = _fmtNum(item['qty'], 1);
      final amt = _fmtNum(item['amt'], 3);
      final stockqty = _fmtNum(item['stockqty'], 1);
      final cqty = _fmtNum(item['cqty'], 1);

      rows.add(
        DataRow2(
          decoration: BoxDecoration(
            color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
            border: const Border(
              right: BorderSide(color: Color(0xFFE1E9F3)),
            ),
          ),
          cells: [
            if (_currentTab == 0)
              DataCell(Padding(
                padding: cellPad,
                child: Text(custname,
                    style: cellStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              )),
            DataCell(Padding(
              padding: cellPad,
              child: Text(productname,
                  style: cellStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            )),
            DataCell(Padding(
              padding: cellPad,
              child: Align(alignment: Alignment.centerRight, child: Text(qty, style: amountStyle)),
            )),
            DataCell(Padding(
              padding: cellPad,
              child: Align(alignment: Alignment.centerRight, child: Text(amt, style: amountStyle)),
            )),
            DataCell(Padding(
              padding: cellPad,
              child: Align(
                  alignment: Alignment.centerRight, child: Text(stockqty, style: amountStyle)),
            )),
            DataCell(Padding(
              padding: cellPad,
              child: Align(alignment: Alignment.centerRight, child: Text(cqty, style: amountStyle)),
            )),
          ],
        ),
      );
    }

    if (_loading) {
      final cellCount = _currentTab == 0 ? 6 : 5;
      rows.add(DataRow2(
        cells: [
          const DataCell(SizedBox(
            height: 44,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
              ),
            ),
          )),
          for (var j = 1; j < cellCount; j++) DataCell.empty,
        ],
      ));
    }

    return rows;
  }
}

class _QuickTimeTag {
  const _QuickTimeTag(this.label, this.id);
  final String label;
  final int id;
}
