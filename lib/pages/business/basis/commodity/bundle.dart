import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// 特价打包商品管理页面
/// 参照 Vue boss 项目 pack.vue 实现
/// 管理打包商品列表，支持扫码/新增/删除/编辑价格
/// 数据通过 Navigator.pop 返回给上一页
class CommodityBundlePage extends StatefulWidget {
  const CommodityBundlePage({
    super.key,
    required this.items,
    this.productName = '',
  });

  /// 当前打包商品列表数据（productSize8）
  final List<Map<String, dynamic>> items;

  /// 商品名称（展示用）
  final String productName;

  @override
  State<CommodityBundlePage> createState() => _CommodityBundlePageState();
}

class _CommodityBundlePageState extends State<CommodityBundlePage> {
  late List<Map<String, dynamic>> _items;

  /// 打开选品页前已有打包商品的 id 快照（对齐调价 edit.dart _selectBeforeIds）：
  /// 选品页返回勾选全集，据此区分“已有保留 / 新增插入”，避免扫码过滤场景误清空明细
  Set<String> _selectBeforePids = {};

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.items);
  }

  /// 扫描条码添加商品（与 Vue pack.vue scanFn 一致）
  /// 扫码 → bi/product/getProductList(scancode) → 已存在提示 / 否则新增
  Future<void> _scanBarcode() async {
    if (!Device.isMobile) {
      Toast.show('当前平台暂不支持扫码');
      return;
    }
    NavigatorUtils.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code == null || !mounted) return;
    _handleScannedBarcode(code.toString());
  }

  /// 处理扫码结果（对齐小程序 pack.vue scanFn）：
  /// 同码多条跳转选品页；单条命中按 sbarcode 判重，已存在则提示，否则新增打包行
  Future<void> _handleScannedBarcode(String code) async {
    final searchCode = code.trim();
    if (searchCode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    try {
      final result = await request(HttpApi.productGetList, {
        'scancode': searchCode,
        'is_page': 1,
        'page': 1,
        'pagesize': 10,
      });
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isEmpty) {
        Toast.show('未查询到该商品');
        return;
      }
      // 同码多条判定（对齐小程序 scanFn）：自编码命中多条 → 跳转选品页；
      // 无自编码命中且商品条码命中多条 → 跳转选品页，由用户手动挑选
      final codeList = list
          .where(
              (c) => (c['code']?.toString() ?? '').isNotEmpty && c['code'].toString() == searchCode)
          .toList();
      final barcodeList = list
          .where((c) =>
              (c['barcode']?.toString() ?? '').isNotEmpty && c['barcode'].toString() == searchCode)
          .toList();
      final needJump = codeList.length >= 2 || (codeList.isEmpty && barcodeList.length >= 2);
      if (needJump) {
        // 选品页按扫码词过滤候选商品，返回后合并明细（勾选全集：已有保留 + 新增插入）
        _snapshotBeforePids();
        final result = await _openSelectProduct(keyword: searchCode);
        _applySelectProductResult(result);
        return;
      }
      // 单条命中：优先取与自编码/商品条码精确匹配的商品，否则取第一条
      Map<String, dynamic> scanned = Map<String, dynamic>.from(list[0] as Map);
      if (codeList.length == 1) {
        scanned = Map<String, dynamic>.from(codeList[0] as Map);
      } else if (codeList.isEmpty && barcodeList.length == 1) {
        scanned = Map<String, dynamic>.from(barcodeList[0] as Map);
      }
      // 判重（对齐小程序：sbarcode 为空时回退 barcode）
      final barcode = scanned['barcode']?.toString() ?? '';
      if (barcode.isNotEmpty &&
          _items.any((e) => (e['sbarcode'] ?? e['barcode'])?.toString() == barcode)) {
        Toast.show('该商品已存在');
        return;
      }
      setState(() => _items.insert(0, _mapProductToBundleItem(scanned)));
    } catch (_) {
      if (mounted) Toast.show('查询商品失败');
    }
  }

  /// 打包行 → 选品页商品结构（选品页按 productid 匹配勾选，回显已有打包商品）
  List<Map<String, dynamic>> _buildSelectList() {
    return _items
        .map((row) {
          final pid = row['productid']?.toString() ?? row['packageid']?.toString() ?? '';
          return {
            'productid': pid,
            'name': row['sname']?.toString() ?? '',
            'barcode': row['sbarcode']?.toString() ?? '',
            'size': row['size']?.toString() ?? '',
            'unit': row['unit']?.toString() ?? '',
            'qty': row['packagenum'] ?? 1,
          };
        })
        .where((e) => (e['productid'] as String).isNotEmpty)
        .toList();
  }

  /// 快照当前打包商品 id，供选品页返回时区分“已有保留 / 新增插入”
  void _snapshotBeforePids() {
    _selectBeforePids = _items
        .map((r) => r['productid']?.toString() ?? r['packageid']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// 选择商品（多选勾选，对齐小程序 add()）
  Future<void> _selectProducts() async {
    _snapshotBeforePids();
    final result = await _openSelectProduct();
    _applySelectProductResult(result);
  }

  /// 跳转选择商品页面（复选框多选，扫码同码多条时带关键词过滤候选商品，对齐小程序 add/scanFn）
  Future<List<Map<String, dynamic>>?> _openSelectProduct({String? keyword}) async {
    return Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          mergData: const {'itemtype': 1},
          multiple: true,
          checkboxMode: true,
          // 回显勾选已有打包商品（对齐调价 edit.dart：selectList 传行结构用于预勾选）
          selectList: _buildSelectList(),
          // 扫码词过滤：选品页按该关键词展示候选商品（对齐小程序 cond）
          initialKeyword: keyword,
        ),
      ),
    );
  }

  /// 选品页返回数据处理（对齐小程序 onSelectProduct）：
  /// 返回勾选全集 → 未取消勾选的已有打包行原样保留（含已改价格/数量），新勾选商品映射后插入头部
  void _applySelectProductResult(List<Map<String, dynamic>>? result) {
    if (result == null || !mounted) return;
    final returnedPids =
        result.map((e) => e['productid']?.toString() ?? '').where((e) => e.isNotEmpty).toSet();
    setState(() {
      // 1. 保留：返回全集中仍勾选的原有行（取消勾选即移除，顺序不变）
      final kept = _items
          .where((row) => returnedPids
              .contains(row['productid']?.toString() ?? row['packageid']?.toString() ?? ''))
          .toList();
      // 2. 新增：本次新勾选商品映射打包行插入头部（条码与已有行重复时提示跳过）
      for (final prod in result) {
        final pid = prod['productid']?.toString() ?? '';
        if (pid.isEmpty || _selectBeforePids.contains(pid)) continue;
        final String barcode = prod['barcode']?.toString() ?? '';
        if (barcode.isNotEmpty &&
            kept.any((e) => (e['sbarcode'] ?? e['barcode'])?.toString() == barcode)) {
          Toast.show('${prod['name'] ?? ''} 已存在');
          continue;
        }
        kept.insert(0, _mapProductToBundleItem(prod));
      }
      _items = kept;
    });
  }

  /// 将选择/扫描的商品映射为打包商品数据结构（对齐小程序 onSelectProduct/scanFn 字段映射）
  Map<String, dynamic> _mapProductToBundleItem(Map<String, dynamic> prod) {
    final sellprice = double.tryParse(prod['sellprice']?.toString() ?? '0') ?? 0;
    final qty = int.tryParse(prod['qty']?.toString() ?? '1') ?? 1;
    return {
      'packageid': prod['productid']?.toString() ?? '',
      'sbarcode': prod['barcode']?.toString() ?? '',
      'sname': prod['name']?.toString() ?? '',
      'oldsellprice': MathUtils.formatDecimal(2, sellprice),
      'ysellprice': MathUtils.formatDecimal(2, sellprice),
      'yamt': MathUtils.formatDecimal(2, sellprice * qty),
      'mprice1': '',
      'packagenum': qty,
      'mprice2': MathUtils.formatDecimal(2, prod['mprice1'] ?? 0),
      'sellprice': MathUtils.formatDecimal(2, sellprice),
      'size': prod['size']?.toString() ?? '',
      'unit': prod['unit']?.toString() ?? '',
      'productid': prod['productid']?.toString() ?? '',
    };
  }

  /// 更新字段值
  void _updateField(int index, String key, String value) {
    setState(() {
      _items[index] = {..._items[index], key: value};
    });
  }

  /// 删除商品
  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  /// 清空全部
  void _clearAll() {
    if (_items.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确认清空全部商品吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _items.clear());
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 确认保存（与 Vue pack.vue confirmFn 一致）
  void _confirm() {
    if (_items.isEmpty) {
      Toast.show('暂无商品数据');
      return;
    }
    for (final item in _items) {
      final pkgNum = double.tryParse(item['packagenum']?.toString() ?? '0') ?? 0;
      if (pkgNum <= 0) {
        Toast.show('${item['sname'] ?? ''} 包内数量不能为空');
        return;
      }
      final sp = item['sellprice']?.toString().trim() ?? '';
      if (sp.isEmpty) {
        Toast.show('${item['sname'] ?? ''} 打包价不能为空');
        return;
      }
    }
    Navigator.pop(context, _items);
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
          '特价打包商品',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行：商品明细 + 扫描/新增
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF006EFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('商品明细',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                    const Spacer(),
                    GestureDetector(
                      onTap: _scanBarcode,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF006EFF)),
                            SizedBox(width: 2),
                            Text('扫描', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _selectProducts,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 16, top: 12, bottom: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 18, color: Color(0xFF006EFF)),
                            Text('新增', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              // 列表
              Expanded(
                child: _items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFD1D5DB)),
                            SizedBox(height: 12),
                            Text('暂无商品数据',
                                style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        cacheExtent: 800,
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return RepaintBoundary(
                            child: _BundleItemCard(
                              item: item,
                              index: index,
                              isLast: index == _items.length - 1,
                              onFieldChanged: (key, value) => _updateField(index, key, value),
                              onDelete: () => _removeItem(index),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _clearAll,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF006EFF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('清空全部', style: TextStyle(fontSize: 15, color: Color(0xFF006EFF))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _confirm,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('确认',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 打包商品列表项卡片
class _BundleItemCard extends StatelessWidget {
  const _BundleItemCard({
    required this.item,
    required this.index,
    required this.isLast,
    required this.onFieldChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> item;
  final int index;
  final bool isLast;
  final void Function(String key, String value) onFieldChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String sname = item['sname']?.toString() ?? '-';
    final String sbarcode = item['sbarcode']?.toString() ?? '';
    final String unit = item['unit']?.toString() ?? '';
    final String size = item['size']?.toString() ?? '';
    final String oldsellprice = MathUtils.formatDecimal(2, item['oldsellprice'] ?? '0');
    final String packagenum = MathUtils.formatDecimal(1, item['packagenum'] ?? '0');
    final String sellprice = item['sellprice']?.toString() ?? '';
    final String mprice1 = item['mprice1']?.toString() ?? '';
    // 原总售价 = oldsellprice * packagenum
    final double total = (double.tryParse(oldsellprice) ?? 0) * (int.tryParse(packagenum) ?? 0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      margin: isLast ? null : const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border:
            isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: 名称(含单位) + 删除按钮
          Row(
            children: [
              Expanded(
                child: Text(
                  unit.isNotEmpty ? '$sname（$unit）' : sname,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 条码
          if (sbarcode.isNotEmpty)
            Text(sbarcode, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          const SizedBox(height: 8),
          // Row 2: 原单价 + 商品规格
          Row(
            children: [
              const SizedBox(
                  width: 85,
                  child: Text('原单价：', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              Expanded(
                  child: Text(oldsellprice,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              const SizedBox(
                  width: 85,
                  child: Text('商品规格：', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              Expanded(
                  child:
                      Text(size, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3: 原总售价 + 包内数量(输入框)
          Row(
            children: [
              const SizedBox(
                  width: 85,
                  child: Text('原总售价：', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              Expanded(
                  child: Text(MathUtils.formatDecimal(2, total),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              const SizedBox(
                width: 85,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '*', style: TextStyle(fontSize: 12, color: Color(0xFFFF4400))),
                  TextSpan(text: '包内数量：', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ])),
              ),
              Expanded(
                child: _BundleInput(
                  initialValue: packagenum,
                  keyboardType: TextInputType.number,
                  col: 1,
                  onChanged: (v) => onFieldChanged('packagenum', v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 4: 会员价(输入框) + 打包价(输入框)
          Row(
            children: [
              const SizedBox(
                  width: 85,
                  child: Text('会员价：', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              Expanded(
                child: _BundleInput(
                  initialValue: mprice1,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  col: 2,
                  onChanged: (v) => onFieldChanged('mprice1', v),
                ),
              ),
              const SizedBox(
                width: 85,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '*', style: TextStyle(fontSize: 12, color: Color(0xFFFF4400))),
                  TextSpan(text: '打包价：', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ])),
              ),
              Expanded(
                child: _BundleInput(
                  initialValue: sellprice,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  col: 2,
                  onChanged: (v) => onFieldChanged('sellprice', v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 独立输入框组件（StatefulWidget），持有自己的 TextEditingController，
/// 避免父组件 setState 重建时光标被重置导致输入字符顺序错乱
class _BundleInput extends StatefulWidget {
  const _BundleInput({
    required this.initialValue,
    required this.keyboardType,
    required this.onChanged,
    this.col,
  });

  final String initialValue;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;

  /// 小数位数（null 表示不做 blur 格式化）
  final int? col;

  @override
  State<_BundleInput> createState() => _BundleInputState();
}

class _BundleInputState extends State<_BundleInput> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    // 对齐 Vue handleBlur：失焦时格式化数值
    if (widget.col != null) {
      _focusNode.addListener(() {
        if (!_focusNode.hasFocus) {
          final value = double.tryParse(_controller.text) ?? 0;
          final formatted = MathUtils.formatDecimal(widget.col!, value < 0 ? 0 : value);
          if (formatted != _controller.text) {
            _controller.text = formatted;
            widget.onChanged(formatted);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFC8C5C5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: widget.keyboardType,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
