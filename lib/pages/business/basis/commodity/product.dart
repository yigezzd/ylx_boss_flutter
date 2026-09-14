import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// 商品明细（成份/拆分商品管理）页面
/// 对应原型"商品明细"界面，管理拆分/组装商品的成份列表
/// 数据通过 Navigator.pop 返回给上一页
class CommodityPackPage extends StatefulWidget {
  const CommodityPackPage({
    super.key,
    required this.items,
    this.productName = '',
    this.productId = '',
    this.itemtype = '1',
  });

  /// 当前成份列表数据
  final List<Map<String, dynamic>> items;

  /// 商品名称（展示用）
  final String productName;

  /// 主商品 id（成份行 productid 字段，对齐小程序 query.productid）
  final String productId;

  final String itemtype;
  @override
  State<CommodityPackPage> createState() => _CommodityPackPageState();
}

class _CommodityPackPageState extends State<CommodityPackPage> {
  late List<Map<String, dynamic>> _items;

  /// 打开选品页前已有成份的子商品 id 快照（对齐调价 edit.dart _selectBeforeIds）：
  /// 选品页返回勾选全集，据此区分“已有保留 / 新增追加”，避免扫码过滤场景误清空明细
  Set<String> _selectBeforePids = {};

  /// 根据 itemtype 动态返回页面标题
  String get _pageTitle {
    switch (widget.itemtype) {
      case '2':
        return '拆分商品';
      case '3':
        return '组装商品';
      case '4':
        return '自动拆分商品';
      case '5':
        return '自动组装商品';
      case '8':
        return '打包商品';
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.items);
  }

  /// 扫描条码添加成份（与采购入库扫码逻辑一致：扫码 → 接口查询商品 → 已存在则累加数量，否则新增一行）
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

  /// 处理扫码结果（对齐小程序 scanFn）：
  /// 同码多条跳转选品页；单条命中按 packageid 判重，已存在则提示，否则新增成份行
  Future<void> _handleScannedBarcode(String code) async {
    if (code.trim().isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    try {
      final result = await request(HttpApi.productGetList, {
        'scancode': code,
        'is_page': 1,
        'page': 1,
        'pagesize': 10,
        'itemtype': 1,
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
          .where((c) => (c['code']?.toString() ?? '').isNotEmpty && c['code'].toString() == code)
          .toList();
      final barcodeList = list
          .where(
              (c) => (c['barcode']?.toString() ?? '').isNotEmpty && c['barcode'].toString() == code)
          .toList();
      final needJump = codeList.length >= 2 || (codeList.isEmpty && barcodeList.length >= 2);
      if (needJump) {
        // 选品页按扫码词过滤候选商品，返回后合并明细（勾选全集：已有保留 + 新增追加）
        _snapshotBeforePids();
        final result = await _openSelectProduct(keyword: code);
        _applySelectProductResult(result);
        return;
      }
      // 单条命中：优先取与自编码/商品条码精确匹配的商品，否则取第一条（对齐小程序 scanFn）
      Map<String, dynamic> scanned = Map<String, dynamic>.from(list[0] as Map);
      if (codeList.length == 1) {
        scanned = Map<String, dynamic>.from(codeList[0] as Map);
      } else if (codeList.isEmpty && barcodeList.length == 1) {
        scanned = Map<String, dynamic>.from(barcodeList[0] as Map);
      }
      // 成分判重：扫描商品（productid）对应明细行 packageid，已存在则不重复添加
      final exists =
          _items.any((row) => row['packageid']?.toString() == scanned['productid']?.toString());
      if (exists) {
        Toast.show('单据中已存在该商品');
        return;
      }
      setState(() {
        _items.insert(0, {
          'productid': widget.productId,
          'packageid': scanned['productid']?.toString() ?? '',
          'sbarcode': scanned['barcode']?.toString() ?? '',
          'sname': scanned['name']?.toString() ?? scanned['productname']?.toString() ?? '',
          'onlyid': '',
          'packagenum': 1,
          'size': scanned['size']?.toString() ?? '',
        });
      });
      Toast.show('扫描添加成功');
    } catch (_) {
      if (mounted) Toast.show('查询商品失败');
    }
  }

  /// 成份行 → 选品页商品结构（选品页按 productid 匹配勾选，成份行需将 packageid 映射为商品 id；
  /// qty 携带成份数量，供选品页“已选 N 项”统计及返回全集使用）
  List<Map<String, dynamic>> _buildSelectList() {
    return _items
        .map((row) {
          final pid = row['packageid']?.toString() ?? '';
          return {
            'productid': pid,
            'name': row['sname']?.toString() ?? '',
            'barcode': row['sbarcode']?.toString() ?? '',
            'size': row['size']?.toString() ?? '',
            'qty': row['packagenum'] ?? 1,
          };
        })
        .where((e) => (e['productid'] as String).isNotEmpty)
        .toList();
  }

  /// 快照当前成份子商品 id，供选品页返回时区分“已有保留 / 新增追加”
  void _snapshotBeforePids() {
    _selectBeforePids =
        _items.map((r) => r['packageid']?.toString() ?? '').where((e) => e.isNotEmpty).toSet();
  }

  /// 跳转选择商品页面（复选框多选，扫码同码多条时带关键词过滤候选商品，对齐小程序 selectProductFn/scanFn）
  Future<List<Map<String, dynamic>>?> _openSelectProduct({String? keyword}) async {
    return Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          // itemtypenot: '1',
          mergData: const {'itemtype': 1},
          multiple: true,
          checkboxMode: true,
          // 回显勾选已有成份（对齐调价 edit.dart：selectList 传行结构用于预勾选）
          selectList: _buildSelectList(),
          // 扫码词过滤：选品页按该关键词展示候选商品（对齐小程序 cond）
          initialKeyword: keyword,
        ),
      ),
    );
  }

