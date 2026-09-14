import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_batch.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/models/scan_settings.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/chain/receivingnote/search.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/load_image.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:flutter_deer/widgets/select_field_item.dart';
import 'package:sp_util/sp_util.dart';

enum _DeliverAction { none, save, sign, delete, retsign, print, withdraw }

/// 配送发货单编辑页（对齐 Vue chain/deliver/deliverEdit.vue）
class DeliverEditPage extends StatefulWidget {
  const DeliverEditPage({super.key, this.billData});

  final Map<String, dynamic>? billData;

  @override
  State<DeliverEditPage> createState() => _DeliverEditPageState();
}

class _DeliverEditPageState extends State<DeliverEditPage> with LogPageMixin<DeliverEditPage> {
  @override
  String get logPageName => _isEdit ? '配送发货单详情' : '配送发货单新增';

  // ---- 表单字段（对齐 Vue query） ----
  String? _outsid; // 配送中心
  String? _outstorename;
  String? _outcounterid; // 出库仓库
  String? _outcountername;
  String? _outcountertype;
  String? _insid; // 收货门店
  String? _instorename;
  String? _outhandlerid; // 发货经手人
  String? _outhandlername;
  String? _inhandlerid; // 收货经手人
  String? _inhandlername;
  String? _psname; // 送货员
  String? _psuserid;
  String? _yhbillid; // 要货申请单id
  String? _yhbillno; // 要货申请单号
  String? _yhremark; // 源单备注
  DateTime? _billdate; // 配送时间（默认今天）
  final TextEditingController _billdateController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();

  // ---- 当前登录机构 ----
  int? _myStoreType;
  int? _spid;
  String _myStoreId = '';

  // ---- PDA 扫码枪 ----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;

  _DeliverAction _submitAction = _DeliverAction.none;
  bool _detailLoading = false;

  late ScanSettings _scanSettings;

  bool _isSelectMode = false;
  Set<int> _selectedIndices = {};

  // ---- 多级审批 ----
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  String _userCode = '';
  String _userid = '';

  Map<String, dynamic>? _billData;
  String? _newBillid;
  List<Map<String, dynamic>> _fileLists = [];

  bool get _isEdit =>
      (_newBillid != null && _newBillid!.isNotEmpty) ||
      (widget.billData != null && (widget.billData!['billid']?.toString().isNotEmpty ?? false));
  bool get _isSigned => _billData?['signflag']?.toString() == '1';
  bool get _isRejected => _billData?['signflag']?.toString() == '2';
  bool get _isWithdrawPending => _billData?['reviewsignflag']?.toString() == '2';

  // =================== 多级审批 ===================
  bool get _isAdmin => _userCode == '1001';

  bool get _bolHandleT {
    if (_isAdmin) return true;
    return _reviewFlowUsers.any((item) => item['userid']?.toString() == _userid);
  }

  bool get _bolHandleTT {
    if (_isAdmin) return true;
    if (_reviewFlowUsers.isEmpty) return true;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return firstIndex <= 1;
  }

  bool get _bolHandleTTT {
    if (_isAdmin) return true;
    if (_reviewFlowUsers.isEmpty) {
      if (_reviewBillFlows.isEmpty) return true;
      return _reviewBillFlows.any((item) => item['userid']?.toString() == _userid);
    }
    return _reviewBillFlows.any((item) => item['userid']?.toString() == _userid);
  }

  /// 对齐 Vue disabled：signflag==1 || signflag==2 || (!permission("013103") && billid)
  bool get _readOnly {
    if (_isSigned || _isRejected) return true;
    if (_isEdit && !PermissionUtils.checkPermission('013103', showTip: false)) return true;
    return false;
  }

  final List<_DetailRow> _items = [];

