import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart';
import 'package:flutter_deer/pages/business/basis/commodity/add.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

class CommodityListPage extends StatefulWidget {
  const CommodityListPage({super.key});

  @override
  State<CommodityListPage> createState() => _CommodityListPageState();
}

class _CommodityListPageState extends State<CommodityListPage> {
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
  String _filterTypecode = '';
  String _filterSupid = '';
  String _filterSupname = '';
  String _filterItemtype = ''; // 商品类型
  String _filterPricetype = ''; // 计价方式
  String _filterItemstatus = ''; // 商品状态（更多筛选中）

  /// 进价查看权限（对齐小程序 index.vue user.inpriceflag）
  int _inpriceflag = 1;

  // 筛选常量
  static const List<Map<String, String>> _itemTypes = [
    {'label': '全部', 'value': ''},
    {'label': '普通', 'value': '1'},
    {'label': '拆分', 'value': '2'},
    {'label': '组装', 'value': '3'},
    {'label': '自动拆分', 'value': '4'},
    {'label': '自动组装', 'value': '5'},
    {'label': '特价打包', 'value': '8'},
  ];

  static const List<Map<String, String>> _priceTypes = [
    {'label': '全部', 'value': ''},
    {'label': '普通商品', 'value': '1'},
    {'label': '计重商品', 'value': '2'},
    {'label': '计份商品', 'value': '3'},
  ];

  static const List<Map<String, String>> _itemStatuses = [
    {'label': '全部', 'value': ''},
    {'label': '正常', 'value': '1'},
    {'label': '新品', 'value': '2'},
    {'label': '冻结', 'value': '3'},
    {'label': '停购', 'value': '4'},
    {'label': '停用', 'value': '5'},
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInpriceFlag();
    // 查看权限校验
    if (!PermissionUtils.checkPermission('010201', showTip: false)) {
      Toast.show('你无权查看商品档案，请在后台修改权限');
    } else {
      _loadData();
    }
  }

  /// 从用户信息读取进价查看权限（对齐小程序 index.vue：inpriceflag==1 展示进价，否则展示 ***）
  void _loadInpriceFlag() {
    try {
      final userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final u = jsonDecode(userStr) as Map<String, dynamic>;
        _inpriceflag = int.tryParse(u['inpriceflag']?.toString() ?? '1') ?? 1;
      }
    } catch (_) {}
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
      if (_filterSupid.isNotEmpty) 'supid': _filterSupid,
      if (_filterItemtype.isNotEmpty) 'itemtype': _filterItemtype,
      if (_filterPricetype.isNotEmpty) 'pricetype': _filterPricetype,
      if (_filterItemstatus.isNotEmpty) 'itemstatus': _filterItemstatus,
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

  /// 扫码搜索（对齐 Vue index.vue scanFn）
  Future<void> _scanBarcode() async {
    if (!Device.isMobile) {
      Toast.show('当前平台暂不支持扫码');
      return;
    }
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code == null || !mounted) return;
    final result = code.toString().trim();
    if (result.isEmpty) return;
    _searchController.text = result;
    _onSearch();
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
        _filterTypename = result['typename']?.toString() ?? '';
        _filterTypecode = result['typecode']?.toString() ?? result['code']?.toString() ?? '';
        _page = 1;
        _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

