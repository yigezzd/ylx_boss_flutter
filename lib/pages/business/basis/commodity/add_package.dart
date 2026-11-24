import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/select/select_unit.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 包装单位新增/编辑页面
/// 参考小程序 addpackage.vue
class AddPackagePage extends StatefulWidget {
  const AddPackagePage({
    super.key,
    this.editData,
    this.existingBarcodes = const [],
    this.mainBarcode = '',
    this.specBarcodes = const [],
    this.basicUnit = '',
    this.productName = '',
    this.mainPrices = const {},
  });

  /// 编辑模式传入已有数据，null 为新增
  final Map<String, dynamic>? editData;

  /// 已有包装条码列表（用于重复校验，排除自身）
  final List<String> existingBarcodes;

  /// 商品主条码
  final String mainBarcode;

  /// 规格条码列表
  final List<String> specBarcodes;

  /// 商品基本单位（包装单位选择时过滤掉）
  final String basicUnit;

  /// 商品名称（包装名称自动命名用：商品名称（包装单位））
  final String productName;

  /// 主商品价格（inprice/sellprice/mprice1-3/pfprice1-3），包装数量失焦自动补价用
  final Map<String, dynamic> mainPrices;

  @override
  State<AddPackagePage> createState() => _AddPackagePageState();
}

class _AddPackagePageState extends State<AddPackagePage> {
  bool get _isEdit => widget.editData != null;

  final _barcodeCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _numCtrl = TextEditingController();
  final _packnameCtrl = TextEditingController();
  final _inpriceCtrl = TextEditingController();
  final _sellpriceCtrl = TextEditingController();
  final _mprice1Ctrl = TextEditingController();
  final _mprice2Ctrl = TextEditingController();
  final _mprice3Ctrl = TextEditingController();
  final _pfprice1Ctrl = TextEditingController();
  final _pfprice2Ctrl = TextEditingController();
  final _pfprice3Ctrl = TextEditingController();

  /// 价格字段 → 输入控制器（编辑回填、数量失焦自动补价、价格关系校验共用）
  late final Map<String, TextEditingController> _priceCtrls = {
    'inprice': _inpriceCtrl,
    'sellprice': _sellpriceCtrl,
    'mprice1': _mprice1Ctrl,
    'mprice2': _mprice2Ctrl,
    'mprice3': _mprice3Ctrl,
    'pfprice1': _pfprice1Ctrl,
    'pfprice2': _pfprice2Ctrl,
    'pfprice3': _pfprice3Ctrl,
  };

  // FocusNode（失焦格式化，对齐 Vue handleBlur）
  final _numFocusNode = FocusNode();
  final _inpriceFocusNode = FocusNode();
  final _sellpriceFocusNode = FocusNode();
  final _mprice1FocusNode = FocusNode();
  final _mprice2FocusNode = FocusNode();
  final _mprice3FocusNode = FocusNode();
  final _pfprice1FocusNode = FocusNode();
  final _pfprice2FocusNode = FocusNode();
  final _pfprice3FocusNode = FocusNode();

  bool _defsizeflag = false;
  bool _stopflag = false;

