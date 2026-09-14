import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/pro_details_sheet.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 快速调价 - 编辑页
/// 参考 Vue boss 项目 productChangePrice/edit.vue
class ChangePriceEditPage extends StatefulWidget {
  const ChangePriceEditPage({super.key, required this.productData});
  final Map<String, dynamic> productData;

  @override
  State<ChangePriceEditPage> createState() => _ChangePriceEditPageState();
}

class _ChangePriceEditPageState extends State<ChangePriceEditPage> {
  /// 价格字段定义（与 Vue priceItems 对齐）
  static const List<Map<String, String>> _allPriceItems = [
    {'key': 'sellprice', 'label': '零售价'},
    {'key': 'inprice', 'label': '进货价'},
    {'key': 'mprice1', 'label': '会员价一'},
    {'key': 'pfprice1', 'label': '批发价一'},
    {'key': 'psprice', 'label': '配送价'},
    {'key': 'minsellprice', 'label': '最低售价'},
    {'key': 'mprice2', 'label': '会员价二'},
    {'key': 'mprice3', 'label': '会员价三'},
    {'key': 'pfprice2', 'label': '批发价二'},
    {'key': 'pfprice3', 'label': '批发价三'},
  ];

  late Map<String, dynamic> _productData;
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;

  /// 变更类型：6=单位变更，7=规格变更；null=未变更
  int? _ptype;
  String _sname = '';
  String _bsid = '';

  List<Map<String, String>> get _priceItems {
    return _allPriceItems.where((item) {
      final key = item['key']!;
      if (_ptype == 7 && key == 'inprice') {
        return false;
      }
      if ((_ptype == 6 || _ptype == 7) && key == 'psprice') {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _productData = Map<String, dynamic>.from(widget.productData);
    _bsid = _productData['bsid']?.toString() ?? '';
    if (_bsid.isEmpty) {
      try {
        final storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          final storeMap = Map<String, dynamic>.from(
              storeStr.startsWith('{') ? const JsonDecoder().convert(storeStr) as Map : {});
          _bsid = storeMap['id']?.toString() ?? '';
        }
      } catch (_) {}
    }
    _controllers = {};
    for (final item in _allPriceItems) {
      final key = item['key']!;
      final original = _productData[key]?.toString() ?? '0';
      _controllers[key] = TextEditingController(text: MathUtils.formatDecimal(2, original));
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  /// 同步所有价格输入框（单位/规格变更后调用）
  void _syncPriceControllers() {
    for (final item in _allPriceItems) {
      final key = item['key']!;
      final ctrl = _controllers[key];
      if (ctrl != null) {
        ctrl.text = MathUtils.formatDecimal(2, _productData[key] ?? '0');
      }
    }
  }

  /// 输入框失焦时格式化（对齐 Vue priceBlur）
  void _onBlur(String key) {
    final ctrl = _controllers[key];
    if (ctrl != null) {
      ctrl.text = MathUtils.formatDecimal(2, ctrl.text.trim());
    }
  }

  /// 打开商品详情弹窗，支持修改单位和规格（单位/规格互斥锁定）
  /// 复用公共组件 ProDetailsSheet（促销计划/门店调价/标签打印同款）
  void _showProductDetailSheet() {
    ProDetailsSheet.show(
      context,
      item: _productData,
      storeid: _bsid,
      mergData: const {'cgpriceflag': 1},
      showFooter: false,
      onExtendSelected: (type, data) {
        if (!mounted) return;
        setState(() {
          // 同步弹窗内的最新数据（单位/规格/价格/条码）
          _productData.addAll(data);
          // 变更类型：6=单位变更，7=规格变更（对齐 Vue proDetails）
          if (type == 'unit') {
            _ptype = 6;
            _sname = data['unit']?.toString() ?? '';
          } else {
            _ptype = 7;
            _sname = data['size']?.toString() ?? '';
          }
        });
        _syncPriceControllers();
      },
    );
  }

  /// 保存调价
  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (!PermissionUtils.checkPermission('010401', showTip: false)) {
      Toast.show('你无权保存快速调价，请在后台修改权限');
      return;
    }
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'productid': _productData['productid']?.toString() ?? '',
      'barcode': _productData['barcode']?.toString() ?? '',
      'name': _productData['name']?.toString() ?? '',
      'unit': _productData['unit']?.toString() ?? '',
      'unitonlyid': _productData['unitonlyid']?.toString() ?? '',
      'size': _productData['size']?.toString() ?? '',
      'sizeonlyid': _productData['sizeonlyid']?.toString() ?? '',
      'ptype': _ptype,
      'sname': _sname,
    };

    // 填充所有价格字段
    for (final item in _allPriceItems) {
      final key = item['key']!;
      data[key] = double.tryParse(_controllers[key]!.text.trim()) ?? 0;
    }

    try {
      await request(HttpApi.productUpdateStoreprice, data, true);
      if (!mounted) {
        return;
      }
      Toast.show('修改成功');
      Navigator.pop(context, true);
    } catch (_) {
      // 拦截器已统一 Toast 提示
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = _productData['name']?.toString() ?? '-';
    final String size = _productData['size']?.toString() ?? '';
    final String barcode = _productData['barcode']?.toString() ?? '';
    final String unit = _productData['unit']?.toString() ?? '';

    // 图片
    final String imagePath = _productData['imageurl']?.toString() ?? '';
    final String imageUrl = imagePath.isEmpty
        ? ''
        : (imagePath.startsWith('http://') || imagePath.startsWith('https://')
            ? imagePath
            : '${Constant.imageBaseUrl}/$imagePath');

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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
          ),
          child: Column(
            children: [
              // ── 商品信息头部（点击修改单位/规格） ──
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showProductDetailSheet,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // 图片
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
                                child:
                                    Icon(Icons.image_outlined, size: 28, color: Color(0xFFD1D5DB)),
                              ),
                      ),
                      const SizedBox(width: 12),
                      // 名称 + 条码
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name +
                                  (size.isNotEmpty ? '/$size' : '') +
                                  (unit.isNotEmpty ? '($unit)' : ''),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (barcode.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(barcode,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20, color: Color(0xFFB7B7B7)),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              // ── 价格类型头部 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 80,
                      child: Text('价格类型',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                    ),
                    const Expanded(
                      child: Center(
                        child:
                            Text('原价格', style: TextStyle(fontSize: 13, color: Color(0xFF374151))),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('新价格',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Color(0xFF374151))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              // ── 价格字段列表 ──
              ..._priceItems.map((item) => _buildPriceRow(
                    item['key']!,
                    item['label']!,
                    unit,
                  )),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
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
                    border: Border.all(color: const Color(0xFFDEDEDE)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Text('取消', style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: _saving ? const Color(0xFF93C5FD) : const Color(0xFF006EFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('保存',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(String key, String label, String unit) {
    final String originalPrice = MathUtils.formatDecimal(2, _productData[key] ?? '0');
    final ctrl = _controllers[key]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Center(
              child: Text(
                originalPrice + (unit.isNotEmpty ? '/$unit' : ''),
                style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFC8C5C5)),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '0.00',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFFD1D5DB)),
                ),
                onSubmitted: (_) => _onBlur(key),
                onTapOutside: (_) => _onBlur(key),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
