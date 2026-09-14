import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/models/scan_settings.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/load_image.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:flutter_deer/widgets/select_field_item.dart';
import 'package:flutter_deer/widgets/voice_recognition_dialog.dart';
import 'package:sp_util/sp_util.dart';

enum _SQAction { none, save, sign, delete, retsign, print, withdraw, generate }

class CgthsqAddPage extends StatefulWidget {
  const CgthsqAddPage({super.key, this.billData});
  final Map<String, dynamic>? billData;
  @override
  State<CgthsqAddPage> createState() => _CgthsqAddPageState();
}

class _CgthsqAddPageState extends State<CgthsqAddPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _buyerController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;
  int? _storeid;
  String? _storename;
  int? _storetype;
  String? _buyerid;
  String? _buyername;
  _SQAction _submitAction = _SQAction.none;
  bool _detailLoading = false;
  late ScanSettings _scanSettings;
  bool _isSelectMode = false;
  Set<int> _selectedIndices = {};
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  bool _billSign = true;
  String _userCode = '';
  String _userid = '';
  Map<String, dynamic>? _billData;
  String? _newBillid;

  /// 附件列表
  List<Map<String, dynamic>> _fileLists = [];

  bool get _isEdit =>
      (_newBillid != null && _newBillid!.isNotEmpty) ||
      (widget.billData != null && (widget.billData!['billid']?.toString().isNotEmpty ?? false));
  bool get _isSigned => _billData?['signflag']?.toString() == '1';
  bool get _isRejected => _billData?['signflag']?.toString() == '2';
  bool get _isWithdrawPending => _billData?['reviewsignflag']?.toString() == '2';
  bool get _isAdmin => _userCode == '1001';
  bool get _bolHandle {
    final signflag = int.tryParse(_billData?['signflag']?.toString() ?? '0') ?? 0;
    if (signflag == 1) return false;
    if (_reviewFlowUsers.isEmpty) return true;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return !(firstIndex > 1);
  }

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

  final List<_DetailRow> _items = [];

  @override
  void initState() {
    super.initState();
    _scanSettings = ScanSettings.fromSp();
    _scanFocusNode = FocusNode(onKeyEvent: (FocusNode node, KeyEvent event) {
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
    });
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
    if (_isEdit) {
      _loadDetail();
    } else {
      _loadNewModeDefaults();
    }
  }

  void _loadNewModeDefaults() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeid = _parseIntFlexible(storeMap, ['id', 'storeid', 'bsid']);
        _storename = storeMap['name']?.toString();
        _storetype = _parseIntFlexible(storeMap, ['storetype']);
        _storeController.text = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _buyerid = userMap['userid']?.toString();
        _buyername = userMap['name']?.toString();
        _buyerController.text = userMap['name']?.toString() ?? '';
        _userid = userMap['userid']?.toString() ?? '';
        _userCode = userMap['code']?.toString() ?? '';
      }
    } catch (_) {}
    if (!_isEdit) _initSignUserBtn();
  }

  static int? _parseIntFlexible(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final val = map[key];
      if (val == null) continue;
      if (val is int) return val;
      if (val is double) return val.toInt();
      final str = val.toString().trim();
      if (str.isEmpty) continue;
      final parsed = int.tryParse(str);
      if (parsed != null) return parsed;
      final d = double.tryParse(str);
      if (d != null) return d.toInt();
    }
    return null;
  }

  @override
  void dispose() {
    _scanDebounceTimer?.cancel();
    _storeController.dispose();
    _buyerController.dispose();
    _remarkController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    for (final row in _items) row.dispose();
    super.dispose();
  }

  void _loadDetail([Map<String, dynamic>? overrideParams]) {
    setState(() => _detailLoading = true);
    final Map<String, dynamic> params =
        overrideParams ?? Map<String, dynamic>.from(widget.billData!);
    request(HttpApi.cgzcGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _storeController.text = data['storename']?.toString() ?? '';
          _buyerController.text = data['buyername']?.toString() ?? '';
          _remarkController.text = data['remark']?.toString() ?? '';
          _fileLists = (data['fileLists'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _storeid = _parseIntFlexible(data, ['bsid', 'storeid']);
          _storename = data['storename']?.toString();
          _storetype = _parseIntFlexible(data, ['storetype']);
          _buyerid = data['buyerid']?.toString();
          _buyername = data['buyername']?.toString();
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) row.dispose();
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            final cgprice = double.tryParse(c['cgprice']?.toString() ?? '') ?? 0;
            final oldPrice = double.tryParse(c['price']?.toString() ?? '') ?? 0;
            final price = cgprice != 0 ? cgprice : oldPrice;
            c['price'] = double.parse(price.toStringAsFixed(2));
            final row = _DetailRow();
            row.prodid = c['prodid']?.toString() ?? c['productid']?.toString() ?? '';
            row.barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            row.qtyController.text =
                MathUtils.formatDecimal(1, double.tryParse(c['qty']?.toString() ?? '') ?? 0);
            row.priceController.text = MathUtils.formatDecimal(2, price);
            // 对齐 Vue handleProperty：amt 始终由 qty*price 重算
            row.amt = MathUtils.formatDecimalNum(
                3, MathUtils.mul(double.tryParse(row.qtyController.text) ?? 0, price));
            row.amtController.text = row.amt!.toStringAsFixed(3);
            row.rawData = c;
            _items.add(row);
          }
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  void _submit({bool withSign = false}) {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('012003', showTip: false)) {
        Toast.show('你无权编辑退货申请，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('012002', showTip: false)) {
        Toast.show('你无权新增退货申请，请在后台修改权限');
        return;
      }
    }
    if (_storeid == null) {
      Toast.show('请选择退货机构');
      return;
    }
    if (!_isEdit && !_formKey.currentState!.validate()) return;
    final List<_DetailRow> submitItems = _isEdit
        ? List.from(_items)
        : _items
            .where(
                (row) => (row.prodid ?? '').isNotEmpty && row.nameController.text.trim().isNotEmpty)
            .toList();
    if (submitItems.isEmpty) {
      Toast.show('请选择商品');
      return;
    }
    for (final row in submitItems) {
      if ((double.tryParse(row.qtyController.text) ?? 0) == 0) {
        Toast.show('请填写数量');
        return;
      }
    }
    setState(() => _submitAction = _SQAction.save);
    final detaillist = _buildSubmitDetailList();
    double totalQty = 0;
    double totalAmt = 0;
    for (final item in detaillist) {
      totalQty = MathUtils.add(totalQty, double.tryParse(item['qty']?.toString() ?? '0') ?? 0);
      totalAmt = MathUtils.add(totalAmt, double.tryParse(item['amt']?.toString() ?? '0') ?? 0);
    }
    // 新增模式默认参数（对齐小程序 cgthsq/edit.vue query 初始值：
    // name/counterid/supid/supname/reviewsignflag/reviewremark/fileLists）
    final Map<String, dynamic> params = _isEdit
        ? Map<String, dynamic>.from(_billData!)
        : {
            'signflag': 0,
            'name': '',
            'counterid': '',
            'supid': '',
            'supname': '',
            'reviewsignflag': 0,
            'reviewremark': '',
            'fileLists': _fileLists,
          };
    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt);
    params['detaillist'] = detaillist;
    params['fileLists'] = _fileLists;
    params['remark'] = _remarkController.text.trim();
    params['bsid'] = _storeid ?? '';
    params['storename'] = _storename ?? '';
    params['buyerid'] = _buyerid ?? '';
    params['buyername'] = _buyername ?? '';
    params['billtype'] = '2';
    request(HttpApi.cgzcSave, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '保存成功');
      final retData = result['data'];
      if (retData is Map<String, dynamic>) {
        if (_isEdit) {
          _loadDetail(Map<String, dynamic>.from(retData));
        } else {
          final String? newBillid = retData['billid']?.toString();
          if (newBillid != null && newBillid.isNotEmpty) {
            setState(() => _newBillid = newBillid);
            // 对齐 Vue _saveAndAudit：保存成功后先同步回写 res 至 _billData（等同 query.value = res），
            // 保证紧随其后的审核流程（_doSign）能取到单据数据；_loadDetail 随后会以 getInfo 结果覆盖
            _billData = Map<String, dynamic>.from(retData);
            _loadDetail(Map<String, dynamic>.from(retData));
          } else {
            Navigator.pop(context, true);
          }
        }
        if (withSign) _doSignAfterSave(retData);
      } else {
        if (!_isEdit) Navigator.pop(context, true);
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _SQAction.none);
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
    if (_reviewFlowUsers.isNotEmpty) {
      _showApprovalDialog().then((r) {
        if (r != null && mounted) {
          _billData?['reviewsignflag'] = r['reviewsignflag'];
          _billData?['reviewremark'] = r['reviewremark'];
          _doSign();
        }
      });
    } else {
      _doSign();
    }
  }

  Future<void> _sign() async {
    if (!PermissionUtils.checkPermission('012005', showTip: false)) {
      Toast.show('你无权审核退货申请，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    if (_reviewFlowUsers.isNotEmpty) {
      final r = await _showApprovalDialog();
      if (r == null || !mounted) return;
      _billData?['reviewsignflag'] = r['reviewsignflag'];
      _billData?['reviewremark'] = r['reviewremark'];
      _doSign();
      return;
    }
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) =>
            AlertDialog(title: const Text('提示'), content: const Text('确定审核单据吗？'), actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定'))
            ]));
    if (confirm != true) return;
    _doSign();
  }

  void _doSign() {
    if (_billData == null) return;
    final params = Map<String, dynamic>.from(_billData!);
    params['signflag'] = 1;
    params['billtype'] = '2';
    params['reviewremark'] = _billData?['reviewremark']?.toString() ?? '';
    final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
    if (reviewsignflag != 2 && reviewsignflag != 0) params['reviewsignflag'] = 1;
    setState(() => _submitAction = _SQAction.sign);
    request(HttpApi.cgzcSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _SQAction.none);
    });
  }

  Future<void> _retsign() async {
    if (_billData == null) return;
    String tipMsg = '确定反审核单据吗？';
    if (_reviewBillFlows.isNotEmpty) tipMsg = '反审核单据后，所有审批步骤需重新处理！确认要反审核单据？';
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(title: const Text('提示'), content: Text(tipMsg), actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定'))
            ]));
    if (confirm != true) return;
    setState(() => _submitAction = _SQAction.retsign);
    final params = Map<String, dynamic>.from(_billData!);
    params['billtype'] = '2';
    request(HttpApi.cgzcRetsign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '反审成功');
      setState(() {
        _reviewFlowUsers = [];
        _reviewBillFlows = [];
      });
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _SQAction.none);
    });
  }

  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('012006', showTip: false)) {
      Toast.show('你无权反审核退货申请，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('提示'),
                content: const Text('撤回单据后，所有审批步骤需重新处理！确定撤回吗？'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定'))
                ]));
    if (confirm != true) return;
    setState(() => _submitAction = _SQAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    params['billtype'] = '2';
    request(HttpApi.cgzcSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _SQAction.none);
    });
  }

  Future<void> _print() async {
    if (_billData == null) return;
    setState(() => _submitAction = _SQAction.print);
    request(HttpApi.cgzcPrint, {'menuid': '050801', 'data': _billData}).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _SQAction.none);
    });
  }

  Future<void> _generateCgStockRet() async {
    if (_billData == null) return;
    setState(() => _submitAction = _SQAction.generate);
    request(HttpApi.cgthsqGenerateCgStockRet, _billData).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '操作成功');
      final retData = result['data'];
      if (retData is List && retData.isNotEmpty)
        _showGenerateResultDialog(retData.cast<Map<String, dynamic>>());
      _loadDetail(_billData);
    }).catchError((e) {
      if (mounted) Toast.show('生成退货单失败');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _SQAction.none);
    });
  }

  void _showGenerateResultDialog(List<Map<String, dynamic>> dataList) {
    showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [
                        const Expanded(
                            child: Text('生成退货单结果',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                        GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)))
                      ])),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Flexible(
                      child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: dataList.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: Color(0xFFF0F0F0)),
                          itemBuilder: (ctx, i) {
                            final item = dataList[i];
                            final billno = item['billno']?.toString() ?? '-';
                            final storename = item['storename']?.toString() ?? '';
                            final createtime = item['createtime']?.toString() ?? '';
                            final dl = item['detaillist'] as List? ?? [];
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(children: [
                                    Text('单号：$billno',
                                        style: const TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Text(storename,
                                        style:
                                            const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))
                                  ])),
                              Text('日期：$createtime',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                              if (dl.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                ...dl.take(5).map((d) {
                                  final dm =
                                      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
                                  return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Text(
                                          '${dm['productname'] ?? dm['name'] ?? ''} x${dm['qty'] ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 12, color: Color(0xFF666666))));
                                }),
                                if (dl.length > 5)
                                  Text('...共${dl.length}项',
                                      style:
                                          const TextStyle(fontSize: 11, color: Color(0xFF999999)))
                              ],
                            ]);
                          })),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF006EFF),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8))),
                              child: const Text('关闭')))),
                ]))));
  }

  void _initSignUserBtn() {
    if (_isAdmin) return;
    if (!_isEdit && _storeid != null) {
      request(HttpApi.reviewTypeConfigGetNewBillSignUser, {'billtypeid': '0508', 'bsid': _storeid})
          .then((result) {
        if (!mounted) return;
        final data = result['data'];
        if (data is List && data.isNotEmpty) {
          setState(() {
            _billSign = data.any((item) => item['userid']?.toString() == _userid);
          });
        } else {
          setState(() {
            _billSign = true;
          });
        }
      }).catchError((_) {
        if (mounted)
          setState(() {
            _billSign = false;
          });
      });
    }
  }

  static List<Map<String, dynamic>> _parseReviewList(dynamic data) {
    if (data == null) return [];
    if (data is List)
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    return [];
  }

  Future<Map<String, dynamic>?> _showApprovalDialog({int defaultFlag = 1}) async =>
      showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _ApprovalDialog(defaultFlag: defaultFlag));
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
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                child: _ApprovalLogSheet(
                    reviewBillFlows: _reviewBillFlows, scrollController: scrollCtrl))));
  }

  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('012004', showTip: false)) {
      Toast.show('你无权删除退货申请，请在后台修改权限');
      return;
    }
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) =>
            AlertDialog(title: const Text('提示'), content: const Text('确定删除吗？'), actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定'))
            ]));
    if (confirm != true) return;
    setState(() => _submitAction = _SQAction.delete);
    final params = Map<String, dynamic>.from(_billData!);
    params['billtype'] = '2';
    request(HttpApi.cgzcDelBill, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _SQAction.none);
    });
  }

  void _toggleSelectMode() => setState(() {
        _isSelectMode = !_isSelectMode;
        if (!_isSelectMode) _selectedIndices.clear();
      });
  void _toggleIndex(int index) => setState(() {
        if (_selectedIndices.contains(index))
          _selectedIndices.remove(index);
        else
          _selectedIndices.add(index);
      });
  bool get _isAllSelected => _items.isNotEmpty && _selectedIndices.length == _items.length;
  void _toggleSelectAll() => setState(() {
        if (_isAllSelected)
          _selectedIndices.clear();
        else
          _selectedIndices = Set<int>.from(List.generate(_items.length, (i) => i));
      });
  Future<void> _batchDelete() async {
    if (_selectedIndices.isEmpty) return;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('提示'),
                content: Text('确定删除选中的 ${_selectedIndices.length} 条明细？'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定'))
                ]));
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

  Future<void> _voiceRecognition() async {
    if (_storeid == null) {
      Toast.show('请先选择退货机构');
      return;
    }
    final result = await VoiceRecognitionDialog.show(context);
    if (result == null || result.isEmpty || !mounted) return;
    int matchCount = 0;
    final unmatched = <String>[];
    for (final item in result) {
      final name = item['name'] as String;
      try {
        final sr = await request(HttpApi.productGetList,
            {'keyword': name, 'is_page': 1, 'page': 1, 'pagesize': 5, ..._buildMergData()});
        if (!mounted) return;
        final data = sr['data'];
        final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
        if (list.isNotEmpty) {
          final prod = list.first as Map<String, dynamic>;
          setState(() {
            final row = _DetailRow()
              ..nameController.text =
                  prod['productname']?.toString() ?? prod['name']?.toString() ?? name
              ..qtyController.text = MathUtils.formatDecimal(
                  1, double.tryParse((item['quantity'] ?? 1).toString()) ?? 1)
              ..priceController.text = MathUtils.formatDecimal(
                  2,
                  double.tryParse(
                          (item['price'] ?? prod['cgprice'] ?? prod['price'] ?? 0).toString()) ??
                      0)
              ..prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? ''
              ..rawData = Map<String, dynamic>.from(prod);
            _recalcRow(row);
            _items.insert(0, row);
          });
          matchCount++;
        } else {
          unmatched.add(name);
        }
      } catch (_) {
        unmatched.add(name);
      }
    }
    if (!mounted) return;
    if (unmatched.isNotEmpty)
      Toast.show('已匹配 $matchCount 项，未匹配：${unmatched.join("、")}');
    else
      Toast.show('已添加 $matchCount 项商品');
  }

  String get _totalQty {
    double sum = 0;
    for (final row in _items) sum += double.tryParse(row.qtyController.text) ?? 0;
    return MathUtils.formatDecimal(1, sum);
  }

  /// 合计金额：以失焦确认后的行金额（row.amt）为准，输入中的中间态
  /// （如 "2."、未完成小数位）不计入合计；失焦时重算 amt 并经 onChanged 触发父页面刷新
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

  /// 提交前同步全部行的 amt（兜底未失焦的数量修改，对齐 Vue writeData 的 amt 重算）
  void _syncAllAmt() {
    for (final row in _items) {
      final qty = double.tryParse(row.qtyController.text) ?? 0;
      final price = double.tryParse(row.priceController.text) ?? 0;
      row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    }
  }

  /// 重算行金额 = 数量 × 单价（保留 3 位小数）并回写 amtController（对齐 Vue handleProperty）
  void _recalcRow(_DetailRow row) {
    final qty = double.tryParse(row.qtyController.text) ?? 0;
    final price = double.tryParse(row.priceController.text) ?? 0;
    row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    row.amtController.text = MathUtils.formatDecimal(3, row.amt);
  }

  List<Map<String, dynamic>> _buildSubmitDetailList() {
    _syncAllAmt();
    return _items.map((row) {
      final qty = MathUtils.formatDecimalNum(1, double.tryParse(row.qtyController.text) ?? 0);
      final price = MathUtils.formatDecimalNum(2, double.tryParse(row.priceController.text) ?? 0);
      final item =
          row.rawData != null ? Map<String, dynamic>.from(row.rawData!) : <String, dynamic>{};
      item['productname'] = row.nameController.text.trim();
      item['prodname'] = row.nameController.text.trim();
      item['qty'] = qty;
      item['price'] = price;
      item['amt'] = MathUtils.formatDecimal(
          3, double.tryParse(row.amtController.text) ?? row.amt ?? MathUtils.mul(qty, price));
      item['prodid'] = row.prodid ?? item['productid'] ?? '';
      item['productid'] = item['productid'] ?? row.prodid ?? '';
      item['unit'] = row.rawData?['unit']?.toString() ?? '';
      item['size'] = row.rawData?['size']?.toString() ?? '';
      item['unitonlyid'] = row.rawData?['unitonlyid']?.toString() ?? '';
      item['sizeonlyid'] = row.rawData?['sizeonlyid']?.toString() ?? '';
      // 对齐 Vue handleProperty：oldprice 为空时回退 cgprice（后端 t_cg_zc_detail.oldprice 不允许 NULL）
      final oldprice = double.tryParse(item['oldprice']?.toString() ?? '') ?? 0;
      final cgprice = double.tryParse(item['cgprice']?.toString() ?? '') ?? 0;
      item['oldprice'] = oldprice != 0 ? oldprice : cgprice;
      // sellamt = qty * sellprice（对齐 handleProperty）
      final sellpriceVal = item['sellprice'];
      final sellprice = double.tryParse(sellpriceVal?.toString() ?? '') ?? 0;
      item['sellamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, sellprice));
      // 毛利率 profit（对齐 jsGrossrate）
      final inprice = double.tryParse(item['inprice']?.toString() ?? '') ?? 0;
      if (sellpriceVal != null && sellprice == 0) {
        item['profit'] = '100';
      } else if (sellprice != 0 && inprice != 0) {
        item['profit'] = (((sellprice - inprice) / sellprice) * 100).toStringAsFixed(2);
      } else {
        item['profit'] = '0';
      }
      return item;
    }).toList();
  }

  Map<String, dynamic> _buildMergData() => {
        'stockflag': 1,
        'storeid': _storeid ?? '',
        'counterid': '',
        'cgpriceflag': 1,
        'itemstatusin': '1,2,3,4',
        'itemtypenot': '5,8'
      };
  bool get _readOnly => _isEdit && !_bolHandle;

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
                onPressed: () => Navigator.pop(context)),
            title: Text(
                _isEdit
                    ? (_isSigned ? '退货申请单详情' : (_isRejected ? '退货申请单详情' : '修改退货申请单'))
                    : '新增退货申请单',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
        body: _detailLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
            : _buildBody());
  }

  static const double _stickyScanHeight = 68.0;
  static const double _stickyTitleHeight = 40.0;
  static const double _stickyColumnHeight = 36.0;
  static const double _stickyMinExtent = _stickyTitleHeight + _stickyColumnHeight;
  static const double _stickyMaxExtent = _stickyScanHeight + _stickyMinExtent;

  Widget _buildBody() {
    // 键盘弹起时隐藏底部栏，给商品明细列表留出更多空间
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final body = Column(children: [
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
        if (!_isSigned && !_scanSettings.showInfraredInput)
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverPersistentHeader(pinned: true, delegate: _CgthsqStickyHeaderDelegate(state: this)),
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
      // 键盘弹起时隐藏底部汇总+按钮栏
      if (!keyboardVisible) _buildBottomBar()
    ]);
    return _isEdit ? body : Form(key: _formKey, child: body);
  }

  Widget _buildStickyHeader() {
    return Align(
        alignment: Alignment.topCenter,
        child: ColoredBox(
            color: const Color(0xFFF5F5F5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_isSigned && _scanSettings.showInfraredInput) ...[
                Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), child: _buildScanInput()),
                const SizedBox(height: 8)
              ],
              Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Container(
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
                                      color: const Color(0xFF006EFF),
                                      borderRadius: BorderRadius.circular(2))),
                              const SizedBox(width: 8),
                              const Expanded(
                                  child: Text('商品明细',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF111827)))),
                              if (!_isSigned) ...[
                                GestureDetector(
                                    onTap: _toggleSelectMode,
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                                              fontWeight: FontWeight.w500))
                                    ])),
                                // TODO: 语音识别按钮暂时隐藏，后续可重新启用
                                if (false) ...[
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                      onTap: _voiceRecognition,
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.mic, size: 16, color: Color(0xFF006EFF)),
                                        SizedBox(width: 2),
                                        Text('语音',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF006EFF),
                                                fontWeight: FontWeight.w500))
                                      ])),
                                ],
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
                                      Icon(Icons.add_circle_outline,
                                          size: 16, color: Color(0xFF006EFF)),
                                      SizedBox(width: 2),
                                      Text('新增',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF006EFF),
                                              fontWeight: FontWeight.w500))
                                    ]))
                              ],
                            ])),
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        Container(
                            color: const Color(0xFFF9FAFB),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: const Row(children: [
                              Expanded(
                                  flex: 5,
                                  child: Text('商品信息',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280),
                                          fontWeight: FontWeight.w500))),
                              Expanded(
                                  flex: 3,
                                  child: Text('单价',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280),
                                          fontWeight: FontWeight.w500))),
                              Expanded(
                                  flex: 3,
                                  child: Text('数量',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280),
                                          fontWeight: FontWeight.w500))),
                              Expanded(
                                  flex: 3,
                                  child: Text('金额',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280),
                                          fontWeight: FontWeight.w500)))
                            ])),
                      ]))),
            ])));
  }

  Widget _buildBillStatusWidget() {
    final data = _billData ?? {};
    final billno = data['billno']?.toString() ?? '-';
    final createtime = data['createtime']?.toString() ?? '-';
    final buyername = data['buyername']?.toString() ?? '';
    final signflag = data['signflag']?.toString() ?? '';
    String sl = '待审核';
    Color sc = const Color(0xFFD54B5A);
    if (signflag == '1') {
      sl = '已审核';
      sc = const Color(0xFF00A870);
    } else if (signflag == '2') {
      sl = '已驳回';
      sc = const Color(0xFFFF9900);
    }
    return _buildCard(
      title: '单号：$billno',
      titleRight: Text(sl, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: sc)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Text('制单信息：$createtime',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            const SizedBox(width: 16),
            Text(buyername, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalNodeCard() {
    Map<String, dynamic>? cn;
    String ci = '';
    if (_reviewFlowUsers.isNotEmpty) {
      cn = _reviewFlowUsers[0];
      ci = '当前在第${cn['index'] ?? '1'}节点【${cn['stepname'] ?? ''}】';
      final u = cn['username']?.toString() ?? '';
      if (u.isNotEmpty) ci += '，审批人:$u';
    } else if (_reviewBillFlows.isNotEmpty) {
      cn = _reviewBillFlows[0];
      ci = '节点【${cn['stepname'] ?? cn['stepno'] ?? ''}】';
      final u = cn['username']?.toString() ?? '';
      if (u.isNotEmpty) ci += '，审批人:$u';
    }
    final tn = _reviewFlowUsers.isNotEmpty
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
            if (tn > 0)
              Text('共$tn个审批节点', style: const TextStyle(fontSize: 12, color: Color(0xFF888888)))
          ]),
          const SizedBox(height: 10),
          if (ci.isNotEmpty)
            Row(children: [
              Expanded(
                  child: Text(ci, style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
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
            ])
        ]));
  }

  Widget _buildBillInfoReadonly() => Column(children: [
        _buildReadonlyField(label: '退货机构', value: _storeController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '经手人', value: _buyerController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '备注', value: _remarkController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildAttachButton()
      ]);
  Widget _buildBillInfoEditable() => Column(children: [
        SelectFieldItem(
            label: '退货机构',
            required: true,
            value: _storeController.text,
            onTap: () async {
              final r =
                  await SelectStorePage.show(context, initialSelectedId: _storeid?.toString());
              if (r != null && mounted)
                setState(() {
                  _storeid = int.tryParse(r['storeid']?.toString() ?? '');
                  _storename = r['storename']?.toString();
                  _storetype = int.tryParse(r['storetype']?.toString() ?? '');
                  _storeController.text = r['storename']?.toString() ?? '';
                });
            }),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
            label: '经手人',
            value: _buyerController.text,
            onTap: () async {
              final r = await SelectBuyerPage.show(context, initialSelectedId: _buyerid);
              if (r != null && mounted)
                setState(() {
                  _buyerid = r['buyerid']?.toString();
                  _buyername = r['buyername']?.toString();
                  _buyerController.text = r['buyername']?.toString() ?? '';
                });
            }),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildField(controller: _remarkController, label: '备注', hint: '请输入备注信息'),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildAttachButton()
      ]);
  Widget _buildBottomBar() {
    if (_isSelectMode) return _buildBatchDeleteBar();
    return Container(
        color: Colors.white,
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 8, bottom: MediaQuery.of(context).padding.bottom + 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('共${_items.length}项，合计数量：$_totalQty，总金额：$_totalAmt',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
          if (_isEdit && !_isSigned) _buildEditUnsignedButtons(),
          if (_isEdit && _isSigned) _buildEditSignedButtons(),
          if (!_isEdit) _buildNewBillButtons()
        ]));
  }

  Widget _buildEditUnsignedButtons() {
    final il = _submitAction != _SQAction.none;
    final b = <Widget>[];
    if (!_isWithdrawPending && _bolHandleTT)
      b.add(PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') _delBill();
            if (v == 'print') _print();
          },
          offset: const Offset(0, -120),
          itemBuilder: (_) => [
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
    final sa = !_isRejected &&
        !_isWithdrawPending &&
        (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT));
    if (sa) {
      if (b.isNotEmpty) b.add(const SizedBox(width: 12));
      b.add(Expanded(
          child: OutlinedButton(
              onPressed: il ? null : () => _submit(),
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF006EFF),
                  side: const BorderSide(color: Color(0xFF006EFF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _SQAction.save
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
                  : const Text('保存',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    }
    if (sa) {
      if (b.isNotEmpty) b.add(const SizedBox(width: 12));
      b.add(Expanded(
          child: ElevatedButton(
              onPressed: il ? null : _sign,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _SQAction.sign
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('审核',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    }
    if (_isRejected) {
      if (b.isNotEmpty) b.add(const SizedBox(width: 12));
      b.add(Expanded(
          child: ElevatedButton(
              onPressed: il ? null : _restsign,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9900),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _SQAction.withdraw
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('撤回',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    }
    return Row(children: b);
  }

  Widget _buildEditSignedButtons() {
    final il = _submitAction != _SQAction.none;
    final b = <Widget>[];
    if (_bolHandleTTT)
      b.add(Expanded(
          child: OutlinedButton(
              onPressed: il ? null : _retsign,
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF006EFF),
                  side: const BorderSide(color: Color(0xFF006EFF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _submitAction == _SQAction.retsign
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
                  : const Text('反审核',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    if (b.isNotEmpty) b.add(const SizedBox(width: 8));
    b.add(Expanded(
        child: ElevatedButton(
            onPressed: il ? null : _generateCgStockRet,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9900),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _SQAction.generate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('生成退货单',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)))));
    if (b.isNotEmpty) b.add(const SizedBox(width: 8));
    b.add(Expanded(
        child: ElevatedButton(
            onPressed: il ? null : _print,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _SQAction.print
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    return Row(children: b);
  }

  Widget _buildNewBillButtons() {
    final il = _submitAction != _SQAction.none;
    final b = <Widget>[];
    b.add(Expanded(
        child: ElevatedButton(
            onPressed: il ? null : () => _submit(),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: _submitAction == _SQAction.save
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    if (_billSign) {
      b.add(const SizedBox(width: 12));
      b.add(Expanded(
          child: ElevatedButton(
              onPressed: il ? null : () => _submit(withSign: true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9900),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child:
                  const Text('审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))));
    }
    return Row(children: b);
  }

  Widget _buildBatchDeleteBar() => Container(
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
              Text('全选 (${_selectedIndices.length}/${_items.length})',
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
            child: const Text('删除选中', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        const SizedBox(width: 12),
        OutlinedButton(
            onPressed: _toggleSelectMode,
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)))
      ]));
  Future<void> _selectProducts({String? initialKeyword, FocusNode? returnFocusNode}) async {
    if (_storeid == null) {
      Toast.show('请先选择退货机构');
      return;
    }
    final result = await Navigator.push<List<Map<String, dynamic>>>(
        context,
        MaterialPageRoute(
            builder: (_) => SelectProductPage(
                storeid: _storeid, mergData: _buildMergData(), initialKeyword: initialKeyword)));
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        for (final prod in result) {
          final pid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
          // 复合去重键对齐后台 ROW_KEYS：productid + unitonlyid + sizeonlyid，
          // 同一商品不同包装/规格视为不同行（切换单位后再选品不会覆盖已有行）
          final pu = prod['unitonlyid']?.toString() ?? '';
          final ps = prod['sizeonlyid']?.toString() ?? '';
          final ei = _items.indexWhere((r) =>
              r.prodid == pid &&
              (r.rawData?['unitonlyid']?.toString() ?? '') == pu &&
              (r.rawData?['sizeonlyid']?.toString() ?? '') == ps);
          if (ei >= 0) {
            final oq = double.tryParse(_items[ei].qtyController.text) ?? 0;
            final aq = double.tryParse(prod['qty']?.toString() ?? '1') ?? 1;
            _items[ei].qtyController.text = MathUtils.formatDecimal(1, oq + aq);
            _recalcRow(_items[ei]);
          } else {
            // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
            final rowCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
            final rowPrice = rowCgprice != 0
                ? rowCgprice
                : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
            final row = _DetailRow()
              ..nameController.text =
                  prod['productname']?.toString() ?? prod['name']?.toString() ?? ''
              ..qtyController.text =
                  MathUtils.formatDecimal(1, double.tryParse((prod['qty'] ?? 1).toString()) ?? 1)
              ..priceController.text = MathUtils.formatDecimal(2, rowPrice)
              ..prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? ''
              ..barcode = prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? ''
              ..rawData = Map<String, dynamic>.from(prod);
            _recalcRow(row);
            _items.insert(0, row);
          }
        }
      });
    }
    // 扫码多条命中跳转选品返回后恢复焦点（红外连续扫码场景）
    if (returnFocusNode != null && mounted) {
      returnFocusNode.requestFocus();
    }
  }

  Future<void> _scanBarcode() async {
    if (_storeid == null) {
      Toast.show('请先选择退货机构');
      return;
    }
    if (Device.isMobile) {
      NavigatorUtils.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final code = await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const QrCodeScannerPage()));
      if (code == null || !mounted) return;
      _handleScannedBarcode(code.toString());
    } else {
      Toast.show('当前平台暂不支持扫码');
    }
  }

  void _handleScannedBarcode(String code, {FocusNode? returnFocusNode}) {
    if (code.trim().isEmpty) return;
    if (_storeid == null) {
      Toast.show('请先选择退货机构');
      return;
    }
    final si = parseScaleBarcode(code);
    final sc = si?.productCode ?? code;
    request(HttpApi.productGetList, {
      'scancode': sc,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      ..._buildMergData()
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isEmpty) {
        Toast.show('未查询到该商品');
        return;
      }
      // 自编码命中：仅一条 → 优先匹配自编码商品不跳转；多条 → 跳转选品页
      // 无自编码命中时：商品条码多条 → 跳转选品页；一条 → 优先匹配该条码商品
      final codeList = list.where((c) => (c['code']?.toString() ?? '') == sc).toList();
      final barcodeList = list.where((c) => (c['barcode']?.toString() ?? '') == sc).toList();
      final needJump = codeList.length >= 2 || (codeList.isEmpty && barcodeList.length >= 2);
      Map<String, dynamic>? primary;
      if (codeList.length == 1) {
        primary = codeList.first as Map<String, dynamic>;
      } else if (codeList.isEmpty && barcodeList.length == 1) {
        primary = barcodeList.first as Map<String, dynamic>;
      }
      if (needJump) {
        // 多条命中：跳转选品页（按扫码词过滤展示候选商品），用户选择后返回合并
        _selectProducts(initialKeyword: sc, returnFocusNode: returnFocusNode);
        return;
      }
      final prod = primary ?? list.first as Map<String, dynamic>;
      final prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
      final barcode = prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? '';
      // 复合去重键对齐后台 ROW_KEYS：productid + unitonlyid + sizeonlyid，同一商品不同包装/规格视为不同行
      final unitonlyid = prod['unitonlyid']?.toString() ?? '';
      final sizeonlyid = prod['sizeonlyid']?.toString() ?? '';
      final ei = _items.indexWhere((r) =>
          r.prodid == prodid &&
          (r.rawData?['unitonlyid']?.toString() ?? '') == unitonlyid &&
          (r.rawData?['sizeonlyid']?.toString() ?? '') == sizeonlyid);
      setState(() {
        if (ei >= 0) {
          final oq = double.tryParse(_items[ei].qtyController.text) ?? 0;
          if (si?.type == 'weight') {
            _items[ei].qtyController.text = MathUtils.formatDecimal(1, si!.qty ?? oq + 1);
          } else if (si?.type == 'amount') {
            final p = double.tryParse(_items[ei].priceController.text) ?? 0;
            _items[ei].qtyController.text = p > 0
                ? MathUtils.formatDecimal(1, (si!.amount ?? 0) / p)
                : MathUtils.formatDecimal(1, oq + 1);
          } else {
            _items[ei].qtyController.text = MathUtils.formatDecimal(1, oq + 1);
          }
          _recalcRow(_items[ei]);
        } else {
          double qty = 1;
          if (si?.type == 'weight') {
            qty = si!.qty ?? 1;
          } else if (si?.type == 'amount') {
            // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
            final scaleCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
            final p = scaleCgprice != 0
                ? scaleCgprice
                : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
            if (p > 0) qty = (si!.amount ?? 0) / p;
          }
          // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
          final scanCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
          final scanPrice = scanCgprice != 0
              ? scanCgprice
              : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
          final row = _DetailRow()
            ..nameController.text =
                prod['productname']?.toString() ?? prod['name']?.toString() ?? ''
            ..qtyController.text = MathUtils.formatDecimal(1, qty)
            ..priceController.text = MathUtils.formatDecimal(2, scanPrice)
            ..prodid = prodid
            ..barcode = barcode
            ..rawData = Map<String, dynamic>.from(prod);
          _recalcRow(row);
          _items.insert(0, row);
        }
      });
      if (returnFocusNode != null && mounted) returnFocusNode.requestFocus();
    }).catchError((_) {
      if (mounted) Toast.show('查询商品失败');
    });
  }

  Widget _buildScanInput() => Container(
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
                            borderRadius: BorderRadius.all(Radius.circular(8))),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                            borderRadius: BorderRadius.all(Radius.circular(8))),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF006EFF)),
                            borderRadius: BorderRadius.all(Radius.circular(8))),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10))))
          ])));
  Widget _buildCard({required String title, Widget? titleRight, required Widget child}) =>
      Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827)))),
                  if (titleRight != null) titleRight
                ])),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            child
          ]));

  /// 附件按钮行（布局参数与 SelectFieldItem 等表单字段一致：
  /// 标签宽 80、字号 14、行高 24 + 上下 12，右箭头同款 chevron）
  Widget _buildAttachButton() {
    return GestureDetector(
      onTap: () async {
        final result = await AttachPage.show(
          context,
          fileLists: _fileLists,
          menuid: '050801',
          billid: _billData?['billid']?.toString() ?? _newBillid ?? '',
          billno: _billData?['billno']?.toString() ?? '',
        );
        if (result != null && mounted) {
          setState(() => _fileLists = result);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: SizedBox(
          height: 24,
          child: Row(children: [
            const SizedBox(
              width: 80,
              child: Text('附件',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(children: [
                const Icon(Icons.attach_file, size: 16, color: Color(0xFF006EFF)),
                const SizedBox(width: 4),
                Text(
                  '附件(${_fileLists.length})',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF006EFF)),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
          ]),
        ),
      ),
    );
  }

  /// 只读字段行（布局参数与 SelectFieldItem 等表单字段一致：标签宽 80、字号 14、行高 24 + 上下 12）
  Widget _buildReadonlyField({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value.isNotEmpty ? value : '-',
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }

  /// 文本输入字段行（布局参数与 SelectFieldItem 等表单字段一致：
  /// 标签宽 80、字号 14、内容行高固定 24 + 上下 12）
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool required = false,
    int maxLines = 1,
    String? Function(String?)? validator,
    double verticalPadding = 12,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
      child: SizedBox(
        height: maxLines > 1 ? null : 24,
        child: Row(
          crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            // 标签区固定 80 宽，必填星号溢出在标签左侧（与 SelectFieldItem 同款），
            // 保证有无星号时标签文字起点完全一致
            SizedBox(
              width: 80,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                  if (required)
                    const Positioned(
                      left: -10,
                      top: 0,
                      child: Text(
                        '*',
                        style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: controller,
                maxLines: maxLines,
                validator: validator,
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
      ),
    );
  }
}

class _DetailRow {
  String? prodid;
  String barcode = '';
  final nameController = TextEditingController();
  final qtyController = TextEditingController();
  final FocusNode qtyFocusNode = FocusNode();
  final priceController = TextEditingController();
  final FocusNode priceFocusNode = FocusNode();
  final amtController = TextEditingController();
  final FocusNode amtFocusNode = FocusNode();
  double? amt;
  Map<String, dynamic>? rawData;
  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    qtyFocusNode.dispose();
    priceFocusNode.dispose();
    priceController.dispose();
    amtFocusNode.dispose();
    amtController.dispose();
  }
}

class _DetailItem extends StatefulWidget {
  const _DetailItem(
      {required this.row,
      required this.index,
      required this.isSelectMode,
      required this.isSelected,
      required this.readOnly,
      required this.onToggle,
      this.onChanged});
  final _DetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final VoidCallback onToggle;

  /// 失焦回调：行金额格式化/重算完成后通知父页面刷新底部合计
  final VoidCallback? onChanged;
  @override
  State<_DetailItem> createState() => _DetailItemState();
}

class _DetailItemState extends State<_DetailItem> {
  TextEditingController get _pc => widget.row.priceController;
  TextEditingController get _qc => widget.row.qtyController;
  TextEditingController get _ac => widget.row.amtController;
  late final VoidCallback _opb;
  late final VoidCallback _oqb;
  late final VoidCallback _oab;
  @override
  void initState() {
    super.initState();
    _opb = () => _ff(widget.row.priceFocusNode, _pc, 2);
    _oqb = () => _ff(widget.row.qtyFocusNode, _qc, 1);
    _oab = () => _faf();
    widget.row.priceFocusNode.addListener(_opb);
    widget.row.qtyFocusNode.addListener(_oqb);
    widget.row.amtFocusNode.addListener(_oab);
    _sam();
  }

  @override
  void dispose() {
    widget.row.priceFocusNode.removeListener(_opb);
    widget.row.qtyFocusNode.removeListener(_oqb);
    widget.row.amtFocusNode.removeListener(_oab);
    super.dispose();
  }

  void _ff(FocusNode n, TextEditingController c, int col) {
    if (n.hasFocus) return;
    final v = double.tryParse(c.text);
    if (v != null) {
      final t = MathUtils.formatDecimal(col, v);
      if (t != c.text) c.text = t;
    }
    _nc();
    widget.onChanged?.call();
  }

  void _faf() {
    final n = widget.row.amtFocusNode;
    if (n.hasFocus) return;
    final v = double.tryParse(_ac.text);
    if (v != null) {
      final t = MathUtils.formatDecimal(3, v);
      if (t != _ac.text) _ac.text = t;
    }
    final a = double.tryParse(_ac.text) ?? 0;
    final p = double.tryParse(_pc.text) ?? 0;
    if (p > 0) {
      _qc.text = MathUtils.formatDecimal(1, a / p);
    }
    widget.row.amt = MathUtils.formatDecimalNum(3, a);
    final r = widget.row.rawData;
    if (r != null) {
      r['amt'] = widget.row.amt;
      r['qty'] = double.tryParse(_qc.text) ?? 0;
    }
    widget.onChanged?.call();
  }

  void _sam() {
    if (widget.row.amt != null) _ac.text = MathUtils.formatDecimal(3, widget.row.amt);
  }

  void _nc() {
    final p = double.tryParse(MathUtils.formatDecimal(2, double.tryParse(_pc.text) ?? 0)) ?? 0;
    final q = double.tryParse(MathUtils.formatDecimal(1, double.tryParse(_qc.text) ?? 0)) ?? 0;
    widget.row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(q, p));
    _sam();
    final r = widget.row.rawData;
    if (r != null) {
      r['price'] = p;
      r['qty'] = q;
      r['amt'] = widget.row.amt;
    }
  }

  static const _dec = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF006EFF))));
  static const _tf = TextStyle(fontSize: 13, color: Color(0xFF111827));
  static final _ifmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))];
  @override
  Widget build(BuildContext context) {
    final name = widget.row.nameController.text;
    final unit = widget.row.rawData?['unit']?.toString() ?? '';
    final size = widget.row.rawData?['size']?.toString() ?? '';
    return GestureDetector(
        onTap: widget.isSelectMode ? widget.onToggle : (widget.readOnly ? null : () {}),
        child: Container(
            margin: const EdgeInsets.only(bottom: 1),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
                color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6)))),
            child: Row(children: [
              if (widget.isSelectMode) ...[
                Icon(widget.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20, color: const Color(0xFF006EFF)),
                const SizedBox(width: 8)
              ],
              Expanded(
                  flex: 5,
                  child: Text(
                      '$name${size.isNotEmpty ? '/$size' : ''}${unit.isNotEmpty ? '($unit)' : ''}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis)),
              Expanded(
                  flex: 3,
                  child: SizedBox(
                      height: 34,
                      child: TextField(
                          controller: _pc,
                          focusNode: widget.row.priceFocusNode,
                          readOnly: widget.readOnly,
                          enabled: !widget.readOnly,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: _ifmt,
                          textAlign: TextAlign.center,
                          style: _tf,
                          decoration: _dec))),
              const SizedBox(width: 4),
              Expanded(
                  flex: 3,
                  child: SizedBox(
                      height: 34,
                      child: TextField(
                          controller: _qc,
                          focusNode: widget.row.qtyFocusNode,
                          readOnly: widget.readOnly,
                          enabled: !widget.readOnly,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: _ifmt,
                          textAlign: TextAlign.center,
                          style: _tf,
                          decoration: _dec))),
              const SizedBox(width: 4),
              Expanded(
                  flex: 3,
                  child: SizedBox(
                      height: 34,
                      child: TextField(
                          controller: _ac,
                          focusNode: widget.row.amtFocusNode,
                          readOnly: widget.readOnly,
                          enabled: !widget.readOnly,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: _ifmt,
                          textAlign: TextAlign.center,
                          style: _tf,
                          decoration: _dec))),
            ])));
  }
}

