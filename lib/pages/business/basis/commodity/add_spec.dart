import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// 新增/编辑规格页面
/// 参考 boss 项目 addspec.vue
class AddSpecPage extends StatefulWidget {
  const AddSpecPage({
    super.key,
    this.typecode = '',
    this.typeid = '',
    this.specData,
    this.sizedata = const [],
    this.packpage = const [],
    this.barcode = '',
    this.editIndex = -1,
  });

  /// 分类编码（生成条码用）
  final String typecode;

  /// 分类ID
  final String typeid;

  /// 编辑时传入已有规格数据，null 为新增
  final Map<String, dynamic>? specData;

  /// 已有规格列表（校验条码重复用，排除自身）
  final List<Map<String, dynamic>> sizedata;

  /// 包装数据（校验条码冲突用）
  final List<Map<String, dynamic>> packpage;

  /// 商品主条码（校验条码冲突用）
  final String barcode;

  /// 编辑时在 sizedata 中的索引，-1 表示新增
  final int editIndex;

  @override
  State<AddSpecPage> createState() => _AddSpecPageState();
}

class _AddSpecPageState extends State<AddSpecPage> {
  final TextEditingController _snameCtrl = TextEditingController();
  final TextEditingController _sbarcodeCtrl = TextEditingController();
  final TextEditingController _sellpriceCtrl = TextEditingController();
  final TextEditingController _mprice1Ctrl = TextEditingController();
  final TextEditingController _mprice2Ctrl = TextEditingController();
  final TextEditingController _mprice3Ctrl = TextEditingController();
  final TextEditingController _pfprice1Ctrl = TextEditingController();
  final TextEditingController _pfprice2Ctrl = TextEditingController();
  final TextEditingController _pfprice3Ctrl = TextEditingController();
  final TextEditingController _packagenumCtrl = TextEditingController();

  // FocusNode（失焦格式化，对齐 Vue handleBlur）
  final _sellpriceFocusNode = FocusNode();
  final _mprice1FocusNode = FocusNode();
  final _mprice2FocusNode = FocusNode();
  final _mprice3FocusNode = FocusNode();
  final _pfprice1FocusNode = FocusNode();
  final _pfprice2FocusNode = FocusNode();
  final _pfprice3FocusNode = FocusNode();
  final _packagenumFocusNode = FocusNode();

  int _defsizeflag = 0;
  int _stopflag = 1; // 1=启用 0=停用

  bool get _isEdit => widget.specData != null;

  @override
  void initState() {
    super.initState();
    // 注册 blur 监听（对齐 Vue handleBlur，所有价格字段 2 位小数）
    _addBlurListener(_sellpriceFocusNode, _sellpriceCtrl, 2);
    _addBlurListener(_mprice1FocusNode, _mprice1Ctrl, 2);
    _addBlurListener(_mprice2FocusNode, _mprice2Ctrl, 2);
    _addBlurListener(_mprice3FocusNode, _mprice3Ctrl, 2);
    _addBlurListener(_pfprice1FocusNode, _pfprice1Ctrl, 2);
    _addBlurListener(_pfprice2FocusNode, _pfprice2Ctrl, 2);
    _addBlurListener(_pfprice3FocusNode, _pfprice3Ctrl, 2);
    _addBlurListener(_packagenumFocusNode, _packagenumCtrl, 4);
    if (_isEdit) {
      final d = widget.specData!;
      _snameCtrl.text = d['sname']?.toString() ?? '';
      _sbarcodeCtrl.text = d['sbarcode']?.toString() ?? '';
      // 对齐 Vue init：价格字段全部 2 位小数
      final priceKeys = [
        'sellprice',
        'mprice1',
        'mprice2',
        'mprice3',
        'pfprice1',
        'pfprice2',
        'pfprice3'
      ];
      final ctrls = [
        _sellpriceCtrl,
        _mprice1Ctrl,
        _mprice2Ctrl,
        _mprice3Ctrl,
        _pfprice1Ctrl,
        _pfprice2Ctrl,
        _pfprice3Ctrl
      ];
      for (int i = 0; i < priceKeys.length; i++) {
        final v = d[priceKeys[i]];
        ctrls[i].text = v != null && v.toString().isNotEmpty ? MathUtils.formatDecimal(2, v) : '';
      }
      _packagenumCtrl.text = d['packagenum']?.toString() ?? '';
      _defsizeflag = d['defsizeflag'] is int
          ? d['defsizeflag'] as int
          : int.tryParse(d['defsizeflag']?.toString() ?? '0') ?? 0;
      _stopflag = d['stopflag'] is int
          ? d['stopflag'] as int
          : int.tryParse(d['stopflag']?.toString() ?? '1') ?? 1;
    }
  }

