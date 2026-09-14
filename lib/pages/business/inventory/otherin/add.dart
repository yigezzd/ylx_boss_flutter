import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
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
import 'package:flutter_deer/util/scan_match_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/load_image.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

enum _OtherinAction { none, save, sign, delete, print, withdraw }

class InventoryOtherinAddPage extends StatefulWidget {
  const InventoryOtherinAddPage({super.key, this.billData});
  final Map<String, dynamic>? billData;

  @override
  State<InventoryOtherinAddPage> createState() => _InventoryOtherinAddPageState();
}

class _InventoryOtherinAddPageState extends State<InventoryOtherinAddPage>
    with LogPageMixin<InventoryOtherinAddPage> {
  @override
  String get logPageName => _isEdit ? '其他入库单详情' : '其他入库单新增';

  final TextEditingController _remarkCtrl = TextEditingController();

  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;

  String? _bsid;
  String? _storename;
  String? _counterid;
  String? _countername;
  String? _handlerid;
  String? _handlername;
  List<Map<String, dynamic>> _detailList = [];
  late ScanSettings _scanSettings;

  _OtherinAction _submitAction = _OtherinAction.none;
  bool _detailLoading = false;
  Map<String, dynamic>? _billData;
  List<Map<String, dynamic>> _fileLists = [];
  // ---- 多级审批 ----
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  bool _billSign = true;
  String _userCode = '';
  String _userid = '';
  bool _isSelectMode = false;
  Set<int> _selectedIndices = {};

  bool get _isEdit => _billData != null && (_billData!['billid']?.toString().isNotEmpty ?? false);
  bool get _isSigned => _billData?['signflag']?.toString() == '1';

  /// 单据状态文案/颜色：0/空→待审核, 1→已审核, 2→已驳回（对齐 lxAss）
  String get _statusLabel {
    final sf = _billData?['signflag']?.toString() ?? '';
    return sf == '1' ? '已审核' : (sf == '2' ? '已驳回' : '待审核');
  }

  Color get _statusColor {
    final sf = _billData?['signflag']?.toString() ?? '';
    return sf == '1'
        ? const Color(0xFF00A870)
        : (sf == '2' ? const Color(0xFFFF9900) : const Color(0xFFD54B5A));
  }

  @override
  void initState() {
    super.initState();
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          _scanDebounceTimer?.cancel();
          _scanDebounceTimer = Timer(const Duration(milliseconds: 150), _processScanInput);
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
      _scanDebounceTimer = Timer(const Duration(milliseconds: 150), _processScanInput);
    });
    _scanSettings = ScanSettings.fromSp();
    // 加载当前登录用户信息（多级审批判断审核人身份）
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _userid = userMap['userid']?.toString() ?? '';
        _userCode = userMap['code']?.toString() ?? '';
      }
    } catch (_) {}
    if (widget.billData != null && (widget.billData!['billid']?.toString().isNotEmpty ?? false)) {
      _loadDetail();
    } else {
      _loadDefaults();
    }
    logEnter();
  }

  void _loadDefaults() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _bsid = storeMap['id']?.toString();
        _storename = storeMap['name']?.toString();
      }
    } catch (_) {}
    // 新增模式：初始化审批签字按钮可见性
    _initSignUserBtn();
  }

  void _loadDetail() {
    setState(() => _detailLoading = true);
    final params = Map<String, dynamic>.from(widget.billData!);
    request(HttpApi.stockModifyGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
          _remarkCtrl.text = data['remark']?.toString() ?? '';
          _fileLists = (data['fileLists'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _bsid = data['bsid']?.toString();
          _storename = data['storename']?.toString();
          _counterid = data['counterid']?.toString();
          _countername = data['countername']?.toString();
          _handlerid = data['handlerid']?.toString();
          _handlername = data['handlername']?.toString();
          final detailArr = data['detaillist'] as List? ?? [];
          _detailList = detailArr.map<Map<String, dynamic>>((e) {
            final m = Map<String, dynamic>.from(e as Map);
            m['qty'] = m['qty'] ?? 0;
            m['birthdate'] = _formatBatchDate(m['birthdate']);
            m['validdate'] = _formatBatchDate(m['validdate']);
            _defValSet(m);
            return m;
          }).toList();
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  @override
  void dispose() {
    _scanDebounceTimer?.cancel();
    _remarkCtrl.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  double get _totalQty {
    double total = 0;
    for (final item in _detailList) {
      total += double.tryParse(item['qty']?.toString() ?? '') ?? 0;
    }
    return total;
  }

  /// 入库 amtJudge: sellamt=qty*saleprice, amt=qty*costprice, notaxamt=amt/(1+intaxrate)
  /// modifyqty=stockqty+qty（入库是加）
  static void _computeAmts(Map<String, dynamic> item) {
    final qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
    final stockqty = double.tryParse(item['stockqty']?.toString() ?? '0') ?? 0;
    final costprice = double.tryParse(item['costprice']?.toString() ?? '0') ?? 0;
    final saleprice =
        double.tryParse(item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '0') ?? 0;
    final intaxrate = double.tryParse(item['intaxrate']?.toString() ?? '0') ?? 0;

    // amtJudge 对齐 lxAss: 金额 formatDecimal(3)、数量 formatDecimal(1)
    item['amt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, costprice));
    item['sellamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, saleprice));
    final taxFactor = 1 + intaxrate;
    item['notaxamt'] =
        MathUtils.formatDecimal(3, MathUtils.divide(MathUtils.mul(qty, costprice), taxFactor));
    item['modifyqty'] = MathUtils.formatDecimal(1, MathUtils.add(stockqty, qty));
  }

  /// 赋值默认值并对齐数值精度（对齐 lxAss defValSet）
  static void _defValSet(Map<String, dynamic> d) {
    d['qty'] = double.tryParse(d['qty']?.toString() ?? '0') ?? 0;
    // 价格类位数 formatDecimal(2)、数量类 formatDecimal(1)（对齐 lxAss 显示）
    d['costprice'] = MathUtils.formatDecimal(2,
        double.tryParse(d['emptycostprice']?.toString() ?? d['costprice']?.toString() ?? '0') ?? 0);
    d['saleprice'] = MathUtils.formatDecimal(
        2, double.tryParse(d['saleprice']?.toString() ?? d['sellprice']?.toString() ?? '0') ?? 0);
    d['sellprice'] = d['saleprice'];
    d['stockqty'] = MathUtils.formatDecimal(
        1,
        double.tryParse(d['emptybatchstockqty']?.toString() ?? d['stockqty']?.toString() ?? '0') ??
            0);
    d['intaxrate'] = (double.tryParse(d['intaxrate']?.toString() ?? '0') ?? 0).toStringAsFixed(1);
    _computeAmts(d);
  }

  /// 写入字段时格式化并重算金额（对齐 lxAss writeData）
  static void _writeData(String key, Map<String, dynamic> d) {
    switch (key) {
      case 'qty':
        d['qty'] = double.tryParse(d['qty']?.toString() ?? '0') ?? 0;
        break;
      case 'costprice':
        d['costprice'] =
            MathUtils.formatDecimal(2, double.tryParse(d['costprice']?.toString() ?? '0') ?? 0);
        break;
      case 'saleprice':
        d['saleprice'] =
            MathUtils.formatDecimal(2, double.tryParse(d['saleprice']?.toString() ?? '0') ?? 0);
        d['sellprice'] = d['saleprice'];
        break;
    }
    _computeAmts(d);
  }

  void _save({bool doSign = false}) {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('014003', showTip: false)) {
        Toast.show('你无权编辑其他入库单，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('014002', showTip: false)) {
        Toast.show('你无权新增其他入库单，请在后台修改权限');
        return;
      }
    }
    logSave(doSign ? '保存并审核' : '保存单据');
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请选择入库机构');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请选择入库仓库');
      return;
    }
    if (_detailList.isEmpty) {
      Toast.show('请选择商品');
      return;
    }

    setState(() => _submitAction = _OtherinAction.save);
    for (final item in _detailList) {
      _computeAmts(item);
      item['outflag'] = -1;
    }

    double billamt = 0, billqty = 0, billsellamt = 0;
    for (final item in _detailList) {
      billamt += double.tryParse(item['amt']?.toString() ?? '0') ?? 0;
      billqty += double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
      billsellamt += double.tryParse(item['sellamt']?.toString() ?? '0') ?? 0;
    }

    final params = <String, dynamic>{
      'bsid': _bsid,
      'storename': _storename,
      'counterid': _counterid,
      'countername': _countername,
      'billtype': 4,
      'outflag': -1,
      'outtype': 2,
      'signflag': 0,
      'remark': _remarkCtrl.text.trim(),
      'fileLists': _fileLists,
      'billamt': MathUtils.formatDecimal(3, billamt),
      'billqty': MathUtils.formatDecimal(1, billqty),
      'billsellamt': MathUtils.formatDecimal(3, billsellamt),
      'detaillist': _detailList,
    };
    if (_isEdit) params['billid'] = _billData!['billid'];
    if (_handlerid != null && _handlerid!.isNotEmpty) {
      params['handlerid'] = _handlerid;
      params['handlername'] = _handlername;
    }

    final isNew = !_isEdit;
    request(HttpApi.stockModifySave, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic> && isNew) {
        setState(() => _billData = data);
      }
      if (!doSign) {
        Toast.show('保存成功');
      } else if (data is Map<String, dynamic>) {
        _doSignAfterSave(data);
      } else {
        _sign();
      }
    }).whenComplete(() {
      if (mounted && !doSign) setState(() => _submitAction = _OtherinAction.none);
    });
  }

  void _sign() {
    if (!PermissionUtils.checkPermission('014005', showTip: false)) {
      Toast.show('你无权审核其他入库单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;

    // 多级审批：弹出审批操作弹窗
    if (_reviewFlowUsers.isNotEmpty) {
      _showApprovalDialog().then((approvalResult) {
        if (approvalResult != null && mounted) {
          _billData?['reviewsignflag'] = approvalResult['reviewsignflag'];
          _billData?['reviewremark'] = approvalResult['reviewremark'];
          _doSign();
        } else if (mounted) {
          setState(() => _submitAction = _OtherinAction.none);
        }
      });
      return;
    }

    // 无多级审批配置：简单确认
    showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('提示'),
              content: const Text('确定审核单据吗？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
              ],
            )).then((confirm) {
      if (confirm != true) {
        if (mounted) setState(() => _submitAction = _OtherinAction.none);
        return;
      }
      _doSign();
    });
  }

  /// 执行审核操作（多级审批：携带 reviewsignflag/reviewremark）
  void _doSign() {
    if (_billData == null) return;
    setState(() => _submitAction = _OtherinAction.sign);
    final signParams = <String, dynamic>{
      ...(_billData ?? {}),
      'bsid': _bsid,
      'storename': _storename,
      'counterid': _counterid,
      'countername': _countername,
      'billtype': 4,
      'outflag': -1,
      'outtype': 2,
      'signflag': 1,
      'reviewremark': _billData?['reviewremark']?.toString() ?? '',
      'remark': _remarkCtrl.text.trim(),
      'fileLists': _fileLists,
      'detaillist': _detailList,
    };
    // reviewsignflag: 2=撤回保持不变，0=驳回保持不变，其余设为1（通过）
    final int rsf = int.tryParse(_billData?['reviewsignflag']?.toString() ?? '') ?? -1;
    if (rsf != 2 && rsf != 0) signParams['reviewsignflag'] = 1;
    if (_handlerid != null && _handlerid!.isNotEmpty) {
      signParams['handlerid'] = _handlerid;
      signParams['handlername'] = _handlername;
    }
    request(HttpApi.stockModifySign, signParams).then((result) {
      if (!mounted) return;
      if (rsf == 0) {
        Toast.show('当前其他入库单已驳回');
      } else {
        Toast.show(result['retmsg']?.toString() ?? '审核成功');
      }
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _OtherinAction.none);
    });
  }

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

  /// 是否有反审核权限
  bool get _bolHandleTTT {
    if (_isAdmin) return true;
    if (_reviewFlowUsers.isEmpty) {
      if (_reviewBillFlows.isEmpty) return true;
      return _reviewBillFlows.any((item) => item['userid']?.toString() == _userid);
    }
    return _reviewBillFlows.any((item) => item['userid']?.toString() == _userid);
  }

  /// reviewsignflag==2 表示单据处于撤回待处理态
  bool get _isWithdrawPending => _billData?['reviewsignflag']?.toString() == '2';

  /// signflag==2 表示单据已驳回
  bool get _isRejected => _billData?['signflag']?.toString() == '2';

  /// 新单据时，根据机构(bsid)查询是否需要审批签字
  void _initSignUserBtn() {
    if (_isAdmin) return;
    if (!_isEdit && _bsid != null) {
      request(HttpApi.reviewTypeConfigGetNewBillSignUser, {
        'billtypeid': '0803',
        'bsid': _bsid,
      }).then((result) {
        if (!mounted) return;
        final data = result['data'];
        if (data is List && data.isNotEmpty) {
          setState(() {
            _billSign = data.any((item) => item['userid']?.toString() == _userid);
          });
        } else {
          setState(() => _billSign = true);
        }
      }).catchError((_) {
        if (mounted) setState(() => _billSign = false);
      });
    }
  }

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

  /// 保存后执行审核（多级审批流程）
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

  /// 审批操作弹窗（通过/驳回 + 备注）
  Future<Map<String, dynamic>?> _showApprovalDialog({int defaultFlag = 1}) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
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

  /// 撤回操作（reviewsignflag==2，所有审批步骤需重新处理）
  Future<void> _restsign() async {
    if (_billData == null) return;
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
    if (confirm != true) return;

    setState(() => _submitAction = _OtherinAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.stockModifySign, params).then((result) {
      if (!mounted) return;
      Toast.show('撤回成功');
      _loadDetail();
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _OtherinAction.none);
    });
  }

  /// 更多弹窗（删单 + 打印）
  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              alignment: Alignment.center,
              child: const Text('请选择', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除'),
              subtitle: const Text('删除整张单据'),
              onTap: () {
                Navigator.pop(ctx);
                _delBill();
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined, color: Color(0xFF006EFF)),
              title: const Text('打印'),
              onTap: () {
                Navigator.pop(ctx);
                _print();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _delBill() async {
    if (_billData == null) return;
    if (!PermissionUtils.checkPermission('014004', showTip: false)) {
      Toast.show('你无权删除其他入库单，请在后台修改权限');
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
            ));
    if (confirm != true) return;
    setState(() => _submitAction = _OtherinAction.delete);
    request(HttpApi.stockModifyDelBill, _billData).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _OtherinAction.none);
    });
  }

  Future<void> _print() async {
    if (_billData == null) return;
    setState(() => _submitAction = _OtherinAction.print);
    request(HttpApi.purchaseInstorePrint, {'menuid': '080301', 'data': _billData}).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _OtherinAction.none);
    });
  }

  Future<void> _selectProduct({String? keyword}) async {
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请选择入库机构');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请选择入库仓库');
      return;
    }
    final result = await Navigator.push<List<Map<String, dynamic>>>(
        context,
        MaterialPageRoute(
            builder: (_) => SelectProductPage(
                  storeid: int.tryParse(_bsid ?? ''),
                  counterid: _counterid,
                  billtypeflag: 'kctz',
                  batchManualInput: true,
                  initialKeyword: keyword,
                  mergData: const {
                    'needbatchflag': 1,
                    'stockflag': 1,
                  },
                  paramJust: const [
                    'qty',
                    'validdate',
                    'birthdate',
                    'batchno',
                    'batch',
                    'unit',
                    'size',
                    'remark',
                  ],
                )));
    if (result != null && mounted) {
      setState(() {
        for (final item in result) {
          final addQty = double.tryParse(item['qty']?.toString() ?? '') ?? 1;
          final stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;
          final prodid = item['prodid']?.toString() ?? item['productid']?.toString() ?? '';
          final barcode = item['barcode']?.toString() ?? item['selfbarcode']?.toString() ?? '';
          final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';

          final existIdx = _detailList.indexWhere((e) =>
              (e['prodid']?.toString() ?? e['productid']?.toString() ?? '') == prodid &&
              (barcode.isEmpty ||
                  (e['barcode']?.toString() ?? e['selfbarcode']?.toString() ?? '') == barcode));

          if (existIdx >= 0) {
            final cur = double.tryParse(_detailList[existIdx]['qty']?.toString() ?? '0') ?? 0;
            _detailList[existIdx]['qty'] = cur + addQty;
            _writeData('qty', _detailList[existIdx]);
          } else {
            final newItem = <String, dynamic>{
              'productid': item['productid']?.toString() ?? prodid,
              'prodid': prodid,
              'barcode': barcode,
              'productname': name,
              'name': name,
              'unit': item['unit']?.toString() ?? '',
              'unitonlyid': item['unitonlyid']?.toString() ?? '',
              'sizeonlyid': item['sizeonlyid']?.toString() ?? '',
              'saleprice': item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '0',
              'sellprice': item['sellprice']?.toString() ?? item['saleprice']?.toString() ?? '0',
              'costprice': item['costprice']?.toString() ?? '0',
              'stockqty': stockqty,
              'qty': addQty,
              'batchno': item['batchno']?.toString() ?? '',
              'birthdate': item['birthdate']?.toString() ?? '',
              'validdate': item['validdate']?.toString() ?? '',
              'remark': item['remark']?.toString() ?? '',
              'size': item['size']?.toString() ?? '',
              'shelves': item['shelves']?.toString() ?? '',
              'stypeid': item['stypeid']?.toString() ?? '',
              'stypename': item['stypename']?.toString() ?? '',
              'intaxrate': item['intaxrate']?.toString() ?? '0',
              'morebatchflag': item['morebatchflag']?.toString() ?? '',
              'supid': item['supid']?.toString() ?? '',
              'supname': item['supname']?.toString() ?? '',
              'itemtype': item['itemtype']?.toString() ?? '',
              'packageflag': item['packageflag']?.toString() ?? '',
              'specflag': item['specflag']?.toString() ?? '',
            };
            _defValSet(newItem);
            _detailList.insert(0, newItem);
          }
        }
      });
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) _selectedIndices.clear();
    });
  }

  Future<void> _scanBarcode() async {
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请先选择入库仓库');
      return;
    }
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
      Toast.show('当前平台暂支持扫码');
    }
  }

  void _processScanInput() {
    if (!mounted) return;
    final code = _scanController.text.trim();
    if (code.isEmpty) return;
    _handleScannedBarcode(code, returnFocusNode: _scanFocusNode);
    _scanController.clear();
    _scanFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _handleScannedBarcode(String code, {FocusNode? returnFocusNode}) async {
    if (code.trim().isEmpty) return;
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请先选择入库仓库');
      return;
    }
    // 对齐 lxAss scanFn：解析秤码（重量码/金额码），取真实商品码查询
    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;
    final params = <String, dynamic>{
      'scancode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      'stockflag': 1,
      'needbatchflag': 1,
      'billtypeflag': 'kctz',
      'storeid': _bsid ?? '',
      'counterid': _counterid ?? '',
    };
    try {
      final result = await request(HttpApi.productGetList, params, false, false);
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isNotEmpty) {
        // 对齐 lxAss scanFn：自编码/条码命中分流
        final match = matchScanList(list, searchCode);
        if (match.needJump) {
          _selectProduct(keyword: searchCode);
          return;
        }
        final prod = match.primary ?? (list.first as Map<String, dynamic>);
        // 对齐 lxAss scanFn：普通码数量 = 接口 qty + 1；重量码直接设数量；金额码按金额/单价反算（单价取 price → costprice → saleprice）
        final double baseQty = double.tryParse(prod['qty']?.toString() ?? '0') ?? 0;
        double scannedQty;
        if (scaleInfo == null) {
          scannedQty = baseQty + 1;
        } else if (scaleInfo.type == 'weight') {
          scannedQty = scaleInfo.qty ?? 0;
        } else if (scaleInfo.type == 'amount') {
          final price = double.tryParse(
                  (prod['price'] ?? prod['costprice'] ?? prod['saleprice'] ?? '0').toString()) ??
              0;
          scannedQty = price > 0 ? (scaleInfo.amount ?? 0) / price : baseQty + 1;
        } else {
          scannedQty = baseQty + 1;
        }
        final existingIndex = _findScanProductIndex(prod);

        if (_scanSettings.scanQtyMode == 0) {
          // ── 默认累加1模式 ──
          if (existingIndex >= 0) {
            setState(() {
              final curQty =
                  double.tryParse(_detailList[existingIndex]['qty']?.toString() ?? '0') ?? 0;
              _detailList[existingIndex]['qty'] = curQty + scannedQty;
              _writeData('qty', _detailList[existingIndex]);
            });
            Toast.show('扫描添加成功');
          } else {
            // 不存在相同商品 → 直接新增一行
            setState(() {
              final stockqty = double.tryParse(prod['stockqty']?.toString() ?? '0') ?? 0;
              final String barcode =
                  prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? '';
              final newItem = <String, dynamic>{
                'productname': prod['productname']?.toString() ?? prod['name']?.toString() ?? '',
                'name': prod['productname']?.toString() ?? prod['name']?.toString() ?? '',
                'unit': prod['unit']?.toString() ?? '',
                'size': prod['size']?.toString() ?? '',
                'barcode': barcode,
                'saleprice': prod['saleprice']?.toString() ?? prod['sellprice']?.toString() ?? '0',
                'sellprice': prod['sellprice']?.toString() ?? prod['saleprice']?.toString() ?? '0',
                'costprice': prod['costprice']?.toString() ?? '0',
                'stockqty': stockqty,
                'qty': scannedQty,
                'prodid': prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '',
                'productid': prod['productid']?.toString() ?? prod['prodid']?.toString() ?? '',
                'batchno': prod['batchno']?.toString() ?? '',
                'stypeid': prod['stypeid']?.toString() ?? '',
                'stypename': prod['stypename']?.toString() ?? '',
                'intaxrate': prod['intaxrate']?.toString() ?? '0',
                'supid': prod['supid']?.toString() ?? '',
                'supname': prod['supname']?.toString() ?? '',
                'itemtype': prod['itemtype']?.toString() ?? '',
                'packageflag': prod['packageflag']?.toString() ?? '',
                'specflag': prod['specflag']?.toString() ?? '',
                'unitonlyid': prod['unitonlyid']?.toString() ?? '',
                'sizeonlyid': prod['sizeonlyid']?.toString() ?? '',
                'shelves': prod['shelves']?.toString() ?? '',
              };
              _defValSet(newItem);
              _detailList.insert(0, newItem);
            });
            Toast.show('扫描添加成功');
          }
        } else {
          // ── 弹窗手动输入模式 ──
          if (existingIndex >= 0) {
            // 已存在相同商品 → 打开详情弹窗编辑已有行
            _showProductDetail(_detailList[existingIndex], existingIndex);
          } else {
            // 不存在相同商品 → 先新增一行，再打开详情弹窗
            final stockqty = double.tryParse(prod['stockqty']?.toString() ?? '0') ?? 0;
            final String barcode =
                prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? '';
            final newItem = <String, dynamic>{
              'productname': prod['productname']?.toString() ?? prod['name']?.toString() ?? '',
              'name': prod['productname']?.toString() ?? prod['name']?.toString() ?? '',
              'unit': prod['unit']?.toString() ?? '',
              'size': prod['size']?.toString() ?? '',
              'barcode': barcode,
              'saleprice': prod['saleprice']?.toString() ?? prod['sellprice']?.toString() ?? '0',
              'sellprice': prod['sellprice']?.toString() ?? prod['saleprice']?.toString() ?? '0',
              'costprice': prod['costprice']?.toString() ?? '0',
              'stockqty': stockqty,
              'qty': scannedQty,
              'prodid': prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '',
              'productid': prod['productid']?.toString() ?? prod['prodid']?.toString() ?? '',
              'batchno': prod['batchno']?.toString() ?? '',
              'stypeid': prod['stypeid']?.toString() ?? '',
              'stypename': prod['stypename']?.toString() ?? '',
              'intaxrate': prod['intaxrate']?.toString() ?? '0',
              'supid': prod['supid']?.toString() ?? '',
              'supname': prod['supname']?.toString() ?? '',
              'itemtype': prod['itemtype']?.toString() ?? '',
              'packageflag': prod['packageflag']?.toString() ?? '',
              'specflag': prod['specflag']?.toString() ?? '',
              'unitonlyid': prod['unitonlyid']?.toString() ?? '',
              'sizeonlyid': prod['sizeonlyid']?.toString() ?? '',
              'shelves': prod['shelves']?.toString() ?? '',
            };
            _defValSet(newItem);
            setState(() {
              _detailList.insert(0, newItem);
            });
            _showProductDetail(_detailList[0], 0);
          }
        }
        _focusAfterScan(returnFocusNode);
      } else {
        if (mounted) Toast.show('未找到匹配商品，请重新扫码录入！');
        _focusAfterScan(returnFocusNode);
      }
    } catch (e) {
      if (mounted) Toast.show('查询商品失败: $e');
      _focusAfterScan(returnFocusNode);
    }
  }

  /// 按 barcode/productid/size/unitonlyid/batchno 查找已在列表中的商品索引
  int _findScanProductIndex(Map<String, dynamic> prod) {
    final String prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
    final String barcode = prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? '';
    final String size = prod['size']?.toString() ?? '';
    final String unitonlyid = prod['unitonlyid']?.toString() ?? '';
    final String batchno = prod['batchno']?.toString() ?? '';
    for (int i = 0; i < _detailList.length; i++) {
      final item = _detailList[i];
      if ((item['barcode']?.toString() ?? '') == barcode &&
          ((item['productid']?.toString() ?? '') == prodid ||
              (item['prodid']?.toString() ?? '') == prodid) &&
          (item['size']?.toString() ?? '') == size &&
          (item['unitonlyid']?.toString() ?? '') == unitonlyid &&
          (item['batchno']?.toString() ?? '') == batchno) {
        return i;
      }
    }
    return -1;
  }

  void _focusAfterScan(FocusNode? returnFocusNode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scanSettings.scanContinuous) {
        if (returnFocusNode != null) {
          returnFocusNode.requestFocus();
        } else {
          _scanFocusNode.requestFocus();
        }
      } else {
        if (returnFocusNode != null) {
          returnFocusNode.requestFocus();
        } else if (_scanSettings.showInfraredInput) {
          _scanFocusNode.requestFocus();
        }
      }
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  void _toggleIndex(int index) {
    setState(() {
      if (_selectedIndices.contains(index))
        _selectedIndices.remove(index);
      else
        _selectedIndices.add(index);
    });
  }

  bool get _isAllSelected =>
      _detailList.isNotEmpty && _selectedIndices.length == _detailList.length;

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedIndices.clear();
      } else {
        _selectedIndices = Set<int>.from(List.generate(_detailList.length, (i) => i));
      }
    });
  }

  void _batchDelete() {
    if (_selectedIndices.isEmpty) return;
    showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('提示'),
              content: Text('确定删除选中的 ${_selectedIndices.length} 条明细？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
              ],
            )).then((confirm) {
      if (confirm != true) return;
      setState(() {
        final sorted = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
        for (final i in sorted) _detailList.removeAt(i);
        _selectedIndices.clear();
        _isSelectMode = false;
      });
    });
  }

  Future<void> _selectStore() async {
    FocusScope.of(context).unfocus();
    final result = await SelectStorePage.show(context);
    if (result != null && mounted) {
      setState(() {
        _bsid = result['storeid']?.toString();
        _storename = result['storename']?.toString();
        _counterid = null;
        _countername = null;
        _detailList = [];
      });
    }
  }

  Future<void> _selectWarehouse() async {
    FocusScope.of(context).unfocus();
    final result = await SelectWarehousePage.show(
      context,
      bsid: _bsid != null && _bsid!.isNotEmpty ? int.tryParse(_bsid!) : null,
      initialSelectedId: _counterid ?? '',
    );
    if (result != null && mounted) {
      setState(() {
        _counterid = result['counterid']?.toString();
        _countername = result['countername']?.toString();
        _detailList = [];
      });
    }
  }

  Future<void> _selectHandler() async {
    FocusScope.of(context).unfocus();
    final result = await SelectBuyerPage.show(context, initialSelectedId: _handlerid ?? '');
    if (result != null && mounted) {
      setState(() {
        _handlerid = result['buyerid']?.toString();
        _handlername = result['buyername']?.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _isSigned;
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
          title: Text(_isEdit ? '修改其他入库单' : '新增其他入库单',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : Column(children: [
              Expanded(
                  child: ColoredBox(
                      color: const Color(0xFFF5F5F5),
                      child: CustomScrollView(
                        cacheExtent: 800,
                        slivers: [
                          if (_isEdit)
                            SliverToBoxAdapter(
                                child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                    child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFFEEEEEE))),
                                        child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Text('单号：${_billData?['billno'] ?? ''}',
                                                    style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF111827))),
                                                const Spacer(),
                                                Text(_statusLabel,
                                                    style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w500,
                                                        color: _statusColor))
                                              ]),
                                              const SizedBox(height: 6),
                                              Text('制单信息：${_billData?['createtime'] ?? ''}',
                                                  style: const TextStyle(
                                                      fontSize: 12, color: Color(0xFF7A7A7A))),
                                              const SizedBox(height: 4),
                                              Text('制单人：${_billData?['createname'] ?? ''}',
                                                  style: const TextStyle(
                                                      fontSize: 12, color: Color(0xFF7A7A7A))),
                                            ])))),
                          // ---- 审核日志卡片（多级审批） ----
                          if (_isEdit && (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty))
                            SliverToBoxAdapter(
                                child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                    child: _buildApprovalNodeCard())),
                          SliverToBoxAdapter(
                              child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                  child: Container(
                                      decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFEEEEEE))),
                                      child: Column(children: [
                                        _buildSelectRow(
                                            label: '入库机构',
                                            value: _storename ?? '',
                                            onTap: disabled ? null : _selectStore,
                                            required: true),
                                        _buildDivider(),
                                        _buildSelectRow(
                                            label: '入库仓库',
                                            value: _countername ?? '',
                                            onTap: disabled ? null : _selectWarehouse,
                                            required: true),
                                        _buildDivider(),
                                        _buildSelectRow(
                                            label: '经手人',
                                            value: _handlername ?? '',
                                            onTap: disabled ? null : _selectHandler),
                                        _buildDivider(),
                                        _buildInputRow(
                                            label: '备注',
                                            controller: _remarkCtrl,
                                            disabled: disabled),
                                        _buildDivider(),
                                        _buildAttachButton(),
                                      ])))),
                          SliverPersistentHeader(
                              pinned: true, delegate: _OtherinStickyHeaderDelegate(state: this)),
                          if (_detailList.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    LoadAssetImage('state/zwsp', width: 80, height: 80),
                                    SizedBox(height: 12),
                                    Text('暂无商品明细',
                                        style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                                  ]),
                                ),
                              ),
                            ),
                          if (_detailList.isNotEmpty)
                            SliverList.builder(
                              itemCount: _detailList.length,
                              itemBuilder: (context, index) => RepaintBoundary(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                                  child: ColoredBox(
                                    color: Colors.white,
                                    child: _buildDetailItem(_detailList[index], index, disabled),
                                  ),
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        ],
                      ))),
            ]),
      bottomNavigationBar: _isSelectMode
          ? _buildBatchDeleteBar()
          : Container(
              padding: EdgeInsets.only(
                  left: 16, right: 16, top: 10, bottom: MediaQuery.of(context).padding.bottom + 12),
              decoration: const BoxDecoration(
                  color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_detailList.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '入库数量：${MathUtils.formatDecimal(1, _totalQty)}，共 ${_detailList.length} 项',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
                    Row(children: [
                      if (_isEdit && _isSigned) ...[
                        Expanded(
                            child: GestureDetector(
                                onTap: _submitAction != _OtherinAction.none ? null : _print,
                                child: Container(
                                    height: 42,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF006EFF),
                                        borderRadius: BorderRadius.circular(6)),
                                    alignment: Alignment.center,
                                    child: _submitAction == _OtherinAction.print
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white))
                                        : const Text('打印',
                                            style: TextStyle(fontSize: 15, color: Colors.white)))))
                      ] else if (_isEdit && !_isSigned) ...[
                        // “更多”按钮 - reviewsignflag != 2 && bolHandleTT
                        if (!_isWithdrawPending && _bolHandleTT) ...[
                          Expanded(
                              child: GestureDetector(
                                  onTap: _submitAction != _OtherinAction.none ? null : _showMoreMenu,
                                  child: Container(
                                      height: 42,
                                      decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFCCCCCC)),
                                          borderRadius: BorderRadius.circular(6)),
                                      alignment: Alignment.center,
                                      child: const Text('更多',
                                          style:
                                              TextStyle(fontSize: 15, color: Color(0xFF333333)))))),
                        ],
                        // 保存/审核按钮 - signflag!=2 && reviewsignflag!=2 && (bolHandleTT || (审批流>0 && bolHandleT))
                        if (!_isRejected &&
                            !_isWithdrawPending &&
                            (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT))) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                                onTap: _submitAction != _OtherinAction.none ? null : () => _save(),
                                child: Container(
                                    height: 42,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF006EFF),
                                        borderRadius: BorderRadius.circular(6)),
                                    alignment: Alignment.center,
                                    child: _submitAction == _OtherinAction.save
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white))
                                        : const Text('保存',
                                            style: TextStyle(fontSize: 15, color: Colors.white))))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: GestureDetector(
                                onTap: _submitAction != _OtherinAction.none
                                    ? null
                                    : () => _save(doSign: true),
                                child: Container(
                                    height: 42,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF00A870),
                                        borderRadius: BorderRadius.circular(6)),
                                    alignment: Alignment.center,
                                    child: _submitAction == _OtherinAction.sign
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white))
                                        : const Text('审核',
                                            style: TextStyle(fontSize: 15, color: Colors.white))))),
                        ],
                        // 撤回按钮 - 仅已驳回状态(signflag==2)显示
                        if (_isRejected) ...[
                          const SizedBox(width: 10),
                          Expanded(
                              child: GestureDetector(
                                  onTap: _submitAction != _OtherinAction.none ? null : _restsign,
                                  child: Container(
                                      height: 42,
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFFF9900),
                                          borderRadius: BorderRadius.circular(6)),
                                      alignment: Alignment.center,
                                      child: _submitAction == _OtherinAction.withdraw
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white))
                                          : const Text('撤回',
                                              style: TextStyle(fontSize: 15, color: Colors.white))))),
                        ],
                      ] else ...[
                        Expanded(
                            child: GestureDetector(
                                onTap: _submitAction != _OtherinAction.none ? null : () => _save(),
                                child: Container(
                                    height: 42,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF006EFF),
                                        borderRadius: BorderRadius.circular(6)),
                                    alignment: Alignment.center,
                                    child: _submitAction == _OtherinAction.save
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white))
                                        : const Text('保存',
                                            style: TextStyle(fontSize: 15, color: Colors.white))))),
                        // 审核按钮 - billSign
                        if (_billSign) ...[
                          const SizedBox(width: 10),
                          Expanded(
                              child: GestureDetector(
                                  onTap: _submitAction != _OtherinAction.none
                                      ? null
                                      : () => _save(doSign: true),
                                  child: Container(
                                      height: 42,
                                      decoration: BoxDecoration(
                                          color: const Color(0xFF00A870),
                                          borderRadius: BorderRadius.circular(6)),
                                      alignment: Alignment.center,
                                      child: _submitAction == _OtherinAction.sign
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white))
                                          : const Text('审核',
                                              style: TextStyle(fontSize: 15, color: Colors.white))))),
                        ],
                      ],
                    ]),
                  ]),
            ),
    );
  }

  Widget _buildBatchDeleteBar() {
    final selectedCount = _selectedIndices.length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleSelectAll,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _isAllSelected,
                    activeColor: const Color(0xFF006EFF),
                    onChanged: (_) => _toggleSelectAll(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('全选', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              ],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: selectedCount > 0 ? _batchDelete : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  selectedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFFD1D5DB),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD1D5DB),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('删除选中($selectedCount)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  static Widget _buildInputRow(
      {required String label, required TextEditingController controller, bool disabled = false}) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          // 星号固定占位，文字始终从同一起点对齐
          const SizedBox(width: 8),
          SizedBox(
              width: 64,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333)))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: controller,
                  enabled: !disabled,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                  decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: '请输入',
                      hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB))))),
        ]));
  }

  static Widget _buildSelectRow(
      {required String label, required String value, VoidCallback? onTap, bool required = false}) {
    return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 星号固定占位，文字始终从同一起点对齐
              SizedBox(
                width: 8,
                child: required
                    ? const Text('*',
                        style: TextStyle(fontSize: 14, color: Color(0xFFD54B5A)))
                    : null,
              ),
              SizedBox(
                width: 64,
                child: Text(label,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(value.isNotEmpty ? value : '请选择',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 14,
                          color: value.isNotEmpty
                              ? const Color(0xFF111827)
                              : const Color(0xFFD1D5DB)))),
              const SizedBox(width: 4),
              if (onTap != null)
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
            ])));
  }

  /// 审核日志卡片（对齐 Vue approvalNode 组件）
  Widget _buildApprovalNodeCard() {
    // 当前审批节点信息
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

    // 审批节点总数
    final totalNodes = _reviewFlowUsers.isNotEmpty
        ? int.tryParse(_reviewFlowUsers[0]['allindex']?.toString() ?? '0') ?? 0
        : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
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

  static Widget _buildDivider() =>
      const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 14, endIndent: 14);

  /// 附件按钮行（对齐采购入库 _buildAttachButton）
  Widget _buildAttachButton() {
    return GestureDetector(
      onTap: () async {
        final result = await AttachPage.show(
          context,
          fileLists: _fileLists,
          menuid: '080301',
          billid: _billData?['billid']?.toString() ?? '',
          billno: _billData?['billno']?.toString() ?? '',
        );
        if (result != null && mounted) {
          setState(() => _fileLists = result);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: _isSigned ? 0 : 8,
          ),
          SizedBox(
            width: _isSigned ? 72 : 64,
            child: const Text('附件',
                style:
                    TextStyle(fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(children: [
              const Icon(Icons.attach_file, size: 16, color: Color(0xFF006EFF)),
              const SizedBox(width: 4),
              Text(
                '附件(${_fileLists.length})',
                style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFFC0C4CC)),
            ]),
          ),
        ]),
      ),
    );
  }

  void _showProductDetail(Map<String, dynamic> item, int index) {
    final disabled = _isSigned;
    final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
    var unit = item['unit']?.toString() ?? '';
    var size = item['size']?.toString() ?? '';
    var unitonlyid = item['unitonlyid']?.toString() ?? '';
    var sizeonlyid = item['sizeonlyid']?.toString() ?? '';
    var barcode = item['barcode']?.toString() ?? item['selfbarcode']?.toString() ?? '';
    var saleprice =
        double.tryParse(item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '') ?? 0;
    var shelves = item['shelves']?.toString() ?? '';
    var costprice = double.tryParse(item['costprice']?.toString() ?? '0') ?? 0;

    double editQty = double.tryParse(item['qty']?.toString() ?? '') ?? 0;
    String editBatchno = item['batchno']?.toString() ?? '';
    String editBirthdate = item['birthdate']?.toString() ?? '';
    String editValiddate = item['validdate']?.toString() ?? '';
    final String editSupid = item['supid']?.toString() ?? '';
    final String editSupname = item['supname']?.toString() ?? '';
    String editRemark = item['remark']?.toString() ?? '';

    final qtyCtrl = TextEditingController(
      text: MathUtils.formatDecimal(1, editQty),
    );
    final qtyFocus = FocusNode();
    qtyFocus.addListener(() {
      if (qtyFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (qtyCtrl.text.isNotEmpty) {
            qtyCtrl.selection = TextSelection(
              baseOffset: 0,
              extentOffset: qtyCtrl.text.length,
            );
          }
        });
      }
    });

    final batchnoCtrl = TextEditingController(text: editBatchno);
    final batchnoFocus = FocusNode();

    final remarkCtrl = TextEditingController(text: editRemark);

    Future<void> handleUnitSpecSelect(
      BuildContext ctx,
      StateSetter setDialogState,
      String type,
      Map<String, dynamic> item,
    ) async {
      final productid = item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
      if (productid.isEmpty) {
        Toast.show('商品信息异常');
        return;
      }

      final params = <String, dynamic>{
        'page': 1,
        'pagesize': 99999,
        'is_page': 0,
        'ptype': 1,
        'commonflag': 1,
        'productid': productid,
        'bsid': _bsid ?? '',
        'itemtype': item['itemtype']?.toString() ?? '',
        'packageflag': item['packageflag']?.toString() ?? '',
        'specflag': item['specflag']?.toString() ?? '',
        'counterid': _counterid ?? '',
        'needbatchflag': 1,
        'stockflag': 1,
      };

      final result = await request(HttpApi.productGetExtendList, params);
      final data = result['data'];
      final rawList = (data is Map<String, dynamic>
              ? (type == 'size' ? data['sizelist'] : data['packlist'])
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

      final opt = await showModalBottomSheet<Map<String, dynamic>>(
        context: ctx,
        builder: (_) => Container(
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
                      onTap: () => Navigator.pop(_),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final o = list[i];
                    final name = o['_name']?.toString() ?? '';
                    return ListTile(
                      title: Text(name),
                      onTap: () => Navigator.pop(_, o),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (opt == null) return;
      setDialogState(() {
        if (type == 'unit') {
          final u = opt['unit']?.toString() ?? opt['_name']?.toString() ?? '';
          if (u.isNotEmpty) unit = u;
          final uid = opt['unitonlyid']?.toString() ?? opt['_id']?.toString() ?? '';
          unitonlyid = uid;
          item['unitonlyid'] = uid;
          if (uid.isNotEmpty) {
            size = item['_mainSize']?.toString() ?? size;
            sizeonlyid = item['_mainSizeonlyid']?.toString() ?? '';
            item['size'] = size;
            item['sizeonlyid'] = sizeonlyid;
          }
          final nb = opt['sbarcode']?.toString() ?? opt['barcode']?.toString();
          if (nb != null) {
            barcode = nb;
            item['barcode'] = nb;
          }
          final nc = opt['scode']?.toString() ?? opt['code']?.toString();
          if (nc != null) item['code'] = nc;
          final nr = opt['sellprice']?.toString() ??
              opt['retailprice']?.toString() ??
              opt['lsprice']?.toString();
          if (nr != null && nr.isNotEmpty) {
            saleprice = double.tryParse(nr) ?? 0;
            item['saleprice'] = nr;
            item['sellprice'] = nr;
          }
          final ns = opt['stockqty']?.toString() ?? opt['stock']?.toString();
          if (ns != null && ns.isNotEmpty) {
            item['stockqty'] = ns;
            item['stock'] = ns;
          }
          final ncost = opt['costprice']?.toString();
          if (ncost != null && ncost.isNotEmpty) {
            costprice = double.tryParse(ncost) ?? 0;
            item['costprice'] = ncost;
          }
          final nsh = opt['shelves']?.toString();
          if (nsh != null && nsh.isNotEmpty) {
            shelves = nsh;
            item['shelves'] = nsh;
          }
        } else {
          if (item['_mainSize'] == null) {
            item['_mainSize'] = item['size'];
            item['_mainSizeonlyid'] = item['sizeonlyid'] ?? '';
          }
          final s = opt['size']?.toString() ?? opt['_name']?.toString() ?? '';
          if (s.isNotEmpty) size = s;
          final sid = opt['sizeonlyid']?.toString() ?? opt['_id']?.toString() ?? '';
          sizeonlyid = sid;
          item['sizeonlyid'] = sid;
          final nb = opt['sbarcode']?.toString() ?? opt['barcode']?.toString();
          if (nb != null) {
            barcode = nb;
            item['barcode'] = nb;
          }
          final nc = opt['scode']?.toString() ?? opt['code']?.toString();
          if (nc != null) item['code'] = nc;
          final nr = opt['sellprice']?.toString() ??
              opt['retailprice']?.toString() ??
              opt['lsprice']?.toString();
          if (nr != null && nr.isNotEmpty) {
            saleprice = double.tryParse(nr) ?? 0;
            item['saleprice'] = nr;
            item['sellprice'] = nr;
          }
          final ns = opt['stockqty']?.toString() ?? opt['stock']?.toString();
          if (ns != null && ns.isNotEmpty) {
            item['stockqty'] = ns;
            item['stock'] = ns;
          }
          final ncost = opt['costprice']?.toString();
          if (ncost != null && ncost.isNotEmpty) {
            costprice = double.tryParse(ncost) ?? 0;
            item['costprice'] = ncost;
          }
        }
      });
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ConstrainedBox(
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
                  child: Row(
                    children: [
                      // 左侧占位，平衡关闭按钮宽度，标题居中
                      const SizedBox(width: 24),
                      Expanded(
                        child: const Text('商品详情',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
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
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '商品名称：$name',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('条码：$barcode',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              const SizedBox(height: 4),
                              Row(children: [
                                Expanded(
                                    child: Text('零售价：¥${MathUtils.formatDecimal(2, saleprice)}',
                                        style: const TextStyle(
                                            fontSize: 13, color: Color(0xFF6B7280)))),
                                Expanded(
                                    child: Text('货架号：$shelves',
                                        style: const TextStyle(
                                            fontSize: 13, color: Color(0xFF6B7280)))),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!disabled &&
                            (item['packageflag']?.toString() != '1' ||
                                item['specflag']?.toString() == '1'))
                          _buildDetailSelectField(
                            label: '单位',
                            value: unit.isNotEmpty ? unit : '请选择',
                            onTap: () => handleUnitSpecSelect(ctx, setDialogState, 'unit', item),
                          )
                        else
                          _buildDetailReadonlyField(
                              label: '单位', value: unit.isNotEmpty ? unit : '-'),
                        _buildDetailDivider(),
                        if (!disabled &&
                            item['specflag']?.toString() == '1' &&
                            (item['unitonlyid'] == null ||
                                (item['unitonlyid']?.toString().isEmpty ?? false)))
                          _buildDetailSelectField(
                            label: '规格',
                            value: size.isNotEmpty ? size : '请选择',
                            onTap: () => handleUnitSpecSelect(ctx, setDialogState, 'size', item),
                          )
                        else
                          _buildDetailReadonlyField(
                              label: '规格', value: size.isNotEmpty ? size : '-'),
                        _buildDetailDivider(),
                        if (disabled)
                          _buildDetailReadonlyField(
                              label: '入库数量', value: editQty.toStringAsFixed(1))
                        else
                          _buildDetailFormField(
                            label: '入库数量',
                            controller: qtyCtrl,
                            focusNode: qtyFocus,
                            isDecimal: true,
                            onChanged: (v) {
                              final val = double.tryParse(v) ?? 0;
                              setDialogState(() => editQty = val);
                            },
                          ),
                        _buildDetailDivider(),
                        if (disabled)
                          _buildDetailReadonlyField(
                              label: '商品批次', value: editBatchno.isNotEmpty ? editBatchno : '-')
                        else
                          _buildDetailFormField(
                            label: '商品批次',
                            controller: batchnoCtrl,
                            focusNode: batchnoFocus,
                            keyboardType: TextInputType.text,
                            onChanged: (v) {
                              setDialogState(() => editBatchno = v);
                            },
                          ),
                        _buildDetailDivider(),
                        if (disabled)
                          _buildDetailReadonlyField(
                              label: '生产日期', value: editBirthdate.isNotEmpty ? editBirthdate : '-')
                        else
                          _buildDetailDateField(
                            label: '生产日期',
                            value: editBirthdate,
                            onTap: () async {
                              final result = await _pickDetailDate(ctx, editBirthdate);
                              if (result != null) {
                                setDialogState(() => editBirthdate = result);
                              }
                            },
                          ),
                        _buildDetailDivider(),
                        if (disabled)
                          _buildDetailReadonlyField(
                              label: '有效日期', value: editValiddate.isNotEmpty ? editValiddate : '-')
                        else
                          _buildDetailDateField(
                            label: '有效日期',
                            value: editValiddate,
                            onTap: () async {
                              final result = await _pickDetailDate(ctx, editValiddate);
                              if (result != null) {
                                setDialogState(() => editValiddate = result);
                              }
                            },
                          ),
                        _buildDetailDivider(),
                        if (disabled)
                          _buildDetailReadonlyField(label: '备注', value: editRemark)
                        else
                          _buildDetailFormField(
                            label: '备注',
                            controller: remarkCtrl,
                            keyboardType: TextInputType.text,
                            onChanged: (v) {
                              setDialogState(() => editRemark = v);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
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
                          onPressed: () => Navigator.pop(ctx),
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
                          onPressed: disabled
                              ? () => Navigator.pop(ctx)
                              : () {
                                  setState(() {
                                    _detailList[index]['qty'] = editQty;
                                    _detailList[index]['unit'] = unit;
                                    _detailList[index]['size'] = size;
                                    _detailList[index]['unitonlyid'] = unitonlyid;
                                    _detailList[index]['sizeonlyid'] = sizeonlyid;
                                    _detailList[index]['batchno'] = editBatchno;
                                    _detailList[index]['birthdate'] = editBirthdate;
                                    _detailList[index]['validdate'] = editValiddate;
                                    _detailList[index]['supid'] = editSupid;
                                    _detailList[index]['supname'] = editSupname;
                                    _detailList[index]['remark'] = editRemark;
                                    _detailList[index]['barcode'] = barcode;
                                    _detailList[index]['code'] = item['code']?.toString() ?? '';
                                    _detailList[index]['stockqty'] = item['stockqty']?.toString() ??
                                        item['stock']?.toString() ??
                                        '';
                                    _detailList[index]['saleprice'] = saleprice.toStringAsFixed(2);
                                    _detailList[index]['sellprice'] = saleprice.toStringAsFixed(2);
                                    _detailList[index]['shelves'] = shelves;
                                    _detailList[index]['costprice'] = costprice.toStringAsFixed(3);
                                    _writeData('qty', _detailList[index]);
                                  });
                                  Navigator.pop(ctx);
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
        ),
      ),
    );
  }

  static Widget _buildDetailFormField({
    required String label,
    required TextEditingController controller,
    bool isDecimal = false,
    TextInputType keyboardType = TextInputType.number,
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType:
                  isDecimal ? const TextInputType.numberWithOptions(decimal: true) : keyboardType,
              inputFormatters:
                  isDecimal ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))] : null,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              onChanged: onChanged,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildDetailReadonlyField({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value.isNotEmpty ? value : '-',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, color: valueColor ?? const Color(0xFF111827))),
          ),
        ],
      ),
    );
  }

  static Widget _buildDetailSelectField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : '请选择',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
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

  static Widget _buildDetailDateField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : '请选择',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
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

  static Widget _buildDetailDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));

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

  Future<String?> _pickDetailDate(BuildContext context, String currentValue) async {
    DateTime initial;
    try {
      initial = currentValue.isNotEmpty ? DateTime.parse(currentValue) : DateTime.now();
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
                        onSelectedItemChanged: (i) {
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
                        onSelectedItemChanged: (i) {
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
                        onSelectedItemChanged: (i) {
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
    if (date != null) {
      final mo = date.month.toString().padLeft(2, '0');
      final dy = date.day.toString().padLeft(2, '0');
      return '${date.year}-$mo-$dy';
    }
    return null;
  }

  static const double _stickyScanHeight = 62.0;
  static const double _stickyTitleHeight = 56.0;
  static const double _stickySignedExtent = 50.0;
  static const double _stickyMaxExtent = _stickyScanHeight + _stickyTitleHeight;
  static const double _stickyMinExtent = _stickyMaxExtent;

  Widget _buildStickyHeader(double extent) {
    final disabled = _isSigned;
    return Align(
      alignment: Alignment.topCenter,
      child: ColoredBox(
        color: const Color(0xFFF5F5F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!disabled && _scanSettings.showInfraredInput) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: TextField(
                      controller: _scanController,
                      focusNode: _scanFocusNode,
                      autofocus: true,
                      showCursor: true,
                      keyboardType: TextInputType.none,
                      enableInteractiveSelection: false,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) {
                        _scanDebounceTimer?.cancel();
                        _scanDebounceTimer =
                            Timer(const Duration(milliseconds: 150), _processScanInput);
                      },
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                  border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    const Text('商品明细',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                    const Spacer(),
                    if (!disabled) ...[
                      GestureDetector(
                          onTap: _toggleSelectMode,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_isSelectMode ? Icons.close : Icons.delete_outline,
                                size: 16,
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
                          ])),
                      if (_scanSettings.showCameraButton) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                            onTap: _scanBarcode,
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              BossSvgIcon(svgFile: 'scan.svg', size: 12),
                              SizedBox(width: 2),
                              Text('扫描',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF006EFF),
                                      fontWeight: FontWeight.w500)),
                            ])),
                      ],
                      if (Device.isWeb) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                            onTap: () => _handleScannedBarcode('4891599900019'),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.qr_code, size: 14, color: Color(0xFFFF6B00)),
                              SizedBox(width: 2),
                              Text('固定扫描',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFFF6B00),
                                      fontWeight: FontWeight.w500)),
                            ])),
                      ],
                      const SizedBox(width: 12),
                      GestureDetector(
                          onTap: _selectProduct,
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF006EFF)),
                            SizedBox(width: 2),
                            Text('新增',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF006EFF),
                                    fontWeight: FontWeight.w500)),
                          ])),
                    ],
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(Map<String, dynamic> item, int idx, bool disabled) {
    final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
    final unit = item['unit']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    final batchno = item['batchno']?.toString() ?? '';
    final costprice = double.tryParse(item['costprice']?.toString() ?? '') ?? 0;
    final stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;
    final qty = double.tryParse(item['qty']?.toString() ?? '') ?? 0;
    final isSelected = _selectedIndices.contains(idx);

    return GestureDetector(
      onTap: () {
        if (_isSelectMode) {
          _toggleIndex(idx);
        } else {
          _showProductDetail(item, idx);
        }
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: idx.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_isSelectMode) ...[
                Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFBDBDBD)),
                const SizedBox(width: 8),
              ],
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    unit.isNotEmpty || size.isNotEmpty
                        ? '$name${size.isNotEmpty ? '/$size' : ''}${unit.isNotEmpty ? '（$unit）' : ''}'
                        : name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                      child: Text('批次：$batchno',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                  Text('成本价：¥${MathUtils.formatDecimal(2, costprice)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                      child: Text('现库存：${MathUtils.formatDecimal(1, stockqty)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                  Text('入库数量：${MathUtils.formatDecimal(1, qty)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ]),
              ])),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
        ],
      ),
    );
  }
}

