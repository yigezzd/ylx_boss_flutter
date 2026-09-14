import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_location.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// WMS 收货托盘编辑页（对齐 Vue wms/receiveTakList/palletEdit.vue）
///
/// 确认后通过 Navigator.pop 回传：
/// `{palletcode, locationcode, locationid, items:[{productid, unitonlyid,
/// sizeonlyid, detailonlyid, productname, size, barcode, qty, receiptqty,
/// batchno, birthdate, validdate, validflag, validday}]}`
class WmsReceivePalletEditPage extends StatefulWidget {
  const WmsReceivePalletEditPage({
    super.key,
    required this.billInfo,
    required this.palletcode,
    required this.locationcode,
    required this.locationid,
    required this.items,
    required this.palletLocationMap,
    required this.billProductList,
    required this.storeid,
  });

  final Map<String, dynamic> billInfo;
  final String palletcode;
  final String locationcode;
  final String locationid;
  final List<Map<String, dynamic>> items;

  /// 托盘码→货位号映射（用于自动带出和校验）
  final Map<String, Map<String, String>> palletLocationMap;

  /// 单据商品列表（用于扫码添加时校验商品是否属于当前单据）
  final List<Map<String, dynamic>> billProductList;
  final String storeid;

  @override
  State<WmsReceivePalletEditPage> createState() => _WmsReceivePalletEditPageState();
}

class _WmsReceivePalletEditPageState extends State<WmsReceivePalletEditPage> {
  bool get _disabled => widget.billInfo['signflag']?.toString() == '1';

  /// 记录进入时的原始托盘码（用于校验时排除自身）
  late final String _originalPalletcode = widget.palletcode;

  String _locationcode = '';
  String _locationid = '';
  final TextEditingController _palletController = TextEditingController();

  List<Map<String, dynamic>> _items = [];

  /// 删除模式
  bool _isDel = false;

  @override
  void initState() {
    super.initState();
    _palletController.text = widget.palletcode;
    _locationcode = widget.locationcode;
    _locationid = widget.locationid;
    // 兼容 name 字段（对齐 Vue onLoad items 处理）
    _items = widget.items
        .map((i) => {
              ...i,
              'productname': (i['productname']?.toString().isNotEmpty ?? false)
                  ? i['productname']
                  : (i['name'] ?? ''),
              'checked': false,
            })
        .toList();
  }

  @override
  void dispose() {
    _palletController.dispose();
    super.dispose();
  }

  String get _palletcode => _palletController.text.trim();

  int get _checkedNum => _items.where((i) => i['checked'] == true).length;

  // ────────────────────── 货位号 ──────────────────────

  Future<void> _openLocationSelect() async {
    final result = await SelectLocationPage.show(
      context,
      initialSelectedId: _locationid.isNotEmpty ? _locationid : null,
      zonetype: 3,
    );
    if (result == null || !mounted) return;
    setState(() {
      _locationcode = result['locationcode']?.toString() ?? '';
      _locationid = result['locationid']?.toString() ?? '';
    });
  }

  // ────────────────────── 托盘码 ──────────────────────

  Future<void> _scanPallet() async {
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code == null || !mounted) return;
    final scancode = code.toString().trim();
    if (scancode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    setState(() {
      _palletController.text = scancode;
    });
    _tryAutoFillLocation();
  }

  /// 托盘码变更时自动带出货位号（对齐 Vue tryAutoFillLocation）
  void _tryAutoFillLocation() {
    final pc = _palletcode;
    if (pc.isEmpty) return;
    final match = widget.palletLocationMap[pc];
    if ((match?['locationcode'] ?? '').isNotEmpty) {
      setState(() {
        _locationcode = match!['locationcode']!;
        _locationid = match['locationid'] ?? '';
      });
    }
  }

  // ────────────────────── 删除模式 ──────────────────────

  void _showDelRow() {
    if (_items.isEmpty) return;
    setState(() => _isDel = true);
  }

  void _cancelDel() {
    setState(() {
      _isDel = false;
      for (final i in _items) {
        i['checked'] = false;
      }
    });
  }

  Future<void> _confirmDel() async {
    if (_checkedNum == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: Text('确定删除$_checkedNum条商品吗？',
            style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _items = _items.where((i) => i['checked'] != true).toList();
      _isDel = false;
    });
  }

  // ────────────────────── 扫码添加商品 ──────────────────────

