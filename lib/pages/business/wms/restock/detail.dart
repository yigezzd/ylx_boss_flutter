import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 商品补货页（对齐 Vue wms/restock/restockDetail.vue）
class WmsRestockDetailPage extends StatefulWidget {
  const WmsRestockDetailPage({super.key, required this.productInfo});

  /// 列表页传入的商品信息（对齐 Vue eventChannel acceptRestockData）
  final Map<String, dynamic> productInfo;

  @override
  State<WmsRestockDetailPage> createState() => _WmsRestockDetailPageState();
}

class _WmsRestockDetailPageState extends State<WmsRestockDetailPage> {
  late Map<String, dynamic> _productInfo;

  /// 补货数量（对齐 Vue restockQty，tm-stepper fixed=2 min=0）
  double _restockQty = 0;
  final TextEditingController _qtyController = TextEditingController();

  /// 移出货位库存列表
  final List<Map<String, dynamic>> _locationStockList = [];
  bool _locationLoaded = false;
  int _selectedIndex = -1;

  bool _saving = false;

  String _storeId = '';

  @override
  void initState() {
    super.initState();
    _productInfo = Map<String, dynamic>.from(widget.productInfo);
    _restockQty = _num(_productInfo['needqty']);
    _qtyController.text = MathUtils.formatDecimal(2, _restockQty);
    _loadLocalInfo();
    _loadLocationStockList();
  }

