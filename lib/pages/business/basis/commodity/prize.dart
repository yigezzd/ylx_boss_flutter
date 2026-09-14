import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/pro_details_sheet.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 兑奖换购管理页面
/// 对齐小程序 prize.vue（itemtype=10）
/// 管理兑换商品列表，支持扫码/新增/删除/编辑兑换数量/加价兑换/兑换成本/选择单位
/// 数据通过 Navigator.pop 返回给上一页
class CommodityPrizePage extends StatefulWidget {
  const CommodityPrizePage({
    super.key,
    required this.prizelist,
    required this.productName,
    this.productSize,
    this.productBarcode,
    this.productSellprice,
    this.readOnly = false,
  });

  /// 当前兑换商品列表数据（prizelist）
  final List<Map<String, dynamic>> prizelist;

  /// 主商品名称
  final String productName;

  /// 主商品规格
  final String? productSize;

  /// 主商品条码
  final String? productBarcode;

  /// 主商品售价
  final String? productSellprice;

  /// 只读模式（新品申请已审核/已驳回）
  final bool readOnly;

  @override
  State<CommodityPrizePage> createState() => _CommodityPrizePageState();
}

class _CommodityPrizePageState extends State<CommodityPrizePage> {
  late List<Map<String, dynamic>> _items;

  /// 打开选品页前已有兑换商品的 id 快照
  Set<String> _selectBeforePids = {};

  static const int _maxPrize = 5;

