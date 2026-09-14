import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_location.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/restock/detail.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 补货列表页（对齐 Vue wms/restock/index.vue）
class WmsRestockListPage extends StatefulWidget {
  const WmsRestockListPage({super.key});

  @override
  State<WmsRestockListPage> createState() => _WmsRestockListPageState();
}

class _WmsRestockListPageState extends State<WmsRestockListPage> {
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  final List<Map<String, dynamic>> _list = [];
  final ScrollController _scrollController = ScrollController();

  // ── 筛选参数（对齐 Vue params）──
  String _selectedLocationId = '';
  String _selectedLocationCode = '';
  String _selectedProductId = '';
  String _selectedProductName = '';

  String _storeId = '';

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadLocalInfo();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadLocalInfo() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeId = storeMap['id']?.toString() ?? '';
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
    final bool isFirstPage = _page == 1;

    final params = <String, dynamic>{
      'is_page': 1,
      'page': _page,
      'pagesize': _pageSize,
      'sids': [_storeId],
      'locationid': _selectedLocationId,
      'locationcode': _selectedLocationCode,
      'productid': _selectedProductId,
      'prolist': _selectedProductId.isNotEmpty ? [_selectedProductId] : <String>[],
    };

    return request(HttpApi.wmsReStockList, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final rawList = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      // 对齐 Vue：兼容 list[0] 为数组的返回结构
      final first = rawList.isNotEmpty ? rawList.first : null;
      final rowsSource = first is List ? first : rawList;
      final rows = rowsSource.whereType<Map<String, dynamic>>().toList();
      setState(() {
        if (isFirstPage) {
          _list
            ..clear()
            ..addAll(rows);
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= _pageSize;
      });
    }).catchError((_) {
      if (mounted) setState(() => _hasMore = false);
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _retParam() {
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  /// 选择拣货位（对齐 Vue openLocationSelect + onLocationSelected）
  Future<void> _openLocationSelect() async {
    final result = await SelectLocationPage.show(
      context,
      withStopflag: true,
      title: '选择拣货位',
      initialSelectedId: _selectedLocationId.isNotEmpty ? _selectedLocationId : null,
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedLocationId = result['locationid']?.toString() ?? '';
      _selectedLocationCode = result['locationcode']?.toString() ?? '';
    });
    _retParam();
  }

  /// 选择商品（对齐 Vue openProductSelect：checked=1 && multiple=false → 单选 radio 模式）
  Future<void> _openProductSelect() async {
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => const SelectProductPage(
          mergData: {
            'stockflag': 1,
            'cgpriceflag': 1,
            'itemstatusin': '1,2,3,4',
            'itemtypenot': '5,8',
          },
          // 对齐 Vue openProductSelect：multiple=false，点击 radio 仅保留一个选中项
          singleSelectMode: true,
        ),
      ),
    );
    if (!mounted) return;
    final item = (result != null && result.isNotEmpty) ? result.first : null;
    if (item == null) return;
    setState(() {
      _selectedProductId = item['productid']?.toString() ?? '';
      _selectedProductName = item['name']?.toString() ?? item['productname']?.toString() ?? '';
    });
    _retParam();
  }

  /// 点击卡片进入商品补货（对齐 Vue goRestock）
  Future<void> _goRestock(Map<String, dynamic> item) async {
    await Navigator.push(
      context,
      MaterialPageRoute<dynamic>(
        builder: (_) => WmsRestockDetailPage(productInfo: Map<String, dynamic>.from(item)),
      ),
    );
    // 对齐 Vue onShow：返回后刷新
    if (mounted) _onRefresh();
  }

  /// 悬浮扫码（对齐 Vue scanFn）
  Future<void> _scan() async {
    final code = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute<dynamic>(builder: (_) => const QrCodeScannerPage()),
    );
    if (!mounted) return;
    final scancode = code?.toString().trim() ?? '';
    if (scancode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    try {
      final result = await request(HttpApi.productGetList, {
        'scancode': scancode,
        'is_page': 1,
        'page': 1,
        'pagesize': 10,
      });
      if (!mounted) return;
      final data = result['data'];
      final raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      if (raw.isEmpty) {
        Toast.show('未查询到该商品');
      }
    } catch (_) {}
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
          '补货',
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Column(
                children: [
                  _buildFilterRow(
                    label: '拣货位',
                    value: _selectedLocationCode.isNotEmpty ? _selectedLocationCode : '全部',
                    isPlaceholder: _selectedLocationCode.isEmpty,
                    onTap: _openLocationSelect,
                  ),
                  _buildFilterRow(
                    label: '商品',
                    value: _selectedProductName.isNotEmpty ? _selectedProductName : '全部',
                    isPlaceholder: _selectedProductName.isEmpty,
                    onTap: _openProductSelect,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
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
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
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
                      final item = _list[index];
                      return RepaintBoundary(
                        child: _RestockCard(item: item, onTap: () => _goRestock(item)),
                      );
                    },
                  ),
          ),
          // ── 悬浮扫码按钮（对齐 Vue float-scan-btn）──
          Positioned(
            right: 20,
            bottom: 40,
            child: GestureDetector(
              onTap: _scan,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE8F0FF)),
                ),
                child: const Icon(Icons.qr_code_scanner, size: 26, color: Color(0xFF006EFF)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow({
    required String label,
    required String value,
    required bool isPlaceholder,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: isPlaceholder ? const Color(0xFF999999) : const Color(0xFF111827),
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF999999)),
          ],
        ),
      ),
    );
  }
}

/// 补货列表卡片（对齐 Vue restock/index.vue 卡片）
class _RestockCard extends StatelessWidget {
  const _RestockCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = item['name']?.toString() ?? item['productname']?.toString() ?? '-';
    final String size = item['size']?.toString() ?? '';
    final String needqty = MathUtils.formatDecimal(2, item['needqty'] ?? 0);
    final String barcode = item['barcode']?.toString() ?? '';
    final String stockqty = MathUtils.formatDecimal(2, item['stockqty'] ?? 0);
    final String locationcode = item['locationcode']?.toString() ?? '';
    final String maxstockqty = MathUtils.formatDecimal(2, item['maxstockqty'] ?? 0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    size.isEmpty ? name : '$name（$size）',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '补货数：$needqty',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    barcode,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '库存：$stockqty',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '拣货位：$locationcode',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '最大储存量：$maxstockqty',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
