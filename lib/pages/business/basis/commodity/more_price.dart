import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/util/math_utils.dart';

/// 更多价格页面（对齐小程序 moreprice.vue）
/// 包含：会员价1/2/3、批发价1/2/3
class MorePricePage extends StatefulWidget {
  const MorePricePage({
    super.key,
    required this.mprice1,
    required this.mprice2,
    required this.mprice3,
    required this.pfprice1,
    required this.pfprice2,
    required this.pfprice3,
    this.readOnly = false,
  });
  final String mprice1;
  final String mprice2;
  final String mprice3;
  final String pfprice1;
  final String pfprice2;
  final String pfprice3;
  final bool readOnly;

  @override
  State<MorePricePage> createState() => _MorePricePageState();
}

class _MorePricePageState extends State<MorePricePage> {
  late final TextEditingController _mprice1Controller;
  late final TextEditingController _mprice2Controller;
  late final TextEditingController _mprice3Controller;
  late final TextEditingController _pfprice1Controller;
  late final TextEditingController _pfprice2Controller;
  late final TextEditingController _pfprice3Controller;

  final FocusNode _mprice1FocusNode = FocusNode();
  final FocusNode _mprice2FocusNode = FocusNode();
  final FocusNode _mprice3FocusNode = FocusNode();
  final FocusNode _pfprice1FocusNode = FocusNode();
  final FocusNode _pfprice2FocusNode = FocusNode();
  final FocusNode _pfprice3FocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _mprice1Controller = TextEditingController(text: widget.mprice1);
    _mprice2Controller = TextEditingController(text: widget.mprice2);
    _mprice3Controller = TextEditingController(text: widget.mprice3);
    _pfprice1Controller = TextEditingController(text: widget.pfprice1);
    _pfprice2Controller = TextEditingController(text: widget.pfprice2);
    _pfprice3Controller = TextEditingController(text: widget.pfprice3);

    // 失焦格式化（对齐 Vue priceBlur）
    _addBlurListener(_mprice1FocusNode, _mprice1Controller);
    _addBlurListener(_mprice2FocusNode, _mprice2Controller);
    _addBlurListener(_mprice3FocusNode, _mprice3Controller);
    _addBlurListener(_pfprice1FocusNode, _pfprice1Controller);
    _addBlurListener(_pfprice2FocusNode, _pfprice2Controller);
    _addBlurListener(_pfprice3FocusNode, _pfprice3Controller);
  }

  void _addBlurListener(FocusNode node, TextEditingController ctrl) {
    node.addListener(() {
      if (!node.hasFocus) {
        final value = double.tryParse(ctrl.text) ?? 0;
        final formatted = MathUtils.formatDecimal(2, value);
        if (formatted != ctrl.text) ctrl.text = formatted;
      }
    });
  }

  @override
  void dispose() {
    _mprice1Controller.dispose();
    _mprice2Controller.dispose();
    _mprice3Controller.dispose();
    _pfprice1Controller.dispose();
    _pfprice2Controller.dispose();
    _pfprice3Controller.dispose();
    _mprice1FocusNode.dispose();
    _mprice2FocusNode.dispose();
    _mprice3FocusNode.dispose();
    _pfprice1FocusNode.dispose();
    _pfprice2FocusNode.dispose();
    _pfprice3FocusNode.dispose();
    super.dispose();
  }

  void _onConfirm() {
    Navigator.pop(context, {
      'mprice1': _mprice1Controller.text,
      'mprice2': _mprice2Controller.text,
      'mprice3': _mprice3Controller.text,
      'pfprice1': _pfprice1Controller.text,
      'pfprice2': _pfprice2Controller.text,
      'pfprice3': _pfprice3Controller.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    const kDivider = Divider(height: 1, thickness: 1, color: Color(0xFFE6E6E6));
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
        title: const Text(
          '更多价格',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
          ),
          child: Column(
            children: [
              _buildPriceField(
                  controller: _mprice1Controller,
                  label: '会员价一',
                  hint: '请输入会员价一',
                  focusNode: _mprice1FocusNode),
              kDivider,
              _buildPriceField(
                  controller: _mprice2Controller,
                  label: '会员价二',
                  hint: '请输入会员价二',
                  focusNode: _mprice2FocusNode),
              kDivider,
              _buildPriceField(
                  controller: _mprice3Controller,
                  label: '会员价三',
                  hint: '请输入会员价三',
                  focusNode: _mprice3FocusNode),
              kDivider,
              _buildPriceField(
                  controller: _pfprice1Controller,
                  label: '批发价一',
                  hint: '请输入批发价一',
                  focusNode: _pfprice1FocusNode),
              kDivider,
              _buildPriceField(
                  controller: _pfprice2Controller,
                  label: '批发价二',
                  hint: '请输入批发价二',
                  focusNode: _pfprice2FocusNode),
              kDivider,
              _buildPriceField(
                  controller: _pfprice3Controller,
                  label: '批发价三',
                  hint: '请输入批发价三',
                  focusNode: _pfprice3FocusNode),
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.readOnly
          ? null
          : Container(
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
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFF006EFF)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text('取消',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF006EFF))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _onConfirm,
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFF006EFF),
                          borderRadius: BorderRadius.circular(8),
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

  /// 价格输入行（label + 输入框）
  Widget _buildPriceField({
    required TextEditingController controller,
    required String label,
    String hint = '请输入',
    FocusNode? focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              readOnly: widget.readOnly,
              enabled: !widget.readOnly,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              style: TextStyle(
                  fontSize: 14,
                  color: widget.readOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