  /// 扫码添加商品（仅允许添加当前单据中已存在的商品，对齐 Vue addProduct）
  Future<void> _addProduct() async {
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code == null || !mounted) return;
    final scancode = code.toString().trim();
    if (scancode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    try {
      final result = await request(HttpApi.productGetList, {
        'scancode': scancode,
        'is_page': 1,
        'page': 1,
        'pagesize': 10,
        'storeid': widget.storeid,
      });
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isEmpty) {
        Toast.show('未查询到该商品');
        return;
      }
      final scanned = Map<String, dynamic>.from(list[0] as Map);
      // 校验：扫码商品必须存在于当前单据的商品列表中
      final billPro = widget.billProductList.firstWhere(
        (p) => p['productid']?.toString() == scanned['productid']?.toString(),
        orElse: () => <String, dynamic>{},
      );
      if (billPro.isEmpty) {
        Toast.show('该商品不在当前收货单中，无法添加');
        return;
      }
      // 同一商品允许多批次录入，每次扫码新增一条记录并打开编辑填写批次信息
      final newItem = <String, dynamic>{
        ...scanned,
        'productid': billPro['productid'],
        'productname': (billPro['productname']?.toString().isNotEmpty ?? false)
            ? billPro['productname']
            : (scanned['productname'] ?? scanned['name'] ?? ''),
        'size': billPro['size'] ?? scanned['size'],
        'barcode': (billPro['barcode']?.toString().isNotEmpty ?? false)
            ? billPro['barcode']
            : (scanned['barcode'] ?? scanned['code'] ?? ''),
        'orderqty': billPro['orderqty'] ?? 0,
        'receiptqty': 1, // 批次级，初始与 qty 保持一致
        'validflag': billPro['validflag'] ?? 0,
        'validday': billPro['validday'] ?? 0,
        'palletstock': billPro['palletstock'] ?? 0,
        'palletbase': billPro['palletbase'] ?? 0,
        'palletlayer': billPro['palletlayer'] ?? 0,
        'qty': 1,
        'batchno': '',
        'birthdate': '',
        'validdate': '',
        'checked': false,
        '_isNew': true, // 标记为新增未完成项，取消时自动清理
      };
      setState(() => _items.add(newItem));
      if (!mounted) return;
      _openProDetail(_items.length - 1);
    } catch (_) {}
  }

  // ────────────────────── 商品编辑弹窗（对齐 Vue proDetails） ──────────────────────

  /// 点击商品行打开编辑弹窗
  Future<void> _openProDetail(int idx) async {
    if (idx < 0 || idx >= _items.length) return;
    final item = _items[idx];
    // 从 billProductList 补充产品级订货数（对齐 Vue openProDetail）
    final billPro = widget.billProductList.firstWhere(
      (p) => p['productid']?.toString() == item['productid']?.toString(),
      orElse: () => <String, dynamic>{},
    );
    final orderqty = num.tryParse(
            (billPro.isNotEmpty ? billPro['orderqty'] : item['orderqty'])?.toString() ?? '') ??
        num.tryParse(item['orderqty']?.toString() ?? '') ??
        0;
    final edited = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        // 键盘弹起时弹窗整体上移，避免批次号输入框被键盘遮挡
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ProEditSheet(
          item: Map<String, dynamic>.from(item),
          orderqty: orderqty,
          disabled: _disabled,
        ),
      ),
    );
    if (!mounted) return;
    if (idx < 0 || idx >= _items.length) return;
    if (edited != null) {
      // 确认：合并编辑结果（对齐 Vue proDetailConfirm）
      setState(() {
        _items[idx] = {..._items[idx], ...edited};
      });
    } else if (_items[idx]['_isNew'] == true) {
      // 取消：清理未完成的新增项（对齐 Vue proDetailCancel）
      setState(() {
        _items.removeAt(idx);
      });
    }
  }

  // ────────────────────── 确认 ──────────────────────

  /// 确认保存（对齐 Vue confirm 校验链）
  void _confirm() {
    if (_palletcode.isEmpty) {
      Toast.show('请填写托盘码');
      return;
    }
    // 校验：保质期商品批次号必填
    final invalidBatch = _items.firstWhere(
      (i) => i['validflag']?.toString() == '1' && (i['batchno']?.toString() ?? '').isEmpty,
      orElse: () => <String, dynamic>{},
    );
    if (invalidBatch.isNotEmpty) {
      Toast.show('商品"${invalidBatch['productname']}"为保质期商品，批次号必填');
      return;
    }
    // 校验：保质期商品生产日期必填
    final invalidBirth = _items.firstWhere(
      (i) => i['validflag']?.toString() == '1' && (i['birthdate']?.toString() ?? '').isEmpty,
      orElse: () => <String, dynamic>{},
    );
    if (invalidBirth.isNotEmpty) {
      Toast.show('商品"${invalidBirth['productname']}"为保质期商品，生产日期必填');
      return;
    }
    // 校验：同一托盘码不能关联不同货位号（排除当前编辑的原始托盘码）
    final pc = _palletcode;
    if (pc != _originalPalletcode) {
      final existing = widget.palletLocationMap[pc];
      if ((existing?['locationcode'] ?? '').isNotEmpty &&
          _locationcode.isNotEmpty &&
          existing!['locationcode'] != _locationcode) {
        Toast.show('托盘码 $pc 已绑定货位号 ${existing['locationcode']}，不能关联不同货位');
        return;
      }
    }

    // 回传托盘完整数据给父页，由父页统一写回 detaillist
    Navigator.pop(context, {
      'palletcode': pc,
      'locationcode': _locationcode,
      'locationid': _locationid,
      'items': _items
          .map((i) => {
                'productid': i['productid'],
                'unitonlyid': i['unitonlyid'],
                'sizeonlyid': i['sizeonlyid'],
                'detailonlyid': i['detailonlyid'],
                'productname': i['productname'],
                'size': i['size'],
                'barcode': (i['barcode']?.toString().isNotEmpty ?? false)
                    ? i['barcode']
                    : (i['code'] ?? ''),
                'qty': i['qty'] ?? 0,
                'receiptqty': i['receiptqty'] ?? 0,
                'batchno': i['batchno'] ?? '',
                'birthdate': i['birthdate'] ?? '',
                'validdate': i['validdate'] ?? '',
                'validflag': i['validflag'] ?? 0,
                'validday': i['validday'] ?? 0,
              })
          .toList(),
    });
  }

  // ────────────────────── UI ──────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '收货托盘详情',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              cacheExtent: 800,
              children: [
                // ── 托盘基本信息 ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
                  ),
                  child: Column(
                    children: [
                      // 收货暂存-货位号
                      _fieldRow(
                        label: '收货暂存-货位号',
                        onTap: _disabled ? null : _openLocationSelect,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _locationcode,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                            ),
                            if (!_disabled)
                              const Icon(Icons.arrow_drop_down, size: 20, color: Color(0xFF999999)),
                          ],
                        ),
                      ),
                      // 托盘码
                      _fieldRow(
                        label: '托盘码',
                        required: true,
                        child: _disabled
                            ? Text(
                                _palletcode,
                                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 130,
                                    child: TextField(
                                      controller: _palletController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.right,
                                      onSubmitted: (_) => _tryAutoFillLocation(),
                                      onEditingComplete: () {
                                        FocusScope.of(context).unfocus();
                                        _tryAutoFillLocation();
                                      },
                                      decoration: const InputDecoration(
                                        hintText: '请输入',
                                        hintStyle:
                                            TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      style:
                                          const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: _scanPallet,
                                    child: const Icon(Icons.qr_code_scanner,
                                        size: 20, color: Color(0xFF006EFF)),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // ── 商品信息区 ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '商品信息',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const Spacer(),
                          if (!_disabled) ...[
                            GestureDetector(
                              onTap: _showDelRow,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '删除',
                                  style: TextStyle(fontSize: 14, color: Color(0xFFD54B5A)),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _addProduct,
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.qr_code_scanner, size: 16, color: Color(0xFF006EFF)),
                                  SizedBox(width: 4),
                                  Text(
                                    '添加商品',
                                    style: TextStyle(fontSize: 14, color: Color(0xFF006EFF)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text(
                              '暂无商品',
                              style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < _items.length; i++) _buildProductRow(i),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── 底部按钮 ──
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _bottomBtn(
                    label: '取消',
                    outlined: true,
                    onTap: _isDel ? _cancelDel : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                if (_isDel)
                  Expanded(
                    child: _bottomBtn(label: '删除', onTap: _confirmDel),
                  )
                else if (!_disabled)
                  Expanded(
                    child: _bottomBtn(label: '确认', onTap: _confirm),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 商品行
  Widget _buildProductRow(int idx) {
    final item = _items[idx];
    final productname = item['productname']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    final batchno = item['batchno']?.toString() ?? '';
    final barcode = (item['barcode']?.toString().isNotEmpty ?? false)
        ? item['barcode'].toString()
        : (item['code']?.toString() ?? '');
    final birthdate = (item['birthdate']?.toString() ?? '').split(' ').first;
    final validdate = (item['validdate']?.toString() ?? '').split(' ').first;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isDel) {
          setState(() => item['checked'] = item['checked'] != true);
        } else {
          _openProDetail(idx);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border:
              idx > 0 ? const Border(top: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isDel)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Icon(
                  item['checked'] == true ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color:
                      item['checked'] == true ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$productname${size.isNotEmpty ? '（$size）' : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '批次：$batchno',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          barcode,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ),
                      Text(
                        '收货数：${MathUtils.formatDecimal(1, item['receiptqty'] ?? 0)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '生产日期：$birthdate',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ),
                      Text(
                        '有效日期：$validdate',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow({
    required String label,
    required Widget child,
    bool required = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (required)
                  const Text('*', style: TextStyle(fontSize: 13, color: Color(0xFFD54B5A))),
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                ),
              ],
            ),
            const Spacer(),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }

  Widget _bottomBtn({
    required String label,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: outlined ? Colors.white : const Color(0xFF006EFF),
          border: outlined ? Border.all(color: const Color(0xFFCCCCCC)) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: outlined ? const Color(0xFF333333) : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 商品编辑弹窗（对齐 Vue proDetails：qty/batchno/birthdate/validdate）
class _ProEditSheet extends StatefulWidget {
  const _ProEditSheet({
    required this.item,
    required this.orderqty,
    required this.disabled,
  });

  final Map<String, dynamic> item;
  final num orderqty;
  final bool disabled;

  @override
  State<_ProEditSheet> createState() => _ProEditSheetState();
}

class _ProEditSheetState extends State<_ProEditSheet> {
  late final Map<String, dynamic> _item = widget.item;
  late final TextEditingController _batchController =
      TextEditingController(text: _item['batchno']?.toString() ?? '');

  num get _qty => num.tryParse(_item['qty']?.toString() ?? '') ?? 0;

  bool get _validflag => _item['validflag']?.toString() == '1';

  @override
  void dispose() {
    _batchController.dispose();
    super.dispose();
  }

  /// 数量限制：不能超过订货数（对齐 Vue writeData）
  void _onQtyChange(num newVal) {
    num v = newVal;
    if (v > widget.orderqty) {
      v = widget.orderqty;
      Toast.show('数量不能超过订货数 ${MathUtils.formatDecimal(1, widget.orderqty)}');
    }
    if (v < 0) v = 0;
    setState(() => _item['qty'] = v);
  }

  Future<void> _pickDate({required bool isBirthdate}) async {
    final key = isBirthdate ? 'birthdate' : 'validdate';
    final current = _item[key]?.toString() ?? '';
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isBirthdate ? '选择生产日期' : '选择有效日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) return;
    final dateStr =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      _item[key] = dateStr;
      // 保质期商品且有 validday，自动计算有效日期（对齐 Vue proDetailConfirm）
      if (isBirthdate && _validflag) {
        final validday = num.tryParse(_item['validday']?.toString() ?? '') ?? 0;
        if (validday > 0) {
          final v = picked.add(Duration(days: validday.toInt()));
          _item['validdate'] =
              '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
        }
      }
    });
  }

  /// 确定前校验（对齐 Vue validateProDetails）
  bool _validate() {
    if (_validflag) {
      if (_batchController.text.trim().isEmpty) {
        Toast.show('商品"${_item['productname']}"为保质期商品，批次号必填');
        return false;
      }
      if ((_item['birthdate']?.toString() ?? '').isEmpty) {
        Toast.show('商品"${_item['productname']}"为保质期商品，生产日期必填');
        return false;
      }
    }
    return true;
  }

  /// 确认（对齐 Vue proDetailConfirm）
  void _confirm() {
    if (!_validate()) return;
    final edited = {
      ..._item,
      'qty': _qty,
      'receiptqty': _qty, // 批次级 receiptqty 始终与 qty 保持一致
      'batchno': _batchController.text.trim(),
    };
    edited.remove('_isNew'); // 确认后移除新增标记
    Navigator.pop(context, edited);
  }

  @override
  Widget build(BuildContext context) {
    final productname = _item['productname']?.toString() ?? '';
    final size = _item['size']?.toString() ?? '';
    final barcode = (_item['barcode']?.toString().isNotEmpty ?? false)
        ? _item['barcode'].toString()
        : (_item['code']?.toString() ?? '');

    return ConstrainedBox(
      // 与 chain 弹窗模式一致：限制弹窗最大高度；键盘弹起时可用高度被压缩，
      // 字段区通过 Flexible 滚动，避免 PDA 小屏 + 软键盘下溢出
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  const Expanded(
                    child: Text(
                      '绑定商品',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$productname${size.isNotEmpty ? '（$size）' : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '条码：$barcode',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ),
                      Text(
                        '订货数：${MathUtils.formatDecimal(1, widget.orderqty)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // 数量
                    _sheetRow(
                      label: '数量',
                      required: true,
                      child: widget.disabled
                          ? Text(
                              MathUtils.formatDecimal(1, _qty),
                              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                            )
                          : _SheetStepper(
                              value: _qty,
                              min: 0,
                              max: widget.orderqty,
                              onChanged: _onQtyChange,
                            ),
                    ),
                    // 批次号
                    _sheetRow(
                      label: '批次号',
                      required: _validflag,
                      child: widget.disabled
                          ? Text(
                              _batchController.text,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                            )
                          : SizedBox(
                              width: 160,
                              child: TextField(
                                controller: _batchController,
                                textAlign: TextAlign.right,
                                decoration: const InputDecoration(
                                  hintText: '请输入',
                                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                              ),
                            ),
                    ),
                    // 生产日期
                    _sheetRow(
                      label: '生产日期',
                      required: _validflag,
                      onTap: widget.disabled ? null : () => _pickDate(isBirthdate: true),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (_item['birthdate']?.toString() ?? '').isNotEmpty
                                ? _item['birthdate'].toString()
                                : (widget.disabled ? '' : '请选择'),
                            style: TextStyle(
                              fontSize: 14,
                              color: (_item['birthdate']?.toString() ?? '').isNotEmpty
                                  ? const Color(0xFF333333)
                                  : const Color(0xFF8B8B8B),
                            ),
                          ),
                          if (!widget.disabled)
                            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB7B7B7)),
                        ],
                      ),
                    ),
                    // 有效日期
                    _sheetRow(
                      label: '有效日期',
                      onTap: widget.disabled ? null : () => _pickDate(isBirthdate: false),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (_item['validdate']?.toString() ?? '').isNotEmpty
                                ? _item['validdate'].toString()
                                : (_validflag ? '由生产日期自动算出' : (widget.disabled ? '' : '请选择')),
                            style: TextStyle(
                              fontSize: (_item['validdate']?.toString() ?? '').isNotEmpty ? 14 : 12,
                              color: (_item['validdate']?.toString() ?? '').isNotEmpty
                                  ? const Color(0xFF333333)
                                  : const Color(0xFF8B8B8B),
                            ),
                          ),
                          if (!widget.disabled)
                            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB7B7B7)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部按钮
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFCCCCCC)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '取消',
                          style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
                        ),
                      ),
                    ),
                  ),
                  if (!widget.disabled) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _confirm,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF006EFF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '确认',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetRow({
    required String label,
    required Widget child,
    bool required = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (required)
                  const Text('*', style: TextStyle(fontSize: 13, color: Color(0xFFD54B5A))),
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                ),
              ],
            ),
            const Spacer(),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// 数量步进器
class _SheetStepper extends StatelessWidget {
  const _SheetStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final num value;
  final num min;
  final num max;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: value > min ? () => onChanged((value - 1).clamp(min, max)) : null,
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
              color: value > min ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
            ),
          ),
        ),
        Container(
          width: 64,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDEDEDE)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            MathUtils.formatDecimal(1, value),
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
          ),
        ),
        GestureDetector(
          onTap: value < max ? () => onChanged((value + 1).clamp(min, max)) : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFDEDEDE)),
            ),
            child: Icon(
              Icons.add,
              size: 16,
              color: value < max ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
            ),
          ),
        ),
      ],
    );
  }
}
