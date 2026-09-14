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

enum _DeliveryAction { none, save, sign, delete, retsign, print, withdraw }

/// 审核前库存不足校验结果（对齐 Vue save→sign 链路的 storageNotEnoughFlag 处理）
enum _StockCheckResult {
  /// 校验通过（无库存不足或无需校验），直接审核
  pass,

  /// 警告模式确认：重新保存后继续审核并跳过库存校验（对齐 Vue save(1, 1) 的 val=1）
  resaveSkipCheck,

  /// 阻止模式修改完毕：重新保存并重新完整校验（对齐用户重新点审核）
  resaveRecheck,

  /// 中止审核（用户取消或阻止模式仍有库存不足）
  blocked,
}

/// 调拨出库单编辑页（对齐 Vue chain/AllotDelivery/AllotDeliveryEdit.vue）
class AllotDeliveryEditPage extends StatefulWidget {
  const AllotDeliveryEditPage({super.key, this.billData});

  final Map<String, dynamic>? billData;

  @override
  State<AllotDeliveryEditPage> createState() => _AllotDeliveryEditPageState();
}

class _AllotDeliveryEditPageState extends State<AllotDeliveryEditPage>
    with LogPageMixin<AllotDeliveryEditPage> {
  @override
  String get logPageName => _isEdit ? '调拨出库单详情' : '调拨出库单新增';

  // ---- 表单字段（对齐 Vue query） ----
  String? _outsid; // 调出机构
  String? _outstorename;
  String? _outcounterid; // 调出仓库
  String? _outcountername;
  String? _outcountertype;
  String? _insid; // 调入机构
  String? _instorename;
  String? _incounterid; // 调入仓库
  String? _incountername;
  String? _incountertype;
  String? _psname; // 送货员
  String? _psuserid;
  String? _outhandlerid; // 发货经手人（对齐 Vue outhandlerid）
  String? _outhandlername;
  String? _inhandlerid; // 收货经手人（对齐 Vue inhandlerid）
  String? _inhandlername;
  String? _outstocksaleflag; // 调出仓库库存销售标志（对齐 Vue outstocksaleflag）
  String? _dbbillid; // 调拨申请单id
  String? _dbbillno; // 调拨申请单号
  DateTime? _billdate; // 调出时间（默认今天）
  final TextEditingController _billdateController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();

  // ---- 当前登录机构 ----
  int? _myStoreType;
  int? _spid;

  // ---- 机构类型联动 ----
  List<int> _instoretypes = [];
  List<int> _outstoretypes = [];
  int? _inStoretype; // 调入机构类型（对齐 Vue form.inStoretype）
  int? _outStoretype; // 调出机构类型（对齐 Vue form.outStoretype）

  // ---- PDA 扫码枪 ----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;

  _DeliveryAction _submitAction = _DeliveryAction.none;
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

  /// 对齐 Vue disabled：signflag==1 || signflag==2 || (!permission("012803") && billid)
  bool get _readOnly {
    if (_isSigned || _isRejected) return true;
    if (_isEdit && !PermissionUtils.checkPermission('012803', showTip: false)) return true;
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
      }
    } catch (_) {}
    // 对齐 Vue useTransferStore：按登录机构类型初始化机构类型联动
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

    request(HttpApi.dbstockoutGetInfo, params).then((result) {
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
          _incounterid = data['incounterid']?.toString();
          _incountername = data['incountername']?.toString();
          _incountertype = data['incountertype']?.toString();
          _psname = data['psname']?.toString();
          _psuserid = data['psuserid']?.toString();
          _outhandlerid = data['outhandlerid']?.toString();
          _outhandlername = data['outhandlername']?.toString();
          _inhandlerid = data['inhandlerid']?.toString();
          _inhandlername = data['inhandlername']?.toString();
          _outstocksaleflag = data['outstocksaleflag']?.toString();
          _dbbillid = data['dbbillid']?.toString();
          _dbbillno = data['dbbillno']?.toString();
          _remarkController.text = data['remark']?.toString() ?? '';
          _fileLists = (data['fileLists'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];

          // 调出时间（对齐 Vue：billdate.split(" ")[0]）
          final bdStr = data['billdate']?.toString() ?? '';
          final billStr = bdStr.contains(' ') ? bdStr.split(' ')[0] : bdStr;
          _billdate = DateTime.tryParse(billStr);
          _billdateController.text = billStr;

          // 多级审批数据
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
          _inStoretype = int.tryParse(data['inStoretype']?.toString() ?? '');
          _outStoretype = int.tryParse(data['outStoretype']?.toString() ?? '');

          // 明细
          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            _applyWriteData(c);
            final row = _DetailRow();
            row.prodid = c['productid']?.toString() ?? c['prodid']?.toString() ?? '';
            row.barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            row.qtyController.text = c['qty']?.toString() ?? '';
            // 对齐 Vue：单价列 price（详情返回的调拨单价，默认进价）
            row.priceController.text = c['price']?.toString() ?? c['inprice']?.toString() ?? '';
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
      if (mounted) {
        setState(() => _detailLoading = false);
        // 对齐 Vue getInfo：加载调入/调出机构类型
        _loadStoreTypes();
      }
    });
  }

  /// 加载机构类型（对齐 Vue getInfo：store/getInfo 获取调入/调出机构 storetype）
  void _loadStoreTypes() {
    final insid = _insid ?? '';
    final outsid = _outsid ?? '';
    if (insid.isNotEmpty && outsid.isNotEmpty) {
      request(HttpApi.storeGetInfo, {'bsid': insid}).then((res) {
        final instoreType = int.tryParse(res['data']?['storetype']?.toString() ?? '');
        request(HttpApi.storeGetInfo, {'bsid': outsid}).then((res2) {
          final outstoreType = int.tryParse(res2['data']?['storetype']?.toString() ?? '');
          if (mounted && instoreType != null && outstoreType != null) {
            setState(() {
              _inStoretype = instoreType;
              _outStoretype = outstoreType;
              _instoretypes = [instoreType, outstoreType];
              _outstoretypes = [instoreType, outstoreType];
            });
          }
        });
      });
    }
  }

  // =================== 提交保存 ===================
  Future<void> _submit({bool withSign = false, bool skipStockCheck = false}) async {
    if (!PermissionUtils.checkPermission('012803', showTip: false)) {
      Toast.show('你无权保存调拨出库单，请在后台修改权限');
      return;
    }
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
    if ((_incounterid ?? '').isEmpty) {
      Toast.show('请选择调入仓库');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择调出机构');
      return;
    }
    if ((_outcounterid ?? '').isEmpty) {
      Toast.show('请选择调出仓库');
      return;
    }
    // 双配送中心间调拨时最终校验仓库类型一致（选择仓库时已拦截，此处兜底防绕过）
    if (!_isCounterTypeMatched()) return;

    // 对齐 Vue save：数量为 0 时弹窗提示修改（productNotqty billName="dbck"）
    final zeroRows = _items
        .where((row) =>
            (row.prodid ?? '').isNotEmpty &&
            (double.tryParse(row.qtyController.text.trim()) ?? 0) <= 0)
        .toList();
    if (zeroRows.isNotEmpty) {
      final handled = await _showZeroQtyDialog(zeroRows);
      if (!handled) return;
      // 对齐 Vue handleProductNotqtyConfirm：弹窗确认修改后重新纯保存（save(0)）
      _submit();
      return;
    }

    // 对齐 Vue save：batchValidateFlag=1 时有有效日期的商品必须输入批次
    if (_loginParamInt('batchValidateFlag') == 1) {
      final batchViolations = _items.where((row) {
        if ((row.prodid ?? '').isEmpty) return false;
        final batchno = (row.batchno ?? row.batchController.text).trim();
        final validdate = row.rawData?['validdate']?.toString() ?? '';
        return batchno.isEmpty && validdate.isNotEmpty;
      }).toList();
      if (batchViolations.isNotEmpty) {
        // 对齐 Vue FiveSeconds 弹窗：列出必须输入批次的商品行
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('以下商品必须输入批次：'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in batchViolations)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                          '第【${_items.indexOf(row) + 1}】行商品【${row.nameController.text}】必须输入批次号',
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
            ],
          ),
        );
        return;
      }
    }

    setState(() => _submitAction = _DeliveryAction.save);

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
    params['incounterid'] = _incounterid ?? '';
    params['incountername'] = _incountername ?? '';
    params['incountertype'] = _incountertype ?? '';
    params['psname'] = _psname ?? '';
    params['psuserid'] = _psuserid ?? '';
    params['outhandlerid'] = _outhandlerid ?? '';
    params['outhandlername'] = _outhandlername ?? '';
    params['inhandlerid'] = _inhandlerid ?? '';
    params['inhandlername'] = _inhandlername ?? '';
    params['outstocksaleflag'] = _outstocksaleflag ?? '';
    // 对齐 Vue formDefault：bsidtype = 'outsid'
    params['bsidtype'] = 'outsid';
    params['dbbillid'] = _dbbillid ?? '';
    params['dbbillno'] = _dbbillno ?? '';
    params['billdate'] = _billdateController.text;
    params['remark'] = _remarkController.text.trim();
    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt, 3);
    params['detaillist'] = detaillist;
    params['fileLists'] = _fileLists;

    request(HttpApi.dbstockoutSave, params).then((result) {
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
        if (withSign && PermissionUtils.checkPermission('012805', showTip: false)) {
          _doSignAfterSave(retData, skipStockCheck: skipStockCheck);
        }
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliveryAction.none);
    });
  }

  /// 保存后审核
  void _doSignAfterSave(Map<String, dynamic> savedData, {bool skipStockCheck = false}) {
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
          _doSign(skipStockCheck: skipStockCheck);
        }
      });
    } else {
      _doSign(skipStockCheck: skipStockCheck);
    }
  }

  /// 执行审核（对齐 Vue signApi；sign 前执行库存不足校验）
  Future<void> _doSign({bool skipStockCheck = false}) async {
    if (_billData == null) return;
    if (!skipStockCheck) {
      final stockResult = await _checkStockLess();
      if (!mounted) return;
      if (stockResult == _StockCheckResult.blocked) return;
      if (stockResult == _StockCheckResult.resaveSkipCheck) {
        // 对齐 Vue handleStockLessConfirm：警告模式确认后 save(1, 1) 重新保存并审核
        _submit(withSign: true, skipStockCheck: true);
        return;
      }
      if (stockResult == _StockCheckResult.resaveRecheck) {
        // 阻止模式修改完毕：重新保存并重新完整校验（对齐用户重新点审核）
        _submit(withSign: true);
        return;
      }
    }
    final params = Map<String, dynamic>.from(_billData!);
    params['signflag'] = 1;
    params['reviewremark'] = _billData?['reviewremark']?.toString() ?? '';
    final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
    if (reviewsignflag != 2 && reviewsignflag != 0) {
      params['reviewsignflag'] = 1;
    }
    setState(() => _submitAction = _DeliveryAction.sign);
    request(HttpApi.dbstockoutSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliveryAction.none);
    });
  }

  /// 数量为 0 弹窗（对齐 Vue productNotqty billName="dbck"：展示调出机构库存，可改数量/删除）
  /// 返回 true=数量已改好（调用方需重新保存），false=取消
  Future<bool> _showZeroQtyDialog(List<_DetailRow> zeroRows) async {
    final result = await showDialog<List<_DetailRow>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ZeroQtyDialog(items: zeroRows),
    );
    if (result == null || !mounted) return false;
    // 对齐 Vue handleProductNotqtyConfirm：移除已删行并按新数量重算金额
    setState(() {
      _items.removeWhere((row) => !result.contains(row));
      for (final row in result) {
        _recalcRowAmt(row);
      }
    });
    return true;
  }

  /// 审核前库存不足校验（对齐 Vue save→sign 链路的 storageNotEnoughFlag 处理）
  Future<_StockCheckResult> _checkStockLess() async {
    final flag = _stockCheckFlag();
    // 与 Vue 一致：仅 2（警告可继续）/3（阻止）时执行校验
    if (flag != 2 && flag != 3) return _StockCheckResult.pass;

    List<_DetailRow> findInsufficient() => _items.where((row) {
          if ((row.prodid ?? '').isEmpty) return false;
          final stock = double.tryParse(row.rawData?['stockoutqty']?.toString() ??
                  row.rawData?['outstockqty']?.toString() ??
                  '0') ??
              0;
          final qty = double.tryParse(row.qtyController.text) ?? 0;
          return stock < qty;
        }).toList();

    final lessItems = findInsufficient();
    if (lessItems.isEmpty) return _StockCheckResult.pass;

    // 弹窗文案对齐 Vue stockLessQty：警告模式(2)可继续审核，阻止模式(3)需修改数量
    final isWarning = flag == 2;
    final result = await showDialog<List<_DetailRow>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StockLessDialog(
        items: lessItems,
        title: isWarning ? '库存不足' : '库存不足，无法审核',
        desc: isWarning ? '以下是库存不足的商品，请确认是否要继续审核' : '以下是库存不足的商品，请修改数量后再审核',
        confirmText: isWarning ? '继续审核' : '确定',
      ),
    );
    if (result == null || !mounted) return _StockCheckResult.blocked;

    // 写回数量、移除已删行并重算金额（对齐 Vue handleStockLessConfirm 的 writeData）
    setState(() {
      _items.removeWhere((row) => !result.contains(row));
      for (final row in result) {
        _recalcRowAmt(row);
      }
    });

    if (isWarning) {
      // 对齐 Vue handleStockLessConfirm：flag=2 确认后重新保存并继续审核
      return _StockCheckResult.resaveSkipCheck;
    }
    // 阻止模式：修改后若仍有库存不足，禁止审核
    if (findInsufficient().isNotEmpty) {
      Toast.show('库存不足，请修改数量后再审核');
      return _StockCheckResult.blocked;
    }
    return _StockCheckResult.resaveRecheck;
  }

  /// storageNotEnoughFlag 计算（对齐 Vue：outstocksaleflag 映射，空/0 取全局参数）
  int _stockCheckFlag() {
    final outstocksaleflag = (_outstocksaleflag ?? '').trim();
    if (outstocksaleflag.isEmpty || outstocksaleflag == '0') {
      return _loginParamInt('storageNotEnoughFlag');
    }
    if (outstocksaleflag == '1') return 2;
    if (outstocksaleflag == '2') return 1;
    return int.tryParse(outstocksaleflag) ?? 0;
  }

  /// 读取登录参数指定 key 的 int 值（对齐 Vue loginParamResp）
  static int _loginParamInt(String key) {
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isEmpty) return 0;
      final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
      return int.tryParse(cfg[key]?.toString() ?? '0') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 反审核（对齐 Vue fsignFn）
  Future<void> _retsign() async {
    if (!PermissionUtils.checkPermission('012806', showTip: false)) {
      Toast.show('你无权反审核调拨出库单，请在后台修改权限');
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

    setState(() => _submitAction = _DeliveryAction.retsign);
    final params = Map<String, dynamic>.from(_billData!);
    request(HttpApi.dbstockoutRetsign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '反审成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliveryAction.none);
    });
  }

  /// 撤回操作（对齐 Vue restsign：设置 reviewsignflag=2 后调用 save(1)）
  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('012805', showTip: false)) {
      Toast.show('你无权审核调拨出库单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('撤回单据后，所有审批步骤需重新处理！是否撤回该调拨出库单？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    // 对齐 Vue：query.value.reviewsignflag = 2 → save(1)
    // 直接调 sign API 绕过保存流程，避免 _doSignAfterSave 误弹审批弹窗
    setState(() => _submitAction = _DeliveryAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.dbstockoutSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliveryAction.none);
    });
  }

  /// 删除单据（对齐 Vue delBill）
  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('012804', showTip: false)) {
      Toast.show('你无权删除调拨出库单，请在后台修改权限');
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

    setState(() => _submitAction = _DeliveryAction.delete);
    final params = {'billid': _billData!['billid']};
    request(HttpApi.dbstockoutDelBill, params).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliveryAction.none);
    });
  }

  /// 打印单据（对齐 Vue menuid: '071901'）
  Future<void> _print() async {
    if (!PermissionUtils.checkPermission('012807', showTip: false)) {
      Toast.show('你无权打印调拨出库单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    setState(() => _submitAction = _DeliveryAction.print);
    request(HttpApi.dbstockoutPrint, {
      'menuid': '071901',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _DeliveryAction.none);
    });
  }

  /// 附件（对齐 Vue openAttach：menuid '071901'）
  Future<void> _openAttach() async {
    final result = await AttachPage.show(
      context,
      fileLists: _fileLists,
      menuid: '071901',
      billid: _billData?['billid']?.toString() ?? _newBillid ?? '',
      billno: _billData?['billno']?.toString() ?? '',
    );
    if (result != null && mounted) {
      setState(() => _fileLists = result);
    }
  }

  // =================== 机构选择 ===================
  /// 选择调出机构（对齐 Vue outStoreMergeData + handleOutStoreConfirm + watch outsid）
  Future<void> _selectOutStore() async {
    final isPs = _myStoreType == 3;
    final result = await SelectStorePage.show(
      context,
      title: '选择调出机构',
      initialSelectedId: _outsid,
      nostoreid: _insid,
      storetypes: isPs ? [3] : (_instoretypes.isNotEmpty ? _instoretypes : [0, 1, 3]),
      stopflag: '0',
    );
    if (result != null && mounted) {
      final newOutid = result['storeid']?.toString() ?? '';
      final st = int.tryParse(result['storetype']?.toString() ?? '');
      setState(() {
        _outsid = newOutid;
        _outstorename = result['storename']?.toString() ?? '';
        // 对齐 Vue handleOutStoreConfirm：清空调出仓库
        _outcounterid = null;
        _outcountername = null;
        _outcountertype = null;
        _outStoretype = st;
        _outstoretypes = st != null ? [0, st] : [];
        // 对齐 Vue handleOutStoreConfirm：调出机构与调入机构相同时清空调入方
        if (_insid != null && _insid!.isNotEmpty && _insid == newOutid) {
          _insid = null;
          _instorename = null;
          _instoretypes = [];
          _inStoretype = null;
          _incounterid = null;
          _incountername = null;
          _incountertype = null;
        }
      });
      // 对齐 Vue watch outsid：新增时自动带出默认出库仓库（stockoutflag==1）
      if (newOutid.isNotEmpty && !_isEdit) {
        _autoFillOutCounter(newOutid);
      }
    }
  }

  /// 选择调出机构后自动带出默认出库仓库（对齐 Vue watch outsid）
  /// 按 countertype 优先级取默认仓库：零售(0) > 常温(1) > 冷藏(2) > 冷冻(3)
  void _autoFillOutCounter(String outsid) {
    request(HttpApi.counterGetList, {
      'sids': [int.tryParse(outsid) ?? 0],
      'is_page': 0,
      'stopflag': 0,
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isEmpty) return;
      // 筛选默认出库仓库（stockoutflag==1），按 countertype 优先级取默认仓库：
      // 零售(0) > 常温(1) > 冷藏(2) > 冷冻(3)，无类型字段的排在最后
      final sorted = list
          .whereType<Map<String, dynamic>>()
          .where((e) => e['stockoutflag']?.toString() == '1')
          .toList()
        ..sort((a, b) {
          final va = int.tryParse(a['countertype']?.toString() ?? '');
          final vb = int.tryParse(b['countertype']?.toString() ?? '');
          if (va == null && vb == null) return 0;
          if (va == null) return 1; // 无类型排最后
          if (vb == null) return -1;
          return va.compareTo(vb);
        });
      if (sorted.isEmpty) return;
      final r = sorted.first;
      final rowType = r['countertype']?.toString() ?? '';
      final bool isZd = _spid != null && outsid == _spid.toString();
      // 对齐 Vue watch outsid：已选调入仓库且存储方式不一致时仅提示，不带出
      if ((_incounterid ?? '').isNotEmpty && _incountertype != rowType) {
        Toast.show('调入仓库与调出仓库的仓库类型不一致');
        return;
      }
      setState(() {
        _outcounterid = r['counterid']?.toString() ?? '';
        _outcountername = r['countername']?.toString() ?? '';
        _outcountertype = rowType;
        if (isZd) {
          _outstoretypes = rowType == '0' ? [0, 1] : [0, 3];
        }
      });
    });
  }

  /// 选择调入机构（对齐 Vue inStoreMergeData + handleInStoreConfirm）
  Future<void> _selectInStore() async {
    final isPs = _myStoreType == 3;
    final result = await SelectStorePage.show(
      context,
      title: '选择调入机构',
      initialSelectedId: _insid,
      nostoreid: _outsid,
      storetypes: isPs ? [3] : (_outstoretypes.isNotEmpty ? _outstoretypes : [0, 1, 3]),
      nosidsflag: '1',
      stopflag: '0',
    );
    if (result != null && mounted) {
      final newInid = result['storeid']?.toString() ?? '';
      final st = int.tryParse(result['storetype']?.toString() ?? '');
      setState(() {
        _insid = newInid;
        _instorename = result['storename']?.toString() ?? '';
        // 对齐 Vue handleInStoreConfirm：清空调入仓库
        _incounterid = null;
        _incountername = null;
        _incountertype = null;
        _inStoretype = st;
        _instoretypes = st != null ? [0, st] : [];
        // 对齐 Vue handleInStoreConfirm：调入机构与调出机构相同时清空调出方
        if (_outsid != null && _outsid!.isNotEmpty && _outsid == newInid) {
          _outsid = null;
          _outstorename = null;
          _outstoretypes = [];
          _outStoretype = null;
          _outcounterid = null;
          _outcountername = null;
          _outcountertype = null;
        }
      });
    }
  }

  /// 出库仓库与调入仓库类型一致性校验（对齐配退申请 returnapplication 的仓库类型联动）：
  /// 仅当调出机构与调入机构均为配送中心（storetype==3）时执行，
  /// 双仓均已选且类型不一致时 Toast 提示并返回 false，其余场景放行
  bool _isCounterTypeMatched() {
    if (_outStoretype != 3 || _inStoretype != 3) return true;
    if ((_outcounterid ?? '').isEmpty || (_incounterid ?? '').isEmpty) return true;
    if (_outcountertype == _incountertype) return true;
    Toast.show('出库仓库与配送中心仓库类型不一致，请重新选择');
    return false;
  }

  /// 选择调出仓库（对齐 Vue outWareMergeData + handleOutCounterConfirm）
  Future<void> _selectOutCounter() async {
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请先选择调出机构');
      return;
    }
    final bool isZd = _spid != null && _outsid == _spid.toString();
    final result = await CommonSelectSheet.show(
      context,
      title: '选择调出仓库',
      searchHint: '输入仓库名称/编码',
      initialSelectedId: _outcounterid,
      nameField: 'countername',
      codeField: 'countercode',
      idField: 'counterid',
      fetchData: (searchText, page) => request(HttpApi.counterGetList, {
        'sids': [int.tryParse(_outsid ?? '') ?? 0],
        'nosidsflag': 1,
        'stopflag': 0,
        // 对齐 Vue outWareMergeData：本店调出且调入机构含配送时仅限配送仓
        'countertype': isZd && _instoretypes.contains(1) ? '0' : '',
        // 对齐 Vue outWareMergeData：pscounterflag = outstoretypes 含 3 时取调入机构 id
        'pscounterflag': _outstoretypes.contains(3) ? (_insid ?? '') : '',
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
      final newType = result['countertype']?.toString() ?? '';
      // 对齐配退申请 returnapplication 仓库类型联动：双配送中心间调拨时，
      // 出库仓库类型须与已选调入仓库类型一致，不一致则不采纳本次选择
      if (_outStoretype == 3 &&
          _inStoretype == 3 &&
          (_incounterid ?? '').isNotEmpty &&
          (_incountertype ?? '').isNotEmpty &&
          newType != _incountertype) {
        Toast.show('出库仓库与配送中心仓库类型不一致，请重新选择');
        return;
      }
      // 对齐 Vue handleOutCounterConfirm：调入仓库已选且存储方式不一致时拦截（非本店或调入机构为配送时）
      if ((_incounterid ?? '').isNotEmpty &&
          (_incountertype ?? '').isNotEmpty &&
          newType != _incountertype &&
          (!isZd || _inStoretype == 3)) {
        Toast.show('调出仓库和调入仓库的存储方式（常温、冷藏、冷冻）需一致');
        return;
      }
      setState(() {
        _outcounterid = result['counterid']?.toString() ?? '';
        _outcountername = result['countername']?.toString() ?? '';
        _outcountertype = newType;
        // 对齐 Vue：记录调出仓库库存销售标志（提交时随单据带上）
        _outstocksaleflag = result['stocksaleflag']?.toString() ?? '';
        // 对齐 Vue handleOutCounterConfirm：本店调出时联动调出机构可选仓库类型
        if (isZd) {
          _outstoretypes = newType == '0' ? [0, 1] : [0, 3];
        }
      });
    }
  }

  /// 选择调入仓库（对齐 Vue inWareMergeData + handleInCounterConfirm）
  Future<void> _selectInCounter() async {
    if ((_insid ?? '').isEmpty) {
      Toast.show('请先选择调入机构');
      return;
    }
    final bool isZd = _spid != null && _insid == _spid.toString();
    final result = await CommonSelectSheet.show(
      context,
      title: '选择调入仓库',
      searchHint: '输入仓库名称/编码',
      initialSelectedId: _incounterid,
      nameField: 'countername',
      codeField: 'countercode',
      idField: 'counterid',
      fetchData: (searchText, page) => request(HttpApi.counterGetList, {
        'sids': [int.tryParse(_insid ?? '') ?? 0],
        'nosidsflag': 1,
        'stopflag': 0,
        // 对齐 Vue inWareMergeData：本店调入且调出机构含配送时仅限配送仓
        'countertype': isZd && _outstoretypes.contains(1) ? '0' : '',
        // 对齐 Vue inWareMergeData：调出机构含配送类型时 pscounterflag 固定为 1
        'pscounterflag': _outstoretypes.contains(3) ? 1 : '',
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
      final newType = result['countertype']?.toString() ?? '';
      // 对齐配退申请 returnapplication 仓库类型联动：双配送中心间调拨时，
      // 调入仓库类型须与已选调出仓库类型一致，不一致则不采纳本次选择
      if (_outStoretype == 3 &&
          _inStoretype == 3 &&
          (_outcounterid ?? '').isNotEmpty &&
          (_outcountertype ?? '').isNotEmpty &&
          newType != _outcountertype) {
        Toast.show('出库仓库与配送中心仓库类型不一致，请重新选择');
        return;
      }
      // 对齐 Vue handleInCounterConfirm：调出仓库已选且存储方式不一致时拦截（非本店或调出机构为配送时）
      if ((_outcounterid ?? '').isNotEmpty &&
          (_outcountertype ?? '').isNotEmpty &&
          newType != _outcountertype &&
          (!isZd || _outStoretype == 3)) {
        Toast.show('调出仓库和调入仓库的存储方式（常温、冷藏、冷冻）需一致');
        return;
      }
      setState(() {
        _incounterid = result['counterid']?.toString() ?? '';
        _incountername = result['countername']?.toString() ?? '';
        _incountertype = newType;
        // 对齐 Vue handleInCounterConfirm：本店调入时联动调入机构可选仓库类型
        if (isZd) {
          _instoretypes = newType == '0' ? [0, 1] : [0, 3];
        }
      });
    }
  }

  /// 选择发货经手人（对齐 Vue handler-form-item :mergeData="{ sids: form.outsid }"）
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

  /// 选择收货经手人（对齐 Vue handler-form-item :mergeData="{ sids: form.insid }"）
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

  /// 选择调拨申请单（对齐 Vue jumpPge('dbsq')）
  Future<void> _selectAllotApply() async {
    // 如果有商品明细，提示会清空
    if (_items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提示'),
          content: const Text('选择调拨申请单会清空当前商品，是否继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      );
      if (confirm != true) return;
    }
    // 导航到调拨申请列表选择（共用查询/选择页：dborder/findList + 调拨申请单卡片）
    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceivingnoteSearchPage(
          isSelect: true,
          billType: SearchBillType.allotApply,
          mergData: {
            if ((_outsid ?? '').isNotEmpty) 'outsid': _outsid ?? '',
            if ((_insid ?? '').isNotEmpty) 'insid': _insid ?? '',
          },
        ),
      ),
    );
    if (result != null && mounted) {
      _loadFromAllotApply(result['billid']?.toString() ?? '');
    }
  }

  /// 从调拨申请单加载数据（对齐 Vue orderFormItem confirm：不覆盖机构字段，明细带出）
  void _loadFromAllotApply(String billid) {
    if (billid.isEmpty) return;
    request(HttpApi.dborderGetInfo, {'billid': billid}).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is! Map<String, dynamic>) return;
      setState(() {
        _dbbillid = data['billid']?.toString() ?? '';
        _dbbillno = data['billno']?.toString() ?? '';

        // 明细
        for (final row in _items) {
          row.dispose();
        }
        _items.clear();
        final list = data['detaillist'] as List? ?? [];
        for (final v in list) {
          if (v is! Map) continue;
          final c = Map<String, dynamic>.from(v);
          // 对齐 Vue confirm：单价=进价、数量按开关与已入数量计算、金额独立计算
          final double qty0 = double.tryParse(c['qty']?.toString() ?? '0') ?? 0;
          final double rrqty = double.tryParse(c['rrqty']?.toString() ?? '0') ?? 0;
          final double price = double.tryParse(c['inprice']?.toString() ?? '0') ?? 0;
          final double costprice = double.tryParse(c['costprice']?.toString() ?? '0') ?? 0;
          final double sellprice = double.tryParse(c['sellprice']?.toString() ?? '0') ?? 0;
          final double newQty = _lsPsOrderQtyFlag() ? 0 : MathUtils.subtract(qty0, rrqty);
          c['price'] = MathUtils.formatDecimal(2, price);
          c['qty'] = MathUtils.formatDecimal(1, newQty);
          c['amt'] = MathUtils.formatDecimal(2, MathUtils.mul(newQty, price));
          c['costamt'] = MathUtils.formatDecimal(2, MathUtils.mul(newQty, costprice));
          c['sellamt'] = MathUtils.formatDecimal(2, MathUtils.mul(newQty, sellprice));
          c['stockoutqty'] =
              MathUtils.formatDecimal(1, double.tryParse(c['outstockqty']?.toString() ?? '0') ?? 0);
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

  /// 读取登录参数 lsPsOrderQtyFlag（申请单带出数量为 0 开关，对齐 Vue loginParamResp）
  static bool _lsPsOrderQtyFlag() {
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
        return cfg['lsPsOrderQtyFlag']?.toString() == '1';
      }
    } catch (_) {}
    return false;
  }

  // =================== 商品选择与扫码 ===================
  Future<void> _selectProducts() async {
    // 对齐 Vue selectProductFn 校验
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择调入机构');
      return;
    }
    if ((_incounterid ?? '').isEmpty) {
      Toast.show('请选择调入仓库');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择调出机构');
      return;
    }
    if ((_outcounterid ?? '').isEmpty) {
      Toast.show('请选择调出仓库');
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
          // 对齐 Vue selectProduct mergeData
          mergData: {
            'insid': _insid ?? '',
            'outsid': _outsid ?? '',
            'itemstatusin': '1,2,3,4',
            'memorytype': _incountertype ?? '',
            'counterid': _outcounterid ?? '',
            'pspriceflag': 1,
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
        // 对齐 Vue productConfirm：单价=进价，调出库存=机构库存
        c['price'] = c['inprice']?.toString() ?? c['price']?.toString() ?? '0';
        c['stockoutqty'] = c['outstockqty']?.toString() ?? c['stockoutqty']?.toString() ?? '';
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
    // 校验四个必填
    if ((_insid ?? '').isEmpty) {
      Toast.show('请选择调入机构');
      return;
    }
    if ((_incounterid ?? '').isEmpty) {
      Toast.show('请选择调入仓库');
      return;
    }
    if ((_outsid ?? '').isEmpty) {
      Toast.show('请选择调出机构');
      return;
    }
    if ((_outcounterid ?? '').isEmpty) {
      Toast.show('请选择调出仓库');
      return;
    }

    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;

    request(HttpApi.productGetList, {
      'barcode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      // 对齐 Vue scan-barcode mergeData
      'insid': _insid ?? '',
      'outsid': _outsid ?? '',
      'itemstatusin': '1,2,3,4',
      'memorytype': _incountertype ?? '',
      'counterid': _outcounterid ?? '',
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
      // 对齐 Vue productConfirm/handleProperty：扫码带入单价=进价
      c['price'] = c['inprice']?.toString() ?? c['price']?.toString() ?? '0';
      c['stockoutqty'] = c['outstockqty']?.toString() ?? c['stockoutqty']?.toString() ?? '';
      double qty = double.tryParse(c['qty']?.toString() ?? '0') ?? 0;
      if (scaleInfo?.type == 'weight') {
        qty = scaleInfo!.qty ?? qty + 1;
      } else if (scaleInfo?.type == 'amount') {
        // 金额条码按调拨单价（进价）反算数量
        final price = double.tryParse(c['price']?.toString() ?? '0') ?? 0;
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
  /// 对齐 Vue writeData：qty 变化时重算 jsqty/sellamt/amt/costamt（三类金额独立计算）
  static void _applyWriteData(Map<String, dynamic> row) {
    final qty = double.tryParse(row['qty']?.toString() ?? '0') ?? 0;
    final packagenum = double.tryParse(row['packagenum']?.toString() ?? '1') ?? 1;
    row['jsqty'] =
        MathUtils.formatDecimal(1, MathUtils.divide(qty, packagenum == 0 ? 1 : packagenum));
    row['qty'] = MathUtils.formatDecimal(1, qty);
    // 对齐 Vue writeData：零售金额 = 数量 × 零售价
    final sellprice = double.tryParse(row['sellprice']?.toString() ?? '') ?? 0;
    row['sellamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, sellprice));
    // 单价：优先取已设置 price（进价/配送价），否则取进价
    final price = double.tryParse(row['price']?.toString() ?? '') ??
        double.tryParse(row['inprice']?.toString() ?? '') ??
        0;
    row['price'] = MathUtils.formatDecimal(2, price);
    // 对齐 Vue writeData：调拨金额 = 数量 × 单价
    row['amt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, price));
    // 成本金额 = 数量 × 成本价
    final costprice = double.tryParse(row['costprice']?.toString() ?? '') ?? 0;
    row['costamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, costprice));
    row['stockoutqty'] = MathUtils.formatDecimal(
        1,
        double.tryParse(row['stockoutqty']?.toString() ?? row['outstockqty']?.toString() ?? '0') ??
            0);
  }

  void _recalcRowAmt(_DetailRow row) {
    final qty = double.tryParse(row.qtyController.text) ?? 0;
    final price = double.tryParse(row.priceController.text) ?? 0;
    row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    row.amtController.text = MathUtils.formatDecimal(3, row.amt);
    if (row.rawData != null) {
      // 对齐 Vue writeData：同步数量/单价及三类金额
      row.rawData!['qty'] = MathUtils.formatDecimal(1, qty);
      row.rawData!['price'] = MathUtils.formatDecimal(2, price);
      row.rawData!['amt'] = row.amt;
      final packagenum = double.tryParse(row.rawData!['packagenum']?.toString() ?? '1') ?? 1;
      row.rawData!['jsqty'] =
          MathUtils.formatDecimal(1, MathUtils.divide(qty, packagenum == 0 ? 1 : packagenum));
      final sellprice = double.tryParse(row.rawData!['sellprice']?.toString() ?? '') ?? 0;
      row.rawData!['sellamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, sellprice));
      final costprice = double.tryParse(row.rawData!['costprice']?.toString() ?? '') ?? 0;
      row.rawData!['costamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, costprice));
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
      // 对齐 Vue writeData：调拨金额 = 数量 × 单价（单价为进价/配送价，非零售价）
      item['amt'] = MathUtils.formatDecimalNum(
          3, double.tryParse(row.amtController.text) ?? row.amt ?? MathUtils.mul(qty, price));
      // 零售金额/成本金额独立计算
      final sellprice = double.tryParse(item['sellprice']?.toString() ?? '') ?? 0;
      item['sellamt'] = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, sellprice));
      final costprice = double.tryParse(item['costprice']?.toString() ?? '') ?? 0;
      item['costamt'] = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, costprice));
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
          _isEdit ? (_isSigned ? '调拨出库单详情' : (_isRejected ? '调拨出库单详情' : '修改调拨出库单')) : '新增调拨出库单',
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
              if (!_isSigned && !_scanSettings.showInfraredInput)
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              // 粘性表头：扫描框 + 商品明细标题栏（固定不随商品列表滚动）
              PinnedHeaderSliver(
                child: ColoredBox(
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
                        child: _buildProductHeader(),
                      ),
                    ],
                  ),
                ),
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
                        bsid: _outsid ?? '',
                        counterid: _outcounterid ?? '',
                        insid: _insid ?? '',
                        outsid: _outsid ?? '',
                        onToggle: () => _toggleIndex(index),
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
    return body;
  }

  /// 是否显示红外条码扫描输入框（未审核 + 扫码设置开启红外输入）
  bool get _showScanInput => !_isSigned && _scanSettings.showInfraredInput;

  // =================== 条码扫描输入框（对齐 allot_apply） ===================
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

  Widget _buildProductHeader() {
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                      color: const Color(0xFF006EFF), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('商品明细',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
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
                              fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
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
                            color:
                                _isSelectMode ? const Color(0xFF6B7280) : const Color(0xFFFF4D4F)),
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
            Row(children: [
              Expanded(
                  child: Text('制单信息：$createtime',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              Text(createname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            ]),
            if (signflag == '1' && (signtime.isNotEmpty || signname.isNotEmpty)) ...[
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                    child: Text('审核信息：$signtime',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                Text(signname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalNodeCard() {
    String currentInfo = '';
    if (_reviewFlowUsers.isNotEmpty) {
      final node = _reviewFlowUsers[0];
      final index = node['index']?.toString() ?? '1';
      final stepname = node['stepname']?.toString() ?? '';
      final username = node['username']?.toString() ?? '';
      currentInfo = '当前在第$index节点【$stepname】';
      if (username.isNotEmpty) currentInfo += '，审批人:$username';
    } else if (_reviewBillFlows.isNotEmpty) {
      final node = _reviewBillFlows[0];
      final stepname = node['stepname']?.toString() ?? '';
      final username = node['username']?.toString() ?? '';
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
          border: Border.all(color: const Color(0xFFE5E7EB))),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('审核日志',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
            if (totalNodes > 0)
              Text('共$totalNodes个审批节点',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
          ]),
          const SizedBox(height: 10),
          if (currentInfo.isNotEmpty)
            Row(children: [
              Expanded(
                  child: Text(currentInfo,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
              GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child:
                      const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF)))),
            ])
          else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('等待审核中...', style: TextStyle(fontSize: 13, color: Color(0xFFBFBFBF))),
              GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child:
                      const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF)))),
            ]),
        ],
      ),
    );
  }

  Widget _buildBillInfoReadonly() {
    return Column(children: [
      _buildReadonlyField(label: '调出机构', value: '${_outstorename ?? ''}-${_outcountername ?? ''}'),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '调入机构', value: '${_instorename ?? ''}-${_incountername ?? ''}'),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '调拨申请单', value: _dbbillno ?? ''),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '调出时间', value: _billdateController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '发货经手人', value: _outhandlername ?? ''),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '收货经手人', value: _inhandlername ?? ''),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '备注', value: _remarkController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '送货员', value: _psname ?? ''),
    ]);
  }

  Widget _buildBillInfoEditable() {
    // 左侧标签文字宽度在原 80 基础上增加 1/3（80*4/3≈107），避免"配送中心仓库"等长标签折行
    const double labelWidth = 107;
    return Column(children: [
      SelectFieldItem(
          label: '调出机构',
          labelWidth: labelWidth,
          required: true,
          value: _outstorename ?? '',
          onTap: _selectOutStore),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '调出仓库',
          labelWidth: labelWidth,
          required: true,
          value: _outcountername ?? '',
          onTap: _selectOutCounter),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '调入机构',
          labelWidth: labelWidth,
          required: true,
          value: _instorename ?? '',
          onTap: _selectInStore),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '调入仓库',
          labelWidth: labelWidth,
          required: true,
          value: _incountername ?? '',
          onTap: _selectInCounter),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '调拨申请单', labelWidth: labelWidth, value: _dbbillno ?? '', onTap: _selectAllotApply),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '调出时间',
          labelWidth: labelWidth,
          value: _billdateController.text,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _billdate ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
              locale: const Locale('zh', 'CN'),
            );
            if (picked != null && mounted) {
              setState(() {
                _billdate = picked;
                _billdateController.text =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              });
            }
          }),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      // 对齐 Vue handler-form-item：调出机构未选时点击提示
      SelectFieldItem(
          label: '发货经手人',
          labelWidth: labelWidth,
          value: _outhandlername ?? '',
          onTap: _selectOutHandler),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '收货经手人',
          labelWidth: labelWidth,
          value: _inhandlername ?? '',
          onTap: _selectInHandler),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildField(controller: _remarkController, label: '备注', hint: '请输入备注信息'),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
          label: '送货员', labelWidth: labelWidth, value: _psname ?? '', onTap: _selectDeliveryPerson),
    ]);
  }

  Widget _buildBottomBar() {
    if (_isSelectMode) return _buildBatchDeleteBar();
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 8, bottom: MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Text('调拨数量：$_totalQty，合计：$_totalAmt  共${_items.length}项',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
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
    final bool isLoading = _submitAction != _DeliveryAction.none;
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
            ])),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _DeliveryAction.save
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
                  : const Text('保存',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _DeliveryAction.sign
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
    final bool isLoading = _submitAction != _DeliveryAction.none;
    final buttons = <Widget>[];
    buttons.add(Expanded(
        child: OutlinedButton(
            onPressed: isLoading
                ? null
                : () {
                    if (PermissionUtils.checkPermission('012804', showTip: false)) {
                      _delBill();
                    } else {
                      Toast.show('你无权删除调拨出库单');
                    }
                  },
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliveryAction.delete
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6B7280)))
                : const Text('删除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    buttons.add(const SizedBox(width: 12));
    buttons.add(Expanded(
        child: ElevatedButton(
            onPressed: isLoading ? null : _print,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliveryAction.print
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    buttons.add(const SizedBox(width: 12));
    buttons.add(Expanded(
        child: OutlinedButton(
            onPressed: isLoading ? null : _restsign,
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF9900),
                side: const BorderSide(color: Color(0xFFFF9900)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliveryAction.withdraw
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF9900)))
                : const Text('撤回', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    return Row(children: buttons);
  }

  Widget _buildEditSignedButtons() {
    final bool isLoading = _submitAction != _DeliveryAction.none;
    final buttons = <Widget>[];
    if (_bolHandleTTT) {
      buttons.add(Expanded(
          child: OutlinedButton(
              onPressed: isLoading ? null : _retsign,
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF006EFF),
                  side: const BorderSide(color: Color(0xFF006EFF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _DeliveryAction.retsign
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
                  : const Text('反审核',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    }
    if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
    buttons.add(Expanded(
        child: ElevatedButton(
            onPressed: isLoading ? null : _print,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliveryAction.print
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    return Row(children: buttons);
  }

  Widget _buildNewBillButtons() {
    final bool isLoading = _submitAction != _DeliveryAction.none;
    final bool canSave = PermissionUtils.checkPermission('012803', showTip: false);
    final bool canSign = PermissionUtils.checkPermission('012805', showTip: false);
    final buttons = <Widget>[];
    buttons.add(Expanded(
        child: ElevatedButton(
            onPressed: isLoading || !canSave ? null : () => _submit(),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliveryAction.save
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    buttons.add(const SizedBox(width: 12));
    buttons.add(Expanded(
        child: ElevatedButton(
            onPressed: isLoading || !canSign ? null : () => _submit(withSign: true),
            style: ElevatedButton.styleFrom(
                backgroundColor: canSign ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _DeliveryAction.sign
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    return Row(children: buttons);
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
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
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
      ]),
    );
  }

  // =================== 通用组件 ===================
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
              if (titleRight != null) titleRight,
            ])),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: child),
      ]),
    );
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
                  textAlign: TextAlign.right)),
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
    required this.insid,
    required this.outsid,
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

  /// 调入/调出机构 id（传给弹窗，用于单位/规格接口 getProductExtendList）
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
    // 对齐 Vue：调拨单价 = price（进价/配送价），零售价独立
    final price = double.tryParse(widget.row.priceController.text.isNotEmpty
            ? widget.row.priceController.text
            : (data['price']?.toString() ?? data['inprice']?.toString() ?? '')) ??
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
        raw['amt'] = newAmt;
        // 对齐 Vue writeData：零售金额独立按零售价计算
        final sellprice0 = double.tryParse(raw['sellprice']?.toString() ?? '') ?? 0;
        raw['sellamt'] = MathUtils.formatDecimal(3, MathUtils.mul(newQty, sellprice0));
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
    final String priceText = widget.row.priceController.text.isNotEmpty
        ? widget.row.priceController.text
        : ((double.tryParse(raw?['price']?.toString() ?? '0') ?? 0).toStringAsFixed(2));
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
            if (batchno.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('批次：$batchno',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ),
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
    required this.initialPrice,
    required this.initialAmt,
    required this.initialBatch,
    required this.initialBirthdate,
    required this.initialValiddate,
    required this.initialRemark,
    this.bsid = '',
    this.counterid = '',
    this.insid = '',
    this.outsid = '',
  });
  final Map<String, dynamic> productData;
  final double initialQty;
  final double initialSellprice;

  /// 调拨单价（进价/配送价，对齐 Vue price 列）
  final double initialPrice;
  final double initialAmt;
  final String initialBatch;
  final String initialBirthdate;
  final String initialValiddate;
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
  late TextEditingController _batchCtrl;
  late TextEditingController _birthdateCtrl;
  late TextEditingController _validdateCtrl;
  late TextEditingController _remarkCtrl;

  /// 当前调拨单价（选单位/规格后被接口返回的配送价更新）
  double _price = 0;

  /// 当前零售价（选单位/规格后会被接口返回值更新）
  double _sellprice = 0;

  /// 调拨金额 = 单价 × 数量（对齐 Vue writeData amt 逻辑）
  double _amt = 0;

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
    // 对齐采购计划：数量按服务器小数位配置格式化初始化，支持小数输入
    _qtyCtrl = TextEditingController(text: MathUtils.formatDecimal(1, widget.initialQty));
    _price = widget.initialPrice;
    _batchCtrl = TextEditingController(text: widget.initialBatch);
    _birthdateCtrl = TextEditingController(text: widget.initialBirthdate);
    _validdateCtrl = TextEditingController(text: widget.initialValiddate);
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
    _currentUnit = widget.productData['unit']?.toString() ?? '';
    _currentSize = widget.productData['size']?.toString() ?? '';
    _unitonlyid = widget.productData['unitonlyid']?.toString() ?? '';
    _sizeonlyid = widget.productData['sizeonlyid']?.toString() ?? '';
    _sellprice = widget.initialSellprice;
    _syncAmts();
    _qtyCtrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _batchCtrl.dispose();
    _birthdateCtrl.dispose();
    _validdateCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  /// 数量/单价变化时实时重算两类金额
  void _onAmountChanged() {
    if (!mounted) return;
    setState(_syncAmts);
  }

  /// 金额重算（对齐 Vue writeData：amt = qty × price）
  void _syncAmts() {
    final q = double.tryParse(_qtyCtrl.text) ?? 0;
    _amt = MathUtils.formatDecimalNum(3, MathUtils.mul(q, _price));
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
    final String name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    final String barcode = data['barcode']?.toString() ?? '';
    // 配送价显示原始值（保留服务器小数位，对齐截图）
    final String psprice = data['price']?.toString() ??
        data['psprice']?.toString() ??
        data['lspsprice']?.toString() ??
        '';
    final String shelves = data['shelves']?.toString() ?? '';

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
                                child: Text('货架号：$shelves',
                                    style: const TextStyle(
                                        fontSize: 12, color: Color(0xFF6B7280), height: 1.5)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    // 商品批次（SelectBatchSheet 选择，带出日期）
                    _buildBatchSelectField(),
                    _buildDivider(),
                    // 生产日期
                    _buildDateField(label: '生产日期', ctrl: _birthdateCtrl),
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
                        // 重算最终金额
                        _syncAmts();
                        Navigator.pop(context, {
                          'qty':
                              MathUtils.formatDecimalNum(1, double.tryParse(_qtyCtrl.text) ?? 0.0),
                          // 对齐 Vue：单价为调拨价（进价/配送价），零售价独立
                          'price': MathUtils.formatDecimalNum(2, _price),
                          'sellprice': MathUtils.formatDecimalNum(2, _sellprice),
                          'amt': _amt,
                          'batchno': _batchCtrl.text.trim(),
                          'birthdate': _birthdateCtrl.text.trim(),
                          'validdate': _validdateCtrl.text.trim(),
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

  /// 数量加减字段（中间可编辑小数输入，对齐采购计划小数位处理）
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

  Widget _buildDateField({required String label, required TextEditingController ctrl}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: () => _pickDate(ctrl),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                ctrl.text.isNotEmpty ? ctrl.text : '请选择',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: ctrl.text.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }

  static Widget _buildDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));

  /// 将批次接口返回的日期字段统一格式化为 YYYY-MM-DD
  static String _formatBatchDate(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null') return '';
    try {
      final dt = DateTime.parse(s);
      final mo = dt.month.toString().padLeft(2, '0');
      final dy = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$mo-$dy';
    } catch (_) {}
    final ms = int.tryParse(s);
    if (ms != null && ms > 1000000000000) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final mo = dt.month.toString().padLeft(2, '0');
      final dy = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$mo-$dy';
    }
    return s;
  }

  /// 批次选择字段：不支持手动录入，点击文本区或右侧箭头打开选择器，选中后自动带出生产日期和有效期
  Widget _buildBatchSelectField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 100,
            child: Text('商品批次',
                style:
                    TextStyle(fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextField(
              controller: _batchCtrl,
              readOnly: true,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
              ),
              onTap: _pickBatch,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _pickBatch,
            child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFFD1D5DB)),
          ),
        ],
      ),
    );
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
        initialBatchNo: _batchCtrl.text,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _batchCtrl.text = result['batchno']?.toString() ?? '';
        final birthdate = _formatBatchDate(result['birthdate']);
        _birthdateCtrl.text = birthdate;
        final validdate = _formatBatchDate(result['validdate']);
        _validdateCtrl.text = validdate.isEmpty ? birthdate : validdate;
      });
    }
  }

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
      builder: (c) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              SizedBox(
                height: 50,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(c, tempDate),
                      child: const Text('确定', style: TextStyle(color: Color(0xFF006EFF))),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: (tempDate.year - 2020).clamp(0, 19),
                        ),
                        itemExtent: 36,
                        onSelectedItemChanged: (int i) {
                          tempDate = DateTime(2020 + i, tempDate.month, tempDate.day);
                        },
                        children: List.generate(
                          20,
                          (i) => Center(
                            child: Text('${2020 + i}年',
                                style: const TextStyle(fontSize: 16, color: Color(0xFF333333))),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: tempDate.month - 1,
                        ),
                        itemExtent: 36,
                        onSelectedItemChanged: (int i) {
                          tempDate = DateTime(tempDate.year, i + 1, tempDate.day);
                        },
                        children: List.generate(
                          12,
                          (i) => Center(
                            child: Text('${i + 1}月',
                                style: const TextStyle(fontSize: 16, color: Color(0xFF333333))),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: tempDate.day - 1,
                        ),
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
                                style: const TextStyle(fontSize: 16, color: Color(0xFF333333))),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
            ],
          ],
        ),
      ),
    );
  }

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
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showExtendOptions(String type) async {
    final data = widget.productData;
    final pid = data['productid']?.toString() ?? data['prodid']?.toString() ?? '';
    if (pid.isEmpty) {
      Toast.show('商品信息异常');
      return;
    }
    // 对齐 Vue unitSelect：基础参数 + mergeData（pspriceflag=1 返回配送价 lspsprice）
    final params = <String, dynamic>{
      'productid': pid,
      'page': 1,
      'pagesize': 99999,
      'is_page': 0,
      'ptype': 1,
      'commonflag': 1,
      'pspriceflag': 1,
      'insid': widget.insid,
      'outsid': widget.outsid,
      'itemtype': data['itemtype']?.toString() ?? '',
    };
    if (type == 'unit') {
      // 单位列 mergeData：packageflag/itemstatusin/counterid（对齐 Vue 单位列）
      params['packageflag'] = data['packageflag']?.toString() ?? '';
      params['itemstatusin'] = '1,2,3,4';
      params['counterid'] = widget.counterid;
    } else {
      // 规格列 mergeData：specflag（对齐 Vue 规格列，无 counterid/packageflag/itemstatusin）
      params['specflag'] = data['specflag']?.toString() ?? '';
    }
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
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280))),
                ])),
            Flexible(
                child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final opt = list[i];
                      return ListTile(
                          title: Text(opt['_name']?.toString() ?? ''),
                          onTap: () => Navigator.pop(ctx, opt));
                    })),
          ]),
        ),
      );
      if (selected != null && mounted) _applyExtendResult(type, selected);
    } catch (e) {
      if (mounted) Toast.show('获取${type == 'unit' ? '单位' : '规格'}失败');
    }
  }

  void _applyExtendResult(String type, Map<String, dynamic> r) {
    setState(() {
      // 对齐 Vue unitConfirm/changeSize：单价 = 配送价 lspsprice，包装数随单位/规格重置
      final lspsprice = r['lspsprice']?.toString() ?? '';
      if (lspsprice.isNotEmpty) {
        _price = double.tryParse(lspsprice) ?? _price;
        widget.productData['price'] = lspsprice;
      }
      final sellprice = r['sellprice']?.toString() ?? '';
      if (sellprice.isNotEmpty) {
        _sellprice = double.tryParse(sellprice) ?? _sellprice;
        widget.productData['sellprice'] = sellprice;
        widget.productData['retailprice'] = sellprice;
      }
      final barcode = r['sbarcode']?.toString() ?? r['barcode']?.toString() ?? '';
      if (barcode.isNotEmpty) widget.productData['barcode'] = barcode;
      final code = r['scode']?.toString() ?? r['code']?.toString() ?? '';
      if (code.isNotEmpty) widget.productData['code'] = code;
      final shelves = r['shelves']?.toString() ?? '';
      if (shelves.isNotEmpty) widget.productData['shelves'] = shelves;
      if (type == 'unit') {
        final u = r['unit']?.toString() ?? r['_name']?.toString() ?? '';
        if (u.isNotEmpty) _currentUnit = u;
        final uid = r['unitonlyid']?.toString() ?? r['_id']?.toString() ?? '';
        if (uid.isNotEmpty) _unitonlyid = uid;
        // 对齐 Vue unitConfirm：unitonlyid 非空时 packagenum = 1
        widget.productData['packagenum'] =
            uid.isNotEmpty ? '1' : (r['packagenum']?.toString() ?? '1');
        final inprice = r['inprice']?.toString();
        if (inprice != null && inprice.isNotEmpty) widget.productData['inprice'] = inprice;
      } else {
        final s = r['size']?.toString() ?? r['_name']?.toString() ?? '';
        if (s.isNotEmpty) _currentSize = s;
        final sid = r['sizeonlyid']?.toString() ?? r['_id']?.toString() ?? '';
        if (sid.isNotEmpty) _sizeonlyid = sid;
        // 对齐 Vue changeSize：sizeonlyid 非空时 packagenum = 1
        widget.productData['packagenum'] =
            sid.isNotEmpty ? '1' : (r['packagenum']?.toString() ?? '1');
      }
      _syncAmts();
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
                                    color: _actionColor(item['reviewsignflag']))),
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

// =================== 数量为 0 弹窗（对齐 Vue productNotqty billName="dbck"） ===================
class _ZeroQtyDialog extends StatefulWidget {
  const _ZeroQtyDialog({required this.items});
  final List<_DetailRow> items;

  @override
  State<_ZeroQtyDialog> createState() => _ZeroQtyDialogState();
}

class _ZeroQtyDialogState extends State<_ZeroQtyDialog> {
  final Set<_DetailRow> _toDelete = {};

  /// 记录各行编辑中的数量文本，确认时才写回 row.qtyController（取消不影响原数据）
  final Map<_DetailRow, String> _qtyEdits = {};

  @override
  Widget build(BuildContext context) {
    final remaining = widget.items.where((item) => !_toDelete.contains(item)).toList();
    return AlertDialog(
      title: const Text('本单数量为零商品信息如下,请修改数量为0的商品再保存', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 表头（对齐 Vue productNotqty：dbck 显示调出机构库存）
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              color: const Color(0xFFF5F5F5),
              child: const Row(
                children: [
                  SizedBox(width: 26), // 删除按钮占位（18 图标 + 8 间距，与行内对齐）
                  Expanded(
                      child: Text('商品名称',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
                  SizedBox(
                      width: 64,
                      child: Text('调出机构库存',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                          textAlign: TextAlign.center)),
                  SizedBox(
                      width: 72,
                      child: Text('数量',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                          textAlign: TextAlign.center)),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (ctx, index) {
                  final item = widget.items[index];
                  if (_toDelete.contains(item)) return const SizedBox.shrink();
                  return RepaintBoundary(
                    child: _QtyEditItem(
                      row: item,
                      onDelete: () => setState(() => _toDelete.add(item)),
                      onQtyChanged: (value) => _qtyEdits[item] = value,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: remaining.isEmpty
              ? null
              : () {
                  // 对齐 Vue sure()：数量必须为有效正数，否则阻止关闭
                  for (final row in remaining) {
                    final text = (_qtyEdits[row] ?? row.qtyController.text).trim();
                    final qty = double.tryParse(text);
                    if (qty == null || qty <= 0) {
                      Toast.show('数量为0, 无法保存!');
                      return;
                    }
                  }
                  // 写回数量（对齐 Vue writeData formatDecimal(1, qty)），返回剩余商品列表
                  for (final row in remaining) {
                    final text = (_qtyEdits[row] ?? row.qtyController.text).trim();
                    final qty = double.tryParse(text) ?? 0;
                    row.qtyController.text = MathUtils.formatDecimal(1, qty);
                  }
                  Navigator.pop(context, remaining);
                },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

// =================== 库存不足弹窗（对齐 Vue stockLessQty stockFiled="outstockqty"） ===================
class _StockLessDialog extends StatefulWidget {
  const _StockLessDialog({
    required this.items,
    this.title = '库存不足，无法审核',
    this.desc = '以下是库存不足的商品，请修改数量后再审核',
    this.confirmText = '确定',
  });

  final List<_DetailRow> items;
  final String title;
  final String desc;
  final String confirmText;

  @override
  State<_StockLessDialog> createState() => _StockLessDialogState();
}

class _StockLessDialogState extends State<_StockLessDialog> {
  final Set<_DetailRow> _toDelete = {};

  /// 记录各行编辑中的数量文本，确认时才写回 row.qtyController（取消不影响原数据）
  final Map<_DetailRow, String> _qtyEdits = {};

  @override
  Widget build(BuildContext context) {
    final remaining = widget.items.where((item) => !_toDelete.contains(item)).toList();
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.desc, style: const TextStyle(fontSize: 13, color: Color(0xFF606266))),
            const SizedBox(height: 8),
            // 表头（对齐 Vue stockFiledName="调出机构库存"）
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              color: const Color(0xFFF5F5F5),
              child: const Row(
                children: [
                  SizedBox(width: 26),
                  Expanded(
                      child: Text('商品名称',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
                  SizedBox(
                      width: 64,
                      child: Text('调出机构库存',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                          textAlign: TextAlign.center)),
                  SizedBox(
                      width: 72,
                      child: Text('调拨数量',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                          textAlign: TextAlign.center)),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (ctx, index) {
                  final item = widget.items[index];
                  if (_toDelete.contains(item)) return const SizedBox.shrink();
                  return RepaintBoundary(
                    child: _QtyEditItem(
                      row: item,
                      onDelete: () => setState(() => _toDelete.add(item)),
                      onQtyChanged: (value) => _qtyEdits[item] = value,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: remaining.isEmpty
              ? null
              : () {
                  // 确认时将编辑后的数量写回 row.qtyController（数量 1 位小数）
                  for (final row in remaining) {
                    final edit = _qtyEdits[row];
                    if (edit == null) continue;
                    final qty = double.tryParse(edit.trim()) ?? 0;
                    row.qtyController.text = MathUtils.formatDecimal(1, qty);
                  }
                  // 返回剩余的商品列表（未删除的）
                  Navigator.pop(context, remaining);
                },
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

/// 数量编辑弹窗中的商品行项（两个校验弹窗共用：商品名/调出机构库存/可编辑数量）
class _QtyEditItem extends StatefulWidget {
  const _QtyEditItem({required this.row, required this.onDelete, required this.onQtyChanged});
  final _DetailRow row;
  final VoidCallback onDelete;

  /// 数量编辑回调，由父弹窗统一收集，确认时才写回
  final ValueChanged<String> onQtyChanged;

  @override
  State<_QtyEditItem> createState() => _QtyEditItemState();
}

class _QtyEditItemState extends State<_QtyEditItem> {
  late TextEditingController _qtyCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.row.qtyController.text);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 调出机构库存（对齐 Vue stockoutqty = outstockqty）
    final stock = double.tryParse(widget.row.rawData?['stockoutqty']?.toString() ??
            widget.row.rawData?['outstockqty']?.toString() ??
            '0') ??
        0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          // 删除按钮
          GestureDetector(
            onTap: widget.onDelete,
            child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF4D4F)),
          ),
          const SizedBox(width: 8),
          // 商品名称
          Expanded(
            child: Text(
              widget.row.nameController.text,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 调出机构库存（固定列宽，与表头对齐）
          SizedBox(
            width: 64,
            child: Text(
              MathUtils.formatDecimal(1, stock),
              style: const TextStyle(fontSize: 12, color: Color(0xFFFF4D4F)),
              textAlign: TextAlign.center,
            ),
          ),
          // 数量（可编辑，固定列宽，与表头对齐）
          SizedBox(
            width: 72,
            child: TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(),
              ),
              onChanged: widget.onQtyChanged,
            ),
          ),
        ],
      ),
    );
  }
}