  @override
  void initState() {
    super.initState();
    _scanSettings = ScanSettings.fromSp();
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          final scanCode = _scanController.text.trim();
          if (scanCode.isNotEmpty) {
            _scanDebounceTimer?.cancel();
            _handleScannedBarcode(scanCode, returnFocusNode: _scanFocusNode);
            _scanController.clear();
            _scanFocusNode.requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.hide');
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
        _handleScannedBarcode(code, returnFocusNode: _scanFocusNode);
        _scanController.clear();
        _scanFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      });
    });
    // 加载当前登录用户信息
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _userid = userMap['userid']?.toString() ?? '';
        _userCode = userMap['code']?.toString() ?? '';
      }
    } catch (_) {}
    // 加载当前登录机构
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _myStoreType = int.tryParse(storeMap['storetype']?.toString() ?? '');
        _spid = int.tryParse(storeMap['spid']?.toString() ?? '');
        _myStoreId = storeMap['id']?.toString() ?? '';
      }
    } catch (_) {}
    if (_isEdit) {
      _loadDetail();
    } else {
      _loadNewModeDefaults();
    }
    logEnter();
  }

  void _loadNewModeDefaults() {
    final now = DateTime.now();
    _billdate = now;
    _billdateController.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _scanDebounceTimer?.cancel();
    _billdateController.dispose();
    _remarkController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  // =================== 加载单据详情 ===================
  void _loadDetail([Map<String, dynamic>? overrideParams]) {
    setState(() => _detailLoading = true);
    final Map<String, dynamic> params =
        overrideParams ?? Map<String, dynamic>.from(widget.billData!);

    request(HttpApi.psstockoutGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _outsid = data['outsid']?.toString();
          _outstorename = data['outstorename']?.toString();
          _outcounterid = data['outcounterid']?.toString();
          _outcountername = data['outcountername']?.toString();
          _outcountertype = data['outcountertype']?.toString();
          _insid = data['insid']?.toString();
          _instorename = data['instorename']?.toString();
          // 对齐 Vue form fields：发货/收货经手人
          _outhandlerid = data['outhandlerid']?.toString();
          _outhandlername = data['outhandlername']?.toString();
          _inhandlerid = data['inhandlerid']?.toString();
          _inhandlername = data['inhandlername']?.toString();
          _psname = data['psname']?.toString();
          _psuserid = data['psuserid']?.toString();
          _yhbillid = data['yhbillid']?.toString();
          _yhbillno = data['yhbillno']?.toString();
          _remarkController.text = data['remark']?.toString() ?? '';
          _fileLists = (data['fileLists'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];

          // 配送时间
          final bdStr = data['billdate']?.toString() ?? '';
          final billStr = bdStr.contains(' ') ? bdStr.split(' ')[0] : bdStr;
          _billdate = DateTime.tryParse(billStr);
          _billdateController.text = billStr;

          // 多级审批数据
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);

          // 明细
          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            // 对齐 Vue：lspsprice = formatDecimal(2, price)
            c['lspsprice'] =
                MathUtils.formatDecimal(2, double.tryParse(c['price']?.toString() ?? '0') ?? 0);
            _applyWriteData(c);
            final row = _DetailRow();
            row.prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? '';
            row.barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            row.qtyController.text = c['qty']?.toString() ?? '';
            row.priceController.text = c['price']?.toString() ?? c['lspsprice']?.toString() ?? '';
            row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
            row.amtController.text = c['amt']?.toString() ?? '';
            row.batchno = c['batchno']?.toString() ?? '';
            row.batchController.text = c['batchno']?.toString() ?? '';
            row.rawData = c;
            _items.add(row);
          }
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  // =================== 提交保存 ===================
  void _submit({bool withSign = false}) {
    if (!PermissionUtils.checkPermission('013103', showTip: false)) {
      Toast.show('你无权保存配送发货单，请在后台修改权限');
      return;
    }
    logSave(_isEdit ? '保存修改' : (withSign ? '保存并审核' : '保存单据'));

    // 对齐 Vue save 校验顺序
    if (_items.isEmpty) {
      Toast.show('请选择商品');
      return;
    }
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择收货门店');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择配送中心');
      return;
    }
    if ((_outcounterid ?? '').isEmpty) {
      Toast.show('请选择出库仓库');
      return;
    }

    setState(() => _submitAction = _DeliverAction.save);

    final detaillist = _buildSubmitDetailList();
    double totalQty = 0;
    double totalAmt = 0;
    for (final item in detaillist) {
      totalQty = MathUtils.add(totalQty, double.tryParse(item['qty']?.toString() ?? '0') ?? 0);
      totalAmt = MathUtils.add(totalAmt, double.tryParse(item['amt']?.toString() ?? '0') ?? 0);
    }

    final Map<String, dynamic> params;
    if (_isEdit) {
      params = Map<String, dynamic>.from(_billData!);
    } else {
      params = {'signflag': 0};
    }
    params['outsid'] = _outsid ?? '';
    params['outstorename'] = _outstorename ?? '';
    params['outcounterid'] = _outcounterid ?? '';
    params['outcountername'] = _outcountername ?? '';
    params['outcountertype'] = _outcountertype ?? '';
    params['insid'] = _insid ?? '';
    params['instorename'] = _instorename ?? '';
    // 对齐 Vue form fields：发货/收货经手人
    params['outhandlerid'] = _outhandlerid ?? '';
    params['outhandlername'] = _outhandlername ?? '';
    params['inhandlerid'] = _inhandlerid ?? '';
    params['inhandlername'] = _inhandlername ?? '';
    params['psname'] = _psname ?? '';
    params['psuserid'] = _psuserid ?? '';
    params['yhbillid'] = _yhbillid ?? '';
    params['yhbillno'] = _yhbillno ?? '';
    params['yhremark'] = _yhremark ?? ''; // 源单备注（对齐 Vue query.yhremark）
    params['billdate'] = _billdateController.text;
    params['remark'] = _remarkController.text.trim();
    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt, 3);
    params['detaillist'] = detaillist;
    params['fileLists'] = _fileLists;

    request(HttpApi.psstockoutSave, params).then((result) {
      if (!mounted) return;
      final retData = result['data'];
      // 保存后进入多级审批流程时，不提示保存成功和接口返回信息
      final bool enterApproval = withSign &&
          retData is Map<String, dynamic> &&
          _parseReviewList(retData['reviewFlowUsers']).isNotEmpty;
      if (!enterApproval) {
        Toast.show(result['retmsg']?.toString() ?? '保存成功');
      }
      if (retData is Map<String, dynamic>) {
        final isNew = !_isEdit;
        if (isNew) {
          final String? newBillid = retData['billid']?.toString();
          if (newBillid != null && newBillid.isNotEmpty) {
            setState(() => _newBillid = newBillid);
          }
          // 对齐 cgplan _saveAndAudit：保存成功后先同步回写 retData 至 _billData，
          // 保证紧随其后的审核流程（_doSign）能取到单据数据；_loadDetail 随后以 getInfo 结果覆盖
          _billData = Map<String, dynamic>.from(retData);
        }
        _loadDetail(Map<String, dynamic>.from(retData));
        if (withSign && PermissionUtils.checkPermission('013105', showTip: false)) {
          _doSignAfterSave(retData);
        }
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliverAction.none);
    });
  }

  /// 保存后审核
  void _doSignAfterSave(Map<String, dynamic> savedData) {
    setState(() {
      _reviewFlowUsers = _parseReviewList(savedData['reviewFlowUsers']);
      _reviewBillFlows = _parseReviewList(savedData['reviewBillFlows']);
    });

    if (_reviewFlowUsers.isNotEmpty && !_bolHandleT) {
      Toast.show('您不属于当前审批节点的审核人！');
      return;
    }

    // 多级审批：新增/编辑单均弹出审批弹窗，确保进入审批节点流程（对齐 cgplan _doSignAfterSave）
    if (_reviewFlowUsers.isNotEmpty) {
      _showApprovalDialog().then((approvalResult) {
        if (approvalResult != null && mounted) {
          _billData?['reviewsignflag'] = approvalResult['reviewsignflag'];
          _billData?['reviewremark'] = approvalResult['reviewremark'];
          _doSign();
        }
      });
    } else {
      _doSign();
    }
  }

  /// 执行审核（对齐 Vue signApi）
  void _doSign() {
    if (_billData == null) return;
    final params = Map<String, dynamic>.from(_billData!);
    params['signflag'] = 1;
    params['reviewremark'] = _billData?['reviewremark']?.toString() ?? '';
    final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
    if (reviewsignflag != 2 && reviewsignflag != 0) {
      params['reviewsignflag'] = 1;
    }
    setState(() => _submitAction = _DeliverAction.sign);
    request(HttpApi.psstockoutSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliverAction.none);
    });
  }

  /// 反审核（对齐 Vue fsignFn）
  Future<void> _retsign() async {
    if (!PermissionUtils.checkPermission('013106', showTip: false)) {
      Toast.show('你无权反审核配送发货单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定反审核单据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _DeliverAction.retsign);
    final params = Map<String, dynamic>.from(_billData!);
    request(HttpApi.psstockoutRetsign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '反审成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliverAction.none);
    });
  }

  /// 撤回操作（对齐 Vue restsign：设置 reviewsignflag=2 后调用 save(1)）
  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('013105', showTip: false)) {
      Toast.show('你无权审核配送发货单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('撤回单据后，所有审批步骤需重新处理！是否撤回该配送发货单？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    // 对齐 Vue：query.value.reviewsignflag = 2 → save(1)
    // 直接调 sign API 绕过保存流程，避免 _doSignAfterSave 误弹审批弹窗
    setState(() => _submitAction = _DeliverAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.psstockoutSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliverAction.none);
    });
  }

  /// 删除单据（对齐 Vue delBill）
  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('013104', showTip: false)) {
      Toast.show('你无权删除配送发货单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
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
    if (confirm != true) return;

    setState(() => _submitAction = _DeliverAction.delete);
    final params = {'billid': _billData!['billid']};
    request(HttpApi.psstockoutDelBill, params).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliverAction.none);
    });
  }

  /// 打印单据（对齐 Vue menuid: '071301'）
  Future<void> _print() async {
    if (!PermissionUtils.checkPermission('013107', showTip: false)) {
      Toast.show('你无权打印配送发货单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    setState(() => _submitAction = _DeliverAction.print);
    request(HttpApi.psstockoutPrint, {
      'menuid': '071301',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliverAction.none);
    });
  }

  /// 附件（对齐 Vue openAttach：menuid '071301'）
  Future<void> _openAttach() async {
    final result = await AttachPage.show(
      context,
      fileLists: _fileLists,
      menuid: '071301',
      billid: _billData?['billid']?.toString() ?? _newBillid ?? '',
      billno: _billData?['billno']?.toString() ?? '',
    );
    if (result != null && mounted) {
      setState(() => _fileLists = result);
    }
  }

  // =================== 机构选择 ===================
  /// 选择配送中心（对齐 Vue deliver/edit.vue store-form-item）
  Future<void> _selectOutStore() async {
    final result = await SelectStorePage.show(
      context,
      title: '选择配送中心',
      initialSelectedId: _outsid,
      nostoreid: _insid,
      // 对齐 Vue :mergeData="{ stopflag: 0, storetypes: [0, 3], psselecttype: 2, insid: form.insid }" + isLs
      storetypes: const [0, 3],
      stopflag: '0',
      psselecttype: '2',
      insid: _insid,
      isLs: true,
      // 对齐 Vue :oneself="isPsStore" → sids: [登录机构id]（配送中心登录仅查自己）
      sids: _myStoreType == 3 && _myStoreId.isNotEmpty ? [int.tryParse(_myStoreId) ?? 0] : null,
    );
    if (result != null && mounted) {
      setState(() {
        _outsid = result['storeid']?.toString() ?? '';
        _outstorename = result['storename']?.toString() ?? '';
        // 对齐 Vue selectStore1：清空出库仓库
        _outcounterid = null;
        _outcountername = null;
        _outcountertype = null;
      });
      // 对齐 PC 版 deliver/edit.vue @confirm 中 wareRef?.refreshFn()：自动带出默认出库仓库
      _autoFillDefaultOutCounter();
    }
  }

  /// 对齐 PC 版 deliver/edit.vue warehouse.vue isCurrentOutflag 机制：已选配送中心且出库仓库为空时，
  /// 自动带出该配送中心的默认出库仓库（按 countertype 优先级取：零售(0) > 常温(1) > 冷藏(2) > 冷冻(3)），
  /// 无可用仓库则保持为空待手动选择；区域中心（storetype==4）登录不自动带出
  Future<void> _autoFillDefaultOutCounter() async {
    final String outsid = _outsid ?? '';
    if (outsid.isEmpty || (_outcounterid ?? '').isNotEmpty) return;
    // 对齐 Vue warehouse.vue：userStore().store.storetype != 4 才自动赋值
    if (_myStoreType == 4) return;
    try {
      final result = await request(HttpApi.counterGetList, {
        'sids': [int.tryParse(outsid) ?? 0],
        // 'nosidsflag': 1,
        'stopflag': 0,
        // 对齐 Vue wareFormItem mergeData：总店作为配送中心时仅查配送仓
        // 'pscounterflag': outsid == _spid.toString() ? '1' : '',
        // 'field': 'countercode',
        // 'type': 'asc',
        // 'cond': '',
        // 对齐 Vue warehouse.vue is_page: '0'：全量拉取后本地筛选默认出库仓
        'is_page': 0,
      });
      if (!mounted || _outsid != outsid) return;
      final data = result['data'];
      final list =
          data is Map<String, dynamic> ? (data['list'] as List? ?? const []) : const <dynamic>[];
      // 筛选默认出库仓库（stockoutflag==1），按 countertype 优先级取默认仓库：
      // 零售(0) > 常温(1) > 冷藏(2) > 冷冻(3)，无类型字段的排在最后
      final matches = list
          .whereType<Map<String, dynamic>>()
          .where((e) => e['stockoutflag']?.toString() == '1')
          .toList();
      if (matches.isEmpty) return;
      matches.sort((a, b) {
        final va = int.tryParse(a['countertype']?.toString() ?? '');
        final vb = int.tryParse(b['countertype']?.toString() ?? '');
        if (va == null && vb == null) return 0;
        if (va == null) return 1; // 无类型排最后
        if (vb == null) return -1;
        return va.compareTo(vb);
      });
      if (!mounted || _outsid != outsid) return;
      final first = matches.first;
      setState(() {
        _outcounterid = first['counterid']?.toString() ?? '';
        _outcountername = first['countername']?.toString() ?? '';
        _outcountertype = first['countertype']?.toString() ?? '';
      });
    } catch (_) {
      // 自动带出失败不影响配送中心选择，用户仍可手动选择出库仓库
    }
  }

  /// 选择收货门店（对齐 Vue deliver/edit.vue store-form-item）
  Future<void> _selectInStore() async {
    final result = await SelectStorePage.show(
      context,
      title: '选择收货门店',
      initialSelectedId: _insid,
      nostoreid: _outsid,
      // 对齐 Vue :mergeData="{ stopflag: 0, storetypes: [0, 1, 2], psselecttype: 2, outsid: form.outsid }" + isLs
      storetypes: const [0, 1, 2],
      stopflag: '0',
      psselecttype: '2',
      outsid: _outsid,
      isLs: true,
    );
    if (result != null && mounted) {
      setState(() {
        _insid = result['storeid']?.toString() ?? '';
        _instorename = result['storename']?.toString() ?? '';
      });
    }
  }

  // =================== 经手人选择（对齐 Vue handler-form-item） ===================
  /// 选择发货经手人（对齐 Vue mergeData: { sids: form.outsid }）
  Future<void> _selectOutHandler() async {
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请先选择配送中心');
      return;
    }
    final result = await CommonSelectSheet.show(
      context,
      title: '选择发货经手人',
      searchHint: '输入经手人名称/编码',
      initialSelectedId: _outhandlerid,
      idField: 'userid',
      fetchData: (searchText, page) => request(HttpApi.sysUserList, {
        'cond': searchText,
        'sids': [_outsid],
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (item) => item,
    );
    if (result != null && mounted) {
      setState(() {
        _outhandlerid = result['userid']?.toString() ?? '';
        _outhandlername = result['name']?.toString() ?? '';
      });
    }
  }

  /// 选择收货经手人（对齐 Vue mergeData: { sids: form.insid }）
  Future<void> _selectInHandler() async {
    if ((_insid ?? '').isEmpty) {
      Toast.show('请先选择收货门店');
      return;
    }
    final result = await CommonSelectSheet.show(
      context,
      title: '选择收货经手人',
      searchHint: '输入经手人名称/编码',
      initialSelectedId: _inhandlerid,
      idField: 'userid',
      fetchData: (searchText, page) => request(HttpApi.sysUserList, {
        'cond': searchText,
        'sids': [_insid],
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (item) => item,
    );
    if (result != null && mounted) {
      setState(() {
        _inhandlerid = result['userid']?.toString() ?? '';
        _inhandlername = result['name']?.toString() ?? '';
      });
    }
  }

  /// 选择出库仓库（对齐 Vue openGodown + selectGodownFn）
  Future<void> _selectOutCounter() async {
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请先选择配送中心');
      return;
    }
    final result = await CommonSelectSheet.show(
      context,
      title: '选择出库仓库',
      searchHint: '输入仓库名称/编码',
      initialSelectedId: _outcounterid,
      nameField: 'countername',
      codeField: 'countercode',
      idField: 'counterid',
      fetchData: (searchText, page) => request(HttpApi.counterGetList, {
        'sids': [int.tryParse(_outsid ?? '') ?? 0],
        'nosidsflag': 1,
        'stopflag': 0,
        // 对齐 Vue wareFormItem mergeData + selectWarehouse queryD
        'pscounterflag': _outsid == _spid.toString() ? '1' : '',
        'field': 'countercode',
        'type': 'asc',
        'cond': searchText,
        'is_page': 1,
        'page': page,
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (item) => item,
    );
    if (result != null && mounted) {
      setState(() {
        _outcounterid = result['counterid']?.toString() ?? '';
        _outcountername = result['countername']?.toString() ?? '';
        _outcountertype = result['countertype']?.toString() ?? '';
        // 对齐 Vue selectGodownFn：清空商品明细
        for (final row in _items) {
          row.dispose();
        }
        _items.clear();
      });
    }
  }

  /// 选择送货员（对齐 Vue selectCom sysuser/findList）
  Future<void> _selectDeliveryPerson() async {
    final result = await CommonSelectSheet.show(
      context,
      title: '选择送货员',
      searchHint: '输入送货员名称/编码',
      initialSelectedId: _psuserid,
      idField: 'userid',
      fetchData: (searchText, page) => request('sysuser/findList', {
        'cond': searchText,
        // 对齐 Vue selectHandler queryDefault：field: createtime, type: asc, stopflag: ''
        'field': 'createtime',
        'type': 'asc',
        'stopflag': '',
        'is_page': 1,
        'page': page,
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (item) => item,
    );
    if (result != null && mounted) {
      setState(() {
        _psuserid = result['userid']?.toString() ?? '';
        _psname = result['name']?.toString() ?? '';
      });
    }
  }

  /// 选择要货申请单（对齐 Vue jumpPge('yhsq')）
  Future<void> _selectYhApply() async {
    // 对齐 Vue：需要先选配送中心、收货门店、出库仓库
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择配送中心');
      return;
    }
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择收货门店');
      return;
    }
    if ((_outcounterid ?? '').isEmpty) {
      Toast.show('请选择出库仓库');
      return;
    }
    if (_items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提示'),
          content: const Text('选择要货申请单会清空当前商品，是否继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      );
      if (confirm != true) return;
    }
    // 导航到要货申请列表选择（共用查询/选择页：yhorder/findList + 要货申请卡片）
    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceivingnoteSearchPage(
          isSelect: true,
          billType: SearchBillType.enquiry,
          mergData: {
            if ((_outsid ?? '').isNotEmpty) 'outsid': _outsid ?? '',
            if ((_insid ?? '').isNotEmpty) 'insid': _insid ?? '',
            if ((_instorename ?? '').isNotEmpty) 'instorename': _instorename ?? '',
            if ((_outstorename ?? '').isNotEmpty) 'outstorename': _outstorename ?? '',
          },
        ),
      ),
    );
    if (result != null && mounted) {
      _loadFromYhApply(result);
    }
  }

  /// 从要货申请单加载数据（对齐 Vue getYhInfo）
  void _loadFromYhApply(Map<String, dynamic> orderData) {
    final billid = orderData['billid']?.toString() ?? '';
    final sid = orderData['sid']?.toString() ?? '';
    if (billid.isEmpty) return;
    request(HttpApi.yhorderGetInfo, {'billid': billid, 'sid': sid}).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is! Map<String, dynamic>) return;
      setState(() {
        _yhbillid = data['billid']?.toString() ?? '';
        _yhbillno = data['billno']?.toString() ?? '';
        _insid = data['insid']?.toString() ?? '';
        _instorename = data['instorename']?.toString() ?? '';
        _yhremark = data['remark']?.toString() ?? '';

        // 明细 - 对齐 Vue：过滤 memorytype == countertype
        for (final row in _items) {
          row.dispose();
        }
        _items.clear();
        final list = data['detaillist'] as List? ?? [];
        for (final v in list) {
          if (v is! Map) continue;
          final c = Map<String, dynamic>.from(v);
          // 对齐 Vue handleProperty
          c['productname'] = c['name']?.toString() ?? c['productname']?.toString() ?? '';
          c['yhqty'] =
              MathUtils.formatDecimal(1, double.tryParse(c['qty']?.toString() ?? '0') ?? 0);
          c['qty'] = c['yhqty'];
          c['price'] =
              MathUtils.formatDecimal(2, double.tryParse(c['lspsprice']?.toString() ?? '0') ?? 0);
          c['diffqty'] = MathUtils.formatDecimal(1, 0);
          c['amt'] = MathUtils.formatDecimal(3, double.tryParse(c['amt']?.toString() ?? '0') ?? 0);
          _applyWriteData(c);

          final row = _DetailRow();
          row.prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? '';
          row.barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
          row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
          row.qtyController.text = c['qty']?.toString() ?? '';
          row.priceController.text = c['price']?.toString() ?? '';
          row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
          row.amtController.text = c['amt']?.toString() ?? '';
          row.batchno = c['batchno']?.toString() ?? '';
          row.batchController.text = c['batchno']?.toString() ?? '';
          row.rawData = c;
          _items.add(row);
        }
      });
    });
  }

  // =================== 商品选择与扫码 ===================
  Future<void> _selectProducts() async {
    // 对齐 Vue selectProductFn 校验
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择收货门店');
      return;
    }
    if ((_outcounterid ?? '').isEmpty) {
      Toast.show('请选择出库仓库');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择配送中心');
      return;
    }
    final result = await _openSelectProductPage();
    if (result != null && mounted) {
      _applySelectedProducts(result);
    }
  }

  /// 打开选择商品页（扫码命中多条商品时以 initialKeyword 自动粘贴条码搜索）
  Future<List<Map<String, dynamic>>?> _openSelectProductPage({String? keyword}) {
    return Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          mergData: {
            'insid': _insid ?? '',
            'outsid': _outsid ?? '',
            'counterid': _outcounterid ?? '',
            'pspriceflag': 1,
            'memorytype': _outcountertype ?? '',
          },
          multiple: true,
          showSelectedCount: true,
          selectList: _items.map((r) => r.rawData ?? <String, dynamic>{}).toList(),
          paramJust: const [
            'qty',
            'jsqty',
            'batch',
            'billdate',
            'birthdate',
            'unit',
            'size',
            'remark',
            'batchno',
            'outstockqty',
            'instockqty',
            'psamt'
          ],
          // 带入扫描条码：选择页首次加载即按该条码搜索，展示全部命中商品供用户挑选
          initialKeyword: keyword,
        ),
      ),
    );
  }

  /// 选择页确认后整体回填明细（对齐 Vue onSelectProduct：选择页已选区含当前明细）
  void _applySelectedProducts(List<Map<String, dynamic>> result) {
    setState(() {
      for (final row in _items) {
        row.dispose();
      }
      _items.clear();
      for (final prod in result) {
        final c = Map<String, dynamic>.from(prod);
        // 对齐 Vue handleProperty：price = lspsprice
        c['price'] =
            MathUtils.formatDecimal(2, double.tryParse(c['lspsprice']?.toString() ?? '0') ?? 0);
        _applyWriteData(c);
        final row = _DetailRow()
          ..prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? ''
          ..barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? ''
          ..nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? ''
          ..qtyController.text = c['qty']?.toString() ?? '0'
          ..priceController.text = c['price']?.toString() ?? '0'
          ..batchController.text = c['batchno']?.toString() ?? ''
          ..rawData = c;
        row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
        row.amtController.text = c['amt']?.toString() ?? '';
        row.batchno = c['batchno']?.toString() ?? '';
        _items.add(row);
      }
    });
  }

  /// 扫描条码命中多条商品时进入选择商品页（避免误取第一条），
  /// 用户挑选确认后焦点交还扫码输入框，便于 PDA 连续录入
  Future<void> _pickFromMultiple(String code, {FocusNode? returnFocusNode}) async {
    final result = await _openSelectProductPage(keyword: code);
    if (!mounted) return;
    if (result != null) {
      _applySelectedProducts(result);
    }
    // 无论确认/取消，均将焦点交还扫码输入框，便于 PDA 连续录入
    if (returnFocusNode != null && mounted) {
      returnFocusNode.requestFocus();
    }
  }

  Future<void> _scanBarcode() async {
    if (Device.isMobile) {
      NavigatorUtils.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final Object? code = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
      );
      if (code == null || !mounted) return;
      _handleScannedBarcode(code.toString());
    } else {
      Toast.show('当前平台暂不支持扫码');
    }
  }

  void _handleScannedBarcode(String code, {FocusNode? returnFocusNode}) {
    if (code.trim().isEmpty) return;
    // 对齐 Vue scanFn 校验
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择收货门店');
      return;
    }
    if ((_outcounterid ?? '').isEmpty) {
      Toast.show('请选择出库仓库');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择配送中心');
      return;
    }

    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;

    request(HttpApi.productGetList, {
      'barcode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      'insid': _insid ?? '',
      'outsid': _outsid ?? '',
      'pspriceflag': 1,
      'counterid': _outcounterid ?? '',
      'memorytype': _outcountertype ?? '',
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isEmpty) {
        Toast.show('未查询到该商品');
        return;
      }
      if (list.length > 1) {
        // 同一(秤)条码命中多条商品时无法自动确定目标：
        // 进入选择商品页并将条码粘贴到搜索框自动搜索，供用户挑选
        _pickFromMultiple(searchCode, returnFocusNode: returnFocusNode);
        return;
      }
      final prod = list.first as Map<String, dynamic>;
      final c = Map<String, dynamic>.from(prod);
      double qty = double.tryParse(c['qty']?.toString() ?? '0') ?? 0;
      if (scaleInfo?.type == 'weight') {
        qty = scaleInfo!.qty ?? qty + 1;
      } else if (scaleInfo?.type == 'amount') {
        final price =
            double.tryParse(c['lspsprice']?.toString() ?? c['price']?.toString() ?? '0') ?? 0;
        if (price > 0) {
          qty = MathUtils.divide(scaleInfo!.amount ?? 0, price);
        } else {
          qty = qty + 1;
        }
      } else {
        qty = qty + 1;
      }
      c['qty'] = MathUtils.formatDecimal(1, qty);
      // 对齐 Vue scanFn：price = formatDecimal(2, lspsprice || 0)
      c['price'] =
          MathUtils.formatDecimal(2, double.tryParse(c['lspsprice']?.toString() ?? '0') ?? 0);
      _applyWriteData(c);

      final prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? '';
      final barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
      final existing =
          _items.indexWhere((r) => r.prodid == prodid && (barcode.isEmpty || r.barcode == barcode));

      setState(() {
        if (existing >= 0) {
          _items[existing].qtyController.text = c['qty']?.toString() ?? '';
          _items[existing].priceController.text = c['price']?.toString() ?? '';
          _items[existing].amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
          _items[existing].amtController.text = c['amt']?.toString() ?? '';
          _items[existing].rawData = c;
        } else {
          final row = _DetailRow()
            ..prodid = prodid
            ..barcode = barcode
            ..nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? ''
            ..qtyController.text = c['qty']?.toString() ?? '0'
            ..priceController.text = c['price']?.toString() ?? '0'
            ..batchController.text = c['batchno']?.toString() ?? ''
            ..rawData = c;
          row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
          row.amtController.text = c['amt']?.toString() ?? '';
          row.batchno = c['batchno']?.toString() ?? '';
          _items.insert(0, row);
        }
      });

      if (returnFocusNode != null && mounted) {
        returnFocusNode.requestFocus();
      }
    }).catchError((_) {
      if (mounted) Toast.show('查询商品失败');
    });
  }

  // =================== 明细数据处理 ===================
  /// 对齐 Vue writeData：qty 变化时重算 jsqty/amt（用 price 配送价计算）
  static void _applyWriteData(Map<String, dynamic> row) {
    final qty = double.tryParse(row['qty']?.toString() ?? '0') ?? 0;
    final packagenum = double.tryParse(row['packagenum']?.toString() ?? '1') ?? 1;
    row['jsqty'] =
        MathUtils.formatDecimal(1, MathUtils.divide(qty, packagenum == 0 ? 1 : packagenum));
    row['qty'] = MathUtils.formatDecimal(1, qty);
    // 对齐 Vue：amt = qty * price（配送价）
    final price = double.tryParse(row['price']?.toString() ?? '0') ?? 0;
    final amt = MathUtils.formatDecimal(3, MathUtils.mul(qty, price));
    row['amt'] = amt;
    // 对齐 Vue：diffqty = yhqty - qty
    final yhqty = double.tryParse(row['yhqty']?.toString() ?? '0') ?? 0;
    row['diffqty'] = MathUtils.formatDecimal(1, MathUtils.subtract(yhqty, qty));
    row['sellamt'] = MathUtils.formatDecimal(
        3, MathUtils.mul(qty, double.tryParse(row['sellprice']?.toString() ?? '0') ?? 0));
  }

  void _recalcRowAmt(_DetailRow row) {
    final qty = double.tryParse(row.qtyController.text) ?? 0;
    final price = double.tryParse(row.priceController.text) ?? 0;
    row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    row.amtController.text = MathUtils.formatDecimal(3, row.amt);
    if (row.rawData != null) {
      row.rawData!['amt'] = row.amt;
      row.rawData!['price'] = price;
    }
  }

  void _syncAllAmt() {
    for (final row in _items) {
      _recalcRowAmt(row);
    }
  }

  List<Map<String, dynamic>> _buildSubmitDetailList() {
    _syncAllAmt();
    return _items.map((row) {
      final qty = MathUtils.formatDecimalNum(1, double.tryParse(row.qtyController.text) ?? 0);
      final price = MathUtils.formatDecimalNum(2, double.tryParse(row.priceController.text) ?? 0);
      final item =
          row.rawData != null ? Map<String, dynamic>.from(row.rawData!) : <String, dynamic>{};
      final packagenum = double.tryParse(item['packagenum']?.toString() ?? '1') ?? 1;
      item['productname'] = row.nameController.text.trim();
      item['prodname'] = row.nameController.text.trim();
      item['qty'] = qty;
      item['price'] = price;
      item['jsqty'] =
          MathUtils.formatDecimalNum(1, MathUtils.divide(qty, packagenum == 0 ? 1 : packagenum));
      item['amt'] = MathUtils.formatDecimalNum(
          3, double.tryParse(row.amtController.text) ?? row.amt ?? MathUtils.mul(qty, price));
      item['prodid'] = row.prodid ?? item['productid'] ?? '';
      item['productid'] = item['productid'] ?? row.prodid ?? '';
      item['unit'] = row.rawData?['unit']?.toString() ?? '';
      item['size'] = row.rawData?['size']?.toString() ?? '';
      item['unitonlyid'] = row.rawData?['unitonlyid']?.toString() ?? '';
      item['sizeonlyid'] = row.rawData?['sizeonlyid']?.toString() ?? '';
      return item;
    }).toList();
  }

  // =================== 汇总 ===================
  String get _totalQty {
    double sum = 0;
    for (final row in _items) {
      sum = MathUtils.add(sum, double.tryParse(row.qtyController.text) ?? 0);
    }
    return MathUtils.formatDecimal(1, sum);
  }

  String get _totalAmt {
    double sum = 0;
    for (final row in _items) {
      if (row.amt != null) {
        sum = MathUtils.add(sum, row.amt!);
      } else {
        final qty = double.tryParse(row.qtyController.text) ?? 0;
        final price = double.tryParse(row.priceController.text) ?? 0;
        sum = MathUtils.add(sum, MathUtils.mul(qty, price));
      }
    }
    return MathUtils.formatDecimal(3, sum);
  }

  // =================== 批量选择删除 ===================
  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) _selectedIndices.clear();
    });
  }

  void _toggleIndex(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  bool get _isAllSelected => _items.isNotEmpty && _selectedIndices.length == _items.length;

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedIndices.clear();
      } else {
        _selectedIndices = Set<int>.from(List.generate(_items.length, (i) => i));
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIndices.isEmpty) return;
    final count = _selectedIndices.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text('确定删除$count条数据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      final sorted = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
      for (final i in sorted) {
        _items[i].dispose();
        _items.removeAt(i);
      }
      _selectedIndices.clear();
      _isSelectMode = false;
    });
  }

  // =================== 审批相关 ===================
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

  Future<Map<String, dynamic>?> _showApprovalDialog({int defaultFlag = 1}) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ApprovalDialog(defaultFlag: defaultFlag),
    );
  }

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

  // =================== Build ===================
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
          _isEdit ? (_isSigned ? '配送发货单详情' : (_isRejected ? '配送发货单详情' : '修改配送发货单')) : '新增配送发货单',
          style:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return Column(children: [
      Expanded(
          child: CustomScrollView(cacheExtent: 800, slivers: [
        if (_isEdit)
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), child: _buildBillStatusWidget())),
        if (_isEdit && (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty))
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), child: _buildApprovalNodeCard())),
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _buildCard(
                    title: '单据信息',
                    child: _readOnly ? _buildBillInfoReadonly() : _buildBillInfoEditable()))),
        // 粘性表头：扫描框 + 商品明细标题栏（固定不随商品列表滚动）
        PinnedHeaderSliver(
            child: ColoredBox(
                color: const Color(0xFFF5F5F5),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_showScanInput) ...[
                    Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), child: _buildScanInput()),
                    const SizedBox(height: 8),
                  ],
                  Padding(
                      padding: EdgeInsets.fromLTRB(8, _showScanInput ? 0 : 10, 8, 0),
                      child: _buildProductHeader())
                ]))),
        if (_items.isNotEmpty)
          SliverList.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) => RepaintBoundary(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _DetailItem(
                          row: _items[index],
                          index: index,
                          isSelectMode: _isSelectMode,
                          isSelected: _selectedIndices.contains(index),
                          readOnly: _readOnly,
                          bsid: _outsid ?? '',
                          counterid: _outcounterid ?? '',
                          insid: _insid ?? '',
                          outsid: _outsid ?? '',
                          onToggle: () => _toggleIndex(index),
                          onChanged: () => setState(() {}))))),
        if (_items.isEmpty)
          const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    LoadAssetImage('state/zwsp', width: 80, height: 80),
                    SizedBox(height: 12),
                    Text('暂无商品明细', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))
                  ])))),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ])),
      if (!keyboardVisible) _buildBottomBar(),
    ]);
  }

  /// 是否显示红外条码扫描输入框（未审核 + 扫码设置开启红外输入）
  bool get _showScanInput => !_isSigned && _scanSettings.showInfraredInput;

  // =================== 条码扫描输入框（对齐 allot_apply） ===================
  Widget _buildScanInput() {
    return Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
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
              )),
            ])));
  }

  Widget _buildProductHeader() {
    return Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                        color: const Color(0xFF006EFF), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('商品明细',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
                GestureDetector(
                    onTap: _openAttach,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.attach_file, size: 15, color: Color(0xFF6B7280)),
                      const SizedBox(width: 2),
                      Text('附件(${_fileLists.length})',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500))
                    ])),
                if (!_readOnly) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                      onTap: _toggleSelectMode,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_isSelectMode ? Icons.close : Icons.delete_outline,
                            size: 17,
                            color:
                                _isSelectMode ? const Color(0xFF6B7280) : const Color(0xFFFF4D4F)),
                        const SizedBox(width: 2),
                        Text(_isSelectMode ? '取消' : '删除',
                            style: TextStyle(
                                fontSize: 12,
                                color: _isSelectMode
                                    ? const Color(0xFF6B7280)
                                    : const Color(0xFFFF4D4F),
                                fontWeight: FontWeight.w500))
                      ])),
                  const SizedBox(width: 10),
                  if (_scanSettings.showCameraButton) ...[
                    GestureDetector(
                        onTap: _scanBarcode,
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          BossSvgIcon(svgFile: 'scan.svg', size: 12),
                          SizedBox(width: 2),
                          Text('扫描',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF006EFF),
                                  fontWeight: FontWeight.w500))
                        ])),
                    const SizedBox(width: 10)
                  ],
                  GestureDetector(
                      onTap: _selectProducts,
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF006EFF)),
                        SizedBox(width: 2),
                        Text('新增',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF006EFF),
                                fontWeight: FontWeight.w500))
                      ])),
                ],
              ])),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
        ]));
  }

  Widget _buildBillStatusWidget() {
    final data = _billData ?? {};
    final String billno = data['billno']?.toString() ?? '-';
    final String createtime = data['createtime']?.toString() ?? '-';
    final String createname = data['createname']?.toString() ?? '';
    final String signflag = data['signflag']?.toString() ?? '';
    String statusLabel = '待审核';
    Color statusColor = const Color(0xFFD54B5A);
    if (signflag == '1') {
      statusLabel = '已审核';
      statusColor = const Color(0xFF00A870);
    } else if (signflag == '2') {
      statusLabel = '已驳回';
      statusColor = const Color(0xFFFF9900);
    } else if (signflag == '-1') {
      statusLabel = '已作废';
      statusColor = const Color(0xFFAAAAAA);
    }
    final String signtime = data['signtime']?.toString() ?? '';
    final String signname = data['signname']?.toString() ?? '';
    return _buildCard(
        title: '单号：$billno',
        titleRight: Text(statusLabel,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text('制单信息：$createtime',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                Text(createname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))
              ]),
              if (signflag == '1' && (signtime.isNotEmpty || signname.isNotEmpty)) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                      child: Text('审核信息：$signtime',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                  Text(signname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))
                ])
              ],
            ])));
  }

  Widget _buildApprovalNodeCard() {
    String currentInfo = '';
    if (_reviewFlowUsers.isNotEmpty) {
      final n = _reviewFlowUsers[0];
      currentInfo = '当前在第${n['index'] ?? '1'}节点【${n['stepname'] ?? ''}】';
      final u = n['username']?.toString() ?? '';
      if (u.isNotEmpty) currentInfo += '，审批人:$u';
    } else if (_reviewBillFlows.isNotEmpty) {
      final n = _reviewBillFlows[0];
      currentInfo = '节点【${n['stepname'] ?? ''}】';
      final u = n['username']?.toString() ?? '';
      if (u.isNotEmpty) currentInfo += '，审批人:$u';
    }
    final totalNodes = _reviewFlowUsers.isNotEmpty
        ? int.tryParse(_reviewFlowUsers[0]['allindex']?.toString() ?? '0') ?? 0
        : 0;
    return Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB))),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('审核日志',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
            if (totalNodes > 0)
              Text('共$totalNodes个审批节点',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888)))
          ]),
          const SizedBox(height: 10),
          if (currentInfo.isNotEmpty)
            Row(children: [
              Expanded(
                  child: Text(currentInfo,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
              GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))))
            ])
          else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('等待审核中...', style: TextStyle(fontSize: 13, color: Color(0xFFBFBFBF))),
              GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))))
            ]),
        ]));
  }

  Widget _buildBillInfoReadonly() {
    return Column(children: [
      _buildReadonlyField(label: '配送中心', value: '${_outstorename ?? ''}-${_outcountername ?? ''}'),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '收货门店', value: _instorename ?? ''),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '配送时间', value: _billdateController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '要货申请单', value: _yhbillno ?? ''),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '发货经手人', value: _outhandlername ?? ''),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '收货经手人', value: _inhandlername ?? ''),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '送货员', value: _psname ?? ''),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '备注', value: _remarkController.text),
    ]);
  }

  Widget _buildBillInfoEditable() {
    // 左侧标签文字宽度在原 80 基础上增加 1/3（80*4/3≈107），避免"配送中心仓库"等长标签折行
    const double labelWidth = 107;
    return Column(children: [
      SelectFieldItem(
          label: '配送中心',
          labelWidth: labelWidth,
          required: true,
          value: _outstorename ?? '',
          onTap: _selectOutStore),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '出库仓库',
          labelWidth: labelWidth,
          required: true,
          value: _outcountername ?? '',
          onTap: _selectOutCounter),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '收货门店',
          labelWidth: labelWidth,
          required: true,
          value: _instorename ?? '',
          onTap: _selectInStore),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '配送时间',
          labelWidth: labelWidth,
          value: _billdateController.text,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
                context: context,
                initialDate: _billdate ?? now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 5),
                locale: const Locale('zh', 'CN'));
            if (picked != null && mounted)
              setState(() {
                _billdate = picked;
                _billdateController.text =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              });
          }),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '要货申请单', labelWidth: labelWidth, value: _yhbillno ?? '', onTap: _selectYhApply),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      // 对齐 Vue handler-form-item：发货经手人（依赖配送中心，未选时点击提示）
      SelectFieldItem(
          label: '发货经手人',
          labelWidth: labelWidth,
          value: _outhandlername ?? '',
          onTap: _selectOutHandler),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      // 对齐 Vue handler-form-item：收货经手人（依赖收货门店，未选时点击提示）
      SelectFieldItem(
          label: '收货经手人',
          labelWidth: labelWidth,
          value: _inhandlername ?? '',
          onTap: _selectInHandler),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '送货员', labelWidth: labelWidth, value: _psname ?? '', onTap: _selectDeliveryPerson),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildField(controller: _remarkController, label: '备注', hint: '请输入备注信息'),
    ]);
  }

  Widget _buildBottomBar() {
    if (_isSelectMode) return _buildBatchDeleteBar();
    return Container(
        color: Colors.white,
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 8, bottom: MediaQuery.of(context).padding.bottom + 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text('配送数量：$_totalQty，合计：$_totalAmt  共${_items.length}项',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))
              ])),
          if (_isEdit && !_isSigned && !_isRejected) _buildEditUnsignedButtons(),
          if (_isEdit && _isRejected) _buildRejectedButtons(),
          if (_isEdit && _isSigned) _buildEditSignedButtons(),
          if (!_isEdit) _buildNewBillButtons(),
        ]));
  }

  Widget _buildEditUnsignedButtons() {
    final isLoading = _submitAction != _DeliverAction.none;
    final buttons = <Widget>[];
    if (!_isWithdrawPending && _bolHandleTT)
      buttons.add(PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') _delBill();
            if (v == 'print') _print();
          },
          offset: const Offset(0, -120),
          itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'delete', child: Text('删除')),
                const PopupMenuItem(value: 'print', child: Text('打印'))
              ],
          child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('更多', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_up, size: 18, color: Color(0xFF6B7280))
              ]))));
    final showSA = !_isRejected &&
        !_isWithdrawPending &&
        (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT));
    if (showSA) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
          child: OutlinedButton(
              onPressed: isLoading ? null : () => _submit(),
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF006EFF),
                  side: const BorderSide(color: Color(0xFF006EFF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _DeliverAction.save
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
                  : const Text('保存',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    }
    if (showSA) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
          child: ElevatedButton(
              onPressed: isLoading ? null : () => _submit(withSign: true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _DeliverAction.sign
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('审核',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    }
    return Row(children: buttons);
  }

  Widget _buildRejectedButtons() {
    final isLoading = _submitAction != _DeliverAction.none;
    final b = <Widget>[];
    b.add(Expanded(
        child: OutlinedButton(
            onPressed: isLoading
                ? null
                : () {
                    if (PermissionUtils.checkPermission('013104', showTip: false))
                      _delBill();
                    else
                      Toast.show('你无权删除配送发货单');
                  },
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliverAction.delete
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6B7280)))
                : const Text('删除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    b.add(const SizedBox(width: 12));
    b.add(Expanded(
        child: ElevatedButton(
            onPressed: isLoading ? null : _print,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliverAction.print
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    b.add(const SizedBox(width: 12));
    b.add(Expanded(
        child: OutlinedButton(
            onPressed: isLoading ? null : _restsign,
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF9900),
                side: const BorderSide(color: Color(0xFFFF9900)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliverAction.withdraw
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF9900)))
                : const Text('撤回', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    return Row(children: b);
  }

  Widget _buildEditSignedButtons() {
    final isLoading = _submitAction != _DeliverAction.none;
    final b = <Widget>[];
    if (_bolHandleTTT)
      b.add(Expanded(
          child: OutlinedButton(
              onPressed: isLoading ? null : _retsign,
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF006EFF),
                  side: const BorderSide(color: Color(0xFF006EFF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _DeliverAction.retsign
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
                  : const Text('反审核',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    if (b.isNotEmpty) b.add(const SizedBox(width: 12));
    b.add(Expanded(
        child: ElevatedButton(
            onPressed: isLoading ? null : _print,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliverAction.print
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    return Row(children: b);
  }

  Widget _buildNewBillButtons() {
    final isLoading = _submitAction != _DeliverAction.none;
    final canSave = PermissionUtils.checkPermission('013103', showTip: false);
    final canSign = PermissionUtils.checkPermission('013105', showTip: false);
    final b = <Widget>[];
    b.add(Expanded(
        child: ElevatedButton(
            onPressed: isLoading || !canSave ? null : () => _submit(),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliverAction.save
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    b.add(const SizedBox(width: 12));
    b.add(Expanded(
        child: ElevatedButton(
            onPressed: isLoading || !canSign ? null : () => _submit(withSign: true),
            style: ElevatedButton.styleFrom(
                backgroundColor: canSign ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliverAction.sign
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    return Row(children: b);
  }

  Widget _buildBatchDeleteBar() {
    return Container(
        color: Colors.white,
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 8, bottom: MediaQuery.of(context).padding.bottom + 12),
        child: Row(children: [
          GestureDetector(
              onTap: _toggleSelectAll,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_isAllSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20, color: const Color(0xFF006EFF)),
                const SizedBox(width: 4),
                Text('全选，已选${_selectedIndices.length}个',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))
              ])),
          const Spacer(),
          OutlinedButton(
              onPressed: _batchDelete,
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('删除', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          const SizedBox(width: 12),
          OutlinedButton(
              onPressed: _toggleSelectMode,
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ]));
  }

  static Widget _buildCard({required String title, Widget? titleRight, required Widget child}) {
    return Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(children: [
                Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                        color: const Color(0xFF006EFF), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
                if (titleRight != null) titleRight
              ])),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: child),
        ]));
  }

  static Widget _buildReadonlyField({required String label, required String value}) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          SizedBox(
              // 与编辑态 SelectFieldItem 标签宽度保持一致（80*4/3≈107）
              width: 107,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)))),
          Expanded(
              child: Text(value.isNotEmpty ? value : '-',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                  textAlign: TextAlign.right))
        ]));
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    double verticalPadding = 10,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
      child: Row(
        children: [
          SizedBox(
            // 与编辑态 SelectFieldItem 标签宽度保持一致（80*4/3≈107）
            width: 107,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
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

// =================== 明细行数据（对齐 Vue detaillist item） ===================
class _DetailRow {
  String? prodid;
  String? barcode;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController amtController = TextEditingController();
  final TextEditingController batchController = TextEditingController();
  double? amt;
  String? batchno;
  Map<String, dynamic>? rawData;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    amtController.dispose();
    batchController.dispose();
  }
}

// =================== 明细卡片（对齐 Vue 商品列表卡片布局） ===================
class _DetailItem extends StatefulWidget {
  const _DetailItem({
    required this.row,
    required this.index,
    required this.isSelectMode,
    required this.isSelected,
    required this.readOnly,
    required this.bsid,
    required this.counterid,
    this.insid = '',
    this.outsid = '',
    required this.onToggle,
    this.onChanged,
  });

  final _DetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final String bsid;
  final String counterid;
  final String insid;
  final String outsid;
  final VoidCallback onToggle;
  final VoidCallback? onChanged;

  @override
  State<_DetailItem> createState() => _DetailItemState();
}

class _DetailItemState extends State<_DetailItem> {
  void _editDetail() {
    final raw = widget.row.rawData;
    final data = raw != null ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    // 对齐 Vue：配送发货 price = 配送价（lspsprice），零售价独立
    final price = double.tryParse(widget.row.priceController.text.isNotEmpty
            ? widget.row.priceController.text
            : (data['lspsprice']?.toString() ??
                data['psprice']?.toString() ??
                data['price']?.toString() ??
                '')) ??
        0;
    final sellprice = double.tryParse(
          data['sellprice']?.toString() ?? data['retailprice']?.toString() ?? '',
        ) ??
        0;
    final qty = double.tryParse(widget.row.qtyController.text) ?? 0;
    final currentAmt = widget.row.amt ?? MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        // 键盘弹起时弹窗整体上移，避免数量输入框被键盘遮挡
        padding: EdgeInsets.only(bottom: MediaQuery.of(_).viewInsets.bottom),
        child: _ProDetailSheet(
          productData: data,
          initialQty: qty,
          initialSellprice: sellprice,
          initialPrice: price,
          initialAmt: currentAmt,
          initialBatch: widget.row.batchController.text,
          initialBirthdate: data['birthdate']?.toString() ?? '',
          initialValiddate: data['validdate']?.toString() ?? '',
          initialRemark: data['remark']?.toString() ?? '',
          bsid: widget.bsid,
          counterid: widget.counterid,
          insid: widget.insid,
          outsid: widget.outsid,
        ),
      ),
    ).then((result) {
      if (result == null) return;
      final newQty =
          MathUtils.formatDecimalNum(1, double.tryParse(result['qty']?.toString() ?? '') ?? 0);
      final newPrice = MathUtils.formatDecimalNum(
          2, double.tryParse(result['price']?.toString() ?? '') ?? price);
      final newSellprice = MathUtils.formatDecimalNum(
          2, double.tryParse(result['sellprice']?.toString() ?? '') ?? sellprice);
      final newAmt =
          MathUtils.formatDecimalNum(3, double.tryParse(result['amt']?.toString() ?? '') ?? 0);
      widget.row.qtyController.text = MathUtils.formatDecimal(1, newQty);
      widget.row.priceController.text = MathUtils.formatDecimal(2, newPrice);
      widget.row.amt = newAmt;
      widget.row.amtController.text = MathUtils.formatDecimal(3, newAmt);
      final batchno = result['batchno']?.toString() ?? '';
      widget.row.batchController.text = batchno;
      widget.row.batchno = batchno;
      if (raw != null) {
        raw['qty'] = newQty;
        raw['price'] = newPrice;
        raw['sellprice'] = newSellprice;
        raw['amt'] = newAmt;
        // 对齐 Vue writeData：零售金额独立按零售价计算
        raw['sellamt'] = double.tryParse(result['sellamt']?.toString() ?? '') ??
            MathUtils.formatDecimalNum(3, MathUtils.mul(newQty, newSellprice));
        raw['batchno'] = batchno;
        raw['batch'] = batchno;
        raw['birthdate'] = result['birthdate']?.toString() ?? '';
        raw['validdate'] = result['validdate']?.toString() ?? '';
        raw['unit'] = result['unit']?.toString() ?? '';
        raw['size'] = result['size']?.toString() ?? '';
        raw['unitonlyid'] = result['unitonlyid']?.toString() ?? '';
        raw['sizeonlyid'] = result['sizeonlyid']?.toString() ?? '';
        raw['remark'] = result['remark']?.toString() ?? '';
      }
      widget.onChanged?.call();
    });
  }

  /// 格式化商品名称（对齐采购入库：productname/size（unit））
  static String _formatProductName(String name, String size, String unit) {
    final sb = StringBuffer(name);
    if (size.isNotEmpty) sb.write('/$size');
    if (unit.isNotEmpty) sb.write('（$unit）');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.row.rawData;
    final String productname = widget.row.nameController.text.isNotEmpty
        ? widget.row.nameController.text
        : (raw?['productname']?.toString() ?? raw?['name']?.toString() ?? '-');
    final String unit = raw?['unit']?.toString() ?? '';
    final String size = raw?['size']?.toString() ?? '';
    final String batchno = widget.row.batchno ?? '';
    final String code = raw?['barcode']?.toString() ?? raw?['selfbarcode']?.toString() ?? '';
    // 配送价（对齐 Vue：price = 配送价，与金额同口径）
    final String deliveryPrice =
        (double.tryParse(widget.row.priceController.text) ?? 0).toStringAsFixed(2);
    final String qtyText = widget.row.qtyController.text;
    final String amtText =
        widget.row.amt != null ? widget.row.amt!.toStringAsFixed(2) : widget.row.amtController.text;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: widget.index.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isSelectMode) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: widget.isSelected,
                        activeColor: const Color(0xFF006EFF),
                        onChanged: (_) => widget.onToggle(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // 列1: 商品名称（点击弹商品详情弹窗）
                Expanded(
                  flex: 6,
                  child: GestureDetector(
                    onTap: widget.readOnly ? null : _editDetail,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatProductName(productname, size, unit),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (code.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(code,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 列2: 数量（右对齐）
                Expanded(
                  flex: 4,
                  child: Text('数量：$qtyText',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
                      textAlign: TextAlign.right),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                flex: 6,
                child: Text('配送价：¥$deliveryPrice',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              ),
              Expanded(
                flex: 4,
                child: Text('金额：$amtText',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    textAlign: TextAlign.right),
              ),
            ]),
            if (batchno.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('批次：$batchno', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ],
          ],
        ),
      ),
    );
  }
}

// =================== 商品明细编辑弹窗 ===================
class _ProDetailSheet extends StatefulWidget {
  const _ProDetailSheet(
      {required this.productData,
      required this.initialQty,
      required this.initialSellprice,
      required this.initialPrice,
      required this.initialAmt,
      required this.initialBatch,
      required this.initialBirthdate,
      required this.initialValiddate,
      required this.initialRemark,
      this.bsid = '',
      this.counterid = '',
      this.insid = '',
      this.outsid = ''});
  final Map<String, dynamic> productData;
  final double initialQty, initialSellprice, initialPrice, initialAmt;
  final String initialBatch, initialBirthdate, initialValiddate, initialRemark;
  final String bsid, counterid, insid, outsid;
  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late TextEditingController _qtyCtrl, _batchCtrl, _birthdateCtrl, _validdateCtrl, _remarkCtrl;
  late final FocusNode _qtyFocusNode;
  double _price = 0;
  double _sellprice = 0;
  double _amt = 0;
  double _sellamt = 0;
  late String _currentUnit, _currentSize, _unitonlyid, _sizeonlyid;

  /// 对齐 PC ylx enquiry edit.vue：生鲜商品（pricetype 2/3）且 lsPsWeightIntFlag == 1 时数量仅可输入整数
  bool get _isIntOnly {
    // 直接读取 loginParamResp（避免多层传递）
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
        if ((cfg['lsPsWeightIntFlag']?.toString() ?? '') == '1') {
          final pricetype = widget.productData['pricetype']?.toString();
          return pricetype == '2' || pricetype == '3';
        }
      }
    } catch (_) {}
    return false;
  }

  bool get _unitCanSelect {
    final pid = widget.productData['productid']?.toString() ??
        widget.productData['prodid']?.toString() ??
        '';
    return pid.isNotEmpty && _sizeonlyid.isEmpty;
  }

  bool get _sizeCanSelect =>
      (widget.productData['specflag']?.toString() ?? '') == '1' && _unitonlyid.isEmpty;
  @override
  void initState() {
    super.initState();
    // 对齐采购计划：数量按服务器小数位配置格式化初始化，支持小数输入
    _qtyCtrl = TextEditingController(text: MathUtils.formatDecimal(1, widget.initialQty));
    _price = widget.initialPrice;
    _sellprice = widget.initialSellprice;
    _batchCtrl = TextEditingController(text: widget.initialBatch);
    _birthdateCtrl = TextEditingController(text: widget.initialBirthdate);
    _validdateCtrl = TextEditingController(text: widget.initialValiddate);
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
    _currentUnit = widget.productData['unit']?.toString() ?? '';
    _currentSize = widget.productData['size']?.toString() ?? '';
    _unitonlyid = widget.productData['unitonlyid']?.toString() ?? '';
    _sizeonlyid = widget.productData['sizeonlyid']?.toString() ?? '';
    _syncAmts();
    _qtyCtrl.addListener(_onAmountChanged);
    _qtyFocusNode = FocusNode()..addListener(_onQtyFocusChange);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _batchCtrl.dispose();
    _birthdateCtrl.dispose();
    _validdateCtrl.dispose();
    _remarkCtrl.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  /// 数量变化时实时重算金额
  void _onAmountChanged() {
    if (!mounted) return;
    setState(_syncAmts);
  }

  /// 金额重算（对齐 Vue writeData：amt = qty × 配送价，sellamt = qty × 零售价）
  void _syncAmts() {
    final q = double.tryParse(_qtyCtrl.text) ?? 0;
    _amt = MathUtils.formatDecimalNum(3, MathUtils.mul(q, _price));
    _sellamt = MathUtils.formatDecimalNum(3, MathUtils.mul(q, _sellprice));
  }

  /// 数量输入框失去焦点：整数模式时取整并按规定小数位格式化（对齐 PC ylx distribution mask
  /// 效果，但输入过程允许小数点避免误操作导致数字异常变大）
  void _onQtyFocusChange() {
    if (_qtyFocusNode.hasFocus || !_isIntOnly) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final intVal = qty.truncate();
    _qtyCtrl.text = MathUtils.formatDecimal(1, intVal.toDouble());
  }

  /// 数量加减（最小 1，步进 1；读写走输入框控制器，对齐采购计划小数输入）
  void _changeQty(double delta) {
    var v = MathUtils.formatDecimalNum(1, (double.tryParse(_qtyCtrl.text) ?? 0) + delta);
    if (v < 1) v = 1;
    _qtyCtrl.text = MathUtils.formatDecimal(1, v);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.productData;
    final name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    final barcode = data['barcode']?.toString() ?? '';
    // 配送价显示服务器原始小数位（对齐截图）
    final psprice = data['lspsprice']?.toString() ??
        data['psprice']?.toString() ??
        data['price']?.toString() ??
        '';
    // 收货门店库存 / 配送中心库存（原始值）
    final instockQty = data['instockqty']?.toString() ?? '0';
    final outstockQty = data['outstockqty']?.toString() ?? '0';
    return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Container(
            decoration: const BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2))),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Stack(alignment: Alignment.center, children: [
                    const Text('商品详情',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                    Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280))))
                  ])),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Flexible(
                  child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 12,
                          bottom: MediaQuery.of(context).padding.bottom + 88),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // 商品信息卡片（名称 / 条码 + 配送价）
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE5E7EB))),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _buildInfoLine('商品名称', name),
                              const SizedBox(height: 6),
                              Row(children: [
                                Expanded(
                                    child: Text('条码：${barcode.isNotEmpty ? barcode : '-'}',
                                        style: const TextStyle(
                                            fontSize: 12, color: Color(0xFF6B7280), height: 1.5))),
                                Expanded(
                                    child: Text('配送价：${psprice.isNotEmpty ? psprice : '-'}',
                                        style: const TextStyle(
                                            fontSize: 12, color: Color(0xFF6B7280), height: 1.5))),
                              ]),
                            ])),
                        const SizedBox(height: 12),
                        // 收货门店库存
                        _buildInfoRow('收货门店库存', instockQty),
                        _buildDivider(),
                        // 配送中心库存
                        _buildInfoRow('配送中心库存', outstockQty),
                        _buildDivider(),
                        // 单位
                        _buildUnitSelectField(),
                        _buildDivider(),
                        // 规格
                        _buildSizeSelectField(),
                        _buildDivider(),
                        // 数量（加减按钮 + 可编辑小数输入，对齐采购计划小数位处理）
                        _buildQtyStepper(),
                        _buildDivider(),
                        // 配送金额（只读，= 配送价 × 数量，随输入实时重算）
                        _buildInfoRow('配送金额', MathUtils.formatDecimal(3, _amt)),
                        _buildDivider(),
                        // 商品批次（SelectBatchSheet 选择，带出生产/有效日期）
                        _buildBatchSelectField(),
                        _buildDivider(),
                        // 生产日期
                        _buildDateField(label: '生产日期', ctrl: _birthdateCtrl),
                        _buildDivider(),
                        // 有效日期
                        _buildDateField(label: '有效日期', ctrl: _validdateCtrl),
                        _buildDivider(),
                        // 备注
                        _buildFormField(
                            label: '备注',
                            controller: _remarkCtrl,
                            keyboardType: TextInputType.text,
                            hintText: '请输入备注'),
                      ]))),
              Container(
                  padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 10,
                      bottom: MediaQuery.of(context).padding.bottom + 12),
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
                  child: Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF6B7280),
                                side: const BorderSide(color: Color(0xFFE5E7EB)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape:
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('取消', style: TextStyle(fontSize: 15)))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: ElevatedButton(
                            onPressed: () {
                              _syncAmts();
                              Navigator.pop(context, {
                                'qty': MathUtils.formatDecimalNum(
                                    1,
                                    _isIntOnly
                                        ? (double.tryParse(_qtyCtrl.text) ?? 0.0).truncateToDouble()
                                        : (double.tryParse(_qtyCtrl.text) ?? 0.0)),
                                // 对齐 Vue：price 为配送价，amt = qty × 配送价，零售金额独立
                                'price': MathUtils.formatDecimalNum(2, _price),
                                'sellprice': MathUtils.formatDecimalNum(2, _sellprice),
                                'amt': _amt,
                                'sellamt': _sellamt,
                                'batchno': _batchCtrl.text.trim(),
                                'birthdate': _birthdateCtrl.text.trim(),
                                'validdate': _validdateCtrl.text.trim(),
                                'remark': _remarkCtrl.text.trim(),
                                'unit': _currentUnit,
                                'size': _currentSize,
                                'unitonlyid': _unitonlyid,
                                'sizeonlyid': _sizeonlyid
                              });
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF006EFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                elevation: 0,
                                shape:
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('确定',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))),
                  ])),
            ])));
  }

  Widget _buildFormField(
      {required String label,
      required TextEditingController controller,
      bool isDecimal = false,
      TextInputType keyboardType = TextInputType.number,
      int maxLines = 1,
      String? hintText}) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
            crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              SizedBox(
                  width: 100,
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
              Expanded(
                  child: TextField(
                      controller: controller,
                      maxLines: maxLines,
                      keyboardType: isDecimal
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : keyboardType,
                      inputFormatters: isDecimal
                          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
                          : null,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                      decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintText: hintText,
                          hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)))))
            ]));
  }

  Widget _buildDateField({required String label, required TextEditingController ctrl}) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: GestureDetector(
            onTap: () => _pickDate(ctrl),
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              SizedBox(
                  width: 100,
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
              Expanded(
                  child: Text(ctrl.text.isNotEmpty ? ctrl.text : '请选择',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 14,
                          color: ctrl.text.isNotEmpty
                              ? const Color(0xFF111827)
                              : const Color(0xFFD1D5DB)))),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB))
            ])));
  }

  static Widget _buildDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));
  static String _formatBatchDate(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null') return '';
    try {
      final dt = DateTime.parse(s);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {}
    final ms = int.tryParse(s);
    if (ms != null && ms > 1000000000000) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    return s;
  }

  Widget _buildBatchSelectField() {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          const SizedBox(
              width: 100,
              child: Text('商品批次',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
          Expanded(
              child: TextField(
                  controller: _batchCtrl,
                  // 商品批次只能选择，不支持手动录入
                  readOnly: true,
                  keyboardType: TextInputType.text,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                  decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB))),
                  onTap: _pickBatch)),
          const SizedBox(width: 4),
          GestureDetector(
              onTap: _pickBatch,
              child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFFD1D5DB)))
        ]));
  }

  /// 打开批次选择器（商品批次只能选择）
  Future<void> _pickBatch() async {
    final productid = widget.productData['productid']?.toString() ??
        widget.productData['prodid']?.toString() ??
        '';
    if (productid.isEmpty) {
      Toast.show('商品信息异常');
      return;
    }
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SelectBatchSheet(
            productid: productid,
            bsid: widget.bsid,
            counterid: widget.counterid,
            // 对齐 Vue select-batch：配送发货不传 costflag
            costflag: false,
            initialBatchNo: _batchCtrl.text));
    if (result != null && mounted) {
      setState(() {
        _batchCtrl.text = result['batchno']?.toString() ?? '';
        final bd = _formatBatchDate(result['birthdate']);
        _birthdateCtrl.text = bd;
        final vd = _formatBatchDate(result['validdate']);
        _validdateCtrl.text = vd.isEmpty ? bd : vd;
      });
    }
  }

  Widget _buildInfoRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827))))
      ]));

  /// 数量加减字段（中间可编辑小数输入，对齐采购计划小数位处理）
  Widget _buildQtyStepper() {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          const SizedBox(
              width: 100,
              child: Text('数量',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
          Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            GestureDetector(
                onTap: () => _changeQty(-1),
                child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDEDEDE)),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.remove, size: 18, color: Color(0xFF333333)))),
            SizedBox(
                width: 72,
                child: TextField(
                    controller: _qtyCtrl,
                    focusNode: _qtyFocusNode,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                    decoration: const InputDecoration(
                        border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero))),
            GestureDetector(
                onTap: () => _changeQty(1),
                child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDEDEDE)),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.add, size: 18, color: Color(0xFF333333)))),
          ]))
        ]));
  }

  /// 商品信息行：「标签：值」，标签加粗、值普通（对齐商品详情卡片样式）
  Widget _buildInfoLine(String label, String value) {
    return Text.rich(
        TextSpan(style: const TextStyle(fontSize: 14, color: Color(0xFF111827)), children: [
      TextSpan(text: '$label：', style: const TextStyle(fontWeight: FontWeight.w600)),
      TextSpan(text: value),
    ]));
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    DateTime initial;
    try {
      initial = ctrl.text.isNotEmpty ? DateTime.parse(ctrl.text) : DateTime.now();
    } catch (_) {
      initial = DateTime.now();
    }
    DateTime tempDate = initial;
    final date = await showModalBottomSheet<DateTime>(
        context: context,
        builder: (c) => SizedBox(
            height: 300,
            child: Column(children: [
              SizedBox(
                  height: 50,
                  child: Row(children: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280)))),
                    const Spacer(),
                    TextButton(
                        onPressed: () => Navigator.pop(c, tempDate),
                        child: const Text('确定', style: TextStyle(color: Color(0xFF006EFF))))
                  ])),
              const Divider(height: 1),
              Expanded(
                  child: Row(children: [
                Expanded(
                    child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                            initialItem: (tempDate.year - 2020).clamp(0, 19)),
                        itemExtent: 36,
                        onSelectedItemChanged: (int i) {
                          tempDate = DateTime(2020 + i, tempDate.month, tempDate.day);
                        },
                        children: List.generate(
                            20,
                            (i) => Center(
                                child: Text('${2020 + i}年',
                                    style: const TextStyle(
                                        fontSize: 16, color: Color(0xFF333333))))))),
                Expanded(
                    child: CupertinoPicker(
                        scrollController:
                            FixedExtentScrollController(initialItem: tempDate.month - 1),
                        itemExtent: 36,
                        onSelectedItemChanged: (int i) {
                          tempDate = DateTime(tempDate.year, i + 1, tempDate.day);
                        },
                        children: List.generate(
                            12,
                            (i) => Center(
                                child: Text('${i + 1}月',
                                    style: const TextStyle(
                                        fontSize: 16, color: Color(0xFF333333))))))),
                Expanded(
                    child: CupertinoPicker(
                        scrollController:
                            FixedExtentScrollController(initialItem: tempDate.day - 1),
                        itemExtent: 36,
                        onSelectedItemChanged: (int i) {
                          final maxDay = DateTime(tempDate.year, tempDate.month + 1, 0).day;
                          tempDate =
                              DateTime(tempDate.year, tempDate.month, (i + 1).clamp(1, maxDay));
                        },
                        children: List.generate(
                            31,
                            (i) => Center(
                                child: Text('${i + 1}日',
                                    style:
                                        const TextStyle(fontSize: 16, color: Color(0xFF333333)))))))
              ]))
            ])));
    if (date != null && mounted) {
      final mo = date.month.toString().padLeft(2, '0');
      final dy = date.day.toString().padLeft(2, '0');
      setState(() {
        ctrl.text = '${date.year}-$mo-$dy';
      });
    }
  }

  Widget _buildUnitSelectField() {
    final canSelect = _unitCanSelect;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: GestureDetector(
            onTap: canSelect ? () => _showExtendOptions('unit') : null,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              const SizedBox(
                  width: 100,
                  child: Text('单位',
                      style: TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
              Expanded(
                  child: Text(_currentUnit.isNotEmpty ? _currentUnit : (canSelect ? '请选择' : ''),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 14,
                          color: _currentUnit.isNotEmpty
                              ? const Color(0xFF111827)
                              : const Color(0xFFD1D5DB)))),
              if (canSelect) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB))
              ]
            ])));
  }

  Widget _buildSizeSelectField() {
    final canSelect = _sizeCanSelect;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: GestureDetector(
            onTap: canSelect ? () => _showExtendOptions('size') : null,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              const SizedBox(
                  width: 100,
                  child: Text('规格',
                      style: TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
              Expanded(
                  child: Text(_currentSize.isNotEmpty ? _currentSize : (canSelect ? '请选择' : ''),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 14,
                          color: _currentSize.isNotEmpty
                              ? const Color(0xFF111827)
                              : const Color(0xFFD1D5DB)))),
              if (canSelect) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB))
              ]
            ])));
  }

  Future<void> _showExtendOptions(String type) async {
    final data = widget.productData;
    final pid = data['productid']?.toString() ?? data['prodid']?.toString() ?? '';
    if (pid.isEmpty) {
      Toast.show('商品信息异常');
      return;
    }
    final params = <String, dynamic>{
      'productid': pid,
      // 对齐 Vue unitSelect：page/pagesize/is_page/ptype/commonflag + 明细行 mergeData
      'page': 1,
      'pagesize': 99999,
      'is_page': 0,
      'ptype': 1,
      'commonflag': 1,
      'pspriceflag': 1,
      'insid': widget.insid,
      'outsid': widget.outsid,
      'itemtype': data['itemtype']?.toString() ?? '',
      'packageflag': data['packageflag']?.toString() ?? '',
      'specflag': data['specflag']?.toString() ?? '',
      'counterid': widget.counterid,
      'bsid': widget.bsid,
    };
    if (type == 'size') params['plugin'] = 'sizelist';
    try {
      final result = await request(HttpApi.productGetExtendList, params);
      if (!mounted) return;
      final rd = result['data'];
      final rawList = (rd is Map<String, dynamic>
              ? (type == 'size' ? rd['sizelist'] : rd['packlist'])
              : null) as List? ??
          [];
      if (rawList.isEmpty) {
        Toast.show('无可选${type == 'unit' ? '单位' : '规格'}');
        return;
      }
      final list = rawList.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['_name'] = type == 'size'
            ? (m['size']?.toString() ?? m['sname']?.toString() ?? '')
            : (m['unit']?.toString() ?? m['sunit']?.toString() ?? '');
        m['_id'] = type == 'size'
            ? (m['sizeonlyid']?.toString() ?? m['onlyid']?.toString() ?? '')
            : (m['unitonlyid']?.toString() ?? m['onlyid']?.toString() ?? '');
        return m;
      }).toList();
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB)))),
                    child: Row(children: [
                      Text('选择${type == 'unit' ? '单位' : '规格'}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)))
                    ])),
                Flexible(
                    child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (ctx, i) => ListTile(
                            title: Text(list[i]['_name']?.toString() ?? ''),
                            onTap: () => Navigator.pop(ctx, list[i]))))
              ])));
      if (selected != null && mounted) _applyExtendResult(type, selected);
    } catch (e) {
      if (mounted) Toast.show('获取${type == 'unit' ? '单位' : '规格'}失败');
    }
  }

  void _applyExtendResult(String type, Map<String, dynamic> r) {
    setState(() {
      if (type == 'unit') {
        final u = r['unit']?.toString() ?? r['_name']?.toString() ?? '';
        if (u.isNotEmpty) _currentUnit = u;
        final uid = r['unitonlyid']?.toString() ?? r['_id']?.toString() ?? '';
        if (uid.isNotEmpty) _unitonlyid = uid;
        final cgprice = r['cgprice']?.toString();
        if (cgprice != null) widget.productData['cgprice'] = cgprice;
        // 对齐 Vue unitConfirm：配送发货单价 = 配送价 lspsprice/psprice
        final ps = r['lspsprice']?.toString() ?? r['psprice']?.toString() ?? cgprice;
        if (ps != null && ps.isNotEmpty) {
          _price = double.tryParse(ps) ?? _price;
          widget.productData['price'] = ps;
          widget.productData['lspsprice'] = ps;
        }
        final inprice = r['inprice']?.toString();
        if (inprice != null) widget.productData['inprice'] = inprice;
        for (final k in [
          'pfprice1',
          'pfprice2',
          'pfprice3',
          'mprice1',
          'mprice2',
          'mprice3',
          'psprice'
        ]) {
          final v = r[k]?.toString();
          if (v != null) widget.productData[k] = v;
        }
        final nb = r['sbarcode']?.toString() ?? r['barcode']?.toString();
        if (nb != null) widget.productData['barcode'] = nb;
        final nr = r['sellprice']?.toString() ?? r['retailprice']?.toString();
        if (nr != null && nr.isNotEmpty) {
          _sellprice = double.tryParse(nr) ?? _sellprice;
          widget.productData['sellprice'] = nr;
          widget.productData['retailprice'] = nr;
        }
        if (uid.isNotEmpty) widget.productData['packagenum'] = 1;
      } else {
        final s = r['size']?.toString() ?? r['_name']?.toString() ?? '';
        if (s.isNotEmpty) _currentSize = s;
        final sid = r['sizeonlyid']?.toString() ?? r['_id']?.toString() ?? '';
        if (sid.isNotEmpty) _sizeonlyid = sid;
        // 对齐 Vue changeSize：配送价 = lspsprice/psprice
        final p =
            r['lspsprice']?.toString() ?? r['psprice']?.toString() ?? r['cgprice']?.toString();
        if (p != null && p.isNotEmpty) {
          _price = double.tryParse(p) ?? _price;
          widget.productData['price'] = p;
          widget.productData['lspsprice'] = p;
        }
        final nb = r['sbarcode']?.toString() ?? r['barcode']?.toString();
        if (nb != null) widget.productData['barcode'] = nb;
        final nr = r['sellprice']?.toString() ?? r['retailprice']?.toString();
        if (nr != null && nr.isNotEmpty) {
          _sellprice = double.tryParse(nr) ?? _sellprice;
          widget.productData['sellprice'] = nr;
          widget.productData['retailprice'] = nr;
        }
      }
    });
  }
}

