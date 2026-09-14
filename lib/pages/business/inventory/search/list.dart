import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_brand.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart';
import 'package:flutter_deer/pages/business/inventory/search/detail.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:sp_util/sp_util.dart';

class InventorySearchListPage extends StatefulWidget {
  const InventorySearchListPage({super.key});

  @override
  State<InventorySearchListPage> createState() => _InventorySearchListPageState();
}

class _InventorySearchListPageState extends State<InventorySearchListPage> {
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ── 机构 ──
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';

  // ── 筛选参数 ──
  String _filterCounterid = '';
  String _filterCountername = '';
  String _filterSupid = '';
  String _filterSupname = '';
  String _filterBrandname = '';
  int _qtyflag = 1; // 1=显示零库存 0=不显示
  List<Map<String, dynamic>> _filterTypelist = []; // [{typeid, name}]

  @override
  void initState() {
    super.initState();
    _loadDefaultStore();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _loadDefaultStore() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        final storeId = storeMap['id']?.toString() ?? '';
        final storeName = storeMap['name']?.toString() ?? '';
        _activeStoreId = storeId;
        _storeName = storeName;
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
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

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);

    final typeId = _filterTypelist
        .map((e) => e['typeid']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .join(',');

    return request(HttpApi.stockproductGetProStockTotal, {
      'is_page': 1,
      'cond': _searchController.text.trim(),
      'page': _page,
      'pagesize': 20,
      'sids': _sids,
      'supid': _filterSupid,
      'supname': _filterSupname,
      'brandname': _filterBrandname,
      'qtyflag': _qtyflag,
      'counterid': _filterCounterid,
      'countername': _filterCountername,
      'typeid': typeId,
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
    String tmpCounterid = _filterCounterid;
    String tmpCountername = _filterCountername;
    String tmpSupid = _filterSupid;
    String tmpSupname = _filterSupname;
    String tmpBrandname = _filterBrandname;
    int tmpQtyflag = _qtyflag;
    List<Map<String, dynamic>> tmpTypelist = List.from(_filterTypelist);

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
                          // ── 仓库 ──
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

                          // ── 商品分类（多选） ──
                          _buildFilterRow(
                            label: '商品分类',
                            value: tmpTypelist.isEmpty
                                ? '全部分类'
                                : tmpTypelist.map((e) => e['name']?.toString() ?? '').join('|'),
                            onTap: () async {
                              final selectedIds = tmpTypelist
                                  .map((e) => e['typeid']?.toString())
                                  .whereType<String>()
                                  .where((e) => e.isNotEmpty)
                                  .toList();
                              final result = await Navigator.push<List<Map<String, dynamic>>>(
                                ctx,
                                MaterialPageRoute(
                                  builder: (_) => CategoryListPage(
                                    isSelect: true,
                                    isMultiSelect: true,
                                    showAll: true,
                                    initialSelectedIds: selectedIds,
                                  ),
                                ),
                              );
                              if (result != null) {
                                setSheetState(() {
                                  tmpTypelist = result.map((item) {
                                    return {
                                      'typeid': item['typeid']?.toString() ?? '',
                                      'name': item['name']?.toString() ?? '',
                                    };
                                  }).toList();
                                });
                              }
                            },
                          ),

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

                          // ── 品牌 ──
                          _buildFilterRow(
                            label: '品牌',
                            value: tmpBrandname.isNotEmpty ? tmpBrandname : '全部品牌',
                            onTap: () async {
                              final result =
                                  await SelectBrandPage.show(ctx, initialSelectedId: tmpBrandname);
                              if (result != null) {
                                setSheetState(() {
                                  tmpBrandname = result['name']?.toString() ?? '';
                                });
                              }
                            },
                          ),

                          const SizedBox(height: 20),

                          // ── 显示零库存 ──
                          const Text(
                            '显示零库存',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            children: [
                              _buildQtyTag(
                                  '显示', 1, tmpQtyflag, (v) => setSheetState(() => tmpQtyflag = v)),
                              _buildQtyTag(
                                  '不显示', 0, tmpQtyflag, (v) => setSheetState(() => tmpQtyflag = v)),
                            ],
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
                                tmpCounterid = '';
                                tmpCountername = '';
                                tmpSupid = '';
                                tmpSupname = '';
                                tmpBrandname = '';
                                tmpQtyflag = 1;
                                tmpTypelist = [];
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
                                _filterCounterid = tmpCounterid;
                                _filterCountername = tmpCountername;
                                _filterSupid = tmpSupid;
                                _filterSupname = tmpSupname;
                                _filterBrandname = tmpBrandname;
                                _qtyflag = tmpQtyflag;
                                _filterTypelist = tmpTypelist;
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

  static Widget _buildQtyTag(
    String label,
    int value,
    int current,
    ValueChanged<int> onTap,
  ) {
    final active = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
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
          label,
          style: TextStyle(
            fontSize: 13,
            color: active ? Colors.white : const Color(0xFF333333),
          ),
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
        titleSpacing: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '库存查询',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
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
                        onChanged: (_) {
                          setState(() {}); // 刷新以显示/隐藏清除按钮
                          _onSearchChanged();
                        },
                        decoration: InputDecoration(
                          hintText: '请输入条码/品名/自编码',
                          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                          prefixIconConstraints: const BoxConstraints(minWidth: 32),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() {});
                                    _onSearch();
                                  },
                                  child:
                                      const Icon(Icons.cancel, size: 18, color: Color(0xFFBDBDBD)),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(minWidth: 28),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
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
                    child: _StockCard(
                      item: _list[index],
                      onTap: () {
                        Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                InventorySearchDetailPage(item: _list[index], sids: _sids),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// 列表卡片
class _StockCard extends StatelessWidget {
  const _StockCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static String _formatDecimal(int fractionDigits, dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(fractionDigits);
  }

  @override
  Widget build(BuildContext context) {
    final String name = item['name']?.toString() ?? '-';
    final String size = item['size']?.toString() ?? '';
    final String barcode = item['barcode']?.toString() ?? '-';
    final dynamic sumqty = item['sumqty'];
    final dynamic sumamt = item['sumamt'];
    final String titleText = size.isNotEmpty ? '$name ($size)' : name;

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
              Text(
                titleText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                barcode,
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '库存数量：${_formatDecimal(1, sumqty)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '库存金额：${_formatDecimal(3, sumamt)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
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
