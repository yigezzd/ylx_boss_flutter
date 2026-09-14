import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

///
/// 预包装商品详情编辑抽屉
///
/// 业务逻辑参考小程序 prepackPrice/index.vue 详情抽屉：
/// 单位/规格选择、包装条码、包装数量、包装金额、包装折扣联动计算
///
class PrepackDetailSheet extends StatefulWidget {
  const PrepackDetailSheet({super.key, required this.item, required this.storeid});

  final Map<String, dynamic> item;
  final String storeid;

  /// 打开详情抽屉，返回编辑后的商品项（取消返回 null）
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> item,
    required String storeid,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        // 键盘弹起时 builder 会重建，此处读取最新键盘高度，弹窗上移避让
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SizedBox(
            // 键盘过高时压缩弹窗高度，保证不超出屏幕
            height: (screenHeight * 2 / 3).clamp(120.0, screenHeight - bottomInset),
            child: PrepackDetailSheet(item: Map<String, dynamic>.from(item), storeid: storeid),
          ),
        );
      },
    );
  }

  @override
  State<PrepackDetailSheet> createState() => _PrepackDetailSheetState();
}

class _PrepackDetailSheetState extends State<PrepackDetailSheet> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _textColor = Color(0xFF333333);
  static const Color _subTextColor = Color(0xFF7A7A7A);
  static const Color _borderColor = Color(0xFFE6E6E6);

  late final Map<String, dynamic> _item = widget.item;

  final TextEditingController _packBarcodeCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController();

  /// 控制器同步标记（避免程序赋值触发 onChanged 循环计算）
  bool _syncAmount = false;
  bool _syncDiscount = false;
  bool _syncBarcode = false;

  @override
  void initState() {
    super.initState();
    _packBarcodeCtrl.text = _item['packBarcode']?.toString() ?? '';
    _amountCtrl.text = _fmtNum(_item['packAmount']);
    _discountCtrl.text = _fmtNum(_item['packDiscount']);
  }

  @override
  void dispose() {
    _packBarcodeCtrl.dispose();
    _amountCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  // ─── 工具 ───

  double _num(dynamic val) => double.tryParse(val?.toString() ?? '') ?? 0;

  double _round2(double value) => (value * 100).roundToDouble() / 100;

  String _fmtNum(dynamic val) {
    final n = _num(val);
    return n == n.roundToDouble() ? n.toStringAsFixed(2) : n.toString();
  }

  String get _barcode => _item['barcode']?.toString() ?? '';

  double get _sellprice => _num(_item['sellprice']);

  double get _packQty => _num(_item['packQty']);

  /// 同步三个输入框显示（带标记防止触发 onChanged）
  void _syncControllers() {
    _syncBarcode = true;
    _packBarcodeCtrl.text = _item['packBarcode']?.toString() ?? '';
    _syncBarcode = false;
    _syncAmount = true;
    _amountCtrl.text = _fmtNum(_item['packAmount']);
    _syncAmount = false;
    _syncDiscount = true;
    _discountCtrl.text = _fmtNum(_item['packDiscount']);
    _syncDiscount = false;
  }

  // ─── 联动计算（对齐小程序 watch/onAmountBlur/onDiscountBlur）───

  /// 包装数量变化：重算折扣和条码（金额保持不变）
  void _onPackQtyChanged(double qty) {
    setState(() {
      _item['packQty'] = qty;
      if (_barcode.isEmpty) {
        return;
      }
      final amount = _num(_item['packAmount']);
      final total = _sellprice * qty;
      _item['packDiscount'] = total > 0 ? _round2(amount / total * 100) : 100;
      _item['packBarcode'] = generatePackageCode(qty, amount, _barcode);
      _syncControllers();
    });
  }

  /// 包装金额变化：根据金额反算折扣
  void _onAmountChanged(String text) {
    if (_syncAmount) {
      return;
    }
    final amount = double.tryParse(text);
    if (amount == null) {
      return;
    }
    setState(() {
      _item['packAmount'] = amount;
      final total = _sellprice * _packQty;
      _item['packDiscount'] = total > 0 ? _round2(amount / total * 100) : 100;
      _item['packBarcode'] = generatePackageCode(_packQty, amount, _barcode);
      _syncDiscount = true;
      _discountCtrl.text = _fmtNum(_item['packDiscount']);
      _syncDiscount = false;
      _syncBarcode = true;
      _packBarcodeCtrl.text = _item['packBarcode']?.toString() ?? '';
      _syncBarcode = false;
    });
  }

  /// 包装折扣变化：根据折扣反算金额
  void _onDiscountChanged(String text) {
    if (_syncDiscount) {
      return;
    }
    final discount = double.tryParse(text);
    if (discount == null) {
      return;
    }
    setState(() {
      final amount = _round2(discount / 100 * _sellprice * _packQty);
      _item['packDiscount'] = discount;
      _item['packAmount'] = amount;
      _item['packBarcode'] = generatePackageCode(_packQty, amount, _barcode);
      _syncAmount = true;
      _amountCtrl.text = _fmtNum(amount);
      _syncAmount = false;
      _syncBarcode = true;
      _packBarcodeCtrl.text = _item['packBarcode']?.toString() ?? '';
      _syncBarcode = false;
    });
  }

  // ─── 单位/规格选择（对齐小程序 selectUnitFn/selectSizeFn）───

  Future<void> _selectUnit() async {
    final selected = await _ExtendSelectSheet.show(
      context,
      title: '选择单位',
      placeholder: '输入单位/编码',
      listKey: 'packlist',
      nameKey: 'unit',
      altNameKey: 'sunit',
      params: {
        'productid': _item['productid']?.toString() ?? '',
        'bsid': widget.storeid,
        'itemtype': 1,
        'packageflag': 1,
        'cond': '',
        'is_page': 1,
        'page': 1,
        'pagesize': 20,
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _item['unit'] = selected['unit'] ?? _item['unit'];
      _item['unitonlyid'] = selected['unitonlyid'] ?? '';
      _updateBarcodePrice(selected);
      if ((selected['unitonlyid']?.toString() ?? '').isNotEmpty) {
        _item['packQty'] = 1.0;
        _item['qtyFromScan'] = false;
      }
      _recalcFromQty();
    });
  }

  Future<void> _selectSize() async {
    final selected = await _ExtendSelectSheet.show(
      context,
      title: '选择规格',
      placeholder: '输入规格/编码',
      listKey: 'sizelist',
      nameKey: 'size',
      altNameKey: 'sname',
      params: {
        'productid': _item['productid']?.toString() ?? '',
        'bsid': widget.storeid,
        'specflag': 1,
        'cond': '',
        'is_page': 1,
        'page': 1,
        'pagesize': 20,
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _item['size'] = selected['size'] ?? _item['size'];
      _item['sizeonlyid'] = selected['sizeonlyid'] ?? '';
      _updateBarcodePrice(selected);
      if ((selected['sizeonlyid']?.toString() ?? '').isNotEmpty) {
        _item['packQty'] = 1.0;
        _item['qtyFromScan'] = false;
      }
      _recalcFromQty();
    });
  }

  /// 单位/规格切换后更新条码与零售价（sbarcode 优先）
  void _updateBarcodePrice(Map<String, dynamic> e) {
    final sbarcode = e['sbarcode']?.toString() ?? '';
    final barcode = e['barcode']?.toString() ?? '';
    if (sbarcode.isNotEmpty) {
      _item['barcode'] = sbarcode;
    } else if (barcode.isNotEmpty) {
      _item['barcode'] = barcode;
    }
    if (e['sellprice'] != null && e['sellprice'].toString().isNotEmpty) {
      _item['sellprice'] = _num(e['sellprice']);
    }
  }

  /// 按当前数量重算包装金额/折扣/条码（单位/规格切换时用）
  void _recalcFromQty() {
    final qty = _packQty;
    final amount = _round2(_sellprice * qty);
    _item['packAmount'] = amount;
    final total = _sellprice * qty;
    _item['packDiscount'] = total > 0 ? _round2(amount / total * 100) : 100;
    _item['packBarcode'] = generatePackageCode(qty, amount, _barcode);
    _syncControllers();
  }

  // ─── 页面构建 ───

  @override
  Widget build(BuildContext context) {
    final name = _item['name']?.toString() ?? '';
    final size = _item['size']?.toString() ?? '';
    final qtyFromScan = _item['qtyFromScan'] == true;

    return Column(
      children: [
        // 头部（对齐小程序 drawer-header）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Text('商品详情',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: _subTextColor),
                ),
              ),
            ],
          ),
        ),
        // 内容区
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // 商品信息区
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: _borderColor),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '商品名称：$name${size.isNotEmpty ? '（$size）' : ''}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: _textColor),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text('条码：$_barcode',
                                style: const TextStyle(fontSize: 13, color: _subTextColor)),
                          ),
                          Text('零售价：${MathUtils.formatDecimal(2, _item['sellprice'] ?? '0')}',
                              style: const TextStyle(fontSize: 13, color: _subTextColor)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 单位选择
                _buildSelectRow('单位', _item['unit']?.toString() ?? '', _selectUnit),
                // 规格选择（多规格商品才显示）
                if (_item['specflag']?.toString() == '1')
                  _buildSelectRow('规格', _item['size']?.toString() ?? '', _selectSize),
                // 包装条码
                _buildFormRow(
                  '包装条码',
                  TextField(
                    controller: _packBarcodeCtrl,
                    textAlign: TextAlign.right,
                    decoration: _inputDecoration(),
                    style: const TextStyle(fontSize: 14, color: _textColor),
                    onChanged: (val) {
                      if (_syncBarcode) {
                        return;
                      }
                      _item['packBarcode'] = val;
                    },
                  ),
                ),
                // 包装数量（扫码获取的数量为只读）
                _buildFormRow(
                  '包装数量',
                  qtyFromScan
                      ? Text(
                          MathUtils.formatDecimal(2, _item['packQty'] ?? 0),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: _textColor),
                        )
                      : _DoubleStepper(
                          value: _packQty,
                          min: 0,
                          onChanged: _onPackQtyChanged,
                        ),
                ),
                // 包装金额
                _buildFormRow(
                  '包装金额',
                  TextField(
                    controller: _amountCtrl,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration(),
                    style: const TextStyle(fontSize: 14, color: _textColor),
                    onChanged: _onAmountChanged,
                  ),
                ),
                // 包装折扣
                _buildFormRow(
                  '包装折扣(%)',
                  TextField(
                    controller: _discountCtrl,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration(),
                    style: const TextStyle(fontSize: 14, color: _textColor),
                    onChanged: _onDiscountChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 底部按钮
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: _primaryColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: const Text('取消', style: TextStyle(fontSize: 15, color: _primaryColor)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, _item),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _primaryColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: const Text('确定',
                        style: TextStyle(
                            fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration() {
    return const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: 8),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );
  }

  /// 表单行（label 固定宽 + 右侧内容）
  Widget _buildFormRow(String label, Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 14, color: _textColor)),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: child),
          ),
        ],
      ),
    );
  }

  /// 单位/规格选择行
  Widget _buildSelectRow(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(fontSize: 14, color: _textColor)),
            ),
            const Spacer(),
            Text(
              value.isEmpty ? '请选择' : value,
              style: TextStyle(fontSize: 13, color: value.isEmpty ? _subTextColor : _textColor),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFB7B7B7)),
          ],
        ),
      ),
    );
  }
}

