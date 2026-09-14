import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// 扫码查价页面
///
/// 对齐 boss 项目中的扫码查价模块
class ScanPricePage extends StatefulWidget {
  const ScanPricePage({super.key});

  @override
  State<ScanPricePage> createState() => _ScanPricePageState();
}

class _ScanPricePageState extends State<ScanPricePage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  Map<String, dynamic>? _productData;
  bool _isScanned = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// 清空输入框并重新聚焦
  void _clearInput() {
    _searchController.clear();
    setState(() {
      _productData = null;
      _isScanned = false;
      _hasError = false;
      _errorMessage = '';
    });
    _focusNode.requestFocus();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () {
        if (!mounted) return;
        _searchProduct();
      },
    );
  }

  /// 固定条码测试入口（对齐其他页面使用 4891599900019）
  void _handleScannedBarcode(String barcode) {
    _searchController.text = barcode;
    // 无需显式调用 _searchProduct，controller listener 会自动触发
  }

  /// 调用摄像头扫描条码（对齐 select_product 流程）
  Future<void> _scanBarcode() async {
    if (Device.isMobile) {
      NavigatorUtils.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final Object? code = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
      );
      if (code == null || !mounted) return;
      _searchController.text = code.toString();
      // 无需显式调用 _searchProduct，controller listener 会自动触发
    } else {
      Toast.show('当前平台暂不支持扫码');
    }
  }

  Future<void> _searchProduct() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _productData = null;
        _isScanned = false;
      });
      return;
    }

    setState(() {
      _isScanned = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final result = await request(
        HttpApi.productGetList,
        {
          'is_page': 1,
          'page': 1,
          'pagesize': 1,
          'barcode': keyword,
          'field': 'barcode',
          'type': 'asc',
        },
      );

      if (!mounted) return;

      final data = result['data'];
      final list = (data is Map<String, dynamic>
              ? data['list']
              : null) as List? ??
          [];

      if (list.isNotEmpty) {
        setState(() {
          _productData = Map<String, dynamic>.from(list.first as Map);
        });
      } else {
        setState(() {
          _productData = null;
          _hasError = true;
          _errorMessage = '未找到该商品';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _productData = null;
        _hasError = true;
        _errorMessage = '查询失败，请重试';
      });
      Toast.show('查询失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
      title: const Text(
        '扫码查价',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
      ),
      centerTitle: true,
      ),
      body: Column(
        children: [
          // ── 搜索栏 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? const Color(0xFF006EFF)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        const Icon(Icons.search,
                            size: 18, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _focusNode,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF111827)),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _searchProduct(),
                            decoration: const InputDecoration(
                              hintText: '请将扫描枪对准商品条码',
                              hintStyle: TextStyle(
                                  fontSize: 13, color: Color(0xFF9CA3AF)),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.only(top: 12, bottom: 8),
                            ),
                          ),
                        ),
                        // 清空图标（有内容时显示）
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchController,
                          builder: (_, value, __) {
                            if (value.text.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return GestureDetector(
                              onTap: _clearInput,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.cancel,
                                    size: 16, color: Color(0xFFBDBDBD)),
                              ),
                            );
                          },
                        ),
                        // 扫描图标
                        GestureDetector(
                          onTap: _scanBarcode,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child:
                                BossSvgIcon(svgFile: 'scan.svg', size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── 固定扫描（Web调试用）──
                if (Device.isWeb) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _handleScannedBarcode('4891599900019'),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFFF6B00)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code,
                              size: 14, color: Color(0xFFFF6B00)),
                          SizedBox(width: 2),
                          Text(
                            '固定扫描',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF6B00),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── 内容区域 ──
          Expanded(
            child: _isScanned
                ? _hasError
                    ? _buildEmptyState()
                    : (_productData != null
                        ? _buildProductInfo()
                        : _buildLoadingState())
                : _buildDefaultState(),
          ),
        ],
      ),
    );
  }

  // ──────────── 未扫码状态 ────────────
  Widget _buildDefaultState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BossSvgIcon(
            svgFile: 'saoma.svg',
            size: 100,
            color: const Color(0xFFD1D5DB),
          ),
          const SizedBox(height: 20),
          const Text(
            '扫码查价',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '请扫描商品条码查询价格',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 加载状态 ────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF006EFF),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '正在查询商品...',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 无数据状态 ────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BossSvgIcon(
            svgFile: 'wushuju.svg',
            size: 100,
            color: const Color(0xFFD1D5DB),
          ),
          const SizedBox(height: 20),
          const Text(
            '无数据',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 商品信息展示 ────────────
  Widget _buildProductInfo() {
    final product = _productData!;
      final productName = _getProductName(product);
      final unit = _getUnit(product);
      final barcode = _getBarcode(product);
      final spec = _getSpec(product);
      final costPrice = _getCostPrice(product);
      final imageUrl = _getImageUrl(product);

    return ListView(
      padding: const EdgeInsets.all(12),
      cacheExtent: 800,
      children: [
        // ── 商品基本信息卡片 ──
        _buildProductCard(productName, unit, barcode, spec, costPrice, imageUrl),

        const SizedBox(height: 12),

        // ── 价格信息分组 ──
        _buildPriceSection('零售价', _getRetailPrices(product)),
        _buildPriceSection('批发价', _getWholesalePrices(product)),
        _buildPriceSection('其他价格', _getOtherPrices(product)),
      ],
    );
  }

  // ──────────── 商品卡片 ────────────
  Widget _buildProductCard(String name, String unit, String barcode, String spec, String costPrice, String imageUrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 商品图片
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      imageUrl,
                      width: 70,
                      height: 70,
                      cacheWidth: 140,
                      cacheHeight: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.inventory_2_outlined,
                            size: 32, color: Color(0xFF9CA3AF)),
                      ),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.inventory_2_outlined,
                        size: 32, color: Color(0xFF9CA3AF)),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      if (unit.isNotEmpty)
                        TextSpan(
                          text: '($unit)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('条码: $barcode',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF7A7A7A))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('规格: ${spec.isEmpty ? "---" : spec}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF7A7A7A))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('进价: $costPrice',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF006EFF))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 价格区域 ────────────
  Widget _buildPriceSection(String title, List<_PriceItem> prices) {
    // 过滤掉价格为0的项
    final validPrices = prices.where((p) => p.value.isNotEmpty).toList();
    if (validPrices.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 12),
          ...validPrices.map((item) => _buildPriceRow(item.label, item.value)),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF006EFF),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 数据提取 ────────────
  String _getImageUrl(Map<String, dynamic> item) {
    final path = item['imageurl']?.toString() ??
        item['imgurl']?.toString() ??
        item['pic']?.toString() ??
        '';
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${Constant.imageBaseUrl}/$path';
  }

  String _getProductName(Map<String, dynamic> item) {
    return item['productname']?.toString() ??
        item['name']?.toString() ??
        item['product']?.toString() ??
        '未知商品';
  }

  String _getUnit(Map<String, dynamic> item) {
    return item['unit']?.toString() ?? '';
  }

  String _getBarcode(Map<String, dynamic> item) {
    return item['barcode']?.toString() ??
        item['itemcode']?.toString() ??
        '---';
  }

  String _getSpec(Map<String, dynamic> item) {
    return item['size']?.toString() ??
        item['spec']?.toString() ??
        item['guige']?.toString() ??
        '---';
  }

  String _getCostPrice(Map<String, dynamic> item) {
    final price = item['inprice']?.toString() ??
        item['costprice']?.toString() ??
        item['cgprice']?.toString() ??
        '0';
    final value = double.tryParse(price) ?? 0;
    return value > 0 ? value.toStringAsFixed(2) : '---';
  }

  // ──────────── 零售价相关 ────────────
  List<_PriceItem> _getRetailPrices(Map<String, dynamic> item) {
    final prices = <_PriceItem>[];

    // 零售价
    final lsprice = item['lsprice']?.toString() ??
        item['sellprice']?.toString() ??
        '0';
    final lsVal = double.tryParse(lsprice) ?? 0;
    if (lsVal > 0) {
      prices.add(_PriceItem('零售价', lsVal.toStringAsFixed(2)));
    }

    // 会员价
    for (int i = 1; i <= 3; i++) {
      final key = 'mprice$i';
      final val = item[key]?.toString() ?? '0';
      final numVal = double.tryParse(val) ?? 0;
      if (numVal > 0) {
        prices.add(_PriceItem('会员价$i', numVal.toStringAsFixed(2)));
      }
    }

    return prices;
  }

  // ──────────── 批发价相关 ────────────
  List<_PriceItem> _getWholesalePrices(Map<String, dynamic> item) {
    final prices = <_PriceItem>[];

    for (int i = 1; i <= 3; i++) {
      final key = 'pfprice$i';
      final val = item[key]?.toString() ?? '0';
      final numVal = double.tryParse(val) ?? 0;
      if (numVal > 0) {
        prices.add(_PriceItem('批发价$i', numVal.toStringAsFixed(2)));
      }
    }

    return prices;
  }

  // ──────────── 其他价格 ────────────
  List<_PriceItem> _getOtherPrices(Map<String, dynamic> item) {
    final prices = <_PriceItem>[];

    // 最低售价
    final minsellprice = item['minsellprice']?.toString() ?? '0';
    final minVal = double.tryParse(minsellprice) ?? 0;
    if (minVal > 0) {
      prices.add(_PriceItem('最低售价', minVal.toStringAsFixed(2)));
    }

    // 配送价
    final psprice = item['psprice']?.toString() ?? '0';
    final psVal = double.tryParse(psprice) ?? 0;
    if (psVal > 0) {
      prices.add(_PriceItem('配送价', psVal.toStringAsFixed(2)));
    }

    return prices;
  }
}

// ──────────── 数据模型 ────────────
class _PriceItem {
  final String label;
  final String value;

  _PriceItem(this.label, this.value);
}