class _CgthsqStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CgthsqStickyHeaderDelegate({required this.state});
  final _CgthsqAddPageState state;
  @override
  double get minExtent => _CgthsqAddPageState._stickyMinExtent;
  @override
  double get maxExtent => (state._isSigned || !state._scanSettings.showInfraredInput)
      ? _CgthsqAddPageState._stickyMinExtent
      : _CgthsqAddPageState._stickyMaxExtent;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      state._buildStickyHeader();
  @override
  bool shouldRebuild(covariant _CgthsqStickyHeaderDelegate oldDelegate) => true;
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({this.defaultFlag = 1});
  final int defaultFlag;
  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late int _flag;
  final _rc = TextEditingController();
  static const int _ml = 200;
  @override
  void initState() {
    super.initState();
    _flag = widget.defaultFlag;
  }

  @override
  void dispose() {
    _rc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('单据审批', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                Row(children: [
                  const Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '*', style: TextStyle(color: Color(0xFFEF4444))),
                      TextSpan(text: '审批意见：'),
                    ]),
                    style: TextStyle(fontSize: 14, color: Color(0xFF333333)),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                      onTap: () => setState(() => _flag = 1),
                      child: Row(children: [
                        _br(1),
                        const SizedBox(width: 6),
                        const Text('通过', style: TextStyle(fontSize: 14))
                      ])),
                  const SizedBox(width: 24),
                  GestureDetector(
                      onTap: () => setState(() => _flag = 0),
                      child: Row(children: [
                        _br(0),
                        const SizedBox(width: 6),
                        const Text('驳回', style: TextStyle(fontSize: 14))
                      ]))
                ]),
                const SizedBox(height: 20),
                Text.rich(
                  TextSpan(children: [
                    if (_flag != 1)
                      const TextSpan(text: '*', style: TextStyle(color: Color(0xFFEF4444))),
                    TextSpan(text: _flag == 1 ? '备注信息：' : '驳回原因：'),
                  ]),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: _rc,
                    maxLines: 3,
                    maxLength: _ml,
                    decoration: InputDecoration(
                        hintText: _flag == 1 ? '请输入备注信息' : '请输入驳回原因',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBFBFBF)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.all(12))),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape:
                                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: const Text('取消'))),
                  const SizedBox(width: 16),
                  Expanded(
                      child: ElevatedButton(
                          onPressed: () {
                            if (_flag == 0 && _rc.text.trim().isEmpty) {
                              Toast.show('驳回原因不能为空！');
                              return;
                            }
                            Navigator.pop(context,
                                {'reviewsignflag': _flag, 'reviewremark': _rc.text.trim()});
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF006EFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape:
                                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: const Text('确认')))
                ]),
              ])));
  Widget _br(int v) {
    final s = _flag == v;
    return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: s ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC), width: 2),
            color: s ? const Color(0xFF006EFF) : Colors.white),
        child: s
            ? Center(
                child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)))
            : null);
  }
}

class _ApprovalLogSheet extends StatelessWidget {
  const _ApprovalLogSheet({required this.reviewBillFlows, required this.scrollController});
  final List<Map<String, dynamic>> reviewBillFlows;
  final ScrollController scrollController;
  String _fa(dynamic v) {
    if (v == 1 || v?.toString() == '1') return '【通过】';
    if (v == 0 || v?.toString() == '0') return '【驳回】';
    if (v == 2 || v?.toString() == '2') return '【撤回】';
    return '';
  }

  Color _ac(dynamic v) {
    if (v == 1 || v?.toString() == '1') return const Color(0xFF00A870);
    if (v == 0 || v?.toString() == '0') return const Color(0xFFEF4444);
    if (v == 2 || v?.toString() == '2') return const Color(0xFFFF9900);
    return const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Expanded(
                  child: Center(
                      child: Text('审批日志',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 20, color: Color(0xFF999999))))
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
                              Text(_fa(item['reviewsignflag']),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _ac(item['reviewsignflag'])))
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
