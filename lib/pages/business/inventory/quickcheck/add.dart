import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_batch.dart';
import 'package:flutter_deer/components/select/select_mult_batch.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_unit_size.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
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
import 'package:flutter_deer/widgets/unsaved_changes_dialog.dart';
import 'package:sp_util/sp_util.dart';

enum _QCAction { none, save, sign, delete, print, withdraw }

class InventoryQuickcheckAddPage extends StatefulWidget {
  const InventoryQuickcheckAddPage({super.key, this.billData});
  final Map<String, dynamic>? billData;

  @override
  State<InventoryQuickcheckAddPage> createState() => _InventoryQuickcheckAddPageState();
}

class _InventoryQuickcheckAddPageState extends State<InventoryQuickcheckAddPage>
    with LogPageMixin<InventoryQuickcheckAddPage> {
  @override
  String get logPageName => _isEdit ? '快速盘点详情' : '快速盘点新增';

  final TextEditingController _remarkCtrl = TextEditingController();

  // ---- 红外扫描输入框（PDA 扫码枪）----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer; // 扫码防抖：扫码枪注入字符极快，停止变化后自动触发查询

  String? _bsid;
  String? _storename;
  String? _counterid;
  String? _countername;
  List<Map<String, dynamic>> _detailList = [];

  _QCAction _submitAction = _QCAction.none;
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

  /// 未保存修改比对基线（进入页面/加载完成/保存完成后更新）
  String _formSnapshot = '';

  bool get _isEdit => _billData != null && (_billData!['billid']?.toString().isNotEmpty ?? false);
  bool get _isSigned => _billData?['signflag']?.toString() == '1';

  /// 系统参数「盘点不管理批次」(stockCheckAllBatch)：开启后同一商品多批次库存合并，
  /// 库存与盈亏取商品总库存 allstockqty，批次/生产日期/有效期等配置项全部隐藏且不再选批次
  /// （对齐 lxAss quickInventoryEdit isCheckAllBatch / stockField）
  bool _checkAllBatch = false;

  /// 读取登录参数指定 key 的数值（对齐 Vue userStore().loginParamResp），缺失或解析异常返回 0
  static int _loginParamInt(String key) {
    try {
      final String cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isEmpty) return 0;
      final Map<String, dynamic> cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
      return int.tryParse(cfg[key]?.toString() ?? '0') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 参与盈亏等计算的库存：不管理批次取商品总库存 allstockqty，否则取批次库存 stockqty
  /// （对齐 lxAss getStockQty）
  double _stockQtyOf(Map<String, dynamic> row) =>
      double.tryParse(row[_checkAllBatch ? 'allstockqty' : 'stockqty']?.toString() ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
    // 系统参数「盘点不管理批次」：决定库存口径（allstockqty / stockqty）与批次相关配置显隐
    _checkAllBatch = _loginParamInt('stockCheckAllBatch') == 1;
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
    // 新增模式：默认值回填后建立基线，未改动直接返回不弹窗
    _refreshSnapshot();
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
    request(HttpApi.stockcheckfastGetInfo, params).then((result) {
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
          final detailArr = data['detaillist'] as List? ?? [];
          _detailList = detailArr.map<Map<String, dynamic>>((e) {
            final m = Map<String, dynamic>.from(e as Map);
            // 确保 checkqty 有值
            m['checkqty'] = m['checkqty'] ?? m['precheckqty'] ?? 0;
            _computeAmts(m);
            return m;
          }).toList();
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
      // 详情加载完成后重建基线，未改动直接离开不弹窗
      _refreshSnapshot();
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

  double get _totalCheckQty {
    double total = 0;
    for (final item in _detailList) {
      total += double.tryParse(item['checkqty']?.toString() ?? '') ?? 0;
    }
    return total;
  }

  /// 计算明细行金额字段（对齐 boss 项目 amtJudge + defValSet）
  void _computeAmts(Map<String, dynamic> item) {
    final checkqty = double.tryParse(item['checkqty']?.toString() ?? '0') ?? 0;
    final costprice = double.tryParse(item['costprice']?.toString() ?? '0') ?? 0;
    final saleprice =
        double.tryParse(item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '0') ?? 0;
    final intaxrate = double.tryParse(item['intaxrate']?.toString() ?? '0') ?? 0;
    // 商品总库存：保留接口值，缺省补 0（对齐 zmProMax defValSet）
    final allstockqty = double.tryParse(item['allstockqty']?.toString() ?? '0') ?? 0;

    // 写回 saleprice（对齐预盘单 _normalizeDetailItem）：拆行/扫描等路径可能只有 sellprice 字段，
    // 后端保存要求每行 saleprice 非空，避免「售价(saleprice)=null」报错
    item['saleprice'] = saleprice;
    item['allstockqty'] = allstockqty;
    // 盈亏数量按系统参数口径计算：盘点不管理批次时相对总库存 allstockqty，否则相对批次库存 stockqty
    // （对齐 lxAss writeData/defValSet：先算 qty，amtJudge 再按最新 qty 计算盈亏金额）
    final double qty = MathUtils.formatDecimalNum(1, MathUtils.subtract(checkqty, _stockQtyOf(item)));
    item['qty'] = MathUtils.formatDecimal(1, qty);
    item['singleamt'] = MathUtils.formatDecimal(3, MathUtils.mul(checkqty, costprice)); // 盘点金额
    item['costamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, costprice)); // 盈亏金额
    item['retailamt'] = MathUtils.formatDecimal(3, MathUtils.mul(checkqty, saleprice)); // 零售金额
    item['sellamt'] = MathUtils.formatDecimal(3, MathUtils.mul(qty, saleprice)); // 盈亏售额
    // 对齐boss项目 amtJudge：始终计算未税字段（intaxrate=0时除以1不影响值）
    final taxFactor = 1 + intaxrate;
    item['notaxcostprice'] = MathUtils.formatDecimal(2, MathUtils.divide(costprice, taxFactor));
    item['notaxsingleamt'] =
        MathUtils.formatDecimal(3, MathUtils.divide(MathUtils.mul(checkqty, costprice), taxFactor));
    item['notaxcostamt'] =
        MathUtils.formatDecimal(3, MathUtils.divide(MathUtils.mul(qty, costprice), taxFactor));
  }

  // ═══ 返回与未保存修改检测 ═══

  /// 生成当前表单快照（拼接所有用户可修改字段，用于返回时比对是否改动）
  String _buildSnapshot() {
    return [
      _bsid,
      _counterid,
      _remarkCtrl.text,
      jsonEncode(_fileLists),
      jsonEncode(_detailList
          .map((e) => {
                'prodid': e['prodid']?.toString() ?? '',
                'unit': e['unit']?.toString() ?? '',
                'size': e['size']?.toString() ?? '',
                'checkqty': e['checkqty']?.toString() ?? '',
                'stockqty': e['stockqty']?.toString() ?? '',
                'allstockqty': e['allstockqty']?.toString() ?? '',
                'saleprice': e['saleprice']?.toString() ?? '',
                'batchno': e['batchno']?.toString() ?? '',
                'birthdate': e['birthdate']?.toString() ?? '',
                'validdate': e['validdate']?.toString() ?? '',
                'remark': e['remark']?.toString() ?? '',
              })
          .toList()),
    ].join('|');
  }

  /// 刷新快照（数据加载/保存完成后调用，作为改动比对基准）
  void _refreshSnapshot() {
    _formSnapshot = _buildSnapshot();
  }

  /// 是否存在未保存的修改
  bool get _isDirty => _buildSnapshot() != _formSnapshot;

  /// 未保存拦截仅在可保存态生效：新增/待审核（signflag 0）单据；
  /// 已审核(1)/已驳回(2) 为只读或撤回态，无保存入口，直接放行
  bool get _guardEnabled => (_billData?['signflag']?.toString() ?? '0') == '0';

  /// 返回统一入口：存在未保存修改时弹出「确认保存吗」弹窗
  Future<void> _onBackPressed() async {
    if (!_guardEnabled || !_isDirty) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    final result = await showUnsavedChangesDialog(context);
    if (result ?? false) {
      // 选择保存：校验/保存失败时留在当前页并提示
      _save(popAfterSave: true);
    } else if (result == false) {
      if (mounted) Navigator.pop(context, true);
    }
  }

  void _save({bool doSign = false, bool popAfterSave = false}) {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('013803', showTip: false)) {
        Toast.show('你无权编辑快速盘点，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('013802', showTip: false)) {
        Toast.show('你无权新增快速盘点，请在后台修改权限');
        return;
      }
    }
    logSave(doSign ? '保存并审核' : '保存单据');
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请选择盘点机构');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请选择盘点仓库');
      return;
    }
    if (_detailList.isEmpty) {
      Toast.show('请选择商品');
      return;
    }

    setState(() => _submitAction = _QCAction.save);
    // 保存前重新计算所有明细行金额字段
    for (final item in _detailList) {
      _computeAmts(item);
    }
    // 批次库存盈亏：billqty / billamt 固定基于批次库存 stockqty 计算，不随系统参数切换
    // 总库存盈亏：billallqty / billallamt 固定基于商品总库存 allstockqty 计算，盈亏金额按成本价计算
    // （对齐 zmProMax/lxAss stockcheckfast/save）
    double billqty = 0;
    double billamt = 0;
    double billallqty = 0;
    double billallamt = 0;
    for (final item in _detailList) {
      final checkqty = double.tryParse(item['checkqty']?.toString() ?? '0') ?? 0;
      final costprice = double.tryParse(item['costprice']?.toString() ?? '0') ?? 0;
      final stockQty = double.tryParse(item['stockqty']?.toString() ?? '0') ?? 0;
      final allStockQty = double.tryParse(item['allstockqty']?.toString() ?? '0') ?? 0;
      final stockProfitqty = MathUtils.subtract(checkqty, stockQty);
      billqty = MathUtils.add(billqty, stockProfitqty);
      billamt = MathUtils.add(billamt, MathUtils.mul(stockProfitqty, costprice));
      final allqty = MathUtils.subtract(checkqty, allStockQty);
      billallqty = MathUtils.add(billallqty, allqty);
      billallamt = MathUtils.add(billallamt, MathUtils.mul(allqty, costprice));
    }
    final params = <String, dynamic>{
      'bsid': _bsid,
      'storename': _storename,
      'counterid': _counterid,
      'countername': _countername,
      'signflag': 0,
      'remark': _remarkCtrl.text.trim(),
      'fileLists': _fileLists,
      'billqty': MathUtils.formatDecimal(1, billqty),
      'billamt': MathUtils.formatDecimal(3, billamt),
      'billallqty': MathUtils.formatDecimal(1, billallqty),
      'billallamt': MathUtils.formatDecimal(3, billallamt),
      'detaillist': _detailList,
    };
    if (_isEdit) params['billid'] = _billData!['billid'];

    // 对齐boss项目：仅新单据用save响应更新_billData（获取billid等服务端字段）
    // 已有单据保持getInfo返回的完整数据，避免sign时丢失字段
    final isNew = !_isEdit;
    request(HttpApi.stockcheckfastSave, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic> && isNew) {
        setState(() => _billData = data);
      }
      if (!doSign) {
        Toast.show('保存成功');
        // 保存成功后重建基线，避免返回时重复提示
        _refreshSnapshot();
      } else if (data is Map<String, dynamic>) {
        _doSignAfterSave(data);
      } else {
        _sign();
      }
      // 返回拦截中选择「保存」：保存成功后直接返回上一页
      if (popAfterSave && !doSign && mounted) Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted && !doSign) setState(() => _submitAction = _QCAction.none);
    });
  }

  void _sign() {
    if (!PermissionUtils.checkPermission('013805', showTip: false)) {
      Toast.show('你无权审核快速盘点，请在后台修改权限');
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
          setState(() => _submitAction = _QCAction.none);
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
        if (mounted) setState(() => _submitAction = _QCAction.none);
        return;
      }
      _doSign();
    });
  }

  /// 执行审核操作（多级审批：携带 reviewsignflag/reviewremark）
  void _doSign() {
    if (_billData == null) return;
    setState(() => _submitAction = _QCAction.sign);
    // 对齐boss项目：sign接口传完整表单数据（含detaillist及计算后的金额字段）
    final signParams = <String, dynamic>{
      ...(_billData ?? {}),
      'bsid': _bsid,
      'storename': _storename,
      'counterid': _counterid,
      'countername': _countername,
      'signflag': 1,
      'reviewremark': _billData?['reviewremark']?.toString() ?? '',
      'remark': _remarkCtrl.text.trim(),
      'fileLists': _fileLists,
      'detaillist': _detailList,
    };
    // reviewsignflag: 2=撤回保持不变，0=驳回保持不变，其余设为1（通过）
    final int rsf = int.tryParse(_billData?['reviewsignflag']?.toString() ?? '') ?? -1;
    if (rsf != 2 && rsf != 0) signParams['reviewsignflag'] = 1;
    request(HttpApi.stockcheckfastSign, signParams).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _QCAction.none);
    });
  }

  Future<void> _delBill() async {
    if (_billData == null) return;
    if (!PermissionUtils.checkPermission('013804', showTip: false)) {
      Toast.show('你无权删除快速盘点，请在后台修改权限');
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
    setState(() => _submitAction = _QCAction.delete);
    request(HttpApi.stockcheckfastDelBill, _billData).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _QCAction.none);
    });
  }

  Future<void> _print() async {
    if (_billData == null) return;
    setState(() => _submitAction = _QCAction.print);
    request(HttpApi.purchaseInstorePrint, {'menuid': '080901', 'data': _billData}).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _QCAction.none);
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
        'billtypeid': '0810',
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

    setState(() => _submitAction = _QCAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.stockcheckfastSign, params).then((result) {
      if (!mounted) return;
      Toast.show('撤回成功');
      _loadDetail();
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _QCAction.none);
    });
  }

  Future<void> _selectProduct({String? keyword}) async {
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请选择盘点机构');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请选择盘点仓库');
      return;
    }
    final result = await Navigator.push<List<Map<String, dynamic>>>(
        context,
        MaterialPageRoute(
            builder: (_) => SelectProductPage(
                  storeid: int.tryParse(_bsid ?? ''),
                  counterid: _counterid,
                  billtypeflag: 'kspd',
                  initialKeyword: keyword,
                )));
    if (result != null && mounted) {
      setState(() {
        for (final item in result) {
          // 系统参数「盘点不管理批次」：不展开批次行，同一商品保持一行（库存取商品总库存 allstockqty）
          // 对齐 lxAss onSelectProduct：if (isCheckAllBatch) delete item.batchList
          if (_checkAllBatch) item.remove('batchList');
          // 多批次商品（morebatchflag==1）：选择页返回 batchList（单行合并），先移除旧行再拆成每批次一行（对齐 lxAss onSelectProduct：替换而非累加）
          if (item['morebatchflag']?.toString() == '1' && !_checkAllBatch) {
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
                _computeAmts(obj);
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
          final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';

          final existIdx = _detailList.indexWhere((e) =>
              (e['prodid']?.toString() ?? e['productid']?.toString() ?? '') == prodid &&
              (barcode.isEmpty ||
                  (e['barcode']?.toString() ?? e['selfbarcode']?.toString() ?? '') == barcode));

          if (existIdx >= 0) {
            final cur = double.tryParse(_detailList[existIdx]['checkqty']?.toString() ?? '0') ?? 0;
            _detailList[existIdx]['checkqty'] = cur + addQty;
            _computeAmts(_detailList[existIdx]);
          } else {
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
              // 商品总库存（商品级，按批次行原样透传；对齐 zmProMax defValSet）
              'allstockqty': item['allstockqty']?.toString() ?? '0',
              'checkqty': addQty,
              'qty': MathUtils.formatDecimal(1, MathUtils.subtract(addQty, stockqty)),
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
              'validflag': item['validflag']?.toString() ?? '',
              // 保质天数：作为生产日期→有效日期联动计算依据（对齐 lxAss birthdateConfirm）
              'validday': item['validday']?.toString() ?? '',
              'supid': item['supid']?.toString() ?? '',
            };
            _computeAmts(newItem);
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

  // ── 扫描 ──
  Future<void> _scanBarcode() async {
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请先选择盘点仓库');
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
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请先选择盘点仓库');
      return;
    }
    debugPrint('[红外扫描] 开始查询条码: $code, bsid=$_bsid, counterid=$_counterid');
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
      'billtypeflag': 'ypd',
      'morebatchflag': 1,
      'storeid': _bsid ?? '',
      'counterid': _counterid ?? '',
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
        // 对齐 lxAss scanFn：普通码数量 = 接口 checkqty + 1；重量码直接设数量；金额码按金额/单价反算（单价取 price → costprice → saleprice）
        final double baseQty = double.tryParse(prod['checkqty']?.toString() ?? '0') ?? 0;
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
            setState(() {
              final curQty = double.tryParse(existing['checkqty']?.toString() ?? '0') ?? 0;
              existing['checkqty'] = curQty + scannedQty;
              _computeAmts(existing);
            });
            Toast.show('扫描添加成功');
            duplicated = true;
          }
        }
        if (!duplicated) {
          setState(() {
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
              // 商品总库存（商品级，按批次行原样透传；对齐 zmProMax defValSet）
              'allstockqty': prod['allstockqty']?.toString() ?? '0',
              'checkqty': scannedQty,
              'qty': MathUtils.formatDecimal(1, MathUtils.subtract(scannedQty, stockqty)),
              'prodid': prodid,
              'productid': prod['productid']?.toString() ?? prodid,
              'batchno': prod['batchno']?.toString() ?? '',
              'stypeid': prod['stypeid']?.toString() ?? '',
              'stypename': prod['stypename']?.toString() ?? '',
              'intaxrate': prod['intaxrate']?.toString() ?? '0',
              'morebatchflag': prod['morebatchflag']?.toString() ?? '',
              'validflag': prod['validflag']?.toString() ?? '',
            };
            _computeAmts(newItem);
            // unshift 到列表首位（新增商品置顶显示）
            _detailList.insert(0, newItem);
          });
          Toast.show('扫描添加成功');
        }
        _focusAfterScan(returnFocusNode);
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
      if (returnFocusNode != null) {
        returnFocusNode.requestFocus();
      } else {
        _scanFocusNode.requestFocus();
      }
      // 聚焦后隐藏软键盘（PDA 扫码枪不需要软键盘）
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  // ── 多批次选择 ──
  /// 多批次商品：跳转多选批次页，确认后删除该商品旧行并按批次生成新行
  /// （对齐 lxAss preOrderEdit onSelectMultBatchPage + selectMultBatch 多选页）
  Future<void> _selectMultBatch(Map<String, dynamic> item) async {
    // 系统参数「盘点不管理批次」开启时，同一商品多批次库存已合并统一录入，不再进入批次选择
    // （对齐 lxAss goChosePc / proDetails chosePc 的 checkAllBatch 直接返回）
    if (_checkAllBatch) return;
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
      qtyType: 'checkqty',
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
        _computeAmts(obj);
        _detailList.add(obj);
      }
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

  // ── 选择机构（对齐 boss 项目 quickInventoryEdit.vue jumpPge('jg')）──
  Future<void> _selectStore() async {
    FocusScope.of(context).unfocus();
    final result = await SelectStorePage.show(context);
    if (result != null && mounted) {
      setState(() {
        _bsid = result['storeid']?.toString();
        _storename = result['storename']?.toString();
        // 切换机构时清空仓库和明细
        _counterid = null;
        _countername = null;
        _detailList = [];
      });
    }
  }

  // ── 选择仓库（对齐 boss 项目 quickInventoryEdit.vue jumpPge('ck')）──
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
        // 切换仓库时清空明细
        _detailList = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _isSigned;
    final page = Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleSpacing: 0,
          leadingWidth: 40,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
              onPressed: _onBackPressed),
          title: Text(_isEdit ? '修改快速盘点' : '新增快速盘点',
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
                                                                : const Color(0xFFD54B5A))))
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
                          if (_isEdit &&
                              (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty))
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
                                          border: Border.all(color: const Color(0xFFEEEEEE))),
                                      child: Column(children: [
                                        _buildSelectRow(
                                            label: '盘点机构',
                                            value: _storename ?? '',
                                            onTap: disabled ? null : _selectStore,
                                            required: true),
                                        _buildDivider(),
                                        _buildSelectRow(
                                            label: '盘点仓库',
                                            value: _countername ?? '',
                                            onTap: disabled ? null : _selectWarehouse,
                                            required: true),
                                        _buildDivider(),
                                        _buildInputRow(
                                            label: '备注',
                                            controller: _remarkCtrl,
                                            disabled: disabled),
                                        _buildDivider(),
                                        _buildAttachButton(),
                                      ])))),
                          // ---- 粘性表头：扫描框 + 商品明细标题/操作按钮（滚到此处后固定） ----
                          SliverPersistentHeader(
                              pinned: true, delegate: _QuickcheckStickyHeaderDelegate(state: this)),
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
                      ))),
            ]),
      bottomNavigationBar: _isSelectMode
          ? _buildBatchDeleteBar()
          : Container(
              padding: EdgeInsets.only(
                  left: 16, right: 16, top: 10, bottom: MediaQuery.of(context).padding.bottom + 12),
              decoration: const BoxDecoration(
                  color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_detailList.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                          '盘点数量：${MathUtils.formatDecimal(1, _totalCheckQty)}，共 ${_detailList.length} 项',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
                Row(children: [
                  if (_isEdit && _isSigned) ...[
                    Expanded(
                        child: GestureDetector(
                            onTap: _submitAction != _QCAction.none ? null : _print,
                            child: Container(
                                height: 42,
                                decoration: BoxDecoration(
                                    color: const Color(0xFF006EFF),
                                    borderRadius: BorderRadius.circular(6)),
                                alignment: Alignment.center,
                                child: _submitAction == _QCAction.print
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Text('打印',
                                        style: TextStyle(fontSize: 15, color: Colors.white)))))
                  ] else if (_isEdit && !_isSigned) ...[
                    // “更多”按钮（删除/打印）- reviewsignflag != 2 && bolHandleTT
                    if (!_isWithdrawPending && _bolHandleTT) ...[
                      Expanded(
                          child: GestureDetector(
                              onTap: _submitAction != _QCAction.none ? null : _showMoreMenu,
                              child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFFCCCCCC)),
                                      borderRadius: BorderRadius.circular(6)),
                                  alignment: Alignment.center,
                                  child: const Text('更多',
                                      style: TextStyle(fontSize: 15, color: Color(0xFF333333)))))),
                    ],
                    // 保存/审核按钮 - signflag!=2 && reviewsignflag!=2 && (bolHandleTT || (审批流>0 && bolHandleT))
                    if (!_isRejected &&
                        !_isWithdrawPending &&
                        (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT))) ...[
                      const SizedBox(width: 10),
                      Expanded(
                          child: GestureDetector(
                              onTap: _submitAction != _QCAction.none ? null : () => _save(),
                              child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF006EFF),
                                      borderRadius: BorderRadius.circular(6)),
                                  alignment: Alignment.center,
                                  child: _submitAction == _QCAction.save
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
                              onTap: _submitAction != _QCAction.none
                                  ? null
                                  : () => _save(doSign: true),
                              child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF00A870),
                                      borderRadius: BorderRadius.circular(6)),
                                  alignment: Alignment.center,
                                  child: _submitAction == _QCAction.sign
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
                              onTap: _submitAction != _QCAction.none ? null : _restsign,
                              child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFFF9900),
                                      borderRadius: BorderRadius.circular(6)),
                                  alignment: Alignment.center,
                                  child: _submitAction == _QCAction.withdraw
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
                            onTap: _submitAction != _QCAction.none ? null : () => _save(),
                            child: Container(
                                height: 42,
                                decoration: BoxDecoration(
                                    color: const Color(0xFF006EFF),
                                    borderRadius: BorderRadius.circular(6)),
                                alignment: Alignment.center,
                                child: _submitAction == _QCAction.save
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
                              onTap: _submitAction != _QCAction.none
                                  ? null
                                  : () => _save(doSign: true),
                              child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF00A870),
                                      borderRadius: BorderRadius.circular(6)),
                                  alignment: Alignment.center,
                                  child: _submitAction == _QCAction.sign
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
              ])),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: page,
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
            child: Row(children: [
              // 星号固定占位，文字始终从同一起点对齐
              SizedBox(
                width: 8,
                child: required
                    ? const Text('*', style: TextStyle(fontSize: 14, color: Color(0xFFD54B5A)))
                    : null,
              ),
              SizedBox(
                width: 64,
                child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
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
          menuid: '081001',
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
                      fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500))),
          const SizedBox(width: 8),
          Expanded(
              child: Row(children: [
            const Icon(Icons.attach_file, size: 16, color: Color(0xFF006EFF)),
            const SizedBox(width: 4),
            Text('附件(${_fileLists.length})',
                style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFFC0C4CC)),
          ])),
        ]),
      ),
    );
  }

  /// 扫描框始终渲染（粘性表头固定展示，无红外扫码设置项）
  bool get _showScanInput => true;

  /// 明细编辑弹窗确认关闭后焦点“落空”时，将焦点恢复到红外扫描框，支持连续扫码；
  /// 焦点已落到其他输入框（用户主动点按）时不干预；弹窗收尾动画中最多重试 30 帧再评估
  void _returnFocusToScanIfIdle([int retryFrame = 0]) {
    if (!_showScanInput) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showScanInput) return;
      // 弹窗/其他页面覆盖中（商品详情弹窗、选品页等）不抢焦点；收尾动画中重试等待
      if (ModalRoute.of(context)?.isCurrent != true) {
        if (retryFrame < 30) _returnFocusToScanIfIdle(retryFrame + 1);
        return;
      }
      final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
      // 焦点已在某个具体控件上（其他输入框或扫描框自身）：不干预
      if (primaryFocus != null && primaryFocus is! FocusScopeNode) return;
      _scanFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  /// 商品详情弹窗（对齐采购入库/预盘单详情抽屉样式 + boss 项目 quickInven proDetails 行为）
  /// 新增/修改时可编辑盘点数量和批次；已审核时为只读
  void _showProductDetail(Map<String, dynamic> item, int index) {
    final disabled = _isSigned;
    final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
    // 单位/规格（可在弹窗内切换，确认后才写回明细行，取消不生效；对齐 lxAss quickInventoryEdit unitcanselect）
    final draft = Map<String, dynamic>.from(item);
    // 记录主规格：选包装单位后规格回退（对齐 lxAss proDetails.vue openFn sizeRevert）
    SelectUnitSizeSheet.initMainSize(draft);
    var unit = item['unit']?.toString() ?? '';
    var size = item['size']?.toString() ?? '';
    var barcode = item['barcode']?.toString() ?? item['selfbarcode']?.toString() ?? '';
    var saleprice =
        double.tryParse(item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '') ?? 0;
    var costprice = double.tryParse(item['costprice']?.toString() ?? '') ?? 0;
    // 现库存展示口径：不管理批次取商品总库存 allstockqty，否则取批次库存 stockqty
    var stockqty = _stockQtyOf(draft);
    var shelves = item['shelves']?.toString() ?? '';
    final morebatchflag = item['morebatchflag']?.toString() ?? '';
    final validflag = item['validflag']?.toString() ?? '';
    // 多批次商品：批次行点击可主动跳转多批次页（对齐 lxAss chosePc(isManual=true)：morebatchflag==1 即可）
    final isMultBatch = morebatchflag == '1';
    // validflag==1：数量入口为强制多批次（箭头跳转，非输入框；对齐 lxAss proDetails 数量可点击条件）
    // 系统参数「盘点不管理批次」开启时批次已合并，数量直接输入不再跳转批次页
    final isForceMultBatch = morebatchflag == '1' && validflag == '1' && !_checkAllBatch;
    // 批次相关配置项（批次/生产日期/有效日期）显隐：不管理批次时整块隐藏（对齐 lxAss myParam）
    final showBatch = !_checkAllBatch;

    double editCheckqty = double.tryParse(item['checkqty']?.toString() ?? '') ?? 0;
    String editBatchno = item['batchno']?.toString() ?? '';
    String editBirthdate = _formatBatchDate(item['birthdate']);
    String editValiddate = _formatBatchDate(item['validdate']);
    String editSupid = item['supid']?.toString() ?? '';
    String editRemark = item['remark']?.toString() ?? '';

    final checkqtyCtrl = TextEditingController(
      text: MathUtils.formatDecimal(1, editCheckqty),
    );
    final checkqtyFocus = FocusNode();
    checkqtyFocus.addListener(() {
      if (checkqtyFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (checkqtyCtrl.text.isNotEmpty) {
            checkqtyCtrl.selection = TextSelection(
              baseOffset: 0,
              extentOffset: checkqtyCtrl.text.length,
            );
          }
        });
      }
    });

    final remarkCtrl = TextEditingController(text: editRemark);
    // 批次输入框（对齐 lxAss proDetails manualBatchInput：快速盘点单批次放开手动输入，箭头仍保留选择入口）
    final batchCtrl = TextEditingController(text: editBatchno);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        // 键盘弹起时弹窗整体上移，避免输入框被键盘遮挡
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
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
                        const Expanded(
                          child: Text('商品详情',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
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
                                      style:
                                          const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text('零售价：¥${MathUtils.formatDecimal(2, saleprice)}',
                                        style: const TextStyle(
                                            fontSize: 13, color: Color(0xFF6B7280))),
                                    const SizedBox(width: 16),
                                    Text('成本价：¥${MathUtils.formatDecimal(2, costprice)}',
                                        style: const TextStyle(
                                            fontSize: 13, color: Color(0xFF6B7280))),
                                  ],
                                ),
                                if (shelves.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('货架号：$shelves',
                                      style:
                                          const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                                ],
                                if (size.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('规格：$size',
                                      style:
                                          const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                                ],
                                const SizedBox(height: 4),
                                Text('现库存：${MathUtils.formatDecimal(1, stockqty)}',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // ── 单位（有包装单位可选，对齐 lxAss proDetails.vue unitCanSelect） ──
                          if (!disabled && SelectUnitSizeSheet.canSelectUnit(draft))
                            _buildDetailSelectField(
                              label: '单位',
                              value: unit,
                              onTap: () async {
                                final result = await SelectUnitSizeSheet.show(
                                  ctx,
                                  type: 'unit',
                                  item: draft,
                                  bsid: _bsid ?? '',
                                  counterid: _counterid ?? '',
                                );
                                if (result == null) return;
                                await SelectUnitSizeSheet.apply(draft,
                                    type: 'unit',
                                    result: result,
                                    bsid: _bsid ?? '',
                                    counterid: _counterid ?? '',
                                    // 库存回写口径：不管理批次写商品总库存 allstockqty，否则写批次库存 stockqty
                                    stockAllBatch: _checkAllBatch);
                                if (!ctx.mounted) return;
                                setDialogState(() {
                                  unit = draft['unit']?.toString() ?? unit;
                                  size = draft['size']?.toString() ?? size;
                                  barcode = draft['barcode']?.toString() ?? barcode;
                                  shelves = draft['shelves']?.toString() ?? shelves;
                                  saleprice = double.tryParse(draft['saleprice']?.toString() ?? '') ??
                                      saleprice;
                                  costprice = double.tryParse(draft['costprice']?.toString() ?? '') ??
                                      costprice;
                                  stockqty = _stockQtyOf(draft);
                                });
                              },
                            )
                          else
                            _buildDetailReadonlyField(label: '单位', value: unit),
                          _buildDetailDivider(),
                          // ── 规格（有规格且未选包装单位可选，对齐 lxAss proDetails.vue sizeCanSelect） ──
                          if (!disabled && SelectUnitSizeSheet.canSelectSize(draft))
                            _buildDetailSelectField(
                              label: '规格',
                              value: size,
                              onTap: () async {
                                final result = await SelectUnitSizeSheet.show(
                                  ctx,
                                  type: 'size',
                                  item: draft,
                                  bsid: _bsid ?? '',
                                  counterid: _counterid ?? '',
                                );
                                if (result == null) return;
                                await SelectUnitSizeSheet.apply(draft,
                                    type: 'size',
                                    result: result,
                                    bsid: _bsid ?? '',
                                    counterid: _counterid ?? '',
                                    // 库存回写口径：不管理批次写商品总库存 allstockqty，否则写批次库存 stockqty
                                    stockAllBatch: _checkAllBatch);
                                if (!ctx.mounted) return;
                                setDialogState(() {
                                  size = draft['size']?.toString() ?? size;
                                  barcode = draft['barcode']?.toString() ?? barcode;
                                  saleprice = double.tryParse(draft['saleprice']?.toString() ?? '') ??
                                      saleprice;
                                  costprice = double.tryParse(draft['costprice']?.toString() ?? '') ??
                                      costprice;
                                  stockqty = _stockQtyOf(draft);
                                });
                              },
                            )
                          else
                            _buildDetailReadonlyField(label: '规格', value: size),
                          if (showBatch) _buildDetailDivider(),
                          // ── 批次（可手动输入，右侧箭头打开批次选择；对齐 lxAss proDetails manualBatchInput） ──
                          // 系统参数「盘点不管理批次」开启时整块隐藏（对齐 lxAss myParam）
                          if (showBatch && disabled)
                            _buildDetailReadonlyField(
                                label: '批次', value: editBatchno.isNotEmpty ? editBatchno : '-')
                          else if (showBatch)
                            _buildDetailBatchInputField(
                              label: '批次',
                              controller: batchCtrl,
                              onChanged: (v) => setDialogState(() => editBatchno = v),
                              onTapChoose: () async {
                                final productid = item['productid']?.toString() ??
                                    item['prodid']?.toString() ??
                                    '';
                                if (productid.isEmpty) {
                                  Toast.show('商品信息异常');
                                  return;
                                }
                                if (isMultBatch) {
                                  // 多批次商品（validflag==0 亦可主动选择）：关闭弹窗跳转多选批次页（对齐 lxAss chosePc(isManual)）
                                  // 跳转前同步弹窗当前编辑值（手动输入的批次/日期不能丢失）
                                  item['batchno'] = editBatchno;
                                  item['birthdate'] = editBirthdate;
                                  item['validdate'] = editValiddate;
                                  item['checkqty'] = editCheckqty;
                                  item['remark'] = editRemark;
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
                                    batchCtrl.text = editBatchno;
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
                          _buildDetailDivider(),
                          // ── 盘点数量 ──
                          if (disabled)
                            _buildDetailReadonlyField(
                                label: '盘点数量', value: MathUtils.formatDecimal(1, editCheckqty))
                          else if (isForceMultBatch)
                            // 多批次商品（validflag==1）：数量只读展示，点击跳转多选批次页（对齐 lxAss proDetails 数量可点击）
                            _buildDetailSelectField(
                              label: '盘点数量',
                              value: MathUtils.formatDecimal(1, editCheckqty),
                              onTap: () async {
                                item['batchno'] = editBatchno;
                                item['birthdate'] = editBirthdate;
                                item['validdate'] = editValiddate;
                                item['checkqty'] = editCheckqty;
                                item['remark'] = editRemark;
                                Navigator.pop(ctx);
                                await _selectMultBatch(item);
                              },
                            )
                          else
                            _buildDetailFormField(
                              label: '盘点数量',
                              controller: checkqtyCtrl,
                              focusNode: checkqtyFocus,
                              isDecimal: true,
                              onChanged: (v) {
                                final val = double.tryParse(v) ?? 0;
                                setDialogState(() => editCheckqty = val);
                              },
                            ),
                          _buildDetailDivider(),
                          // ── 盈亏数量（实时计算，只读） ──
                          _buildDetailReadonlyField(
                            label: '盈亏数量',
                            value: MathUtils.formatDecimal(1, editCheckqty - stockqty),
                            valueColor: (editCheckqty - stockqty) >= 0
                                ? const Color(0xFF00A870)
                                : const Color(0xFFD54B5A),
                          ),
                          if (showBatch) _buildDetailDivider(),
                          // ── 生产日期（可点击选择，对齐 lxAss proDetails openCalendar('birthdate')） ──
                          if (showBatch && disabled)
                            _buildDetailReadonlyField(
                                label: '生产日期',
                                value: editBirthdate.isNotEmpty ? editBirthdate : '-')
                          else if (showBatch)
                            _buildDetailSelectField(
                              label: '生产日期',
                              value: editBirthdate,
                              onTap: () async {
                                final picked = await _pickDetailDate(ctx, editBirthdate);
                                if (picked == null || !ctx.mounted) return;
                                setDialogState(() {
                                  editBirthdate = picked;
                                  // 保质期商品：生产日期 + 保质天数自动算出有效日期（对齐 lxAss birthdateConfirm）
                                  final linked = _calcLinkedDate(picked, item);
                                  if (linked.isNotEmpty) editValiddate = linked;
                                });
                              },
                            ),
                          if (showBatch) _buildDetailDivider(),
                          // ── 有效日期（可点击选择，对齐 lxAss proDetails openCalendar('validdate')） ──
                          if (showBatch && disabled)
                            _buildDetailReadonlyField(
                                label: '有效日期',
                                value: editValiddate.isNotEmpty ? editValiddate : '-')
                          else if (showBatch)
                            _buildDetailSelectField(
                              label: '有效日期',
                              value: editValiddate,
                              onTap: () async {
                                final picked = await _pickDetailDate(ctx, editValiddate);
                                if (picked == null || !ctx.mounted) return;
                                setDialogState(() => editValiddate = picked);
                              },
                            ),
                          _buildDetailDivider(),
                          // ── 备注 ──
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
                                      final row = _detailList[index];
                                      // 单位/规格切换结果写回明细行（对齐 lxAss detailConfirm：
                                      // detaillist[index] = item，连同零售价/成本价/库存/条码一起覆盖）
                                      for (final key in const [
                                        'unit',
                                        'unitonlyid',
                                        'defunit',
                                        'defunitid',
                                        'size',
                                        'sizeonlyid',
                                        'defsize',
                                        'defsizeid',
                                        'packagenum',
                                        'sellprice',
                                        'saleprice',
                                        'costprice',
                                        'stockqty',
                                        // 商品总库存：不管理批次时切换单位/规格按总库存回写
                                        'allstockqty',
                                        'shelves',
                                        'barcode',
                                        'code',
                                      ]) {
                                        if (draft.containsKey(key)) row[key] = draft[key];
                                      }
                                      row['checkqty'] = editCheckqty;
                                      row['batchno'] = editBatchno;
                                      row['birthdate'] = editBirthdate;
                                      row['validdate'] = editValiddate;
                                      row['supid'] = editSupid;
                                      row['remark'] = editRemark;
                                      _computeAmts(row);
                                    });
                                    // 弹窗确认编辑后评估恢复扫描框焦点（连续扫码）
                                    _returnFocusToScanIfIdle();
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
      ),
    );
  }

  /// 表单输入行（对齐采购入库/预盘单 _buildFormField）
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

  static Widget _buildDetailDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));

  /// 批次输入行：可手动输入批次号，右侧箭头打开批次选择（对齐 lxAss proDetails manualBatchInput）
  static Widget _buildDetailBatchInputField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required VoidCallback onTapChoose,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
              keyboardType: TextInputType.text,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: '请输入',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
              ),
            ),
          ),
          GestureDetector(
            onTap: onTapChoose,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.chevron_right, size: 20, color: Color(0xFFD1D5DB)),
            ),
          ),
        ],
      ),
    );
  }

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

  /// 日期选择弹窗（年/月/日 滚轮，对齐库存单据 otherout _pickDetailDate）
  Future<String?> _pickDetailDate(BuildContext ctx, String currentValue) async {
    DateTime initial;
    try {
      initial = currentValue.isNotEmpty ? DateTime.parse(currentValue) : DateTime.now();
    } catch (_) {
      initial = DateTime.now();
    }
    DateTime tempDate = initial;
    final date = await showModalBottomSheet<DateTime>(
      context: ctx,
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
                        child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280)))),
                    const Spacer(),
                    TextButton(
                        onPressed: () => Navigator.pop(c, tempDate),
                        child: const Text('确定', style: TextStyle(color: Color(0xFF006EFF)))),
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
                            initialItem: (tempDate.year - 2020).clamp(0, 29)),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) {
                          tempDate = DateTime(2020 + i, tempDate.month, tempDate.day);
                        },
                        children: List.generate(
                            30,
                            (i) => Center(
                                child: Text('${2020 + i}年',
                                    style:
                                        const TextStyle(fontSize: 16, color: Color(0xFF333333))))),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController:
                            FixedExtentScrollController(initialItem: tempDate.month - 1),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) {
                          tempDate = DateTime(tempDate.year, i + 1, tempDate.day);
                        },
                        children: List.generate(
                            12,
                            (i) => Center(
                                child: Text('${i + 1}月',
                                    style:
                                        const TextStyle(fontSize: 16, color: Color(0xFF333333))))),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController:
                            FixedExtentScrollController(initialItem: tempDate.day - 1),
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
                                    style:
                                        const TextStyle(fontSize: 16, color: Color(0xFF333333))))),
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

  /// 生产日期 + 保质天数（validday）自动算出有效日期（对齐 lxAss proDetails birthdateConfirm）
  /// 非保质期商品（validflag != 1）、无保质天数或日期非法时返回空串（不覆盖有效日期）
  static String _calcLinkedDate(String baseDate, Map<String, dynamic> src) {
    if (src['validflag']?.toString() != '1') return '';
    final days = num.tryParse(src['validday']?.toString() ?? '') ?? 0;
    if (days <= 0) return '';
    final d = DateTime.tryParse(baseDate);
    if (d == null) return '';
    final v = d.add(Duration(days: days.toInt()));
    return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
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
            // 扫描输入框（仅非已审核时显示）
            if (!disabled) ...[
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
                        // 盘点仓库等前置校验统一在 _handleScannedBarcode 内处理。
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
    final validflag = item['validflag']?.toString() ?? '';
    final mbillid = item['mbillid']?.toString() ?? '';
    final addbatchflag = item['addbatchflag']?.toString() ?? '';
    // 多批次商品（validflag==1）且未合并批次时显示"请选择批次"（对齐 lxAss preOrderEdit 列表项）
    // 系统参数「盘点不管理批次」开启时不显示该入口（批次已合并，库存取商品总库存）
    final showMultBatchLink = !_checkAllBatch &&
        morebatchflag == '1' &&
        validflag == '1' &&
        mbillid.isEmpty &&
        addbatchflag.isEmpty;
    final saleprice =
        double.tryParse(item['saleprice']?.toString() ?? item['sellprice']?.toString() ?? '') ?? 0;
    // 现库存展示口径：不管理批次取商品总库存 allstockqty，否则取批次库存 stockqty
    final stockqty = _stockQtyOf(item);
    final checkqty = double.tryParse(item['checkqty']?.toString() ?? '') ?? 0;
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
                      // 系统参数「盘点不管理批次」开启时隐藏批次显示（对齐 lxAss `v-if="!isCheckAllBatch"`）
                      child: _checkAllBatch
                          ? const SizedBox.shrink()
                          : Text('批次：$batchno',
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
                  Text('盘点数量：${MathUtils.formatDecimal(1, checkqty)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ]),
                const SizedBox(height: 4),
                Text('盈亏数量：${MathUtils.formatDecimal(1, qty)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: qty >= 0 ? const Color(0xFF00A870) : const Color(0xFFD54B5A))),
              ])),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
        ],
      ),
    );
  }
}

/// 快速盘点粘性表头代理
class _QuickcheckStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _QuickcheckStickyHeaderDelegate({required this.state});
  final _InventoryQuickcheckAddPageState state;
  @override
  double get minExtent => state._isSigned
      ? _InventoryQuickcheckAddPageState._stickySignedExtent
      : _InventoryQuickcheckAddPageState._stickyMinExtent;
  @override
  double get maxExtent => state._isSigned
      ? _InventoryQuickcheckAddPageState._stickySignedExtent
      : _InventoryQuickcheckAddPageState._stickyMaxExtent;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader(maxExtent);
  }

  @override
  bool shouldRebuild(covariant _QuickcheckStickyHeaderDelegate oldDelegate) => true;
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