  /// 兑奖换购默认字段（对齐小程序 defaultPrizeItem）
  static const Map<String, dynamic> _defaultPrizeItem = {
    'packageid': '',
    'barcode': '',
    'code': '',
    'name': '',
    'productcode': '',
    'productid': '',
    'packageflag': 0,
    'specflag': 0,
    'itemtype': 1,
    'sname': '',
    'unitname': '',
    'unitonlyid': '',
    'sellprice': '',
    'addprice': '',
    'costprice': '',
    'prizenum': '1',
  };

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.prizelist);
  }

  /// 新增：打开选品页多选（对齐小程序 add()）
  Future<void> _addProducts() async {
    if (_items.length >= _maxPrize) {
      Toast.show('最多支持$_maxPrize个兑换商品');
      return;
    }
    _snapshotBeforePids();
    final result = await _openSelectProduct();
    _applySelectProductResult(result);
  }

  /// 跳转选择商品页面（复选框多选 + 勾选上限，对齐小程序 add/scanFn）
  Future<List<Map<String, dynamic>>?> _openSelectProduct({String? keyword}) async {
    return Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          mergData: const {'itemtype': 1},
          multiple: true,
          checkboxMode: true,
          selectList: _buildSelectList(),
          selectMax: _maxPrize,
          initialKeyword: keyword,
        ),
      ),
    );
  }

  /// 兑换行 → 选品页商品结构（选品页按 productid 匹配勾选，回显已有兑换商品）
  List<Map<String, dynamic>> _buildSelectList() {
    return _items
        .map((row) {
          final pid = row['productid']?.toString() ?? row['packageid']?.toString() ?? '';
          return {
            'productid': pid,
            'name': row['name']?.toString() ?? '',
            'barcode': row['barcode']?.toString() ?? '',
            'size': row['sname']?.toString() ?? '',
            'unit': row['unitname']?.toString() ?? '',
            'sellprice': row['sellprice'],
            'code': row['code'],
            'unitonlyid': row['unitonlyid'],
            'packageflag': row['packageflag'],
            'specflag': row['specflag'],
            'itemtype': row['itemtype'],
            'prizenum': row['prizenum'],
            'addprice': row['addprice'],
            'costprice': row['costprice'],
          };
        })
        .where((e) => (e['productid'] as String).isNotEmpty)
        .toList();
  }

  /// 快照当前兑换商品 id
  void _snapshotBeforePids() {
    _selectBeforePids = _items
        .map((r) => r['productid']?.toString() ?? r['packageid']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// 选品页返回数据处理（对齐小程序 onSelectProduct）：
  /// 返回勾选全集 → 已有保留 + 新勾选映射插入头部，判重过滤
  void _applySelectProductResult(List<Map<String, dynamic>>? result) {
    if (result == null || !mounted) return;
    final returnedPids =
        result.map((e) => e['productid']?.toString() ?? '').where((e) => e.isNotEmpty).toSet();

    // 判重去重（对齐小程序 onSelectProduct 重复过滤）
    final seen = <String>{};
    final filteredResult = result.where((item) {
      final key = item['productid']?.toString() ?? '';
      if (seen.contains(key)) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Toast.show('重复商品,已过滤');
        });
        return false;
      }
      seen.add(key);
      return true;
    }).toList();

    setState(() {
      // 1. 保留：返回全集中仍勾选的原有行
      final kept = _items
          .where((row) => returnedPids
              .contains(row['productid']?.toString() ?? row['packageid']?.toString() ?? ''))
          .toList();
      // 2. 新增：本次新勾选商品映射兑换行插入头部
      for (final prod in filteredResult) {
        final pid = prod['productid']?.toString() ?? '';
        if (pid.isEmpty || _selectBeforePids.contains(pid)) continue;
        final String barcode = prod['barcode']?.toString() ?? '';
        if (barcode.isNotEmpty && kept.any((e) => e['barcode']?.toString() == barcode)) {
          Toast.show('${prod['name'] ?? ''} 已存在');
          continue;
        }
        kept.insert(0, _mapProductToPrizeItem(prod));
      }
      if (kept.length > _maxPrize) {
        Toast.show('最多支持$_maxPrize个兑换商品');
        _items = kept.take(_maxPrize).toList();
        return;
      }
      _items = kept;
    });
  }

  /// 将选择/扫描的商品映射为兑换商品数据结构（对齐小程序 onSelectProduct 字段映射）
  Map<String, dynamic> _mapProductToPrizeItem(Map<String, dynamic> prod) {
    // 已选明细原样保留（含用户编辑的兑换数量/加价兑换/兑换成本等）
    if (prod['prizenum'] != null && (prod['packageid']?.toString() ?? '').isNotEmpty) {
      return Map<String, dynamic>.from(prod);
    }
    return {
      ..._defaultPrizeItem,
      'packageid': prod['productid']?.toString() ?? '',
      'barcode': prod['barcode']?.toString() ?? '',
      'code': prod['code']?.toString() ?? '',
      'name': prod['name']?.toString() ?? '',
      'productcode': prod['code']?.toString() ?? '',
      'productid': prod['productid']?.toString() ?? '',
      'packageflag': prod['packageflag'] ?? 0,
      'specflag': prod['specflag'] ?? 0,
      'itemtype': prod['itemtype'] ?? 1,
      'sname': prod['size']?.toString() ?? '',
      'unitname': prod['unit']?.toString() ?? '',
      'unitonlyid': prod['unitonlyid']?.toString() ?? '',
      'sellprice': prod['sellprice']?.toString() ?? '',
    };
  }

  /// 扫描条码添加兑换商品（对齐小程序 scanFn）
  Future<void> _scanBarcode() async {
    if (_items.length >= _maxPrize) {
      Toast.show('最多支持$_maxPrize个兑换商品');
      return;
    }
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

  /// 处理扫码结果（对齐小程序 prize.vue scanFn）：
  /// 同码多条跳转选品页；单条命中判重后合并
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
      // 同码多条判定（对齐小程序 scanFn）
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
        _snapshotBeforePids();
        final selResult = await _openSelectProduct(keyword: searchCode);
        _applySelectProductResult(selResult);
        return;
      }
      // 单条命中：优先取精确匹配
      Map<String, dynamic> scanned = Map<String, dynamic>.from(list[0] as Map);
      if (codeList.length == 1) {
        scanned = Map<String, dynamic>.from(codeList[0] as Map);
      } else if (codeList.isEmpty && barcodeList.length == 1) {
        scanned = Map<String, dynamic>.from(barcodeList[0] as Map);
      }
      // 判重
      final pid = scanned['productid']?.toString() ?? '';
      final exists = _items
          .any((r) => (r['productid']?.toString() ?? r['packageid']?.toString() ?? '') == pid);
      if (exists) {
        Toast.show('重复商品,已过滤');
        return;
      }
      _applySelectProductResult([..._items.map((e) => e), scanned]);
    } catch (_) {
      if (mounted) Toast.show('查询商品失败');
    }
  }

  /// 删除单个兑换商品
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

  /// 编辑文本框（数量/价格，带失焦格式化）
  void _onFieldChanged(int index, String key, String value) {
    setState(() => _items[index][key] = value);
  }

  /// 失焦时格式化数值（对齐 Vue handleBlur）
  void _onFieldBlur(int index, String key, String value, int col) {
    final formatted = MathUtils.formatDecimal(col, value);
    setState(() => _items[index][key] = formatted);
  }

  /// 点击单位：打开商品详情弹窗修改单位（对齐小程序 openUnitDetail → proDetails）
  Future<void> _selectUnit(int index) async {
    final row = _items[index];
    if ((row['packageid']?.toString() ?? '').isEmpty) {
      Toast.show('请先选择商品');
      return;
    }
    // 对齐小程序 openFn：productid 回退 packageid、单位回显、未选规格保证单位可选
    final updated = await ProDetailsSheet.show(
      context,
      item: {
        ...row,
        'productid':
            (row['productid']?.toString() ?? '').isNotEmpty ? row['productid'] : row['packageid'],
        'unit': row['unitname'] ?? '',
        'sizeonlyid': '',
      },
      storeid: _getStoreId(),
      // 对齐小程序 proDetails：paramJust 只含 unit（规格锁定）、不展示货架号
      sizeDisabled: true,
      showShelves: false,
      mergData: const {'ptype': 6},
    );
    if (updated == null || !mounted) {
      return;
    }
    // 对齐小程序 detailConfirm：同步单位/售价/条码/自编码，规格保持不变
    setState(() {
      final target = _items[index];
      final unit = updated['unit']?.toString() ?? '';
      if (unit.isNotEmpty) {
        target['unitname'] = unit;
      }
      target['unitonlyid'] = updated['unitonlyid'] ?? target['unitonlyid'];
      if (updated['sellprice'] != null && updated['sellprice'].toString().isNotEmpty) {
        target['sellprice'] = updated['sellprice'];
      }
      if (updated['barcode']?.toString().isNotEmpty ?? false) {
        target['barcode'] = updated['barcode'];
      }
      if (updated['code']?.toString().isNotEmpty ?? false) {
        target['code'] = updated['code'];
      }
    });
  }

  /// 获取当前门店 ID（对齐小程序 store.id，供商品详情弹窗查询单位）
  String _getStoreId() {
    final storeStr = SpUtil.getString(Constant.store) ?? '';
    try {
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap['id']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// 确认保存（对齐小程序 confirmFn）
  void _confirm() {
    final validList = _items.where((c) => (c['packageid']?.toString() ?? '').isNotEmpty).toList();
    if (validList.isEmpty) {
      Toast.show('请至少选择一个兑换商品');
      return;
    }
    for (final item in validList) {
      final prizenum = item['prizenum']?.toString() ?? '';
      if (prizenum.isEmpty) {
        Toast.show('请输入兑换数量');
        return;
      }
      final num = double.tryParse(prizenum) ?? 0;
      if (num <= 0) {
        Toast.show('兑换数量必须大于0');
        return;
      }
    }
    Navigator.pop(context, _items);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.readOnly;

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
          '兑奖换购',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
          ),
          child: Column(
            children: [
              // ── 当前兑奖商品（主商品信息，对齐小程序 prize.vue 头部区域）──
              _buildProductInfoSection(),
              // ── 兑换商品明细标题 + 扫描/新增 ──
              _buildDetailHeader(isEdit),
              // ── 兑换商品列表 ──
              Expanded(
                child: _buildPrizeList(isEdit),
              ),
            ],
          ),
        ),
      ),
      // 底部操作栏（只读模式隐藏）
      bottomNavigationBar: isEdit ? null : _buildBottomBar(),
    );
  }

  /// 当前兑奖商品信息区（对齐小程序 prize.vue 头部区域：标题/名称/条码/售价 + 底部分隔线）
  Widget _buildProductInfoSection() {
    final name = widget.productName;
    final size = widget.productSize ?? '';
    final barcode = widget.productBarcode ?? '';
    final sellprice = widget.productSellprice ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '当前兑奖商品',
            style: TextStyle(fontSize: 14, color: Color(0xFF000000)),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  ),
                  if (size.isNotEmpty)
                    TextSpan(
                      text: '（$size）',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                ],
              ),
            ),
          ],
          if (barcode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '商品条码：$barcode',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '商品售价：${MathUtils.formatDecimal(2, sellprice)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
          ),
        ],
      ),
    );
  }

  /// 兑换商品明细标题行（对齐小程序 prize.vue：标题 + 扫描/新增按钮 + 底部分隔线）
  Widget _buildDetailHeader(bool isEdit) {
    return Container(
      padding: EdgeInsets.only(left: 14, right: isEdit ? 14 : 0, top: 4, bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
      ),
      child: Row(
        children: [
          const Text('兑换商品明细',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          const Spacer(),
          if (!isEdit) ...[
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
              onTap: _addProducts,
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
        ],
      ),
    );
  }

  /// 兑换商品列表（对齐小程序 prize.vue：明细行扁平排列）
  Widget _buildPrizeList(bool isEdit) {
    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('暂无商品数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      cacheExtent: 800,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return RepaintBoundary(
          child: _PrizeItemCard(
            item: item,
            index: index,
            isLast: index == _items.length - 1,
            readOnly: isEdit,
            onFieldChanged: (k, v) => _onFieldChanged(index, k, v),
            onFieldBlur: (k, v, col) => _onFieldBlur(index, k, v, col),
            onDelete: () => _removeItem(index),
            onSelectUnit: () => _selectUnit(index),
          ),
        );
      },
    );
  }

  /// 底部确认栏（对齐小程序底部操作栏）
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

