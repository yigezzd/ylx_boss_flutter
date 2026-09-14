import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_batch.dart';
import 'package:flutter_deer/components/select/select_mult_batch.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

class SelectProductPage extends StatefulWidget {
  const SelectProductPage({
    super.key,
    this.storeid,
    this.counterid,
    this.billsupid,
    this.planid,
    this.checktype,
    this.billtypeflag,
    this.planCategories,
    this.mergData,
    this.multiple = false,
    this.selectList,
    this.paramJust,
    this.batchManualInput = false,
    this.checkboxMode = false,
    this.singleSelectMode = false,
    this.initialKeyword,
    this.amtRecalcQty = true,
    this.amtQtyDecimals = 2,
    this.showSelectedCount = false,
    this.selectMax,
  });
  final int? storeid;
  final String? counterid;
  final String? billsupid;

  /// 盘点计划ID（预盘单按盘点计划过滤商品）
  final String? planid;

  /// 盘点范围类型（1=全场 2=分类 3=供应商 4=品牌）
  final int? checktype;

  /// 单据类型标识（ypd=预盘单, kspd=快速盘点）
  final String? billtypeflag;

  /// 盘点计划关联的分类列表（stockPlanItemtypeResp），
  /// 传入后左侧分类栏仅展示计划内的分类，而非全部分类（对齐 boss 项目 treeArr 逻辑）
  final List<Map<String, dynamic>>? planCategories;

  /// 批发模块传入的额外 API 参数
  final Map<String, dynamic>? mergData;

  /// 是否允许多选（默认 false）
  final bool multiple;

  /// 已选商品列表（对齐 lxAss selectList，用于预加载已有选中项）
  final List<Map<String, dynamic>>? selectList;

  /// 商品详情弹窗字段白名单（对齐 lxAss proDetails 的 paramJust）。
  /// 例如库存单据传 ['qty','validdate','birthdate','batchno','batch','unit','size','remark']，
  /// 成本变更单传 ['newcostprice','remark']。
  final List<String>? paramJust;

  /// 批次字段手动输入模式（其他入库专用，不弹窗选批次）
  final bool batchManualInput;

  /// 复选框模式（促销计划等不需要数量的场景，用复选框替代步进器）
  final bool checkboxMode;

  /// 单选模式（对齐 Vue selectProduct checked=1 && !multiple）
  /// 显示 radio 指示器，点击即选中并清除其他选项，不显示底部数量栏
  final bool singleSelectMode;

  /// 初始搜索关键字（由调用页带入，避免用户重复输入）
  final String? initialKeyword;

  /// 小计金额失焦/确认反算模式（对齐小程序各单据 edit.vue writeData key=amt 分支）：
  /// true → 反算数量 qty = amt / price（cgorder/cgth/cgzc/cgother/cgothercd 默认）；
  /// false → 反算单价 price = amt / qty（instore 且 cgSupChangeAmtFlag != 2 时）
  final bool amtRecalcQty;

  /// 反算数量的保留小数位（对齐各单据 formatDecimal：instore=1，其余页面=2）
  final int amtQtyDecimals;

  /// 历史参数（连锁模块单据曾用于区分"已选X件"统计样式）。
  /// 现底部栏统一为两列"数量 / 合计"（label 在上、value 在下），该参数仅作兼容保留不再影响布局
  final bool showSelectedCount;

  /// 最大可选数量上限（复选框模式下生效，0 或 null 表示不限制）
  /// 对齐小程序 selectMax（兑奖换购等场景传 5）
  final int? selectMax;

  @override
  State<SelectProductPage> createState() => _SelectProductPageState();
}

class _SelectProductPageState extends State<SelectProductPage> {
  static const Color _primaryColor = Color(0xFF3B82F6);
  static const Color _bgColor = Color(0xFFF5F5F5);

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // 分类相关
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _selectedL1Category; // 当前选中的一级分类（null = 全部）
  bool _loadingCategories = false;

  // 二级分类相关
  int _twoTypeIndex = 0; // 0 = "全部分类"，>0 = 对应 children[index-1]

