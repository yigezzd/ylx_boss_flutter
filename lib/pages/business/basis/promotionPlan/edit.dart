import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/pro_details_sheet.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 促销调价 - 编辑/新增页
/// 参考 Vue boss 项目 promotionPlan/edit.vue
class PromotionPlanEditPage extends StatefulWidget {
  const PromotionPlanEditPage({super.key, this.billid});

  final String? billid;

  @override
  State<PromotionPlanEditPage> createState() => _PromotionPlanEditPageState();
}

class _PromotionPlanEditPageState extends State<PromotionPlanEditPage> {
  final TextEditingController _billnameCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // ── 单据数据（对齐 Vue query）──
  String _billid = '';
  String _billno = '';
  String _startdate = '';
  String _enddate = '';
  String _starttime = '00:00:00';
  String _endtime = '23:59:59';
  String _sids = '';
  String _mdstore = '';
  String _createtime = '';
  String _createname = '';
  int _signflag = 0;
  String _reviewsignflag = '';
  String _reviewremark = '';
  List<Map<String, dynamic>> _ptdetaillist = [];

  // ── 多级审批 ──
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  String _userCode = '';
  String _userid = '';
  Map<String, dynamic>? _savedSignData;

  // ── 批量删除 ──
  bool _isDelMode = false;
  Set<int> _delChecked = {};

  // ── PDA/扫码枪输入（与门店调价单一致的扫码交互）──
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  Timer? _scanDebounceTimer;
  bool _scanFieldFocused = false;
  bool _scanBusy = false;

  /// 吸顶区高度常量（对齐采购订货粘性表头）：扫码框区域 + 明细标题栏，区块固定高度确保总高精确无间隙
  static const double _scanStickyHeight = 68.0;
  static const double _stickyTitleHeight = 40.0;
  static const double _stickyExtent = _scanStickyHeight + _stickyTitleHeight;

  bool _loading = false;

  bool get _isEdit => _billid.isNotEmpty;
  bool get _isSigned => _signflag == 1;
  bool get _isRejected => _signflag == 2;
  bool get _isAdmin => _userCode == '1001';

  /// 表单是否可编辑（对齐 Vue bolHandle）
  bool get _bolHandle {
    if (_signflag == 1) return false;
    if (_reviewFlowUsers.isEmpty) return true;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return !(firstIndex > 1);
  }

  bool get _disabled => !_bolHandle;

  /// 当前用户是否属于审批流
  bool get _bolHandleT {
    if (_isAdmin) return true;
    return _reviewFlowUsers.any((item) => item['userid']?.toString() == _userid);
  }

  /// 是否为第一审批人或管理员
  bool get _bolHandleTT {
    if (_isAdmin) return true;
    if (_reviewFlowUsers.isEmpty) return true;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return firstIndex <= 1;
  }

  /// 是否可显示撤回按钮（审核中途且非第一节点）
  bool get _canWithdraw {
    if (!_isEdit) return false;
    if (_isSigned) return false;
    if (_reviewFlowUsers.isEmpty) return false;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return firstIndex > 1;
  }