/// 兑换商品列表项卡片（对齐小程序 prize.vue list-item）
class _PrizeItemCard extends StatelessWidget {
  const _PrizeItemCard({
    required this.item,
    required this.index,
    required this.isLast,
    required this.readOnly,
    required this.onFieldChanged,
    required this.onFieldBlur,
    required this.onDelete,
    required this.onSelectUnit,
  });

  final Map<String, dynamic> item;
  final int index;
  final bool isLast;
  final bool readOnly;
  final void Function(String key, String value) onFieldChanged;
  final void Function(String key, String value, int col) onFieldBlur;
  final VoidCallback onDelete;
  final VoidCallback onSelectUnit;

  @override
  Widget build(BuildContext context) {
    final String name = item['name']?.toString() ?? '请选择商品';
    final String sname = item['sname']?.toString() ?? '';
    final String barcode = item['barcode']?.toString() ?? '';
    final String sellprice = MathUtils.formatDecimal(2, item['sellprice'] ?? '');
    final String unitname = item['unitname']?.toString() ?? '';
    final String prizenum = item['prizenum']?.toString() ?? '1';
    final String addprice = item['addprice']?.toString() ?? '';
    final String costprice = item['costprice']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: isLast
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: 名称(含规格) + 删除按钮（对齐小程序 tmicon-times-circle-fill）
          Row(
            children: [
              Expanded(
                child: Text(
                  sname.isNotEmpty ? '$name（$sname）' : name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!readOnly)
                GestureDetector(
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8, top: 4, bottom: 4),
                    child: Icon(Icons.cancel, size: 16, color: Color(0xFFFF4400)),
                  ),
                ),
            ],
          ),
          // 条码
          if (barcode.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(barcode, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ],
          const SizedBox(height: 6),
          // Row 2: 商品售价
          Row(
            children: [
              const SizedBox(
                  width: 75,
                  child: Text('商品售价：', style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)))),
              Expanded(
                child:
                    Text(sellprice, style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 3: 单位 + 兑换数量(*必填)
          Row(
            children: [
              // 单位（点击打开商品详情弹窗修改单位，对齐小程序 openUnitDetail）
              Expanded(
                child: GestureDetector(
                  onTap: readOnly ? null : onSelectUnit,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      const SizedBox(
                          width: 75,
                          child: Text('单位：',
                              style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)))),
                      Expanded(
                        child: Text(
                          unitname.isNotEmpty ? unitname : '请选择',
                          style: TextStyle(
                              fontSize: 13,
                              color: unitname.isNotEmpty
                                  ? const Color(0xFF333333)
                                  : const Color(0xFF8B8B8B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!readOnly)
                        const Icon(Icons.chevron_right, size: 16, color: Color(0xFFB7B7B7)),
                    ],
                  ),
                ),
              ),
              // 兑换数量(*必填)
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(
                      width: 85,
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: '*', style: TextStyle(fontSize: 13, color: Color(0xFFFF4400))),
                        TextSpan(
                            text: '兑换数量：',
                            style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
                      ])),
                    ),
                    Expanded(
                      child: _PrizeInput(
                        initialValue: prizenum,
                        keyboardType: TextInputType.number,
                        col: 1,
                        readOnly: readOnly,
                        onChanged: (v) => onFieldChanged('prizenum', v),
                        onBlurFormatted: (v) => onFieldBlur('prizenum', v, 1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 4: 加价兑换 + 兑换成本
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(
                        width: 75,
                        child: Text('加价兑换：',
                            style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)))),
                    Expanded(
                      child: _PrizeInput(
                        initialValue: addprice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        col: 2,
                        readOnly: readOnly,
                        onChanged: (v) => onFieldChanged('addprice', v),
                        onBlurFormatted: (v) => onFieldBlur('addprice', v, 2),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(
                        width: 85,
                        child: Text('兑换成本：',
                            style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)))),
                    Expanded(
                      child: _PrizeInput(
                        initialValue: costprice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        col: 2,
                        readOnly: readOnly,
                        onChanged: (v) => onFieldChanged('costprice', v),
                        onBlurFormatted: (v) => onFieldBlur('costprice', v, 2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 兑换商品输入框组件（独立 StatefulWidget，避免父组件重建时光标重置）
class _PrizeInput extends StatefulWidget {
  const _PrizeInput({
    required this.initialValue,
    required this.keyboardType,
    required this.onChanged,
    required this.onBlurFormatted,
    this.col,
    this.readOnly = false,
  });

  final String initialValue;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onBlurFormatted;

  /// 小数位数（null 表示不做 blur 格式化）
  final int? col;
  final bool readOnly;

  @override
  State<_PrizeInput> createState() => _PrizeInputState();
}

class _PrizeInputState extends State<_PrizeInput> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    if (widget.col != null) {
      _focusNode.addListener(() {
        if (!_focusNode.hasFocus) {
          final value = double.tryParse(_controller.text) ?? 0;
          final formatted = MathUtils.formatDecimal(widget.col!, value < 0 ? 0 : value);
          if (formatted != _controller.text) {
            _controller.text = formatted;
            widget.onBlurFormatted(formatted);
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
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFC8C5C5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: widget.keyboardType,
        readOnly: widget.readOnly,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
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
