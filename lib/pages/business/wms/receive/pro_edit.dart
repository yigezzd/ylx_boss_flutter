import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/select/select_batch.dart';
import 'package:flutter_deer/components/select/select_location.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// WMS 收货商品编辑页（对齐 Vue wms/receiveTakList/proEdit.vue）
///
/// 确认后通过 Navigator.pop 回传：
/// `{productid, barcode, code, size, unit, batchlist:[{id,receiptqty,qty,batchno,birthdate,validdate,locationcode,locationid,palletcode}]}`
class WmsReceiveProEditPage extends StatefulWidget {
  const WmsReceiveProEditPage({
    super.key,
    required this.billInfo,
    required this.item,
    required this.disabled,
    required this.palletLocationMap,
    required this.bsid,
  });

  final Map<String, dynamic> billInfo;
  final Map<String, dynamic> item;
  final bool disabled;

  /// 托盘码→货位号映射（用于自动带出和校验）
  final Map<String, Map<String, String>> palletLocationMap;

  /// 批次查询机构 id（对齐 Vue item.sid || store.id）
  final String bsid;

  @override
  State<WmsReceiveProEditPage> createState() => _WmsReceiveProEditPageState();
}

/// 收货行数据模型
class _ReceiptRow {
  _ReceiptRow({
    this.id,
    this.qty = 0,
    this.receiptqty = 0,
    String batchno = '',
    this.birthdate = '',
    this.validdate = '',
    this.locationcode = '',
    this.locationid = '',
    String palletcode = '',
  })  : batchController = TextEditingController(text: batchno),
        palletController = TextEditingController(text: palletcode);

  dynamic id;
  num qty;
  num receiptqty;
  final TextEditingController batchController;
  String birthdate;
  String validdate;
  String locationcode;
  String locationid;
  final TextEditingController palletController;

  String get batchno => batchController.text.trim();
  String get palletcode => palletController.text.trim();

  void dispose() {
    batchController.dispose();
    palletController.dispose();
  }
}

