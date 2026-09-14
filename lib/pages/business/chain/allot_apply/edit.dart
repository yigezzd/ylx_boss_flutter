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

enum _AllotAction { none, save, sign, delete, retsign, print, withdraw }

/// 调拨申请单编辑页（对齐 Vue chain/AllotApply/AllotApplyEdit.vue）
class AllotApplyEditPage extends StatefulWidget {
  const AllotApplyEditPage({super.key, this.billData});

  final Map<String, dynamic>? billData;

  @override
  State<AllotApplyEditPage> createState() => _AllotApplyEditPageState();
}

class _AllotApplyEditPageState extends State<AllotApplyEditPage>
    with LogPageMixin<AllotApplyEditPage> {
  @override
  String get logPageName => _isEdit ? '调拨申请单详情' : '调拨申请单新增';

  // ---- 表单字段（对齐 Vue query） ----
  String? _insid; // 调入机构
  String? _instorename;
  String? _counterid; // 调入仓库
  String? _countername;
  String? _countertype;
  String? _outsid; // 调出机构
  String? _outstorename;
  String? _outhandlerid; // 发货经手人
  String? _outhandlername;
  String? _inhandlerid; // 收货经手人
  String? _inhandlername;
  DateTime? _validtime; // 有效日期（默认30天后）
  final TextEditingController _validtimeController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();

  // ---- 当前登录机构（对齐 Vue useTransferStore store） ----
  int? _myStoreType;
  int? _spid;

  // ---- 机构类型联动（对齐 Vue useTransferStore：instoretypes/outstoretypes 初始值） ----
  List<int> _instoretypes = [];
  List<int> _outstoretypes = [];

  // ---- PDA 扫码枪 ----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;

  _AllotAction _submitAction = _AllotAction.none;
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

  /// 是否有反审核权限（当前用户曾在审批流中审批过）
  bool get _bolHandleTTT {
    if (_isAdmin) return true;
    if (_reviewFlowUsers.isEmpty) {
      if (_reviewBillFlows.isEmpty) return true;
      return _reviewBillFlows.any((item) => item['userid']?.toString() == _userid);
    }
    return _reviewBillFlows.any((item) => item['userid']?.toString() == _userid);
  }

  /// 对齐 Vue disabled：signflag==1 || signflag==2 || (!permission("012703") && billid)
  bool get _readOnly {
    if (_isSigned || _isRejected) return true;
    if (_isEdit && !PermissionUtils.checkPermission('012703', showTip: false)) return true;
    return false;
  }

  /// 对齐 Vue isStoredisabled：调入机构为总店且未选调入仓库时，禁用调出机构
  bool get _isStoredisabled {
    if (_spid != null && _insid == _spid.toString() && (_counterid ?? '').isEmpty) {
      return true;
    }
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
    // 加载当前登录用户信息（编辑/新增模式均需使用，反审核权限判断依赖 _userid/_userCode）
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _userid = userMap['userid']?.toString() ?? '';
        _userCode = userMap['code']?.toString() ?? '';
      }
    } catch (_) {}
    // 加载当前登录机构（对齐 Vue useTransferStore store：storetype/spid）
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _myStoreType = int.tryParse(storeMap['storetype']?.toString() ?? '');
        _spid = int.tryParse(storeMap['spid']?.toString() ?? '');
      }
    } catch (_) {}
    // 对齐 Vue useTransferStore：instoretypes/outstoretypes 初始值
    // isPsStore ? [3] : isZyStore ? [1] : []
    if (_myStoreType == 3) {
      _instoretypes = [3];
      _outstoretypes = [3];
    } else if (_myStoreType == 1) {
      _instoretypes = [1];
      _outstoretypes = [1];
    }
    if (_isEdit) {
      _loadDetail();
    } else {
      _loadNewModeDefaults();
    }
    logEnter();
  }

  void _loadNewModeDefaults() {
    // 有效日期默认30天后（对齐 Vue validtime = dayjs().add(30, 'day')）
    final future = DateTime.now().add(const Duration(days: 30));
    _validtime = future;
    _validtimeController.text =
        '${future.year}-${future.month.toString().padLeft(2, '0')}-${future.day.toString().padLeft(2, '0')}';
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

    request(HttpApi.dborderGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _insid = data['insid']?.toString();
          _instorename = data['instorename']?.toString();
          _counterid = data['counterid']?.toString();
          _countername = data['countername']?.toString();
          _countertype = data['countertype']?.toString();
          _outsid = data['outsid']?.toString();
          _outstorename = data['outstorename']?.toString();
          // 对齐 Vue form fields：发货/收货经手人
          _outhandlerid = data['outhandlerid']?.toString();
          _outhandlername = data['outhandlername']?.toString();
          _inhandlerid = data['inhandlerid']?.toString();
          _inhandlername = data['inhandlername']?.toString();
          _remarkController.text = data['remark']?.toString() ?? '';
          _fileLists = (data['fileLists'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];

          // 有效日期（对齐 Vue：validtime.split(" ")[0]）
          final vtStr = data['validtime']?.toString() ?? '';
          final validStr = vtStr.contains(' ') ? vtStr.split(' ')[0] : vtStr;
          _validtime = DateTime.tryParse(validStr);
          _validtimeController.text = validStr;

          // 多级审批数据
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);

          // 明细：对齐 Vue writeData + defValSet
          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            _applyWriteData(c);
            _applyDefValSet(c);
            final row = _DetailRow();
            row.prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? '';
            row.barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            row.qtyController.text = c['qty']?.toString() ?? '';
            row.priceController.text = c['lspsprice']?.toString() ?? c['price']?.toString() ?? '';
            row.amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
            row.amtController.text = c['amt']?.toString() ?? '';
            row.rawData = c;
            _items.add(row);
          }
        });
      }
      // 对齐 Vue getInfo：加载后获取调入/调出机构类型
      _loadStoreTypes();
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  /// 加载机构类型（对齐 Vue getInfo：store/getInfo 获取调入/调出机构 storetype）
  void _loadStoreTypes() {
    final insid = _insid ?? '';
    final outsid = _outsid ?? '';
    if (insid.isNotEmpty) {
      request(HttpApi.storeGetInfo, {'bsid': insid}).then((res) {
        final instoreType = int.tryParse(res['data']?['storetype']?.toString() ?? '');
        if (outsid.isNotEmpty) {
          request(HttpApi.storeGetInfo, {'bsid': outsid}).then((res2) {
            final outstoreType = int.tryParse(res2['data']?['storetype']?.toString() ?? '');
            if (mounted && instoreType != null && outstoreType != null) {
              setState(() {
                _instoretypes = [instoreType, outstoreType];
                _outstoretypes = [instoreType, outstoreType];
              });
            }
          });
        }
      });
    }
  }

  // =================== 提交保存 ===================
  void _submit({bool withSign = false}) {
    if (!PermissionUtils.checkPermission('012703', showTip: false)) {
      Toast.show('你无权保存调拨申请单，请在后台修改权限');
      return;
    }
    // 操作审计
    logSave(_isEdit ? '保存修改' : (withSign ? '保存并审核' : '保存单据'));

    // 对齐 Vue save 校验顺序
    if (_items.isEmpty) {
      Toast.show('请选择商品');
      return;
    }
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择调入机构');
      return;
    }
    if ((_counterid ?? '').isEmpty) {
      Toast.show('请选择调入仓库');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择调出机构');
      return;
    }
    for (final row in _items) {
      final qty = double.tryParse(row.qtyController.text) ?? 0;
      if (qty == 0) {
        Toast.show('请填写数量');
        return;
      }
    }

    setState(() => _submitAction = _AllotAction.save);

    final detaillist = _buildSubmitDetailList();
    double totalQty = 0;
    double totalAmt = 0;
    for (final item in detaillist) {
      totalQty = MathUtils.add(totalQty, double.tryParse(item['qty']?.toString() ?? '0') ?? 0);
      totalAmt = MathUtils.add(totalAmt, double.tryParse(item['amt']?.toString() ?? '0') ?? 0);
    }

    // 对齐 Vue：parmas = deepClone(query) + billqty + billamt
    final Map<String, dynamic> params;
    if (_isEdit) {
      params = Map<String, dynamic>.from(_billData!);
    } else {
      params = {'signflag': 0};
    }
    params['insid'] = _insid ?? '';
    params['instorename'] = _instorename ?? '';
    params['counterid'] = _counterid ?? '';
    params['countername'] = _countername ?? '';
    params['countertype'] = _countertype ?? '';
    params['outsid'] = _outsid ?? '';
    params['outstorename'] = _outstorename ?? '';
    // 对齐 Vue form fields：发货/收货经手人
    params['outhandlerid'] = _outhandlerid ?? '';
    params['outhandlername'] = _outhandlername ?? '';
    params['inhandlerid'] = _inhandlerid ?? '';
    params['inhandlername'] = _inhandlername ?? '';
    // 对齐 Vue formDefault/getInfo：bsidtype 固定为 'insid'
    params['bsidtype'] = 'insid';
    params['validtime'] =
        '${_validtime!.year}-${_validtime!.month.toString().padLeft(2, '0')}-${_validtime!.day.toString().padLeft(2, '0')}';
    params['remark'] = _remarkController.text.trim();
    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt, 3);
    params['detaillist'] = detaillist;

    request(HttpApi.dborderSave, params).then((result) {
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
        if (withSign && PermissionUtils.checkPermission('012705', showTip: false)) {
          _doSignAfterSave(retData);
        }
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _AllotAction.none);
    });
  }

  /// 保存后审核（对齐 cgplan/Vue saveFn(sign==1) 的审批流程）
  void _doSignAfterSave(Map<String, dynamic> savedData) {
    // 更新审批流数据
    setState(() {
      _reviewFlowUsers = _parseReviewList(savedData['reviewFlowUsers']);
      _reviewBillFlows = _parseReviewList(savedData['reviewBillFlows']);
    });

    // 校验当前用户是否属于审批节点
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

  /// 执行审核操作（对齐 Vue signApi）
  void _doSign() {
    if (_billData == null) return;
    final params = Map<String, dynamic>.from(_billData!);
    params['signflag'] = 1;
    params['reviewremark'] = _billData?['reviewremark']?.toString() ?? '';
    // reviewsignflag: 2=撤回保持不变，0=驳回保持不变，其余设为1（通过）
    final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
    if (reviewsignflag != 2 && reviewsignflag != 0) {
      params['reviewsignflag'] = 1;
    }
    setState(() => _submitAction = _AllotAction.sign);
    request(HttpApi.dborderSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _AllotAction.none);
    });
  }

  /// 反审核（对齐 Vue fsignFn）
  Future<void> _retsign() async {
    if (!PermissionUtils.checkPermission('012706', showTip: false)) {
      Toast.show('你无权反审核调拨申请单，请在后台修改权限');
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

    setState(() => _submitAction = _AllotAction.retsign);
    final params = Map<String, dynamic>.from(_billData!);
    request(HttpApi.dborderRetsign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '反审成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _AllotAction.none);
    });
  }

  /// 撤回操作（对齐 Vue restsign：reviewsignflag=2 后重新提交）
  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('012705', showTip: false)) {
      Toast.show('你无权审核调拨申请单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('撤回单据后，所有审批步骤需重新处理！是否撤回该调拨申请单？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _AllotAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.dborderSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _AllotAction.none);
    });
  }

  /// 删除单据（对齐 Vue delBill）
  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('012704', showTip: false)) {
      Toast.show('你无权删除调拨申请单，请在后台修改权限');
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

    setState(() => _submitAction = _AllotAction.delete);
    final params = Map<String, dynamic>.from(_billData!);
    request(HttpApi.dborderDelBill, params).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _AllotAction.none);
    });
  }

  /// 打印单据（对齐 Vue menuid: '071801'）
  Future<void> _print() async {
    if (!PermissionUtils.checkPermission('012707', showTip: false)) {
      Toast.show('你无权打印调拨申请单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    setState(() => _submitAction = _AllotAction.print);
    request(HttpApi.dborderPrint, {
      'menuid': '071801',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _AllotAction.none);
    });
  }

  /// 附件（对齐 Vue openAttach：menuid '071801'）
  Future<void> _openAttach() async {
    final result = await AttachPage.show(
      context,
      fileLists: _fileLists,
      menuid: '071801',
      billid: _billData?['billid']?.toString() ?? _newBillid ?? '',
      billno: _billData?['billno']?.toString() ?? '',
    );
    if (result != null && mounted) {
      setState(() => _fileLists = result);
    }
  }

  // =================== 机构选择（对齐 Vue useTransferStore） ===================
  /// 选择调入机构（对齐 Vue inStoreMergeData + store-form-item）
  Future<void> _selectInStore() async {
    final isPs = _myStoreType == 3;
    final result = await SelectStorePage.show(
      context,
      title: '选择调入机构',
      initialSelectedId: _insid,
      nostoreid: _outsid,
      // 对齐 Vue inStoreMergeData: isPsStore ? [3] : outstoretypes?.length ? outstoretypes : [0, 1, 3]
      storetypes: isPs ? [3] : (_outstoretypes.isNotEmpty ? _outstoretypes : [0, 1, 3]),
      stopflag: '0',
    );
    if (result != null && mounted) {
      setState(() {
        _insid = result['storeid']?.toString() ?? '';
        _instorename = result['storename']?.toString() ?? '';
        // 对齐 Vue handleInStoreConfirm：清空调入仓库
        _counterid = null;
        _countername = null;
        _countertype = null;
        final st = int.tryParse(result['storetype']?.toString() ?? '');
        _instoretypes = st != null ? [0, st] : [];
        // 调入机构与调出机构相同：清空调出机构
        if (_outsid != null && _outsid!.isNotEmpty && _outsid == _insid) {
          _outsid = null;
          _outstorename = null;
          _outstoretypes = [];
        }
      });
    }
  }

  /// 选择调出机构（对齐 Vue outStoreMergeData + store-form-item）
  Future<void> _selectOutStore() async {
    // 对齐 Vue isStoredisabled：调入机构为总店且未选调入仓库时禁止选择
    if (_isStoredisabled) {
      Toast.show('请先选择调入仓库');
      return;
    }
    final isPs = _myStoreType == 3;
    final result = await SelectStorePage.show(
      context,
      title: '选择调出机构',
      initialSelectedId: _outsid,
      nostoreid: _insid,
      // 对齐 Vue outStoreMergeData: isPsStore ? [3] : instoretypes?.length ? instoretypes : [0, 1, 3]
      storetypes: isPs ? [3] : (_instoretypes.isNotEmpty ? _instoretypes : [0, 1, 3]),
      nosidsflag: '1',
      stopflag: '0',
    );
    if (result != null && mounted) {
      setState(() {
        final newOutid = result['storeid']?.toString() ?? '';
        final st = int.tryParse(result['storetype']?.toString() ?? '');
        _outstoretypes = st != null ? [0, st] : [];
        // 对齐 Vue handleOutStoreConfirm：调出机构与调入机构相同时清空调入机构
        if (_insid != null && _insid!.isNotEmpty && _insid == newOutid) {
          _insid = null;
          _instorename = null;
          _instoretypes = [];
          _counterid = null;
          _countername = null;
          _countertype = null;
        }
        _outsid = newOutid;
        _outstorename = result['storename']?.toString() ?? '';
      });
    }
  }

  /// 选择调入仓库（对齐 Vue inWareMergeData + wareFormItem + handleCounterConfirm）
  Future<void> _selectCounter() async {
    if ((_insid ?? '').isEmpty) {
      Toast.show('请先选择调入机构');
      return;
    }
    // 对齐 Vue inWareMergeData
    // countertype: spid == insid && outstoretypes.includes(1) ? '0' : ''
    // pscounterflag: outstoretypes.includes(3) ? 1 : ''
    final String countertypeParam =
        (_spid != null && _insid == _spid.toString() && _outstoretypes.contains(1)) ? '0' : '';
    final String pscounterflagParam = _outstoretypes.contains(3) ? '1' : '';
    final result = await CommonSelectSheet.show(
      context,
      title: '选择调入仓库',
      searchHint: '输入仓库名称/编码',
      initialSelectedId: _counterid,
      nameField: 'countername',
      codeField: 'countercode',
      idField: 'counterid',
      fetchData: (searchText, page) => request(HttpApi.counterGetList, {
        'sids': [int.tryParse(_insid ?? '') ?? 0],
        'nosidsflag': 1,
        'stopflag': 0,
        'cond': searchText,
        'is_page': 1,
        'page': page,
        if (countertypeParam.isNotEmpty) 'countertype': countertypeParam,
        if (pscounterflagParam.isNotEmpty) 'pscounterflag': pscounterflagParam,
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (item) => item,
    );
    if (result != null && mounted) {
      setState(() {
        _counterid = result['counterid']?.toString() ?? '';
        _countername = result['countername']?.toString() ?? '';
        _countertype = result['countertype']?.toString() ?? '';
        // 对齐 Vue wareFormItem @confirm：调入机构为总店时清空调出机构
        if (_spid != null && _insid == _spid.toString()) {
          _outsid = null;
          _outstorename = null;
        }
        // 对齐 Vue handleCounterConfirm：调入机构为总店时按仓库存储方式联动
        if (_spid != null && _insid == _spid.toString()) {
          _instoretypes = _countertype == '0' ? [0, 1] : [0, 3];
        }
      });
    }
  }

  // =================== 经手人选择（对齐 Vue handler-form-item） ===================
  /// 选择发货经手人（对齐 Vue mergeData: { sids: form.outsid }）
  Future<void> _selectOutHandler() async {
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请先选择调出机构');
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
      Toast.show('请先选择调入机构');
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

  // =================== 商品选择与扫码 ===================
  Future<void> _selectProducts() async {
    // 对齐 Vue selectProductFn 校验
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择调入机构');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择调出机构');
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
            'itemstatusin': '1,2,3,4',
            'memorytype': _countertype ?? '',
            'counterid': _counterid ?? '',
            'pspriceflag': 1,
          },
          multiple: true,
          showSelectedCount: true,
          selectList: _items.map((r) => r.rawData ?? <String, dynamic>{}).toList(),
          paramJust: const [
            'qty',
            'jsqty',
            'batch',
            'unit',
            'size',
            'remark',
            'outstockqty',
            'instockqty',
            'sellamt'
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
        _applyWriteData(c);
        _applyDefValSet(c);
        final row = _DetailRow()
          ..prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? ''
          ..barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? ''
          ..nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? ''
          ..qtyController.text = c['qty']?.toString() ?? '0'
          ..priceController.text = c['lspsprice']?.toString() ?? c['price']?.toString() ?? '0'
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

    // 尝试解析条码秤生成的重量码/金额码（对齐 Vue scanFn）
    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;

    request(HttpApi.productGetList, {
      'barcode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      'insid': _insid ?? '',
      'outsid': _outsid ?? '',
      'itemstatusin': '1,2,3,4',
      'memorytype': _countertype ?? '',
      'counterid': _counterid ?? '',
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
      // 对齐 Vue scanFn：重量码/金额码/普通条码数量处理
      double qty = double.tryParse(c['qty']?.toString() ?? '0') ?? 0;
      if (scaleInfo?.type == 'weight') {
        qty = scaleInfo!.qty ?? qty + 1;
      } else if (scaleInfo?.type == 'amount') {
        final price =
            double.tryParse(c['sellprice']?.toString() ?? c['price']?.toString() ?? '0') ?? 0;
        if (price > 0) {
          qty = MathUtils.divide(scaleInfo!.amount ?? 0, price);
        } else {
          qty = qty + 1;
        }
      } else {
        qty = qty + 1;
      }
      c['qty'] = MathUtils.formatDecimal(1, qty);
      _applyWriteData(c);
      _applyDefValSet(c);

      final prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? '';
      final barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
      final existing =
          _items.indexWhere((r) => r.prodid == prodid && (barcode.isEmpty || r.barcode == barcode));

      setState(() {
        if (existing >= 0) {
          _items[existing].qtyController.text = c['qty']?.toString() ?? '';
          _items[existing].priceController.text = c['lspsprice']?.toString() ?? '';
          _items[existing].amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
          _items[existing].amtController.text = c['amt']?.toString() ?? '';
          _items[existing].rawData = c;
        } else {
          final row = _DetailRow()
            ..prodid = prodid
            ..barcode = barcode
            ..nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? ''
            ..qtyController.text = c['qty']?.toString() ?? '0'
            ..priceController.text = c['lspsprice']?.toString() ?? c['price']?.toString() ?? '0'
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

  // =================== 明细数据处理（对齐 Vue writeData/defValSet） ===================
  /// 对齐 Vue writeData：qty 变化时重算 jsqty/sellamt/amt
  static void _applyWriteData(Map<String, dynamic> row) {
    final qty = double.tryParse(row['qty']?.toString() ?? '0') ?? 0;
    final packagenum = double.tryParse(row['packagenum']?.toString() ?? '1') ?? 1;
    row['jsqty'] =
        MathUtils.formatDecimal(1, MathUtils.divide(qty, packagenum == 0 ? 1 : packagenum));
    row['qty'] = MathUtils.formatDecimal(1, qty);
    // 零售金额 = 数量 × 零售价（对齐 Vue writeData sellamt）
    final sellprice = double.tryParse(row['sellprice']?.toString() ?? '0') ?? 0;
    row['sellamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, sellprice));
    // 调拨金额 = 数量 × 配送价（对齐 Vue writeData amt）
    final price = double.tryParse(row['price']?.toString() ?? '0') ?? 0;
    row['amt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, price));
  }

  /// 对齐 Vue defValSet：明细初始值（配送价优先取 lspsprice）
  static void _applyDefValSet(Map<String, dynamic> row) {
    // 配送价：优先取 lspsprice（SelectProductPage 传入），其次 price
    final price =
        double.tryParse(row['lspsprice']?.toString() ?? row['price']?.toString() ?? '0') ?? 0;
    row['price'] = MathUtils.formatDecimal(2, price);
    // 零售价
    final sellprice = double.tryParse(row['sellprice']?.toString() ?? '0') ?? 0;
    row['sellprice'] = MathUtils.formatDecimal(2, sellprice);
    row['qty'] = MathUtils.formatDecimal(1, double.tryParse(row['qty']?.toString() ?? '0') ?? 0);
    row['sellamt'] =
        MathUtils.formatDecimal(3, double.tryParse(row['sellamt']?.toString() ?? '0') ?? 0);
    // 调拨金额 = 数量 × 配送价
    row['amt'] = MathUtils.formatDecimal(
        3, MathUtils.mul(double.tryParse(row['qty']?.toString() ?? '0') ?? 0, price));
  }

  /// 重算行金额（amt = qty × priceController 配送价，保留 3 位小数）
  void _recalcRowAmt(_DetailRow row) {
    final qty = double.tryParse(row.qtyController.text) ?? 0;
    final price = double.tryParse(row.priceController.text) ?? 0;
    row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    row.amtController.text = MathUtils.formatDecimal(3, row.amt);
    if (row.rawData != null) {
      row.rawData!['amt'] = row.amt;
      row.rawData!['sellamt'] = row.amt;
    }
  }

  /// 提交前同步全部行的 amt（兜底未失焦的数量修改）
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
      item['sellprice'] = price;
      item['jsqty'] =
          MathUtils.formatDecimalNum(1, MathUtils.divide(qty, packagenum == 0 ? 1 : packagenum));
      item['sellamt'] = MathUtils.formatDecimalNum(
          3, double.tryParse(row.amtController.text) ?? row.amt ?? MathUtils.mul(qty, price));
      item['amt'] = item['sellamt'];
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
  /// 调拨数量（对齐 Vue sumdata.billqty）
  String get _totalQty {
    double sum = 0;
    for (final row in _items) {
      sum = MathUtils.add(sum, double.tryParse(row.qtyController.text) ?? 0);
    }
    return MathUtils.formatDecimal(1, sum);
  }

  /// 合计金额（对齐 Vue sumdata.billamt）
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

  /// 单行删除
  void _deleteItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
      _selectedIndices.remove(index);
    });
  }

  // =================== 审批相关 ===================
  /// 解析审批列表数据
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

  /// 审批操作弹窗（通过/驳回 + 备注）
  Future<Map<String, dynamic>?> _showApprovalDialog({int defaultFlag = 1}) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ApprovalDialog(defaultFlag: defaultFlag),
    );
  }

  /// 查看审批日志弹窗
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
          _isEdit ? (_isSigned ? '调拨申请单详情' : (_isRejected ? '调拨申请单详情' : '修改调拨申请单')) : '新增调拨申请单',
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

  /// 粘性表头高度常量（已迁移至 PinnedHeaderSliver，自动适配内容高度）
  // static const double _stickyScanHeight = 68.0;
  // static const double _stickyTitleHeight = 48.0;
  // static const double _stickyMinExtent = _stickyTitleHeight;
  // static const double _stickyMaxExtent = _stickyScanHeight + _stickyMinExtent;

  Widget _buildBody() {
    // 键盘弹起时隐藏底部栏，给商品明细列表留出更多空间
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final body = Column(
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
              // 审批日志卡片
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
              // 商品明细列表
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
                        onDelete: () => _deleteItem(index),
                        bsid: _outsid ?? '',
                        insid: _insid ?? '',
                        outsid: _outsid ?? '',
                        counterid: _counterid ?? '',
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
        // 键盘弹起时隐藏底部汇总+按钮栏
        if (!keyboardVisible) _buildBottomBar(),
      ],
    );
    return body;
  }

  Widget _buildStickyHeader() {
    return ColoredBox(
      color: const Color(0xFFF5F5F5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showScanInput) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: _buildScanInput(),
            ),
            const SizedBox(height: 8),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
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
                        // 附件（对齐 Vue openAttach）
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
                                Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF006EFF)),
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
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 粘性表头委托（对齐采购订货 _CgorderStickyDelegate）
  bool get _showScanInput => !_isSigned && _scanSettings.showInfraredInput;

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

    // 审核信息（对齐 Vue：signflag==1 时显示审核时间/审核人）
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

  /// 审核日志卡片（对齐 Vue approvalNode 组件）
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
        _buildReadonlyField(label: '调入机构', value: _instorename ?? ''),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '调入仓库', value: _countername ?? ''),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '调出机构', value: _outstorename ?? ''),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '有效日期', value: _validtimeController.text),
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
    // 左侧标签文字宽度在原 80 基础上增加 1/3（80*4/3≈107），避免长标签折行
    const double labelWidth = 107;
    return Column(
      children: [
        SelectFieldItem(
          label: '调入机构',
          labelWidth: labelWidth,
          required: true,
          value: _instorename ?? '',
          onTap: _selectInStore,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '调入仓库',
          labelWidth: labelWidth,
          required: true,
          value: _countername ?? '',
          onTap: _selectCounter,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        // 对齐 Vue isStoredisabled：调入机构为总店且未选调入仓库时禁用
        SelectFieldItem(
          label: '调出机构',
          labelWidth: labelWidth,
          required: true,
          value: _outstorename ?? '',
          enabled: !_isStoredisabled,
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
        // 对齐 Vue handler-form-item：发货经手人（依赖调出机构，未选时点击提示）
        SelectFieldItem(
          label: '发货经手人',
          labelWidth: labelWidth,
          value: _outhandlername ?? '',
          onTap: _selectOutHandler,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        // 对齐 Vue handler-form-item：收货经手人（依赖调入机构，未选时点击提示）
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
                  '调拨数量：$_totalQty，合计：$_totalAmt  共${_items.length}项',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          // 编辑模式 - 待审核
          if (_isEdit && !_isSigned && !_isRejected) _buildEditUnsignedButtons(),
          // 编辑模式 - 已驳回
          if (_isEdit && _isRejected) _buildRejectedButtons(),
          // 编辑模式 - 已审核
          if (_isEdit && _isSigned) _buildEditSignedButtons(),
          // 新增模式：保存 + 审核
          if (!_isEdit) _buildNewBillButtons(),
        ],
      ),
    );
  }

  /// 编辑模式 - 待审核：更多(删除/打印) + 保存 + 审核
  Widget _buildEditUnsignedButtons() {
    final bool isLoading = _submitAction != _AllotAction.none;
    final buttons = <Widget>[];

    // "更多"按钮（删除/打印）- reviewsignflag != 2 && bolHandleTT
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

    // 保存/审核按钮 - signflag!=2 && reviewsignflag!=2 && (bolHandleTT || (reviewFlowUsers>0 && bolHandleT))
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
          child: _submitAction == _AllotAction.save
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
              : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    // 审核按钮（对齐 Vue：保存并审核）
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
          child: _submitAction == _AllotAction.sign
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

  /// 编辑模式 - 已驳回：删除 + 打印 + 撤回（对齐 Vue signflag==2 按钮区）
  Widget _buildRejectedButtons() {
    final bool isLoading = _submitAction != _AllotAction.none;
    final buttons = <Widget>[];

    // 删除
    buttons.add(Expanded(
      child: OutlinedButton(
        onPressed: isLoading
            ? null
            : () {
                if (PermissionUtils.checkPermission('012704', showTip: false)) {
                  _delBill();
                } else {
                  Toast.show('你无权删除调拨申请单，请在后台修改权限');
                }
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6B7280),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _AllotAction.delete
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6B7280)))
            : const Text('删除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));
    buttons.add(const SizedBox(width: 12));

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
        child: _submitAction == _AllotAction.print
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
          foregroundColor: const Color(0xFFFF9900),
          side: const BorderSide(color: Color(0xFFFF9900)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _AllotAction.withdraw
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF9900)))
            : const Text('撤回', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    return Row(children: buttons);
  }

  /// 编辑模式 - 已审核：反审核 + 打印
  Widget _buildEditSignedButtons() {
    final bool isLoading = _submitAction != _AllotAction.none;
    final buttons = <Widget>[];

    // 反审核按钮 - bolHandleTTT
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
          child: _submitAction == _AllotAction.retsign
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
              : const Text('反审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    // 打印按钮（已审核状态下始终显示）
    if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
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
        child: _submitAction == _AllotAction.print
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    return Row(children: buttons);
  }

  /// 新增模式：保存 + 审核（对齐 Vue 新增按钮区，审核权限 012705）
  Widget _buildNewBillButtons() {
    final bool isLoading = _submitAction != _AllotAction.none;
    final buttons = <Widget>[];

    buttons.add(Expanded(
      child: ElevatedButton(
        onPressed: isLoading
            ? null
            : () {
                if (PermissionUtils.checkPermission('012703', showTip: false)) {
                  _submit();
                } else {
                  Toast.show('你无权保存调拨申请单，请在后台修改权限');
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF006EFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _AllotAction.save
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    // 审核按钮（保存并审核）
    buttons.add(const SizedBox(width: 12));
    buttons.add(Expanded(
      child: ElevatedButton(
        onPressed: isLoading
            ? null
            : () {
                if (PermissionUtils.checkPermission('012705', showTip: false)) {
                  _submit(withSign: true);
                } else {
                  Toast.show('你无权审核调拨申请单，请在后台修改权限');
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF9900),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    return Row(children: buttons);
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
          GestureDetector(
            onTap: _toggleSelectAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_isAllSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20, color: const Color(0xFF006EFF)),
                const SizedBox(width: 4),
                Text('全选，已选${_selectedIndices.length}个',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
              ],
            ),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: _batchDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: const BorderSide(color: Color(0xFFEF4444)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('删除', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _toggleSelectMode,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // =================== 扫描输入框 ===================
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

  // =================== 通用 UI 组件 ===================
  Widget _buildCard({
    required String title,
    Widget? titleRight,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          child,
        ],
      ),
    );
  }

  Widget _buildReadonlyField({required String label, required String value}) {
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
            child: Text(
              value.isNotEmpty ? value : '-',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
            ),
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
}

// =================== 明细行数据 ===================
class _DetailRow {
  String? prodid;
  String barcode = '';
  final nameController = TextEditingController();
  final qtyController = TextEditingController();
  final priceController = TextEditingController();
  final amtController = TextEditingController();
  double? amt;

  /// 商品原始数据（对齐 Vue detaillist）
  Map<String, dynamic>? rawData;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    amtController.dispose();
  }
}

// =================== 明细行 Widget ===================
class _DetailItem extends StatefulWidget {
  const _DetailItem({
    required this.row,
    required this.index,
    required this.isSelectMode,
    required this.isSelected,
    required this.readOnly,
    required this.onToggle,
    required this.bsid,
    required this.onDelete,
    this.insid = '',
    this.outsid = '',
    this.counterid = '',
    this.onChanged,
  });

  final _DetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  /// 调出机构（对齐 Vue proDetails size 请求参数 outsid）
  final String bsid;
  final String insid;
  final String outsid;

  /// 调入仓库 id（对齐 Vue mergeData counterid）
  final String counterid;

  /// 编辑弹窗返回后通知父页面刷新底部合计
  final VoidCallback? onChanged;

  @override
  State<_DetailItem> createState() => _DetailItemState();
}

class _DetailItemState extends State<_DetailItem> {
  /// 格式化商品名称（对齐 Vue：productname/size（unit））
  static String _formatProductName(String name, String size, String unit) {
    final sb = StringBuffer(name);
    if (size.isNotEmpty) sb.write('/$size');
    if (unit.isNotEmpty) sb.write('（$unit）');
    return sb.toString();
  }

  void _editDetail() {
    final raw = widget.row.rawData;
    final data = raw != null ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final sellprice = double.tryParse(
          data['sellprice']?.toString() ?? data['retailprice']?.toString() ?? '',
        ) ??
        0;
    final qty = double.tryParse(widget.row.qtyController.text) ?? 0;
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
      // 对齐 Vue writeData：amt = sellamt = qty × 零售价（弹窗不编辑单价）
      final newSellprice = double.tryParse(result['sellprice']?.toString() ?? '') ?? sellprice;
      final newAmt = MathUtils.formatDecimalNum(3, MathUtils.mul(newQty, newSellprice));
      widget.row.qtyController.text = MathUtils.formatDecimal(1, newQty);
      widget.row.priceController.text = MathUtils.formatDecimal(2, newSellprice);
      widget.row.amt = newAmt;
      widget.row.amtController.text = MathUtils.formatDecimal(3, newAmt);
      if (raw != null) {
        raw['qty'] = newQty;
        raw['sellprice'] = result['sellprice']?.toString() ?? raw['sellprice']?.toString() ?? '';
        raw['amt'] = newAmt;
        raw['sellamt'] = newAmt;
        raw['unit'] = result['unit']?.toString() ?? '';
        raw['size'] = result['size']?.toString() ?? '';
        raw['unitonlyid'] = result['unitonlyid']?.toString() ?? '';
        raw['sizeonlyid'] = result['sizeonlyid']?.toString() ?? '';
        raw['remark'] = result['remark']?.toString() ?? '';
      }
      widget.onChanged?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.row.rawData;
    final name = widget.row.nameController.text.isNotEmpty
        ? widget.row.nameController.text
        : (raw?['productname']?.toString() ?? raw?['name']?.toString() ?? '-');
    final unit = raw?['unit']?.toString() ?? '';
    final size = raw?['size']?.toString() ?? '';
    final priceText = widget.row.priceController.text.isNotEmpty
        ? widget.row.priceController.text
        : (raw?['price']?.toString() ?? '0');
    final qtyText = widget.row.qtyController.text.isNotEmpty
        ? widget.row.qtyController.text
        : (raw?['qty']?.toString() ?? '0');
    final amtText = widget.row.amt != null
        ? MathUtils.formatDecimal(3, widget.row.amt)
        : widget.row.amtController.text;

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
                    onTap: widget.isSelectMode ? null : (widget.readOnly ? null : _editDetail),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      _formatProductName(name, size, unit),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 列2: 数量（对齐 Vue：'数量：' + formatDecimal(1, item.qty || 0)）
                Expanded(
                  flex: 4,
                  child: Text(
                    '数量：$qtyText',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(children: [
              // 零售价
              Expanded(
                  flex: 6,
                  child: Text('配送价：$priceText',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
              // 金额
              Expanded(
                  flex: 3,
                  child: Text('金额：$amtText',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      textAlign: TextAlign.right)),
              if (!widget.readOnly && !widget.isSelectMode)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, size: 15, color: Color(0xFFAAAAAA)),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

// =================== 商品明细编辑弹窗（对齐采购入库 proDetails 样式） ===================
class _ProDetailSheet extends StatefulWidget {
  const _ProDetailSheet({
    required this.productData,
    required this.initialQty,
    required this.initialSellprice,
    required this.initialRemark,
    this.bsid = '',
    this.counterid = '',
    this.insid = '',
    this.outsid = '',
  });
  final Map<String, dynamic> productData;
  final double initialQty;
  final double initialSellprice;
  final String initialRemark;
  final String bsid;
  final String counterid;

  /// 调入/调出机构 id（对齐 Vue unitSelect mergeData 的 insid/outsid）
  final String insid;
  final String outsid;

  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late TextEditingController _qtyCtrl;
  late TextEditingController _remarkCtrl;

  /// 当前零售价（选单位/规格后会被接口返回值更新）
  double _sellprice = 0;

  // 单位/规格状态
  late String _currentUnit;
  late String _currentSize;
  late String _unitonlyid;
  late String _sizeonlyid;

  /// 单位可选条件（productid 存在 && sizeonlyid 为空）
  bool get _unitCanSelect {
    final data = widget.productData;
    final productid = data['productid']?.toString() ?? data['prodid']?.toString() ?? '';
    return productid.isNotEmpty && _sizeonlyid.isEmpty;
  }

  /// 规格可选条件（specflag == 1 && unitonlyid 为空）
  bool get _sizeCanSelect {
    final specflag = widget.productData['specflag']?.toString() ?? '';
    return specflag == '1' && _unitonlyid.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: MathUtils.formatDecimal(1, widget.initialQty));
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
    _currentUnit = widget.productData['unit']?.toString() ?? '';
    _currentSize = widget.productData['size']?.toString() ?? '';
    _unitonlyid = widget.productData['unitonlyid']?.toString() ?? '';
    _sizeonlyid = widget.productData['sizeonlyid']?.toString() ?? '';
    _sellprice = widget.initialSellprice;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  /// 数量加减（最小 1，步进 1；读写走输入框控制器，对齐 cgplan 小数输入）
  void _changeQty(double delta) {
    var v = MathUtils.formatDecimalNum(1, (double.tryParse(_qtyCtrl.text) ?? 0) + delta);
    if (v < 1) v = 1;
    _qtyCtrl.text = MathUtils.formatDecimal(1, v);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.productData;
    final String name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    final String barcode = data['barcode']?.toString() ?? '';
    // 配送价显示原始值（对齐 Vue proDetails：直接拼接 saleprice）
    final String psprice = data['price']?.toString() ??
        data['psprice']?.toString() ??
        data['lspsprice']?.toString() ??
        '';
    final String shelves = data['shelves']?.toString() ?? '';
    final String outstockQty = data['outstockqty']?.toString() ?? '0';
    final String instockQty = data['instockqty']?.toString() ?? '0';

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    '商品详情',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 88,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 商品信息卡片
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoLine('商品名称', name),
                          const SizedBox(height: 6),
                          Text('条码：${barcode.isNotEmpty ? barcode : '-'}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280), height: 1.5)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text('配送价：${psprice.isNotEmpty ? psprice : '-'}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Color(0xFF6B7280), height: 1.5)),
                              ),
                              Expanded(
                                child: Text('货架号：${shelves.isNotEmpty ? shelves : '暂无货架'}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Color(0xFF6B7280), height: 1.5)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 调出机构库存
                    _buildInfoRow('调出机构库存', outstockQty),
                    _buildDivider(),
                    // 调入机构库存
                    _buildInfoRow('调入机构库存', instockQty),
                    _buildDivider(),
                    // 单位
                    _buildUnitSelectField(),
                    _buildDivider(),
                    // 规格
                    _buildSizeSelectField(),
                    _buildDivider(),
                    // 数量（加减按钮）
                    _buildQtyStepper(),
                    _buildDivider(),
                    // 零售金额（对齐 cgplan 小计金额：随数量输入实时重算 = qty × 零售价）
                    ListenableBuilder(
                      listenable: _qtyCtrl,
                      builder: (_, __) => _buildInfoRow(
                          '零售金额',
                          MathUtils.formatDecimal(
                              3, MathUtils.mul(double.tryParse(_qtyCtrl.text) ?? 0, _sellprice))),
                    ),
                    _buildDivider(),
                    // 备注
                    _buildFormField(
                        label: '备注',
                        controller: _remarkCtrl,
                        keyboardType: TextInputType.text,
                        hintText: '请输入备注'),
                  ],
                ),
              ),
            ),
            // 底部按钮
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('取消', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final qty = double.tryParse(_qtyCtrl.text) ?? 0;
                        Navigator.pop(context, {
                          'qty': qty,
                          'sellprice': MathUtils.formatDecimalNum(2, _sellprice),
                          'sellamt': MathUtils.formatDecimalNum(3, MathUtils.mul(qty, _sellprice)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('确定',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    bool isDecimal = false,
    TextInputType keyboardType = TextInputType.number,
    int maxLines = 1,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              keyboardType:
                  isDecimal ? const TextInputType.numberWithOptions(decimal: true) : keyboardType,
              inputFormatters:
                  isDecimal ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))] : null,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单位选择字段（对齐 Vue proDetails.vue unit 字段）
  Widget _buildUnitSelectField() {
    final canSelect = _unitCanSelect;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: canSelect ? () => _showExtendOptions('unit') : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            const SizedBox(
              width: 100,
              child: Text('单位',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                _currentUnit.isNotEmpty ? _currentUnit : (canSelect ? '请选择' : ''),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color:
                      _currentUnit.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
                ),
              ),
            ),
            if (canSelect) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB))
            ],
          ],
        ),
      ),
    );
  }

  /// 规格选择字段（对齐 Vue proDetails.vue size 字段）
  Widget _buildSizeSelectField() {
    final canSelect = _sizeCanSelect;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: canSelect ? () => _showExtendOptions('size') : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            const SizedBox(
              width: 100,
              child: Text('规格',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                _currentSize.isNotEmpty ? _currentSize : (canSelect ? '请选择' : ''),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color:
                      _currentSize.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
                ),
              ),
            ),
            if (canSelect) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB))
            ],
          ],
        ),
      ),
    );
  }

  /// 数量加减字段（最小 1，步进 1）
  Widget _buildQtyStepper() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 100,
            child: Text('数量',
                style:
                    TextStyle(fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => _changeQty(-1),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.remove, size: 18, color: Color(0xFF333333)),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _qtyCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _changeQty(1),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.add, size: 18, color: Color(0xFF333333)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));

  /// 调用接口查询单位/规格选项（对齐 Vue selectCom getProductExtendList 逻辑）
  Future<void> _showExtendOptions(String type) async {
    final data = widget.productData;
    final String productid = data['productid']?.toString() ?? data['prodid']?.toString() ?? '';
    if (productid.isEmpty) {
      Toast.show('商品信息异常');
      return;
    }

    final params = <String, dynamic>{
      'productid': productid,
      'cgpriceflag': 1,
      'bsid': widget.bsid,
      'itemtype': data['itemtype']?.toString() ?? '',
      'packageflag': data['packageflag']?.toString() ?? '',
      'specflag': data['specflag']?.toString() ?? '',
      'is_page': 1,
    };
    if (type == 'size') {
      params['outsid'] = widget.bsid;
    }

    try {
      final result = await request(HttpApi.productGetExtendList, params);
      if (!mounted) return;
      final responseData = result['data'];
      final rawList = (responseData is Map<String, dynamic>
              ? (type == 'size' ? responseData['sizelist'] : responseData['packlist'])
              : null) as List? ??
          [];
      if (rawList.isEmpty) {
        Toast.show('无可选${type == 'unit' ? '单位' : '规格'}');
        return;
      }

      final list = rawList.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (type == 'size') {
          m['_name'] = m['size']?.toString() ?? m['sname']?.toString() ?? '';
          m['_id'] = m['sizeonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
        } else {
          m['_name'] = m['unit']?.toString() ?? m['sunit']?.toString() ?? '';
          m['_id'] = m['unitonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
        }
        return m;
      }).toList();

      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: [
                    Text('选择${type == 'unit' ? '单位' : '规格'}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final opt = list[i];
                    final optName = opt['_name']?.toString() ?? '';
                    return ListTile(
                      title: Text(optName),
                      onTap: () => Navigator.pop(ctx, opt),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (selected != null && mounted) {
        _applyExtendResult(type, selected);
      }
    } catch (e) {
      if (mounted) Toast.show('获取${type == 'unit' ? '单位' : '规格'}失败');
    }
  }

  /// 应用单位/规格选择结果（对齐 Vue proDetails.vue selectUnitFn / selectSizeFn）
  void _applyExtendResult(String type, Map<String, dynamic> result) {
    setState(() {
      if (type == 'unit') {
        final u = result['unit']?.toString() ?? result['_name']?.toString() ?? '';
        if (u.isNotEmpty) _currentUnit = u;
        final uid = result['unitonlyid']?.toString() ?? result['_id']?.toString() ?? '';
        if (uid.isNotEmpty) _unitonlyid = uid;
        // selectUnitFn 价格逻辑
        final cgprice = result['cgprice']?.toString();
        if (cgprice != null) {
          widget.productData['cgprice'] = cgprice;
          widget.productData['price'] = cgprice;
        }
        final inprice = result['inprice']?.toString();
        if (inprice != null) widget.productData['inprice'] = inprice;
        final oldprice = result['oldprice']?.toString() ?? cgprice;
        if (oldprice != null) widget.productData['oldprice'] = oldprice;
        // 批发价同步
        for (final key in [
          'pfprice1',
          'pfprice2',
          'pfprice3',
          'mprice1',
          'mprice2',
          'mprice3',
          'psprice'
        ]) {
          final v = result[key]?.toString();
          if (v != null) widget.productData[key] = v;
        }
        final pfprice = result['pfprice']?.toString() ?? result['pfprice1']?.toString();
        if (pfprice != null) widget.productData['pfprice'] = pfprice;
        final mprice = result['mprice']?.toString() ?? result['mprice1']?.toString();
        if (mprice != null) widget.productData['mprice'] = mprice;
        // 条码更新
        final nb = result['sbarcode']?.toString() ?? result['barcode']?.toString();
        if (nb != null) widget.productData['barcode'] = nb;
        // 零售价更新
        final nr = result['sellprice']?.toString() ?? result['retailprice']?.toString();
        if (nr != null && nr.isNotEmpty) {
          widget.productData['sellprice'] = nr;
          widget.productData['retailprice'] = nr;
          _sellprice = double.tryParse(nr) ?? _sellprice;
        }
        // packagenum: 选了单位后设为 1
        if (uid.isNotEmpty) widget.productData['packagenum'] = 1;
      } else {
        // size
        final s = result['size']?.toString() ?? result['_name']?.toString() ?? '';
        if (s.isNotEmpty) _currentSize = s;
        final sid = result['sizeonlyid']?.toString() ?? result['_id']?.toString() ?? '';
        if (sid.isNotEmpty) _sizeonlyid = sid;
        // 价格：取 cgprice
        final p = result['cgprice']?.toString();
        if (p != null) {
          widget.productData['price'] = p;
        }
        // 条码更新
        final nb = result['sbarcode']?.toString() ?? result['barcode']?.toString();
        if (nb != null) widget.productData['barcode'] = nb;
        // 零售价更新
        final nr = result['sellprice']?.toString() ?? result['retailprice']?.toString();
        if (nr != null && nr.isNotEmpty) {
          widget.productData['sellprice'] = nr;
          widget.productData['retailprice'] = nr;
          _sellprice = double.tryParse(nr) ?? _sellprice;
        }
      }
    });
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

  /// 只读信息行（库存等）
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
          ),
        ],
      ),
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

/// 审批日志弹窗（历史记录表格）
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
