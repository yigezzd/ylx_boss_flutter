import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/models/scan_settings.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
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

enum _EnqAction { none, save, sign, delete, retsign, print, withdraw, stop }

/// 要货申请单编辑页（对齐 Vue chain/enquiry/enquiryEdit.vue）
class EnquiryEditPage extends StatefulWidget {
  const EnquiryEditPage({super.key, this.billData});

  final Map<String, dynamic>? billData;

  @override
  State<EnquiryEditPage> createState() => _EnquiryEditPageState();
}

class _EnquiryEditPageState extends State<EnquiryEditPage> with LogPageMixin<EnquiryEditPage> {
  @override
  String get logPageName => _isEdit ? '要货申请单详情' : '要货申请单新增';

  // ---- 表单字段（对齐 Vue query） ----
  String? _insid; // 要货门店
  String? _instorename;
  String? _outsid; // 配送中心
  String? _outstorename;
  String? _outhandlerid; // 发货经手人
  String? _outhandlername;
  String? _inhandlerid; // 收货经手人
  String? _inhandlername;
  DateTime? _validtime; // 有效日期
  final TextEditingController _validtimeController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();

  // ---- 要货模板 ----
  String _refcode = '';
  String _refname = '';

  // ---- 紧急补货 ----
  bool _urgentflag = false;

  // ---- 当前登录机构 ----
  int? _myStoreType;
  int? _spid;
  bool? _isStore; // 是否总店
  String _myStoreId = ''; // 当前登录机构ID（对齐 Vue oneself 计算）

  // ---- 要货门店记忆数据（对齐 Vue memorydata：常温/冷库/服务配送中心） ----
  String _memoryNtsid = '';
  String _memoryColdsid = '';
  String _memoryFwsid = '';

  /// 对齐 Vue lsPsStoreApplyUpdateCenterFlag（loginParamResp 中为 0 时开启）
  bool _lsPsStoreApplyUpdateCenterFlag = false;

  /// 对齐 Vue loginParamResp.lsPsMasterTemplateFlag：为 1 时禁止手工选择/扫码商品，仅模板带入
  bool _lsPsMasterTemplateFlag = false;

  /// 对齐 Vue loginParamResp.lsPsApplyValidateDay：新增时有效日期默认天数（无值/0 为当天）
  int _lsPsApplyValidateDay = 0;

  /// 对齐 Vue loginParamResp.lsPsApplyShowStockqtyFlag：为 1 时商品详情弹窗显示配送中心库存，否则显示 ***
  int _lsPsApplyShowStockqtyFlag = 0;

  /// 对齐 PC ylx loginParamResp.lsPsWeightIntFlag：为 1 时生鲜商品（pricetype 2/3）数量仅可输入整数
  int _lsPsWeightIntFlag = 0;

  // ---- PDA 扫码枪 ----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;

  _EnqAction _submitAction = _EnqAction.none;
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
  bool get _isStopped => _billData?['phstatus']?.toString() == '4';

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