  @override
  void initState() {
    super.initState();
    // 注册 blur 监听（对齐 Vue handleBlur）
    // 包装数量单独处理：格式化后按主商品价格 × 数量补齐未填价格（对齐后台 calcPackagePrice）
    _numFocusNode.addListener(() {
      if (!_numFocusNode.hasFocus) _onNumBlur();
    });
    _addBlurListener(_inpriceFocusNode, _inpriceCtrl, 2);
    _addBlurListener(_sellpriceFocusNode, _sellpriceCtrl, 2);
    _addBlurListener(_mprice1FocusNode, _mprice1Ctrl, 2);
    _addBlurListener(_mprice2FocusNode, _mprice2Ctrl, 2);
    _addBlurListener(_mprice3FocusNode, _mprice3Ctrl, 2);
    _addBlurListener(_pfprice1FocusNode, _pfprice1Ctrl, 2);
    _addBlurListener(_pfprice2FocusNode, _pfprice2Ctrl, 2);
    _addBlurListener(_pfprice3FocusNode, _pfprice3Ctrl, 2);
    if (_isEdit) {
      final d = widget.editData!;
      _barcodeCtrl.text = d['sbarcode']?.toString() ?? '';
      _codeCtrl.text = d['scode']?.toString() ?? '';
      _unitCtrl.text = d['sunit']?.toString() ?? '';
      // 对齐 Vue init：packagenum 1位小数，价格字段 2位小数
      _numCtrl.text = d['packagenum'] != null && d['packagenum'].toString().isNotEmpty
          ? MathUtils.formatDecimal(1, d['packagenum'])
          : '';
      _packnameCtrl.text = d['packname']?.toString() ?? '';
      // 对齐 Vue init：价格字段 2 位小数
      _priceCtrls.forEach((key, ctrl) {
        final v = d[key];
        ctrl.text = v != null && v.toString().isNotEmpty ? MathUtils.formatDecimal(2, v) : '';
      });
      _defsizeflag = (d['defsizeflag']?.toString() ?? '0') == '1';
      _stopflag = (d['stopflag']?.toString() ?? '0') == '1';
    }
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _codeCtrl.dispose();
    _unitCtrl.dispose();
    _numCtrl.dispose();
    _packnameCtrl.dispose();
    _inpriceCtrl.dispose();
    _sellpriceCtrl.dispose();
    _mprice1Ctrl.dispose();
    _mprice2Ctrl.dispose();
    _mprice3Ctrl.dispose();
    _pfprice1Ctrl.dispose();
    _pfprice2Ctrl.dispose();
    _pfprice3Ctrl.dispose();
    for (final fn in [
      _numFocusNode,
      _inpriceFocusNode,
      _sellpriceFocusNode,
      _mprice1FocusNode,
      _mprice2FocusNode,
      _mprice3FocusNode,
      _pfprice1FocusNode,
      _pfprice2FocusNode,
      _pfprice3FocusNode,
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

  /// 包装名称自动命名：商品名称（包装单位），与后台 getAutoPackName 一致
  String _getAutoPackName(String unit) {
    final name = widget.productName.trim();
    return (name.isNotEmpty && unit.isNotEmpty) ? '$name（$unit）' : '';
  }

  /// 切换包装单位后回填包装名称：仅名称为空或仍是旧单位的自动名时才覆盖，用户手改过的名称不动
  void _fillPackName(String oldUnit) {
    final current = _packnameCtrl.text.trim();
    if (current.isEmpty || current == _getAutoPackName(oldUnit)) {
      _packnameCtrl.text = _getAutoPackName(_unitCtrl.text.trim());
    }
  }

  /// 写入新单位并回填包装名称
  void _applyUnit(String oldUnit, String newUnit) {
    _unitCtrl.text = newUnit;
    _fillPackName(oldUnit);
  }

  /// 选择包装单位（对齐小程序 selectunitFn / 后台 handleUnitChange）
  Future<void> _selectUnit(Map<String, dynamic> result) async {
    final newUnit = result['name']?.toString() ?? '';
    if (newUnit.isEmpty) return;
    final oldUnit = _unitCtrl.text.trim();
    final rowId = widget.editData?['id']?.toString() ?? '';
    // 与后台 checkDelProductSize 一致：无 id（新增行）直接通过不发请求；
    // 只有已落库的行改单位才校验，sname 传旧单位名
    if (rowId.isEmpty || oldUnit == newUnit) {
      setState(() => _applyUnit(oldUnit, newUnit));
      return;
    }
    final packageid = widget.editData?['packageid']?.toString() ?? '';
    final productid = widget.editData?['productid']?.toString() ?? '';
    try {
      await request(HttpApi.productCheckDelSize, {
        'id': rowId,
        'productid': packageid.isNotEmpty ? packageid : productid,
        'sname': oldUnit,
        'ptype': 6,
      });
    } catch (_) {
      // 校验不通过：保持原单位（对齐后台 catch 回滚）
      return;
    }
    if (!mounted) return;
    setState(() => _applyUnit(oldUnit, newUnit));
  }

  /// 包装数量失焦：格式化数量后按主商品价格 × 包装数量补齐未填的价格（与后台 calcPackagePrice 一致）
  void _onNumBlur() {
    final raw = double.tryParse(_numCtrl.text) ?? 0;
    final formatted = MathUtils.formatDecimal(1, raw < 0 ? 0 : raw);
    if (formatted != _numCtrl.text) _numCtrl.text = formatted;
    final qty = double.tryParse(_numCtrl.text) ?? 0;
    if (!(qty > 0)) return;
    bool changed = false;
    _priceCtrls.forEach((key, ctrl) {
      final basePrice = double.tryParse(widget.mainPrices[key]?.toString() ?? '') ?? 0;
      // 只补空价格，已填写的不覆盖
      if (basePrice > 0 && ctrl.text.trim().isEmpty) {
        ctrl.text = MathUtils.formatDecimal(2, MathUtils.multiply(basePrice, qty));
        changed = true;
      }
    });
    if (changed) setState(() {});
  }

  /// 读取 loginParamResp 配置（对齐 Vue loginParamResp.value）
  Map<String, dynamic> _readLoginCfg() {
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) return jsonDecode(cfgStr) as Map<String, dynamic>;
    } catch (_) {}
    return {};
  }

  void _save() {
    // 对齐 Web（el-input @blur 先于提交触发）：点确定时先执行数量失焦逻辑（格式化 + 自动补价）再校验
    _onNumBlur();
    final barcode = _barcodeCtrl.text.trim();
    final unit = _unitCtrl.text.trim();
    final num = _numCtrl.text.trim();
    final packname = _packnameCtrl.text.trim();
    final inprice = _inpriceCtrl.text.trim();
    final sellprice = _sellpriceCtrl.text.trim();

    if (barcode.isEmpty) {
      Toast.show('请输入包装条码');
      return;
    }
    if (num.isEmpty) {
      Toast.show('请输入包装数量');
      return;
    }
    // 后台 rules.packagenum：包装数量必须大于0
    final qty = double.tryParse(num) ?? 0;
    if (qty <= 0) {
      Toast.show('包装数量必须大于0');
      return;
    }
    if (unit.isEmpty) {
      Toast.show('请选择包装单位');
      return;
    }
    // 后台 rules.packname：有包装单位的行包装名称必填
    if (packname.isEmpty) {
      Toast.show('请输入包装名称');
      return;
    }
    if (inprice.isEmpty) {
      Toast.show('请输入包装进价');
      return;
    }
    if (sellprice.isEmpty) {
      Toast.show('请输入包装售价');
      return;
    }

    // 后台 rules.inprice / rules.sellprice：商品参数不允许零售价小于进价
    final loginCfg = _readLoginCfg();
    final inpriceVal = double.tryParse(inprice) ?? 0;
    final sellpriceVal = double.tryParse(sellprice) ?? 0;
    if (loginCfg['salePriceLessInpriceFlag']?.toString() != '1' && inpriceVal > sellpriceVal) {
      Toast.show('商品参数不允许零售价小于进价，请检查');
      return;
    }
    // 后台 rules.sellprice：商品参数不允许零售价小于会员价1/2/3
    if (loginCfg['allowRetailLessMember']?.toString() != '1') {
      for (int i = 1; i <= 3; i++) {
        final mprice = double.tryParse(_priceCtrls['mprice$i']!.text.trim()) ?? 0;
        if (sellpriceVal < mprice && mprice > 0) {
          Toast.show('商品参数不允许零售价小于会员价$i，请检查');
          return;
        }
      }
    }

    // 条码重复校验
    for (final b in widget.existingBarcodes) {
      if (b == barcode) {
        Toast.show('包装条码已存在');
        return;
      }
    }
    for (final b in widget.specBarcodes) {
      if (b == barcode) {
        Toast.show('包装条码不能和规格条码相同');
        return;
      }
    }
    if (barcode == widget.mainBarcode && widget.mainBarcode.isNotEmpty) {
      Toast.show('包装条码不能和商品条码相同');
      return;
    }

    // 新增态补默认空字段（对齐小程序新增 query）；编辑态以原行数据为底展开，
    // 避免丢失 id 等未展示字段（与小程序整行提交一致）
    final result = <String, dynamic>{
      'id': '',
      'productid': '',
      'packageid': '',
      'sname': '',
      'size': '',
      ...?widget.editData,
      'sbarcode': barcode,
      'scode': _codeCtrl.text.trim(),
      'sunit': unit,
      'packname': packname,
      'packagenum': num,
      'defsizeflag': _defsizeflag ? 1 : 0,
      'stopflag': _stopflag ? 1 : 0,
    };
    _priceCtrls.forEach((key, ctrl) => result[key] = ctrl.text.trim());
    Navigator.pop<Map<String, dynamic>>(context, result);
  }

  /// 删除包装单位（对齐小程序 handleDelete）
  void _handleDelete() {
    request(HttpApi.productCheckDelSize, {
      'productid': widget.editData?['productid']?.toString() ?? '',
      'sname': widget.editData?['sname']?.toString() ?? '',
      'ptype': 6,
    }).then((_) {
      if (!mounted) return;
      // 返回删除标记，区别于普通返回（null）
      Navigator.pop<Map<String, dynamic>>(context, {'_delete': true});
    });
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(
          _isEdit ? '修改包装单位' : '新增包装单位',
          style:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildCard(
              child: Column(children: [
                _buildTextField(_barcodeCtrl, '包装条码',
                    hint: '请输入包装条码',
                    required: true,
                    keyboard: TextInputType.number,
                    suffix: GestureDetector(
                      onTap: _scanBarcode,
                      child: const Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFF666666)),
                    )),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_codeCtrl, '包装自编码', hint: '请输入自编码', keyboard: TextInputType.number),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildUnitSelect(),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_numCtrl, '包装数量',
                    hint: '请输入包装数量', required: true, decimal: true, focusNode: _numFocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_packnameCtrl, '包装名称',
                    hint: '请输入包装名称', required: true, maxLength: 20),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_inpriceCtrl, '包装进价',
                    hint: '请输入包装进价', required: true, decimal: true, focusNode: _inpriceFocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_sellpriceCtrl, '包装售价',
                    hint: '请输入包装售价', required: true, decimal: true, focusNode: _sellpriceFocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_mprice1Ctrl, '会员价一',
                    hint: '请输入会员价一', decimal: true, focusNode: _mprice1FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_mprice2Ctrl, '会员价二',
                    hint: '请输入会员价二', decimal: true, focusNode: _mprice2FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_mprice3Ctrl, '会员价三',
                    hint: '请输入会员价三', decimal: true, focusNode: _mprice3FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_pfprice1Ctrl, '批发价一',
                    hint: '请输入批发价一', decimal: true, focusNode: _pfprice1FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_pfprice2Ctrl, '批发价二',
                    hint: '请输入批发价二', decimal: true, focusNode: _pfprice2FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildTextField(_pfprice3Ctrl, '批发价三',
                    hint: '请输入批发价三', decimal: true, focusNode: _pfprice3FocusNode),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildSwitchRow('默认单位', _defsizeflag, (v) => setState(() => _defsizeflag = v)),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildSwitchRow('单位状态', !_stopflag, (v) => setState(() => _stopflag = !v)),
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
                  child: const Text('确定', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 卡片容器 ──
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

  // ── 扫描条码 ──
  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code != null && code.isNotEmpty && mounted) {
      setState(() => _barcodeCtrl.text = code);
    }
  }

  // ── 文本输入行 ──
  Widget _buildTextField(
    TextEditingController ctrl,
    String label, {
    String hint = '请输入',
    bool required = false,
    bool decimal = false,
    TextInputType? keyboard,
    Widget? suffix,
    FocusNode? focusNode,
    int? maxLength,
  }) {
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
              focusNode: focusNode,
              keyboardType: keyboard ??
                  (decimal ? const TextInputType.numberWithOptions(decimal: true) : null),
              inputFormatters: [
                if (decimal) FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
              ],
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

  // ── 包装单位选择行 ──
  Widget _buildUnitSelect() {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (_) => SelectUnitPage(excludedUnit: widget.basicUnit),
          ),
        );
        if (result != null && mounted) {
          await _selectUnit(result);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 80,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('包装单位',
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
              child: Text(
                _unitCtrl.text.isNotEmpty ? _unitCtrl.text : '请选择',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      _unitCtrl.text.isNotEmpty ? const Color(0xFF111827) : const Color(0xFF006EFF),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  // ── 开关行 ──
  Widget _buildSwitchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Transform.translate(
            offset: const Offset(-8, 0),
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF006EFF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