class _OtherinStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _OtherinStickyHeaderDelegate({required this.state});
  final _InventoryOtherinAddPageState state;
  @override
  double get minExtent => state._isSigned
      ? _InventoryOtherinAddPageState._stickySignedExtent
      : _InventoryOtherinAddPageState._stickyMinExtent;
  @override
  double get maxExtent => state._isSigned
      ? _InventoryOtherinAddPageState._stickySignedExtent
      : _InventoryOtherinAddPageState._stickyMaxExtent;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader(maxExtent);
  }

  @override
  bool shouldRebuild(covariant _OtherinStickyHeaderDelegate oldDelegate) => true;
}

/// 审批操作弹窗（通过/驳回 + 备注，对齐采购入库 _ApprovalDialog）
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
            Row(
              children: [
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
            Text.rich(
              TextSpan(children: [
                if (_flag != 1)
                  const TextSpan(text: '*', style: TextStyle(color: Color(0xFFEF4444))),
                TextSpan(text: _flag == 1 ? '备注信息：' : '驳回原因：'),
              ]),
              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
            ),
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

/// 审批日志弹窗（历史记录表格，对齐采购入库 _ApprovalLogSheet）
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Expanded(
                child: Center(
                  child: Text('审批日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: Color(0xFF999999)),
                ),
              ),
            ],
          ),
        ),
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
                            Text(
                              '备注：${item['reviewremark']}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                            ),
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
