import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_batch.dart';
import 'package:flutter_deer/components/select/select_inventory_plan.dart';
import 'package:flutter_deer/components/select/select_mult_batch.dart';
import 'package:flutter_deer/components/select/select_product.dart';
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

enum _PCAction { none, save, sign, delete, print, resign, withdraw }

class InventoryPrecheckAddPage extends StatefulWidget {
  const InventoryPrecheckAddPage({super.key, this.billData});
  final Map<String, dynamic>? billData;

  @override
  State<InventoryPrecheckAddPage> createState() => _InventoryPrecheckAddPageState();
}

class _InventoryPrecheckAddPageState extends State<InventoryPrecheckAddPage>
    with LogPageMixin<InventoryPrecheckAddPage> {
  @override
  String get logPageName => _isEdit ? '预盘单详情' : '预盘单新增';

  final TextEditingController _remarkCtrl = TextEditingController();

  // ---- 红外扫描输入框（PDA 扫码枪）----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer; // 扫码防抖：扫码枪注入字符极快，停止变化后自动触发查询

  String? _planid;
  String? _planname;
  String? _bsid;
  String? _storename;
  String? _counterid;
  String? _countername;
  int _checktype = 2;
  List<Map<String, dynamic>> _typeList = [];
  List<Map<String, dynamic>> _detailList = [];

  _PCAction _submitAction = _PCAction.none;
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

  // ---- 扫码设置 ----
  late ScanSettings _scanSettings;

  bool get _isEdit => _billData != null && (_billData!['billid']?.toString().isNotEmpty ?? false);
  bool get _isSigned => _billData?['signflag']?.toString() == '1';

  @override
  void initState() {
    super.initState();
    // 读取扫码设置
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
    // 红外扫描 FocusNode：onKeyEvent 需在 initState 中初始化，避免字段初始化器中访问 this
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          // 扫码头注入条码字符与 Enter 几乎同时到达，但字符走 IME 通道、
          // Enter 走按键通道，二者异步，立即读取会漏掉尚未提交的末尾字符。
          // 这里仅重置防抖延迟读取——末尾字符提交时会再次重置防抖，
          // 确保在条码完整后才发起查询（修复商米L3扫码"未找到商品"）。
          debugPrint('[红外扫描] onKeyEvent Enter，重置防抖延迟读取');
          _scanDebounceTimer?.cancel();
          _scanDebounceTimer = Timer(const Duration(milliseconds: 150), _processScanInput);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    // 扫码框聚焦时隐藏软键盘（PDA 扫码枪通过硬件/IME注入字符，无需软键盘）
    // 注意：不可使用 readOnly，会阻断 PDA 扫码器的 IME 注入通道
    // 主要通过 keyboardType: TextInputType.none 在引擎层面阻止键盘弹出
    _scanFocusNode.addListener(() {
      if (_scanFocusNode.hasFocus && !_scanFieldFocused) {
        _scanFieldFocused = true;
        // 兜底：确保键盘隐藏
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } else if (!_scanFocusNode.hasFocus) {
        _scanFieldFocused = false;
      }
    });
    // 扫码防抖兜底：PDA 扫码枪模拟键盘注入字符极快（<100ms），
    // 当文本停止变化 300ms 后自动触发查询（兜底 onKeyEvent/onSubmitted 未触发的场景）
    _scanController.addListener(() {
      _scanDebounceTimer?.cancel();
      final text = _scanController.text.trim();
      if (text.isEmpty) return;
      _scanDebounceTimer = Timer(const Duration(milliseconds: 150), _processScanInput);
    });
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
    request(HttpApi.stockprecheckGetInfo, params).then((result) {
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
          _planid = data['planid']?.toString();
          _planname = data['planname']?.toString();
          _bsid = data['bsid']?.toString();
          _storename = data['storename']?.toString();
          _counterid = data['counterid']?.toString();
          _countername = data['countername']?.toString();
          _checktype = int.tryParse(data['checktype']?.toString() ?? '') ?? 2;
          final typeArr = data['stockPlanItemtypeResp'] as List? ?? [];
          _typeList = typeArr.cast<Map<String, dynamic>>();
          final detailArr = data['detaillist'] as List? ?? [];
          _detailList = detailArr.map<Map<String, dynamic>>((e) {
            final m = Map<String, dynamic>.from(e as Map);
            _normalizeDetailItem(m);
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

  String _checktypeName(int v) {
    switch (v) {
      case 1:
        return '全场盘点';
      case 2:
        return '盘点分类';
      case 3:
        return '盘点供应商';
      case 4:
        return '盘点品牌';
      default:
        return '';
    }
  }

  String _filterTypeNames() {
    if (_checktype == 1) return '全场盘点';
    if (_typeList.isEmpty) return '全部分类';
    return _typeList.map((e) => e['stypename']?.toString() ?? '').join('|');
  }

  /// 规范化明细项字段（对齐 boss 项目 defValSet + writeData）
  /// 确保 stockqty / precheckqty / qty / saleprice 等字段有正确的默认值和计算值
  static void _normalizeDetailItem(Map<String, dynamic> item) {
    final precheckqty = double.tryParse(item['precheckqty']?.toString() ?? '0') ?? 0;
    final stockqty = double.tryParse(item['stockqty']?.toString() ?? '0') ?? 0;
    final saleprice =
        double.tryParse(item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '0') ?? 0;
    final costprice = double.tryParse(item['costprice']?.toString() ?? '0') ?? 0;

    // 设置默认值（对齐 defValSet）
    item['precheckqty'] = precheckqty;
    item['stockqty'] = stockqty;
    item['costprice'] = costprice;
    item['saleprice'] = saleprice;

    // 重新计算盈亏数量 = 预盘数量 - 现库存（对齐 writeData: qty = precheckqty - stockqty）
    item['qty'] = MathUtils.formatDecimal(1, MathUtils.subtract(precheckqty, stockqty));

    // 计算零售金额（对齐 amtJudge: sellamt = precheckqty * saleprice）
    item['sellamt'] = MathUtils.formatDecimal(3, MathUtils.mul(precheckqty, saleprice));
  }

  double get _totalPrecheckQty {
    double total = 0;
    for (final item in _detailList) {
      total += double.tryParse(item['precheckqty']?.toString() ?? '') ?? 0;
    }
    return total;
  }

  // ── 保存 ──
  void _save({bool doSign = false}) {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('013703', showTip: false)) {
        Toast.show('你无权编辑预盘单，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('013702', showTip: false)) {
        Toast.show('你无权新增预盘单，请在后台修改权限');
        return;
      }
    }
    logSave(doSign ? '保存并审核' : '保存单据');
    if (_planid == null || _planid!.isEmpty) {
      Toast.show('请选择盘点计划');
      return;
    }
    if (_detailList.isEmpty) {
      Toast.show('请选择商品');
      return;
    }

    setState(() => _submitAction = _PCAction.save);
    // 保存前规范化所有明细行（对齐 quickcheck _computeAmts + boss defValSet）
    for (final item in _detailList) {
      _normalizeDetailItem(item);
    }
    final params = <String, dynamic>{
      'planid': _planid,
      'planname': _planname,
      'bsid': _bsid,
      'storename': _storename,
      'counterid': _counterid,
      'countername': _countername,
      'checktype': _checktype,
      'signflag': 0,
      'remark': _remarkCtrl.text.trim(),
      'fileLists': _fileLists,
      'stypename': _typeList.map((e) => e['stypename']?.toString() ?? '').join(','),
      'detaillist': _detailList,
    };
    if (_isEdit) params['billid'] = _billData!['billid'];

    // 对齐quickcheck：新单据始终用save响应更新_billData（获取billid等服务端字段）
    // 确保 doSign=true 时 _sign() 能拿到完整数据
    final isNew = !_isEdit;
    request(HttpApi.stockprecheckSave, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic> && (isNew || !doSign)) {
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
      if (mounted && !doSign) setState(() => _submitAction = _PCAction.none);
    });
  }

  void _sign() {
    if (!PermissionUtils.checkPermission('013705', showTip: false)) {
      Toast.show('你无权审核预盘单，请在后台修改权限');
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
          setState(() => _submitAction = _PCAction.none);
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
      ),
    ).then((confirm) {
      if (confirm != true) {
        if (mounted) setState(() => _submitAction = _PCAction.none);
        return;
      }
      _doSign();
    });
  }

  /// 执行审核操作（多级审批：携带 reviewsignflag/reviewremark）
  void _doSign() {
    if (_billData == null) return;
    setState(() => _submitAction = _PCAction.sign);
    // 对齐boss项目signFn：传完整表单数据（含detaillist + stypename）
    final signParams = <String, dynamic>{
      ...(_billData ?? {}),
      'planid': _planid,
      'planname': _planname,
      'bsid': _bsid,
      'storename': _storename,
      'counterid': _counterid,
      'countername': _countername,
      'checktype': _checktype,
      'signflag': 1,
      'reviewremark': _billData?['reviewremark']?.toString() ?? '',
      'remark': _remarkCtrl.text.trim(),
      'fileLists': _fileLists,
      'stypename': _typeList.map((e) => e['stypename']?.toString() ?? '').join(','),
      'detaillist': _detailList,
    };
    // reviewsignflag: 2=撤回保持不变，0=驳回保持不变，其余设为1（通过）
    final int rsf = int.tryParse(_billData?['reviewsignflag']?.toString() ?? '') ?? -1;
    if (rsf != 2 && rsf != 0) signParams['reviewsignflag'] = 1;
    request(HttpApi.stockprecheckSign, signParams).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PCAction.none);
    });
  }

  Future<void> _delBill() async {
    if (_billData == null) return;
    if (!PermissionUtils.checkPermission('013704', showTip: false)) {
      Toast.show('你无权删除预盘单，请在后台修改权限');
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
    if (confirm != true) return;
    setState(() => _submitAction = _PCAction.delete);
    request(HttpApi.stockprecheckDelBill, _billData).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PCAction.none);
    });
  }

  Future<void> _print() async {
    if (_billData == null) return;
    setState(() => _submitAction = _PCAction.print);
    request(HttpApi.purchaseInstorePrint, {
      'menuid': '080801',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PCAction.none);
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

  // ── 反审核 ──
  void _resign() {
    if (!PermissionUtils.checkPermission('013706', showTip: false)) {
      Toast.show('你无权反审核预盘单，请在后台修改权限');
      return;
    }
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定反审核该预盘单吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    ).then((confirm) {
      if (confirm != true) return;
      setState(() => _submitAction = _PCAction.resign);
      final resignParams = <String, dynamic>{
        ...(_billData ?? {}),
        'planid': _planid,
        'planname': _planname,
        'bsid': _bsid,
        'storename': _storename,
        'counterid': _counterid,
        'countername': _countername,
        'checktype': _checktype,
        'signflag': _billData?['signflag'] ?? 0,
        'remark': _remarkCtrl.text.trim(),
        'fileLists': _fileLists,
        'stypename': _typeList.map((e) => e['stypename']?.toString() ?? '').join(','),
        'detaillist': _detailList,
      };
      request(HttpApi.stockprecheckResign, resignParams).then((result) {
        if (!mounted) return;
        Toast.show('反审核成功');
        _loadDetail();
      }).whenComplete(() {
        if (mounted) setState(() => _submitAction = _PCAction.none);
      });
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
        'billtypeid': '0808',
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

    setState(() => _submitAction = _PCAction.withdraw);
    final params = <String, dynamic>{
      ...(_billData ?? {}),
      'planid': _planid,
      'planname': _planname,
      'bsid': _bsid,
      'storename': _storename,
      'counterid': _counterid,
      'countername': _countername,
      'checktype': _checktype,
      'reviewsignflag': 2,
      'reviewremark': '',
      'signflag': 1,
      'remark': _remarkCtrl.text.trim(),
      'fileLists': _fileLists,
      'stypename': _typeList.map((e) => e['stypename']?.toString() ?? '').join(','),
      'detaillist': _detailList,
    };
    request(HttpApi.stockprecheckSign, params).then((result) {
      if (!mounted) return;
      Toast.show('撤回成功');
      _loadDetail();
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PCAction.none);
    });
  }

  // ── 选择商品 ──
  Future<void> _selectProduct({String? keyword}) async {
    if (_planid == null || _planid!.isEmpty) {
      Toast.show('请选择盘点计划');
      return;
    }
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          storeid: int.tryParse(_bsid ?? ''),
          counterid: _counterid,
          planid: _planid,
          checktype: _checktype,
          billtypeflag: 'ypd',
          planCategories: _typeList.isNotEmpty ? _typeList : null,
          initialKeyword: keyword,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        for (final item in result) {
          // 多批次商品：选择页返回 batchList（单行合并），先移除旧行再拆成每批次一行（对齐 lxAss onSelectProduct：替换而非累加）
          if (item['morebatchflag']?.toString() == '1') {
            final rawBatchList = item['batchList'];
            if (rawBatchList is List && rawBatchList.isNotEmpty) {
              final prodid = item['prodid']?.toString() ?? item['productid']?.toString() ?? '';
              // 移除该商品所有旧行（对齐 lxAss：重新选择替换整个列表，非累加）
              _detailList.removeWhere(
                  (e) => (e['prodid']?.toString() ?? e['productid']?.toString() ?? '') == prodid);
              for (final el in rawBatchList.cast<Map<String, dynamic>>()) {
                final obj = Map<String, dynamic>.from(item)
                  ..addAll(el)
                  ..remove('batchList')
                  ..['addbatchflag'] = 1;
                _normalizeDetailItem(obj);
                // unshift 到列表首位（新增商品置顶显示）
                _detailList.insert(0, obj);
              }
              continue;
            }
          }
          final addQty = double.tryParse(item['qty']?.toString() ?? '') ?? 1;
          final stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;
          final prodid = item['prodid']?.toString() ?? item['productid']?.toString() ?? '';
          final barcode = item['barcode']?.toString() ?? item['selfbarcode']?.toString() ?? '';

          final existing = _detailList.cast<Map<String, dynamic>?>().firstWhere(
                (r) =>
                    (r!['prodid']?.toString() ?? r['productid']?.toString() ?? '') == prodid &&
                    (barcode.isEmpty ||
                        (r['barcode']?.toString() ?? r['selfbarcode']?.toString() ?? '') ==
                            barcode),
                orElse: () => null,
              );

          if (existing != null) {
            final curQty = double.tryParse(existing['precheckqty']?.toString() ?? '0') ?? 0;
            existing['precheckqty'] = curQty + addQty;
            _normalizeDetailItem(existing);
          } else {
            final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
            final newItem = <String, dynamic>{
              'productid': item['productid']?.toString() ?? prodid,
              'prodid': prodid,
              'barcode': barcode,
              'productname': name,
              'name': name,
              'unit': item['unit']?.toString() ?? '',
              'saleprice': item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '0',
              'sellprice': item['sellprice']?.toString() ?? item['saleprice']?.toString() ?? '0',
              'costprice': item['costprice']?.toString() ?? '0',
              'stockqty': stockqty,
              'precheckqty': addQty,
              'batchno': item['batchno']?.toString() ?? '',
              'birthdate': item['birthdate']?.toString() ?? '',
              'validdate': item['validdate']?.toString() ?? '',
              'remark': item['remark']?.toString() ?? '',
              'size': item['size']?.toString() ?? '',
              'shelves': item['shelves']?.toString() ?? '',
              'stypeid': item['stypeid']?.toString() ?? '',
              'stypename': item['stypename']?.toString() ?? '',
              'morebatchflag': item['morebatchflag']?.toString() ?? '',
            };
            _normalizeDetailItem(newItem);
            // unshift 到列表首位（新增商品置顶显示）
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

  /// 商品详情弹窗（对齐采购入库详情抽屉样式 + boss 项目 proDetails 编辑行为）
  /// 新增/修改时可编辑预盘数量和批次；已审核时为只读
  void _showProductDetail(Map<String, dynamic> item, int index) {
    final disabled = _isSigned;
    final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
    final unit = item['unit']?.toString() ?? '';
    final barcode = item['barcode']?.toString() ?? item['selfbarcode']?.toString() ?? '';
    final saleprice =
        double.tryParse(item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '') ?? 0;
    final costprice = double.tryParse(item['costprice']?.toString() ?? '') ?? 0;
    final stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;
    final size = item['size']?.toString() ?? '';
    final shelves = item['shelves']?.toString() ?? '';
    final morebatchflag = item['morebatchflag']?.toString() ?? '';
    // 多批次商品：批次/数量点击跳转多选批次页（对齐 lxAss proDetails chosePc，仅看 morebatchflag）
    final isMultBatch = morebatchflag == '1';

    // 可编辑状态的局部变量
    double editPrecheckqty = double.tryParse(item['precheckqty']?.toString() ?? '') ?? 0;
    String editBatchno = item['batchno']?.toString() ?? '';
    String editBirthdate = _formatBatchDate(item['birthdate']);
    String editValiddate = _formatBatchDate(item['validdate']);
    String editSupid = item['supid']?.toString() ?? '';
    String editRemark = item['remark']?.toString() ?? '';

    final precheckqtyCtrl = TextEditingController(
      text: MathUtils.formatDecimal(1, editPrecheckqty),
    );
    final precheckqtyFocus = FocusNode();
    precheckqtyFocus.addListener(() {
      if (precheckqtyFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (precheckqtyCtrl.text.isNotEmpty) {
            precheckqtyCtrl.selection = TextSelection(
              baseOffset: 0,
              extentOffset: precheckqtyCtrl.text.length,
            );
          }
        });
      }
    });

    final remarkCtrl = TextEditingController(text: editRemark);

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
                // ── 标题栏 ──
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
                // ── 可滚动内容区 ──
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
                        // ── 商品信息卡片 ──
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
                              Text(
                                unit.isNotEmpty ? '$name（$unit）' : name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              if (barcode.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(barcode,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text('零售价：¥${MathUtils.formatDecimal(2, saleprice)}',
                                      style:
                                          const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                                  const SizedBox(width: 16),
                                  Text('成本价：¥${MathUtils.formatDecimal(2, costprice)}',
                                      style:
                                          const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                                ],
                              ),
                              if (shelves.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('货架号：$shelves',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              ],
                              if (size.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('规格：$size',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              ],
                              const SizedBox(height: 4),
                              Text('现库存：${MathUtils.formatDecimal(1, stockqty)}',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // ── 单位（只读） ──
                        _buildReadonlyField(label: '单位', value: unit),
                        _buildFormDivider(),
                        // ── 规格（只读） ──
                        _buildReadonlyField(label: '规格', value: size),
                        _buildFormDivider(),
                        // ── 批次 ──
                        if (disabled)
                          _buildReadonlyField(
                              label: '批次', value: editBatchno.isNotEmpty ? editBatchno : '-')
                        else
                          _buildSelectField(
                            label: '批次',
                            value: editBatchno,
                            onTap: () async {
                              final productid =
                                  item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
                              if (productid.isEmpty) {
                                Toast.show('商品信息异常');
                                return;
                              }
                              if (isMultBatch) {
                                // 多批次商品：关闭弹窗跳转多选批次页（对齐 lxAss chosePc）
                                Navigator.pop(ctx);
                                await _selectMultBatch(item);
                                return;
                              }
                              final result = await showModalBottomSheet<Map<String, dynamic>>(
                                context: ctx,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => SelectBatchSheet(
                                  productid: productid,
                                  bsid: _bsid ?? '',
                                  counterid: _counterid ?? '',
                                  initialBatchNo: editBatchno,
                                ),
                              );
                              if (result != null) {
                                setDialogState(() {
                                  editBatchno = result['batchno']?.toString() ?? '';
                                  // 选择批次后自动带出生产日期和有效期（对齐 web handleBatchConfirm）
                                  editBirthdate = _formatBatchDate(result['birthdate']);
                                  final bd = editBirthdate.isNotEmpty ? editBirthdate : '';
                                  editValiddate = _formatBatchDate(result['validdate']);
                                  if (editValiddate.isEmpty && bd.isNotEmpty) {
                                    editValiddate = bd;
                                  }
                                  editSupid = result['supid']?.toString() ?? '';
                                });
                              }
                            },
                          ),
                        _buildFormDivider(),
                        // ── 预盘数量 ──
                        if (disabled)
                          _buildReadonlyField(
                              label: '预盘数量', value: MathUtils.formatDecimal(1, editPrecheckqty))
                        else if (isMultBatch)
                          // 多批次商品：数量只读展示，点击跳转多选批次页（对齐 lxAss proDetails 数量可点击）
                          _buildSelectField(
                            label: '预盘数量',
                            value: MathUtils.formatDecimal(1, editPrecheckqty),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await _selectMultBatch(item);
                            },
                          )
                        else
                          _buildFormField(
                            label: '预盘数量',
                            controller: precheckqtyCtrl,
                            focusNode: precheckqtyFocus,
                            isDecimal: true,
                            onChanged: (v) {
                              final val = double.tryParse(v) ?? 0;
                              setDialogState(() => editPrecheckqty = val);
                            },
                          ),
                        _buildFormDivider(),
                        // ── 盈亏数量（实时计算，只读） ──
                        _buildReadonlyField(
                          label: '盈亏数量',
                          value: MathUtils.formatDecimal(1, editPrecheckqty - stockqty),
                          valueColor: (editPrecheckqty - stockqty) >= 0
                              ? const Color(0xFF00A870)
                              : const Color(0xFFD54B5A),
                        ),
                        _buildFormDivider(),
                        // ── 生产日期（只读，由批次自动带出，不可手动修改，对齐 lxAss tm-text 只读） ──
                        _buildReadonlyField(
                            label: '生产日期', value: editBirthdate.isNotEmpty ? editBirthdate : '-'),
                        _buildFormDivider(),
                        // ── 有效日期（只读，由批次自动带出，不可手动修改，对齐 lxAss tm-text 只读） ──
                        _buildReadonlyField(
                            label: '有效日期', value: editValiddate.isNotEmpty ? editValiddate : '-'),
                        _buildFormDivider(),
                        // ── 备注 ──
                        if (disabled)
                          _buildReadonlyField(label: '备注', value: editRemark)
                        else
                          _buildFormField(
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
                // ── 底部按钮区 ──
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
                                    _detailList[index]['precheckqty'] = editPrecheckqty;
                                    _detailList[index]['batchno'] = editBatchno;
                                    _detailList[index]['birthdate'] = editBirthdate;
                                    _detailList[index]['validdate'] = editValiddate;
                                    _detailList[index]['supid'] = editSupid;
                                    _detailList[index]['remark'] = editRemark;
                                    _normalizeDetailItem(_detailList[index]);
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

  /// 表单输入行（对齐采购入库 _buildFormField）
  static Widget _buildFormField({
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

  /// 只读展示行（对齐采购入库 _buildFormField 的只读态）
  static Widget _buildReadonlyField({
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

  /// 选择型字段（左标签 + 右"请选择/当前值 >"）
  static Widget _buildSelectField({
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

  static Widget _buildFormDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));

  /// 将批次接口返回的日期字段统一格式化为 YYYY-MM-DD
  /// 支持 ISO 字符串、时间戳毫秒数、已格式化字符串
  static String _formatBatchDate(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null') return '';
    // 尝试解析 ISO 字符串
    try {
      final dt = DateTime.parse(s);
      final mo = dt.month.toString().padLeft(2, '0');
      final dy = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$mo-$dy';
    } catch (_) {}
    // 尝试解析时间戳毫秒数
    final ms = int.tryParse(s);
    if (ms != null && ms > 1000000000000) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final mo = dt.month.toString().padLeft(2, '0');
      final dy = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$mo-$dy';
    }
    return s;
  }

  /// 日期选择弹窗（年/月/日 滚轮）已废弃：预盘/快速盘点日期字段只读，由批次自动带出

  void _toggleIndex(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
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
      ),
    ).then((confirm) {
      if (confirm != true) return;
      setState(() {
        final sorted = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
        for (final i in sorted) {
          _detailList.removeAt(i);
        }
        _selectedIndices.clear();
        _isSelectMode = false;
      });
    });
  }

  // ── 扫描 ──
  Future<void> _scanBarcode() async {
    if (_planid == null || _planid!.isEmpty) {
      Toast.show('请选择盘点计划');
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
      Toast.show('当前平台暂不支持扫码');
    }
  }

  /// 扫码输入统一处理入口。
  /// 在防抖等待结束后才读取条码，确保扫码头经 IME 注入的字符已全部提交——
  /// 避免 Enter 到达时立即读取漏掉末尾字符，导致查询"未找到商品"。
  void _processScanInput() {
    if (!mounted) return;
    final code = _scanController.text.trim();
    if (code.isEmpty) return;
    debugPrint('[红外扫描] 防抖触发, 处理条码: "$code"');
    _handleScannedBarcode(code, returnFocusNode: _scanFocusNode);
    _scanController.clear();
    _scanFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// 处理扫码结果：若商品已存在则累加数量，否则新增明细行
  /// [returnFocusNode] 有值时，扫码完成后焦点回到该节点（用于红外扫描框连续扫码）
  void _handleScannedBarcode(String code, {FocusNode? returnFocusNode}) {
    if (code.trim().isEmpty) return;
    if (_planid == null || _planid!.isEmpty) {
      Toast.show('请选择盘点计划');
      return;
    }
    debugPrint(
        '[红外扫描] 开始查询条码: $code, bsid=$_bsid, counterid=$_counterid, planid=$_planid, checktype=$_checktype');
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
      'morebatchflag': 1,
      'billtypeflag': 'ypd',
      'storeid': _bsid ?? '',
      'counterid': _counterid ?? '',
      'checktype': _checktype,
      'planid': _planid,
      'notmoresizeunit': 1,
    };
    request(HttpApi.productGetList, params, false, false).then((result) {
      if (!mounted) return;
      debugPrint('[红外扫描] 接口返回: $result');
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      debugPrint('[红外扫描] 商品列表长度: ${list.length}');
      if (list.isNotEmpty) {
        // 对齐 lxAss scanFn：自编码/条码命中分流
        final match = matchScanList(list, searchCode);
        if (match.needJump) {
          _selectProduct(keyword: searchCode);
          return;
        }
        final prod = match.primary ?? (list.first as Map<String, dynamic>);
        // 对齐 lxAss scanFn：普通码数量 = 接口 precheckqty + 1；重量码直接设数量；金额码按金额/单价反算（单价取 price → costprice → saleprice）
        final double baseQty = double.tryParse(prod['precheckqty']?.toString() ?? '0') ?? 0;
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
        final String prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
        final String barcode = prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? '';
        Map<String, dynamic>? targetItem;
        int? targetIndex;
        bool duplicated = false;
        if (prodid.isNotEmpty) {
          final existing = _detailList.cast<Map<String, dynamic>?>().firstWhere(
            (r) {
              final rProdid = r!['prodid']?.toString() ?? r['productid']?.toString() ?? '';
              final rBarcode = r['barcode']?.toString() ?? r['selfbarcode']?.toString() ?? '';
              return rProdid == prodid && (barcode.isEmpty || rBarcode == barcode);
            },
            orElse: () => null,
          );
          if (existing != null) {
            if (_scanSettings.scanQtyMode == 0) {
              // 默认累加1模式
              setState(() {
                final curQty = double.tryParse(existing['precheckqty']?.toString() ?? '0') ?? 0;
                existing['precheckqty'] = curQty + scannedQty;
                _normalizeDetailItem(existing);
              });
              Toast.show('扫描添加成功');
            }
            targetItem = existing;
            targetIndex = _detailList.indexOf(existing);
            duplicated = true;
          }
        }
        if (!duplicated) {
          final stockqty = double.tryParse(prod['stockqty']?.toString() ?? '0') ?? 0;
          final newItem = <String, dynamic>{
            'productname': prod['productname']?.toString() ?? prod['name']?.toString() ?? '',
            'name': prod['productname']?.toString() ?? prod['name']?.toString() ?? '',
            'unit': prod['unit']?.toString() ?? '',
            'size': prod['size']?.toString() ?? '',
            'barcode': barcode,
            'saleprice': prod['saleprice']?.toString() ?? prod['sellprice']?.toString() ?? '0',
            'sellprice': prod['sellprice']?.toString() ?? '0',
            'costprice': prod['costprice']?.toString() ?? '0',
            'stockqty': stockqty,
            'precheckqty': scannedQty,
            'prodid': prodid,
            'productid': prod['productid']?.toString() ?? prodid,
            'batchno': prod['batchno']?.toString() ?? '',
            'morebatchflag': prod['morebatchflag']?.toString() ?? '',
          };
          _normalizeDetailItem(newItem);
          setState(() {
            // unshift 到列表首位（新增商品置顶显示）
            _detailList.insert(0, newItem);
          });
          if (_scanSettings.scanQtyMode == 0) {
            Toast.show('扫描添加成功');
          }
          targetItem = newItem;
          targetIndex = 0;
        }

        // 根据扫码设置决定后续行为
        if (_scanSettings.scanQtyMode == 1) {
          // 弹窗手动输入模式：打开商品详情抽屉
          if (targetIndex != null && targetItem != null) {
            _showProductDetail(targetItem, targetIndex);
          }
        } else {
          // 默认累加1模式：焦点处理
          _focusAfterScan(returnFocusNode);
        }
      } else {
        if (mounted) Toast.show('未找到匹配商品，请重新扫码录入！');
        _focusAfterScan(returnFocusNode);
      }
    }).catchError((Object e) {
      debugPrint('[红外扫描] 接口异常: $e');
      if (mounted) Toast.show('查询商品失败: $e');
      _focusAfterScan(returnFocusNode);
    });
  }

  /// 扫码后焦点处理：优先回到 returnFocusNode，否则跳到扫码输入框
  void _focusAfterScan(FocusNode? returnFocusNode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scanSettings.scanContinuous) {
        // 连续扫码开启：焦点回到扫描框
        if (returnFocusNode != null) {
          returnFocusNode.requestFocus();
        } else if (_scanSettings.showInfraredInput) {
          _scanFocusNode.requestFocus();
        }
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } else {
        // 连续扫码关闭：无特殊处理（预盘单没有明细行数量焦点概念）
        // 默认回到扫描框
        if (returnFocusNode != null) {
          returnFocusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        } else if (_scanSettings.showInfraredInput) {
          _scanFocusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        }
      }
    });
  }

  // ── 选择批次 ──
  // ── 多批次选择 ──
  /// 多批次商品：跳转多选批次页，确认后删除该商品旧行并按批次生成新行
  /// （对齐 lxAss preOrderEdit onSelectMultBatchPage + selectMultBatch 多选页）
  Future<void> _selectMultBatch(Map<String, dynamic> item) async {
    final productid = item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
    if (productid.isEmpty) {
      Toast.show('商品信息异常');
      return;
    }
    // 已选数据回显：当前明细中该商品的所有行（对齐 lxAss selectBatchList = detaillist）
    final selectList = _detailList
        .where((e) => (e['productid']?.toString() ?? e['prodid']?.toString() ?? '') == productid)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final result = await SelectMultBatchSheet.show(
      context,
      productid: productid,
      bsid: _bsid ?? '',
      counterid: _counterid ?? '',
      selectList: selectList,
    );
    if (result == null || !mounted) return;
    setState(() {
      // 先删除该商品所有旧行（对齐 lxAss filter productid）
      _detailList.removeWhere(
          (e) => (e['productid']?.toString() ?? e['prodid']?.toString() ?? '') == productid);
      // 每个选中批次生成一行（对齐 lxAss {...currCliRow, ...el, addbatchflag: 1} + defValSet + writeData）
      for (final el in result) {
        final obj = Map<String, dynamic>.from(item)
          ..addAll(el)
          ..['addbatchflag'] = 1;
        _normalizeDetailItem(obj);
        _detailList.add(obj);
      }
    });
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEdit ? '修改预盘单' : '新增预盘单',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : Column(
              children: [
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xFFF5F5F5),
                    child: CustomScrollView(
                      cacheExtent: 800,
                      slivers: [
                        // ---- 单号+状态（编辑模式，可滚动消失） ----
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
                                  border: Border.all(color: const Color(0xFFEEEEEE)),
                                ),
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
                                      Text(
                                          _isSigned
                                              ? '已审核'
                                              : (_isRejected ? '已驳回' : '待审核'),
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: _isSigned
                                                  ? const Color(0xFF00A870)
                                                  : (_isRejected
                                                      ? const Color(0xFFFF9900)
                                                      : const Color(0xFFD54B5A)))),
                                    ]),
                                    const SizedBox(height: 6),
                                    Text('制单信息：${_billData?['createtime'] ?? ''}',
                                        style: const TextStyle(
                                            fontSize: 12, color: Color(0xFF7A7A7A))),
                                    const SizedBox(height: 4),
                                    Text('制单人：${_billData?['createname'] ?? ''}',
                                        style: const TextStyle(
                                            fontSize: 12, color: Color(0xFF7A7A7A))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // ---- 审核日志卡片（多级审批） ----
                        if (_isEdit && (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty))
                          SliverToBoxAdapter(
                              child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                  child: _buildApprovalNodeCard())),
                        // ---- 表单卡片（可滚动消失） ----
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFEEEEEE)),
                              ),
                              child: Column(children: [
                                _buildSelectRow(
                                    label: '盘点计划',
                                    value: _planname ?? '',
                                    onTap: disabled ? null : _selectPlan,
                                    required: true),
                                _buildDivider(),
                                _buildReadonlyRow(label: '盘点机构', value: _storename ?? ''),
                                _buildDivider(),
                                _buildReadonlyRow(label: '盘点仓库', value: _countername ?? ''),
                                _buildDivider(),
                                _buildReadonlyRow(
                                    label: _checktypeName(_checktype), value: _filterTypeNames()),
                                _buildDivider(),
                                _buildInputRow(
                                    label: '备注', controller: _remarkCtrl, disabled: disabled),
                                _buildDivider(),
                                _buildAttachButton(),
                              ]),
                            ),
                          ),
                        ),
                        // 不显示红外扫描框时，补充与粘性表头之间的间距
                        if (!disabled && !_scanSettings.showInfraredInput)
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        // ---- 粘性表头：扫描框 + 商品明细标题/操作按钮（滚到此处后固定） ----
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _PrecheckStickyHeaderDelegate(state: this),
                        ),
                        // ---- 空状态（独立 Sliver，不在粘性表头内） ----
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
                        // ---- 明细行列表（SliverList 逐项渲染） ----
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
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(disabled),
    );
  }

  Widget _buildBottomBar(bool disabled) {
    if (_isSelectMode) {
      return _buildBatchDeleteBar();
    }
    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 汇总行
          if (_detailList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text(
                  '预盘数量：${MathUtils.formatDecimal(1, _totalPrecheckQty)}，共 ${_detailList.length} 项',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
              ]),
            ),
          Row(children: [
            if (_isEdit && _isSigned) ...[
              Expanded(
                child: GestureDetector(
                  onTap: _submitAction != _PCAction.none ? null : _resign,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFCCCCCC)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: _submitAction == _PCAction.resign
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF999999)))
                        : const Text('反审核',
                            style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _submitAction != _PCAction.none ? null : _print,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF006EFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: _submitAction == _PCAction.print
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('打印', style: TextStyle(fontSize: 15, color: Colors.white)),
                  ),
                ),
              ),
            ] else if (_isEdit && !_isSigned) ...[
              // “更多”按钮（删除/打印）- reviewsignflag != 2 && bolHandleTT
              if (!_isWithdrawPending && _bolHandleTT) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: _submitAction != _PCAction.none ? null : _showMoreMenu,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCCCCCC)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: const Text('更多',
                          style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // 保存/审核按钮 - signflag!=2 && reviewsignflag!=2 && (bolHandleTT || (审批流>0 && bolHandleT))
              if (!_isRejected &&
                  !_isWithdrawPending &&
                  (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT))) ...[
              Expanded(
                child: GestureDetector(
                  onTap: _submitAction != _PCAction.none ? null : () => _save(),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF006EFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: _submitAction == _PCAction.save
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('保存', style: TextStyle(fontSize: 15, color: Colors.white)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _submitAction != _PCAction.none ? null : () => _save(doSign: true),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A870),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: _submitAction == _PCAction.sign
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('审核', style: TextStyle(fontSize: 15, color: Colors.white)),
                  ),
                ),
              ),
            ],
              // 撤回按钮 - 仅已驳回状态(signflag==2)显示
              if (_isRejected) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _submitAction != _PCAction.none ? null : _restsign,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9900),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: _submitAction == _PCAction.withdraw
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('撤回',
                              style: TextStyle(fontSize: 15, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ] else ...[
              Expanded(
                child: GestureDetector(
                  onTap: _submitAction != _PCAction.none ? null : () => _save(),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF006EFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: _submitAction == _PCAction.save
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('保存', style: TextStyle(fontSize: 15, color: Colors.white)),
                  ),
                ),
              ),
              // 审核按钮 - billSign
              if (_billSign) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _submitAction != _PCAction.none ? null : () => _save(doSign: true),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A870),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: _submitAction == _PCAction.sign
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('审核', style: TextStyle(fontSize: 15, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ],
          ]),
        ],
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

  // ── 选择盘点计划 ──
  Future<void> _selectPlan() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectInventoryPlanPage(bsid: _bsid),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _planid = result['billid']?.toString();
        _planname = result['planname']?.toString();
        _bsid = result['bsid']?.toString() ?? _bsid;
        _storename = result['storename']?.toString() ?? _storename;
        _counterid = result['counterid']?.toString();
        _countername = result['countername']?.toString();
        _checktype = int.tryParse(result['checktype']?.toString() ?? '') ?? 2;
        final typeArr = result['stockPlanItemtypeResp'] as List? ?? [];
        _typeList = typeArr.cast<Map<String, dynamic>>();
      });
    }
  }

  static Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    bool disabled = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        // 星号固定占位，文字始终从同一起点对齐
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
        ),
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
              hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
            ),
          ),
        ),
      ]),
    );
  }

  static Widget _buildSelectRow({
    required String label,
    required String value,
    VoidCallback? onTap,
    bool required = false,
  }) {
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
                  color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
                )),
          ),
          const SizedBox(width: 4),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
        ]),
      ),
    );
  }

  static Widget _buildReadonlyRow({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(children: [
        // 星号固定占位，文字始终从同一起点对齐
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value.isNotEmpty ? value : '-',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
        ),
      ]),
    );
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
          menuid: '080801',
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
          SizedBox(width: _isSigned ? 0 : 8),
          SizedBox(
              width: _isSigned ? 72 : 64,
              child: const Text('附件',
                  style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w500))),
          const SizedBox(width: 8),
          Expanded(
              child: Row(children: [
            const Icon(Icons.attach_file, size: 16, color: Color(0xFF006EFF)),
            const SizedBox(width: 4),
            Text('附件(${_fileLists.length})',
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFFC0C4CC)),
          ])),
        ]),
      ),
    );
  }

  /// 粘性表头区域高度常量（扫描框 + 商品明细标题行）
  /// minExtent = maxExtent 表头不收缩，内容恒山可见，消除溢出和间隙
  static const double _stickyScanHeight = 62.0;
  static const double _stickyTitleHeight = 56.0; // 精确对齐内容高度消除间隙
  static const double _stickySignedExtent = 50.0; // 已审核时仅显示标题行
  static const double _stickyMaxExtent = _stickyScanHeight + _stickyTitleHeight; // 118
  static const double _stickyMinExtent = _stickyMaxExtent; // = 118，不收缩

  /// 构建粘性表头内容（扫描框 + 商品明细标题/操作按钮）
  /// 外层用 Align 确保内容始终靠上对齐，避免 maxExtent 偏大时内容居中推挤明细行
  Widget _buildStickyHeader(double extent) {
    final disabled = _isSigned;
    return Align(
      alignment: Alignment.topCenter,
      child: ColoredBox(
        color: const Color(0xFFF5F5F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 扫描输入框（仅非已审核且设置了显示红外输入框时显示）
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
                        // 与 onKeyEvent 相同的异步时序问题：不立即读取，重置防抖延迟读取。
                        // 盘点计划等前置校验统一在 _handleScannedBarcode 内处理。
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
            // 商品明细卡片标题 + 操作按钮（仅保留底部边框）
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
                      const SizedBox(width: 12),
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
                                      fontWeight: FontWeight.w500)),
                            ])),
                        const SizedBox(width: 12),
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

  /// 构建单个明细行
  Widget _buildDetailItem(Map<String, dynamic> item, int idx, bool disabled) {
    final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
    final unit = item['unit']?.toString() ?? '';
    final batchno = item['batchno']?.toString() ?? '';
    final morebatchflag = item['morebatchflag']?.toString() ?? '';
    final mbillid = item['mbillid']?.toString() ?? '';
    final addbatchflag = item['addbatchflag']?.toString() ?? '';
    // 多批次商品且未合并批次时显示"请选择批次"（对齐 lxAss preOrderEdit 列表项）
    final showMultBatchLink = morebatchflag == '1' && mbillid.isEmpty && addbatchflag.isEmpty;
    final saleprice =
        double.tryParse(item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '') ?? 0;
    final stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;
    final precheckqty = double.tryParse(item['precheckqty']?.toString() ?? '') ?? 0;
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isSelectMode) ...[
                  Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                      color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFBDBDBD)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(unit.isNotEmpty ? '$name（$unit）' : name,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827)))),
                        if (!disabled && showMultBatchLink)
                          GestureDetector(
                              onTap: () => _selectMultBatch(item),
                              child: const Text('请选择批次',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF006EFF),
                                      fontWeight: FontWeight.w500))),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                            child: Text('批次：$batchno',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                        Text('零售价：¥${MathUtils.formatDecimal(2, saleprice)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                            child: Text('现库存：${MathUtils.formatDecimal(1, stockqty)}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                        Text('预盘数量：${MathUtils.formatDecimal(1, precheckqty)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                      ]),
                      const SizedBox(height: 4),
                      Text('盈亏数量：${MathUtils.formatDecimal(1, qty)}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: qty >= 0 ? const Color(0xFF00A870) : const Color(0xFFD54B5A))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
        ],
      ),
    );
  }
}

/// 预盘单粘性表头代理
class _PrecheckStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PrecheckStickyHeaderDelegate({required this.state});
  final _InventoryPrecheckAddPageState state;
  @override
  double get minExtent => state._isSigned
      ? _InventoryPrecheckAddPageState._stickySignedExtent
      : (state._scanSettings.showInfraredInput
          ? _InventoryPrecheckAddPageState._stickyMinExtent
          : _InventoryPrecheckAddPageState._stickyTitleHeight);
  @override
  double get maxExtent => state._isSigned
      ? _InventoryPrecheckAddPageState._stickySignedExtent
      : (state._scanSettings.showInfraredInput
          ? _InventoryPrecheckAddPageState._stickyMaxExtent
          : _InventoryPrecheckAddPageState._stickyTitleHeight);
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader(maxExtent);
  }

  @override
  bool shouldRebuild(covariant _PrecheckStickyHeaderDelegate oldDelegate) => true;
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