  // 商品相关
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];
  final List<Map<String, dynamic>> _selectedItems = [];

  String get _searchText => _searchController.text.trim();

  /// 已选总数量（double 累加，支持小数 qty；对齐 Vue selectTotalAll.getTotal）
  double get _totalQtyValue => _selectedItems.fold<double>(
      0, (sum, item) => MathUtils.add(sum, double.tryParse(item['qty']?.toString() ?? '0') ?? 0));

  /// 已选总数量显示文本（formatDecimal(1) 按服务端 countLength 保留小数位）
  String get _totalQtyText => MathUtils.formatDecimal(1, _totalQtyValue);

  /// 已选总金额：Σ(单价 × 数量)，单价取值对齐 _getPrice
  /// （cgpriceflag 取 cgprice||price，cgprice 为空或为 0 时回退档案进价 price，
  /// pspriceflag 取 lspsprice||price，否则 sellprice||price）
  /// formatDecimal(3) 对齐 Vue getAmt
  String get _totalAmtText {
    final cgpriceflag = widget.mergData?['cgpriceflag']?.toString() == '1';
    final pspriceflag = widget.mergData?['pspriceflag']?.toString() == '1';
    double sum = 0;
    for (final item in _selectedItems) {
      final qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
      String priceText;
      if (cgpriceflag) {
        priceText = _cgPriceText(item, fallback: '0');
      } else if (pspriceflag) {
        priceText = item['lspsprice']?.toString() ?? item['price']?.toString() ?? '0';
      } else {
        priceText = item['sellprice']?.toString() ?? item['price']?.toString() ?? '0';
      }
      sum = MathUtils.add(sum, MathUtils.mul(qty, double.tryParse(priceText) ?? 0));
    }
    return MathUtils.formatDecimal(3, sum);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 对齐 lxAss：预加载已有选中项到 _selectedItems
    if (widget.selectList != null && widget.selectList!.isNotEmpty) {
      for (final item in widget.selectList!) {
        if (item['productid']?.toString().isNotEmpty ?? false) {
          _selectedItems.add(Map<String, dynamic>.from(item));
        }
      }
    }
    _loadCategories();
    // 带入调用页的搜索关键字，首次加载即按关键字搜索
    final keyword = widget.initialKeyword?.trim() ?? '';
    if (keyword.isNotEmpty) {
      _searchController.text = keyword;
    }
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
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

  // ─── 分类加载（对齐 boss 项目 treeArr 逻辑：有盘点计划分类时仅展示计划内分类，保留完整父子树）────
  void _loadCategories() {
    // 如果外部传入了盘点计划关联的分类（stockPlanItemtypeResp），
    // 直接使用，不再请求全部分类接口（对齐 boss 项目 selectProduct 中 treeArr 覆盖逻辑）
    if (widget.planCategories != null && widget.planCategories!.isNotEmpty) {
      final planList = widget.planCategories!;
      // 构建完整父子关系树，保留 children（对齐 boss 项目 buildTree + treeHandle）
      final Map<String, Map<String, dynamic>> nodeMap = {};
      for (final item in planList) {
        final id = item['stypeid']?.toString() ?? item['typeid']?.toString() ?? '';
        if (id.isEmpty) continue;
        nodeMap[id] = Map<String, dynamic>.from(item)
          ..['typeid'] = id
          ..['name'] = item['stypename']?.toString() ?? item['name']?.toString() ?? ''
          ..['children'] = <Map<String, dynamic>>[];
      }
      final List<Map<String, dynamic>> topCategories = [];
      for (final node in nodeMap.values) {
        final pid = node['parenttypeid']?.toString() ?? '';
        if (pid.isNotEmpty && pid != '0' && nodeMap.containsKey(pid)) {
          // 有父节点且在计划分类中 → 加入父节点的 children
          (nodeMap[pid]!['children'] as List<Map<String, dynamic>>).add(node);
        } else {
          topCategories.add(node);
        }
      }
      setState(() {
        _categories = topCategories;
        _loadingCategories = false;
      });
      return;
    }
    if (_loadingCategories) return;
    setState(() => _loadingCategories = true);
    request(HttpApi.typeGetListandCode, {
      'field': 'typeid',
      'is_page': 0,
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      // 接口返回完整树结构，children 字段包含子分类
      final list = (data is Map<String, dynamic>)
          ? (data['children'] as List? ?? data['alllist'] as List? ?? [])
          : <dynamic>[];
      // 构建树结构：为每个节点添加空的 children 列表（若 API 未返回 children）
      final tree = list.map<Map<String, dynamic>>((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (!m.containsKey('children')) m['children'] = <Map<String, dynamic>>[];
        return m;
      }).toList();
      setState(() {
        _categories = tree;
      });
    }).whenComplete(() {
      if (mounted) setState(() => _loadingCategories = false);
    });
  }

  // ─── 二级分类计算属性（对齐 boss 项目 twoTypeList computed）──────────────
  List<Map<String, dynamic>> get _twoTypeList {
    final l1 = _selectedL1Category;
    if (l1 == null) return [];
    final children = (l1['children'] as List? ?? []).cast<Map<String, dynamic>>();
    if (children.isEmpty) return [];
    // 前置"全部分类"项，typeid 使用当前一级分类的 typeid（对齐 boss 项目逻辑）
    return [
      {'name': '全部分类', 'typeid': l1['typeid']},
      ...children,
    ];
  }

  // ─── 当前实际使用的 typeid（综合一级/二级选中状态）──────────────────────
  String? get _effectiveTypeId {
    final twoList = _twoTypeList;
    if (twoList.isNotEmpty && _twoTypeIndex > 0 && _twoTypeIndex < twoList.length) {
      return twoList[_twoTypeIndex]['typeid']?.toString();
    }
    // 未选中二级分类，使用一级分类的 typeid
    return _selectedL1Category?['typeid']?.toString();
  }

  // ─── 商品加载 ────────────────────────────────────────────
  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    final typeid = _effectiveTypeId;
    final isCostChange = widget.paramJust?.contains('newcostprice') ?? false;
    return request(HttpApi.productGetList, {
      'stockflag': 1,
      'storeid': widget.storeid ?? '',
      if (!isCostChange) 'counterid': widget.counterid ?? '',
      if (!isCostChange) 'cgpriceflag': 1,
      if (!isCostChange) 'billsupid': widget.billsupid ?? '',
      if (!isCostChange) 'itemstatusin': '1,2',
      if (!isCostChange) 'itemtypenot': '5,8',
      if (!isCostChange) 'signflag': '',
      // 成本变更：对齐 lxAss 传参
      if (isCostChange) 'billtypeflag': 'cbbg',
      if (isCostChange) 'havestock': '',
      if (isCostChange) 'itemstatus': '1,2',
      if (isCostChange) 'unitquerytype': '',
      // 盘点类单据（预盘/快盘）需要批次信息：对齐 lxAss filterChecktype 传参
      if (widget.billtypeflag == 'kspd' || widget.billtypeflag == 'ypd') 'needbatchflag': 1,
      if (widget.billtypeflag == 'kspd' || widget.billtypeflag == 'ypd') 'morebatchflag': 1,
      if (widget.planid != null && widget.planid!.isNotEmpty) 'planid': widget.planid,
      if (widget.checktype != null) 'checktype': widget.checktype,
      if (!isCostChange && widget.billtypeflag != null && widget.billtypeflag!.isNotEmpty)
        'billtypeflag': widget.billtypeflag,
      if (typeid != null && typeid.isNotEmpty) 'typeid': typeid,
      if (widget.mergData != null) ...widget.mergData!,
      'is_page': 1,
      'page': _page,
      'pagesize': 20,
      'cond': _searchText,
      'field': 'barcode',
      'type': 'asc',
    }).then((result) {
      if (!mounted) return;
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

  void _onSearch() {
    _page = 1;
    _hasMore = true;
    _list = [];
    _loadData();
  }

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
      _onSearch();
    } else {
      Toast.show('当前平台暂不支持扫码');
    }
  }

  void _onCategoryTap(Map<String, dynamic>? category) {
    setState(() {
      _selectedL1Category = category;
      _twoTypeIndex = 0; // 切换一级分类时重置二级分类
      _page = 1;
      _hasMore = true;
      _list = [];
    });
    _loadData();
  }

  /// 二级分类点击（对齐 boss 项目 selectTwoChirenList）
  void _onTwoTypeTap(int index) {
    if (_twoTypeIndex == index) return;
    setState(() {
      _twoTypeIndex = index;
      _page = 1;
      _hasMore = true;
      _list = [];
    });
    _loadData();
  }

  // ─── 已选商品查找工具方法 ─────────────────────────────────────
  /// 获取商品在已选列表中的索引，-1 表示未选
  int _findSelectedIndex(Map<String, dynamic> item) {
    final productId = item['productid']?.toString() ?? '';
    if (productId.isEmpty) return -1;
    for (int i = 0; i < _selectedItems.length; i++) {
      if (_selectedItems[i]['productid']?.toString() == productId) return i;
    }
    return -1;
  }

  /// 获取商品已选数量，0 表示未选
  double _getSelectedQty(Map<String, dynamic> item) {
    final idx = _findSelectedIndex(item);
    if (idx < 0) return 0;
    return double.tryParse(_selectedItems[idx]['qty']?.toString() ?? '0') ?? 0;
  }

  /// 快速增加数量（卡片上 + 按钮），对齐单据页 formatDecimalNum(1) 步进
  void _quickAdd(Map<String, dynamic> item) {
    final idx = _findSelectedIndex(item);
    if (idx < 0) {
      // 未选过，以数量 1 加入（同步写入 price 和 amt，对齐 _confirm 补全逻辑）
      final result = Map<String, dynamic>.from(item);
      result['qty'] = 1;
      result['giftqty'] = 0;
      final initPrice = double.tryParse(_getPrice(item)) ?? 0;
      result['price'] = MathUtils.formatDecimalNum(2, initPrice);
      result['amt'] = MathUtils.formatDecimalNum(3, initPrice);
      setState(() => _selectedItems.add(result));
    } else {
      final currentQty = double.tryParse(_selectedItems[idx]['qty']?.toString() ?? '0') ?? 0;
      setState(() {
        final newQty = currentQty + 1;
        _selectedItems[idx]['qty'] = MathUtils.formatDecimalNum(1, newQty);
        // 数量步进等同 writeData qty：重置手动金额标记，amt 交由 _confirm 按 qty × price 重算
        _selectedItems[idx]['_amtManual'] = false;
        // 同步重算 amt（对齐 _confirm 补全逻辑）
        final cgpriceflag = widget.mergData?['cgpriceflag']?.toString() == '1';
        final priceText = cgpriceflag
            ? _cgPriceText(_selectedItems[idx], fallback: '0')
            : (_selectedItems[idx]['sellprice']?.toString() ??
                _selectedItems[idx]['price']?.toString() ??
                '0');
        final amtPrice = double.tryParse(priceText) ?? 0;
        _selectedItems[idx]['amt'] = MathUtils.formatDecimalNum(3, MathUtils.mul(newQty, amtPrice));
      });
    }
  }

  /// 快速减少数量（卡片上 - 按钮），减到 0 则移除
  void _quickMinus(Map<String, dynamic> item) {
    final idx = _findSelectedIndex(item);
    if (idx < 0) return;
    final qty = double.tryParse(_selectedItems[idx]['qty']?.toString() ?? '0') ?? 0;
    if (qty <= 1) {
      setState(() => _selectedItems.removeAt(idx));
    } else {
      setState(() {
        _selectedItems[idx]['qty'] = MathUtils.formatDecimalNum(1, qty - 1);
        // 数量步进等同 writeData qty：重置手动金额标记，amt 交由 _confirm 按 qty × price 重算
        _selectedItems[idx]['_amtManual'] = false;
      });
    }
  }

  /// 复选框模式：切换选中/取消选中（对齐 Vue selectProduct checked=1 逻辑）
  void _toggleSelect(Map<String, dynamic> item) {
    final idx = _findSelectedIndex(item);
    if (idx < 0) {
      // 勾选上限校验（对齐小程序 selectMax）：达到上限时阻止勾选
      if (widget.selectMax != null &&
          widget.selectMax! > 0 &&
          _selectedItems.length >= widget.selectMax!) {
        Toast.show('最多支持${widget.selectMax}个兑换商品');
        return;
      }
      // 未选中 → 加入（同步写入 price 和 amt，对齐 _confirm 补全逻辑）
      final result = Map<String, dynamic>.from(item);
      result['qty'] = 1;
      result['giftqty'] = 0;
      final initPrice = double.tryParse(_getPrice(item)) ?? 0;
      result['price'] = MathUtils.formatDecimalNum(2, initPrice);
      result['amt'] = MathUtils.formatDecimalNum(3, initPrice);
      setState(() => _selectedItems.add(result));
    } else {
      // 已选中 → 移除
      setState(() => _selectedItems.removeAt(idx));
    }
  }

  /// 单选模式：选中当前项并清除其他（对齐 Vue changeCheckedfn 单选逻辑）
  void _toggleSingleSelect(Map<String, dynamic> item) {
    final idx = _findSelectedIndex(item);
    if (idx < 0) {
      // 未选中 → 清除其他，选中当前（同步写入 price 和 amt，对齐 _confirm 补全逻辑）
      final result = Map<String, dynamic>.from(item);
      result['qty'] = 1;
      result['giftqty'] = 0;
      final initPrice = double.tryParse(_getPrice(item)) ?? 0;
      result['price'] = MathUtils.formatDecimalNum(2, initPrice);
      result['amt'] = MathUtils.formatDecimalNum(3, initPrice);
      setState(() {
        _selectedItems.clear();
        _selectedItems.add(result);
      });
    } else {
      // 已选中 → 取消选中
      setState(() => _selectedItems.removeAt(idx));
    }
  }

  /// 复选框模式：判断商品是否已选中
  bool _isChecked(Map<String, dynamic> item) {
    return _findSelectedIndex(item) >= 0;
  }

  // ─── 商品字段工具方法 ─────────────────────────────────────
  String _getProductName(Map<String, dynamic> item) {
    return item['productname']?.toString() ?? item['name']?.toString() ?? '-';
  }

  String _getUnit(Map<String, dynamic> item) {
    return item['unit']?.toString() ?? '';
  }

  String _getSpec(Map<String, dynamic> item) {
    return item['spec']?.toString() ??
        item['guige']?.toString() ??
        item['specification']?.toString() ??
        '';
  }

  String _getStock(Map<String, dynamic> item) {
    return item['stock']?.toString() ?? item['stockqty']?.toString() ?? '0';
  }

  /// 采购价文本（对齐小程序 selectProduct.vue 真值链 item.cgprice || item.price）：
  /// cgprice 为空、不可解析或为 0 时回退档案进价 price；两者均无效时返回 fallback
  String _cgPriceText(Map<String, dynamic> item, {String fallback = '0.00'}) {
    for (final key in const ['cgprice', 'price']) {
      final raw = item[key];
      if (raw == null) continue;
      final value = double.tryParse(raw.toString());
      if (value != null && value != 0) return raw.toString();
    }
    return fallback;
  }

  String _getPrice(Map<String, dynamic> item) {
    // 对齐 lxAss: cgpriceflag 模式下取 cgprice，否则取 sellprice（默认）
    final cgpriceflag = widget.mergData?['cgpriceflag']?.toString() == '1';
    if (cgpriceflag) {
      // 对齐小程序：cgprice 为空或为 0 时回退档案进价 price
      return _cgPriceText(item);
    }
    // 配送价模式（连锁模块单据：pspriceflag=1 时取 lspsprice 配送价）
    final pspriceflag = widget.mergData?['pspriceflag']?.toString() == '1';
    if (pspriceflag) {
      return item['lspsprice']?.toString() ?? item['price']?.toString() ?? '0.00';
    }
    return item['sellprice']?.toString() ?? item['price']?.toString() ?? '0.00';
  }

  String _getBarcode(Map<String, dynamic> item) {
    return item['barcode']?.toString() ?? item['itemcode']?.toString() ?? '';
  }

  String _getRetailPrice(Map<String, dynamic> item) {
    return item['retailprice']?.toString() ??
        item['lsprice']?.toString() ??
        item['saleprice']?.toString() ??
        _getPrice(item);
  }

  String _getShelves(Map<String, dynamic> item) {
    return item['shelves']?.toString() ?? '';
  }

  String _getSize(Map<String, dynamic> item) {
    return item['size']?.toString() ?? _getSpec(item);
  }

  String _getImageUrl(Map<String, dynamic> item) {
    final path =
        item['imageurl']?.toString() ?? item['imgurl']?.toString() ?? item['pic']?.toString() ?? '';
    if (path.isEmpty) return '';
    // 已经是完整 URL 则直接返回
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${Constant.imageBaseUrl}/$path';
  }

  // ─── 批发模块：调接口查询规格/单位选项（复用 pf_order/edit.dart 逻辑） ───
  Future<Map<String, dynamic>?> _showExtendOptions(String type, Map<String, dynamic> item) async {
    final String productid = item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
    if (productid.isEmpty) return null;

    final mergData = widget.mergData ?? <String, dynamic>{};
    final params = <String, dynamic>{
      'productid': productid,
      'cgpriceflag': 1,
      'bsid': mergData['bsid']?.toString() ?? '',
      'custid': mergData['custid']?.toString() ?? '',
      'itemtype': item['itemtype']?.toString() ?? '',
      'packageflag': item['packageflag']?.toString() ?? '',
      'specflag': item['specflag']?.toString() ?? '',
      'pfpriceflag': 1,
      'needbatchflag': 1,
      'itemstatus': '1,2',
      'is_page': 1,
    };
    if (type == 'size') {
      params['counterid'] = mergData['counterid']?.toString() ?? '';
    }

    return _showExtendOptionsWithParams(type, params);
  }

  // ─── 库存单据（其他出库/其他入库/转仓/成本变更）：调接口查询规格/单位选项 ───
  // 查询参数对齐 zmProMax inventory/*/edit.vue 的 unit-form-item mergeData。
  // 其他出库/其他入库带 counterid/needbatchflag/stockflag；转仓单与成本变更单不带（withStock=false）。
  Future<Map<String, dynamic>?> _showStockExtendOptions(String type, Map<String, dynamic> item,
      {bool withStock = true}) async {
    final String productid = item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
    if (productid.isEmpty) return null;

    final params = <String, dynamic>{
      'page': 1,
      'pagesize': 99999,
      'is_page': 0,
      'ptype': 1,
      'commonflag': 1,
      'productid': productid,
      'bsid': (widget.storeid ?? '').toString(),
      'itemtype': item['itemtype']?.toString() ?? '',
      'packageflag': item['packageflag']?.toString() ?? '',
      'specflag': item['specflag']?.toString() ?? '',
      if (withStock) ...{
        'counterid': widget.counterid ?? '',
        'needbatchflag': 1,
        'stockflag': 1,
      },
    };
    return _showExtendOptionsWithParams(type, params);
  }

  /// 通用的规格/单位选项查询 + 底部弹窗（批发与库存模块共用）
  Future<Map<String, dynamic>?> _showExtendOptionsWithParams(
      String type, Map<String, dynamic> params) async {
    final result = await request(HttpApi.productGetExtendList, params);
    final data = result['data'];
    final rawList = (data is Map<String, dynamic>
            ? (type == 'size' ? data['sizelist'] : data['packlist'])
            : null) as List? ??
        [];
    if (rawList.isEmpty) {
      Toast.show('无可选${type == 'unit' ? '单位' : '规格'}');
      return null;
    }

    // 字段映射：selectCom 中 getProductExtendList 的特殊处理
    final list = rawList.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      if (type == 'size') {
        m['_name'] = m['size']?.toString() ?? m['sname']?.toString() ?? '';
        m['_id'] = m['sizeonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
      } else {
        m['_name'] = m['unit']?.toString() ?? m['sunit']?.toString() ?? '';
        m['_id'] = m['unitonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
      }
      return m;
    }).toList();

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Text('选择${type == 'unit' ? '单位' : '规格'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final opt = list[i];
                  final name = opt['_name']?.toString() ?? '';
                  return ListTile(
                    title: Text(name),
                    onTap: () => Navigator.pop(ctx, opt),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 静默获取当前规格对应的扩展数据（不弹选择框），用于初始价格/库存回填
  Future<Map<String, dynamic>?> _fetchDefaultSpecData(
      Map<String, dynamic> item, String targetSize) async {
    final String productid = item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
    if (productid.isEmpty || targetSize.isEmpty) return null;

    final mergData = widget.mergData ?? <String, dynamic>{};
    final params = <String, dynamic>{
      'productid': productid,
      'cgpriceflag': 1,
      'bsid': mergData['bsid']?.toString() ?? '',
      'custid': mergData['custid']?.toString() ?? '',
      'itemtype': item['itemtype']?.toString() ?? '',
      'packageflag': item['packageflag']?.toString() ?? '',
      'specflag': item['specflag']?.toString() ?? '',
      'pfpriceflag': 1,
      'needbatchflag': 1,
      'itemstatus': '1,2',
      'is_page': 1,
      'counterid': mergData['counterid']?.toString() ?? '',
    };

    final result = await request(HttpApi.productGetExtendList, params);
    final data = result['data'];
    final rawList = (data is Map<String, dynamic> ? data['sizelist'] : null) as List? ?? [];
    if (rawList.isEmpty) return null;

    for (final e in rawList) {
      final m = Map<String, dynamic>.from(e as Map);
      final sz = m['size']?.toString() ?? m['sname']?.toString() ?? '';
      if (sz == targetSize) {
        m['_name'] = sz;
        m['_id'] = m['sizeonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
        return m;
      }
    }
    return null;
  }

  // ─── 商品详情右侧抽屉（根据 billtypeflag 动态展示字段） ────────────────────
  Future<void> _showProductDetail(Map<String, dynamic> item) async {
    final billType = widget.billtypeflag ?? '';
    final cgpriceflag = widget.mergData?['cgpriceflag']?.toString() == '1';
    final paramJust = widget.paramJust ?? const <String>[];
    if (billType == 'ypd' || billType == 'kspd') {
      _showInventoryDetail(item);
    } else if (paramJust.contains('newcostprice')) {
      // 成本变更单：原成本价/新成本价/变更差额/备注（对齐 lxAss costChange paramJust）
      _showCostChangeDetail(item);
    } else if (billType == 'kctz' || billType == 'ycd') {
      // 库存单据（其他出库/其他入库/转仓）：单位/规格/数量/商品批次/生产日期/有效日期/备注
      _showStockDetail(item);
    } else if (cgpriceflag) {
      // 采购入库模块（cgpriceflag=1）：使用采购详情页（含单位/规格选择 + cgprice 价格逻辑）
      _showPurchaseDetail(item);
    } else if (widget.mergData != null) {
      // 批发模块（pforder/pfsale/pfreturn）：使用与编辑弹窗一致的详情页
      await _showWholesaleDetail(item);
    } else {
      _showPurchaseDetail(item);
    }
  }

  // ─── 采购入库抽屉（默认 / cgpriceflag）：单位/规格/数量/赠送数量/备注/价格 ────────────────────
  void _showPurchaseDetail(Map<String, dynamic> item) {
    final name = _getProductName(item);
    final barcode = _getBarcode(item);
    final stock = _getStock(item);
    final price = _getPrice(item);
    final retailPrice = _getRetailPrice(item);
    final shelves = _getShelves(item);
    final cgpriceflag = widget.mergData?['cgpriceflag']?.toString() == '1';
    // 读取 paramJust 配置（对齐小程序各页面 paramJust，控制字段显示与编辑权限）
    final purchaseParamJust = widget.paramJust ?? const <String>[];

    final existIdx = _findSelectedIndex(item);
    final existItem = existIdx >= 0 ? _selectedItems[existIdx] : null;

    var currentUnit = existItem?['unit']?.toString() ?? _getUnit(item);
    var currentSize = existItem?['size']?.toString() ?? _getSize(item);
    var currentRemark = existItem?['remark']?.toString() ?? item['remark']?.toString() ?? '';
    var editBatchno = existItem?['batchno']?.toString() ?? item['batchno']?.toString() ?? '';
    var editBirthdate = existItem?['birthdate']?.toString() ?? item['birthdate']?.toString() ?? '';
    var editValiddate = existItem?['validdate']?.toString() ?? item['validdate']?.toString() ?? '';
    // 数量支持小数（对齐小程序 qty 可为小数：instore formatDecimal(1)/cgorder formatDecimal(2)）
    double qty = existItem != null ? (double.tryParse(existItem['qty']?.toString() ?? '') ?? 1) : 1;
    double giftQty =
        existItem != null ? (double.tryParse(existItem['giftqty']?.toString() ?? '') ?? 0) : 0;

    final FocusNode qtyFocusNode = FocusNode();
    final TextEditingController qtyController =
        TextEditingController(text: MathUtils.formatDecimal(1, qty));
    qtyFocusNode.addListener(() {
      if (qtyFocusNode.hasFocus) {
        qtyController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: qtyController.text.length,
        );
      }
    });
    final FocusNode giftFocusNode = FocusNode();
    final TextEditingController giftController =
        TextEditingController(text: MathUtils.formatDecimal(1, giftQty));
    // 价格/零售价/小计金额（可编辑，对齐 Vue proDetails.vue price/sellprice/amt 字段）
    // 不使用外部 FocusNode，让 TextField 自行管理内部 FocusNode 生命周期
    // 价格回显优先级：回传的选中项（existItem）→ 商品档案（item）——对齐 Vue proDetails openFn
    // 直接用 detaillist 行数据（已保存/已修改值）展示，避免再次打开抽屉时被档案原价覆盖
    // 导致手动金额确认时被错误反算（instore：price = amt / qty 或 qty = amt / 档案价）
    // 优先取 price（各页面 selectList 必写的修改值），cgprice 兜底（rawData 可能残留档案价）
    final String existPriceText =
        existItem?['price']?.toString() ?? existItem?['cgprice']?.toString() ?? '';
    final TextEditingController priceController = TextEditingController(
        text: existPriceText.isNotEmpty ? existPriceText : (item['price']?.toString() ?? price));
    final TextEditingController sellpriceController = TextEditingController(
        text: existItem?['sellprice']?.toString() ??
            existItem?['retailprice']?.toString() ??
            retailPrice);
    // 小计金额初始值：手动修改过的商品（_amtManual）回显其 amt，否则按 qty × price 计算
    // （对齐 Vue proDetails openFn：userAmt 恢复 + writeData amt 反算）
    final double initPrice = double.tryParse(
            existPriceText.isNotEmpty ? existPriceText : (item['price']?.toString() ?? price)) ??
        0;
    final TextEditingController amtController = TextEditingController(
        text: (existItem?['_amtManual'] == true && existItem?['amt'] != null)
            ? MathUtils.formatDecimal(
                3, double.tryParse(existItem!['amt'].toString()) ?? MathUtils.mul(qty, initPrice))
            : MathUtils.formatDecimal(3, MathUtils.mul(qty, initPrice)));
    // 小计金额是否被用户手动修改（对齐 Vue writeData 的 _amtManual；重新打开抽屉时沿用上次标记）
    bool amtManual = existItem?['_amtManual'] == true;
    // 程序性更新金额标志：避免重算回写文本时误标记手动修改
    bool updatingAmt = false;
    // 价格变化 → 重置手动金额标记并重算小计（对齐 Vue writeData key==price：
    // writeData 开头 _amtManual=false，收尾 amt = qty × price）
    priceController.addListener(() {
      if (updatingAmt) return;
      amtManual = false;
      final p = double.tryParse(priceController.text) ?? 0;
      updatingAmt = true;
      amtController.text = MathUtils.formatDecimal(3, MathUtils.mul(qty, p));
      updatingAmt = false;
    });
    // 小计金额输入 → 标记手动修改（对齐 Vue writeData key==amt 的 _amtManual）
    amtController.addListener(() {
      if (updatingAmt) return;
      amtManual = true;
    });

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.82,
              height: MediaQuery.of(ctx).size.height,
              decoration: const BoxDecoration(color: Colors.white),
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (ctx, setDialogState) {
                    // ─── 小计金额反算（对齐 Vue writeData key=amt 分支）───
                    // amt 失焦/回车/确认时：amtManual=true 保留金额，并按页面参数反算
                    // 数量（qty = amt / price，cgorder 等）或单价（price = amt / qty，instore 默认）
                    void applyAmtRecalc() {
                      // 去除输入尾部 '.'（如 "5."），空值按 0 处理
                      final amtText = amtController.text.trim().replaceAll(RegExp(r'\.$'), '');
                      final amtVal = double.tryParse(amtText) ?? 0;
                      amtManual = true;
                      // 归一化金额精度（对齐 Vue formatDecimal(3, amt * 1)）
                      updatingAmt = true;
                      amtController.text = MathUtils.formatDecimal(3, amtVal);
                      updatingAmt = false;
                      double newQty = qty;
                      double newPrice = double.tryParse(priceController.text) ?? 0;
                      if (widget.amtRecalcQty) {
                        // 反算数量：qty = amt / price（除零置 0 防 Infinity，对齐各单据 amt 分支）
                        newQty = newPrice == 0
                            ? 0
                            : MathUtils.formatDecimalNum(
                                widget.amtQtyDecimals, MathUtils.divide(amtVal, newPrice));
                        qty = newQty;
                        qtyController.text = MathUtils.formatDecimal(1, newQty);
                      } else {
                        // 反算单价：price = amt / qty（数量为 0 时保留原价，对齐 instore amt 分支）
                        newPrice = qty == 0
                            ? newPrice
                            : MathUtils.formatDecimalNum(2, MathUtils.divide(amtVal, qty));
                        updatingAmt = true;
                        priceController.text = MathUtils.formatDecimal(2, newPrice);
                        updatingAmt = false;
                      }
                      // 系统参数 cgAmountRecalculationflag==1 时金额始终按 qty × price 重算
                      // （对齐 writeData 收尾分支）
                      if (_loginParamInt('cgAmountRecalculationflag') == 1) {
                        updatingAmt = true;
                        amtController.text =
                            MathUtils.formatDecimal(3, MathUtils.mul(newQty, newPrice));
                        updatingAmt = false;
                      }
                      // 重建抽屉：刷新数量步进器的 value 快照（反算后的 qty 同步到 +/- 按钮）
                      if (ctx.mounted) setDialogState(() {});
                    }

                    // ─── 单位/规格可选条件（对齐 Vue proDetails.vue cgpriceflag 逻辑）───
                    // cgpriceflag: unitCanSelect = productid 存在 && sizeonlyid 为空
                    // 非 cgpriceflag: unitCanSelect = packageflag == 1 || (pfsale && specflag == 1)
                    final productid =
                        item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
                    final sizeonlyid = item['sizeonlyid']?.toString() ?? '';
                    final unitonlyid = item['unitonlyid']?.toString() ?? '';
                    final specflag = item['specflag']?.toString() ?? '';
                    final packageflag = item['packageflag']?.toString() ?? '';
                    final bool unitCanSelect = cgpriceflag
                        ? (productid.isNotEmpty && sizeonlyid.isEmpty)
                        : (packageflag == '1');
                    final bool sizeCanSelect = cgpriceflag
                        ? (specflag == '1' && unitonlyid.isEmpty)
                        : (specflag == '1' && unitonlyid.isEmpty);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDrawerHeader(ctx, '商品详情'),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProductInfoCard(
                                    name, barcode, price, shelves, stock, currentUnit, currentSize),
                                if (cgpriceflag) ...[
                                  const SizedBox(height: 8),
                                  _buildInfoRow('原进价', price),
                                ],
                                const SizedBox(height: 12),
                                const Divider(color: Color(0xFFE5E7EB)),
                                const SizedBox(height: 12),
                                // 单位（对齐 Vue proDetails.vue unit 字段）
                                _buildSelectField(
                                    '单位', currentUnit.isNotEmpty ? currentUnit : '请选择',
                                    onTap: unitCanSelect
                                        ? () async {
                                            final result = await _showExtendOptions('unit', item);
                                            if (result != null) {
                                              setDialogState(() {
                                                final u = result['unit']?.toString() ??
                                                    result['_name']?.toString() ??
                                                    '';
                                                if (u.isNotEmpty) currentUnit = u;
                                                final uid = result['unitonlyid']?.toString() ??
                                                    result['_id']?.toString() ??
                                                    '';
                                                if (uid.isNotEmpty) {
                                                  item['unitonlyid'] = uid;
                                                  currentSize =
                                                      item['_mainSize']?.toString() ?? currentSize;
                                                  item['size'] = currentSize;
                                                  item['sizeonlyid'] =
                                                      item['_mainSizeonlyid']?.toString() ?? '';
                                                }
                                                // cgpriceflag 模式：selectUnitFn 价格逻辑
                                                if (cgpriceflag) {
                                                  final cgprice = result['cgprice']?.toString();
                                                  if (cgprice != null) {
                                                    item['cgprice'] = cgprice;
                                                    item['price'] = cgprice;
                                                  }
                                                  final inprice = result['inprice']?.toString();
                                                  if (inprice != null) item['inprice'] = inprice;
                                                  final oldprice =
                                                      result['oldprice']?.toString() ?? cgprice;
                                                  item['oldprice'] = oldprice;
                                                  // 批发价同步
                                                  for (final key in [
                                                    'pfprice1',
                                                    'pfprice2',
                                                    'pfprice3',
                                                    'mprice1',
                                                    'mprice2',
                                                    'mprice3',
                                                    'psprice'
                                                  ]) {
                                                    final v = result[key]?.toString();
                                                    if (v != null) item[key] = v;
                                                  }
                                                  final pfprice = result['pfprice']?.toString() ??
                                                      result['pfprice1']?.toString();
                                                  if (pfprice != null) item['pfprice'] = pfprice;
                                                  final mprice = result['mprice']?.toString() ??
                                                      result['mprice1']?.toString();
                                                  if (mprice != null) item['mprice'] = mprice;
                                                }
                                                // 条码更新
                                                final nb = result['sbarcode']?.toString() ??
                                                    result['barcode']?.toString();
                                                if (nb != null) item['barcode'] = nb;
                                                // 零售价更新
                                                final nr = result['sellprice']?.toString() ??
                                                    result['retailprice']?.toString();
                                                if (nr != null && nr.isNotEmpty) {
                                                  item['sellprice'] = nr;
                                                  item['retailprice'] = nr;
                                                }
                                                // packagenum: 选了单位后设为 1
                                                if (uid.isNotEmpty) item['packagenum'] = 1;
                                              });
                                            }
                                          }
                                        : null),
                                const SizedBox(height: 12),
                                // 规格（对齐 Vue proDetails.vue size 字段）
                                _buildSelectField(
                                    '规格', currentSize.isNotEmpty ? currentSize : '请选择',
                                    onTap: sizeCanSelect
                                        ? () async {
                                            final result = await _showExtendOptions('size', item);
                                            if (result != null) {
                                              setDialogState(() {
                                                final s = result['size']?.toString() ??
                                                    result['_name']?.toString() ??
                                                    '';
                                                if (s.isNotEmpty) currentSize = s;
                                                if (item['_mainSize'] == null) {
                                                  item['_mainSize'] = item['size'] ?? currentSize;
                                                  item['_mainSizeonlyid'] =
                                                      item['sizeonlyid']?.toString() ?? '';
                                                }
                                                final sid = result['sizeonlyid']?.toString() ??
                                                    result['_id']?.toString() ??
                                                    '';
                                                if (sid.isNotEmpty) item['sizeonlyid'] = sid;
                                                // 价格：cgpriceflag 模式下取 cgprice，否则取 sellprice
                                                if (cgpriceflag) {
                                                  final p = result['cgprice']?.toString();
                                                  if (p != null) item['price'] = p;
                                                } else {
                                                  final p = result['sellprice']?.toString();
                                                  if (p != null) item['price'] = p;
                                                }
                                                // 条码更新
                                                final nb = result['sbarcode']?.toString() ??
                                                    result['barcode']?.toString();
                                                if (nb != null) item['barcode'] = nb;
                                                // 零售价更新
                                                final nr = result['sellprice']?.toString() ??
                                                    result['retailprice']?.toString();
                                                if (nr != null && nr.isNotEmpty) {
                                                  item['sellprice'] = nr;
                                                  item['retailprice'] = nr;
                                                }
                                              });
                                            }
                                          }
                                        : null),
                                const SizedBox(height: 12),
                                _buildQtyRow('数量', qty, qtyFocusNode, qtyController,
                                    onChanged: (v) {
                                  if (v < 1) return;
                                  setDialogState(() {
                                    qty = v;
                                    // 数量变化 → 重置手动金额标记并重算小计
                                    // （对齐 Vue writeData qty 分支：_amtManual=false → amt = qty × price）
                                    amtManual = false;
                                    final p = double.tryParse(priceController.text) ?? 0;
                                    updatingAmt = true;
                                    amtController.text =
                                        MathUtils.formatDecimal(3, MathUtils.mul(v, p));
                                    updatingAmt = false;
                                  });
                                }),
                                const SizedBox(height: 12),
                                _buildQtyRow('赠送数量', giftQty, giftFocusNode, giftController,
                                    onChanged: (v) {
                                  if (v >= 0) setDialogState(() => giftQty = v);
                                }),
                                const SizedBox(height: 12),
                                // 商品批次（使用 SelectBatchSheet 选择，带出日期）
                                _buildSelectField(
                                    '商品批次', editBatchno.isNotEmpty ? editBatchno : '请选择',
                                    onTap: () async {
                                  final productid = item['productid']?.toString() ??
                                      item['prodid']?.toString() ??
                                      '';
                                  if (productid.isEmpty) {
                                    Toast.show('商品信息异常');
                                    return;
                                  }
                                  final batchResult =
                                      await showModalBottomSheet<Map<String, dynamic>>(
                                    context: ctx,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => SelectBatchSheet(
                                      productid: productid,
                                      bsid: (widget.storeid ?? '').toString(),
                                      counterid: widget.counterid ?? '',
                                      initialBatchNo: editBatchno,
                                    ),
                                  );
                                  if (batchResult != null) {
                                    setDialogState(() {
                                      editBatchno = batchResult['batchno']?.toString() ?? '';
                                      // 选择批次后自动带出生产日期和有效期（对齐 web handleBatchConfirm）
                                      editBirthdate = _formatBatchDate(batchResult['birthdate']);
                                      final bd = editBirthdate.isNotEmpty ? editBirthdate : '';
                                      editValiddate = _formatBatchDate(batchResult['validdate']);
                                      if (editValiddate.isEmpty && bd.isNotEmpty) {
                                        editValiddate = bd;
                                      }
                                    });
                                  }
                                }),
                                const SizedBox(height: 12),
                                // 生产日期
                                _buildSelectField(
                                    '生产日期', editBirthdate.isNotEmpty ? editBirthdate : '请选择',
                                    onTap: () {
                                  _pickInventoryDate(ctx, editBirthdate).then((v) {
                                    if (v != null) setDialogState(() => editBirthdate = v);
                                  });
                                }),
                                const SizedBox(height: 12),
                                // 有效日期
                                _buildSelectField(
                                    '有效日期', editValiddate.isNotEmpty ? editValiddate : '请选择',
                                    onTap: () {
                                  _pickInventoryDate(ctx, editValiddate).then((v) {
                                    if (v != null) setDialogState(() => editValiddate = v);
                                  });
                                }),
                                const SizedBox(height: 12),
                                _buildRemarkRow('备注', currentRemark, onChanged: (v) {
                                  setDialogState(() => currentRemark = v);
                                }),
                                const SizedBox(height: 16),
                                const Divider(color: Color(0xFFE5E7EB)),
                                const SizedBox(height: 12),
                                // 原进价（仅非 cgpriceflag 模式在此显示，cgpriceflag 模式已在 L829 显示）
                                if (!cgpriceflag) _buildInfoRow('原进价', price),
                                if (!cgpriceflag) const SizedBox(height: 8),
                                // 价格（按 paramJust 控制——对齐 Vue proDetails.vue，仅包含 'price' 时显示）
                                if (purchaseParamJust.contains('price'))
                                  _buildEditableRow('价格', priceController),
                                if (purchaseParamJust.contains('price')) const SizedBox(height: 8),
                                // 零售价（按 paramJust 控制——对齐 Vue proDetails.vue，仅包含 'sellprice' 时显示）
                                if (purchaseParamJust.contains('sellprice'))
                                  _buildEditableRow('零售价', sellpriceController),
                                if (purchaseParamJust.contains('sellprice'))
                                  const SizedBox(height: 8),
                                // 小计金额（按 paramJust 控制——对齐 Vue proDetails.vue，仅包含 'amt' 时显示）
                                if (purchaseParamJust.contains('amt'))
                                  _buildEditableRow(
                                    '小计金额',
                                    amtController,
                                    // 失焦/回车 → 反算单价或数量（对齐 Vue @blur 触发 writeData key=amt）
                                    onSubmitted: (_) => applyAmtRecalc(),
                                    onFocusChange: (hasFocus) {
                                      if (!hasFocus) applyAmtRecalc();
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                        _buildDrawerBottom(ctx,
                            onCancel: () => Navigator.pop(ctx),
                            onConfirm: () {
                              // 手动修改过小计金额时先反算（对齐 Vue detailConfirm：userAmt 恢复后 writeData key=amt）
                              if (amtManual) applyAmtRecalc();
                              final result = Map<String, dynamic>.from(item);
                              result['qty'] = qty;
                              result['giftqty'] = giftQty;
                              result['unit'] = currentUnit;
                              result['size'] = currentSize;
                              result['remark'] = currentRemark;
                              result['batchno'] = editBatchno;
                              result['birthdate'] = editBirthdate;
                              result['validdate'] = editValiddate;
                              // 价格/零售价/小计金额（可编辑，对齐 Vue proDetails.vue price/sellprice/amt）
                              final confirmPrice = double.tryParse(priceController.text) ?? 0;
                              final confirmSellprice =
                                  double.tryParse(sellpriceController.text) ?? 0;
                              result['price'] = MathUtils.formatDecimalNum(2, confirmPrice);
                              result['cgprice'] = MathUtils.formatDecimalNum(2, confirmPrice);
                              result['sellprice'] = MathUtils.formatDecimalNum(2, confirmSellprice);
                              // 小计金额：手动修改过则用输入值（applyAmtRecalc 已归一化/按参数重算），
                              // 否则 qty × price（对齐 Vue writeData 收尾分支）
                              result['amt'] = MathUtils.formatDecimalNum(
                                  3,
                                  amtManual
                                      ? (double.tryParse(amtController.text) ?? 0)
                                      : MathUtils.mul(qty, confirmPrice));
                              // 手动金额标记随结果传递（_confirm 补全 amt 时跳过手动项，对齐 Vue _amtManual）
                              result['_amtManual'] = amtManual;
                              // 写回 item，保证再次打开该商品详情时回显修改后的值
                              item['price'] = result['price'];
                              item['cgprice'] = result['price'];
                              item['sellprice'] = result['sellprice'];
                              item['retailprice'] = result['sellprice'];
                              item['qty'] = qty;
                              item['giftqty'] = giftQty;
                              item['_amtManual'] = amtManual;
                              Navigator.pop(ctx);
                              setState(() {
                                if (existIdx >= 0) {
                                  _selectedItems[existIdx] = result;
                                } else {
                                  _selectedItems.add(result);
                                }
                              });
                            }),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      // 延迟到抽屉退出动画(280ms)结束后再释放 FocusNode/Controller：
      // 退出动画期间 TextField 仍挂载，立即 dispose 会在键盘收起触发焦点清理时
      // 报 "FocusNode/TextEditingController was used after being disposed"（手动输入小计金额后点确认必现）
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        qtyFocusNode.dispose();
        qtyController.dispose();
        giftFocusNode.dispose();
        giftController.dispose();
        priceController.dispose();
        sellpriceController.dispose();
        amtController.dispose();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (qtyFocusNode.canRequestFocus) {
        qtyFocusNode.requestFocus();
      }
    });
  }

  // ─── 批发模块抽屉（mergData 不为空时使用）：数量/赠送数量/价格/单位/规格/备注 ───
  Future<void> _showWholesaleDetail(Map<String, dynamic> item) async {
    final name = _getProductName(item);
    final shelves = _getShelves(item);

    final existIdx = _findSelectedIndex(item);
    final existItem = existIdx >= 0 ? _selectedItems[existIdx] : null;

    var currentUnit = existItem?['unit']?.toString() ?? _getUnit(item);
    var currentSize = existItem?['size']?.toString() ?? _getSize(item);

    // ─── 初始值：优先从扩展接口获取当前规格对应的价格/库存 ───
    var stock = _getStock(item);
    double initialPrice = 0;

    // defValSet 价格优先级：custdiscountprice > custprice > price
    final cdd = double.tryParse(item['custdiscountprice']?.toString() ?? '0') ?? 0;
    final cp = double.tryParse(item['custprice']?.toString() ?? '0') ?? 0;
    final rawP = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
    initialPrice = cdd > 0 ? cdd : (cp > 0 ? cp : rawP);

    // 尝试拉取当前规格对应的扩展数据（对齐 lxAss 规格切换行为）
    if (currentSize.isNotEmpty && item['specflag']?.toString() == '1') {
      final specData = await _fetchDefaultSpecData(item, currentSize);
      if (specData != null) {
        // 价格：defValSet 优先级 custdiscountprice > custprice > price
        final scdd = double.tryParse(specData['custdiscountprice']?.toString() ?? '') ?? 0;
        final scp = double.tryParse(specData['custprice']?.toString() ?? '') ?? 0;
        final srp = double.tryParse(specData['price']?.toString() ?? '') ?? 0;
        final sp = scdd > 0 ? scdd : (scp > 0 ? scp : srp);
        if (sp > 0) initialPrice = sp;
        // 库存：规格对应的 stockqty
        final sq = specData['stockqty']?.toString() ?? specData['stock']?.toString();
        if (sq != null && sq.isNotEmpty) stock = sq;
        // 零售价
        final nr = specData['sellprice']?.toString() ??
            specData['retailprice']?.toString() ??
            specData['lsprice']?.toString();
        if (nr != null && nr.isNotEmpty) {
          item['retailprice'] = nr;
          item['sellprice'] = nr;
        }
        // 同步 custprice 到 item，使后续 defValSet 能正确取值
        final ecp = specData['custprice']?.toString();
        if (ecp != null && ecp.isNotEmpty) item['custprice'] = double.tryParse(ecp);
      }
    }

    final defaultPrice = existItem?['price']?.toString() ?? initialPrice.toStringAsFixed(2);

    var currentRemark = existItem?['remark']?.toString() ?? item['remark']?.toString() ?? '';
    int qty = existItem != null ? (int.tryParse(existItem['qty']?.toString() ?? '1') ?? 1) : 1;
    int giftQty =
        existItem != null ? (int.tryParse(existItem['giftqty']?.toString() ?? '0') ?? 0) : 0;

    final FocusNode qtyFocusNode = FocusNode();
    final TextEditingController qtyController = TextEditingController(text: '$qty');
    qtyFocusNode.addListener(() {
      if (qtyFocusNode.hasFocus) {
        qtyController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: qtyController.text.length,
        );
      }
    });
    final FocusNode giftFocusNode = FocusNode();
    final TextEditingController giftController = TextEditingController(text: '$giftQty');
    final FocusNode priceFocusNode = FocusNode();
    final TextEditingController priceController = TextEditingController(text: defaultPrice);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.82,
              height: MediaQuery.of(ctx).size.height,
              decoration: const BoxDecoration(color: Colors.white),
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (ctx, setDialogState) {
                    final curPrice = double.tryParse(priceController.text) ?? 0;
                    final curQty = qty;
                    final subtotal = curPrice * curQty;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDrawerHeader(ctx, '商品详情'),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProductInfoCard(name, _getBarcode(item), _getPrice(item),
                                    shelves, stock, currentUnit, currentSize),
                                const SizedBox(height: 12),
                                const Divider(color: Color(0xFFE5E7EB)),
                                const SizedBox(height: 12),
                                // 单位（可点击选择）
                                _buildSelectField(
                                    '单位', currentUnit.isNotEmpty ? currentUnit : '请选择',
                                    onTap: (item['packageflag']?.toString() != '1' ||
                                            item['specflag']?.toString() == '1')
                                        ? () async {
                                            final result = await _showExtendOptions('unit', item);
                                            if (result != null) {
                                              setDialogState(() {
                                                final u = result['unit']?.toString() ??
                                                    result['_name']?.toString() ??
                                                    '';
                                                if (u.isNotEmpty) currentUnit = u;
                                                final uid = result['unitonlyid']?.toString() ??
                                                    result['_id']?.toString() ??
                                                    '';
                                                if (uid.isNotEmpty) {
                                                  item['unitonlyid'] = uid;
                                                  currentSize =
                                                      item['_mainSize']?.toString() ?? currentSize;
                                                  item['size'] = currentSize;
                                                  item['sizeonlyid'] =
                                                      item['_mainSizeonlyid']?.toString() ?? '';
                                                }
                                                // lxAss selectUnitFn(cgpriceflag=false) → price = custprice
                                                final p = result['custprice']?.toString();
                                                if (p != null) {
                                                  priceController.text = p;
                                                }
                                                // 单位切换更新条码（对齐编辑页 _onSelect 行为）
                                                final nb = result['sbarcode']?.toString() ??
                                                    result['barcode']?.toString();
                                                if (nb != null) item['barcode'] = nb;
                                                // lxAss selectUnitFn: code = scode || code
                                                final nc = result['scode']?.toString() ??
                                                    result['code']?.toString();
                                                if (nc != null) item['code'] = nc;
                                                // 零售价更新（lxAss: sellprice）
                                                final nr = result['sellprice']?.toString() ??
                                                    result['retailprice']?.toString() ??
                                                    result['lsprice']?.toString();
                                                if (nr != null && nr.isNotEmpty) {
                                                  item['retailprice'] = nr;
                                                  item['sellprice'] = nr;
                                                }
                                                // 库存更新（lxAss: stockqty）
                                                final ns = result['stockqty']?.toString() ??
                                                    result['stock']?.toString();
                                                if (ns != null && ns.isNotEmpty) {
                                                  stock = ns;
                                                  item['stock'] = ns;
                                                }
                                              });
                                            }
                                          }
                                        : null),
                                const SizedBox(height: 12),
                                // 规格（可点击选择）
                                _buildSelectField(
                                    '规格', currentSize.isNotEmpty ? currentSize : '请选择',
                                    onTap: (item['specflag']?.toString() == '1' &&
                                            (item['unitonlyid'] == null ||
                                                (item['unitonlyid']?.toString().isEmpty ?? false)))
                                        ? () async {
                                            final result = await _showExtendOptions('size', item);
                                            if (result != null) {
                                              setDialogState(() {
                                                final s = result['size']?.toString() ??
                                                    result['_name']?.toString() ??
                                                    '';
                                                if (s.isNotEmpty) currentSize = s;
                                                if (item['_mainSize'] == null) {
                                                  item['_mainSize'] = item['size'] ?? currentSize;
                                                  item['_mainSizeonlyid'] =
                                                      item['sizeonlyid']?.toString() ?? '';
                                                }
                                                final sid = result['sizeonlyid']?.toString() ??
                                                    result['_id']?.toString() ??
                                                    '';
                                                if (sid.isNotEmpty) item['sizeonlyid'] = sid;
                                                // lxAss selectSizeFn(pricetype="sellprice") → price = sellprice
                                                final p = result['sellprice']?.toString();
                                                if (p != null) {
                                                  priceController.text = p;
                                                }
                                                // lxAss selectSizeFn(pfsale): barcode = sbarcode || barcode
                                                final nb = result['sbarcode']?.toString() ??
                                                    result['barcode']?.toString();
                                                if (nb != null) item['barcode'] = nb;
                                                // lxAss selectSizeFn(pfsale): code = scode || code
                                                final nc = result['scode']?.toString() ??
                                                    result['code']?.toString();
                                                if (nc != null) item['code'] = nc;
                                                // 零售价更新（lxAss: sellprice）
                                                final nr = result['sellprice']?.toString() ??
                                                    result['retailprice']?.toString() ??
                                                    result['lsprice']?.toString();
                                                if (nr != null && nr.isNotEmpty) {
                                                  item['retailprice'] = nr;
                                                  item['sellprice'] = nr;
                                                }
                                                // 库存更新（lxAss: stockqty）
                                                final ns = result['stockqty']?.toString() ??
                                                    result['stock']?.toString();
                                                if (ns != null && ns.isNotEmpty) {
                                                  stock = ns;
                                                  item['stock'] = ns;
                                                }
                                              });
                                            }
                                          }
                                        : null),
                                const SizedBox(height: 12),
                                _buildQtyRow('数量', qty.toDouble(), qtyFocusNode, qtyController,
                                    onChanged: (v) {
                                  if (v >= 1) setDialogState(() => qty = v.toInt());
                                }),
                                const SizedBox(height: 12),
                                _buildQtyRow(
                                    '赠送数量', giftQty.toDouble(), giftFocusNode, giftController,
                                    onChanged: (v) {
                                  if (v >= 0) setDialogState(() => giftQty = v.toInt());
                                }),
                                const SizedBox(height: 12),
                                // 价格（可编辑）
                                _buildPriceRow(priceController, priceFocusNode, onChanged: () {
                                  setDialogState(() {});
                                }),
                                const SizedBox(height: 12),
                                _buildRemarkRow('备注', currentRemark, onChanged: (v) {
                                  setDialogState(() => currentRemark = v);
                                }),
                                const SizedBox(height: 16),
                                const Divider(color: Color(0xFFE5E7EB)),
                                const SizedBox(height: 12),
                                _buildInfoRow('小计金额', subtotal.toStringAsFixed(2)),
                              ],
                            ),
                          ),
                        ),
                        _buildDrawerBottom(ctx,
                            onCancel: () => Navigator.pop(ctx),
                            onConfirm: () {
                              final result = Map<String, dynamic>.from(item);
                              result['qty'] = curQty;
                              result['giftqty'] = giftQty;
                              result['unit'] = currentUnit;
                              result['size'] = currentSize;
                              result['price'] = curPrice;
                              result['pfprice1'] = curPrice;
                              result['amt'] = subtotal;
                              result['remark'] = currentRemark;
                              Navigator.pop(ctx);
                              setState(() {
                                if (existIdx >= 0) {
                                  _selectedItems[existIdx] = result;
                                } else {
                                  _selectedItems.add(result);
                                }
                              });
                            }),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      qtyFocusNode.dispose();
      qtyController.dispose();
      giftFocusNode.dispose();
      giftController.dispose();
      priceFocusNode.dispose();
      priceController.dispose();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (qtyFocusNode.canRequestFocus) {
        qtyFocusNode.requestFocus();
      }
    });
  }

  // ─── 盘点类抽屉（预盘单 ypd / 快速盘点 kspd）：批次/盘点数量/盈亏/日期/备注 ──────
  void _showInventoryDetail(Map<String, dynamic> item) {
    // 多批次商品：本次选择的批次列表（对齐 lxAss proDetails onSelectMultBatch 的 batchList）
    var multBatchList = <Map<String, dynamic>>[];
    final billType = widget.billtypeflag ?? '';
    final isYpd = billType == 'ypd';
    final isKspd = billType == 'kspd';
    final qtyLabel = isYpd ? '预盘数量' : '盘点数量';
    // 数量字段名（对齐 lxAss qtyTypeFn：预盘单 precheckqty / 快速盘点 checkqty）
    final qtyType = isYpd ? 'precheckqty' : 'checkqty';
    // 多批次多选仅对预盘单/快速盘点生效（对齐 lxAss chosePc 仅 preOrder/quickInven 模块），其他单据不启用
    final enableMultBatch = (isYpd || isKspd) && item['morebatchflag']?.toString() == '1';

    final name = _getProductName(item);
    final barcode = _getBarcode(item);
    final stock = _getStock(item);
    final costPrice = item['costprice']?.toString() ?? '0';
    final shelves = _getShelves(item);
    final stockqty = double.tryParse(item['stockqty']?.toString() ?? stock) ?? 0;

    final existIdx = _findSelectedIndex(item);
    final existItem = existIdx >= 0 ? _selectedItems[existIdx] : null;

    final currentUnit = existItem?['unit']?.toString() ?? _getUnit(item);
    final currentSize = existItem?['size']?.toString() ?? _getSize(item);
    // 已确认过的多批次选择回显：从商品数据 batchList 恢复（对齐 lxAss proItem.batchList 持久化）
    final savedBatchList = existItem?['batchList'] ?? item['batchList'];
    if (savedBatchList is List) {
      multBatchList = savedBatchList
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    // 多批次回显：批次逗号拼接（对齐 lxAss proDetails 打开时按 batchList 回显 batchno）
    var editBatchno = multBatchList.isNotEmpty
        ? multBatchList
            .map((e) => e['batchno']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(',')
        : (existItem?['batchno']?.toString() ?? item['batchno']?.toString() ?? '');
    var editBirthdate = existItem?['birthdate']?.toString() ?? item['birthdate']?.toString() ?? '';
    var editValiddate = existItem?['validdate']?.toString() ?? item['validdate']?.toString() ?? '';
    var editSupid = existItem?['supid']?.toString() ?? item['supid']?.toString() ?? '';
    var editRemark = existItem?['remark']?.toString() ?? item['remark']?.toString() ?? '';
    double editQty;
    if (multBatchList.isNotEmpty) {
      // 多批次回显：数量为各批次数量总和（对齐 lxAss onSelectMultBatch totalQty）
      editQty = multBatchList.fold<double>(0, (sum, e) {
        final q = double.tryParse(e[qtyType]?.toString() ?? '0') ?? 0;
        return sum + q;
      });
    } else if (existItem != null) {
      editQty = double.tryParse(existItem['qty']?.toString() ?? '1') ?? 1;
    } else {
      editQty = 1;
    }

    final qtyFocusNode = FocusNode();
    final qtyCtrl = TextEditingController(
      text: editQty == editQty.toInt() ? editQty.toInt().toString() : editQty.toStringAsFixed(1),
    );
    qtyFocusNode.addListener(() {
      if (qtyFocusNode.hasFocus && qtyCtrl.text.isNotEmpty) {
        qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: qtyCtrl.text.length);
      }
    });
    final remarkCtrl = TextEditingController(text: editRemark);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.82,
              height: MediaQuery.of(ctx).size.height,
              decoration: const BoxDecoration(color: Colors.white),
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (ctx, setDialogState) {
                    // 多批次弹窗本地函数（批次字段和数量字段共用，对齐 lxAss chosePc）
                    Future<void> openMultBatch() async {
                      final productid =
                          item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
                      if (productid.isEmpty) {
                        Toast.show('商品信息异常');
                        return;
                      }
                      // 回显已选批次：用当前抽屉的批次列表（已从商品 batchList 恢复），确保勾选状态和数量回显（对齐 lxAss selectMultBatch selectList）
                      final selectList =
                          multBatchList.map((e) => Map<String, dynamic>.from(e)).toList();
                      final multResult = await SelectMultBatchSheet.show(
                        ctx,
                        productid: productid,
                        bsid: (widget.storeid ?? '').toString(),
                        counterid: widget.counterid ?? '',
                        qtyType: qtyType,
                        selectList: selectList,
                      );
                      if (multResult != null) {
                        setDialogState(() {
                          multBatchList =
                              multResult.map((e) => Map<String, dynamic>.from(e)).toList();
                          editBatchno = multResult
                              .map((e) => e['batchno']?.toString() ?? '')
                              .where((s) => s.isNotEmpty)
                              .join(',');
                          // 单选批次时带回生产/有效日期，多条时清空（对齐 lxAss onSelectMultBatch）
                          if (multResult.length == 1) {
                            editBirthdate = _formatBatchDate(multResult.first['birthdate']);
                            editValiddate = _formatBatchDate(multResult.first['validdate']);
                          } else {
                            editBirthdate = '';
                            editValiddate = '';
                          }
                          editSupid = '';
                          editQty = multResult.fold<double>(0, (sum, e) {
                            final q = double.tryParse(e[qtyType]?.toString() ?? '0') ?? 0;
                            return sum + q;
                          });
                        });
                      }
                    }

                    final profitLoss = editQty - stockqty;
                    // 多批次且选中多条批次时隐藏生产/有效日期（对齐 lxAss：!(morebatchflag==1 && batchList.length>1)）
                    final hideDateRows = enableMultBatch && multBatchList.length > 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDrawerHeader(ctx, '商品详情'),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProductInfoCard(name, barcode, _getPrice(item), shelves,
                                    stock, currentUnit, currentSize,
                                    costPrice: costPrice, stockqty: stockqty),
                                const SizedBox(height: 12),
                                const Divider(color: Color(0xFFE5E7EB)),
                                const SizedBox(height: 12),
                                // 单位（只读）
                                _buildInfoRow('单位', currentUnit.isNotEmpty ? currentUnit : '-'),
                                const SizedBox(height: 8),
                                // 规格（只读）
                                _buildInfoRow('规格', currentSize.isNotEmpty ? currentSize : '-'),
                                const SizedBox(height: 12),
                                // 批次（多批次商品跳多选页，单选批次用 SelectBatchSheet，带出日期）
                                _buildSelectField(
                                    '批次', editBatchno.isNotEmpty ? editBatchno : '请选择',
                                    onTap: () async {
                                  final productid = item['productid']?.toString() ??
                                      item['prodid']?.toString() ??
                                      '';
                                  if (productid.isEmpty) {
                                    Toast.show('商品信息异常');
                                    return;
                                  }
                                  // 多批次商品：弹多批次选择（对齐 lxAss proDetails chosePc）
                                  if (enableMultBatch) {
                                    await openMultBatch();
                                    return;
                                  }
                                  final batchResult =
                                      await showModalBottomSheet<Map<String, dynamic>>(
                                    context: ctx,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => SelectBatchSheet(
                                      productid: productid,
                                      bsid: (widget.storeid ?? '').toString(),
                                      counterid: widget.counterid ?? '',
                                      initialBatchNo: editBatchno,
                                    ),
                                  );
                                  if (batchResult != null) {
                                    setDialogState(() {
                                      editBatchno = batchResult['batchno']?.toString() ?? '';
                                      // 选择批次后自动带出生产日期和有效期（对齐 web handleBatchConfirm）
                                      editBirthdate = _formatBatchDate(batchResult['birthdate']);
                                      final bd = editBirthdate.isNotEmpty ? editBirthdate : '';
                                      editValiddate = _formatBatchDate(batchResult['validdate']);
                                      if (editValiddate.isEmpty && bd.isNotEmpty) {
                                        editValiddate = bd;
                                      }
                                      editSupid = batchResult['supid']?.toString() ?? '';
                                    });
                                  }
                                }),
                                const SizedBox(height: 12),
                                // 盘点/预盘数量（多批次时箭头选择跳多选，非多批次保持加减输入）
                                (enableMultBatch
                                    ? _buildSelectField(qtyLabel, editQty.toStringAsFixed(1),
                                        onTap: () {
                                        openMultBatch();
                                      })
                                    : _buildQtyRow(qtyLabel, editQty, qtyFocusNode, qtyCtrl,
                                        onChanged: (v) {
                                        if (v >= 0) setDialogState(() => editQty = v);
                                      })),
                                const SizedBox(height: 12),
                                // 盈亏数量（只读）
                                _buildInfoRowColored(
                                    '盈亏数量',
                                    profitLoss.toStringAsFixed(1),
                                    profitLoss >= 0
                                        ? const Color(0xFF00A870)
                                        : const Color(0xFFD54B5A)),
                                const SizedBox(height: 12),
                                // 生产/有效日期：只读展示，不可修改（对齐 lxAss 预盘/快速盘点 tm-text 只读）
                                if (!hideDateRows) ...[
                                  _buildInfoRow(
                                      '生产日期', editBirthdate.isNotEmpty ? editBirthdate : '-'),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                      '有效日期', editValiddate.isNotEmpty ? editValiddate : '-'),
                                  const SizedBox(height: 12),
                                ],
                                // 备注
                                _buildRemarkRow('备注', editRemark, onChanged: (v) {
                                  setDialogState(() => editRemark = v);
                                }),
                              ],
                            ),
                          ),
                        ),
                        _buildDrawerBottom(ctx,
                            onCancel: () => Navigator.pop(ctx),
                            onConfirm: () {
                              final result = Map<String, dynamic>.from(item);
                              result['qty'] = editQty;
                              result['unit'] = currentUnit;
                              result['size'] = currentSize;
                              result['batchno'] = editBatchno;
                              result['birthdate'] = editBirthdate;
                              result['validdate'] = editValiddate;
                              result['supid'] = editSupid;
                              result['morebatchflag'] = item['morebatchflag']?.toString() ?? '';
                              if (multBatchList.isNotEmpty) {
                                // 多批次：批次列表 + 数量总和一并回传（对齐 lxAss onSelectMultBatch 后 detailConfirm）
                                result['batchList'] =
                                    List<Map<String, dynamic>>.from(multBatchList);
                                result[qtyType] = editQty;
                                // 同步写回当前商品项，再次进入详情时可按 batchList 回显（对齐 lxAss proItem 持久化）
                                item['batchList'] = List<Map<String, dynamic>>.from(multBatchList);
                                item['batchno'] = editBatchno;
                                item[qtyType] = editQty;
                              }
                              result['remark'] = editRemark;
                              Navigator.pop(ctx);
                              setState(() {
                                if (existIdx >= 0) {
                                  _selectedItems[existIdx] = result;
                                } else {
                                  _selectedItems.add(result);
                                }
                              });
                            }),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      qtyFocusNode.dispose();
      qtyCtrl.dispose();
      remarkCtrl.dispose();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (qtyFocusNode.canRequestFocus) {
        qtyFocusNode.requestFocus();
      }
    });
  }

  // ─── 库存单据抽屉（kctz/ycd：其他出库/其他入库/转仓）：单位/规格/数量/商品批次/生产日期/有效日期/备注 ────────────────────
  void _showStockDetail(Map<String, dynamic> item) {
    // 多批次商品：本次选择的批次列表（库存单据无多批次入口，恒为空，仅保持结构一致）
    final multBatchList = <Map<String, dynamic>>[];
    // 数量字段名（库存单据无多批次入口，仅保持结构一致）
    const qtyType = 'qty';
    // 转仓单（ycd）不带库存相关查询参数（对齐 zmProMax moveWarehouse mergeData）
    final withStock = widget.billtypeflag != 'ycd';
    final name = _getProductName(item);
    var stock = _getStock(item);
    var shelves = _getShelves(item);
    var stockqty = double.tryParse(item['stockqty']?.toString() ?? stock) ?? 0;

    final existIdx = _findSelectedIndex(item);
    final existItem = existIdx >= 0 ? _selectedItems[existIdx] : null;

    var currentUnit = existItem?['unit']?.toString() ?? _getUnit(item);
    var currentSize = existItem?['size']?.toString() ?? _getSize(item);
    var editBatchno = existItem?['batchno']?.toString() ?? item['batchno']?.toString() ?? '';
    var editBirthdate = existItem?['birthdate']?.toString() ?? item['birthdate']?.toString() ?? '';
    var editValiddate = existItem?['validdate']?.toString() ?? item['validdate']?.toString() ?? '';
    var editSupid = existItem?['supid']?.toString() ?? item['supid']?.toString() ?? '';
    var editRemark = existItem?['remark']?.toString() ?? item['remark']?.toString() ?? '';
    double editQty =
        existItem != null ? (double.tryParse(existItem['qty']?.toString() ?? '1') ?? 1) : 1;

    final qtyFocusNode = FocusNode();
    final qtyCtrl = TextEditingController(
      text: editQty == editQty.toInt() ? editQty.toInt().toString() : editQty.toStringAsFixed(1),
    );
    qtyFocusNode.addListener(() {
      if (qtyFocusNode.hasFocus && qtyCtrl.text.isNotEmpty) {
        qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: qtyCtrl.text.length);
      }
    });
    final remarkCtrl = TextEditingController(text: editRemark);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.82,
              height: MediaQuery.of(ctx).size.height,
              decoration: const BoxDecoration(color: Colors.white),
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (ctx, setDialogState) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDrawerHeader(ctx, '商品详情'),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProductInfoCard(name, _getBarcode(item), _getPrice(item),
                                    shelves, stock, currentUnit, currentSize,
                                    stockqty: stockqty),
                                const SizedBox(height: 12),
                                const Divider(color: Color(0xFFE5E7EB)),
                                const SizedBox(height: 12),
                                // 单位（可选择，限制逻辑同批发销售单）
                                _buildSelectField(
                                    '单位', currentUnit.isNotEmpty ? currentUnit : '请选择',
                                    onTap: (item['packageflag']?.toString() != '1' ||
                                            item['specflag']?.toString() == '1')
                                        ? () async {
                                            final result = await _showStockExtendOptions(
                                                'unit', item,
                                                withStock: withStock);
                                            if (result != null) {
                                              setDialogState(() {
                                                final u = result['unit']?.toString() ??
                                                    result['_name']?.toString() ??
                                                    '';
                                                if (u.isNotEmpty) currentUnit = u;
                                                final uid = result['unitonlyid']?.toString() ??
                                                    result['_id']?.toString() ??
                                                    '';
                                                if (uid.isNotEmpty) {
                                                  item['unitonlyid'] = uid;
                                                  currentSize =
                                                      item['_mainSize']?.toString() ?? currentSize;
                                                  item['size'] = currentSize;
                                                  item['sizeonlyid'] =
                                                      item['_mainSizeonlyid']?.toString() ?? '';
                                                }
                                                // barcode = sbarcode || barcode（对齐 zmProMax unitConfirm）
                                                final nb = result['sbarcode']?.toString() ??
                                                    result['barcode']?.toString();
                                                if (nb != null) item['barcode'] = nb;
                                                // code = scode || code
                                                final nc = result['scode']?.toString() ??
                                                    result['code']?.toString();
                                                if (nc != null) item['code'] = nc;
                                                // 零售价更新（sellprice）
                                                final nr = result['sellprice']?.toString() ??
                                                    result['retailprice']?.toString() ??
                                                    result['lsprice']?.toString();
                                                if (nr != null && nr.isNotEmpty) {
                                                  item['retailprice'] = nr;
                                                  item['sellprice'] = nr;
                                                }
                                                // 库存更新（stockqty）
                                                final ns = result['stockqty']?.toString() ??
                                                    result['stock']?.toString();
                                                if (ns != null && ns.isNotEmpty) {
                                                  stock = ns;
                                                  item['stock'] = ns;
                                                  final nq = double.tryParse(ns);
                                                  if (nq != null) {
                                                    stockqty = nq;
                                                    item['stockqty'] = ns;
                                                  }
                                                }
                                                // 成本价更新（对齐 zmProMax unitConfirm: costprice）
                                                final ncost = result['costprice']?.toString();
                                                if (ncost != null && ncost.isNotEmpty) {
                                                  item['costprice'] = ncost;
                                                }
                                                // 移仓单出入成本价（对齐 zmProMax unitConfirm: outemptycostprice/inemptycostprice）
                                                final nout =
                                                    result['outemptycostprice']?.toString();
                                                if (nout != null && nout.isNotEmpty) {
                                                  item['outcostprice'] = nout;
                                                  item['outemptycostprice'] = nout;
                                                }
                                                final nin = result['inemptycostprice']?.toString();
                                                if (nin != null && nin.isNotEmpty) {
                                                  item['incostprice'] = nin;
                                                  item['inemptycostprice'] = nin;
                                                }
                                                // 货架号更新（对齐 zmProMax unitConfirm: shelves）
                                                final nsh = result['shelves']?.toString();
                                                if (nsh != null && nsh.isNotEmpty) {
                                                  shelves = nsh;
                                                  item['shelves'] = nsh;
                                                }
                                              });
                                            }
                                          }
                                        : null),
                                const SizedBox(height: 8),
                                // 规格（可选择，限制逻辑同批发销售单）
                                _buildSelectField(
                                    '规格', currentSize.isNotEmpty ? currentSize : '请选择',
                                    onTap: (item['specflag']?.toString() == '1' &&
                                            (item['unitonlyid'] == null ||
                                                (item['unitonlyid']?.toString().isEmpty ?? false)))
                                        ? () async {
                                            final result = await _showStockExtendOptions(
                                                'size', item,
                                                withStock: withStock);
                                            if (result != null) {
                                              setDialogState(() {
                                                final s = result['size']?.toString() ??
                                                    result['_name']?.toString() ??
                                                    '';
                                                if (s.isNotEmpty) currentSize = s;
                                                if (item['_mainSize'] == null) {
                                                  item['_mainSize'] = item['size'] ?? currentSize;
                                                  item['_mainSizeonlyid'] =
                                                      item['sizeonlyid']?.toString() ?? '';
                                                }
                                                final sid = result['sizeonlyid']?.toString() ??
                                                    result['_id']?.toString() ??
                                                    '';
                                                if (sid.isNotEmpty) item['sizeonlyid'] = sid;
                                                // barcode = sbarcode || barcode（对齐 zmProMax changeSize）
                                                final nb = result['sbarcode']?.toString() ??
                                                    result['barcode']?.toString();
                                                if (nb != null) item['barcode'] = nb;
                                                // code = scode || code
                                                final nc = result['scode']?.toString() ??
                                                    result['code']?.toString();
                                                if (nc != null) item['code'] = nc;
                                                // 零售价更新（sellprice）
                                                final nr = result['sellprice']?.toString() ??
                                                    result['retailprice']?.toString() ??
                                                    result['lsprice']?.toString();
                                                if (nr != null && nr.isNotEmpty) {
                                                  item['retailprice'] = nr;
                                                  item['sellprice'] = nr;
                                                }
                                                // 库存更新（stockqty）
                                                final ns = result['stockqty']?.toString() ??
                                                    result['stock']?.toString();
                                                if (ns != null && ns.isNotEmpty) {
                                                  stock = ns;
                                                  item['stock'] = ns;
                                                  final nq = double.tryParse(ns);
                                                  if (nq != null) {
                                                    stockqty = nq;
                                                    item['stockqty'] = ns;
                                                  }
                                                }
                                                // 成本价更新（对齐 zmProMax changeSize: costprice）
                                                final ncost = result['costprice']?.toString();
                                                if (ncost != null && ncost.isNotEmpty) {
                                                  item['costprice'] = ncost;
                                                }
                                                // 移仓单出入成本价（对齐 zmProMax changeSize: outemptycostprice/inemptycostprice）
                                                final nout =
                                                    result['outemptycostprice']?.toString();
                                                if (nout != null && nout.isNotEmpty) {
                                                  item['outcostprice'] = nout;
                                                  item['outemptycostprice'] = nout;
                                                }
                                                final nin = result['inemptycostprice']?.toString();
                                                if (nin != null && nin.isNotEmpty) {
                                                  item['incostprice'] = nin;
                                                  item['inemptycostprice'] = nin;
                                                }
                                              });
                                            }
                                          }
                                        : null),
                                const SizedBox(height: 12),
                                // 数量
                                _buildQtyRow('数量', editQty, qtyFocusNode, qtyCtrl, onChanged: (v) {
                                  if (v >= 0) setDialogState(() => editQty = v);
                                }),
                                const SizedBox(height: 12),
                                if (widget.batchManualInput) ...[
                                  // 商品批次（手动输入模式）
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 70,
                                        child: Text('商品批次：',
                                            style:
                                                TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: TextEditingController(text: editBatchno)
                                            ..selection = TextSelection.fromPosition(
                                                TextPosition(offset: editBatchno.length)),
                                          onChanged: (v) {
                                            setDialogState(() => editBatchno = v);
                                          },
                                          style: const TextStyle(fontSize: 13),
                                          decoration: const InputDecoration(
                                            hintText: '请输入批次',
                                            hintStyle:
                                                TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                            border: OutlineInputBorder(
                                              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                                            ),
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // 生产日期
                                  _buildSelectField(
                                      '生产日期', editBirthdate.isNotEmpty ? editBirthdate : '请选择',
                                      onTap: () {
                                    _pickInventoryDate(ctx, editBirthdate).then((v) {
                                      if (v != null) setDialogState(() => editBirthdate = v);
                                    });
                                  }),
                                  const SizedBox(height: 12),
                                  // 有效日期
                                  _buildSelectField(
                                      '有效日期', editValiddate.isNotEmpty ? editValiddate : '请选择',
                                      onTap: () {
                                    _pickInventoryDate(ctx, editValiddate).then((v) {
                                      if (v != null) setDialogState(() => editValiddate = v);
                                    });
                                  }),
                                ] else ...[
                                  // 商品批次（使用 SelectBatchSheet 选择，带出日期）
                                  _buildSelectField(
                                      '商品批次', editBatchno.isNotEmpty ? editBatchno : '请选择',
                                      onTap: () async {
                                    final productid = item['productid']?.toString() ??
                                        item['prodid']?.toString() ??
                                        '';
                                    if (productid.isEmpty) {
                                      Toast.show('商品信息异常');
                                      return;
                                    }
                                    final batchResult =
                                        await showModalBottomSheet<Map<String, dynamic>>(
                                      context: ctx,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => SelectBatchSheet(
                                        productid: productid,
                                        bsid: (widget.storeid ?? '').toString(),
                                        counterid: widget.counterid ?? '',
                                        initialBatchNo: editBatchno,
                                      ),
                                    );
                                    if (batchResult != null) {
                                      setDialogState(() {
                                        editBatchno = batchResult['batchno']?.toString() ?? '';
                                        // 选择批次后自动带出生产日期和有效期（对齐 web handleBatchConfirm）
                                        editBirthdate = _formatBatchDate(batchResult['birthdate']);
                                        final bd = editBirthdate.isNotEmpty ? editBirthdate : '';
                                        editValiddate = _formatBatchDate(batchResult['validdate']);
                                        if (editValiddate.isEmpty && bd.isNotEmpty) {
                                          editValiddate = bd;
                                        }
                                        editSupid = batchResult['supid']?.toString() ?? '';
                                      });
                                    }
                                  }),
                                  const SizedBox(height: 12),
                                  // 生产日期（选了批次后禁用编辑，未选批次可自行修改）
                                  if (editBatchno.isNotEmpty)
                                    _buildInfoRow(
                                        '生产日期', editBirthdate.isNotEmpty ? editBirthdate : '-')
                                  else ...[
                                    _buildSelectField(
                                        '生产日期', editBirthdate.isNotEmpty ? editBirthdate : '请选择',
                                        onTap: () {
                                      _pickInventoryDate(ctx, editBirthdate).then((v) {
                                        if (v != null) setDialogState(() => editBirthdate = v);
                                      });
                                    }),
                                  ],
                                  const SizedBox(height: 12),
                                  // 有效日期（选了批次后禁用编辑，未选批次可自行修改）
                                  if (editBatchno.isNotEmpty)
                                    _buildInfoRow(
                                        '有效日期', editValiddate.isNotEmpty ? editValiddate : '-')
                                  else ...[
                                    _buildSelectField(
                                        '有效日期', editValiddate.isNotEmpty ? editValiddate : '请选择',
                                        onTap: () {
                                      _pickInventoryDate(ctx, editValiddate).then((v) {
                                        if (v != null) setDialogState(() => editValiddate = v);
                                      });
                                    }),
                                  ],
                                ],
                                const SizedBox(height: 12),
                                // 备注
                                _buildRemarkRow('备注', editRemark, onChanged: (v) {
                                  setDialogState(() => editRemark = v);
                                }),
                              ],
                            ),
                          ),
                        ),
                        _buildDrawerBottom(ctx,
                            onCancel: () => Navigator.pop(ctx),
                            onConfirm: () {
                              final result = Map<String, dynamic>.from(item);
                              result['qty'] = editQty;
                              result['unit'] = currentUnit;
                              result['size'] = currentSize;
                              result['batchno'] = editBatchno;
                              result['birthdate'] = editBirthdate;
                              result['validdate'] = editValiddate;
                              result['supid'] = editSupid;
                              result['morebatchflag'] = item['morebatchflag']?.toString() ?? '';
                              if (multBatchList.isNotEmpty) {
                                // 多批次：批次列表 + 数量总和一并回传（对齐 lxAss onSelectMultBatch 后 detailConfirm）
                                result['batchList'] =
                                    List<Map<String, dynamic>>.from(multBatchList);
                                result[qtyType] = editQty;
                                // 同步写回当前商品项，再次进入详情时可按 batchList 回显（对齐 lxAss proItem 持久化）
                                item['batchList'] = List<Map<String, dynamic>>.from(multBatchList);
                                item['batchno'] = editBatchno;
                                item[qtyType] = editQty;
                              }
                              result['remark'] = editRemark;
                              Navigator.pop(ctx);
                              setState(() {
                                if (existIdx >= 0) {
                                  _selectedItems[existIdx] = result;
                                } else {
                                  _selectedItems.add(result);
                                }
                              });
                            }),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      qtyFocusNode.dispose();
      qtyCtrl.dispose();
      remarkCtrl.dispose();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (qtyFocusNode.canRequestFocus) {
        qtyFocusNode.requestFocus();
      }
    });
  }

  // ─── 成本变更单抽屉（costchange）：原成本价/新成本价/变更差额/备注 ────────────────────
  void _showCostChangeDetail(Map<String, dynamic> item) {
    final name = _getProductName(item);
    // 成本价：优先取 costprice，API 带 cgpriceflag=1 时可能不返回，fallback 到 inprice/cgprice/price
    var costprice = double.tryParse(item['costprice']?.toString() ?? '') ?? 0;
    if (costprice == 0) {
      costprice = double.tryParse(item['inprice']?.toString() ?? '') ?? 0;
    }
    if (costprice == 0) {
      costprice = double.tryParse(item['cgprice']?.toString() ?? '') ?? 0;
    }
    if (costprice == 0) {
      costprice = double.tryParse(item['price']?.toString() ?? '') ?? 0;
    }
    final stockqty = double.tryParse(item['stockqty']?.toString() ?? '0') ?? 0;
    // 进价：对齐 lxAss proDetails 用 inprice 字段
    final inprice = double.tryParse(item['inprice']?.toString() ?? '') ?? costprice;

    final existIdx = _findSelectedIndex(item);
    final existItem = existIdx >= 0 ? _selectedItems[existIdx] : null;
    // 已选中项（修改过单位/规格时优先取）
    final src = existItem ?? item;

    // 原成本价：对齐 lxAss onlyShowSelectStatus 预处理逻辑
    // 已有选中项时取该项的 oldcostprice，为 0/空时从商品资料取成本价（接口可能返回 oldcostprice=0）
    final oldcostprice = (() {
      final oc = double.tryParse(src['oldcostprice']?.toString() ?? '') ?? 0;
      return oc != 0 ? oc : costprice;
    })();
    // 新成本价默认 0（对齐 lxAss onlyShowSelectStatus: c.newcostprice = c.newcostprice ?? 0）
    var editNewcostprice =
        existItem != null ? (double.tryParse(existItem['newcostprice']?.toString() ?? '') ?? 0) : 0;
    var editRemark = existItem?['remark']?.toString() ?? item['remark']?.toString() ?? '';

    // 单位/规格：已选中项优先
    final unit = src['unit']?.toString() ?? '';
    final size = src['size']?.toString() ?? '';
    final unitonlyid = src['unitonlyid']?.toString() ?? '';
    final sizeonlyid = src['sizeonlyid']?.toString() ?? '';
    final barcode = src['barcode']?.toString() ?? _getBarcode(item);

    final priceFocusNode = FocusNode();
    final priceCtrl = TextEditingController(text: MathUtils.formatDecimal(2, editNewcostprice));
    priceFocusNode.addListener(() {
      if (priceFocusNode.hasFocus && priceCtrl.text.isNotEmpty) {
        priceCtrl.selection = TextSelection(baseOffset: 0, extentOffset: priceCtrl.text.length);
      }
    });
    final remarkCtrl = TextEditingController(text: editRemark);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.82,
              height: MediaQuery.of(ctx).size.height,
              decoration: const BoxDecoration(color: Colors.white),
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (ctx, setDialogState) {
                    final amt = (editNewcostprice - oldcostprice) * stockqty;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDrawerHeader(ctx, '商品详情'),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 头部信息（对齐 lxAss costChange：商品名称/条码/成本价+库存）
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('商品名称：$name',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF111827))),
                                      const SizedBox(height: 4),
                                      Text('条码：${_getBarcode(item)}',
                                          style: const TextStyle(
                                              fontSize: 13, color: Color(0xFF6B7280))),
                                      const SizedBox(height: 4),
                                      Text('进价：¥${MathUtils.formatDecimal(2, inprice)}',
                                          style: const TextStyle(
                                              fontSize: 13, color: Color(0xFF111827))),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        Expanded(
                                            child: Text(
                                                '成本价：¥${MathUtils.formatDecimal(2, costprice)}',
                                                style: const TextStyle(
                                                    fontSize: 13, color: Color(0xFF6B7280)))),
                                        Expanded(
                                            child: Text(
                                                '库存：${MathUtils.formatDecimal(1, stockqty)}',
                                                style: const TextStyle(
                                                    fontSize: 13, color: Color(0xFF6B7280)))),
                                      ]),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Divider(color: Color(0xFFE5E7EB)),
                                const SizedBox(height: 12),
                                _buildInfoRow('单位', unit.isNotEmpty ? unit : '-'),
                                const SizedBox(height: 12),
                                _buildInfoRow('规格', size.isNotEmpty ? size : '-'),
                                const SizedBox(height: 12),
                                // 原成本价（只读）
                                _buildInfoRow(
                                    '原成本价', '¥${MathUtils.formatDecimal(2, oldcostprice)}'),
                                const SizedBox(height: 12),
                                // 新成本价（可编辑）
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 70,
                                      child: Text('新成本价：',
                                          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: priceCtrl,
                                        focusNode: priceFocusNode,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(fontSize: 13),
                                        onChanged: (text) {
                                          final v = double.tryParse(text) ?? 0;
                                          setDialogState(() => editNewcostprice = v);
                                        },
                                        decoration: const InputDecoration(
                                          hintText: '请输入新成本价',
                                          hintStyle:
                                              TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                          border: OutlineInputBorder(
                                            borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                                          ),
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // 变更差额（只读，黑色）
                                _buildInfoRow('变更差额', '¥${MathUtils.formatDecimal(3, amt)}'),
                                const SizedBox(height: 12),
                                // 备注
                                _buildRemarkRow('备注', editRemark, onChanged: (v) {
                                  setDialogState(() => editRemark = v);
                                }),
                              ],
                            ),
                          ),
                        ),
                        _buildDrawerBottom(ctx,
                            onCancel: () => Navigator.pop(ctx),
                            onConfirm: () {
                              final result = Map<String, dynamic>.from(item);
                              // 写回按 lxAss 位数规则：价格 formatDecimal(2)、差额 formatDecimal(3)
                              result['oldcostprice'] = MathUtils.formatDecimal(2, oldcostprice);
                              result['newcostprice'] = MathUtils.formatDecimal(2, editNewcostprice);
                              result['amt'] = MathUtils.formatDecimal(
                                  3,
                                  MathUtils.multiply(
                                      MathUtils.subtract(editNewcostprice, oldcostprice),
                                      stockqty));
                              result['remark'] = editRemark;
                              // 单位/规格/条码写回（对齐库存模块确定返回字段）
                              result['unit'] = unit;
                              result['size'] = size;
                              result['unitonlyid'] = unitonlyid;
                              result['sizeonlyid'] = sizeonlyid;
                              result['barcode'] = barcode;
                              Navigator.pop(ctx);
                              setState(() {
                                if (existIdx >= 0) {
                                  _selectedItems[existIdx] = result;
                                } else {
                                  _selectedItems.add(result);
                                }
                              });
                            }),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      priceFocusNode.dispose();
      priceCtrl.dispose();
      remarkCtrl.dispose();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (priceFocusNode.canRequestFocus) {
        priceFocusNode.requestFocus();
      }
    });
  }

  // ─── 抽屉公共组件 ─────────────────────────────────────
  Widget _buildDrawerHeader(BuildContext ctx, String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerBottom(BuildContext ctx,
      {required VoidCallback onCancel, required VoidCallback onConfirm}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onCancel,
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('取消', style: TextStyle(fontSize: 15, color: Color(0xFF6B7280))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onConfirm,
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('确定',
                    style:
                        TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductInfoCard(String name, String barcode, String price, String shelves,
      String stock, String unit, String size,
      {String? costPrice, double? stockqty}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        const SizedBox(height: 4),
        Text(barcode.isNotEmpty ? barcode : '-',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _buildInfoInline('配送价', price)),
          const SizedBox(width: 16),
          if (costPrice != null)
            Expanded(child: _buildInfoInline('成本价', costPrice))
          else
            Expanded(child: _buildInfoInline('货架号', shelves.isNotEmpty ? shelves : '-')),
        ]),
        if (costPrice != null && shelves.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildInfoInline('货架号', shelves),
        ],
        const SizedBox(height: 8),
        if (stockqty != null)
          _buildInfoInline('现库存', stockqty.toStringAsFixed(1))
        else
          _buildInfoInline('库存', stock),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _buildInfoInline('单位', unit.isNotEmpty ? unit : '-')),
          const SizedBox(width: 16),
          Expanded(child: _buildInfoInline('规格', size.isNotEmpty ? size : '-')),
        ]),
      ],
    );
  }

  Widget _buildInfoRowColored(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text('$label：', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: valueColor, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectField(String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text('$label：', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: value == '请选择' ? const Color(0xFFD1D5DB) : const Color(0xFF111827),
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
          ],
        ],
      ),
    );
  }

  Future<String?> _pickInventoryDate(BuildContext ctx, String currentValue) async {
    DateTime initial;
    try {
      initial = currentValue.isNotEmpty ? DateTime.parse(currentValue) : DateTime.now();
    } catch (_) {
      initial = DateTime.now();
    }
    DateTime tempDate = initial;
    final date = await showModalBottomSheet<DateTime>(
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
                        child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280)))),
                    const Spacer(),
                    TextButton(
                        onPressed: () => Navigator.pop(c, tempDate),
                        child: const Text('确定', style: TextStyle(color: Color(0xFF006EFF)))),
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
                            initialItem: (tempDate.year - 2020).clamp(0, 19)),
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
                        scrollController:
                            FixedExtentScrollController(initialItem: tempDate.month - 1),
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
                        scrollController:
                            FixedExtentScrollController(initialItem: tempDate.day - 1),
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
    if (date != null) {
      final mo = date.month.toString().padLeft(2, '0');
      final dy = date.day.toString().padLeft(2, '0');
      return '${date.year}-$mo-$dy';
    }
    return null;
  }

  /// 将批次接口返回的日期字段统一格式化为 YYYY-MM-DD
  /// 支持 ISO 字符串、时间戳毫秒数、已格式化字符串
  static String _formatBatchDate(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null') return '';
    // 尝试解析 ISO 字符串
    try {
      final dt = DateTime.parse(s);
      final mo = dt.month.toString().padLeft(2, '0');
      final dy = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$mo-$dy';
    } catch (_) {}
    // 尝试解析时间戳毫秒数
    final ms = int.tryParse(s);
    if (ms != null && ms > 1000000000000) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final mo = dt.month.toString().padLeft(2, '0');
      final dy = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$mo-$dy';
    }
    return s;
  }

  // ─── 弹窗内行组件 ─────────────────────────────────────
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label：',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF111827), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoInline(String label, String value) {
    return Row(
      children: [
        Text('$label：', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF111827), fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _buildRemarkRow(String label, String value, {required ValueChanged<String> onChanged}) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text('$label：', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: TextField(
            controller: TextEditingController(text: value)
              ..selection = TextSelection.fromPosition(TextPosition(offset: value.length)),
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: '请输入备注',
              hintStyle: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE5E7EB)),
              ),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(TextEditingController controller, FocusNode focusNode,
      {VoidCallback? onChanged}) {
    return Row(
      children: [
        const SizedBox(
          width: 70,
          child: Text('价格：', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13),
            onChanged: (_) => onChanged?.call(),
            decoration: const InputDecoration(
              hintText: '请输入价格',
              hintStyle: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE5E7EB)),
              ),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  /// 可编辑输入行（label 可配置，对齐 Vue proDetails.vue tm-input 字段：
  /// 价格/零售价/小计金额均支持手动输入）
  /// 不使用外部 FocusNode，让 TextField 自行管理内部 FocusNode 生命周期
  ///（避免抽屉关闭时外部 FocusNode 与 Flutter 焦点管理器不一致导致 'used after disposed'）
  Widget _buildEditableRow(String label, TextEditingController controller,
      {ValueChanged<String>? onSubmitted,
      VoidCallback? onChanged,
      ValueChanged<bool>? onFocusChange}) {
    final TextField field = TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13),
      onChanged: (_) => onChanged?.call(),
      onSubmitted: onSubmitted,
      decoration: const InputDecoration(
        hintText: '请输入',
        hintStyle: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
        ),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text('$label：', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ),
        Expanded(
          // 需要失焦回调时用 Focus 包裹（对齐 Vue @blur），不创建外部 FocusNode，
          // 避免抽屉关闭时外部 FocusNode 与 Flutter 焦点管理器不一致导致 'used after disposed'
          child: onFocusChange != null ? Focus(onFocusChange: onFocusChange, child: field) : field,
        ),
      ],
    );
  }

  Widget _buildQtyRow(
    String label,
    double value,
    FocusNode focusNode,
    TextEditingController controller, {
    required ValueChanged<double> onChanged,
  }) {
    const double stepperHeight = 34;
    const double btnWidth = 34;
    const double inputWidth = 50;
    const Color borderColor = Color(0xFFD1D5DB);
    const Color btnBg = Color(0xFFF3F4F6);
    const double radius = 6;

    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text('$label：', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ),
        // 一体化步进器：[-] 输入框 [+]  共用外框
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 减号按钮
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (value > (label == '数量' ? 1 : 0)) {
                      onChanged(value - 1);
                      controller.text = MathUtils.formatDecimal(1, value - 1);
                    }
                  },
                  child: Container(
                    width: btnWidth,
                    height: stepperHeight,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: btnBg,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(radius),
                        bottomLeft: Radius.circular(radius),
                      ),
                    ),
                    child: const Icon(Icons.remove, size: 16, color: Color(0xFF374151)),
                  ),
                ),
                // 左侧分隔线
                Container(width: 1, color: borderColor),
                // 数量输入框
                SizedBox(
                  width: inputWidth,
                  height: stepperHeight,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF111827), fontWeight: FontWeight.w500),
                    onChanged: (text) {
                      final v = double.tryParse(text) ?? value;
                      onChanged(v);
                    },
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                // 右侧分隔线
                Container(width: 1, color: borderColor),
                // 加号按钮
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    onChanged(value + 1);
                    controller.text = MathUtils.formatDecimal(1, value + 1);
                  },
                  child: Container(
                    width: btnWidth,
                    height: stepperHeight,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: btnBg,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(radius),
                        bottomRight: Radius.circular(radius),
                      ),
                    ),
                    child: const Icon(Icons.add, size: 16, color: Color(0xFF374151)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 已选列表弹窗 ─────────────────────────────────────
  void _showSelectedList() {
    if (_selectedItems.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                    child: Row(
                      children: [
                        const Text(
                          '已选商品',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedItems.clear());
                            setSheetState(() {});
                          },
                          child: const Text('清空',
                              style: TextStyle(fontSize: 14, color: Color(0xFFEF4444))),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _selectedItems.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFF0F0F0)),
                      itemBuilder: (ctx, index) {
                        final item = _selectedItems[index];
                        final name = _getProductName(item);
                        final unit = _getUnit(item);
                        final price = _getPrice(item);
                        final qty = item['qty']?.toString() ?? '1';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onTap: () => _showProductDetail(item),
                          title: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: Text('$unit  ¥$price',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                          trailing: Text(
                            'x$qty',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                        );
                      },
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
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          elevation: 0,
                        ),
                        child: const Text('完成',
                            style: TextStyle(
                                fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
                      ),
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

  /// 读取登录参数指定 key 的 int 值（对齐 Vue userStore().loginParamResp），
  /// 缺失或解析异常时返回 0
  int _loginParamInt(String key) {
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isEmpty) return 0;
      final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
      return int.tryParse(cfg[key]?.toString() ?? '0') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void _confirm() {
    // 对齐 Vue selectProduct.vue getAmt / 单据 edit.vue comProAmt：
    // 返回前统一补全 amt（qty × price），确保主页面可直接使用；
    // 手动修改过小计金额的商品（_amtManual=true）保留其 amt，
    // 除非系统参数 cgAmountRecalculationflag==1 强制按 qty × price 重算（对齐 writeData 收尾分支）
    final cgpriceflag = widget.mergData?['cgpriceflag']?.toString() == '1';
    final recalcAllAmt = _loginParamInt('cgAmountRecalculationflag') == 1;
    for (final item in _selectedItems) {
      final manual = item['_amtManual'] == true;
      if (!recalcAllAmt && manual) continue;
      final qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
      final priceText = cgpriceflag
          ? _cgPriceText(item, fallback: '0')
          : (item['sellprice']?.toString() ?? item['price']?.toString() ?? '0');
      final price = double.tryParse(priceText) ?? 0;
      item['amt'] = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    }
    Navigator.pop(context, _selectedItems);
  }

  // ─── 主页面构建 ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // 强制使用亮色主题，避免手机暗夜模式导致硬编码颜色显示异常
    return Theme(
        data: ThemeData.light().copyWith(
          primaryColor: _primaryColor,
          colorScheme: const ColorScheme.light().copyWith(
            primary: _primaryColor,
          ),
        ),
        child: Scaffold(
          backgroundColor: _bgColor,
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
              '选择商品',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ),
          body: Column(
            children: [
              // 搜索框
              _buildSearchBar(),
              // 主体：左侧分类 + 右侧（二级分类 + 商品列表）
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧分类栏
                    _buildCategorySidebar(),
                    // 右侧：二级分类横向条 + 商品列表
                    Flexible(
                      child: Column(
                        children: [
                          _buildTwoTypeBar(),
                          Flexible(child: _buildProductList()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 底部栏
              _buildBottomBar(),
            ],
          ),
        ));
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
            const SizedBox(width: 6),
            Flexible(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '输入条码/自编码/商品名称/拼音简码/辅助条码',
                  hintStyle: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (_) => _onSearch(),
              ),
            ),
            // 清除按钮（有内容时显示）
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (_, value, __) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _onSearch();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.cancel, size: 16, color: Color(0xFFBDBDBD)),
                  ),
                );
              },
            ),
            // 扫描按钮
            GestureDetector(
              onTap: _scanBarcode,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: BossSvgIcon(svgFile: 'scan.svg', size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySidebar() {
    return Container(
      width: 90,
      color: const Color(0xFFF9FAFB),
      child: _loadingCategories
          ? const Center(
              child:
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _categoryItem('全部', null),
                ..._categories.map((cat) {
                  return _categoryItem(
                    cat['name']?.toString() ?? '',
                    cat,
                  );
                }),
              ],
            ),
    );
  }

  Widget _categoryItem(String label, Map<String, dynamic>? category) {
    final isSelected = _selectedL1Category == category;
    return GestureDetector(
      onTap: () => _onCategoryTap(category),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? _primaryColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isSelected ? _primaryColor : const Color(0xFF6B7280),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ─── 二级分类横向滚动条（对齐 boss 项目 type-two-list-box）────────────
  Widget _buildTwoTypeBar() {
    final twoList = _twoTypeList;
    if (twoList.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 40,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: twoList.length,
        itemBuilder: (context, index) {
          final item = twoList[index];
          final name = item['name']?.toString() ?? '';
          final isActive = _twoTypeIndex == index;
          return GestureDetector(
            onTap: () => _onTwoTypeTap(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: isActive ? _primaryColor.withOpacity(0.1) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  color: isActive ? _primaryColor : const Color(0xFF374151),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductList() {
    return RefreshIndicator(
      color: _primaryColor,
      onRefresh: _onRefresh,
      child: _list.isEmpty && !_loading
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, size: 48, color: Color(0xFFD1D5DB)),
                      SizedBox(height: 10),
                      Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              cacheExtent: 800,
              itemCount: _list.length + (_loading ? 1 : (_hasMore ? 0 : 1)),
              itemBuilder: (context, index) {
                if (index == _list.length) {
                  return _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
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
                final item = _list[index];
                final selectedQty = _getSelectedQty(item);
                final isChecked =
                    (widget.checkboxMode || widget.singleSelectMode) && _isChecked(item);
                return _ProductCard(
                  item: item,
                  selectedQty: selectedQty,
                  getProductName: _getProductName,
                  getUnit: _getUnit,
                  getSpec: _getSpec,
                  getStock: _getStock,
                  getPrice: _getPrice,
                  getImageUrl: _getImageUrl,
                  // onQtyTap: 点击数量数字弹出详情抽屉
                  onQtyTap: () => _showProductDetail(item),
                  onQuickAdd: () => _quickAdd(item),
                  onQuickMinus: () => _quickMinus(item),
                  // 复选框模式参数
                  checkboxMode: widget.checkboxMode,
                  singleSelectMode: widget.singleSelectMode,
                  isSelected: isChecked,
                  onToggle: widget.checkboxMode
                      ? () => _toggleSelect(item)
                      : widget.singleSelectMode
                          ? () => _toggleSingleSelect(item)
                          : null,
                );
              },
            ),
    );
  }

  Widget _buildBottomBar() {
    final bool isCountMode = widget.singleSelectMode || widget.checkboxMode;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          // 统计区：单选/复选模式显示已选项数；普通模式显示数量+合计（对齐小程序 total-box）
          // 统计区用 Expanded 占满剩余宽度（不再加 Spacer，避免与 Expanded 对半分宽）
          if (isCountMode)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showSelectedList,
                child: Text(
                  '已选 ${_selectedItems.length} 项',
                  style: const TextStyle(
                    fontSize: 14,
                    color: _primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showSelectedList,
                // 统计区两列：label 在上、value 在下（数量 + 合计，金额红色强调）
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTotalStatItem('数量', _totalQtyText)),
                    Expanded(child: _buildTotalStatItem('合计', '¥$_totalAmtText', isAmt: true)),
                  ],
                ),
              ),
            ),
          SizedBox(
            width: 120,
            height: 40,
            child: ElevatedButton(
              onPressed: _selectedItems.isEmpty ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                disabledBackgroundColor: const Color(0xFF93C5FD),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
              child: Text(
                '确定',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _selectedItems.isEmpty ? Colors.white70 : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部统计项（与单据页面统计栏样式保持一致：
  /// label 灰色小字在上，value 深色加粗大字在下，金额红色强调）
  Widget _buildTotalStatItem(String label, String value, {bool isAmt = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.4)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: isAmt ? const Color(0xFFFF4D4F) : const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

// ─── 商品卡片组件（PDA低端机优化：无BoxShadow/无Material按钮/RepaintBoundary隔离重绘）
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.selectedQty,
    required this.getProductName,
    required this.getUnit,
    required this.getSpec,
    required this.getStock,
    required this.getPrice,
    required this.getImageUrl,
    required this.onQtyTap,
    required this.onQuickAdd,
    required this.onQuickMinus,
    this.checkboxMode = false,
    this.singleSelectMode = false,
    this.isSelected = false,
    this.onToggle,
  });
  final Map<String, dynamic> item;
  final double selectedQty;
  final String Function(Map<String, dynamic>) getProductName;
  final String Function(Map<String, dynamic>) getUnit;
  final String Function(Map<String, dynamic>) getSpec;
  final String Function(Map<String, dynamic>) getStock;
  final String Function(Map<String, dynamic>) getPrice;
  final String Function(Map<String, dynamic>) getImageUrl;
  final VoidCallback onQtyTap;
  final VoidCallback onQuickAdd;
  final VoidCallback onQuickMinus;
  final bool checkboxMode;
  final bool singleSelectMode;
  final bool isSelected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final name = getProductName(item);
    final unit = getUnit(item);
    final spec = getSpec(item);
    final stock = getStock(item);
    final price = getPrice(item);
    final imageUrl = getImageUrl(item);

    // RepaintBoundary 隔离每张卡片的重绘范围，避免滚动时全列表重绘
    final isSelectMode = checkboxMode || singleSelectMode;
    return RepaintBoundary(
      child: GestureDetector(
        behavior: isSelectMode ? HitTestBehavior.opaque : null,
        onTap: isSelectMode ? onToggle : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelectMode && isSelected ? const Color(0xFFF0F7FF) : Colors.white,
            // 用 Border 替代 boxShadow，避免低端设备高斯模糊开销
            border: const Border(
              bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 商品图片（避免 ClipRRect，改用 Container 圆角背景 + 手动裁切）
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        cacheWidth: 120, // 限制解码尺寸，降低内存占用
                        cacheHeight: 120,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              const SizedBox(width: 10),
              // 商品信息（名称行铺满，加减按钮移入底部价格行）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.isNotEmpty ? '$name($unit)' : name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (spec.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          spec,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text('库存: $stock',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '¥$price',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                        if (!checkboxMode && !singleSelectMode) ...[
                          const Spacer(),
                          _buildSelectButton(),
                        ],
                        if (checkboxMode) ...[
                          const Spacer(),
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF4688FA) : Colors.transparent,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color:
                                    isSelected ? const Color(0xFF4688FA) : const Color(0xFFCCCCCC),
                                width: 1.5,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 12, color: Colors.white)
                                : null,
                          ),
                        ],
                        if (singleSelectMode) ...[
                          const Spacer(),
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    isSelected ? const Color(0xFF4688FA) : const Color(0xFFCCCCCC),
                                width: 1.5,
                              ),
                            ),
                            child: isSelected
                                ? const Padding(
                                    padding: EdgeInsets.all(3),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0xFF4688FA),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ],
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

  Widget _buildSelectButton() {
    if (selectedQty <= 0) {
      // 未选中 —— 显示圆形加号图标，点击快速添加（不弹抽屉）
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onQuickAdd,
        child: const Icon(
          Icons.add_circle_outline,
          size: 26,
          color: Color(0xFF3B82F6),
        ),
      );
    }
    // 已选中 —— 显示 [-] 数量 [+] 组件，加减按钮 opaque 拦截，数量区域点击冒泡到卡片打开详情
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _miniQtyBtn(Icons.remove, onQuickMinus),
        const SizedBox(width: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onQtyTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Text(
              MathUtils.formatDecimal(1, selectedQty),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF111827),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _miniQtyBtn(Icons.add, onQuickAdd),
      ],
    );
  }

  Widget _miniQtyBtn(IconData icon, VoidCallback onTap) {
    final outlineIcon = icon == Icons.add ? Icons.add_circle_outline : Icons.remove_circle_outline;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Icon(outlineIcon, size: 26, color: const Color(0xFF3B82F6)),
    );
  }

  static Widget _placeholder() {
    return const Center(
      child: Icon(Icons.image_outlined, size: 24, color: Color(0xFFD1D5DB)),
    );
  }
}