  @override
  void initState() {
    super.initState();
    // 从 user cookie 读取 userid / code（对齐采购计划/订货等模块）
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _userid = userMap['userid']?.toString() ?? '';
        _userCode = userMap['code']?.toString() ?? '';
      }
    } catch (_) {}

    final today = _formatDate(DateTime.now());
    _startdate = today;
    _enddate = today;

    if (widget.billid != null && widget.billid!.isNotEmpty) {
      _billid = widget.billid!;
      _getInfo({'billid': _billid});
    } else {
      // 新增：默认当前门店（从 store cookie 读取，对齐 Vue store?.id / store?.name）
      try {
        final storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
          _sids = storeMap['id']?.toString() ?? '';
          _mdstore = storeMap['name']?.toString() ?? '';
        }
      } catch (_) {}
      _initSignUserBtn();
    }

    // 扫码枪输入框：回车提交；150ms 防抖兜底红外扫码枪逐字符写入（参考采购入库单）
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          final scanCode = _scanController.text.trim();
          if (scanCode.isNotEmpty) {
            _scanDebounceTimer?.cancel();
            _onScanInput(scanCode);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _scanFocusNode.addListener(() {
      if (_scanFocusNode.hasFocus && !_scanFieldFocused) {
        _scanFieldFocused = true;
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } else if (!_scanFocusNode.hasFocus) {
        _scanFieldFocused = false;
      }
    });
    _scanController.addListener(() {
      _scanDebounceTimer?.cancel();
      final text = _scanController.text.trim();
      if (text.isEmpty) return;
      _scanDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final code = _scanController.text.trim();
        if (code.isEmpty) return;
        _onScanInput(code);
      });
    });
  }

  @override
  void dispose() {
    _billnameCtrl.dispose();
    _scrollCtrl.dispose();
    _scanDebounceTimer?.cancel();
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // =================== 数据加载 ===================
  Future<void> _getInfo(Map<String, dynamic> params,
      {bool clearIds = false, VoidCallback? callback}) async {
    setState(() => _loading = true);
    try {
      final result = await request(HttpApi.promotionPlanGetInfo, {
        'getMasterInfo': params,
      });
      final data = result['data'];
      if (data != null) {
        final masterinfo = data is Map<String, dynamic> ? data['masterinfo'] : null;
        final master = masterinfo is Map<String, dynamic> ? masterinfo['master'] : null;
        final detaillist = masterinfo is Map<String, dynamic> ? masterinfo['detaillist'] : null;

        if (master is Map<String, dynamic>) {
          _billid = master['billid']?.toString() ?? _billid;
          _billno = master['billno']?.toString() ?? '';
          _startdate = (master['startdate']?.toString() ?? '').substring(0, 10);
          _enddate = (master['enddate']?.toString() ?? '').substring(0, 10);
          _starttime = master['starttime']?.toString() ?? '00:00:00';
          _endtime = master['endtime']?.toString() ?? '23:59:59';
          _sids = master['sids']?.toString() ?? '';
          _mdstore = master['mdstore']?.toString() ?? '';
          _createtime = master['createtime']?.toString() ?? '';
          _createname = master['createname']?.toString() ?? '';
          _signflag = int.tryParse(master['signflag']?.toString() ?? '0') ?? 0;
          _reviewsignflag = master['reviewsignflag']?.toString() ?? '';
          _reviewremark = master['reviewremark']?.toString() ?? '';
          _billnameCtrl.text = master['billname']?.toString() ?? '';

          // 审批数据
          _reviewFlowUsers = _parseReviewList(master['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(master['reviewBillFlows']);
        }

        _ptdetaillist =
            (detaillist as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

        if (clearIds) {
          for (final c in _ptdetaillist) {
            c.remove('id');
          }
        }

        // 格式化价格字段
        for (final c in _ptdetaillist) {
          c['dcprice'] = MathUtils.formatDecimal(2, c['dcprice']);
          c['promotionjoinrate'] = MathUtils.formatDecimal(2, c['promotionjoinrate']);
          c['promotioninprice'] = MathUtils.formatDecimal(2, c['promotioninprice']);
        }
      }
      callback?.call();
    } catch (e) {
      Toast.show('加载失败：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 新单据时，根据机构查询是否需要审批签字
  Future<void> _initSignUserBtn() async {
    if (_isAdmin) return;
    if (!_isEdit && _sids.isNotEmpty) {
      try {
        await request(HttpApi.reviewTypeConfigGetNewBillSignUser, {
          'billtypeid': '0149',
          'bsid': _sids,
        });
      } catch (_) {
        // ignore
      }
      if (mounted) setState(() {});
    }
  }

  // =================== 门店选择 ===================
  Future<void> _selectStore() async {
    if (_disabled) return;
    final result = await SelectStorePage.show(
      context,
      initialSelectedId: _sids,
    );
    if (result != null && mounted) {
      setState(() {
        _sids = result['storeid']?.toString() ?? '';
        _mdstore = result['storename']?.toString() ?? '';
      });
      _initSignUserBtn();
    }
  }

  // =================== 日期选择 ===================
  Future<void> _pickDateRange() async {
    if (_disabled) return;
    final start = await showCommonDatePicker(
      context,
      initial: DateTime.tryParse(_startdate) ?? DateTime.now(),
    );
    if (start == null) return;
    final end = await showCommonDatePicker(
      context,
      initial: DateTime.tryParse(_enddate) ?? DateTime.now(),
    );
    if (end == null) return;
    if (end.isBefore(start)) {
      Toast.show('结束日期不能早于开始日期');
      return;
    }
    setState(() {
      _startdate = _formatDate(start);
      _enddate = _formatDate(end);
    });
  }

  // =================== 时间选择 ===================
  Future<void> _pickStartTime() async {
    if (_disabled) return;
    final initial = _starttime.isNotEmpty ? _starttime : '00:00:00';
    final picked = await showCommonTimePicker(context, initial: initial);
    if (picked != null) {
      if (_endtime.isNotEmpty && picked.compareTo(_endtime) >= 0) {
        Toast.show('开始时间必须小于结束时间');
        return;
      }
      setState(() => _starttime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    if (_disabled) return;
    final initial = _endtime.isNotEmpty ? _endtime : '23:59:59';
    final picked = await showCommonTimePicker(context, initial: initial);
    if (picked != null) {
      if (_starttime.isNotEmpty && picked.compareTo(_starttime) <= 0) {
        Toast.show('结束时间必须大于开始时间');
        return;
      }
      setState(() => _endtime = picked);
    }
  }

  // =================== 商品选择 ===================
  Future<void> _selectProduct() async {
    if (_disabled) return;
    final result = await _openSelectProduct();
    _applySelectProductResult(result);
  }

  /// 跳转商品选择页（多选），扫码同码多条时带关键词过滤候选商品（对齐小程序 selectProductFn/scanFn）
  Future<List<Map<String, dynamic>>?> _openSelectProduct({String? keyword}) async {
    final storeid = int.tryParse(_sids);
    return Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          storeid: storeid,
          multiple: true,
          checkboxMode: true,
          selectList: _ptdetaillist,
          paramJust: const ['unit', 'size'],
          mergData: {
            'itemstatus': '1,2',
            'storeid': _sids,
            'field': 'barcode',
            'type': 'desc',
          },
          // 扫码词过滤：选品页按该关键词展示候选商品（对齐小程序 cond）
          initialKeyword: keyword,
        ),
      ),
    );
  }

  /// 选品页返回数据处理（对齐小程序 onSelectProduct：handleProperty 后覆盖明细）
  void _applySelectProductResult(List<Map<String, dynamic>>? result) {
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      for (final prod in result) {
        prod['productbarcode'] = prod['barcode']?.toString() ?? '';
        prod['productcode'] = prod['code']?.toString() ?? '';
        prod['dcprice'] = MathUtils.formatDecimal(2, prod['dcprice'] ?? 0);
        prod['promotionjoinrate'] = MathUtils.formatDecimal(2, prod['promotionjoinrate'] ?? 0);
        prod['promotioninprice'] = MathUtils.formatDecimal(2, prod['promotioninprice'] ?? 0);
      }
      _ptdetaillist = result;
    });
  }

  // =================== 扫码 ===================
  Future<void> _scanBarcode() async {
    if (_disabled) return;
    if (!Device.isMobile) {
      Toast.show('当前平台暂支持扫码');
      return;
    }
    final code = await Navigator.push<Object>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code == null || !mounted) return;
    _handleScannedCode(code.toString());
    // _handleScannedCode('98545415511');
  }

  /// PDA/扫码枪输入统一入口：先清空输入框防重触发，
  /// 复用摄像头扫码同一处理方法 _handleScannedCode（判重/累加/覆盖/弹窗一致），
  /// 处理完成（含商品详情弹窗关闭）后重新聚焦，支持连续扫码
  Future<void> _onScanInput(String code) async {
    _scanController.clear();
    _scanDebounceTimer?.cancel();
    if (_disabled) return;
    // 上一笔仍在查询/弹窗中时丢弃本次输入，避免并发插入明细造成数据竞争
    if (_scanBusy) return;
    _scanBusy = true;
    try {
      await _handleScannedCode(code);
    } finally {
      _scanBusy = false;
    }
    if (!mounted) return;
    _scanFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// 扫码枪输入框（与门店调价单一致：白色圆角卡片包裹）
  Widget _buildScanInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _scanController,
                focusNode: _scanFocusNode,
                autofocus: true,
                showCursor: true,
                keyboardType: TextInputType.none,
                enableInteractiveSelection: false,
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '请将扫描枪对准商品条码',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFFD1D5DB)),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF006EFF)),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleScannedCode(String code) async {
    if (code.trim().isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    try {
      // 尝试解析条码秤生成的重量码/金额码（对齐小程序 scanFn）
      final scaleInfo = parseScaleBarcode(code);
      final searchCode = scaleInfo?.productCode ?? code;
      final result = await request(HttpApi.productGetList, {
        'barcode': searchCode,
        'is_page': 1,
        'page': 1,
        'pagesize': 10,
        'itemstatus': '1,2',
        'bsid': _sids,
        'weekmonthflag': 1,
        'indivunitsize': 1,
        'ydcpriceflag': 1,
      });
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      // 未查询到商品或返回数据无效（无 productid）时友好提示
      final prod = list.isNotEmpty ? Map<String, dynamic>.from(list[0] as Map) : null;
      if (prod == null || (prod['productid']?.toString() ?? '').isEmpty) {
        Toast.show('未查询到该商品');
        return;
      }
      // 同码多条判定（对齐小程序 scanFn）：自编码命中多条 → 跳转选品页；
      // 无自编码命中且商品条码命中多条 → 跳转选品页，由用户手动挑选
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
        // 选品页按扫码词过滤候选商品，多选返回后覆盖明细（与 selectProductFn 一致）
        final result = await _openSelectProduct(keyword: searchCode);
        _applySelectProductResult(result);
        return;
      }
      // 对齐小程序 isSameProductItem：productid + barcode 组合判重
      //（同商品不同条码的多单位/多规格允许录入；任一方条码为空时按 productid 判重）
      final filterIndex = _ptdetaillist.indexWhere((row) => _isSameProductItem(prod, row));
      // 重复录入策略取后台配置（对齐 loginParamResp.addRepeatProductFlag）
      final flag = _getAddRepeatProductFlag();
      // 扫码数量：重量码直接取数量，金额码按单价反算，普通条码默认1
      double scanQty = 1;
      if (scaleInfo?.type == 'weight') {
        scanQty = scaleInfo?.qty ?? 1;
      } else if (scaleInfo?.type == 'amount') {
        // JS 真值语义：sellprice || inprice || 0
        final sp = prod['sellprice']?.toString() ?? '';
        final priceSrc = (sp.isNotEmpty && sp != '0') ? prod['sellprice'] : prod['inprice'];
        final price = double.tryParse(priceSrc?.toString() ?? '') ?? 0;
        if (price > 0) {
          scanQty = (scaleInfo?.amount ?? 0) / price;
        }
      }
      if (filterIndex < 0 || flag == 3) {
        // 商品不存在 或 允许重复：新增一行，默认字段赋值（对齐 handleProperty）
        final newRow = Map<String, dynamic>.from(prod);
        _handleProperty(newRow);
        newRow['qty'] = scanQty;
        _writeData(newRow);
        _defValSet(newRow);
        setState(() => _ptdetaillist.insert(0, newRow));
        // 记录新增行下标，保证弹窗确认后能回写到正确行；
        // 等待弹窗关闭后再返回，便于扫码枪输入框重新聚焦连续扫码
        await _showProductDetail(0);
      } else if (flag == 1) {
        // 不提示，累加：扫码数量累加到已存在行
        setState(() {
          final existRow = _ptdetaillist[filterIndex];
          final existQty = double.tryParse(existRow['qty']?.toString() ?? '') ?? 0;
          existRow['qty'] = existQty + scanQty;
          _writeData(existRow);
          _defValSet(existRow);
        });
      } else if (flag == 2) {
        // 不提示，覆盖：扫码数量覆盖已存在行数量
        setState(() {
          final existRow = _ptdetaillist[filterIndex];
          existRow['qty'] = scanQty;
          _writeData(existRow);
          _defValSet(existRow);
        });
      } else {
        // flag == 0：提示，限制重复录入
        Toast.show('单据中已存在该商品');
      }
    } catch (_) {
      Toast.show('查询商品失败');
    }
  }

  /// 同一商品明细判断：按 productid + barcode 组合判重（对齐小程序 isSameProductItem）
  static bool _isSameProductItem(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a['productid']?.toString() != b['productid']?.toString()) return false;
    final aBarcode = (a['productbarcode'] ?? a['barcode'])?.toString() ?? '';
    final bBarcode = (b['productbarcode'] ?? b['barcode'])?.toString() ?? '';
    if (aBarcode.isEmpty || bBarcode.isEmpty) return true;
    return aBarcode == bBarcode;
  }

  /// 读取登录参数 addRepeatProductFlag（重复录入策略，对齐小程序 loginParamResp）
  int _getAddRepeatProductFlag() {
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
        return int.tryParse(cfg['addRepeatProductFlag']?.toString() ?? '') ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// 默认字段赋值（对齐小程序 handleProperty）
  void _handleProperty(Map<String, dynamic> v) {
    v['onlyid'] = v['onlyid'] ?? '';
    if ((v['productbarcode']?.toString() ?? '').isEmpty) {
      v['productbarcode'] = v['barcode'];
    }
    if ((v['productcode']?.toString() ?? '').isEmpty) {
      v['productcode'] = v['code'];
    }
    if ((v['productname']?.toString() ?? '').isEmpty) {
      v['productname'] = v['name'];
    }
    v['name'] = v['name'] ?? '';
    v['typename'] = v['typename'] ?? '';
    v['unit'] = v['unit'] ?? '';
    final rate = double.tryParse(v['rate']?.toString() ?? '');
    if (rate == null || rate == 0) v['rate'] = 0;
    v['dcprice'] = v['dcprice'] ?? '';
    v['promotionjoinrate'] = v['promotionjoinrate'] ?? 0;
    v['itempromotionflag'] = v['itempromotionflag'] ?? 1;
    for (final key in v.keys.toList()) {
      if (key.contains('price')) {
        v[key] = MathUtils.formatDecimal(2, v[key]);
      }
    }
  }

  /// 赋初始值（对齐小程序 defValSet）
  void _defValSet(Map<String, dynamic> row) {
    row['stockqty'] = MathUtils.formatDecimal(1, row['stockqty'] ?? 0);
    row['costprice'] = MathUtils.formatDecimal(2, row['costprice'] ?? 0);
    // JS 真值语义：(obj.saleprice || obj.sellprice) ?? 0
    final sp = row['saleprice']?.toString() ?? '';
    final saleprice = (sp.isNotEmpty && sp != '0') ? row['saleprice'] : row['sellprice'];
    row['saleprice'] = MathUtils.formatDecimal(2, saleprice ?? 0);
    row['sellamt'] = MathUtils.formatDecimal(3, row['sellamt'] ?? 0);
    row['qty'] = MathUtils.formatDecimal(1, row['qty'] ?? 0);
  }

  /// 数量联动计算（对齐小程序 writeData）：qty 与 jsqty 按 packagenum 换算，sellamt = qty * sellprice
  void _writeData(Map<String, dynamic> row) {
    final qty = double.tryParse(row['qty']?.toString() ?? '') ?? 0;
    final packagenum = double.tryParse(row['packagenum']?.toString() ?? '');
    final pn = (packagenum == null || packagenum == 0) ? 1.0 : packagenum;
    row['jsqty'] = MathUtils.formatDecimal(1, qty / pn);
    row['qty'] = MathUtils.formatDecimal(1, qty);
    final sellprice = double.tryParse(row['sellprice']?.toString() ?? '') ?? 0;
    row['sellamt'] = MathUtils.formatDecimal(3, qty * sellprice);
  }

  // =================== 商品详情弹窗 ===================
  Future<void> _showProductDetail(int index) async {
    if (_isDelMode) {
      setState(() {
        if (_delChecked.contains(index)) {
          _delChecked.remove(index);
        } else {
          _delChecked.add(index);
        }
      });
      return;
    }
    if (_disabled) return;
    final item = Map<String, dynamic>.from(_ptdetaillist[index]);
    final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
    final unitcopy = item['unit']?.toString() ?? '';
    final sizecopy = item['size']?.toString() ?? '';
    // 复用公共商品详情弹窗（单位/规格选择 + 价格同步）
    final updated = await ProDetailsSheet.show(
      context,
      item: item,
      storeid: _sids,
      disabled: _disabled,
      showShelves: false,
      // mergData: const { 'counterid': ''},
    );
    if (updated != null && mounted && index >= 0 && index < _ptdetaillist.length) {
      setState(() {
        print('Updating product detail at index $updated');
        final target = _ptdetaillist[index];
        // 更新单位/规格
        // if (updated['unit'] != null) {
        //   target['unit'] = updated['unit'];
        // }
        if (updated['unitonlyid'] != null) {
          target['unitonlyid'] = updated['unitonlyid'];
        }
        // if (updated['size'] != null) {
        //   target['size'] = updated['size'];
        // }
        target['unit'] = unitcopy;
        target['size'] = sizecopy;
        if (updated['sizeonlyid'] != null) {
          target['sizeonlyid'] = updated['sizeonlyid'];
        }
        // 条码
        if (updated['productbarcode']?.toString().isNotEmpty ?? false) {
          target['productbarcode'] = updated['productbarcode'];
        } else if (updated['barcode']?.toString().isNotEmpty ?? false) {
          target['productbarcode'] = updated['barcode'];
        }
        // 单位名称
        if (updated['unitname']?.toString().isNotEmpty ?? false) {
          target['unitname'] = updated['unitname'];
        } else if (updated['unit']?.toString().isNotEmpty ?? false) {
          target['unitname'] = updated['unit'];
        }
        // 规格名称
        if (updated['sizename']?.toString().isNotEmpty ?? false) {
          target['sizename'] = updated['sizename'];
        } else if (updated['size']?.toString().isNotEmpty ?? false) {
          target['sizename'] = updated['size'];
        }
        // 价格同步（对齐 Vue detailConfirm 全量字段）
        final priceFields = [
          'inprice',
          'sellprice',
          'cgprice',
          'oldprice',
          'mprice1',
          'mprice2',
          'mprice3',
          'pfprice1',
          'pfprice2',
          'pfprice3',
          'pfprice',
          'mprice',
          'psprice',
          'ydcprice',
          'dcprice',
          'promotioninprice',
          'promotionjoinrate',
          'packagenum',
        ];
        for (final key in priceFields) {
          if (updated[key] != null) {
            target[key] = updated[key];
          }
        }
      });
    }
  }

  // =================== 批量删除 ===================
  void _toggleDelMode() {
    if (_ptdetaillist.isEmpty) return;
    setState(() {
      _isDelMode = !_isDelMode;
      if (!_isDelMode) _delChecked.clear();
    });
  }

  void _toggleAllDel() {
    setState(() {
      if (_delChecked.length == _ptdetaillist.length) {
        _delChecked.clear();
      } else {
        _delChecked = Set<int>.from(List.generate(_ptdetaillist.length, (i) => i));
      }
    });
  }

  void _confirmDelete() {
    if (_delChecked.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text('确定删除${_delChecked.length}条数据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              setState(() {
                final sorted = _delChecked.toList()..sort();
                for (int i = sorted.length - 1; i >= 0; i--) {
                  _ptdetaillist.removeAt(sorted[i]);
                }
                _isDelMode = false;
                _delChecked.clear();
              });
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // =================== 保存 ===================
  bool _validate() {
    if (_billnameCtrl.text.trim().isEmpty) {
      Toast.show('促销名称不能为空');
      return false;
    }
    if (_startdate.isEmpty || _enddate.isEmpty) {
      Toast.show('活动日期不能为空');
      return false;
    }
    if (_ptdetaillist.every((item) => !(item['productid']?.toString().isNotEmpty ?? false))) {
      Toast.show('请选择商品');
      return false;
    }
    if (_ptdetaillist.any(
        (item) => !(item['dcprice']?.toString().isNotEmpty ?? false) && item['dcprice'] != 0)) {
      Toast.show('请填写商品特价');
      return false;
    }
    return true;
  }

  Map<String, dynamic> _buildSaveParams() {
    double billamt = 0;
    double billqty = 0;
    double billsellamt = 0;
    for (final v in _ptdetaillist) {
      billamt += double.tryParse(v['amt']?.toString() ?? '0') ?? 0;
      billqty += double.tryParse(v['qty']?.toString() ?? '0') ?? 0;
      billsellamt += double.tryParse(v['sellamt']?.toString() ?? '0') ?? 0;
    }

    return {
      'startdate': _startdate,
      'enddate': _enddate,
      'starttime': _starttime,
      'endtime': _endtime,
      'billname': _billnameCtrl.text.trim(),
      'billno': _billno,
      'billid': _billid,
      'sids': _sids,
      'mdstore': _mdstore,
      'billtype': 8,
      'itemtype': 0,
      'salebound': 1,
      'memo': '',
      'signflag': 0,
      'ptdetaillist': _ptdetaillist.map((row) {
        if (row['packageflag'] == 1 && row['unit'] == row['unitname']) {
          row['unitname'] = '';
        }
        if (row['specflag'] == 1 && row['size'] == row['sizename']) {
          row['sizename'] = '';
        }
        return row;
      }).toList(),
      'billamt': billamt,
      'billqty': billqty,
      'billsellamt': billsellamt,
    };
  }

  Future<void> _save() async {
    // 权限校验：区分新增/编辑
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('014903', showTip: false)) {
        Toast.show('你无权编辑促销调价，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('014902', showTip: false)) {
        Toast.show('你无权新增促销调价，请在后台修改权限');
        return;
      }
    }
    if (!_validate()) return;
    final params = _buildSaveParams();
    try {
      final result = await request(HttpApi.promotionPlanSave, {
        'addorUpdateCp': params,
      });
      final data = result['data'];
      if (data != null) {
        _reviewFlowUsers =
            _parseReviewList(data is Map<String, dynamic> ? data['reviewFlowUsers'] : null);
        _reviewBillFlows =
            _parseReviewList(data is Map<String, dynamic> ? data['reviewBillFlows'] : null);
        final newBillid = data is Map<String, dynamic> ? data['billid'] : null;
        if (newBillid != null) {
          _billid = newBillid.toString();
        }
        Toast.show('保存成功');
        _getInfo({'billid': _billid});
        if (mounted) setState(() {});
      }
    } catch (e) {
      print('[促销调价] save error: $e');
      Toast.show('保存失败：$e');
    }
  }

  // =================== 安全解析审批列表（对齐采购入库 _parseReviewList） ===================
  static List<Map<String, dynamic>> _parseReviewList(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Future<void> _saveAndAudit() async {
    if (!PermissionUtils.checkPermission('014905', showTip: false)) {
      Toast.show('你无权审核促销调价，请在后台修改权限');
      return;
    }
    if (!_validate()) return;
    final params = _buildSaveParams();
    try {
      final result = await request(HttpApi.promotionPlanSave, {
        'addorUpdateCp': params,
      });
      final data = result['data'];
      if (data != null) {
        final dataMap = data is Map<String, dynamic> ? data : null;
        final newBillid = dataMap?['billid'];
        if (newBillid != null) {
          _billid = newBillid.toString();
        }
        _savedSignData = dataMap;

        // 保存后先刷新详情（await 等 _getInfo 完成，拿到 reviewFlowUsers）
        await _getInfo({'billid': _billid});
        debugPrint('[促销调价] after _getInfo: reviewFlowUsers=${_reviewFlowUsers.length}');

        // 校验当前用户是否属于审批节点（对齐采购入库）
        if (_reviewFlowUsers.isNotEmpty && !_bolHandleT) {
          Toast.show('您不属于当前审批节点的审核人！');
          return;
        }

        // 与Web端auditCommon对齐：有多级审批时弹窗，无多级审批时直接审核通过
        if (_reviewFlowUsers.isNotEmpty) {
          debugPrint('[促销调价] opening approval modal');
          final approvalResult = await _openApprovalModal();
          if (approvalResult != null && mounted) {
            _reviewsignflag = approvalResult['reviewsignflag']?.toString() ?? '';
            _reviewremark = approvalResult['reviewremark']?.toString() ?? '';
            _doSign(_reviewremark, _savedSignData);
          }
        } else {
          debugPrint('[促销调价] no reviewFlowUsers, auto sign');
          _reviewsignflag = '1';
          _doSign('', _savedSignData);
        }
        if (mounted) setState(() {});
      }
    } catch (e, stack) {
      debugPrint('[促销调价] save error: $e\n$stack');
      Toast.show('保存失败：$e');
    }
  }

  // =================== 审核 ===================
  Future<void> _sign() async {
    if (!PermissionUtils.checkPermission('014905', showTip: false)) {
      Toast.show('你无权审核促销调价，请在后台修改权限');
      return;
    }
    debugPrint(
        '[促销调价] _sign called, billid: $_billid, reviewFlowUsers: ${_reviewFlowUsers.length}');
    if (_billid.isEmpty) return;

    // 多级审批：弹出审批操作弹窗
    if (_reviewFlowUsers.isNotEmpty) {
      debugPrint('[促销调价] _sign: opening approval modal');
      final approvalResult = await _openApprovalModal();
      if (approvalResult == null || !mounted) return;
      _reviewsignflag = approvalResult['reviewsignflag']?.toString() ?? '';
      _reviewremark = approvalResult['reviewremark']?.toString() ?? '';
      _doSign(_reviewremark);
      return;
    }

    // 无多级审批配置：简单确认
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定审核单据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;
    _reviewsignflag = '1';
    _doSign('');
  }

  // =================== 审核弹窗 ===================
  Future<Map<String, dynamic>?> _openApprovalModal() async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ApprovalDialog(),
    );
  }

  Future<void> _doSign(String reviewremark, [Map<String, dynamic>? savedData]) async {
    final statusCpReq = <String, dynamic>{
      if (savedData != null) ...savedData,
      'billid': _billid,
      'signflag': 1,
      'reviewremark': reviewremark,
      'reviewsignflag': _reviewsignflag,
    };
    final rsf = int.tryParse(statusCpReq['reviewsignflag']?.toString() ?? '') ?? 1;
    if (rsf != 2 && rsf != 0) {
      statusCpReq['reviewsignflag'] = 1;
    }
    try {
      final result = await request(HttpApi.promotionPlanSign, {
        'statusCpReq': statusCpReq,
      });
      Toast.show(result['retmsg'] as String? ?? '审核成功');
      _getInfo({'billid': _billid});
      if (mounted) setState(() {});
    } catch (e) {
      Toast.show('审核失败：$e');
    }
  }

  Future<void> _restsignFn() async {
    if (!PermissionUtils.checkPermission('014906', showTip: false)) {
      Toast.show('你无权反审核促销调价，请在后台修改权限');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('撤回单据后，所有审批步骤需重新处理！确定撤回吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm ?? false) {
      _reviewsignflag = '2';
      _doSign('');
    }
  }

  // =================== 删除单据 ===================
  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('014904', showTip: false)) {
      Toast.show('你无权删除促销调价，请在后台修改权限');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定删除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm ?? false) {
      try {
        await request(HttpApi.promotionPlanDelete, {
          'statusCpReq': {
            'billids': [_billid],
            'status': 0,
          },
        });
        Toast.show('删除成功');
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        Toast.show('删除失败：$e');
      }
    }
  }

  // =================== 复制并新增 ===================
  Future<void> _copyAndNew() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确认复制当前单据并新增？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;
    _getInfo({'billid': _billid}, clearIds: true, callback: () {
      setState(() {
        _billid = '';
        _billno = '';
        _signflag = 0;
        _createtime = '';
        _reviewremark = '';
        _reviewBillFlows = [];
        _reviewFlowUsers = [];
      });
      _initSignUserBtn();
    });
  }

  // =================== 审批日志 ===================
  void _showApprovalLogDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: _ApprovalLogSheet(
            reviewBillFlows: _reviewBillFlows,
            scrollController: scrollCtrl,
          ),
        ),
      ),
    );
  }

  // =================== BUILD ===================
  @override
  Widget build(BuildContext context) {
    final String title = _isEdit ? (_isSigned ? '促销调价详情' : '修改促销调价') : '新增促销调价';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              controller: _scrollCtrl,
              cacheExtent: 800,
              slivers: [
                // 审批节点卡片
                if (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: _buildApprovalNodeCard(),
                    ),
                  ),
                // 单据信息卡片
                if (_isEdit)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: _buildBillInfoCard(),
                    ),
                  ),
                // 表单区域
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _buildFormCard(),
                  ),
                ),
                // 扫码枪输入框吸顶（对齐采购订货 SliverPersistentHeader）：
                // 初始位于表单与商品明细之间，滚动到顶部后粘住不滚走
                if (!_disabled)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ScanInputStickyDelegate(state: this),
                  ),
                // 商品明细（可编辑态紧贴吸顶标题栏，无顶部间距）
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, _disabled ? 12 : 0, 12, 0),
                    child: _buildProductDetailSection(),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
      // 底部操作按钮
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── 审批节点卡片 ──
  Widget _buildApprovalNodeCard() {
    Map<String, dynamic>? currentNode;
    String currentInfo = '';

    if (_reviewFlowUsers.isNotEmpty) {
      currentNode = _reviewFlowUsers[0];
      final index = currentNode['index']?.toString() ?? '1';
      final stepname = currentNode['stepname']?.toString() ?? '';
      final username = currentNode['username']?.toString() ?? '';
      currentInfo = '当前在第$index节点【$stepname】';
      if (username.isNotEmpty) currentInfo += '，审批人:$username';
    } else if (_reviewBillFlows.isNotEmpty) {
      currentNode = _reviewBillFlows[0];
      final stepname =
          currentNode['stepname']?.toString() ?? currentNode['stepno']?.toString() ?? '';
      final username = currentNode['username']?.toString() ?? '';
      currentInfo = '节点【$stepname】';
      if (username.isNotEmpty) currentInfo += '，审批人:$username';
    }

    final totalNodes = _reviewFlowUsers.isNotEmpty
        ? int.tryParse(_reviewFlowUsers[0]['allindex']?.toString() ?? '0') ?? 0
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('审核日志',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
              if (totalNodes > 0)
                Text('共$totalNodes个审批节点',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
            ],
          ),
          const SizedBox(height: 10),
          if (currentInfo.isNotEmpty)
            Row(children: [
              Expanded(
                child: Text(currentInfo,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
              ),
              GestureDetector(
                onTap: _showApprovalLogDialog,
                child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
              ),
            ])
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('等待审核中...', style: TextStyle(fontSize: 13, color: Color(0xFFBFBFBF))),
                GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 单据信息卡片 ──
  Widget _buildBillInfoCard() {
    String statusLabel;
    Color statusColor;
    if (_signflag == 0) {
      statusLabel = '待审核';
      statusColor = const Color(0xFFD54B5A);
    } else if (_signflag == 2) {
      statusLabel = '已驳回';
      statusColor = const Color(0xFFE0620D);
    } else {
      statusLabel = '已审核';
      statusColor = const Color(0xFF00A870);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('单号$_billno',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: statusColor),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('制单信息：$_createtime',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            const SizedBox(width: 16),
            Text(_createname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ]),
        ],
      ),
    );
  }

  // ── 表单区域 ──
  Widget _buildFormCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // 促销名称
          _buildFormItem(
            label: '促销名称',
            required: true,
            child: TextField(
              controller: _billnameCtrl,
              enabled: !_disabled,
              decoration: const InputDecoration(
                hintText: '请输入',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 活动日期
          _buildTapSelectItem(
            label: '活动日期',
            text: (_startdate.isNotEmpty && _enddate.isNotEmpty) ? '$_startdate 至 $_enddate' : '',
            onTap: _pickDateRange,
            requiredField: true,
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 活动时间
          _buildTimeRangeItem(),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 促销机构
          _buildTapSelectItem(
            label: '促销机构',
            text: _mdstore,
            onTap: _selectStore,
            requiredField: true,
          ),
        ],
      ),
    );
  }

  /// 活动时间：开始时间 + 至 + 结束时间
  Widget _buildTimeRangeItem() {
    return _buildFormItem(
      label: '活动时间',
      required: true,
      child: Row(children: [
        Expanded(child: _buildTimeBox(_starttime, '请选择开始时间', _pickStartTime)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('至', style: TextStyle(fontSize: 13, color: Color(0xFF262626))),
        ),
        Expanded(child: _buildTimeBox(_endtime, '请选择结束时间', _pickEndTime)),
      ]),
    );
  }

  Widget _buildTimeBox(String value, String hint, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: _disabled ? null : Border.all(color: const Color(0xFFE2E2E2)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          value.isNotEmpty ? value : hint,
          style: TextStyle(
            fontSize: 13,
            color: value.isNotEmpty ? const Color(0xFF262626) : const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  /// 通用"点击选择"表单项：文本 + 右箭头
  Widget _buildTapSelectItem({
    required String label,
    required String text,
    required VoidCallback onTap,
    bool requiredField = false,
    bool enabled = true,
    String placeholder = '请选择',
  }) {
    final displayText = text.isNotEmpty ? text : placeholder;
    return _buildFormItem(
      label: label,
      required: requiredField,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              displayText,
              style: TextStyle(
                fontSize: 14,
                color: text.isNotEmpty ? const Color(0xFF333333) : const Color(0xFF9CA3AF),
              ),
            ),
            if (enabled) const Icon(Icons.chevron_right, size: 20, color: Color(0xFF999999)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormItem({
    required String label,
    required Widget child,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Row(children: [
              if (required)
                const Text('*', style: TextStyle(fontSize: 14, color: Color(0xFFEF4444))),
              Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ]),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  // ── 商品明细区域 ──
  /// 吸顶头部（对齐采购订货 _buildStickyHeader）：扫码输入框 + 商品明细标题栏（删除/扫描/新增）
  Widget _buildStickyHeader() {
    return Align(
      alignment: Alignment.topCenter,
      child: ColoredBox(
        color: const Color(0xFFF5F5F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 扫码框区域固定高度，内容顶部对齐（余量作为与标题栏的自然间距）
            SizedBox(
              height: _scanStickyHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(alignment: Alignment.topCenter, child: _buildScanInput()),
              ),
            ),
            // 标题栏固定高度，底边与明细卡片紧贴无间隙
            SizedBox(
              height: _stickyTitleHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildDetailTitleBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 商品明细标题栏（标题 + 删除/扫描/新增按钮），置于吸顶头部；
  /// 与下方明细卡片拼接，仅保留顶部圆角
  Widget _buildDetailTitleBar() {
    return Container(
      height: _stickyTitleHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
        border: Border(
          top: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
          left: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
          right: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('商品明细',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          Row(children: [
            _buildActionBtn('删除', const Color(0xFFEF4444), Icons.delete_outline, _toggleDelMode),
            const SizedBox(width: 8),
            _buildActionBtn('扫描', const Color(0xFF006EFF), Icons.qr_code_scanner, _scanBarcode),
            const SizedBox(width: 8),
            _buildActionBtn(
                '新增', const Color(0xFF006EFF), Icons.add_circle_outline, _selectProduct),
          ]),
        ],
      ),
    );
  }

  Widget _buildProductDetailSection() {
    // 可编辑态与吸顶标题栏拼接：仅底部圆角；详情态独立卡片全圆角
    final BorderRadius radius = _disabled
        ? BorderRadius.circular(10)
        : const BorderRadius.only(
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 详情态无吸顶头部时，卡片内保留标题
          if (_disabled)
            const Text('商品明细',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          if (_ptdetaillist.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
              ),
            )
          else
            ...List.generate(_ptdetaillist.length, (i) {
              return _buildProductCard(i);
            }),
        ],
      ),
    );
  }

  Widget _buildActionBtn(String label, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildProductCard(int index) {
    final item = _ptdetaillist[index];
    final name = item['productname']?.toString() ?? '';
    final sizeName = item['sizename']?.toString() ?? '';
    final sizeVal = item['size']?.toString() ?? '';
    final size = sizeName.isNotEmpty ? sizeName : sizeVal;
    final unitName = item['unitname']?.toString() ?? '';
    final unitVal = item['unit']?.toString() ?? '';
    final unit = unitName.isNotEmpty ? unitName : unitVal;
    final barcode = item['productbarcode']?.toString() ?? '';
    final sellprice = item['sellprice']?.toString() ?? '';
    final inprice = item['inprice']?.toString() ?? '';
    final isChecked = _delChecked.contains(index);
    final itempromotionflag = item['itempromotionflag']?.toString() == '1' ||
        item['itempromotionflag'] == true ||
        item['itempromotionflag'] == 1;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // 商品信息头部
          GestureDetector(
            onTap: () => _showProductDetail(index),
            child: Container(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isDelMode) ...[
                    Checkbox(
                      value: isChecked,
                      onChanged: (v) {
                        setState(() {
                          if (v ?? false) {
                            _delChecked.add(index);
                          } else {
                            _delChecked.remove(index);
                          }
                        });
                      },
                      activeColor: const Color(0xFF006EFF),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$name${size.isNotEmpty ? '/$size' : ''}${unit.isNotEmpty ? '($unit)' : ''}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
                        ),
                        const SizedBox(height: 4),
                        Text(barcode,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                        const SizedBox(height: 4),
                        Row(children: [
                          Text('原售价：${MathUtils.formatDecimal(2, sellprice)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                          const SizedBox(width: 16),
                          Text('原进价：${MathUtils.formatDecimal(2, inprice)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // 特价
          _buildPriceInputRow('特价', item, 'dcprice', 2),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 促销进货价
          _buildPriceInputRow('促销进货价', item, 'promotioninprice', 2),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 促销联营扣率
          _buildPriceInputRow('促销联营扣率', item, 'promotionjoinrate', 2),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 参与特价折扣促销
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('参与特价折扣促销', style: TextStyle(fontSize: 13, color: Color(0xFF333333))),
                Checkbox(
                  value: itempromotionflag,
                  onChanged: _disabled
                      ? null
                      : (v) {
                          setState(() {
                            item['itempromotionflag'] = (v ?? false) ? 1 : 0;
                          });
                        },
                  activeColor: const Color(0xFF006EFF),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceInputRow(String label, Map<String, dynamic> item, String field, int scale) {
    final ctrl = TextEditingController(text: item[field]?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
        ),
        Expanded(
          child: Builder(
            builder: (inputCtx) {
              return TextField(
                controller: ctrl,
                enabled: !_disabled,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                // 键盘弹出时预留滚动余量，确保输入框完整露出不被遮挡
                scrollPadding: const EdgeInsets.only(bottom: 120),
                onTap: () {
                  // 键盘弹出会压缩视口，等键盘动画结束后再滚动到输入框，
                  // 避免“点击时可见、键盘弹出后被遮挡”的时序问题
                  Future.delayed(const Duration(milliseconds: 350), () {
                    if (!inputCtx.mounted) return;
                    try {
                      Scrollable.ensureVisible(
                        inputCtx,
                        alignment: 0.6,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    } catch (_) {
                      // 页面已关闭、widget 已从树中移除（deactivated）时忽略
                    }
                  });
                },
                decoration: InputDecoration(
                  hintText: '请输入',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF006EFF)),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: (v) {
                  final formatted = MathUtils.formatDecimal(scale, v);
                  setState(() => item[field] = formatted);
                  ctrl.text = formatted;
                },
                onTapOutside: (_) {
                  final v = ctrl.text;
                  final formatted = MathUtils.formatDecimal(scale, v);
                  setState(() => item[field] = formatted);
                  ctrl.text = formatted;
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  // ── 底部操作按钮 ──
  Widget _buildBottomBar() {
    final bottom = MediaQuery.of(context).padding.bottom;

    // 批量删除模式
    if (_isDelMode) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 全选
            GestureDetector(
              onTap: _toggleAllDel,
              child: Row(children: [
                Checkbox(
                  value: _delChecked.length == _ptdetaillist.length,
                  onChanged: (_) => _toggleAllDel(),
                  activeColor: const Color(0xFF006EFF),
                  visualDensity: VisualDensity.compact,
                ),
                Text('全选，已选${_delChecked.length}个',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
              ]),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isDelMode = false;
                      _delChecked.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _confirmDelete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006EFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('删除'),
                ),
              ),
            ]),
          ],
        ),
      );
    }

    // 已审核：复制并新增
    if (_isSigned) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _copyAndNew,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('复制并新增'),
          ),
        ),
      );
    }

    // 编辑中（有单据ID且未审核/已驳回）
    if (_isEdit && !_isSigned) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Row(children: [
          // 删除按钮（signflag != 2 且 bolHandleTT）
          if (!_isRejected && _bolHandleTT)
            Expanded(
              child: OutlinedButton(
                onPressed: _delBill,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('删除'),
              ),
            ),
          if (!_isRejected && _bolHandleTT) const SizedBox(width: 8),
          // 保存按钮
          if (!_isRejected && (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT))) ...[
            Expanded(
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('保存'),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 审核按钮（已保存单据直接审核，对齐 Vue 独立审核 + 采购入库 _sign）
          if (!_isRejected && (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT))) ...[
            Expanded(
              child: ElevatedButton(
                onPressed: _sign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('审核'),
              ),
            ),
          ],
          // 已驳回时显示撤回按钮
          if (_isRejected)
            Expanded(
              child: ElevatedButton(
                onPressed: _restsignFn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('撤回'),
              ),
            ),
          // canWithdraw 撤回
          if (_canWithdraw) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _restsignFn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('撤回'),
              ),
            ),
          ],
        ]),
      );
    }

    // 新增
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('保存'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _saveAndAudit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('保存并审核'),
          ),
        ),
      ]),
    );
  }
}

/// 审批操作弹窗（通过/驳回 + 备注）
class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({this.defaultFlag = 1});
  final int defaultFlag;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late int _flag;
  final _remarkCtrl = TextEditingController();
  static const int _maxLength = 200;

  @override
  void initState() {
    super.initState();
    _flag = widget.defaultFlag;
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('单据审批', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            // ── 审批意见 ──
            Row(children: [
              const SizedBox(
                width: 14,
                child: Text('*',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, height: 1.2)),
              ),
              const Text('审批意见：', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => setState(() => _flag = 1),
                child: Row(children: [
                  _buildRadio(1),
                  const SizedBox(width: 6),
                  const Text('通过', style: TextStyle(fontSize: 14)),
                ]),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: () => setState(() => _flag = 0),
                child: Row(children: [
                  _buildRadio(0),
                  const SizedBox(width: 6),
                  const Text('驳回', style: TextStyle(fontSize: 14)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            // ── 备注/驳回原因 ──
            Row(children: [
              SizedBox(
                width: 14,
                child: _flag != 1
                    ? const Text('*',
                        style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, height: 1.2))
                    : null,
              ),
              Text(
                _flag == 1 ? '备注信息：' : '驳回原因：',
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _remarkCtrl,
              maxLines: 3,
              maxLength: _maxLength,
              decoration: InputDecoration(
                hintText: _flag == 1 ? '请输入备注信息' : '请输入驳回原因',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBFBFBF)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (_flag == 0 && _remarkCtrl.text.trim().isEmpty) {
                      Toast.show('驳回原因不能为空！');
                      return;
                    }
                    Navigator.pop(context, {
                      'reviewsignflag': _flag,
                      'reviewremark': _remarkCtrl.text.trim(),
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006EFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('确认'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildRadio(int value) {
    final isSelected = _flag == value;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC),
          width: 2,
        ),
        color: isSelected ? const Color(0xFF006EFF) : Colors.white,
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}

/// 审批日志弹窗（历史记录表格）
class _ApprovalLogSheet extends StatelessWidget {
  const _ApprovalLogSheet({
    required this.reviewBillFlows,
    required this.scrollController,
  });

  final List<Map<String, dynamic>> reviewBillFlows;
  final ScrollController scrollController;

  /// 操作文本（对齐 Vue getActionText）
  static String _actionText(dynamic v) {
    final s = v?.toString();
    if (s == '1') return '通过';
    if (s == '0') return '驳回';
    if (s == '2') return '撤回';
    return '待审';
  }

  /// 操作文字颜色（对齐 Vue getActionColor）
  static Color _actionColor(dynamic v) {
    final s = v?.toString();
    if (s == '1') return const Color(0xFF16A34A);
    if (s == '0') return const Color(0xFFDC2626);
    if (s == '2') return const Color(0xFFD97706);
    return const Color(0xFF6B7280);
  }

  /// 操作标签背景色（对齐 Vue getActionBg）
  static Color _actionBg(dynamic v) {
    final s = v?.toString();
    if (s == '1') return const Color(0xFFF0FDF4);
    if (s == '0') return const Color(0xFFFEF2F2);
    if (s == '2') return const Color(0xFFFFFBEB);
    return const Color(0xFFF3F4F6);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 标题栏（对齐 Vue close-box）──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
          ),
          child: Row(
            children: [
              const SizedBox(width: 40),
              const Expanded(
                child: Text('审核日志',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF999999)),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── 日志列表 ──
        Expanded(
          child: reviewBillFlows.isEmpty
              ? const Center(
                  child: Text('暂无审批记录', style: TextStyle(fontSize: 13, color: Color(0xFFBFBFBF))))
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: reviewBillFlows.length,
                  itemBuilder: (ctx, i) {
                    final item = reviewBillFlows[i];
                    final flag = item['reviewsignflag'];
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: i < reviewBillFlows.length - 1
                            ? const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 头部：序号 + 用户名 + 操作标签（标签紧跟用户名）
                          Row(children: [
                            // 蓝色序号徽章
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: const Color(0xFF006EFF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(item['username']?.toString() ?? '',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF333333))),
                            const SizedBox(width: 8),
                            // 操作标签（圆角药丸 + 彩色背景）
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _actionBg(flag),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(_actionText(flag),
                                  style: TextStyle(fontSize: 11, color: _actionColor(flag))),
                            ),
                          ]),
                          // 节点 + 时间（左缩进对齐用户名，对齐 Vue padding-left: 52rpx）
                          Padding(
                            padding: const EdgeInsets.only(left: 26, top: 3),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    '节点：${item['stepname']?.toString() ?? item['stepno']?.toString() ?? ''}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                                Text(
                                    item['signtime']?.toString() ??
                                        item['createtime']?.toString() ??
                                        '',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                              ],
                            ),
                          ),
                          // 备注（缩进对齐）
                          if ((item['reviewremark']?.toString() ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 3),
                              child: Text('备注：${item['reviewremark']}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 吸顶委托（对齐采购订货 _CgorderStickyDelegate）：
/// 扫码输入框 + 商品明细标题栏（删除/扫描/新增），初始位于表单与明细之间，滚动到顶部后粘住
class _ScanInputStickyDelegate extends SliverPersistentHeaderDelegate {
  _ScanInputStickyDelegate({required this.state});
  final _PromotionPlanEditPageState state;

  @override
  double get minExtent => _PromotionPlanEditPageState._stickyExtent;

  @override
  double get maxExtent => _PromotionPlanEditPageState._stickyExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader();
  }

  @override
  bool shouldRebuild(covariant _ScanInputStickyDelegate oldDelegate) => true;
}