  /// 选品页返回数据处理（对齐小程序 handleProductConfirm）：
  /// 返回勾选全集 → 未取消勾选的已有成份原样保留（含已修改数量），新勾选商品映射成份行追加
  void _applySelectProductResult(List<Map<String, dynamic>>? result) {
    if (result == null || !mounted) return;
    final returnedPids =
        result.map((e) => e['productid']?.toString() ?? '').where((e) => e.isNotEmpty).toSet();
    setState(() {
      // 1. 保留：返回全集中仍勾选的原有成份（取消勾选即从明细移除，顺序不变）
      final kept =
          _items.where((row) => returnedPids.contains(row['packageid']?.toString() ?? '')).toList();
      // 2. 追加：本次新增勾选的商品（成份数量默认 1，返回后在明细中可调整）
      for (final prod in result) {
        final pid = prod['productid']?.toString() ?? '';
        if (pid.isEmpty || _selectBeforePids.contains(pid)) continue;
        kept.add({
          'productid': widget.productId,
          'packageid': pid,
          'sbarcode': prod['barcode']?.toString() ?? '',
          'sname': prod['name']?.toString() ?? prod['productname']?.toString() ?? '',
          'onlyid': '',
          'packagenum': 1,
          'size': prod['size']?.toString() ?? '',
        });
      }
      _items = kept;
    });
  }

  /// 跳转选择商品页面，将选中的商品添加到成份列表（对齐小程序 selectProductFn）
  Future<void> _selectProducts() async {
    _snapshotBeforePids();
    final result = await _openSelectProduct();
    _applySelectProductResult(result);
  }

  /// 更新成份数量
  void _updateQty(int index, int delta) {
    setState(() {
      final current = int.tryParse(_items[index]['packagenum']?.toString() ?? '0') ?? 0;
      final newVal = (current + delta).clamp(0, 99999);
      _items[index] = {..._items[index], 'packagenum': newVal.toString()};
    });
  }

  /// 删除成份
  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
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
        centerTitle: true,
        title: Text(
          _pageTitle,
          style:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
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
                    // 扫描按钮
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
                    // 新增按钮
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
              Expanded(
                child: _items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFD1D5DB)),
                            SizedBox(height: 12),
                            Text('暂无成份明细',
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
                            child: _PackDetailItem(
                              item: item,
                              isLast: index == _items.length - 1,
                              onDecrement: () => _updateQty(index, -1),
                              onIncrement: () => _updateQty(index, 1),
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
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF006EFF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('取消', style: TextStyle(fontSize: 15, color: Color(0xFF006EFF))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context, _items),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('保存',
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

/// 成份明细列表项
class _PackDetailItem extends StatelessWidget {
  const _PackDetailItem({
    required this.item,
    required this.isLast,
    required this.onDecrement,
    required this.onIncrement,
    required this.onDelete,
  });

  final Map<String, dynamic> item;
  final bool isLast;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String name = item['sname']?.toString() ?? '-';
    final String packagenum = MathUtils.formatDecimal(1, item['packagenum'] ?? '0');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border:
            isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：名称 + 删除按钮
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
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
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：成份数量 + 步进器
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('成份数量：', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
              _QuantityControl(
                value: packagenum,
                onDecrement: onDecrement,
                onIncrement: onIncrement,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 数量控制组件 (-, 数值, +)
class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onDecrement,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Text('−',
                style:
                    TextStyle(fontSize: 18, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
          ),
        ),
        Flexible(
          child: SizedBox(
            height: 32,
            child: Center(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
            ),
          ),
        ),
        GestureDetector(
          onTap: onIncrement,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Text('+',
                style:
                    TextStyle(fontSize: 18, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }
}