// =================== 审批弹窗 ===================
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部滑杆
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 标题（居中）
          const Center(
            child: Text('单据审批',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          ),
          const SizedBox(height: 20),
          // 审批意见
          Row(
            children: [
              const Text.rich(TextSpan(children: [
                TextSpan(text: '*', style: TextStyle(fontSize: 14, color: Color(0xFFD54B5A))),
                TextSpan(text: '审批意见：', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
              ])),
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
            ],
          ),
          const SizedBox(height: 20),
          // 备注/驳回原因
          if (_flag == 1)
            const Text('备注信息：', style: TextStyle(fontSize: 14, color: Color(0xFF333333)))
          else
            const Text.rich(TextSpan(children: [
              TextSpan(text: '*', style: TextStyle(fontSize: 14, color: Color(0xFFD54B5A))),
              TextSpan(text: '驳回原因：', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ])),
          const SizedBox(height: 8),
          Stack(children: [
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
          ]),
          const SizedBox(height: 20),
          Row(
            children: [
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
            ],
          ),
        ],
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

// =================== 审批日志弹窗 ===================
class _ApprovalLogSheet extends StatelessWidget {
  const _ApprovalLogSheet({required this.reviewBillFlows, required this.scrollController});
  final List<Map<String, dynamic>> reviewBillFlows;
  final ScrollController scrollController;
  String _formatAction(dynamic v) {
    if (v == 1 || v?.toString() == '1') return '【通过】';
    if (v == 0 || v?.toString() == '0') return '【驳回】';
    if (v == 2 || v?.toString() == '2') return '【撤回】';
    return '';
  }

  Color _actionColor(dynamic v) {
    if (v == 1 || v?.toString() == '1') return const Color(0xFF00A870);
    if (v == 0 || v?.toString() == '0') return const Color(0xFFEF4444);
    if (v == 2 || v?.toString() == '2') return const Color(0xFFFF9900);
    return const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            // 左侧对称占位（与右侧关闭热区等宽），保证标题居中
            const Spacer(),
            const Text('审批日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            // 关闭热区：宽度为头部 1/3 以上，图标仍贴右，便于大触点关闭
            Expanded(
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: Container(
                        height: 44,
                        alignment: Alignment.centerRight,
                        child: const Icon(Icons.close, size: 20, color: Color(0xFF999999)))))
          ])),
      const Divider(height: 1, color: Color(0xFFE5E7EB)),
      Expanded(
          child: reviewBillFlows.isEmpty
              ? const Center(
                  child: Text('暂无审批记录', style: TextStyle(fontSize: 13, color: Color(0xFF999999))))
              : ListView.builder(
                  controller: scrollController,
                  itemCount: reviewBillFlows.length,
                  itemBuilder: (ctx, i) {
                    final item = reviewBillFlows[i];
                    return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                            color: i.isEven ? Colors.white : const Color(0xFFFAFAFA),
                            border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F5),
                                    borderRadius: BorderRadius.circular(12)),
                                child: Center(
                                    child: Text('${i + 1}',
                                        style: const TextStyle(
                                            fontSize: 11, color: Color(0xFF666666))))),
                            const SizedBox(width: 10),
                            Text(item['username']?.toString() ?? '',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF333333))),
                            const SizedBox(width: 8),
                            Text(_formatAction(item['reviewsignflag']),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _actionColor(item['reviewsignflag'])))
                          ]),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                                child: Text('节点：${item['stepname']?.toString() ?? ''}',
                                    style:
                                        const TextStyle(fontSize: 12, color: Color(0xFF999999)))),
                            Text(
                                item['signtime']?.toString() ??
                                    item['createtime']?.toString() ??
                                    '',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)))
                          ]),
                          if ((item['reviewremark']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('备注：${item['reviewremark']}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF666666)))
                          ],
                        ]));
                  })),
    ]);
  }
}