  @override
  void dispose() {
    _snameCtrl.dispose();
    _sbarcodeCtrl.dispose();
    _sellpriceCtrl.dispose();
    _mprice1Ctrl.dispose();
    _mprice2Ctrl.dispose();
    _mprice3Ctrl.dispose();
    _pfprice1Ctrl.dispose();
    _pfprice2Ctrl.dispose();
    _pfprice3Ctrl.dispose();
    _packagenumCtrl.dispose();
    for (final fn in [
      _sellpriceFocusNode,
      _mprice1FocusNode,
      _mprice2FocusNode,
      _mprice3FocusNode,
      _pfprice1FocusNode,
      _pfprice2FocusNode,
      _pfprice3FocusNode,
      _packagenumFocusNode,
    ]) {
      fn.dispose();
    }
    super.dispose();
  }

  /// 失焦格式化监听（对齐 Vue handleBlur）
  void _addBlurListener(FocusNode node, TextEditingController ctrl, int col) {
    node.addListener(() {
      if (!node.hasFocus) {
        final value = double.tryParse(ctrl.text) ?? 0;
        final formatted = MathUtils.formatDecimal(col, value < 0 ? 0 : value);
        if (formatted != ctrl.text) ctrl.text = formatted;
      }
    });
  }

  /// 生成规格条码
  void _generateBarcode() {
    if (widget.typeid.isEmpty) {
      Toast.show('请先选择商品分类');
      return;
    }
    request(HttpApi.productBarCodeGeneration, {
      'type': 1,
      'value': widget.typecode,
      'typeid': widget.typeid,
    }).then((result) {
      if (!mounted) return;
      final barcode = result['data']?.toString() ?? '';
      if (barcode.isNotEmpty) {
        setState(() => _sbarcodeCtrl.text = barcode);
      }
    });
  }

