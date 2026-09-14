import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/purchase/instore/add.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';

String _fmtDecimal(int n, dynamic value) {
  final v = double.tryParse(value?.toString() ?? '0') ?? 0.0;
  return v.toStringAsFixed(n);
}

class PurchaseInstoreSearchPage extends StatefulWidget {
  const PurchaseInstoreSearchPage({super.key});

  @override
  State<PurchaseInstoreSearchPage> createState() => _PurchaseInstoreSearchPageState();
}

class _PurchaseInstoreSearchPageState extends State<PurchaseInstoreSearchPage> {
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  final List<Map<String, dynamic>> _list = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  /// 路由参数
  bool _isSelect = false;
  String _emitFnName = '';
  Map<String, dynamic> _mergData = const {};

  // ── 筛选参数 ──
  DateTime? _startDate;
  DateTime? _endDate;
  String _filterSupid = '';
  String _filterSupname = '';

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _isSelect = args['isSelect'] == true;
        _emitFnName = args['emitFnName']?.toString() ?? '';
        final mergData = args['mergData'];
        if (mergData is Map<String, dynamic>) {
          _mergData = mergData;
        }
      }
      final now = DateTime.now();
      _startDate = now;
      _endDate = now;
      if (_isSelect) {
        _loadData();
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
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

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);

    return request(HttpApi.purchaseInstoreList, {
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'billno': _searchController.text.trim(),
      'is_page': 1,
      'pagesize': 20,
      if (_startDate != null) 'starttime': '${_fmtDate(_startDate!)} 00:00:00',
      if (_endDate != null) 'endtime': '${_fmtDate(_endDate!)} 23:59:59',
      if (_filterSupid.isNotEmpty) 'supid': _filterSupid,
      if (_mergData.isNotEmpty) ..._mergData,
    }).then((result) {
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list.clear();
          _list.addAll(rows);
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= 20;
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

  void _onSearch() {
    FocusScope.of(context).unfocus();
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _page = 1;
      _hasMore = true;
      _loadData();
    });
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _openFilterSheet() {
    DateTime tmpStart = _startDate ?? DateTime.now();
    DateTime tmpEnd = _endDate ?? DateTime.now();
    String tmpSupid = _filterSupid;
    String tmpSupname = _filterSupname;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: 400,
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
                          const Text('时间范围',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151))),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDateBtn(
                                  label: '开始：${_fmtDate(tmpStart)}',
                                  onTap: () async {
                                    final picked = await _pickDate(ctx, initial: tmpStart);
                                    if (picked != null) {
                                      setSheetState(() => tmpStart = picked);
                                    }
                                  },
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text('—', style: TextStyle(color: Color(0xFF9CA3AF))),
                              ),
                              Expanded(
                                child: _buildDateBtn(
                                  label: '结束：${_fmtDate(tmpEnd)}',
                                  onTap: () async {
                                    final picked = await _pickDate(ctx, initial: tmpEnd);
                                    if (picked != null) {
                                      setSheetState(() => tmpEnd = picked);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
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
                                tmpStart = now;
                                tmpEnd = now;
                                tmpSupid = '';
                                tmpSupname = '';
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
                                _filterSupid = tmpSupid;
                                _filterSupname = tmpSupname;
                                _page = 1;
                                _hasMore = true;
                              });
                              Navigator.pop(ctx);
                              _onRefresh();
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

  static Widget _buildDateBtn({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
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

  String _statusLabel(String? signflag) {
    if (signflag == '1') return '已审核';
    return '待审核';
  }

  Color _statusColor(String? signflag) {
    if (signflag == '1') return const Color(0xFF00A870);
    return const Color(0xFFD54B5A);
  }

  Color _retStatusColor(String? retstatusname) {
    if (retstatusname == '待处理' || retstatusname == '部分退货' || retstatusname == '全部退货') {
      return const Color(0xFF4D4D4D);
    }
    return const Color(0xFF006EFF);
  }

  void _onItemTap(Map<String, dynamic> item) {
    if (_isSelect) {
      Navigator.pop(context, item);
    } else {
      final billid = item['billid']?.toString();
      if (billid != null && billid.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PurchaseInstoreAddPage(billData: item),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSelect ? '选择入库单' : '搜索';
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
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          // 搜索栏
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
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
                        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                        prefixIconConstraints: const BoxConstraints(minWidth: 32),
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
                if (_isSelect) ...[
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
                ],
              ],
            ),
          ),
          // 列表
          Expanded(
            child: RefreshIndicator(
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
                              Text('暂无数据',
                                  style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
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
                          child: _InstoreSearchCard(
                            item: _list[index],
                            onTap: () => _onItemTap(_list[index]),
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
}

class _InstoreSearchCard extends StatelessWidget {
  const _InstoreSearchCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static Color _statusColor(String? signflag) {
    if (signflag == '1') return const Color(0xFF00A870);
    return const Color(0xFFD54B5A);
  }

  static String _statusLabel(String? signflag) {
    if (signflag == '1') return '已审核';
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
    final String supname = item['supname']?.toString() ?? '-';
    final String storename = item['storename']?.toString() ?? '-';
    final String billamt = _fmtDecimal(3, item['billamt']);
    final String createtime = item['createtime']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
    final String retstatusname = item['retstatusname']?.toString() ?? '';

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
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '入库机构：$storename',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '单据金额：$billamt',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    ),
                  ),
                  if (retstatusname.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: _retStatusColor(retstatusname)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        retstatusname,
                        style: TextStyle(
                          fontSize: 11,
                          color: _retStatusColor(retstatusname),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '制单时间：$createtime',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