  // ── 供应商筛选 ──
  Future<void> _selectSupplier() async {
    final result = await SelectSupplierPage.show(
      context,
      initialSelectedId: _filterSupid,
    );
    if (result != null && mounted) {
      setState(() {
        _filterSupid = result['supid']?.toString() ?? '';
        _filterSupname = result['supname']?.toString() ?? '';
        _page = 1;
        _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

  // ── 更多筛选抽屉 ──
  void _openFilterSheet() {
    String tmpItemtype = _filterItemtype;
    String tmpPricetype = _filterPricetype;
    String tmpItemstatus = _filterItemstatus;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final screenHeight = MediaQuery.of(context).size.height;
            return Container(
              height: screenHeight * 2 / 3,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // 标题栏
                  SizedBox(
                    height: 50,
                    child: Row(children: [
                      const SizedBox(width: 48),
                      const Expanded(
                        child: Text('筛选',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                    ]),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  // 内容区（可滚动）
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 商品类型
                          const Text('商品类型',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _itemTypes.map((t) {
                              final selected = t['value'] == tmpItemtype;
                              return GestureDetector(
                                onTap: () => setSheetState(() => tmpItemtype = t['value']!),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF006EFF)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t['label']!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: selected ? Colors.white : const Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                          // 计价方式
                          const Text('计价方式',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _priceTypes.map((t) {
                              final selected = t['value'] == tmpPricetype;
                              return GestureDetector(
                                onTap: () => setSheetState(() => tmpPricetype = t['value']!),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF006EFF)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t['label']!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: selected ? Colors.white : const Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                          // 商品状态
                          const Text('商品状态',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _itemStatuses.map((t) {
                              final selected = t['value'] == tmpItemstatus;
                              return GestureDetector(
                                onTap: () => setSheetState(() => tmpItemstatus = t['value']!),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF006EFF)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t['label']!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: selected ? Colors.white : const Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  // 底部按钮
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      MediaQuery.of(context).padding.bottom + 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setSheetState(() {
                                tmpItemtype = '';
                                tmpPricetype = '';
                                tmpItemstatus = '';
                              });
                            },
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFDEDEDE)),
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
                                _filterItemtype = tmpItemtype;
                                _filterPricetype = tmpPricetype;
                                _filterItemstatus = tmpItemstatus;
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

  bool get _hasActiveFilters =>
      _filterTypeid.isNotEmpty ||
      _filterSupid.isNotEmpty ||
      _filterItemtype.isNotEmpty ||
      _filterPricetype.isNotEmpty ||
      _filterItemstatus.isNotEmpty;

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
          '商品管理',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 工具栏：搜索框 + 新增 ──
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
                                onChanged: (_) => _onSearchChanged(),
                                decoration: InputDecoration(
                                  hintText: '请输入商品名称/编码',
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
                                            _debounce?.cancel();
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
                                              size: 20, color: Color(0xFF666666)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: const Color.fromRGBO(245, 245, 245, 1),
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
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          if (!PermissionUtils.checkPermission('010202', showTip: false)) {
                            Toast.show('你无权新增商品档案，请在后台修改权限');
                            return;
                          }
                          final refresh = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CommodityAddPage(
                                initialTypeId: _filterTypeid.isNotEmpty ? _filterTypeid : null,
                                initialTypecode:
                                    _filterTypecode.isNotEmpty ? _filterTypecode : null,
                                initialTypename:
                                    _filterTypename.isNotEmpty ? _filterTypename : null,
                              ),
                            ),
                          );
                          if (refresh ?? false) _onRefresh();
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
                // ── 分类 + 货商 + 筛选按钮（对齐小程序 contant-box 占满一行） ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
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
                                if (_filterTypeid.isNotEmpty)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _filterTypeid = '';
                                        _filterTypename = '';
                                        _filterTypecode = '';
                                        _page = 1;
                                        _list = [];
                                        _hasMore = true;
                                      });
                                      _loadData();
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(Icons.close, size: 16, color: Color(0xFF006EFF)),
                                    ),
                                  ),
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.arrow_drop_down,
                                      size: 18, color: Color(0xFF999999)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectSupplier,
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
                                    _filterSupid.isNotEmpty ? _filterSupname : '全部货商',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _filterSupid.isNotEmpty
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFF333333),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_filterSupid.isNotEmpty)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _filterSupid = '';
                                        _filterSupname = '';
                                        _page = 1;
                                        _list = [];
                                        _hasMore = true;
                                      });
                                      _loadData();
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(Icons.close, size: 16, color: Color(0xFF006EFF)),
                                    ),
                                  ),
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.arrow_drop_down,
                                      size: 18, color: Color(0xFF999999)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _openFilterSheet,
                        child: Container(
                          width: 36,
                          height: 32,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _hasActiveFilters
                                  ? const Color(0xFF006EFF)
                                  : const Color(0xFFDEDEDE),
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(
                            Icons.tune,
                            size: 20,
                            color: _hasActiveFilters
                                ? const Color(0xFF006EFF)
                                : const Color(0xFF666666),
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
                        Text('暂无商品数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
                    child: _CommodityCard(
                      item: _list[index],
                      inpriceflag: _inpriceflag,
                      onTap: () async {
                        final refresh = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CommodityAddPage(
                              productData: _list[index],
                            ),
                          ),
                        );
                        if (refresh ?? false) _onRefresh();
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// 商品列表卡片（对齐小程序 index.vue product-item 布局）
class _CommodityCard extends StatelessWidget {
  const _CommodityCard({
    required this.item,
    required this.inpriceflag,
    required this.onTap,
  });
  final Map<String, dynamic> item;

  /// 进价查看权限：1 展示进价，否则展示 ***（对齐小程序 user.inpriceflag）
  final int inpriceflag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = item['productname']?.toString() ?? item['name']?.toString() ?? '-';
    final String size = item['size']?.toString() ?? '';
    final String unit = item['unit']?.toString() ?? '';
    final String barcode = item['barcode']?.toString() ?? '';
    final sellprice = MathUtils.formatDecimal(2, item['sellprice']);
    final stock = MathUtils.formatDecimal(1, item['allstockqty'] ?? item['stock']);
    final inprice = MathUtils.formatDecimal(2, item['inprice']);
    final pfprice1 = MathUtils.formatDecimal(2, item['pfprice1']);
    final shelves = item['shelves']?.toString() ?? '';

    // 图片 URL 处理
    final String imagePath =
        item['imageurl']?.toString() ?? item['imgurl']?.toString() ?? item['pic']?.toString() ?? '';
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
              // 左侧商品图片（对齐小程序 168rpx ≈ 84px）
              Container(
                width: 84,
                height: 84,
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
                          width: 84,
                          height: 84,
                          cacheWidth: 168,
                          cacheHeight: 168,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.image_not_supported_outlined,
                                size: 28, color: Color(0xFFD1D5DB)),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.image_outlined, size: 28, color: Color(0xFFD1D5DB)),
                      ),
              ),
              const SizedBox(width: 10),
              // 右侧文本内容（对齐小程序 product-info：4行 space-between）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 商品名称 + 规格
                    Text(
                      name + (size.isNotEmpty ? '($size)' : ''),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // 条码 | 库存
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            barcode,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '库存：$stock',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 货位号 | 进价
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '货位号：$shelves',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          inpriceflag == 1 ? '进价：$inprice' : '进价：***',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 零售价 | 批发价
                    Row(
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                              children: [
                                const TextSpan(text: '零售价：'),
                                TextSpan(
                                  text: sellprice,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFFF3B30)),
                                ),
                                if (unit.isNotEmpty) TextSpan(text: '/$unit'),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          '批发价：$pfprice1',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
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