  @override
  void dispose() {
    _qtyController.dispose();
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

  /// 查询商品货位库存列表（对齐 Vue getLocationStockList）
  Future<void> _loadLocationStockList() async {
    final productid = _productInfo['productid']?.toString() ?? '';
    if (productid.isEmpty) return;
    try {
      final result = await request(HttpApi.wmsProductLocationStockList, {
        'productid': productid,
        'sids': [_storeId],
        'is_page': 0,
        'zonetype': 2,
      });
      if (!mounted) return;
      final data = result['data'];
      final raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      setState(() {
        _locationStockList
          ..clear()
          ..addAll(raw.whereType<Map<String, dynamic>>());
        _locationLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _locationLoaded = true);
    }
  }

  void _selectLocation(int index) {
    setState(() => _selectedIndex = index);
  }

  /// 步进器 +/-（步长 1，最小 0）
  void _stepQty(double delta) {
    final next = MathUtils.add(_restockQty, delta);
    if (next < 0) return;
    setState(() {
      _restockQty = next;
      _qtyController.text = MathUtils.formatDecimal(2, next);
    });
  }

  /// 手动输入同步
  void _onQtyChanged(String text) {
    final v = double.tryParse(text.trim());
    if (v != null && v >= 0) {
      _restockQty = v;
    }
  }

  /// 保存（对齐 Vue save 校验链）
  Future<void> _save() async {
    if (_selectedIndex < 0 || _selectedIndex >= _locationStockList.length) {
      Toast.show('请选择移出货位号');
      return;
    }
    final qty = _restockQty;
    if (qty <= 0) {
      Toast.show('补货数量必须大于0');
      return;
    }
    final selectedRow = Map<String, dynamic>.from(_locationStockList[_selectedIndex]);
    if (qty > _num(selectedRow['qty'])) {
      Toast.show('补货数量不能超过移出货位的可用库存');
      return;
    }
    if (qty > _num(_productInfo['needqty'])) {
      Toast.show('补货数量不能超过商品待补货数');
      return;
    }
    if (_saving) return;

    selectedRow['lunchqty'] = qty;
    selectedRow['sellamt'] = _firstTruthy(
        [selectedRow['sellamt'], MathUtils.multiply(qty, _num(selectedRow['sellprice']))]);
    selectedRow['psamt'] =
        _firstTruthy([selectedRow['psamt'], MathUtils.multiply(qty, _num(selectedRow['psprice']))]);

    final params = <String, dynamic>{
      'lunchqty': qty,
      'bsid': _storeId,
      'sellamt': selectedRow['sellamt'],
      'psamt': selectedRow['psamt'],
      ..._productInfo,
      'detaillist': [selectedRow],
    };

    setState(() => _saving = true);
    try {
      await request(HttpApi.wmsRestockSave, params);
      if (!mounted) return;
      Toast.show('补货成功');
      Navigator.pop(context);
    } catch (_) {
      // 请求层已统一提示错误
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  /// 对齐 JS `||`：返回第一个非 0 数值
  static num _firstTruthy(List<dynamic> values) {
    for (final v in values) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n != null && n != 0) return n;
    }
    return 0;
  }

  static String _date10(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : '--';
  }

  @override
  Widget build(BuildContext context) {
    final String name =
        _productInfo['name']?.toString() ?? _productInfo['productname']?.toString() ?? '-';
    final String size = _productInfo['size']?.toString() ?? '';
    final String barcode = _productInfo['barcode']?.toString() ?? '';
    final String stockqty = MathUtils.formatDecimal(1, _productInfo['stockqty'] ?? 0);
    final String maxstockqty = MathUtils.formatDecimal(1, _productInfo['maxstockqty'] ?? 0);
    final String locationcode = _productInfo['locationcode']?.toString() ?? '';
    final String updatetime = _date10(_productInfo['updatetime']);

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
          '商品补货',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        cacheExtent: 800,
        children: [
          // ── 商品基本信息 ──
          _buildCard(
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
                      '库存：$stockqty',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
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
                      '最大储存量：$maxstockqty',
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
                      '最后上架时间：$updatetime',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ── 待补货数 & 补货数量 ──
          _buildCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 90,
                        child:
                            Text('待补货数', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
                      ),
                      Expanded(
                        child: Text(
                          MathUtils.formatDecimal(1, _productInfo['needqty'] ?? 0),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 90,
                        child:
                            Text('补货数量', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
                      ),
                      const Spacer(),
                      _buildStepper(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ── 选择移出货位号 ──
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择移出货位号',
                  style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
                ),
                if (_locationStockList.isEmpty && _locationLoaded)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                    ),
                  )
                else
                  ...List.generate(
                    _locationStockList.length,
                    (index) => RepaintBoundary(
                      child: _buildLocationStockItem(_locationStockList[index], index),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      // ── 底部操作按钮 ──
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          12,
          10,
          12,
          MediaQuery.of(context).padding.bottom + 10,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 16, color: Color(0xFF006EFF)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: _saving ? const Color(0xFFB0C8EE) : const Color(0xFF006EFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _saving ? '保存中...' : '确认',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: child,
    );
  }

  /// 补货数量步进器（对齐 Vue tm-stepper fixed=2 min=0，支持手动输入）
  Widget _buildStepper() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _restockQty > 0 ? () => _stepQty(-1) : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFDEDEDE)),
            ),
            child: Icon(
              Icons.remove,
              size: 16,
              color: _restockQty > 0 ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
            ),
          ),
        ),
        Container(
          width: 72,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDEDEDE)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            onChanged: _onQtyChanged,
            onSubmitted: (text) {
              setState(() {
                _qtyController.text = MathUtils.formatDecimal(2, _restockQty);
              });
            },
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => _stepQty(1),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFDEDEDE)),
            ),
            child: const Icon(Icons.add, size: 16, color: Color(0xFF333333)),
          ),
        ),
      ],
    );
  }

  /// 移出货位库存项（对齐 Vue location-item）
  Widget _buildLocationStockItem(Map<String, dynamic> loc, int index) {
    final bool selected = _selectedIndex == index;
    final String locationcode = loc['locationcode']?.toString() ?? '';
    final String qty = MathUtils.formatDecimal(1, loc['qty'] ?? 0);
    final String batchno = loc['batchno']?.toString() ?? '';
    final String lastintime = _date10(loc['lastintime']);
    final String maxstockqty = MathUtils.formatDecimal(1, loc['maxstockqty'] ?? 0);
    final String validdate = _date10(loc['validdate']);

    return GestureDetector(
      onTap: () => _selectLocation(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '存货位：$locationcode',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF006EFF),
                    ),
                  ),
                ),
                Text(
                  '库存：$qty',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_off,
                  size: 20,
                  color: selected ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '批次：$batchno',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    '最后上架时间：$lastintime',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '最大储量：$maxstockqty',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
                ),
                Expanded(
                  child: Text(
                    '有效期时间：$validdate',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