  /// 对齐 Vue disabled：signflag==1 || signflag==2 || (!permission("013003") && billid)
  bool get _readOnly {
    if (_isSigned || _isRejected) return true;
    if (_isEdit && !PermissionUtils.checkPermission('013003', showTip: false)) return true;
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
    // 加载当前登录机构（对齐 Vue store）
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _myStoreType = int.tryParse(storeMap['storetype']?.toString() ?? '');
        _spid = int.tryParse(storeMap['spid']?.toString() ?? '');
        final storeId = storeMap['id']?.toString() ?? '';
        _myStoreId = storeId;
        _isStore = storeId == _spid.toString();
        // 对齐 Vue 默认值：自加盟门店且非总店时默认填入要货门店
        final isZyJm = _myStoreType == 1 || _myStoreType == 2 || _myStoreType == 0;
        if (isZyJm && !_isStore!) {
          _insid = storeId;
          _instorename = storeMap['name']?.toString() ?? '';
        }
        // 对齐 Vue：配送中心且非总店时默认填入配送中心
        if (_myStoreType == 3 && !_isStore!) {
          _outsid = storeId;
          _outstorename = storeMap['name']?.toString() ?? '';
        }
      }
    } catch (_) {}
    // 加载连锁配送参数（对齐 Vue loginParamResp.lsPsStoreApplyUpdateCenterFlag）
    try {
      final String cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
        _lsPsStoreApplyUpdateCenterFlag = cfg['lsPsStoreApplyUpdateCenterFlag']?.toString() == '0';
        // 对齐 Vue：lsPsMasterTemplateFlag == 1 时仅允许通过要货模板带入商品
        _lsPsMasterTemplateFlag = cfg['lsPsMasterTemplateFlag']?.toString() == '1';
        // 对齐 Vue validtime 默认：lsPsApplyValidateDay 为天数，空/0 时默认当天
        _lsPsApplyValidateDay = int.tryParse(cfg['lsPsApplyValidateDay']?.toString() ?? '') ?? 0;
        // 对齐 Vue proDetails.vue yhsq：lsPsApplyShowStockqtyFlag == 1 时弹窗显示配送中心库存
        _lsPsApplyShowStockqtyFlag =
            int.tryParse(cfg['lsPsApplyShowStockqtyFlag']?.toString() ?? '') ?? 0;
        // 对齐 PC ylx：lsPsWeightIntFlag == 1 时生鲜商品数量仅可输入整数
        _lsPsWeightIntFlag = int.tryParse(cfg['lsPsWeightIntFlag']?.toString() ?? '') ?? 0;
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
    // 对齐 Vue validtime：默认 = 当天 + lsPsApplyValidateDay 天（参数无值/0 时为当天）
    final now = DateTime.now();
    final target = now.add(Duration(days: _lsPsApplyValidateDay));
    _validtime = target;
    _validtimeController.text =
        '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _scanDebounceTimer?.cancel();
    _validtimeController.dispose();
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

    request(HttpApi.yhorderGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _insid = data['insid']?.toString();
          _instorename = data['instorename']?.toString();
          _outsid = data['outsid']?.toString();
          _outstorename = data['outstorename']?.toString();
          // 对齐 Vue form fields：发货/收货经手人
          _outhandlerid = data['outhandlerid']?.toString();
          _outhandlername = data['outhandlername']?.toString();
          _inhandlerid = data['inhandlerid']?.toString();
          _inhandlername = data['inhandlername']?.toString();
          _remarkController.text = data['remark']?.toString() ?? '';
          _urgentflag = data['urgentflag']?.toString() == '1';
          _refcode = data['refcode']?.toString() ?? '';
          _refname = data['refname']?.toString() ?? '';
          _fileLists = (data['fileLists'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];

          // 有效日期
          final vtStr = data['validtime']?.toString() ?? '';
          final validStr = vtStr.contains(' ') ? vtStr.split(' ')[0] : vtStr;
          _validtime = DateTime.tryParse(validStr);
          _validtimeController.text = validStr;

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
            // 对齐 Vue：详情接口未返回配送价时以 price 补齐 lspsprice（配送价=单价），
            // 保证详情弹窗/再保存时 lspsprice 不为空
            if ((c['lspsprice']?.toString() ?? '').isEmpty) {
              c['lspsprice'] = c['price']?.toString() ?? '';
            }
            _applyWriteData(c);
            final row = _DetailRow();
            row.prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? '';
            row.barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            row.qtyController.text = c['qty']?.toString() ?? '';
            row.priceController.text = c['price']?.toString() ?? '';
            row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
            row.amtController.text = c['amt']?.toString() ?? '';
            row.rawData = c;
            _items.add(row);
          }
        });

        // 对齐 Vue getInfo：开关开启时按要货门店拉取冷热/服务配送中心（memorytypein 计算用）
        if (_lsPsStoreApplyUpdateCenterFlag && (_insid ?? '').isNotEmpty) {
          request(HttpApi.storeGetInfo, {'bsid': _insid}).then((storeResult) {
            if (!mounted) return;
            final storeData = storeResult['data'];
            if (storeData is Map<String, dynamic>) {
              _memoryNtsid = storeData['ntsid']?.toString() ?? '';
              _memoryColdsid = storeData['coldsid']?.toString() ?? '';
              _memoryFwsid = storeData['fwsid']?.toString() ?? '';
            }
          });
        }
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  // =================== 提交保存 ===================
  void _submit({bool withSign = false}) {
    if (!PermissionUtils.checkPermission('013003', showTip: false)) {
      Toast.show('你无权保存要货申请单，请在后台修改权限');
      return;
    }
    logSave(_isEdit ? '保存修改' : (withSign ? '保存并审核' : '保存单据'));

    if (_items.isEmpty) {
      // 对齐 Vue：开启按要货模板要货时空单引导先选模板
      Toast.show(_lsPsMasterTemplateFlag ? '请先选择要货模板' : '请选择商品');
      return;
    }
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择要货门店');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择配送中心');
      return;
    }

    setState(() => _submitAction = _EnqAction.save);

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
    params['insid'] = _insid ?? '';
    params['instorename'] = _instorename ?? '';
    params['outsid'] = _outsid ?? '';
    params['outstorename'] = _outstorename ?? '';
    // 对齐 Vue form fields：发货/收货经手人
    params['outhandlerid'] = _outhandlerid ?? '';
    params['outhandlername'] = _outhandlername ?? '';
    params['inhandlerid'] = _inhandlerid ?? '';
    params['inhandlername'] = _inhandlername ?? '';
    params['validtime'] =
        '${_validtime!.year}-${_validtime!.month.toString().padLeft(2, '0')}-${_validtime!.day.toString().padLeft(2, '0')}';
    params['remark'] = _remarkController.text.trim();
    params['refcode'] = _refcode;
    params['refname'] = _refname;
    params['urgentflag'] = _urgentflag ? 1 : 0;
    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt, 3);
    params['detaillist'] = detaillist;

    request(HttpApi.yhorderSave, params).then((result) {
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
        if (withSign && PermissionUtils.checkPermission('013005', showTip: false)) {
          _doSignAfterSave(retData);
        }
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _EnqAction.none);
    });
  }

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

  void _doSign() {
    if (_billData == null) return;
    final params = Map<String, dynamic>.from(_billData!);
    params['signflag'] = 1;
    params['reviewremark'] = _billData?['reviewremark']?.toString() ?? '';
    final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
    if (reviewsignflag != 2 && reviewsignflag != 0) {
      params['reviewsignflag'] = 1;
    }
    setState(() => _submitAction = _EnqAction.sign);
    request(HttpApi.yhorderSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _EnqAction.none);
    });
  }

  Future<void> _retsign() async {
    if (!PermissionUtils.checkPermission('013006', showTip: false)) {
      Toast.show('你无权反审核要货申请单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    String tipMsg = '确定反审核单据吗？';
    if (_reviewBillFlows.isNotEmpty) {
      tipMsg = '反审核单据后，所有审批步骤需重新处理！确认要反审核单据？';
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text(tipMsg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _EnqAction.retsign);
    final params = Map<String, dynamic>.from(_billData!);
    request(HttpApi.yhorderRetsign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '反审成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _EnqAction.none);
    });
  }

  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('013005', showTip: false)) {
      Toast.show('你无权审核要货申请单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('撤回单据后，所有审批步骤需重新处理！是否撤回该要货申请单？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _EnqAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.yhorderSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _EnqAction.none);
    });
  }

  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('013004', showTip: false)) {
      Toast.show('你无权删除要货申请单，请在后台修改权限');
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

    setState(() => _submitAction = _EnqAction.delete);
    request(HttpApi.yhorderDelBill, {
      'billid': _billData!['billid'],
    }).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _EnqAction.none);
    });
  }

  /// 终止（对齐 Vue stopFn：phstatus==1 && signflag==1）
  Future<void> _stopBill() async {
    if (!PermissionUtils.checkPermission('013008', showTip: false)) {
      Toast.show('你无权终止要货申请单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定终止单据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _EnqAction.stop);
    request(HttpApi.yhorderStop, {
      'billid': _billData!['billid'],
    }).then((result) {
      if (!mounted) return;
      Toast.show('终止成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _EnqAction.none);
    });
  }

  Future<void> _print() async {
    if (!PermissionUtils.checkPermission('013007', showTip: false)) {
      Toast.show('你无权打印要货申请单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    setState(() => _submitAction = _EnqAction.print);
    request(HttpApi.yhorderPrint, {
      'menuid': '071201',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _EnqAction.none);
    });
  }

  Future<void> _openAttach() async {
    final result = await AttachPage.show(
      context,
      fileLists: _fileLists,
      menuid: '071201',
      billid: _billData?['billid']?.toString() ?? _newBillid ?? '',
      billno: _billData?['billno']?.toString() ?? '',
    );
    if (result != null && mounted) {
      setState(() => _fileLists = result);
    }
  }

  // =================== 要货模板带入 ===================
  /// 选择要货模板（对齐 Vue openYHMB/selectYHMBFn：yhtemplate/findList，选中后拉取模板商品）
  Future<void> _selectTemplate() async {
    // findProList 需 insid/outsid，对齐 Vue save 校验顺序先行提示
    if ((_insid ?? '').isEmpty) {
      Toast.show('请先选择要货门店');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请先选择配送中心');
      return;
    }
    final result = await CommonSelectSheet.show(
      context,
      title: '选择要货模板',
      searchHint: '输入模板名称',
      fetchData: (searchText, page) {
        return request(HttpApi.yhtemplateFindList, {
          'name': searchText,
          'is_page': 1,
          'page': page,
          'pagesize': 20,
        }).then((res) {
          final data = res['data'];
          return data is Map<String, dynamic> ? data : null;
        });
      },
      // 列表仅展示模板名称，不显示 [code] 前缀
      codeField: '',
      idField: 'code',
      initialSelectedId: _refcode.isEmpty ? null : _refcode,
    );
    if (result == null || !mounted) return;
    final code = result['code']?.toString() ?? '';
    final name = result['name']?.toString() ?? '';
    // 确认弹窗：选择模板将替换当前商品列表
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text('是否选择模板“$name”？\n选择后模板商品将替换当前商品列表。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    // 对齐 Vue selectYHMBFn：refcode = e.code、refname = e.name，随后 findProList 带入商品
    setState(() {
      _refcode = code;
      _refname = name;
    });
    await _loadTemplateProducts();
  }

  /// 拉取要货模板商品明细（对齐 Vue findProList：yhtemplate/findProList，psprice → price）
  /// 选择模板后整体替换现有商品列表，不再保留/合并原明细
  Future<void> _loadTemplateProducts() async {
    if (_refcode.isEmpty || !mounted) return;
    request(HttpApi.yhtemplateFindProList, {
      'code': _refcode,
      'is_page': 0,
      'insid': _insid ?? '',
      'outsid': _outsid ?? '',
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isEmpty) {
        Toast.show('该模板暂无商品');
        return;
      }
      setState(() {
        // 对齐 Vue findProList：productname = proname、price = formatDecimal(2, psprice)、qty 缺省取 1
        final built = <_DetailRow>[];
        for (final v in list) {
          if (v is! Map) continue;
          final c = Map<String, dynamic>.from(v);
          c['productname'] = c['proname']?.toString() ?? '';
          c['price'] =
              MathUtils.formatDecimal(2, double.tryParse(c['psprice']?.toString() ?? '') ?? 0);
          if ((c['lspsprice']?.toString() ?? '').isEmpty) {
            c['lspsprice'] = c['price']?.toString() ?? '';
          }
          final tqty = double.tryParse(c['qty']?.toString() ?? '') ?? 0;
          c['qty'] = MathUtils.formatDecimal(1, tqty > 0 ? tqty : 1);
          _applyWriteData(c);
          final row = _DetailRow()
            ..prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? ''
            ..barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? ''
            ..nameController.text = c['productname']?.toString() ?? ''
            ..qtyController.text = c['qty']?.toString() ?? '0'
            ..priceController.text = c['price']?.toString() ?? '0'
            ..rawData = c;
          row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
          row.amtController.text = c['amt']?.toString() ?? '';
          built.add(row);
        }
        // 选择模板后整体替换现有商品列表（不保留/合并原明细）
        for (final row in _items) {
          row.dispose();
        }
        _items.clear();
        _items.addAll(built);
      });
    });
  }

  // =================== 商品选择与扫码 ===================
  /// 对齐 Vue memorytypein：开关开启时按配送中心匹配要货门店的常温/冷库/服务配送中心
  String get _memorytypein {
    if (!_lsPsStoreApplyUpdateCenterFlag) return '';
    final types = <String>[];
    if (_memoryNtsid.isNotEmpty && _memoryNtsid == _outsid) types.add('1');
    if (_memoryColdsid.isNotEmpty && _memoryColdsid == _outsid) types.add('2');
    if (_memoryFwsid.isNotEmpty && _memoryFwsid == _outsid) types.add('3');
    return types.join(',');
  }

  /// 对齐 Vue mergeData（选择商品/扫码共用）：insid/outsid/pspriceflag/pstype/memorytypein
  Map<String, dynamic> _buildProductMergData() {
    return {
      'insid': _insid ?? '',
      'outsid': _outsid ?? '',
      'pspriceflag': 1,
      'pstype': '1,2,4',
      'memorytypein': _memorytypein,
    };
  }

  Future<void> _selectProducts() async {
    // 对齐 Vue：模板参数开启时仅允许通过要货模板带入商品
    if (_lsPsMasterTemplateFlag) {
      Toast.show('请先选择要货模板');
      return;
    }
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择要货门店');
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
            ..._buildProductMergData(),
            'itemstatus': '1,2',
          },
          multiple: true,
          showSelectedCount: true,
          selectList: _items.map((r) => r.rawData ?? <String, dynamic>{}).toList(),
          paramJust: const [
            'qty',
            'unit',
            'size',
            'remark',
            'outstockqty',
            'instockqty',
            'psamt',
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
        // 对齐 Vue：price = lspsprice
        c['price'] =
            MathUtils.formatDecimal(2, double.tryParse(c['lspsprice']?.toString() ?? '') ?? 0);
        _applyWriteData(c);
        final row = _DetailRow()
          ..prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? ''
          ..barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? ''
          ..nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? ''
          ..qtyController.text = c['qty']?.toString() ?? '0'
          ..priceController.text = c['price']?.toString() ?? '0'
          ..rawData = c;
        row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
        row.amtController.text = c['amt']?.toString() ?? '';
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
    // 对齐 Vue：模板参数开启时禁止扫码录入商品
    if (_lsPsMasterTemplateFlag) {
      Toast.show('请先选择要货模板');
      return;
    }
    if (Device.isMobile) {
      FocusScope.of(context).unfocus();
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
    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;

    request(HttpApi.productGetList, {
      'barcode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      ..._buildProductMergData(),
      'itemstatus': '1,2',
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
      final first = list.first as Map;
      final c = Map<String, dynamic>.from(first);
      // 对齐 Vue scanFn：price = lspsprice
      c['price'] =
          MathUtils.formatDecimal(2, double.tryParse(c['lspsprice']?.toString() ?? '') ?? 0);
      final qty = double.tryParse(c['qty']?.toString() ?? '0') ?? 0;
      c['qty'] = MathUtils.formatDecimal(1, qty > 0 ? qty : 1);
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
            ..qtyController.text = c['qty']?.toString() ?? '1'
            ..priceController.text = c['price']?.toString() ?? '0'
            ..rawData = c;
          row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
          row.amtController.text = c['amt']?.toString() ?? '';
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

  /// 点击商品行打开详情弹窗（对齐 Vue proDetails：编辑数量/配送价/备注、单位/规格选择）
  Future<void> _editRowDetail(int index) async {
    final row = _items[index];
    final raw = row.rawData;
    final data = raw != null ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final price = double.tryParse(
          data['price']?.toString() ?? data['lspsprice']?.toString() ?? row.priceController.text,
        ) ??
        0;
    final qty = double.tryParse(row.qtyController.text) ?? 0;
    final currentAmt = row.amt ?? MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    final result = await showModalBottomSheet<Map<String, dynamic>>(
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
          initialPrice: price,
          initialAmt: currentAmt,
          initialRemark: data['remark']?.toString() ?? '',
          insid: _insid ?? '',
          outsid: _outsid ?? '',
          // 对齐 Vue proDetails.vue yhsq：lsPsApplyShowStockqtyFlag == 1 显示配送中心库存
          showPsStockqty: _lsPsApplyShowStockqtyFlag == 1,
          // 对齐 PC ylx edit.vue L314/L335：lsPsWeightIntFlag == 1 时生鲜商品数量仅可输入整数
          qtyIntOnly: _lsPsWeightIntFlag == 1,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final newQty =
        MathUtils.formatDecimalNum(1, double.tryParse(result['qty']?.toString() ?? '') ?? 0);
    final newPrice =
        MathUtils.formatDecimalNum(2, double.tryParse(result['price']?.toString() ?? '') ?? price);
    final newAmt =
        MathUtils.formatDecimalNum(3, double.tryParse(result['amt']?.toString() ?? '') ?? 0);
    setState(() {
      row.qtyController.text = MathUtils.formatDecimal(1, newQty);
      row.priceController.text = MathUtils.formatDecimal(2, newPrice);
      row.amt = newAmt;
      row.amtController.text = MathUtils.formatDecimal(3, newAmt);
      if (raw != null) {
        // 弹窗返回完整商品数据（含单位/规格切换后的价格、packagenum、条码等），整体合并
        raw.addAll(result);
        // 对齐 Vue writeData：qty 变化重算 jsqty/amt
        _applyWriteData(raw);
        row.amt = double.tryParse(raw['amt']?.toString() ?? '') ?? newAmt;
        row.amtController.text = raw['amt']?.toString() ?? '';
        final nb = result['barcode']?.toString() ?? '';
        if (nb.isNotEmpty) row.barcode = nb;
      }
    });
  }

  // =================== 明细数据处理（对齐 Vue writeData） ===================
  /// 对齐 Vue writeData：qty 变化时重算 amt = qty × price (配送价)
  static void _applyWriteData(Map<String, dynamic> row) {
    final qty = double.tryParse(row['qty']?.toString() ?? '0') ?? 0;
    final packagenum = double.tryParse(row['packagenum']?.toString() ?? '1') ?? 1;
    row['jsqty'] =
        MathUtils.formatDecimal(1, MathUtils.divide(qty, packagenum == 0 ? 1 : packagenum));
    row['qty'] = MathUtils.formatDecimal(1, qty);
    final price = double.tryParse(row['price']?.toString() ?? '0') ?? 0;
    row['price'] = MathUtils.formatDecimal(2, price);
    final amt = MathUtils.formatDecimal(3, MathUtils.mul(qty, price));
    row['amt'] = amt;
  }

  void _recalcRowAmt(_DetailRow row) {
    final qty = double.tryParse(row.qtyController.text) ?? 0;
    final price = double.tryParse(row.priceController.text) ?? 0;
    row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    row.amtController.text = MathUtils.formatDecimal(3, row.amt);
    if (row.rawData != null) {
      row.rawData!['amt'] = row.amt;
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

  // =================== 机构选择 ===================
  /// 选择要货门店（对齐 Vue jumpPge('yhmd')：mergeData 含 psselecttype/outsid 联动）
  Future<void> _selectInStore() async {
    final result = await SelectStorePage.show(
      context,
      title: '选择要货门店',
      initialSelectedId: _insid,
      nostoreid: _outsid,
      storetypes: const [0, 1, 2],
      stopflag: '0',
      isLs: true,
      psselecttype: '1',
      outsid: _outsid,
    );
    if (result != null && mounted) {
      // 对齐 Vue allowflag：总部/配送中心/区域中心登录时校验门店供货状态
      final myType = _myStoreType ?? -1;
      if ((myType == 0 || myType == 3 || myType == 4) && result['allowflag']?.toString() == '0') {
        Toast.show('该门店已停止供货');
        return;
      }
      setState(() {
        _insid = result['storeid']?.toString() ?? '';
        _instorename = result['storename']?.toString() ?? '';
        // 对齐 Vue：记录要货门店的冷热/服务配送中心（memorytypein 计算用）
        _memoryNtsid = result['ntsid']?.toString() ?? '';
        _memoryColdsid = result['coldsid']?.toString() ?? '';
        _memoryFwsid = result['fwsid']?.toString() ?? '';
        if (_outsid != null && _outsid!.isNotEmpty && _outsid == _insid) {
          _outsid = null;
          _outstorename = null;
        }
      });
    }
  }

  /// 选择配送中心（对齐 Vue jumpPge('pszx')：mergeData 含 psselecttype/insid 联动，配送中心登录仅查自己）
  Future<void> _selectOutStore() async {
    if ((_insid ?? '').isEmpty) {
      Toast.show('请先选择要货门店');
      return;
    }
    final result = await SelectStorePage.show(
      context,
      title: '选择配送中心',
      initialSelectedId: _outsid,
      nostoreid: _insid,
      storetypes: const [0, 3],
      stopflag: '0',
      isLs: true,
      psselecttype: '1',
      insid: _insid,
      // 对齐 Vue oneself：配送中心登录时仅能选择自己
      sids: _myStoreType == 3 && _myStoreId.isNotEmpty ? [_myStoreId] : null,
    );
    if (result != null && mounted) {
      setState(() {
        final newOutid = result['storeid']?.toString() ?? '';
        if (_insid != null && _insid!.isNotEmpty && _insid == newOutid) {
          Toast.show('配送中心不能与要货门店相同');
          return;
        }
        _outsid = newOutid;
        _outstorename = result['storename']?.toString() ?? '';
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
      Toast.show('请先选择要货门店');
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
          _isEdit ? (_isSigned || _isRejected ? '要货申请单详情' : '修改要货申请单') : '新增要货申请单',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            cacheExtent: 800,
            slivers: [
              if (_isEdit)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: _buildBillStatusWidget(),
                  ),
                ),
              if (_isEdit && (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: _buildApprovalNodeCard(),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: _buildCard(
                    title: '单据信息',
                    child: _readOnly ? _buildBillInfoReadonly() : _buildBillInfoEditable(),
                  ),
                ),
              ),
              // 粘性表头：扫描框 + 商品明细标题栏（固定不随商品列表滚动）
              PinnedHeaderSliver(
                child: _buildStickyHeader(),
              ),
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
                        onToggle: () => _toggleIndex(index),
                        onProductTap: () => _editRowDetail(index),
                        bsid: _outsid ?? '',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ),
                ),
              if (_items.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        LoadAssetImage('state/zwsp', width: 80, height: 80),
                        SizedBox(height: 12),
                        Text('暂无商品明细', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                      ]),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        ),
        if (!keyboardVisible) _buildBottomBar(),
      ],
    );
  }

  /// 商品明细头部（附件/删除/扫描/新增 + 标题，对齐 Vue 商品明细 tm-sheet）
  Widget _buildStickyHeader() {
    return ColoredBox(
      color: const Color(0xFFF5F5F5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isSigned && _scanSettings.showInfraredInput && !_lsPsMasterTemplateFlag) ...[
              Padding(
                padding: EdgeInsets.zero,
                child: _buildScanInput(),
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF006EFF),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('商品明细',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827))),
                          ),
                          GestureDetector(
                            onTap: _openAttach,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.attach_file, size: 15, color: Color(0xFF6B7280)),
                                const SizedBox(width: 2),
                                Text('附件(${_fileLists.length})',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280),
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          if (!_readOnly) ...[
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _toggleSelectMode,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_isSelectMode ? Icons.close : Icons.delete_outline,
                                      size: 17,
                                      color: _isSelectMode
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFFFF4D4F)),
                                  const SizedBox(width: 2),
                                  Text(_isSelectMode ? '取消' : '删除',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _isSelectMode
                                              ? const Color(0xFF6B7280)
                                              : const Color(0xFFFF4D4F),
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            // 对齐 Vue：lsPsMasterTemplateFlag == 1 时隐藏扫描/新增入口（仅模板带入）
                            if (!_lsPsMasterTemplateFlag) ...[
                              const SizedBox(width: 10),
                              if (_scanSettings.showCameraButton) ...[
                                GestureDetector(
                                  onTap: _scanBarcode,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      BossSvgIcon(svgFile: 'scan.svg', size: 12),
                                      SizedBox(width: 2),
                                      Text('扫描',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF006EFF),
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              GestureDetector(
                                onTap: _selectProducts,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_circle_outline,
                                        size: 16, color: Color(0xFF006EFF)),
                                    SizedBox(width: 2),
                                    Text('新增',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF006EFF),
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

    // 终止状态覆盖
    if (_isStopped) {
      statusLabel = '已终止';
      statusColor = const Color(0xFF666666);
    }

    final String signtime = data['signtime']?.toString() ?? '';
    final String signname = data['signname']?.toString() ?? '';

    return _buildCard(
      title: '单号：$billno',
      titleRight: Text(statusLabel,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('制单信息：$createtime',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ),
                Text(createname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ],
            ),
            if (signflag == '1' && (signtime.isNotEmpty || signname.isNotEmpty)) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text('审核信息：$signtime',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                  ),
                  Text(signname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

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
      margin: const EdgeInsets.only(bottom: 4),
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
            Row(
              children: [
                Expanded(
                  child: Text(currentInfo,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
                ),
                GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
                ),
              ],
            )
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

  Widget _buildBillInfoReadonly() {
    return Column(
      children: [
        _buildReadonlyField(label: '要货门店', value: _instorename ?? ''),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '配送中心', value: _outstorename ?? ''),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '有效日期', value: _validtimeController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '要货模板', value: _refname),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '紧急补货', value: _urgentflag ? '是' : '否'),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '发货经手人', value: _outhandlername ?? ''),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '收货经手人', value: _inhandlername ?? ''),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '备注', value: _remarkController.text),
      ],
    );
  }

  Widget _buildBillInfoEditable() {
    // 左侧标签文字宽度在原 80 基础上增加 1/3（80*4/3≈107），避免"配送中心仓库"等长标签折行
    const double labelWidth = 107;
    return Column(
      children: [
        SelectFieldItem(
          label: '要货门店',
          labelWidth: labelWidth,
          required: true,
          value: _instorename ?? '',
          onTap: _selectInStore,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '配送中心',
          labelWidth: labelWidth,
          required: true,
          value: _outstorename ?? '',
          onTap: _selectOutStore,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '有效日期',
          labelWidth: labelWidth,
          value: _validtimeController.text,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _validtime ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
              locale: const Locale('zh', 'CN'),
            );
            if (picked != null && mounted) {
              setState(() {
                _validtime = picked;
                _validtimeController.text =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '要货模板',
          labelWidth: labelWidth,
          value: _refname,
          onTap: _selectTemplate,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        // 对齐 Vue ps-template-tip：开启按要货模板要货时的橙色提示
        if (_lsPsMasterTemplateFlag)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            alignment: Alignment.centerLeft,
            child: const Text(
              '已开启按要货模板要货：商品明细由要货模板带入，不支持新增/扫码录入商品',
              style: TextStyle(fontSize: 11, color: Color(0xFFFF9900), height: 1.4),
            ),
          ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        // 紧急补货
        GestureDetector(
          onTap: _readOnly
              ? null
              : () {
                  setState(() => _urgentflag = !_urgentflag);
                },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            child: Row(
              children: [
                const SizedBox(
                  width: 90,
                  child: Text('紧急补货', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
                ),
                const Spacer(),
                Switch(
                  value: _urgentflag,
                  onChanged: _readOnly ? null : (v) => setState(() => _urgentflag = v),
                  activeColor: const Color(0xFF006EFF),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        // 对齐 Vue handler-form-item：发货经手人（依赖配送中心，未选时点击提示）
        SelectFieldItem(
          label: '发货经手人',
          labelWidth: labelWidth,
          value: _outhandlername ?? '',
          onTap: _selectOutHandler,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        // 对齐 Vue handler-form-item：收货经手人（依赖要货门店，未选时点击提示）
        SelectFieldItem(
          label: '收货经手人',
          labelWidth: labelWidth,
          value: _inhandlername ?? '',
          onTap: _selectInHandler,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildField(
          controller: _remarkController,
          label: '备注',
          hint: '请输入备注信息',
        ),
      ],
    );
  }

  // =================== 底部栏 ===================
  Widget _buildBottomBar() {
    if (_isSelectMode) {
      return _buildBatchDeleteBar();
    }
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  '申请数量：$_totalQty，合计：$_totalAmt  共${_items.length}项',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          if (_isEdit && !_isSigned && !_isRejected) _buildEditUnsignedButtons(),
          if (_isEdit && _isRejected) _buildRejectedButtons(),
          if (_isEdit && _isSigned) _buildEditSignedButtons(),
          if (!_isEdit) _buildNewBillButtons(),
        ],
      ),
    );
  }

  Widget _buildEditUnsignedButtons() {
    final bool isLoading = _submitAction != _EnqAction.none;
    final buttons = <Widget>[];

    if (!_isWithdrawPending && _bolHandleTT) {
      buttons.add(PopupMenuButton<String>(
        onSelected: (val) {
          if (val == 'delete') _delBill();
          if (val == 'print') _print();
        },
        offset: const Offset(0, -120),
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'delete', child: Text('删除')),
          const PopupMenuItem(value: 'print', child: Text('打印')),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('更多', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_up, size: 18, color: Color(0xFF6B7280)),
          ]),
        ),
      ));
    }

    final showSaveAndAudit = !_isRejected &&
        !_isWithdrawPending &&
        (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT));
    if (showSaveAndAudit) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
        child: OutlinedButton(
          onPressed: isLoading ? null : () => _submit(),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF006EFF),
            side: const BorderSide(color: Color(0xFF006EFF)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitAction == _EnqAction.save
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
              : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    if (showSaveAndAudit) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: isLoading ? null : () => _submit(withSign: true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF006EFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitAction == _EnqAction.sign
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    return Row(children: buttons);
  }

  Widget _buildRejectedButtons() {
    final bool isLoading = _submitAction != _EnqAction.none;
    final buttons = <Widget>[];

    buttons.add(Expanded(
      child: OutlinedButton(
        onPressed: isLoading ? null : () => _delBill(),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6B7280),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _EnqAction.delete
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6B7280)))
            : const Text('删除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));
    buttons.add(const SizedBox(width: 12));

    buttons.add(Expanded(
      child: ElevatedButton(
        onPressed: isLoading ? null : _print,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF006EFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _EnqAction.print
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));
    buttons.add(const SizedBox(width: 12));

    // 撤回
    buttons.add(Expanded(
      child: OutlinedButton(
        onPressed: isLoading ? null : _restsign,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF006EFF),
          side: const BorderSide(color: Color(0xFF006EFF)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _EnqAction.withdraw
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
            : const Text('撤回', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    return Row(children: buttons);
  }

  Widget _buildEditSignedButtons() {
    final bool isLoading = _submitAction != _EnqAction.none;
    final buttons = <Widget>[];

    // 反审核
    if (_bolHandleTTT) {
      buttons.add(Expanded(
        child: OutlinedButton(
          onPressed: isLoading ? null : _retsign,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF006EFF),
            side: const BorderSide(color: Color(0xFF006EFF)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitAction == _EnqAction.retsign
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
              : const Text('反审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
      buttons.add(const SizedBox(width: 12));
    }

    // 终止
    final phstatus = _billData?['phstatus']?.toString() ?? '';
    if (phstatus == '1') {
      buttons.add(Expanded(
        child: OutlinedButton(
          onPressed: isLoading ? null : _stopBill,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF006EFF),
            side: const BorderSide(color: Color(0xFF006EFF)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitAction == _EnqAction.stop
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
              : const Text('终止', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
      buttons.add(const SizedBox(width: 12));
    }

    // 打印
    buttons.add(Expanded(
      child: ElevatedButton(
        onPressed: isLoading ? null : _print,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF006EFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _EnqAction.print
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    return Row(children: buttons);
  }

  Widget _buildNewBillButtons() {
    final bool isLoading = _submitAction != _EnqAction.none;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: isLoading ? null : () => _submit(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF006EFF),
              side: const BorderSide(color: Color(0xFF006EFF)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _submitAction == _EnqAction.save
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
                : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: isLoading ? null : () => _submit(withSign: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _submitAction == _EnqAction.sign
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  Widget _buildBatchDeleteBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          // 全选
          GestureDetector(
            onTap: _toggleSelectAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isAllSelected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: _isAllSelected ? const Color(0xFF006EFF) : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 6),
                Text('全选，已选${_selectedIndices.length}个',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                _isSelectMode = false;
                _selectedIndices.clear();
              });
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: const Text('取消', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _batchDelete,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF006EFF),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: const Text('删除', style: TextStyle(fontSize: 14, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // =================== 通用组件 ===================
  Widget _buildCard({required String title, required Widget child, Widget? titleRight}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF006EFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                ),
                if (titleRight != null) titleRight,
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: child),
        ],
      ),
    );
  }

  static Widget _buildReadonlyField({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            // 与编辑态 SelectFieldItem 标签宽度保持一致（80*4/3≈107）
            width: 107,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value.isNotEmpty ? value : '-',
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
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

  Widget _buildScanInput() {
    // 对齐 Vue：lsPsMasterTemplateFlag == 1 时禁止扫码录入商品（隐藏红外扫码输入框）
    if (_lsPsMasterTemplateFlag) return const SizedBox.shrink();
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
}

// =================== 明细行数据模型 ===================
class _DetailRow {
  String? prodid;
  String barcode = '';
  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController amtController = TextEditingController();
  double? amt;
  Map<String, dynamic>? rawData;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    amtController.dispose();
  }
}

// =================== 明细列表项 Widget ===================
class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.row,
    required this.index,
    required this.isSelectMode,
    required this.isSelected,
    required this.readOnly,
    required this.onToggle,
    required this.onProductTap,
    required this.bsid,
    required this.onChanged,
  });

  final _DetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final VoidCallback onToggle;

  /// 点击商品信息打开商品详情弹窗（对齐 Vue proDetails 编辑明细）
  final VoidCallback onProductTap;
  final String bsid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final String nameText = row.nameController.text;
    final String qtyText = row.qtyController.text;
    final String amtText = row.amtController.text;
    final String priceText = row.priceController.text;

    return Container(
      decoration: BoxDecoration(
        color: index.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelectMode) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      activeColor: const Color(0xFF006EFF),
                      onChanged: (_) => onToggle(),
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
                  onTap: isSelectMode ? onToggle : (readOnly ? null : onProductTap),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nameText,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (row.barcode.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('条码：${row.barcode}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
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
              child: Text('配送价：¥$priceText',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ),
            Expanded(
              flex: 4,
              child: Text('金额：$amtText',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  textAlign: TextAlign.right),
            ),
          ]),
        ],
      ),
    );
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

// =================== 审批日志 Sheet ===================
class _ApprovalLogSheet extends StatelessWidget {
  const _ApprovalLogSheet({
    required this.reviewBillFlows,
    required this.scrollController,
  });

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
    return Column(
      children: [
        // 头部
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
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
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF999999)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        // 表格
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
                        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text('${i + 1}',
                                      style:
                                          const TextStyle(fontSize: 11, color: Color(0xFF666666))),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                item['username']?.toString() ?? '',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF333333)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatAction(item['reviewsignflag']),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _actionColor(item['reviewsignflag'])),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '节点：${item['stepname']?.toString() ?? ''}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                                ),
                              ),
                              Text(
                                item['signtime']?.toString() ??
                                    item['createtime']?.toString() ??
                                    '',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                              ),
                            ],
                          ),
                          if ((item['reviewremark']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('备注：${item['reviewremark']}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF666666)))
                          ],
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

// =================== 商品详情编辑弹窗（对齐 Vue proDetails：数量/配送价/备注/单位/规格） ===================
class _ProDetailSheet extends StatefulWidget {
  const _ProDetailSheet({
    required this.productData,
    required this.initialQty,
    required this.initialPrice,
    required this.initialAmt,
    required this.initialRemark,
    this.insid = '',
    this.outsid = '',
    this.showPsStockqty = false,
    this.qtyIntOnly = false,
  });

  final Map<String, dynamic> productData;
  final double initialQty, initialPrice, initialAmt;
  final String initialRemark;

  /// 要货门店/配送中心 id（对齐 Vue unit-form-item mergeData 的 insid/outsid/bsid）
  final String insid;
  final String outsid;

  /// 对齐 Vue proDetails.vue yhsq：loginParamResp.lsPsApplyShowStockqtyFlag == 1 时显示配送中心库存
  final bool showPsStockqty;

  /// 对齐 PC ylx enquiry edit.vue：loginParamResp.lsPsWeightIntFlag == 1 时
  /// 生鲜商品（pricetype 2/3）数量仅可输入整数（imask distribution），否则可输小数（max7dec4）
  final bool qtyIntOnly;

  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late TextEditingController _qtyCtrl, _remarkCtrl;
  late final FocusNode _qtyFocusNode;
  late String _currentUnit, _currentSize, _unitonlyid, _sizeonlyid;

  /// 对齐 PC ylx edit.vue L314/L335：生鲜商品（pricetype 2/3）且 lsPsWeightIntFlag == 1 时数量仅可输入整数
  bool get _isIntOnly =>
      widget.qtyIntOnly &&
      (widget.productData['pricetype']?.toString() == '2' ||
          widget.productData['pricetype']?.toString() == '3');

  /// 当前配送价（选单位/规格后被接口返回的 lspsprice 更新）
  double _price = 0;

  /// 单位可选（对齐 Vue unit 列：packageflag==1 且未选规格）
  bool get _unitCanSelect {
    final pid = widget.productData['productid']?.toString() ??
        widget.productData['prodid']?.toString() ??
        '';
    return (widget.productData['packageflag']?.toString() ?? '') == '1' &&
        pid.isNotEmpty &&
        _sizeonlyid.isEmpty;
  }

  /// 规格可选（对齐 Vue size 列：specflag==1 且未选单位）
  bool get _sizeCanSelect =>
      (widget.productData['specflag']?.toString() ?? '') == '1' && _unitonlyid.isEmpty;

  /// 金额 = 配送价 × 数量（对齐 Vue writeData amt 逻辑）
  double get _amt {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    return MathUtils.formatDecimalNum(3, MathUtils.mul(qty, _price));
  }

  @override
  void initState() {
    super.initState();
    // 对齐采购计划：数量按服务器小数位配置格式化初始化，支持小数输入
    _qtyCtrl = TextEditingController(text: MathUtils.formatDecimal(1, widget.initialQty));
    _price = widget.initialPrice;
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
    _currentUnit = widget.productData['unit']?.toString() ?? '';
    _currentSize = widget.productData['size']?.toString() ?? '';
    _unitonlyid = widget.productData['unitonlyid']?.toString() ?? '';
    _sizeonlyid = widget.productData['sizeonlyid']?.toString() ?? '';
    _qtyFocusNode = FocusNode()..addListener(_onQtyFocusChange);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _remarkCtrl.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  /// 数量输入框失去焦点：整数模式时取整并按规定小数位格式化（对齐 PC ylx distribution mask
  /// 效果，但输入过程允许小数点避免误操作导致数字异常变大）
  void _onQtyFocusChange() {
    if (_qtyFocusNode.hasFocus || !_isIntOnly) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final intVal = qty.truncate(); // 取整（去掉小数部分）
    _qtyCtrl.text = MathUtils.formatDecimal(1, intVal.toDouble());
  }

  /// 数量加减（最小 1，步进 1；读写走输入框控制器，对齐采购计划小数输入）
  void _changeQty(double delta) {
    var v = MathUtils.formatDecimalNum(1, (double.tryParse(_qtyCtrl.text) ?? 0) + delta);
    if (v < 1) v = 1;
    setState(() {
      _qtyCtrl.text = MathUtils.formatDecimal(1, v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.productData;
    final name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    final barcode = data['barcode']?.toString() ?? '';
    // 配送价显示原始值（保留服务器小数位，对齐截图）
    final pspriceText = data['lspsprice']?.toString() ?? data['price']?.toString() ?? '';
    // 要货门店库存（instockqty = 要货门店方向），配送中心库存（outstockqty = 配送中心方向）
    final instockQty = data['instockqty']?.toString() ?? '0';
    final outstockQty = data['outstockqty']?.toString() ?? '0';
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                                  child: Text('配送价：${pspriceText.isNotEmpty ? pspriceText : '-'}',
                                      style: const TextStyle(
                                          fontSize: 12, color: Color(0xFF6B7280), height: 1.5))),
                            ]),
                          ])),
                      const SizedBox(height: 12),
                      // 要货门店库存
                      _buildInfoRow('要货门店库存', instockQty),
                      _buildDivider(),
                      // 配送中心库存（对齐 Vue proDetails.vue yhsq：lsPsApplyShowStockqtyFlag == 1
                      // 显示真实值，否则显示 ***）
                      _buildInfoRow('配送中心库存', widget.showPsStockqty ? outstockQty : '***'),
                      _buildDivider(),
                      _buildUnitSelectField(),
                      _buildDivider(),
                      _buildSizeSelectField(),
                      _buildDivider(),
                      // 数量（加减按钮 + 可编辑小数输入，对齐采购计划小数位处理）
                      _buildQtyStepper(),
                      _buildDivider(),
                      // 配送金额（只读，= 配送价 × 数量，随输入实时重算）
                      _buildInfoRow('配送金额', MathUtils.formatDecimal(3, _amt)),
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
                    color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
                child: Row(children: [
                  const SizedBox(width: 8),
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
                            Navigator.pop(context, {
                              ...widget.productData,
                              'qty': MathUtils.formatDecimalNum(
                                  1,
                                  _isIntOnly
                                      ? (double.tryParse(_qtyCtrl.text) ?? 0.0).truncateToDouble()
                                      : (double.tryParse(_qtyCtrl.text) ?? 0.0)),
                              'price': MathUtils.formatDecimalNum(2, _price),
                              'amt': _amt,
                              'remark': _remarkCtrl.text.trim(),
                              'unit': _currentUnit,
                              'size': _currentSize,
                              'unitonlyid': _unitonlyid,
                              'sizeonlyid': _sizeonlyid,
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
          ],
        ),
      ),
    );
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
                      onChanged: (_) => setState(() {}),
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

  /// 数量加减字段（中间可编辑小数输入，对齐采购计划小数位处理）
  Widget _buildQtyStepper() {
    // 对齐 PC ylx enquiry edit.vue L314/L335：生鲜商品（pricetype 2/3）且
    // lsPsWeightIntFlag == 1 时数量仅可输入整数（imask distribution），否则可输小数（max7dec4）
    // 输入过程允许小数点，失去焦点时由 _onQtyFocusChange 取整格式化
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
                    onChanged: (_) => setState(() {}),
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
      TextSpan(
        style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
        children: [
          TextSpan(text: '$label：', style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: value),
        ],
      ),
    );
  }

  static Widget _buildDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));

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

  /// 单位/规格扩展（对齐 Vue unit-form-item mergeData：productid/insid/outsid/pspriceflag/itemtype/packageflag/specflag/bsid）
  Future<void> _showExtendOptions(String type) async {
    final data = widget.productData;
    final pid = data['productid']?.toString() ?? data['prodid']?.toString() ?? '';
    if (pid.isEmpty) {
      Toast.show('商品信息异常');
      return;
    }
    final params = <String, dynamic>{
      'productid': pid,
      'pspriceflag': 1,
      'insid': widget.insid,
      'outsid': widget.outsid,
      'itemtype': data['itemtype']?.toString() ?? '',
      'packageflag': data['packageflag']?.toString() ?? '',
      'specflag': data['specflag']?.toString() ?? '',
      'bsid': widget.insid,
      'is_page': 1,
    };
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
        // 对齐 Vue unitConfirm：price = lspsprice
        final psprice = r['lspsprice']?.toString() ?? r['psprice']?.toString();
        if (psprice != null) {
          widget.productData['lspsprice'] = psprice;
          widget.productData['price'] = psprice;
          _price = double.tryParse(psprice) ?? _price;
        }
        final packagenum = r['packagenum']?.toString();
        if (packagenum != null) widget.productData['packagenum'] = packagenum;
        if (uid.isNotEmpty) widget.productData['packagenum'] = 1;
        final sellprice = r['sellprice']?.toString();
        if (sellprice != null) widget.productData['sellprice'] = sellprice;
        final inprice = r['inprice']?.toString();
        if (inprice != null) widget.productData['inprice'] = inprice;
        final nb = r['sbarcode']?.toString() ?? r['barcode']?.toString();
        if (nb != null) widget.productData['barcode'] = nb;
        final code = r['scode']?.toString() ?? r['code']?.toString();
        if (code != null) widget.productData['code'] = code;
        final shelves = r['shelves']?.toString();
        if (shelves != null) widget.productData['shelves'] = shelves;
      } else {
        final s = r['size']?.toString() ?? r['_name']?.toString() ?? '';
        if (s.isNotEmpty) _currentSize = s;
        final sid = r['sizeonlyid']?.toString() ?? r['_id']?.toString() ?? '';
        if (sid.isNotEmpty) _sizeonlyid = sid;
        // 对齐 Vue changeSize：price = lspsprice
        final p = r['lspsprice']?.toString() ?? r['psprice']?.toString();
        if (p != null) {
          widget.productData['price'] = p;
          widget.productData['lspsprice'] = p;
          _price = double.tryParse(p) ?? _price;
        }
        if (sid.isNotEmpty) widget.productData['packagenum'] = 1;
        final nb = r['sbarcode']?.toString() ?? r['barcode']?.toString();
        if (nb != null) widget.productData['barcode'] = nb;
        final code = r['scode']?.toString() ?? r['code']?.toString();
        if (code != null) widget.productData['code'] = code;
      }
    });
  }
}