/// 数量步进器（包装数量，支持小数显示，最小 0）
class _DoubleStepper extends StatelessWidget {
  const _DoubleStepper({
    required this.value,
    required this.min,
    required this.onChanged,
  });

  final double value;
  final double min;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBtn(
          icon: Icons.remove,
          enabled: value > min,
          onTap: () => onChanged(value <= min + 1 ? min : value - 1),
        ),
        Container(
          width: 48,
          alignment: Alignment.center,
          child: Text(
            MathUtils.formatDecimal(2, value),
            style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
          ),
        ),
        _buildBtn(
          icon: Icons.add,
          enabled: true,
          onTap: () => onChanged(value + 1),
        ),
      ],
    );
  }

  Widget _buildBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? const Color(0xFFDEDEDE) : const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
        ),
      ),
    );
  }
}

///
/// 单位/规格选择弹窗（对齐小程序 selectCom：搜索 + 列表选择）
///
class _ExtendSelectSheet extends StatefulWidget {
  const _ExtendSelectSheet({
    required this.title,
    required this.placeholder,
    required this.listKey,
    required this.nameKey,
    required this.altNameKey,
    required this.params,
  });

  final String title;
  final String placeholder;

  /// 响应数据列表 key：单位=packlist，规格=sizelist
  final String listKey;

