import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart';
import 'package:flutter_deer/pages/business/basis/productChangePrice/edit.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 快速调价 - 商品列表页
/// 参考 Vue boss 项目 productChangePrice/index.vue
class ChangePriceListPage extends StatefulWidget {
  const ChangePriceListPage({super.key});

  @override
  State<ChangePriceListPage> createState() => _ChangePriceListPageState();
}

class _ChangePriceListPageState extends State<ChangePriceListPage> {
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ── 筛选参数 ──
  String _filterTypeid = '';
  String _filterTypename = '';
  String _storeId = '';
  String _storeName = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 默认当前门店
    try {
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap =
            Map<String, dynamic>.from(storeStr.startsWith('{') ? _parseJson(storeStr) : {});
        _storeId = storeMap['id']?.toString() ?? '';
        _storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
    if (!PermissionUtils.checkPermission('010401', showTip: false)) {
      Toast.show('你无权使用快速调价，请在后台修改权限');
      return;
    }
    _loadData();
  }

  Map<String, dynamic> _parseJson(String str) {
    try {
      return Map<String, dynamic>.from(const JsonDecoder().convert(str) as Map);
    } catch (_) {
      return {};
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
    return request(HttpApi.productGetList, {
      'is_page': 1,
      'page': _page,
      'pagesize': 20,
      'cond': _searchController.text.trim(),
      'field': 'createtime',
      'type': 'desc',
      if (_filterTypeid.isNotEmpty) 'typeid': _filterTypeid,
      if (_storeId.isNotEmpty) 'sids': _storeId,
      if (_storeId.isNotEmpty) 'storeid': _storeId,
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
    await _loadData();
  }

  void _onSearch() {
    FocusScope.of(context).unfocus();
    _page = 1;
    _list = [];
    _hasMore = true;
    _loadData();
  }

  // ── 分类筛选 ──
  Future<void> _selectType() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const CategoryListPage(isSelect: true)),
    );
    if (result != null && mounted) {
      setState(() {
        _filterTypeid = result['typeid']?.toString() ?? '';
        _filterTypename = result['typename']?.toString() ?? result['name']?.toString() ?? '';
        _page = 1;
        _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

  // ── 门店筛选 ──
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _storeId,
    );
    if (result != null && mounted) {
      setState(() {
        _storeId = result['storeid']?.toString() ?? '';
        _storeName = result['storename']?.toString() ?? '';
        _page = 1;
        _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

  // ── 扫描条码 ──
  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code != null && code.isNotEmpty && mounted) {
      _searchController.text = code;
      _onSearch();
    }
  }

  // ── 打开编辑页 ──
  Future<void> _openEdit(Map<String, dynamic> item) async {
    if (!PermissionUtils.checkPermission('010401', showTip: false)) {
      Toast.show('你无权编辑快速调价，请在后台修改权限');
      return;
    }
    final refresh = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ChangePriceEditPage(productData: item)),
    );
    if ((refresh ?? false) && mounted) {
      _onRefresh();
    }
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
          '快速调价',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 搜索栏 ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, value, _) {
                              return TextField(
                                controller: _searchController,
                                onSubmitted: (_) => _onSearch(),
                                decoration: InputDecoration(
                                  hintText: '条码/品名/自编码',
                                  hintStyle:
                                      const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                                  prefixIcon:
                                      const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // 有输入内容时显示清空按钮
                                      if (value.text.isNotEmpty)
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            _searchController.clear();
                                            _onSearch();
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 6),
                                            child: Icon(Icons.cancel,
                                                size: 16, color: Color(0xFFBFBFBF)),
                                          ),
                                        ),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _scanBarcode,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 10),
                                          child: Icon(Icons.qr_code_scanner,
                                              size: 18, color: Color(0xFF666666)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  contentPadding: EdgeInsets.zero,
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
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── 门店 + 分类选择器 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      // 门店选择
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectStore,
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFFDEDEDE)),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _storeId.isNotEmpty ? _storeName : '全部门店',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _storeId.isNotEmpty
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFF333333),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_storeId.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _storeId = '';
                                        _storeName = '';
                                        _page = 1;
                                        _list = [];
                                        _hasMore = true;
                                      });
                                      _loadData();
                                    },
                                    child:
                                        const Icon(Icons.close, size: 16, color: Color(0xFF006EFF)),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down,
                                    size: 18, color: Color(0xFF999999)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 分类选择
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectType,
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFFDEDEDE)),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _filterTypeid.isNotEmpty ? _filterTypename : '全部分类',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _filterTypeid.isNotEmpty
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFF333333),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_filterTypeid.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _filterTypeid = '';
                                        _filterTypename = '';
                                        _page = 1;
                                        _list = [];
                                        _hasMore = true;
                                      });
                                      _loadData();
                                    },
                                    child:
                                        const Icon(Icons.close, size: 16, color: Color(0xFF006EFF)),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down,
                                    size: 18, color: Color(0xFF999999)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _list.isEmpty && !_loading
          ? const Center(
              child: Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))))
          : RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                cacheExtent: 800,
                itemCount: _list.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _list.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  return RepaintBoundary(
                    child: _ChangePriceItemCard(
                      item: _list[index],
                      onTap: () => _openEdit(_list[index]),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// 商品列表项卡片
class _ChangePriceItemCard extends StatelessWidget {
  const _ChangePriceItemCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = item['name']?.toString() ?? '-';
    final String size = item['size']?.toString() ?? '';
    final String unit = item['unit']?.toString() ?? '';
    final String sellprice = MathUtils.formatDecimal(2, item['sellprice'] ?? '0');
    final String mprice1 = MathUtils.formatDecimal(2, item['mprice1'] ?? '0');

    // 图片
    final String imagePath = item['imageurl']?.toString() ?? '';
    final String imageUrl = imagePath.isEmpty
        ? ''
        : (imagePath.startsWith('http://') || imagePath.startsWith('https://')
            ? imagePath
            : '${Constant.imageBaseUrl}/$imagePath');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧图片
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
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
                            child: Icon(Icons.image_not_supported_outlined,
                                size: 24, color: Color(0xFFD1D5DB)),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.image_outlined, size: 28, color: Color(0xFFD1D5DB)),
                      ),
              ),
              const SizedBox(width: 10),
              // 右侧文本
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名称(规格)
                    Text(
                      '$name/$size${unit.isNotEmpty ? '($unit)' : ''}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    // 零售价
                    Row(
                      children: [
                        const Text('零售价',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF374151))),
                        const Spacer(),
                        Text(
                          '$sellprice/$unit',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 会员价
                    Row(
                      children: [
                        const Text('会员价',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF374151))),
                        const Spacer(),
                        Text(
                          '$mprice1/$unit',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
