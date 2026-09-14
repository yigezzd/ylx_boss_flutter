import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/models/scan_settings.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/in_price_height_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/not_master_product_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/load_image.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:flutter_deer/widgets/select_field_item.dart';
import 'package:flutter_deer/widgets/voice_recognition_dialog.dart';
import 'package:sp_util/sp_util.dart';

enum _COAction { none, save, sign, delete, retsign, stop, withdraw, print }

/// 读取登录参数指定 key 的 int 值（对齐 Vue userStore().loginParamResp），
/// 缺失或解析异常时返回 0
int _loginParamInt(String key) {
  try {
    final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
    if (cfgStr.isEmpty) return 0;
    final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
    return int.tryParse(cfg[key]?.toString() ?? '0') ?? 0;
  } catch (_) {
    return 0;
  }
}

class PurchaseCgorderAddPage extends StatefulWidget {
  const PurchaseCgorderAddPage({super.key, this.billData});
  final Map<String, dynamic>? billData;

  @override
  State<PurchaseCgorderAddPage> createState() => _PurchaseCgorderAddPageState();
}

class _PurchaseCgorderAddPageState extends State<PurchaseCgorderAddPage>
    with LogPageMixin<PurchaseCgorderAddPage> {
  @override
  String get logPageName => _isEdit ? '采购订货详情' : '采购订货新增';

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _supController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _buyerController = TextEditingController();

  // ---- 红外扫描 ----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;

  // ---- 扫码设置 ----
  late ScanSettings _scanSettings;

  String? _supid;
  int? _storeid;
  String? _buyerid;
  String? _buyername;
  String? _storename;
  int? _storetype;

  _COAction _submitAction = _COAction.none;
  bool _detailLoading = false;
  bool _isTipNotMasterProduct = true;
  // 进价校验放行标记（对齐 Vue cgorder/edit.vue isTipInprice / isTipDoubleInprice，
  // 用户弹窗确认后置 false 防止重复弹出）
  bool _isTipInprice = true; // 入库价和档案价不同（cgProductPriceNotSellPriceFlag）
  bool _isTipDoubleInprice = true; // 进价达原进价两倍（cgInPriceHeightSellPriceFlag）

  // ---- 批量选择 ----
  bool _isSelectMode = false;
  Set<int> _selectedIndices = {};

  Map<String, dynamic>? _billData;
  String? _newBillid;
  List<Map<String, dynamic>> _fileLists = [];

  // ---- 多级审批 ----
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  bool _billSign = true;
  String _userCode = '';
  String _userid = '';

  bool get _isEdit =>
      (_newBillid != null && _newBillid!.isNotEmpty) ||
      (widget.billData != null && (widget.billData!['billid']?.toString().isNotEmpty ?? false));
  bool get _isSigned => _billData?['signflag']?.toString() == '1';
  bool get _isRejected => _billData?['signflag']?.toString() == '2';

  // ---- 多级审批权限计算（对齐 Vue computed） ----
  bool get _isAdmin => _userCode == '1001';

  /// 表单是否可编辑
  bool get _bolHandle {
    final signflag = int.tryParse(_billData?['signflag']?.toString() ?? '0') ?? 0;
    if (signflag == 1) return false;
    if (_reviewFlowUsers.isEmpty) return true;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return !(firstIndex > 1);
  }

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

  final List<_DetailRow> _items = [];

  @override
  void initState() {
    super.initState();
    // 读取扫码设置
    _scanSettings = ScanSettings.fromSp();
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          final scanCode = _scanController.text.trim();
          debugPrint('[红外扫描] onKeyEvent Enter: "$scanCode"');
          if (scanCode.isNotEmpty) {
            _scanDebounceTimer?.cancel(); // Enter 命中，取消防抖
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
        // 兆底：确保键盘隐藏
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } else if (!_scanFocusNode.hasFocus) {
        _scanFieldFocused = false;
      }
    });
    // 扫码防抖兆底：PDA 扫码枪模拟键盘注入字符极快（<100ms），
    // 当文本停止变化 150ms 后自动触发查询（兆底 onKeyEvent 未触发的场景）
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

    // 加载当前登录用户信息（编辑/新增模式均需使用）
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
    logEnter();
  }

  void _loadNewModeDefaults() {
    _isTipNotMasterProduct = true;
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeid = _parseIntFlexible(storeMap, ['id', 'storeid', 'bsid']);
        _storename = storeMap['name']?.toString();
        _storetype = _parseIntFlexible(storeMap, ['storetype']);
        _storeController.text = storeMap['name']?.toString() ?? '';
      }
    } catch (e) {
      debugPrint('[订货新增] store 解析异常: $e');
    }
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _buyerid = userMap['userid']?.toString();
        _buyername = userMap['name']?.toString();
        _buyerController.text = userMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    // 新增模式：初始化审批签字按钮可见性
    if (!_isEdit) {
      _initSignUserBtn();
    }
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
    _supController.dispose();
    _remarkController.dispose();
    _storeController.dispose();
    _buyerController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  // =================== 编辑模式：加载单据详情 ===================
  void _loadDetail([Map<String, dynamic>? overrideParams]) {
    _isTipNotMasterProduct = true;
    setState(() => _detailLoading = true);
    final Map<String, dynamic> params =
        overrideParams ?? Map<String, dynamic>.from(widget.billData!);

    request(HttpApi.cgorderGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _supController.text = data['supname']?.toString() ?? '';
          _storeController.text = data['storename']?.toString() ?? '';
          _buyerController.text = data['buyername']?.toString() ?? '';
          _remarkController.text = data['remark']?.toString() ?? '';
          _supid = data['supid']?.toString();
          _storeid = _parseIntFlexible(data, ['bsid', 'storeid']);
          _storename = data['storename']?.toString();
          _storetype = _parseIntFlexible(data, ['storetype']);
          _buyerid = data['buyerid']?.toString();
          _buyername = data['buyername']?.toString();
          // 多级审批数据
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
          _fileLists = (data['fileLists'] as List? ?? [])
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            // 对齐 Vue getInfo handleProperty(item, undefined, true)：回显场景已保存价优先
            // （price || cgprice || 0），保护手动调价不被旧 cgprice 覆盖；已保存价为空/0 时
            // 兜底取最新采购价 cgprice
            final savedPrice = double.tryParse(c['price']?.toString() ?? '') ?? 0;
            final cgprice = double.tryParse(c['cgprice']?.toString() ?? '') ?? 0;
            final price = savedPrice != 0 ? savedPrice : cgprice;
            c['price'] = MathUtils.formatDecimalNum(2, price);
            final row = _DetailRow();
            row.prodid = c['prodid']?.toString() ?? c['productid']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            final qtyVal0 = double.tryParse(c['qty']?.toString() ?? '') ?? 0;
            row.qtyController.text = MathUtils.formatDecimal(1, qtyVal0);
            row.priceController.text = MathUtils.formatDecimal(2, price);
            final giftVal =
                double.tryParse(c['presentqty']?.toString() ?? c['giftqty']?.toString() ?? '') ?? 0;
            row.giftQtyController.text = MathUtils.formatDecimal(1, giftVal);
            // 对齐 Vue handleProperty：amt 始终由 qty*price 重算
            row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qtyVal0, price));
            row.remarkController.text = c['remark']?.toString() ?? '';
            // 计算件数 = 数量 / 包装数（对齐 Vue writeData jsqty formatDecimal(1,...)）
            final packagenum = double.tryParse(c['packagenum']?.toString() ?? '') ?? 1;
            row.jsQtyController.text =
                packagenum > 0 ? MathUtils.formatDecimal(1, qtyVal0 / packagenum) : '0';
            row.rawData = c;
            // 折扣率计算（对齐 Vue getInfo → handleProperty → jsGrossrate）
            _calcProfit(row);
            _items.add(row);
          }
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  // =================== 提交保存 ===================
  Future<void> _submit({bool isDraft = false}) async {
    // 权限校验
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('011303', showTip: false)) {
        Toast.show('你无权编辑采购订货，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('011302', showTip: false)) {
        Toast.show('你无权新增采购订货，请在后台修改权限');
        return;
      }
    }
    // 操作审计：提交保存
    logSave(_isEdit ? '保存修改' : (isDraft ? '存为草稿' : '保存单据'));

    if (!_isSigned) {
      if (_supid == null || _supid!.isEmpty) {
        Toast.show('请选择供应商');
        return;
      }
      if (_storeid == null) {
        Toast.show('请选择订货机构');
        return;
      }
    }

    if (!_isEdit) {
      if (!_formKey.currentState!.validate()) return;
    }

    final List<_DetailRow> submitItems;
    if (_isEdit) {
      submitItems = List.from(_items);
    } else {
      submitItems = _items
          .where(
              (row) => (row.prodid ?? '').isNotEmpty && row.nameController.text.trim().isNotEmpty)
          .toList();
    }

    if (submitItems.isEmpty) {
      Toast.show('请选择商品');
      return;
    }

    if (!_isEdit) {
      for (final row in submitItems) {
        final qty = double.tryParse(row.qtyController.text) ?? 0;
        final presentqty = double.tryParse(row.giftQtyController.text) ?? 0;
        if (qty == 0 && presentqty == 0) {
          Toast.show('请填写数量');
          return;
        }
      }
    }

    // 非供货资格商品校验（对齐 Vue cgNotMasterProductFlag）
    if (_isTipNotMasterProduct) {
      final cgFlag = getCgNotMasterProductFlag();
      if (cgFlag == 2 || cgFlag == 3) {
        final notMatchItems = submitItems.where((row) {
          final rowSupid = row.rawData?['supid']?.toString() ?? '';
          return rowSupid.isNotEmpty && rowSupid != _supid;
        }).toList();
        if (notMatchItems.isNotEmpty) {
          final names = notMatchItems
              .map((r) => r.nameController.text.trim())
              .where((n) => n.isNotEmpty)
              .toList();
          showNotMasterProductDialog(context, flag: cgFlag, names: names).then((result) {
            if (result == NotMasterProductResult.cancel) return;
            if (result == NotMasterProductResult.removeThenSave) {
              // 删除非供货资格的商品后保存
              setState(() {
                for (final row in notMatchItems) {
                  _items.remove(row);
                  row.dispose();
                }
              });
            }
            // 对齐 Vue：弹窗确认后置 false 防止重复弹出
            _isTipNotMasterProduct = false;
            _submit(isDraft: isDraft);
          });
          return;
        }
      }
    }

    // 进价不一致 / 进价两倍差校验（对齐 Vue cgorder/edit.vue save：
    // 先校验入库价和档案价不同 cgProductPriceNotSellPriceFlag，
    // 再校验进价高于原进价两倍 cgInPriceHeightSellPriceFlag）
    final diffFlag = getCgProductPriceNotSellPriceFlag();
    final doubleFlag = getCgInPriceHeightSellPriceFlag();
    if ((_isTipInprice && (diffFlag == 2 || diffFlag == 3)) ||
        (_isTipDoubleInprice && (doubleFlag == 2 || doubleFlag == 3))) {
      // 构造校验数据：商品ID/现进价/原进价(inprice 无则 oldprice)/商品名称
      final checkItems = submitItems.map((row) {
        final raw = row.rawData ?? {};
        return <String, dynamic>{
          'prodid': row.prodid ?? '',
          'productid': row.prodid ?? '',
          'productname': row.nameController.text.trim(),
          'price': row.priceController.text.trim(),
          'inprice': raw['inprice'],
          'oldprice': raw['oldprice'],
        };
      }).toList();
      final outcome = await checkInPriceHeight(
        context,
        checkItems,
        tipDoubleInprice: _isTipDoubleInprice,
        tipInprice: _isTipInprice,
        diffFirst: true,
      );
      if (!mounted) return;
      if (outcome.result == InPriceHeightResult.cancel) return;
      if (outcome.result == InPriceHeightResult.continueSave) {
        // 对齐 Vue handleInPriceHeightConfirm：确认后仅置触发类型的放行标记，重新走保存流程
        if (outcome.firedType == kInPriceHeightType) {
          _isTipDoubleInprice = false;
        } else {
          _isTipInprice = false;
        }
        _submit(isDraft: isDraft);
        return;
      }
    }

    setState(() => _submitAction = _COAction.save);

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
      params['fileLists'] = _fileLists;
    } else {
      // 新增模式默认参数（对齐后台 cgorder/edit.vue formDefault：
      // name/startdate/enddate/signflag/fileLists）
      params = {
        'name': '',
        'startdate': '',
        'enddate': '',
        'signflag': 0,
        'fileLists': _fileLists,
      };
    }

    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt);
    params['detaillist'] = detaillist;
    params['remark'] = _remarkController.text.trim();
    params['supname'] = _supController.text.trim();
    params['supid'] = _supid ?? '';
    params['bsid'] = _storeid ?? '';
    params['storename'] = _storename ?? '';
    params['storetype'] = _storetype ?? '';
    params['buyerid'] = _buyerid ?? '';
    params['buyername'] = _buyername ?? '';

    request(HttpApi.cgorderSave, params).then((result) {
      if (!mounted) return;
      // 对齐 Vue save finally：请求完成后重置进价校验放行标记
      _isTipInprice = true;
      _isTipDoubleInprice = true;
      Toast.show(result['retmsg']?.toString() ?? '保存成功');
      final retData = result['data'];
      if (retData is Map<String, dynamic>) {
        if (_isEdit) {
          _loadDetail(Map<String, dynamic>.from(retData));
        } else {
          final String? newBillid = retData['billid']?.toString();
          if (newBillid != null && newBillid.isNotEmpty) {
            setState(() => _newBillid = newBillid);
            _loadDetail(Map<String, dynamic>.from(retData));
          } else {
            Navigator.pop(context, true);
          }
        }
      } else {
        if (!_isEdit) Navigator.pop(context, true);
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 审核（已保存的单据直接审核，多级审批时弹出审批弹窗）
  Future<void> _sign() async {
    if (!PermissionUtils.checkPermission('011305', showTip: false)) {
      Toast.show('你无权审核采购订货，请在后台修改权限');
      return;
    }
    if (_billData == null) return;

    // 多级审批：弹出审批操作弹窗
    if (_reviewFlowUsers.isNotEmpty) {
      final approvalResult = await _showApprovalDialog();
      if (approvalResult == null || !mounted) return;
      _billData?['reviewsignflag'] = approvalResult['reviewsignflag'];
      _billData?['reviewremark'] = approvalResult['reviewremark'];
      _doSign();
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
    _doSign();
  }

  /// 反审核
  Future<void> _retsign() async {
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

    setState(() => _submitAction = _COAction.retsign);
    // 构造完整反审核参数（对齐 Vue fsignFn 发送 query.value 完整单据对象）：
    // 对后端强依赖的关键字段做兜底补充，避免写入审批流表时出现 NULL
    final params = Map<String, dynamic>.from(_billData!);
    final billdate = params['billdate']?.toString().trim() ?? '';
    if (billdate.isEmpty) {
      final now = DateTime.now();
      params['billdate'] =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
    if (params['billid'] == null || params['billid'].toString().isEmpty) {
      params['billid'] = _newBillid ?? '';
    }
    if (params['billtypeid'] == null || params['billtypeid'].toString().isEmpty) {
      params['billtypeid'] = '0502';
    }
    final dl = params['detaillist'];
    if (dl is! List || dl.isEmpty) {
      params['detaillist'] = _buildSubmitDetailList();
    }
    request(HttpApi.cgorderRetsign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '反审成功');
      setState(() {
        _reviewFlowUsers = [];
        _reviewBillFlows = [];
      });
      _loadDetail(params);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 删除单据
  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('011304', showTip: false)) {
      Toast.show('你无权删除采购订货，请在后台修改权限');
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

    setState(() => _submitAction = _COAction.delete);
    request(HttpApi.cgorderDelBill, _billData).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 终止单据
  Future<void> _stopBill() async {
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定终止吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _COAction.stop);
    final params = Map<String, dynamic>.from(_billData!);
    params['detaillist'] = <dynamic>[];
    request(HttpApi.cgorderStop, params).then((result) {
      if (!mounted) return;
      Toast.show('终止成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 打印单据
  Future<void> _print() async {
    if (_billData == null) return;
    final printParams = {
      'menuid': '050201',
      'data': _billData,
    };
    setState(() => _submitAction = _COAction.print);
    request(HttpApi.cgorderPrint, printParams).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  // =================== 多级审批 ===================

  /// 新单据时，根据机构(bsid)查询是否需要审批签字
  void _initSignUserBtn() {
    if (_isAdmin) return;
    if (!_isEdit && _storeid != null) {
      request(HttpApi.reviewTypeConfigGetNewBillSignUser, {
        'billtypeid': '0502',
        'bsid': _storeid,
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

  /// 撤回操作（signflag==2 已驳回状态）
  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('011306', showTip: false)) {
      Toast.show('你无权反审核采购订货，请在后台修改权限');
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
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _COAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.cgorderSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
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

  /// 保存并审核（新增模式）
  void _saveAndSign() {
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请选择供应商');
      return;
    }
    if (_storeid == null) {
      Toast.show('请选择订货机构');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final submitItems = _items
        .where((row) => (row.prodid ?? '').isNotEmpty && row.nameController.text.trim().isNotEmpty)
        .toList();
    if (submitItems.isEmpty) {
      Toast.show('请选择商品');
      return;
    }
    for (final row in submitItems) {
      final qty = double.tryParse(row.qtyController.text) ?? 0;
      final presentqty = double.tryParse(row.giftQtyController.text) ?? 0;
      if (qty == 0 && presentqty == 0) {
        Toast.show('请填写数量');
        return;
      }
    }

    setState(() => _submitAction = _COAction.save);
    final detaillist = _buildSubmitDetailList();
    double totalQty = 0;
    double totalAmt = 0;
    for (final item in detaillist) {
      totalQty = MathUtils.add(totalQty, double.tryParse(item['qty']?.toString() ?? '0') ?? 0);
      totalAmt = MathUtils.add(totalAmt, double.tryParse(item['amt']?.toString() ?? '0') ?? 0);
    }
    // 新增模式默认参数（对齐后台 cgorder/edit.vue formDefault：
    // name/startdate/enddate/signflag/fileLists）
    final params = <String, dynamic>{
      'name': '',
      'startdate': '',
      'enddate': '',
      'signflag': 0,
      'fileLists': _fileLists,
    };
    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt);
    params['detaillist'] = detaillist;
    params['remark'] = _remarkController.text.trim();
    params['supname'] = _supController.text.trim();
    params['supid'] = _supid ?? '';
    params['bsid'] = _storeid ?? '';
    params['storename'] = _storename ?? '';
    params['storetype'] = _storetype ?? '';
    params['buyerid'] = _buyerid ?? '';
    params['buyername'] = _buyername ?? '';

    request(HttpApi.cgorderSave, params).then((result) {
      if (!mounted) return;
      // 对齐 Vue save finally：请求完成后重置进价校验放行标记
      _isTipInprice = true;
      _isTipDoubleInprice = true;
      Toast.show(result['retmsg']?.toString() ?? '保存成功');
      final retData = result['data'];
      if (retData is Map<String, dynamic>) {
        final newBillid = retData['billid']?.toString();
        if (newBillid != null && newBillid.isNotEmpty) {
          setState(() {
            _newBillid = newBillid;
            _billData = retData;
          });
          // 保存成功后执行审核（多级审批流程）
          _doSignAfterSave(retData);
        } else {
          Toast.show('保存失败，无法审核');
        }
      } else {
        Toast.show('保存失败');
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 保存后执行审核（多级审批流程）
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

    // 多级审批：弹出审批弹窗
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

  /// 执行审核操作（对齐 Vue doSign）
  void _doSign([Map<String, dynamic>? data]) {
    final billData = data ?? _billData;
    if (billData == null) return;
    final params = Map<String, dynamic>.from(billData);
    params['signflag'] = 1;
    params['reviewremark'] = billData['reviewremark']?.toString() ?? '';
    // reviewsignflag: 2=撤回保持不变，0=驳回保持不变，其余设为1（通过）
    final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
    if (reviewsignflag != 2 && reviewsignflag != 0) {
      params['reviewsignflag'] = 1;
    }
    setState(() => _submitAction = _COAction.sign);
    request(HttpApi.cgorderSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  // =================== 批量选择 ===================
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

  bool get _isAllSelected {
    return _items.isNotEmpty && _selectedIndices.length == _items.length;
  }

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
        content: Text('确定删除选中的 $count 条明细？'),
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

  // =================== 语音识别 ===================
  Future<void> _voiceRecognition() async {
    if (_storeid == null) {
      Toast.show('请先选择订货机构');
      return;
    }
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
      return;
    }
    final result = await VoiceRecognitionDialog.show(context);
    if (result == null || result.isEmpty || !mounted) return;

    int matchCount = 0;
    final unmatched = <String>[];

    for (final item in result) {
      final name = item['name'] as String;
      try {
        final searchResult = await request(HttpApi.productGetList, {
          'keyword': name,
          'is_page': 1,
          'page': 1,
          'pagesize': 5,
          'stockflag': 1,
          'storeid': _storeid ?? '',
          'counterid': '',
          'cgpriceflag': 1,
          'billsupid': _supid ?? '',
          'itemstatusin': '1,2',
          'itemtypenot': '5,8',
        });
        if (!mounted) return;
        final data = searchResult['data'];
        final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
        if (list.isNotEmpty) {
          final prod = list.first as Map<String, dynamic>;
          setState(() {
            final qtyVal = double.tryParse((item['quantity'] ?? 1).toString()) ?? 1;
            final pn = double.tryParse(prod['packagenum']?.toString() ?? '') ?? 1;
            final row = _DetailRow()
              ..nameController.text =
                  prod['productname']?.toString() ?? prod['name']?.toString() ?? name
              ..qtyController.text = (item['quantity'] ?? 1).toString()
              ..priceController.text =
                  // 对齐 Vue handleProperty：选品场景最新采购价 cgprice 优先，
                  // 为空/0 时兜底语音解析价，再兜底档案价 price
                  ((double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0) != 0
                          ? prod['cgprice']
                          : (item['price'] ?? prod['price'] ?? 0))
                      .toString()
              ..prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? ''
              ..jsQtyController.text = pn > 0 ? (qtyVal / pn).toStringAsFixed(1) : '0'
              ..rawData = Map<String, dynamic>.from(prod);
            // 初始化金额（对齐 Vue handleProperty：amt = qty × price），
            // 与扫码新建行一致；仅靠消费端兜底会使 row.amt 长期为 null
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
    if (unmatched.isNotEmpty) {
      Toast.show('已匹配 $matchCount 项，未匹配：${unmatched.join("、")}');
    } else {
      Toast.show('已添加 $matchCount 项商品');
    }
  }

  // =================== 扫码 ===================

  /// 主扫码按钮：打开相机扫码页面
  Future<void> _scanBarcode() async {
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
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

  /// 处理扫码结果：若商品已存在则累加数量，否则新增行
  /// [returnFocusNode] 有值时，扫码完成后焦点回到该节点（用于红外扫描框连续扫码）
  void _handleScannedBarcode(String code, {FocusNode? returnFocusNode}) {
    if (code.trim().isEmpty) return;
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
      return;
    }

    // 尝试解析条码秤生成的重量码/金额码（采购订货特有功能）
    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;

    debugPrint(
        '[红外扫描] 开始查询条码: $code, searchCode=$searchCode, storeid=$_storeid, supid=$_supid, scaleType=${scaleInfo?.type}');

    final params = {
      'scancode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      'stockflag': 1,
      'storeid': _storeid ?? '',
      'counterid': '',
      'cgpriceflag': 1,
      'billsupid': _supid ?? '',
      'itemstatusin': '1,2',
      'itemtypenot': '5,8',
    };

    request(HttpApi.productGetList, params).then((result) {
      if (!mounted) return;
      debugPrint('[红外扫描] 接口返回: $result');
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      debugPrint('[红外扫描] 商品列表长度: ${list.length}');
      if (list.isNotEmpty) {
        // 自编码命中：仅一条 → 优先匹配自编码商品不跳转；多条 → 跳转选品页
        // 无自编码命中时：商品条码多条 → 跳转选品页；一条 → 优先匹配该条码商品
        final codeList = list.where((c) => (c['code']?.toString() ?? '') == searchCode).toList();
        final barcodeList =
            list.where((c) => (c['barcode']?.toString() ?? '') == searchCode).toList();
        final needJump = codeList.length >= 2 || (codeList.isEmpty && barcodeList.length >= 2);
        Map<String, dynamic>? primary;
        if (codeList.length == 1) {
          primary = codeList.first as Map<String, dynamic>;
        } else if (codeList.isEmpty && barcodeList.length == 1) {
          primary = barcodeList.first as Map<String, dynamic>;
        }
        if (needJump) {
          // 多条命中：跳转选品页（按扫码词过滤展示候选商品），用户选择后返回合并
          _selectProduct(initialKeyword: searchCode, returnFocusNode: returnFocusNode);
          return;
        }
        final prod = primary ?? list.first as Map<String, dynamic>;
        final String prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
        // 复合去重键对齐后台 ROW_KEYS：productid + unitonlyid + sizeonlyid
        final String unitonlyid = prod['unitonlyid']?.toString() ?? '';
        final String sizeonlyid = prod['sizeonlyid']?.toString() ?? '';

        // 根据条码秤类型计算数量
        double qtyDelta;
        if (scaleInfo?.type == 'weight') {
          qtyDelta = scaleInfo!.qty ?? 1;
        } else if (scaleInfo?.type == 'amount') {
          // 对齐 Vue handleProperty：cgprice 优先，为 0 时兜底 price
          final cgVal = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
          final price =
              cgVal != 0 ? cgVal : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
          qtyDelta = price > 0 ? (scaleInfo!.amount ?? 0) / price : 1;
        } else {
          qtyDelta = 1;
        }

        // 若同一商品（prodid + unitonlyid + sizeonlyid 复合键匹配，对齐后台 ROW_KEYS）已在明细中，累加数量
        // 同一商品的不同包装/规格视为不同行，可分别录入数量
        _DetailRow? targetRow;
        int? targetIndex;
        bool duplicated = false;
        if (prodid.isNotEmpty) {
          final existing = _items.cast<_DetailRow?>().firstWhere(
                (r) =>
                    r!.prodid == prodid &&
                    (r.rawData?['unitonlyid']?.toString() ?? '') == unitonlyid &&
                    (r.rawData?['sizeonlyid']?.toString() ?? '') == sizeonlyid,
                orElse: () => null,
              );
          if (existing != null) {
            if (_scanSettings.scanQtyMode == 0) {
              // 默认累加模式
              setState(() {
                final curQty = double.tryParse(existing.qtyController.text) ?? 0;
                final newQty = curQty + qtyDelta;
                existing.qtyController.text = newQty == newQty.toInt()
                    ? newQty.toInt().toString()
                    : newQty.toStringAsFixed(2);
                final pn = double.tryParse(existing.rawData?['packagenum']?.toString() ?? '') ?? 1;
                existing.jsQtyController.text = pn > 0 ? (newQty / pn).toStringAsFixed(1) : '0';
                // 扫码累加数量视为编辑数量（对齐 Vue writeData）：重置手动金额标记
                existing.amtManual = false;
                _recalcRow(existing);
              });
              Toast.show('扫描添加成功');
            }
            targetRow = existing;
            targetIndex = _items.indexOf(existing);
            duplicated = true;
          }
        }
        if (!duplicated) {
          // 对齐 Vue handleProperty（扫描 @confirm="handleProperty"）：
          // 最新采购价 cgprice 优先，为空/0 时兜底档案价 price
          final cgVal = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
          final price =
              cgVal != 0 ? cgVal : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
          final row = _DetailRow();
          row.prodid = prodid;
          row.nameController.text =
              prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
          row.qtyController.text = qtyDelta == qtyDelta.toInt()
              ? qtyDelta.toInt().toString()
              : qtyDelta.toStringAsFixed(2);
          row.priceController.text = price.toStringAsFixed(2);
          row.giftQtyController.text = '0';
          row.rawData = Map<String, dynamic>.from(prod);
          final pn = double.tryParse(prod['packagenum']?.toString() ?? '') ?? 1;
          final qtyVal = double.tryParse(row.qtyController.text) ?? 0;
          row.jsQtyController.text = pn > 0 ? (qtyVal / pn).toStringAsFixed(1) : '0';
          _recalcRow(row);
          setState(() {
            _items.insert(0, row);
          });
          if (_scanSettings.scanQtyMode == 0) {
            Toast.show('扫描添加成功');
          }
          targetRow = row;
          targetIndex = 0;
        }

        // 根据扫码设置决定后续行为
        if (_scanSettings.scanQtyMode == 1) {
          // 弹窗手动输入模式：打开商品详情抽屉
          if (targetIndex != null) {
            _editDetail(targetIndex);
          }
        } else {
          // 默认累加模式：焦点处理
          _focusAfterScan(returnFocusNode, targetRow: targetRow);
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

  /// 扫码后焦点处理
  /// [returnFocusNode] 红外扫描框的焦点节点（连续扫码模式时回到此处）
  /// [targetRow] 扫码匹配到的商品行，连续扫码关闭时聚焦到该行的数量输入框
  void _focusAfterScan(FocusNode? returnFocusNode, {_DetailRow? targetRow}) {
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
        // 连续扫码关闭：焦点转移到数量输入框
        if (targetRow != null) {
          targetRow.qtyFocusNode.requestFocus();
        } else if (returnFocusNode != null) {
          returnFocusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        } else if (_scanSettings.showInfraredInput) {
          _scanFocusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        }
      }
    });
  }

  void _recalcRow(_DetailRow row) {
    final qty = MathUtils.formatDecimalNum(1, double.tryParse(row.qtyController.text) ?? 0);
    final price = MathUtils.formatDecimalNum(2, double.tryParse(row.priceController.text) ?? 0);
    row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    // 折扣率联动（对齐 Vue writeData price 分支：改价后重算 profit）
    _calcProfit(row);
  }

  /// 折扣率计算（对齐 Vue cgorder/edit.vue jsGrossrate / handleProperty）：
  /// profit = price / oldprice * 100（比率列保留 2 位小数，对齐 Vue setDecimals(4)）；
  /// oldprice 取值对齐 Vue handleProperty：仅已保存未审核单据（signflag===0）优先商品主数据
  /// 进价 inprice，新增页（signflag 为空）与已审核单据均优先 oldprice、为空时兜底 cgprice；
  /// oldprice 为 0 时折扣率记 100。结果回写 rawData，返回字符串 profit（后台折扣率 rate 字段）。
  String _calcProfit(_DetailRow row) {
    final raw = row.rawData ?? <String, dynamic>{};
    final price = double.tryParse(row.priceController.text) ?? 0;
    // 严格对齐 Vue `form.signflag === 0`：新增页 signflag 为空字符串（非 0），
    // 仅已保存未审核单据（后端返回数字 0）才走 inprice 优先分支
    final signflag = int.tryParse(_billData?['signflag']?.toString() ?? '') ?? -1;
    final inprice = double.tryParse(raw['inprice']?.toString() ?? '') ?? 0;
    final savedOldprice = double.tryParse(raw['oldprice']?.toString() ?? '') ?? 0;
    final cgprice = double.tryParse(raw['cgprice']?.toString() ?? '') ?? 0;
    final double oldprice;
    if (signflag == 0) {
      oldprice = inprice != 0 ? inprice : savedOldprice;
    } else {
      oldprice = savedOldprice != 0 ? savedOldprice : cgprice;
    }
    // 规范化原价回写（对齐 Vue handleProperty：v.oldprice = ...）
    raw['oldprice'] = oldprice;
    String profit = '0';
    if (oldprice == 0) {
      profit = '100';
    } else if (price != 0) {
      profit =
          MathUtils.formatDecimal(4, MathUtils.multiply(MathUtils.divide(price, oldprice), 100));
    }
    raw['profit'] = profit;
    return profit;
  }

  /// 供应商/机构切换后刷新商品价格（对齐 Vue updateCgPrice）
  /// 使用批量 API /cgstockin/updateCgPrice 一次性更新所有商品价格
  Future<void> _refreshProductPrices() async {
    if (_items.isEmpty) {
      debugPrint('[updateCgPrice] _items 为空，跳过');
      return;
    }

    // 构建 detaillist（对齐 Vue updateCgPrice）
    final detaillist = <Map<String, dynamic>>[];
    int isort = 1;
    for (final row in _items) {
      final prodId = row.prodid ?? '';
      if (prodId.isEmpty) continue;
      detaillist.add({
        'isort': isort++,
        'productid': prodId,
        'unitonlyid': row.rawData?['unitonlyid']?.toString() ?? '',
        'sizeonlyid': row.rawData?['sizeonlyid']?.toString() ?? '',
        'batchno': row.batchno,
      });
    }
    if (detaillist.isEmpty) {
      debugPrint('[updateCgPrice] detaillist 为空（无有效商品），跳过');
      return;
    }

    // 对齐 Vue：发送完整表单参数（cloneDeep(form)），后端需要完整上下文才能正确计算价格
    final params = <String, dynamic>{
      'bsid': _storeid ?? '',
      'supid': _supid ?? '',
      'counterid': '', // 采购订货单无仓库选择
      'detaillist': detaillist,
    };
    // 编辑模式：带入已有单据信息（对齐 Vue cloneDeep(form) 带入 billid 等字段）
    if (_billData != null) {
      params['billid'] = _billData!['billid']?.toString() ?? _newBillid ?? '';
      params['billtypeid'] = _billData!['billtypeid']?.toString() ?? '0502';
      params['billno'] = _billData!['billno']?.toString() ?? '';
    } else if (_newBillid != null && _newBillid!.isNotEmpty) {
      params['billid'] = _newBillid;
    }

    debugPrint(
        '[updateCgPrice] 请求参数: bsid=${params['bsid']}, supid=${params['supid']}, billid=${params['billid']}, detaillist.length=${detaillist.length}');

    try {
      final result = await request(HttpApi.purchaseUpdateCgPrice, params);
      if (!mounted) return;

      final responseData = result['data'];
      debugPrint(
          '[updateCgPrice] 响应 data 类型: ${responseData.runtimeType}, retcode=${result['retcode']}');

      final list = (responseData is List ? responseData : responseData?['list']) as List? ?? [];
      debugPrint('[updateCgPrice] 解析到 ${list.length} 条价格数据');

      if (list.isEmpty) {
        debugPrint('[updateCgPrice] 返回数据为空，可能参数有误');
        return;
      }

      // 打印首条数据辅助排查字段匹配
      if (list.isNotEmpty && list.first is Map<String, dynamic>) {
        final first = list.first as Map<String, dynamic>;
        debugPrint(
            '[updateCgPrice] 首条返回: productid=${first['productid']}, unitonlyid=${first['unitonlyid']}, sizeonlyid=${first['sizeonlyid']}, cgprice=${first['cgprice']}');
      }

      // 构建 productid + unitonlyid + sizeonlyid 组合键映射
      final Map<String, Map<String, dynamic>> priceMap = {};
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final productid = item['productid']?.toString() ?? '';
        if (productid.isEmpty) continue;
        final unitonlyid = item['unitonlyid']?.toString() ?? '';
        final sizeonlyid = item['sizeonlyid']?.toString() ?? '';
        final key = '${productid}_${unitonlyid}_$sizeonlyid';
        priceMap[key] = item;
      }
      debugPrint('[updateCgPrice] priceMap 共 ${priceMap.length} 条');

      setState(() {
        // 更新已有行的价格，移除不在返回结果中的商品
        _items.removeWhere((row) {
          final prodId = row.prodid ?? '';
          if (prodId.isEmpty) return false; // 保留空行
          final unitonlyid = row.rawData?['unitonlyid']?.toString() ?? '';
          final sizeonlyid = row.rawData?['sizeonlyid']?.toString() ?? '';
          final key = '${prodId}_${unitonlyid}_$sizeonlyid';
          return !priceMap.containsKey(key);
        });

        // 更新价格
        for (final row in _items) {
          final prodId = row.prodid ?? '';
          if (prodId.isEmpty) continue;
          final unitonlyid = row.rawData?['unitonlyid']?.toString() ?? '';
          final sizeonlyid = row.rawData?['sizeonlyid']?.toString() ?? '';
          final key = '${prodId}_${unitonlyid}_$sizeonlyid';
          final item = priceMap[key];
          if (item == null) continue;

          // 更新采购价（cgprice 优先，为 0 时取 price）
          final cgprice = double.tryParse(item['cgprice']?.toString() ?? '') ?? 0;
          final price =
              cgprice != 0 ? cgprice : (double.tryParse(item['price']?.toString() ?? '') ?? 0);
          row.priceController.text = MathUtils.formatDecimal(2, price);
          debugPrint('[updateCgPrice] 商品 $prodId 更新价格: $price (cgprice=$cgprice)');

          // 同步进价相关基数（对齐 Vue updateTableDataInPlace Object.assign：
          // cgprice/sellprice/inprice/oldprice 随价格一并刷新，保证折扣率 profit 基数正确）
          if (row.rawData != null) {
            row.rawData!['cgprice'] = cgprice;
            final sellpriceVal = item['sellprice']?.toString();
            if (sellpriceVal != null) {
              row.rawData!['sellprice'] = sellpriceVal;
            }
            final inpriceVal = item['inprice']?.toString();
            if (inpriceVal != null && double.tryParse(inpriceVal) != 0) {
              row.rawData!['inprice'] = inpriceVal;
            }
            final oldpriceVal = item['oldprice']?.toString() ?? inpriceVal;
            row.rawData!['oldprice'] = oldpriceVal;
          }

          // 更新库存
          row.stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;

          // 重算金额（刷新价格视为编辑价格，对齐 Vue writeData：重置手动金额标记）
          row.amtManual = false;
          _recalcRow(row);
        }
      });
    } catch (e) {
      debugPrint('[updateCgPrice] 刷新价格失败: $e');
    }
  }

  // =================== 计算汇总 ===================
  String get _totalQty {
    double sum = 0;
    for (final row in _items) {
      sum += double.tryParse(row.qtyController.text) ?? 0;
    }
    return sum.toStringAsFixed(1);
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

  /// 提交前同步全部行的 amt（兜底未失焦的数量修改，对齐 Vue writeData 的 amt 重算）：
  /// 手动修改过金额的行保留其值，除非系统参数 cgAmountRecalculationflag==1 强制重算
  void _syncAllAmt() {
    final forceRecalc = _loginParamInt('cgAmountRecalculationflag') == 1;
    for (final row in _items) {
      if (row.amtManual && !forceRecalc) continue;
      final qty = double.tryParse(row.qtyController.text) ?? 0;
      final price = double.tryParse(row.priceController.text) ?? 0;
      row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    }
  }

  List<Map<String, dynamic>> _buildSubmitDetailList() {
    _syncAllAmt();
    return _items.map((row) {
      final qty = MathUtils.formatDecimalNum(1, double.tryParse(row.qtyController.text) ?? 0);
      final price = MathUtils.formatDecimalNum(2, double.tryParse(row.priceController.text) ?? 0);
      final giftqty =
          MathUtils.formatDecimalNum(1, double.tryParse(row.giftQtyController.text) ?? 0);
      final item =
          row.rawData != null ? Map<String, dynamic>.from(row.rawData!) : <String, dynamic>{};
      item['productname'] = row.nameController.text.trim();
      item['prodname'] = row.nameController.text.trim();
      item['qty'] = qty;
      item['price'] = price;
      item['amt'] = MathUtils.formatDecimalNum(3, row.amt ?? MathUtils.mul(qty, price));
      item['giftqty'] = giftqty;
      item['presentqty'] = giftqty;
      // 折扣率（对齐 Vue jsGrossrate：profit = price / oldprice * 100）：
      // 提交时统一重算并携带 profit/rate 字段，防止缺失或沿用接口旧值导致后台折扣率异常
      item['profit'] = _calcProfit(row);
      item['rate'] = item['profit'];
      item['prodid'] = row.prodid ?? item['productid'] ?? '';
      item['remark'] = row.remarkController.text.trim();
      // 单位/规格字段
      item['unit'] = item['unit']?.toString() ?? '';
      item['size'] = item['size']?.toString() ?? '';
      item['unitonlyid'] = item['unitonlyid']?.toString() ?? '';
      item['sizeonlyid'] = item['sizeonlyid']?.toString() ?? '';
      return item;
    }).toList();
  }

  // =================== 选择商品 ===================
  /// 构建选择页 selectList：将当前明细行转换为选择页所需的预选中格式
  /// 包含 productid、qty、price 等字段，对齐小程序 selectProduct.vue selectList 参数
  List<Map<String, dynamic>> _buildSelectList() {
    return _items.map((row) {
      final raw = row.rawData;
      final map = raw != null ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      map['productid'] = row.prodid ?? map['prodid'] ?? '';
      map['qty'] = double.tryParse(row.qtyController.text) ?? 1;
      map['giftqty'] = double.tryParse(row.giftQtyController.text) ?? 0;
      map['price'] = double.tryParse(row.priceController.text) ?? 0;
      // cgprice 同步为修改后的价格（覆盖 rawData 中的档案价），
      // 保证选择页详情抽屉价格回显/反算使用用户修改值而非档案原价（对齐 instore）
      map['cgprice'] = map['price'];
      map['amt'] = row.amt ?? 0;
      map['unit'] = map['unit']?.toString() ?? '';
      map['size'] = map['size']?.toString() ?? '';
      return map;
    }).toList();
  }

  /// 构建商品查询参数（对齐 Vue cgorder/edit.vue mergDataFn）：
  /// cgpriceflag=1 时选择页价格显示 cgprice（为空或为 0 回退档案进价 price）
  Map<String, dynamic> _buildMergData() {
    return {
      'stockflag': 1,
      'storeid': _storeid ?? '',
      'counterid': '',
      'cgpriceflag': 1,
      'billsupid': _supid ?? '',
      'itemstatus': '1,2',
      'itemstatusin': '1,2',
      'itemtypenot': '5,8',
    };
  }

  Future<void> _selectProduct({String? initialKeyword, FocusNode? returnFocusNode}) async {
    if (_storeid == null) {
      Toast.show('请先选择订货机构');
      return;
    }
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
      return;
    }
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          storeid: _storeid,
          counterid: '',
          billsupid: _supid,
          mergData: _buildMergData(),
          selectList: _buildSelectList(),
          paramJust: const ['qty', 'jsqty', 'presentqty', 'price', 'amt', 'unit', 'size', 'remark'],
          initialKeyword: initialKeyword,
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        for (final prod in result) {
          final prodId = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
          // 对齐采购入库：使用选择页面返回的 qty（用户通过 +/- 或详情抽屉修改后的数量）
          final selectedQty = double.tryParse(prod['qty']?.toString() ?? '') ?? 1;
          final selectedGiftQty = double.tryParse(prod['giftqty']?.toString() ?? '') ?? 0;
          // 复合去重键对齐后台 ROW_KEYS：productid + unitonlyid + sizeonlyid，
          // 同一商品不同包装/规格视为不同行（切换单位后再选品不会覆盖已有行）
          final prodUnit = prod['unitonlyid']?.toString() ?? '';
          final prodSize = prod['sizeonlyid']?.toString() ?? '';
          final existIndex = _items.indexWhere((r) =>
              r.prodid == prodId &&
              (r.rawData?['unitonlyid']?.toString() ?? '') == prodUnit &&
              (r.rawData?['sizeonlyid']?.toString() ?? '') == prodSize);
          if (existIndex >= 0) {
            // 对齐 Vue onSelectProduct 合并语义：选择页返回的行整体替换已有行
            // （Map 按复合键去重后返回行覆盖旧行，qty/price/amt 均取返回值，不再累加）
            final row = _items[existIndex];
            // 价格取值（对齐选择页规则）：采购价 cgprice 优先，为空或 0 回退档案进价 price
            final syncCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
            final newPrice = syncCgprice != 0
                ? syncCgprice
                : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
            row.prodid = prodId;
            row.nameController.text =
                prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
            row.qtyController.text = MathUtils.formatDecimal(1, selectedQty);
            row.giftQtyController.text = MathUtils.formatDecimal(1, selectedGiftQty);
            row.priceController.text = MathUtils.formatDecimal(2, newPrice);
            final pn = double.tryParse(prod['packagenum']?.toString() ?? '') ?? 1;
            row.jsQtyController.text = pn > 0 ? (selectedQty / pn).toStringAsFixed(1) : '0';
            row.rawData = Map<String, dynamic>.from(prod);
            // 替换语义：手动金额状态以返回行为准（旧行手动状态不保留）
            row.amtManual = false;
            _recalcRow(row);
            // 优先使用选择页返回的 amt（选择页可能手动修改小计金额，已按参数反算数量）
            final prodAmt = prod['amt']?.toString();
            if (prodAmt != null && prodAmt.isNotEmpty) {
              row.amt = MathUtils.formatDecimalNum(3, double.tryParse(prodAmt) ?? row.amt ?? 0);
            }
            // 手动金额标记透传（对齐 Vue _amtManual）
            if (prod['_amtManual'] == true) row.amtManual = true;
          } else {
            final cgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
            final price =
                cgprice != 0 ? cgprice : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
            final row = _DetailRow();
            row.prodid = prodId;
            row.nameController.text =
                prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
            row.qtyController.text = MathUtils.formatDecimal(1, selectedQty);
            row.giftQtyController.text = MathUtils.formatDecimal(1, selectedGiftQty);
            row.priceController.text = price.toStringAsFixed(2);
            final pn = double.tryParse(prod['packagenum']?.toString() ?? '') ?? 1;
            row.jsQtyController.text = pn > 0 ? (selectedQty / pn).toStringAsFixed(1) : '0';
            row.rawData = Map<String, dynamic>.from(prod);
            _recalcRow(row);
            // 优先使用选择页返回的 amt（选择页可能手动修改小计金额，对齐 instore）
            final prodAmt = prod['amt']?.toString();
            if (prodAmt != null && prodAmt.isNotEmpty) {
              row.amt = MathUtils.formatDecimalNum(3, double.tryParse(prodAmt) ?? row.amt ?? 0);
            }
            // 手动金额标记透传（对齐 Vue _amtManual）
            if (prod['_amtManual'] == true) row.amtManual = true;
            _items.insert(0, row);
          }
        }
      });
    }
    // 扫码多条命中跳转选品返回后恢复焦点（红外连续扫码场景）
    if (returnFocusNode != null && mounted) {
      _focusAfterScan(returnFocusNode);
    }
  }

  // =================== 商品详情抽屉 ===================
  Future<void> _editDetail(int index) async {
    if (_isSelectMode) {
      _toggleIndex(index);
      return;
    }
    final row = _items[index];
    if ((row.prodid ?? '').isEmpty) return;
    final raw = Map<String, dynamic>.from(row.rawData ?? {});
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        // 键盘弹起时弹窗整体上移，避免输入框被键盘遮挡
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ProDetailSheet(
          productData: raw,
          initialPrice: double.tryParse(row.priceController.text) ?? 0,
          initialQty: double.tryParse(row.qtyController.text) ?? 0,
          initialGiftQty: double.tryParse(row.giftQtyController.text) ?? 0,
          initialAmt: row.amt,
          initialAmtManual: row.amtManual,
          initialRemark: row.remarkController.text,
          bsid: _storeid,
          readOnly: _readOnly,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        // 抽屉确定返回值兼容 String（formatDecimal）/num 两种类型，容错解析避免强转崩溃
        final priceVal =
            MathUtils.formatDecimalNum(2, double.tryParse(result['price']?.toString() ?? '') ?? 0);
        row.priceController.text = MathUtils.formatDecimal(2, priceVal);
        final qtyVal =
            MathUtils.formatDecimalNum(1, double.tryParse(result['qty']?.toString() ?? '') ?? 0);
        row.qtyController.text = MathUtils.formatDecimal(1, qtyVal);
        final giftVal = MathUtils.formatDecimalNum(
            1, double.tryParse(result['giftqty']?.toString() ?? '') ?? 0);
        row.giftQtyController.text = MathUtils.formatDecimal(1, giftVal);
        row.remarkController.text = result['remark']?.toString() ?? '';
        // 同步单位/规格
        final unit = result['unit']?.toString();
        if (unit != null) raw['unit'] = unit;
        final size = result['size']?.toString();
        if (size != null) raw['size'] = size;
        final unitonlyid = result['unitonlyid']?.toString();
        if (unitonlyid != null) raw['unitonlyid'] = unitonlyid;
        final sizeonlyid = result['sizeonlyid']?.toString();
        if (sizeonlyid != null) raw['sizeonlyid'] = sizeonlyid;
        row.rawData = raw;
        // 同步件数 = 数量 / 包装数
        final pn = double.tryParse(raw['packagenum']?.toString() ?? '') ?? 1;
        row.jsQtyController.text = pn > 0 ? MathUtils.formatDecimal(1, qtyVal / pn) : '0';
        // 小计金额与手动标记透传（对齐 Vue proDetails writeData key==amt）:
        // 抽屉内手动修改过金额时保留其值，否则按 qty × price 重算
        final detailAmtManual = result['_amtManual'] == true;
        final detailAmtVal = double.tryParse(result['amt']?.toString() ?? '');
        if (detailAmtManual && detailAmtVal != null) {
          row.amtManual = true;
          row.amt = MathUtils.formatDecimalNum(3, detailAmtVal);
        } else {
          row.amtManual = false;
          _recalcRow(row);
        }
      });
    }
  }

  // =================== Build ===================
  bool get _readOnly => _isEdit && !_bolHandle;

  /// 粘性表头区域高度常量（已迁移至 PinnedHeaderSliver）
  // static const double _stickyScanHeight = 68.0;
  // static const double _stickyTitleHeight = 40.0;
  // static const double _stickyColumnHeight = 36.0;
  // static const double _stickyMinExtent = _stickyTitleHeight + _stickyColumnHeight;
  // static const double _stickyMaxExtent = _stickyScanHeight + _stickyMinExtent;

  @override
  Widget build(BuildContext context) {
    final String title =
        _isEdit ? (_isSigned ? '采购订货单详情' : (_isRejected ? '采购订货单详情' : '修改采购订货')) : '新增采购订货';

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
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            )),
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    // 键盘弹起时隐藏底部栏，给商品明细列表留出更多空间
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final body = Column(
      children: [
        Expanded(
          child: CustomScrollView(
            cacheExtent: 800,
            slivers: [
              // ---- 单号+状态（仅编辑模式） ----
              if (_isEdit && _billData != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: _buildBillStatusWidget(),
                  ),
                ),
              // ---- 审核日志卡片（多级审批） ----
              if (_isEdit && (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: _buildApprovalNodeCard(),
                  ),
                ),
              // ---- 单据信息卡片 ----
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: _buildCard(
                    title: '单据信息',
                    child: _readOnly ? _buildBillInfoReadonly() : _buildBillInfoEditable(),
                  ),
                ),
              ),
              // ---- 粘性表头：扫描框 + 商品明细标题 + 列头 ----
              PinnedHeaderSliver(
                child: _buildStickyHeader(),
              ),
              // ---- 明细行列表 ----
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
                        onTap: () => _editDetail(index),
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ),
                ),
              // ---- 空状态（放在滚动区域内，避免溢出粘性表头）----
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
    return _isEdit ? body : Form(key: _formKey, child: body);
  }

  // =================== 粘性表头 ===================
  Widget _buildStickyHeader() {
    return ColoredBox(
      color: const Color(0xFFF5F5F5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 扫描输入框（仅非已审核 + 扫码设备设置显示红外输入时显示）
          if (!_readOnly && _scanSettings.showInfraredInput) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: _buildScanInput(),
            ),
            const SizedBox(height: 4),
          ],
          // 商品明细卡片（标题栏 + 列头）
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题 + 操作按钮
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
                        if (!_readOnly) ...[
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
                                      fontWeight: FontWeight.w500)),
                            ]),
                          ),
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
                                        fontWeight: FontWeight.w500)),
                              ]),
                            ),
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
                                        fontWeight: FontWeight.w500)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                          ],
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
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  // 列头
                  Container(
                    color: const Color(0xFFF9FAFB),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: const Row(
                      children: [
                        Expanded(
                            flex: 5,
                            child: Text('商品信息',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500))),
                        Expanded(
                            flex: 3,
                            child: Text('进价',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500))),
                        Expanded(
                            flex: 2,
                            child: Text('赠送',
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 红外扫描输入框（PDA 扫码枪）
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
                onSubmitted: (value) {
                  final code = value.trim();
                  if (code.isNotEmpty) {
                    if (_supid == null || _supid!.isEmpty) {
                      Toast.show('请先选择供应商');
                      if (mounted) {
                        _scanController.clear();
                        _scanFocusNode.requestFocus();
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                      }
                      return;
                    }
                    _handleScannedBarcode(code);
                    if (mounted) {
                      _scanController.clear();
                      _scanFocusNode.requestFocus();
                      SystemChannels.textInput.invokeMethod('TextInput.hide');
                    }
                  }
                },
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

  // =================== 单号状态卡片 ===================
  Widget _buildBillStatusWidget() {
    final data = _billData ?? {};
    final String billno = data['billno']?.toString() ?? '-';
    final String createtime = data['createtime']?.toString() ?? '-';
    final String buyername = data['buyername']?.toString() ?? '';
    final String signflag = data['signflag']?.toString() ?? '';
    final String signtime = data['signtime']?.toString() ?? '';
    final String signusername =
        data['signusername']?.toString() ?? data['signname']?.toString() ?? '';

    String statusText = '待审核';
    Color statusColor = const Color(0xFFD54B5A);
    if (signflag == '1') {
      statusText = '已审核';
      statusColor = const Color(0xFF00A870);
    } else if (signflag == '2') {
      statusText = '已驳回';
      statusColor = const Color(0xFFFF9900);
    }

    return _buildCard(
      title: '单号：$billno',
      titleRight: Text(statusText,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('制单信息：$createtime',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              const SizedBox(width: 16),
              Text(buyername, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            ]),
            if (_isSigned && (signtime.isNotEmpty || signusername.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Row(children: [
                Text('审核信息：${signtime.isNotEmpty ? signtime : '-'}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                const SizedBox(width: 16),
                Text(signusername.isNotEmpty ? signusername : '-',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // =================== 通用卡片 ===================
  Widget _buildCard({
    required String title,
    required Widget child,
    Widget? titleRight,
  }) {
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
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
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          child,
        ],
      ),
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

  // =================== 单据信息 ===================
  Widget _buildBillInfoReadonly() {
    return Column(children: [
      _buildReadonlyField(label: '供应商', value: _supController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '订货机构', value: _storeController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '经手人', value: _buyerController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '备注', value: _remarkController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildAttachButton(),
    ]);
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

  /// 附件按钮行
  Widget _buildAttachButton() {
    return GestureDetector(
      onTap: () async {
        final result = await AttachPage.show(
          context,
          fileLists: _fileLists,
          menuid: '050201',
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

  Widget _buildBillInfoEditable() {
    return Column(children: [
      SelectFieldItem(
        label: '供应商',
        required: true,
        value: _supController.text,
        onTap: () async {
          final result = await SelectSupplierPage.show(context, initialSelectedId: _supid ?? '');
          if (result != null && mounted) {
            final oldSupid = _supid;
            setState(() {
              _supid = result['supid']?.toString() ?? '';
              // 对齐 Vue selectSupFn：只保存供应商名称，不拼接编号
              _supController.text =
                  result['name']?.toString() ?? result['supname']?.toString() ?? '';
            });
            debugPrint(
                '[updateCgPrice] 供应商切换: oldSupid=$oldSupid, newSupid=$_supid, items=${_items.length}');
            if (oldSupid != _supid) _refreshProductPrices();
          }
        },
      ),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
        label: '订货机构',
        required: true,
        value: _storeController.text,
        onTap: () async {
          final result =
              await SelectStorePage.show(context, initialSelectedId: _storeid?.toString() ?? '');
          if (result != null && mounted) {
            final oldStoreid = _storeid;
            setState(() {
              final storeId = result['storeid']?.toString() ?? '';
              _storeid = int.tryParse(storeId);
              _storename = result['storename']?.toString() ?? '';
              _storetype = int.tryParse(result['storetype']?.toString() ?? '') ?? _storetype;
              _storeController.text = result['storename']?.toString() ?? '';
            });
            if (oldStoreid != _storeid) {
              _refreshProductPrices();
              _initSignUserBtn();
            }
          }
        },
      ),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
        label: '经手人',
        value: _buyerController.text,
        onTap: () async {
          final result = await SelectBuyerPage.show(context, initialSelectedId: _buyerid ?? '');
          if (result != null && mounted) {
            setState(() {
              _buyerid = result['buyerid']?.toString() ?? '';
              _buyername = result['buyername']?.toString() ?? '';
              _buyerController.text = result['buyername']?.toString() ?? '';
            });
          }
        },
      ),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildField(controller: _remarkController, label: '备注', hint: '请输入备注信息'),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildAttachButton(),
    ]);
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

  // =================== 底部操作栏 ===================
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
          // 统计栏：实时监听明细行数量/价格输入，输入过程中同步刷新（对齐 instore）
          ListenableBuilder(
            listenable: Listenable.merge([
              for (final row in _items) ...[row.qtyController, row.priceController],
            ]),
            builder: (context, _) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      '共${_items.length}项，合计数量：$_totalQty，总金额：$_totalAmt',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              );
            },
          ),
          // 编辑模式 - 待审核/已驳回（signflag != 1）
          if (_isEdit && !_isSigned) _buildEditUnsignedButtons(),
          // 编辑模式 - 已审核：反审核 + 终止 + 打印
          if (_isEdit && _isSigned) _buildEditSignedButtons(),
          // 新增模式：保存 + 审核
          if (!_isEdit) _buildNewBillButtons(),
        ],
      ),
    );
  }

  /// 编辑模式 - 待审核/已驳回：更多(删除/打印) + 保存 + 审核 + 撤回
  Widget _buildEditUnsignedButtons() {
    final bool isLoading = _submitAction != _COAction.none;
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
          child: _submitAction == _COAction.save
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
              : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    // 审核按钮
    if (showSaveAndAudit) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: isLoading ? null : _sign,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF006EFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitAction == _COAction.sign
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    // 撤回按钮 - 仅已驳回状态(signflag==2)显示
    if (_isRejected) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: isLoading ? null : _restsign,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9900),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitAction == _COAction.withdraw
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('撤回', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    return Row(children: buttons);
  }

  /// 编辑模式 - 已审核：反审核 + 终止 + 打印
  Widget _buildEditSignedButtons() {
    final bool isLoading = _submitAction != _COAction.none;
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
          child: _submitAction == _COAction.retsign
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
              : const Text('反审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    // 终止按钮 - dhflag != 4
    final dhflag = _billData?['dhflag']?.toString() ?? '';
    if (dhflag != '4') {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
        child: OutlinedButton(
          onPressed: isLoading ? null : _stopBill,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFEF4444),
            side: const BorderSide(color: Color(0xFFEF4444)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitAction == _COAction.stop
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)))
              : const Text('终止', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
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
        child: _submitAction == _COAction.print
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('打印', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    return Row(children: buttons);
  }

  /// 新增模式：保存 + 审核
  Widget _buildNewBillButtons() {
    final bool isLoading = _submitAction != _COAction.none;
    final buttons = <Widget>[];

    buttons.add(Expanded(
      child: OutlinedButton(
        onPressed: isLoading ? null : () => _submit(),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF006EFF),
          side: const BorderSide(color: Color(0xFF006EFF)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _COAction.save
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
            : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    // 审核按钮 - billSign
    if (_billSign) {
      buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: isLoading ? null : _saveAndSign,
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
    }

    return Row(children: buttons);
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
      child: Row(children: [
        GestureDetector(
          onTap: _toggleSelectAll,
          behavior: HitTestBehavior.opaque,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: selectedCount > 0 ? _batchDelete : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: selectedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFFD1D5DB),
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
      ]),
    );
  }
}

// =================== 明细行独立 Widget ===================
class _DetailItem extends StatefulWidget {
  const _DetailItem({
    required this.row,
    required this.index,
    this.isSelectMode = false,
    this.isSelected = false,
    this.readOnly = false,
    required this.onToggle,
    required this.onTap,
    this.onChanged,
  });
  final _DetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  /// 失焦回调：行金额格式化/重算完成后通知父页面刷新底部合计
  final VoidCallback? onChanged;

  @override
  State<_DetailItem> createState() => _DetailItemState();
}

class _DetailItemState extends State<_DetailItem> {
  // 直接使用 _DetailRow 的控制器（共享引用）
  TextEditingController get _priceCtrl => widget.row.priceController;
  TextEditingController get _giftQtyCtrl => widget.row.giftQtyController;
  TextEditingController get _qtyCtrl => widget.row.qtyController;

  // 失焦格式化监听器
  late final VoidCallback _onPriceBlur;
  late final VoidCallback _onQtyBlur;
  late final VoidCallback _onGiftBlur;

  @override
  void initState() {
    super.initState();
    _onPriceBlur = () => _formatField(widget.row.priceFocusNode, _priceCtrl, 2);
    _onQtyBlur = () => _formatField(widget.row.qtyFocusNode, _qtyCtrl, 1);
    _onGiftBlur = () => _formatField(widget.row.giftQtyFocusNode, _giftQtyCtrl, 1);
    widget.row.priceFocusNode.addListener(_onPriceBlur);
    widget.row.qtyFocusNode.addListener(_onQtyBlur);
    widget.row.giftQtyFocusNode.addListener(_onGiftBlur);
  }

  @override
  void dispose() {
    widget.row.priceFocusNode.removeListener(_onPriceBlur);
    widget.row.qtyFocusNode.removeListener(_onQtyBlur);
    widget.row.giftQtyFocusNode.removeListener(_onGiftBlur);
    super.dispose();
  }

  /// 失焦时格式化输入框文本（对齐 Vue writeData formatDecimal 逻辑）
  void _formatField(FocusNode node, TextEditingController ctrl, int col) {
    if (node.hasFocus) return;
    final value = double.tryParse(ctrl.text);
    if (value != null) {
      final text = MathUtils.formatDecimal(col, value);
      if (text != ctrl.text) {
        ctrl.text = text;
      }
    }
    _notifyChange();
    widget.onChanged?.call();
  }

  /// 通知父组件数据变更（更新 amt + 触发 UI 刷新）
  void _notifyChange() {
    final price = MathUtils.formatDecimalNum(2, double.tryParse(_priceCtrl.text) ?? 0);
    final qty = MathUtils.formatDecimalNum(1, double.tryParse(_qtyCtrl.text) ?? 0);
    final giftQty = MathUtils.formatDecimalNum(1, double.tryParse(_giftQtyCtrl.text) ?? 0);
    // 失焦重算（对齐 Vue writeData 收尾）：手动修改过金额的行保留其值，
    // 除非系统参数 cgAmountRecalculationflag==1 强制按 qty × price 重算
    if (!widget.row.amtManual || _loginParamInt('cgAmountRecalculationflag') == 1) {
      widget.row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    }
    final raw = widget.row.rawData;
    if (raw != null) {
      raw['price'] = price;
      raw['qty'] = qty;
      raw['amt'] = widget.row.amt;
      raw['giftqty'] = giftQty;
      raw['presentqty'] = giftQty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.row.rawData;
    final String productname = widget.row.nameController.text.isNotEmpty
        ? widget.row.nameController.text
        : (raw?['productname']?.toString() ?? raw?['name']?.toString() ?? '-');
    final String unit = raw?['unit']?.toString() ?? '';
    final String size = raw?['size']?.toString() ?? '';
    final String code = raw?['barcode']?.toString() ?? raw?['selfbarcode']?.toString() ?? '';
    final String retailPrice =
        (double.tryParse(raw?['retailprice']?.toString() ?? raw?['sellprice']?.toString() ?? '0') ??
                0)
            .toStringAsFixed(2);
    final String displayName =
        '$productname${size.isNotEmpty ? '/$size' : ''}${unit.isNotEmpty ? '($unit)' : ''}';

    return Container(
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
              // 列1: 商品信息 flex:5（点击打开详情弹窗）
              Expanded(
                flex: 5,
                child: GestureDetector(
                  onTap: widget.isSelectMode
                      ? widget.onToggle
                      : (widget.readOnly ? null : widget.onTap),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (code.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(code, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      ],
                      const SizedBox(height: 2),
                      Text('零售价：¥$retailPrice',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 右侧：可编辑数值字段
              Expanded(
                flex: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(children: [
                      // 列2: 进价 flex:3
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _priceCtrl,
                            focusNode: widget.row.priceFocusNode,
                            readOnly: widget.readOnly,
                            enabled: !widget.readOnly,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                            // 对齐 Vue writeData：编辑单价时重置手动金额标记，amt 回归 qty × price
                            onChanged: (_) => widget.row.amtManual = false,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              border: OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFF006EFF))),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 列3: 赠送 flex:2
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _giftQtyCtrl,
                            focusNode: widget.row.giftQtyFocusNode,
                            readOnly: widget.readOnly,
                            enabled: !widget.readOnly,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                            // 对齐 Vue writeData：编辑赠送数量时重置手动金额标记
                            onChanged: (_) => widget.row.amtManual = false,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              border: OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFF006EFF))),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 列4: 数量 flex:3
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _qtyCtrl,
                            focusNode: widget.row.qtyFocusNode,
                            readOnly: widget.readOnly,
                            enabled: !widget.readOnly,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                            // 对齐 Vue writeData：编辑数量时重置手动金额标记，amt 回归 qty × price
                            onChanged: (_) => widget.row.amtManual = false,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              border: OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFF006EFF))),
                            ),
                          ),
                        ),
                      ),
                    ]),
                    // 小计行（对齐 Vue writeData：手动修改过金额的行显示保留值（row.amt），
                    // 其余实时按 qty × price 计算；失焦时经 _notifyChange 锁定确认值）
                    ListenableBuilder(
                      listenable: Listenable.merge([_qtyCtrl, _priceCtrl]),
                      builder: (_, __) {
                        final q = double.tryParse(_qtyCtrl.text) ?? 0;
                        final p = double.tryParse(_priceCtrl.text) ?? 0;
                        final a = widget.row.amtManual && widget.row.amt != null
                            ? MathUtils.formatDecimal(3, widget.row.amt)
                            : MathUtils.formatDecimal(3, MathUtils.mul(q, p));
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('小计：¥$a',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 明细行数据模型
class _DetailRow {
  String? prodid;

  /// 小计金额是否被用户手动修改（对齐 Vue writeData 的 _amtManual）：
  /// true 时保留 amt（不随 qty × price 重算），除非系统参数 cgAmountRecalculationflag==1
  bool amtManual = false;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController(text: '1');
  final FocusNode qtyFocusNode = FocusNode();
  final TextEditingController priceController = TextEditingController();
  final FocusNode priceFocusNode = FocusNode();
  final TextEditingController giftQtyController = TextEditingController(text: '0');
  final FocusNode giftQtyFocusNode = FocusNode();
  final TextEditingController jsQtyController = TextEditingController(text: '0');
  final TextEditingController remarkController = TextEditingController();
  double? amt;

  /// 门店库存（对齐 Vue stockqty，用于负库存校验）
  double stockqty = 0;

  /// 批次号（对齐 Vue batchno）
  String batchno = '';
  Map<String, dynamic>? rawData;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    qtyFocusNode.dispose();
    priceFocusNode.dispose();
    giftQtyFocusNode.dispose();
    priceController.dispose();
    giftQtyController.dispose();
    jsQtyController.dispose();
    remarkController.dispose();
  }
}

/// 商品详情抽屉（对齐采购入库 _ProDetailSheet 样式，字段按 Vue cgorder paramJust 配置）
class _ProDetailSheet extends StatefulWidget {
  const _ProDetailSheet({
    required this.productData,
    required this.initialPrice,
    required this.initialQty,
    required this.initialGiftQty,
    this.initialAmt,
    this.initialAmtManual = false,
    required this.initialRemark,
    this.bsid,
    this.readOnly = false,
  });
  final Map<String, dynamic> productData;
  final double initialPrice;
  final double initialQty;
  final double initialGiftQty;

  /// 小计金额初始值：null 时按 qty × price 计算
  final double? initialAmt;

  /// 小计金额是否被手动修改（对齐 Vue writeData 的 _amtManual）
  final bool initialAmtManual;
  final String initialRemark;
  final int? bsid;
  final bool readOnly;

  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _giftCtrl;
  late TextEditingController _jsQtyCtrl;
  late TextEditingController _amtCtrl;
  late TextEditingController _remarkCtrl;
  late final FocusNode _amtFocusNode;

  /// 小计金额是否被用户手动修改（对齐 Vue writeData 的 _amtManual）
  bool _amtManual = false;

  /// 程序性更新金额标志：避免 _syncAmt 回写文本时误标记手动修改
  bool _updatingAmt = false;

  // 单位/规格状态（对齐 Vue proDetails.vue cgpriceflag 逻辑）
  late String _currentUnit;
  late String _currentSize;
  late String _unitonlyid;
  late String _sizeonlyid;

  /// 单位可选条件（对齐 Vue edit.vue unit 列：productid 存在 && sizeonlyid 为空，
  /// 禁用状态随 sizeonlyid 动态重算，规格清空/切回原规格后单位自动解禁）
  bool get _unitCanSelect {
    final data = widget.productData;
    final productid = data['productid']?.toString() ?? data['prodid']?.toString() ?? '';
    return productid.isNotEmpty && _sizeonlyid.isEmpty;
  }

  /// 规格可选条件（对齐 Vue edit.vue size 列：specflag == 1 && unitonlyid 为空）
  bool get _sizeCanSelect {
    final data = widget.productData;
    final specflag = data['specflag']?.toString() ?? '';
    return specflag == '1' && _unitonlyid.isEmpty;
  }

  double get _packagenum =>
      double.tryParse(widget.productData['packagenum']?.toString() ?? '') ?? 1;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: widget.initialPrice.toStringAsFixed(2));
    final qty = MathUtils.formatDecimalNum(1, widget.initialQty);
    _qtyCtrl = TextEditingController(
      text: MathUtils.formatDecimal(1, qty),
    );
    _giftCtrl = TextEditingController(text: MathUtils.formatDecimal(1, widget.initialGiftQty));
    _jsQtyCtrl = TextEditingController(
      text: _packagenum > 0 ? MathUtils.formatDecimal(1, qty / _packagenum) : '0',
    );
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
    _amtManual = widget.initialAmtManual;
    final initAmt = widget.initialAmt ??
        MathUtils.formatDecimalNum(3, MathUtils.mul(widget.initialQty, widget.initialPrice));
    _amtCtrl = TextEditingController(text: MathUtils.formatDecimal(3, initAmt));
    _amtFocusNode = FocusNode();
    // 初始化单位/规格状态
    _currentUnit = widget.productData['unit']?.toString() ?? '';
    _currentSize = widget.productData['size']?.toString() ?? '';
    _unitonlyid = widget.productData['unitonlyid']?.toString() ?? '';
    _sizeonlyid = widget.productData['sizeonlyid']?.toString() ?? '';

    // 数量变化时同步件数
    _qtyCtrl.addListener(_syncJsQty);
    _jsQtyCtrl.addListener(_syncQtyFromJs);
    // 价格/数量变化 → 编辑时重置手动金额标记并重算 amt = qty × price（对齐 Vue writeData）
    _priceCtrl.addListener(_onCalcChanged);
    _qtyCtrl.addListener(_onCalcChanged);
    // 金额输入 → 标记手动修改；失焦 → 归一化 + 反算数量（对齐 Vue writeData key==amt）
    _amtCtrl.addListener(_onAmtChanged);
    _amtFocusNode.addListener(_onAmtBlur);
  }

  // ─── 金额联动（对齐 Vue edit.vue writeData）─────────────

  /// 价格/数量变化：编辑数量/单价重置手动金额标记（对齐 Vue writeData 开头
  /// v._amtManual = false），未手动修改时重算 amt = qty × price
  void _onCalcChanged() {
    if (_updatingAmt) return;
    if (_amtManual) {
      _amtManual = false;
      setState(() {});
    }
    _syncAmt();
  }

  /// 用户编辑金额 → 标记手动修改（对齐 Vue writeData key==amt 的 _amtManual）
  void _onAmtChanged() {
    if (_updatingAmt) return;
    _amtManual = true;
  }

  /// 金额失焦监听：提供失焦确认入口（对齐 Vue writeData key==amt 的 blur）
  void _onAmtBlur() {
    if (_amtFocusNode.hasFocus) return;
    _finalizeAmt();
  }

  /// 金额确认（失焦/回车/确定前）：归一化精度 + 反算数量 + 系统参数强制重算
  /// （对齐 Vue writeData key==amt：qty = amt / price；price 为 0 时 qty = 0）
  void _finalizeAmt() {
    if (!_amtManual) return;
    final amt = double.tryParse(_amtCtrl.text) ?? 0;
    _updatingAmt = true;
    _amtCtrl.text = MathUtils.formatDecimal(3, amt);
    _updatingAmt = false;
    // 反算数量 qty = amt / price（保留 2 位，对齐 Vue writeData key==amt；除零置 0 防 Infinity）
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final double qty = price == 0 ? 0 : MathUtils.divide(amt, price);
    _updatingAmt = true;
    _qtyCtrl.text = MathUtils.formatDecimal(2, qty);
    _updatingAmt = false;
    // 系统参数 cgAmountRecalculationflag==1：按反算后的 qty × price 强制重算 amt
    // （对齐 Vue writeData 收尾分支：反算在前、重算在后，与选择页 applyAmtRecalc 顺序一致）
    if (_loginParamInt('cgAmountRecalculationflag') == 1) {
      _amtManual = false;
      _syncAmt();
      setState(() {});
    }
  }

  /// 金额自动重算（对齐 Vue writeData：金额未手动修改时 amt = qty × price）
  void _syncAmt() {
    if (_amtManual) return;
    final q = double.tryParse(_qtyCtrl.text) ?? 0;
    final p = double.tryParse(_priceCtrl.text) ?? 0;
    _updatingAmt = true;
    _amtCtrl.text = MathUtils.formatDecimal(3, MathUtils.mul(q, p));
    _updatingAmt = false;
  }

  void _syncJsQty() {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final pn = _packagenum;
    final js = pn > 0 ? qty / pn : 0;
    _jsQtyCtrl.removeListener(_syncQtyFromJs);
    _jsQtyCtrl.text = MathUtils.formatDecimal(1, js);
    _jsQtyCtrl.addListener(_syncQtyFromJs);
  }

  void _syncQtyFromJs() {
    final js = double.tryParse(_jsQtyCtrl.text) ?? 0;
    final pn = _packagenum;
    final qty = js * pn;
    _qtyCtrl.removeListener(_syncJsQty);
    _qtyCtrl.text = MathUtils.formatDecimal(1, qty);
    _qtyCtrl.addListener(_syncJsQty);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _giftCtrl.dispose();
    _jsQtyCtrl.dispose();
    _amtCtrl.dispose();
    _amtFocusNode.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.productData;
    final String name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    final String barcode = data['barcode']?.toString() ?? data['selfbarcode']?.toString() ?? '';
    final double spVal = double.tryParse(
          data['saleprice']?.toString() ??
              data['retailprice']?.toString() ??
              data['sellprice']?.toString() ??
              '0',
        ) ??
        0;
    final String saleprice = spVal.toStringAsFixed(2);
    final String shelves = data['shelves']?.toString() ?? '';

    final ro = widget.readOnly;
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
            // 顶部拖拽条
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    ro ? '商品详情（只读）' : '商品详情',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            // 滚动内容
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
                          Text(
                            _currentUnit.isNotEmpty ? '$name（$_currentUnit）' : name,
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
                              Text('零售价：¥$saleprice',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              if (shelves.isNotEmpty) ...[
                                const SizedBox(width: 16),
                                Text('货架号：$shelves',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              ],
                            ],
                          ),
                          if (_currentSize.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('规格：$_currentSize',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFormField(
                      label: '进价',
                      controller: _priceCtrl,
                      isDecimal: true,
                      readOnly: ro,
                    ),
                    _buildDivider(),
                    _buildFormField(
                      label: '数量',
                      controller: _qtyCtrl,
                      isDecimal: true,
                      readOnly: ro,
                    ),
                    _buildDivider(),
                    _buildFormField(
                      label: '件数',
                      controller: _jsQtyCtrl,
                      isDecimal: true,
                      readOnly: ro,
                    ),
                    _buildDivider(),
                    _buildFormField(
                      label: '赠送数量',
                      controller: _giftCtrl,
                      readOnly: ro,
                    ),
                    _buildDivider(),
                    _buildAmtField(),
                    _buildDivider(),
                    // 单位（可点击选择，对齐 Vue proDetails.vue unit 字段）
                    _buildUnitSelectField(),
                    _buildDivider(),
                    // 规格（可点击选择，对齐 Vue proDetails.vue size 字段）
                    _buildSizeSelectField(),
                    _buildDivider(),
                    _buildFormField(
                      label: '备注',
                      controller: _remarkCtrl,
                      keyboardType: TextInputType.text,
                      maxLines: 2,
                      readOnly: ro,
                    ),
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
              child: ro
                  ? SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6B7280),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('关闭', style: TextStyle(fontSize: 15)),
                      ),
                    )
                  : Row(
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
                              // 金额确认（反算数量）后再取当前值（对齐 Vue writeData key==amt）
                              _finalizeAmt();
                              Navigator.pop(context, {
                                'price': double.tryParse(_priceCtrl.text) ?? 0.0,
                                'qty': double.tryParse(_qtyCtrl.text) ?? 0.0,
                                'giftqty': double.tryParse(_giftCtrl.text) ?? 0.0,
                                'amt': MathUtils.formatDecimalNum(
                                    3, double.tryParse(_amtCtrl.text) ?? 0.0),
                                '_amtManual': _amtManual,
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

  /// 小计金额字段（可编辑，对齐 Vue proDetails.vue amt 输入框：
  /// 手动修改时标记 _amtManual 并在确认后反算数量；未修改时自动按 qty × price 重算）
  Widget _buildAmtField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 80,
            child: Text('小计金额',
                style:
                    TextStyle(fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextField(
              controller: _amtCtrl,
              focusNode: _amtFocusNode,
              readOnly: widget.readOnly,
              enabled: !widget.readOnly,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE74C3C),
              ),
              onSubmitted: (_) => _finalizeAmt(),
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

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    bool isDecimal = false,
    TextInputType keyboardType = TextInputType.number,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
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
              maxLines: maxLines,
              readOnly: readOnly,
              keyboardType:
                  isDecimal ? const TextInputType.numberWithOptions(decimal: true) : keyboardType,
              inputFormatters:
                  isDecimal ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))] : null,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: readOnly ? const Color(0xFF6B7280) : const Color(0xFF111827),
              ),
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

  /// 单位选择字段（对齐 Vue proDetails.vue unit 字段）
  Widget _buildUnitSelectField() {
    final canSelect = _unitCanSelect && !widget.readOnly;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: canSelect ? () => _showExtendOptions('unit') : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            const SizedBox(
              width: 80,
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

  /// 规格选择字段（对齐 Vue proDetails.vue size 字段）
  Widget _buildSizeSelectField() {
    final canSelect = _sizeCanSelect && !widget.readOnly;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: canSelect ? () => _showExtendOptions('size') : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            const SizedBox(
              width: 80,
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
      'bsid': widget.bsid?.toString() ?? '',
      'itemtype': data['itemtype']?.toString() ?? '',
      'packageflag': data['packageflag']?.toString() ?? '',
      'specflag': data['specflag']?.toString() ?? '',
      'is_page': 1,
    };
    if (type == 'size') {
      params['counterid'] = '';
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

      // 字段映射
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

  /// 应用单位/规格选择结果（对齐 Vue cgorder/edit.vue unitConfirm / changeSize）
  ///
  /// 关键点：名称与 id 均无条件覆盖。默认单位/默认规格对应的 unitonlyid /
  /// sizeonlyid 为空串，切回原单位/原规格时必须清空旧值，_unitCanSelect /
  /// _sizeCanSelect 才能重新解禁对方字段（对齐 Vue unitSelect.vue 选中即
  /// emit、空值 emit ""）；旧实现的 isNotEmpty 守卫导致切回原规格时旧
  /// sizeonlyid 无法清空，单位字段保持卡死禁用
  void _applyExtendResult(String type, Map<String, dynamic> result) {
    setState(() {
      final data = widget.productData;
      if (type == 'unit') {
        // 名称/id 无条件覆盖，后端字段缺失时兜底空串
        _currentUnit = result['unit']?.toString() ?? result['_name']?.toString() ?? '';
        _unitonlyid = result['unitonlyid']?.toString() ?? result['_id']?.toString() ?? '';
        data['unit'] = _currentUnit;
        data['unitonlyid'] = _unitonlyid;
        // packagenum：选了非默认单位后设为 1
        // （对齐 Vue unitConfirm：if (unitonlyid != "") packagenum = 1）
        if (_unitonlyid.isNotEmpty) data['packagenum'] = 1;
        // 货架号同步（仅 unitConfirm）
        final sh = result['shelves']?.toString();
        if (sh != null) data['shelves'] = sh;
      } else {
        // 规格：名称/id 同样无条件覆盖，切回原规格时 sizeonlyid 为空，
        // 清空后 _unitCanSelect 重新为 true，单位字段恢复可选
        _currentSize = result['size']?.toString() ?? result['_name']?.toString() ?? '';
        _sizeonlyid = result['sizeonlyid']?.toString() ?? result['_id']?.toString() ?? '';
        data['size'] = _currentSize;
        data['sizeonlyid'] = _sizeonlyid;
        // packagenum：选了非默认规格后设为 1
        // （对齐 Vue changeSize：if (sizeonlyid != "") packagenum = 1）
        if (_sizeonlyid.isNotEmpty) data['packagenum'] = 1;
      }
      _applyPriceFields(result);
    });
  }

  /// 价格类字段联动（unitConfirm / changeSize 共用）：
  /// cgprice→price 及进价输入框、inprice/oldprice、批发价组、条码(sbarcode优先)/编码(scode优先)、零售价
  void _applyPriceFields(Map<String, dynamic> result) {
    final data = widget.productData;
    final cgprice = result['cgprice']?.toString();
    if (cgprice != null) {
      data['cgprice'] = cgprice;
      data['price'] = cgprice;
      _priceCtrl.text = double.tryParse(cgprice)?.toStringAsFixed(2) ?? cgprice;
    }
    final inprice = result['inprice']?.toString();
    if (inprice != null) data['inprice'] = inprice;
    final oldprice = result['oldprice']?.toString() ?? cgprice;
    if (oldprice != null) data['oldprice'] = oldprice;
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
      if (v != null) data[key] = v;
    }
    final pfprice = result['pfprice']?.toString() ?? result['pfprice1']?.toString();
    if (pfprice != null) data['pfprice'] = pfprice;
    final mprice = result['mprice']?.toString() ?? result['mprice1']?.toString();
    if (mprice != null) data['mprice'] = mprice;
    // 条码/编码更新（sbarcode / scode 优先）
    final nb = result['sbarcode']?.toString() ?? result['barcode']?.toString();
    if (nb != null) data['barcode'] = nb;
    final nc = result['scode']?.toString() ?? result['code']?.toString();
    if (nc != null) data['code'] = nc;
    // 零售价更新
    final nr = result['sellprice']?.toString() ?? result['retailprice']?.toString();
    if (nr != null && nr.isNotEmpty) {
      data['sellprice'] = nr;
      data['retailprice'] = nr;
    }
  }
}

/// 粘性表头委托
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
            // 审批意见
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
            // 备注/驳回原因
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