  /// 显示名称字段：单位=unit，规格=size
  final String nameKey;

  /// 名称兜底字段（对齐小程序）：单位=sunit，规格=sname
  final String altNameKey;
  final Map<String, dynamic> params;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String title,
    required String placeholder,
    required String listKey,
    required String nameKey,
    required String altNameKey,
    required Map<String, dynamic> params,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: _ExtendSelectSheet(
          title: title,
          placeholder: placeholder,
          listKey: listKey,
          nameKey: nameKey,
          altNameKey: altNameKey,
          params: params,
        ),
      ),
    );
  }

  @override
  State<_ExtendSelectSheet> createState() => _ExtendSelectSheetState();
}

class _ExtendSelectSheetState extends State<_ExtendSelectSheet> {
  final TextEditingController _keywordCtrl = TextEditingController();

  List<Map<String, dynamic>> _allList = [];
  List<Map<String, dynamic>> _filterList = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await request(HttpApi.productGetExtendList, widget.params);
      if (!mounted) {
        return;
      }
      final data = res['data'];
      final rawList = (data is Map<String, dynamic> ? data[widget.listKey] : null) as List? ?? [];
      // 对齐小程序 selectCom：名称字段兜底 unit=unit||sunit，size=size||sname
      _allList = rawList.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (widget.altNameKey.isNotEmpty && (m[widget.nameKey]?.toString() ?? '').isEmpty) {
          m[widget.nameKey] = m[widget.altNameKey] ?? '';
        }
        return m;
      }).toList();
      _filterList = _allList;
      if (_allList.isEmpty) {
        Toast.show('无可选项');
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 本地关键字过滤（对齐小程序 selfSearch：名称/编码）
  void _onKeywordChanged(String keyword) {
    setState(() {
      if (keyword.isEmpty) {
        _filterList = _allList;
      } else {
        _filterList = _allList.where((e) {
          final name = e[widget.nameKey]?.toString() ?? '';
          final code = e['code']?.toString() ?? '';
          return name.contains(keyword) || code.contains(keyword);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 标题 + 关闭
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: Color(0xFF7A7A7A)),
                ),
              ),
            ],
          ),
        ),
        // 搜索框
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _keywordCtrl,
              onChanged: _onKeywordChanged,
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 列表
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
              : _filterList.isEmpty
                  ? const Center(
                      child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
                    )
                  : ListView.builder(
                      cacheExtent: 800,
                      itemCount: _filterList.length,
                      itemBuilder: (ctx, i) {
                        final e = _filterList[i];
                        final name = e[widget.nameKey]?.toString() ?? '';
                        return RepaintBoundary(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context, e),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Color(0xFFF0F0F0)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(name,
                                        style: const TextStyle(
                                            fontSize: 14, color: Color(0xFF333333))),
                                  ),
                                  const Icon(Icons.chevron_right,
                                      size: 16, color: Color(0xFFB7B7B7)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
