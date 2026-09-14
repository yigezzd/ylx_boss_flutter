import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_location.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 商品移货页（对齐 Vue wms/stockQuery/moveGoods.vue）
class WmsMoveGoodsPage extends StatefulWidget {
  const WmsMoveGoodsPage({super.key, required this.data});

  /// 列表页传入的移货数据（对齐 Vue eventChannel sendMoveData）
  final Map<String, dynamic> data;

  @override
  State<WmsMoveGoodsPage> createState() => _WmsMoveGoodsPageState();
}

class _WmsMoveGoodsPageState extends State<WmsMoveGoodsPage> {
  late Map<String, dynamic> _query;

  /// 移货数量（对齐 Vue moveQty / moveQtyStr）
  double _moveQty = 0;
  final TextEditingController _qtyController = TextEditingController();

  /// 移入货位列表
  final List<Map<String, dynamic>> _locationList = [];
  bool _locationLoaded = false;
  String _selectedLocationId = '';
  String _selectedLocationCode = '';

  bool _saving = false;

  String _storeId = '';

  @override
  void initState() {
    super.initState();
    _query = Map<String, dynamic>.from(widget.data);
    _moveQty = _num(_query['qty']);
    _qtyController.text = MathUtils.formatDecimal(2, _moveQty);
    _loadLocalInfo();
    _loadLocationList();
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

  /// 查询可移入货位列表（对齐 Vue getLocationList）
  Future<void> _loadLocationList() async {
    try {
      final result = await request(HttpApi.wmsRemoveLocationList, {
        'counterid': _query['counterid']?.toString() ?? '',
        'stopflag': '',
        'storeid': _storeId,
        'zonetypenot': '3',
        'locationIdnot': _query['fromlocationid']?.toString() ?? '',
        'productid': _query['productid']?.toString() ?? '',
      });
      if (!mounted) return;
      final data = result['data'];
      final raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      // 排除移出货位本身
      final fromId = _query['fromlocationid']?.toString() ?? '';
      setState(() {
        _locationList
          ..clear()
          ..addAll(raw.whereType<Map<String, dynamic>>().where(
                (loc) => loc['locationid']?.toString() != fromId,
              ));
        _locationLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _locationLoaded = true);
    }
  }

  void _selectLocation(Map<String, dynamic> loc) {
    setState(() {
      _selectedLocationId = loc['locationid']?.toString() ?? '';
      _selectedLocationCode = loc['locationcode']?.toString() ?? '';
    });
  }

  /// 新货位号选择（对齐 Vue openNewLocation，zonetypenot=3 排除收货暂存）
  Future<void> _openNewLocation() async {
    final result = await SelectLocationPage.show(
      context,
      zonetype: null,
      withStopflag: true,
      zonetypenot: '3',
      locationIdnot: _query['fromlocationid']?.toString() ?? '',
      title: '选择货位号',
    );
    if (result == null || !mounted) return;
    final locationid = result['locationid']?.toString() ?? '';
    setState(() {
      _selectedLocationId = locationid;
      _selectedLocationCode = result['locationcode']?.toString() ?? '';
      // 将新货位添加到列表顶部（如果不存在）
      final exists = _locationList.any((l) => l['locationid']?.toString() == locationid);
      if (!exists) {
        _locationList.insert(0, {
          'locationid': locationid,
          'locationcode': result['locationcode']?.toString() ?? '',
          'locationname': result['locationname']?.toString() ?? '',
          'qty': 0,
        });
      }
    });
  }

  /// 移货数量失焦校验（对齐 Vue onQtyBlur）
  void _onQtyBlur() {
    final v = double.tryParse(_qtyController.text.trim());
    final maxQty = _num(_query['qty']);
    if (v == null || v < 0) {
      _moveQty = 0;
      _qtyController.text = '0.00';
    } else if (v > maxQty) {
      Toast.show('移货数量不能超过可用库存');
      _moveQty = maxQty;
      _qtyController.text = MathUtils.formatDecimal(2, maxQty);
    } else {
      _moveQty = v;
      _qtyController.text = MathUtils.formatDecimal(2, v);
    }
    setState(() {});
  }

  void _stepMinus() {
    final raw = MathUtils.add(_moveQty, -1);
    final next = raw < 0 ? 0.0 : raw;
    setState(() {
      _moveQty = next;
      _qtyController.text = MathUtils.formatDecimal(2, next);
    });
  }

  void _stepPlus() {
    final next = MathUtils.add(_moveQty, 1);
    if (next > _num(_query['qty'])) {
      Toast.show('移货数量不能超过可用库存');
      return;
    }
    setState(() {
      _moveQty = next;
      _qtyController.text = MathUtils.formatDecimal(2, next);
    });
  }

  /// 保存（对齐 Vue save）
  Future<void> _save() async {
    if (_selectedLocationId.isEmpty) {
      Toast.show('请选择移入货位号');
      return;
    }
    final qty = double.tryParse(_qtyController.text.trim()) ?? _moveQty;
    if (qty <= 0) {
      Toast.show('移货数量必须大于0');
      return;
    }
    if (_saving) return;

    final batchno = _query['batchno']?.toString() ?? '';
    final params = <String, dynamic>{
      ..._query,
      'counterid': _query['counterid']?.toString() ?? '',
      'productid': _query['productid']?.toString() ?? '',
      'outlocationid': _query['fromlocationid']?.toString() ?? '',
      'outlocationcode': _query['fromlocationcode']?.toString() ?? '',
      'inlocationid': _selectedLocationId,
      'inlocationcode': _selectedLocationCode,
      'stockzoneid': _query['stockzoneid']?.toString() ?? '',
      'qty': qty,
      'sellamt': _firstTruthyNum([_query['sellamt'], 0]),
      'psamt': _firstTruthyNum([_query['psamt'], 0]),
      'outbatchno': batchno,
      'inbatchno': batchno,
    };

    setState(() => _saving = true);
    try {
      await request(HttpApi.wmsMoveStock, params);
      if (!mounted) return;
      Toast.show('移货成功');
      Navigator.pop(context, true);
    } catch (_) {
      // 请求层已统一提示错误
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 货位区域类型文案（对齐 Vue zonetypeStr）
  static String _zonetypeLabel(dynamic zonetype) {
    final v = zonetype?.toString() ?? '';
    if (v == '1') return '拣货位：';
    if (v == '2') return '存货位：';
    if (v == '3') return '收货暂存：';
    return '其它：';
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  /// 对齐 JS `||`：返回第一个非 0 数值
  static num _firstTruthyNum(List<dynamic> values) {
    for (final v in values) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n != null && n != 0) return n;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final String countername = _query['countername']?.toString() ?? '';
    final String productname = _query['productname']?.toString() ?? '';
    final String size = _query['size']?.toString() ?? '';
    final String fromlocationcode = _query['fromlocationcode']?.toString() ?? '';

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
          '商品移货',
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
          // ── 基础信息 ──
          _buildCard(
            child: Column(
              children: [
                _buildInfoRow('仓库', countername),
                _buildInfoRow('商品', size.isEmpty ? productname : '$productname（$size）'),
                _buildInfoRow('移出货位', fromlocationcode),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 80,
                        child:
                            Text('移货数量', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
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
          // ── 选择移入货位 ──
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '选择移入货位号',
                      style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _openNewLocation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF006EFF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '新货位号',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_locationList.isEmpty && _locationLoaded)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                    ),
                  )
                else
                  ...List.generate(
                    _locationList.length,
                    (index) => RepaintBoundary(
                      child: _buildLocationItem(_locationList[index]),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: child,
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  /// 移货数量步进器（对齐 Vue stepper，支持手动输入，失焦校验）
  Widget _buildStepper() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _moveQty > 0 ? _stepMinus : null,
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
              color: _moveQty > 0 ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
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
            onEditingComplete: _onQtyBlur,
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
            ),
          ),
        ),
        GestureDetector(
          onTap: _stepPlus,
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

  /// 移入货位项（对齐 Vue location-item）
  Widget _buildLocationItem(Map<String, dynamic> loc) {
    final String locationid = loc['locationid']?.toString() ?? '';
    final bool selected = _selectedLocationId == locationid;
    final String locationcode = loc['locationcode']?.toString() ?? '';
    final String stockqty = MathUtils.formatDecimal(2, loc['stockqty'] ?? 0);

    return GestureDetector(
      onTap: () => _selectLocation(loc),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _zonetypeLabel(loc['zonetype']) + locationcode,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '库存：$stockqty',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_off,
              size: 20,
              color: selected ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC),
            ),
          ],
        ),
      ),
    );
  }
}