class _WmsReceiveProEditPageState extends State<WmsReceiveProEditPage> {
  late final Map<String, dynamic> _item;
  final List<_ReceiptRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _item = {
      'validflag': 0,
      'validday': 0,
      ...widget.item,
    };
    _initRows();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// 初始化收货行（对齐 Vue onLoad 从 batchlist 构建）
  void _initRows() {
    final batchList = ((_item['batchlist'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (batchList.isNotEmpty) {
      for (final b in batchList) {
        _rows.add(_ReceiptRow(
          id: b['id'],
          qty: _num(b['qty']),
          // 默认收货数对齐 Vue `b.receiptqty || b.qty || b.checkqty || 0`：
          // 已保存的收货数优先，为 0/空时依次继承批次数量、盘点数量
          receiptqty: _firstTruthyNum([b['receiptqty'], b['qty'], b['checkqty']]),
          batchno: b['batchno']?.toString() ?? '',
          birthdate: _dateOnly(b['birthdate']),
          validdate: _dateOnly(b['validdate']),
          // 货位/托盘对齐 Vue `||` 链：行内值为空时回退商品级默认值
          locationcode: _firstNonEmpty([b['locationcode'], _item['locationcode']]),
          locationid: _firstNonEmpty([b['locationid'], _item['locationid']]),
          palletcode: _firstNonEmpty([b['palletcode'], b['dataonlyid']]),
        ));
      }
    } else {
      _rows.add(_ReceiptRow(
        id: _item['id'],
        qty: _num(_item['qty']),
        receiptqty: _num(_item['receiptqty']),
        batchno: _item['batchno']?.toString() ?? '',
        birthdate: _dateOnly(_item['birthdate']),
        validdate: _dateOnly(_item['validdate']),
        locationcode: _item['locationcode']?.toString() ?? '',
        locationid: _item['locationid']?.toString() ?? '',
        palletcode: _item['palletcode']?.toString() ?? '',
      ));
    }
  }

  static num _num(dynamic v) {
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// 对齐 JS `b.receiptqty || b.qty || b.checkqty || 0` 数量取值链：
  /// 依次取第一个可解析且非 0 的数量，全部为 0/空时返回 0
  static num _firstTruthyNum(List<dynamic> candidates) {
    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      final n = num.tryParse(s);
      if (n == null || n == 0) continue;
      return n;
    }
    return 0;
  }

  /// 对齐 JS `a || b || ""` 字符串取值链：依次取第一个非空值
  static String _firstNonEmpty(List<dynamic> candidates) {
    for (final v in candidates) {
      final s = v?.toString() ?? '';
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _dateOnly(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  bool get _validflag => _item['validflag']?.toString() == '1';

  num get _orderqty => _num(_item['orderqty']);

  /// 每行实际允许的最大收货数量（对齐 Vue rowMaxAllowed）
  num _rowMaxAllowed(int idx) {
    num sumOthers = 0;
    for (int i = 0; i < _rows.length; i++) {
      if (i != idx) sumOthers += _rows[i].receiptqty;
    }
    final max = _orderqty - sumOthers;
    return max > 0 ? max : 0;
  }

  // ────────────────────── 行操作 ──────────────────────

  /// 添加收货行（对齐 Vue addRow：继承上一行的 batch/birthdate/validdate/location）
  void _addRow() {
    final last = _rows.last;
    setState(() {
      _rows.add(_ReceiptRow(
        qty: _orderqty,
        batchno: last.batchno,
        birthdate: last.birthdate,
        validdate: last.validdate,
        locationcode: last.locationcode,
        locationid: last.locationid,
      ));
    });
  }

  void _delRow(int idx) {
    if (_rows.length <= 1) {
      Toast.show('至少保留一条收货行');
      return;
    }
    setState(() {
      _rows[idx].dispose();
      _rows.removeAt(idx);
    });
  }

  /// 收货数量变更：保证所有行合计不超过订货数（对齐 Vue onReceiptQtyChange）
  void _onReceiptQtyChange(int idx, num newVal) {
    final maxAllowed = _rowMaxAllowed(idx);
    if (newVal > maxAllowed) {
      setState(() => _rows[idx].receiptqty = maxAllowed);
      Toast.show('收货总数不能超过订货数，当前行已自动限制为 $maxAllowed');
    } else if (newVal < 0) {
      setState(() => _rows[idx].receiptqty = 0);
    } else {
      setState(() => _rows[idx].receiptqty = newVal);
    }
  }

  // ────────────────────── 批次/日期/货位/托盘 ──────────────────────

  /// 选择批次（对齐 Vue selectBatchFn：自动回填生产日期/有效日期）
  Future<void> _openBatchSelect(int idx) async {
    final row = _rows[idx];
    final result = await SelectBatchSheet.show(
      context,
      productid: _item['productid']?.toString() ?? '',
      bsid: widget.bsid,
      counterid: '',
      initialBatchNo: row.batchno,
    );
    if (result == null || !mounted) return;
    setState(() {
      row.batchController.text = result['batchno']?.toString() ?? '';
      final birthdate = _dateOnly(result['birthdate']);
      final validdate = _dateOnly(result['validdate']);
      if (birthdate.isNotEmpty) row.birthdate = birthdate;
      if (validdate.isNotEmpty) row.validdate = validdate;
      // 保质期商品且有 validday，重新自动计算有效日期
      if (_validflag && _num(_item['validday']) > 0 && row.birthdate.isNotEmpty) {
        row.validdate = _calcValidDate(row.birthdate);
      }
    });
  }

  /// 保质期商品：生产日期 + validday 计算有效日期
  String _calcValidDate(String birthdate) {
    final d = DateTime.tryParse(birthdate);
    if (d == null) return '';
    final days = _num(_item['validday']).toInt();
    final v = d.add(Duration(days: days));
    return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
  }

  /// 日期选择（生产日期/有效日期）
  Future<void> _pickDate(int idx, {required bool isBirthdate}) async {
    final row = _rows[idx];
    final current = isBirthdate ? row.birthdate : row.validdate;
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
      if (isBirthdate) {
        row.birthdate = dateStr;
        // validflag == 1 且有 validday，自动计算有效日期（对齐 Vue onBirthdateConfirm）
        if (_validflag && _num(_item['validday']) > 0) {
          row.validdate = _calcValidDate(dateStr);
        }
      } else {
        row.validdate = dateStr;
      }
    });
  }

  /// 选择货位号（zonetype=3 收货暂存区）
  Future<void> _openLocationSelect(int idx) async {
    final row = _rows[idx];
    final result = await SelectLocationPage.show(
      context,
      initialSelectedId: row.locationid.isNotEmpty ? row.locationid : null,
      zonetype: 3,
    );
    if (result == null || !mounted) return;
    setState(() {
      row.locationcode = result['locationcode']?.toString() ?? '';
      row.locationid = result['locationid']?.toString() ?? '';
    });
  }

  /// 扫描托盘码
  Future<void> _scanPalletCode(int idx) async {
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
      _rows[idx].palletController.text = scancode;
    });
    _tryAutoFillLocation(idx);
  }

  /// 自动带出货位号（对齐 Vue tryAutoFillLocation）
  /// 优先级：全局映射 > 当前页面内其他行（同托盘码）
  void _tryAutoFillLocation(int idx) {
    final row = _rows[idx];
    final pc = row.palletcode;
    if (pc.isEmpty) return;
    final globalMatch = widget.palletLocationMap[pc];
    if ((globalMatch?['locationcode'] ?? '').isNotEmpty) {
      setState(() {
        row.locationcode = globalMatch!['locationcode']!;
        row.locationid = globalMatch['locationid'] ?? '';
      });
      return;
    }
    for (int i = 0; i < _rows.length; i++) {
      if (i != idx && _rows[i].palletcode == pc && _rows[i].locationcode.isNotEmpty) {
        setState(() {
          row.locationcode = _rows[i].locationcode;
          row.locationid = _rows[i].locationid;
        });
        return;
      }
    }
  }

  // ────────────────────── 确认 ──────────────────────

  /// 确认提交（对齐 Vue confirm 校验链）
  void _confirm() {
    // 校验：托盘码必填
    if (_rows.any((r) => r.palletcode.isEmpty)) {
      Toast.show('请填写托盘码');
      return;
    }
    // 校验：生产日期必填（保质期商品）
    if (_validflag && _rows.any((r) => r.birthdate.isEmpty)) {
      Toast.show('请填写生产日期');
      return;
    }
    // 校验：保质期商品批次必填
    if (_validflag && _rows.any((r) => r.batchno.isEmpty)) {
      Toast.show('管理保质期商品必须输入批次！');
      return;
    }
    // 校验：收货数量总和不能超过订货数
    num totalReceipt = 0;
    for (final r in _rows) {
      totalReceipt += r.receiptqty;
    }
    if (totalReceipt > _orderqty) {
      Toast.show('收货总数($totalReceipt)不能超过订货数($_orderqty)');
      return;
    }
    // 校验：存在收货数为0的行
    if (_rows.any((r) => r.receiptqty == 0)) {
      Toast.show('存在收货数为0的收货行，请填写或删除');
      return;
    }
    // 校验：重复行（批次 + 货位 + 托盘码 完全相同）
    final keySet = <String>{};
    for (final r in _rows) {
      if (r.batchno.isNotEmpty && r.locationcode.isNotEmpty && r.palletcode.isNotEmpty) {
        final key = '${r.batchno}||${r.locationcode}||${r.palletcode}';
        if (keySet.contains(key)) {
          Toast.show('存在重复的收货行（批次+货位+托盘码相同）');
          return;
        }
        keySet.add(key);
      }
    }
    // 校验：同一托盘码必须对应唯一货位号（页面内 + 全局）
    final localPalletLocMap = <String, String>{};
    for (final r in _rows) {
      if (r.palletcode.isEmpty) continue;
      final globalLoc = widget.palletLocationMap[r.palletcode];
      if ((globalLoc?['locationcode'] ?? '').isNotEmpty &&
          r.locationcode.isNotEmpty &&
          globalLoc!['locationcode'] != r.locationcode) {
        Toast.show('托盘码 ${r.palletcode} 已绑定货位号 ${globalLoc['locationcode']}，不能关联不同货位');
        return;
      }
      if (localPalletLocMap.containsKey(r.palletcode)) {
        if (r.locationcode.isNotEmpty && localPalletLocMap[r.palletcode] != r.locationcode) {
          Toast.show('同一托盘码 ${r.palletcode} 必须对应相同的货位号');
          return;
        }
      } else if (r.locationcode.isNotEmpty) {
        localPalletLocMap[r.palletcode] = r.locationcode;
      }
    }

    // 回传数据给父页（对齐 Vue onProEditDone 回传结构）：
    // 需回传 barcode/code 供父页按 productid + barcode 精准匹配当前规格
    Navigator.pop(context, {
      'productid': _item['productid']?.toString() ?? '',
      'barcode': _item['barcode']?.toString() ?? '',
      'code': _item['code']?.toString() ?? '',
      'size': _item['size']?.toString() ?? '',
      'unit': _item['unit']?.toString() ?? '',
      'batchlist': _rows
          .map((r) => {
                'id': r.id,
                'receiptqty': r.receiptqty,
                'qty': r.qty,
                'batchno': r.batchno,
                'birthdate': r.birthdate,
                'validdate': r.validdate,
                'locationcode': r.locationcode,
                'locationid': r.locationid,
                'palletcode': r.palletcode,
              })
          .toList(),
    });
  }

  // ────────────────────── UI ──────────────────────

  @override
  Widget build(BuildContext context) {
    final productname = _item['productname']?.toString() ?? _item['name']?.toString() ?? '';
    final size = _item['size']?.toString() ?? '';
    final barcode = (_item['barcode']?.toString() ?? '').isNotEmpty
        ? _item['barcode'].toString()
        : (_item['code']?.toString() ?? '');

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
          '收货商品详情',
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
                // ── 商品基本信息 ──
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '商品名称：$productname${size.isNotEmpty ? '（$size）' : ''}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                          Text(
                            '订货数：${MathUtils.formatDecimal(1, _item['orderqty'] ?? 0)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '条码：$barcode',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                            ),
                          ),
                          Text(
                            '收货数：${MathUtils.formatDecimal(1, _item['receiptqty'] ?? 0)}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '托盘存数：${MathUtils.formatDecimal(1, _item['palletstock'] ?? 0)}',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                            ),
                          ),
                          Text(
                            '托盘底数：${MathUtils.formatDecimal(1, _item['palletbase'] ?? 0)}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '托盘层数：${MathUtils.formatDecimal(1, _item['palletlayer'] ?? 0)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // ── 收货信息区域 ──
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
                            '收货信息',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const Spacer(),
                          if (!widget.disabled)
                            GestureDetector(
                              onTap: _addRow,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF006EFF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '添加',
                                  style: TextStyle(fontSize: 13, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (int i = 0; i < _rows.length; i++) ...[
                        if (i > 0) const Divider(height: 20, color: Color(0xFFE5E7EB)),
                        _buildReceiptRow(i),
                      ],
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
    );
  }

  /// 单条收货行
  Widget _buildReceiptRow(int idx) {
    final row = _rows[idx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 收货数量（支持手动输入 + 步进器，对齐 Vue tm-stepper fixed=1）
        _fieldRow(
          label: '收货数量',
          child: widget.disabled
              ? Text(
                  MathUtils.formatDecimal(1, row.receiptqty),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                )
              : _Stepper(
                  value: row.receiptqty,
                  max: _rowMaxAllowed(idx),
                  min: 0,
                  onChanged: (v) => _onReceiptQtyChange(idx, v),
                ),
        ),
        // 商品批次
        _fieldRow(
          label: '商品批次',
          required: _validflag,
          child: widget.disabled
              ? Text(
                  row.batchno,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: row.batchController,
                        keyboardType: TextInputType.number,
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
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _openBatchSelect(idx),
                      child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFFB7B7B7)),
                    ),
                  ],
                ),
        ),
        // 生产日期
        _fieldRow(
          label: '生产日期',
          required: _validflag,
          onTap: widget.disabled ? null : () => _pickDate(idx, isBirthdate: true),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.birthdate.isNotEmpty ? row.birthdate : (widget.disabled ? '' : '请选择'),
                style: TextStyle(
                  fontSize: 14,
                  color:
                      row.birthdate.isNotEmpty ? const Color(0xFF333333) : const Color(0xFF8B8B8B),
                ),
              ),
              if (!widget.disabled)
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB7B7B7)),
            ],
          ),
        ),
        // 有效日期
        _fieldRow(
          label: '有效日期',
          onTap: widget.disabled ? null : () => _pickDate(idx, isBirthdate: false),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.validdate.isNotEmpty
                    ? row.validdate
                    : (_validflag ? '由生产日期自动算出' : (widget.disabled ? '' : '请选择')),
                style: TextStyle(
                  fontSize: row.validdate.isNotEmpty ? 14 : 12,
                  color:
                      row.validdate.isNotEmpty ? const Color(0xFF333333) : const Color(0xFF8B8B8B),
                ),
              ),
              if (!widget.disabled)
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB7B7B7)),
            ],
          ),
        ),
        // 收货暂存-货位号
        _fieldRow(
          label: '收货暂存-货位号',
          onTap: widget.disabled ? null : () => _openLocationSelect(idx),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.locationcode,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
              if (!widget.disabled)
                const Icon(Icons.arrow_drop_down, size: 20, color: Color(0xFF999999)),
            ],
          ),
        ),
        // 托盘码
        _fieldRow(
          label: '托盘码',
          required: true,
          child: widget.disabled
              ? Text(
                  row.palletcode,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: row.palletController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        onSubmitted: (_) => _tryAutoFillLocation(idx),
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
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _scanPalletCode(idx),
                      child: const Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFF006EFF)),
                    ),
                  ],
                ),
        ),
        // 删除行按钮
        if (!widget.disabled && _rows.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _delRow(idx),
              child: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.remove_circle_outline, size: 22, color: Color(0xFFD54B5A)),
              ),
            ),
          ),
      ],
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
            // 标签：自然宽度左对齐（不截断、不换行），标签与控件间距紧凑
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (required)
                  const Text('*', style: TextStyle(fontSize: 13, color: Color(0xFFD54B5A))),
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                  maxLines: 1,
                ),
              ],
            ),
            const SizedBox(width: 8),
            // 控件区：占满剩余空间，内容靠右显示
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// 数量输入器（对齐 Vue tm-stepper，fixed=1）
///
/// 中间为可手动输入的文本框，两侧为步进按钮；
/// 失焦/回车时统一按一位数量格式（formatDecimal(1)）回显并触发变更。
class _Stepper extends StatefulWidget {
  const _Stepper({
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
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  late final TextEditingController _controller = TextEditingController(text: _fmt(widget.value));
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _Stepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 值由外部（父级限制逻辑）变更时同步回显，避免与输入中的内容冲突
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 显示格式与页面其他数量字段统一（保留一位数量小数）
  static String _fmt(num v) => MathUtils.formatDecimal(1, v);

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  /// 提交输入：解析 + 范围限制 + 统一格式化回显
  void _commit() {
    final parsed = num.tryParse(_controller.text.trim());
    if (parsed == null) {
      // 非法输入回退为当前值
      _controller.text = _fmt(widget.value);
      return;
    }
    var next = parsed;
    if (next < widget.min) {
      next = widget.min;
    } else if (next > widget.max) {
      next = widget.max;
    }
    _controller.text = _fmt(next);
    if (next != widget.value) {
      widget.onChanged(next);
    }
  }

  /// 步进调整：基于输入框当前数值 +1/-1（对齐 tm-stepper）
  void _step(num delta) {
    final base = num.tryParse(_controller.text.trim()) ?? widget.value;
    var next = base + delta;
    if (next < widget.min) {
      next = widget.min;
    } else if (next > widget.max) {
      next = widget.max;
    }
    _controller.text = _fmt(next);
    if (next != widget.value) {
      widget.onChanged(next);
    } else {
      // 已到边界时刷新按钮禁用态
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.value > widget.min ? () => _step(-1) : null,
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
              color: widget.value > widget.min ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
            ),
          ),
        ),
        Container(
          width: 76,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDEDEDE)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            onSubmitted: (_) => _commit(),
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
            ),
          ),
        ),
        GestureDetector(
          onTap: widget.value < widget.max ? () => _step(1) : null,
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
              color: widget.value < widget.max ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
            ),
          ),
        ),
      ],
    );
  }
}