  /// 扫描条码
  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code != null && code.isNotEmpty && mounted) {
      setState(() => _sbarcodeCtrl.text = code);
    }
  }

  void _save() {
    if (_sbarcodeCtrl.text.trim().isEmpty) {
      Toast.show('请输入规格条码');
      return;
    }
    if (_snameCtrl.text.trim().isEmpty) {
      Toast.show('请输入规格名称');
      return;
    }

    final inputBarcode = _sbarcodeCtrl.text.trim();

    // 校验规格条码是否与其他规格条码重复（排除自身）
    for (int i = 0; i < widget.sizedata.length; i++) {
      if (i == widget.editIndex) continue;
      if (widget.sizedata[i]['sbarcode']?.toString() == inputBarcode) {
        Toast.show('规格条码已存在');
        return;
      }
    }

    // 校验规格条码是否与包装条码冲突
    for (final pack in widget.packpage) {
      if (pack['sbarcode']?.toString() == inputBarcode) {
        Toast.show('规格条码不能和包装条码相同');
        return;
      }
    }

    // 校验规格条码是否与商品主条码冲突
    if (inputBarcode == widget.barcode && widget.barcode.isNotEmpty) {
      Toast.show('规格条码不能和商品条码相同');
      return;
    }

    final result = <String, dynamic>{
      if (_isEdit) ...widget.specData!,
      'productid': widget.specData?['productid']?.toString() ?? '',
      'packageid': widget.specData?['packageid']?.toString() ?? '',
      'sbarcode': _sbarcodeCtrl.text.trim(),
      'sname': _snameCtrl.text.trim(),
      'sunit': widget.specData?['sunit']?.toString() ?? '',
      'scode': widget.specData?['scode']?.toString() ?? '',
      'size': widget.specData?['size']?.toString() ?? '',
      'inprice': widget.specData?['inprice']?.toString() ?? '',
      'sellprice': _sellpriceCtrl.text.trim(),
      'mprice1': _mprice1Ctrl.text.trim(),
      'mprice2': _mprice2Ctrl.text.trim(),
      'mprice3': _mprice3Ctrl.text.trim(),
      'pfprice1': _pfprice1Ctrl.text.trim(),
      'pfprice2': _pfprice2Ctrl.text.trim(),
      'pfprice3': _pfprice3Ctrl.text.trim(),
      'packagenum': _packagenumCtrl.text.trim(),
      'defsizeflag': _defsizeflag,
      'stopflag': _stopflag,
    };
    Navigator.pop(context, result);
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
        title: Text(
          _isEdit ? '编辑规格' : '新增规格',
          style:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildCard(
              child: Column(children: [
                _buildTextField(_snameCtrl, '规格名称', hint: '请输入规格名称', required: true),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildBarcodeField(),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildNumberField(_sellpriceCtrl, '零售价', focusNode: _sellpriceFocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildNumberField(_mprice1Ctrl, '会员价一', focusNode: _mprice1FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildNumberField(_mprice2Ctrl, '会员价二', focusNode: _mprice2FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildNumberField(_mprice3Ctrl, '会员价三', focusNode: _mprice3FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildNumberField(_pfprice1Ctrl, '批发价一', focusNode: _pfprice1FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildNumberField(_pfprice2Ctrl, '批发价二', focusNode: _pfprice2FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildNumberField(_pfprice3Ctrl, '批发价三', focusNode: _pfprice3FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildNumberField(_packagenumCtrl, '库存扣减', focusNode: _packagenumFocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildSwitchRow(
                    '默认规格', _defsizeflag == 1, (v) => setState(() => _defsizeflag = v ? 1 : 0)),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildSwitchRow(
                    '规格状态', _stopflag == 1, (v) => setState(() => _stopflag = v ? 1 : 0)),
              ]),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _isEdit ? _handleDelete : () => Navigator.pop(context),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(_isEdit ? '删除' : '取消',
                      style: const TextStyle(fontSize: 15, color: Color(0xFF006EFF))),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF006EFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: const Text('确定',
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

  /// 删除规格（对齐小程序 handleDelete，ptype: 7）
  void _handleDelete() {
    request(HttpApi.productCheckDelSize, {
      'productid': widget.specData?['productid']?.toString() ?? '',
      'sname': widget.specData?['sname']?.toString() ?? '',
      'ptype': 7,
    }).then((_) {
      if (!mounted) return;
      Navigator.pop<Map<String, dynamic>>(context, {'_delete': true});
    });
  }

  // ── 通用组件 ──

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: child,
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label,
      {String hint = '请输入', bool required = false, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                if (required)
                  const Positioned(
                    left: -10,
                    top: 0,
                    child: Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFD1D5DB)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          if (suffix != null) suffix,
        ],
      ),
    );
  }

  Widget _buildNumberField(TextEditingController ctrl, String label, {FocusNode? focusNode}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: ctrl,
              focusNode: focusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 80,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Text('规格条码',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                Positioned(
                  left: -10,
                  top: 0,
                  child: Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _sbarcodeCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(
                  hintText: '请输入条码',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6)),
            ),
          ),
          // 生成条码按钮
          GestureDetector(
            onTap: _generateBarcode,
            child: Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF006EFF)),
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: const Text('生成\n条码',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Color(0xFF006EFF), height: 1.3)),
            ),
          ),
          const SizedBox(width: 6),
          // 扫描按钮
          GestureDetector(
            onTap: _scanBarcode,
            child: const Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
          const Spacer(),
          Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF006EFF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ],
      ),
    );
  }
}
