import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 库存查询 - 商品详情页
class InventorySearchDetailPage extends StatefulWidget {
  final Map<String, dynamic> item;
  final List<int> sids;

  const InventorySearchDetailPage({
    super.key,
    required this.item,
    this.sids = const [],
  });

  @override
  State<InventorySearchDetailPage> createState() =>
      _InventorySearchDetailPageState();
}

class _InventorySearchDetailPageState extends State<InventorySearchDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  // 商品库存信息 (Tab 0)
  Map<String, dynamic> _stockInfo = {};
  bool _stockInfoLoading = false;

  // 供应商价格 (Tab 1)
  List<Map<String, dynamic>> _supList = [];
  bool _supLoading = false;

  // 机构库存 (Tab 2)
  List<Map<String, dynamic>> _storeKcList = [];
  bool _storeKcLoading = false;
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
        _onTabChanged(_tabIndex);
      }
    });

    // 初始化机构
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        final storeId = storeMap['id']?.toString() ?? '';
        _activeStoreId = storeId;
        _storeName = storeMap['name']?.toString() ?? '';
        _sids = widget.sids.isNotEmpty
            ? widget.sids
            : (storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : []);
      }
    } catch (_) {}

    _loadStockInfo();
    _loadSupInfo();
    _loadStoreKc();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    switch (index) {
      case 0:
        if (_stockInfo.isEmpty) _loadStockInfo();
        break;
      case 1:
        if (_supList.isEmpty) _loadSupInfo();
        break;
      case 2:
        if (_storeKcList.isEmpty) _loadStoreKc();
        break;
    }
  }

  Future<void> _loadStockInfo() {
    if (_stockInfoLoading) return Future.value();
    setState(() => _stockInfoLoading = true);
    final productId = widget.item['productid']?.toString() ?? '';
    return request(HttpApi.stockproductGetProStockInfo, {
      'is_page': 1,
      'productid': productId,
    }, false, false).then((result) {
      if (mounted) {
        setState(() {
          final dynamic rawData = result['data'];
          _stockInfo =
              rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};
        });
      }
    }).catchError((_) {}).whenComplete(() {
      if (mounted) setState(() => _stockInfoLoading = false);
    });
  }

  Future<void> _loadSupInfo() {
    if (_supLoading) return Future.value();
    setState(() => _supLoading = true);
    final productId = widget.item['productid']?.toString() ?? '';
    return request(HttpApi.stockproductGetKcProductSupPrice, {
      'is_page': 1,
      'productid': productId,
    }, false, false).then((result) {
      if (mounted) {
        final data = result['data'];
        final list =
            (data is List) ? data.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => _supList = list);
      }
    }).catchError((_) {}).whenComplete(() {
      if (mounted) setState(() => _supLoading = false);
    });
  }

  Future<void> _loadStoreKc() {
    if (_storeKcLoading) return Future.value();
    setState(() => _storeKcLoading = true);
    final productId = widget.item['productid']?.toString() ?? '';
    return request(HttpApi.stockproductGetKcProductSid, {
      'is_page': 1,
      'productid': productId,
      'sids': _sids,
    }, false, false).then((result) {
      if (mounted) {
        final data = result['data'];
        final list =
            (data is List) ? data.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        setState(() => _storeKcList = list);
      }
    }).catchError((_) {}).whenComplete(() {
      if (mounted) setState(() => _storeKcLoading = false);
    });
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
        _storeName = result['storename']?.toString() ?? '';
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
      });
      _loadStoreKc();
    }
  }

  static String _fmt(int fractionDigits, dynamic value) {
    final num v =
        value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(fractionDigits);
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.item['name']?.toString() ?? '-';
    final String size = widget.item['size']?.toString() ?? '';
    final String barcode = widget.item['barcode']?.toString() ?? '-';
    // 单位/品牌/供应商/货位号优先取 getProStockInfo 返回的 _stockInfo，
    // 接口未返回或加载前回退到列表传入的 widget.item，对齐 boss 项目 detail.vue 取值逻辑
    final String unit = _stockInfo['unit']?.toString() ??
        widget.item['unit']?.toString() ??
        '';
    final String brandname = _stockInfo['brandname']?.toString() ??
        _stockInfo['typename']?.toString() ??
        widget.item['brandname']?.toString() ??
        widget.item['typename']?.toString() ??
        '';
    final String supname = _stockInfo['supname']?.toString() ??
        widget.item['supname']?.toString() ??
        '';
    final String shelves = _stockInfo['shelves']?.toString() ??
        widget.item['shelves']?.toString() ??
        '';
    final String imageUrl = widget.item['imageurl']?.toString() ?? '';
    final String titleText = size.isNotEmpty ? '$name ($size)' : name;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '库存详情',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── 商品卡片 ──
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 商品图片
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          width: 70,
                          height: 70,
                          cacheWidth: 140,
                          cacheHeight: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, st) => Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F1F1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.image,
                                size: 30, color: Color(0xFFCCCCCC)),
                          ),
                        )
                      : Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F1F1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.image,
                              size: 30, color: Color(0xFFCCCCCC)),
                        ),
                ),
                const SizedBox(width: 12),
                // 商品信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        barcode,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF7A7A7A)),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '单位：$unit',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF7A7A7A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '品牌：$brandname',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF7A7A7A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '供应商：$supname',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF7A7A7A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '货位号：$shelves',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF7A7A7A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Tab 栏 ──
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF006EFF),
              unselectedLabelColor: const Color(0xFF6B7280),
              indicatorColor: const Color(0xFF006EFF),
              indicatorWeight: 2,
              labelStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 14),
              tabs: const [
                Tab(text: '商品信息'),
                Tab(text: '供应商'),
                Tab(text: '机构库存'),
              ],
            ),
          ),

          // ── Tab 内容 ──
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(10)),
                border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
              ),
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  _buildStockInfoTab(),
                  _buildSupplierTab(),
                  _buildStoreKcTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 0: 商品信息 ──
  Widget _buildStockInfoTab() {
    if (_stockInfoLoading) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: Color(0xFF006EFF)),
      );
    }
    if (_stockInfo.isEmpty) {
      return const Center(
        child: Text('暂无数据',
            style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
      );
    }

    final rows = [
      _InfoRow('零售价', '￥${_fmt(2, _stockInfo['sellprice'])}'),
      _InfoRow('商品库存', _fmt(2, _stockInfo['qty'])),
      _InfoRow('库存单价', '￥${_fmt(2, _stockInfo['costprice'])}'),
      _InfoRow('库存金额', '￥${_fmt(2, _stockInfo['amt'])}'),
      _InfoRow('未税单价', '￥${_fmt(2, _stockInfo['notaxcostprice'])}'),
      _InfoRow('未税库存金额', '￥${_fmt(2, _stockInfo['notaxamt'])}'),
      _InfoRow('未税零售价', '￥${_fmt(2, _stockInfo['notaxsellprice'])}'),
    ];

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFFE2E2E2)),
      itemBuilder: (context, index) {
        final row = rows[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(row.label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF686868))),
              Text(row.value,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF111827))),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 1: 供应商 ──
  Widget _buildSupplierTab() {
    if (_supLoading) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: Color(0xFF006EFF)),
      );
    }
    if (_supList.isEmpty) {
      return const Center(
        child: Text('暂无数据',
            style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 24,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFFF9FAFB)),
          dataRowMinHeight: 42,
          dataRowMaxHeight: 42,
          headingRowHeight: 42,
          columnSpacing: 24,
          columns: const [
            DataColumn(
              label: Text('供应商',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
            ),
            DataColumn(
              label: Text('经销方式',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
            ),
            DataColumn(
              label: Text('进价',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
            ),
          ],
          rows: _supList.map((item) {
            return DataRow(cells: [
              DataCell(Text(item['supname']?.toString() ?? '--',
                  style: const TextStyle(fontSize: 13))),
              DataCell(Text(item['supselltypename']?.toString() ?? '--',
                  style: const TextStyle(fontSize: 13))),
              DataCell(Text(_fmt(2, item['price']),
                  style: const TextStyle(fontSize: 13))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ── Tab 2: 机构库存 ──
  Widget _buildStoreKcTab() {
    return Column(
      children: [
        // 机构选择
        GestureDetector(
          onTap: _selectStore,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFDEDEDE)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _storeName.isNotEmpty ? _storeName : '全部机构',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF333333)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down,
                    size: 20, color: Color(0xFF666666)),
              ],
            ),
          ),
        ),
        // 表格
        Expanded(
          child: _storeKcLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF006EFF)),
                )
              : _storeKcList.isEmpty
                  ? const Center(
                      child: Text('暂无数据',
                          style: TextStyle(
                              fontSize: 14, color: Color(0xFF9CA3AF))),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width - 24,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                              const Color(0xFFF9FAFB)),
                          dataRowMinHeight: 42,
                          dataRowMaxHeight: 42,
                          headingRowHeight: 42,
                          columnSpacing: 24,
                          columns: const [
                            DataColumn(
                              label: Text('序号',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF374151))),
                            ),
                            DataColumn(
                              label: Text('机构名称',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF374151))),
                            ),
                            DataColumn(
                              label: Text('库存数量',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF374151))),
                            ),
                          ],
                          rows: List.generate(_storeKcList.length, (index) {
                            final item = _storeKcList[index];
                            return DataRow(cells: [
                              DataCell(Text('${index + 1}',
                                  style: const TextStyle(fontSize: 13))),
                              DataCell(Text(
                                  item['storename']?.toString() ?? '--',
                                  style: const TextStyle(fontSize: 13))),
                              DataCell(Text(_fmt(2, item['qty']),
                                  style: const TextStyle(fontSize: 13))),
                            ]);
                          }),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}
