import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_refbill.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/models/scan_settings.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/device_utils.dart';
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

enum _COAction { none, save, sign, delete, retsign, print, withdraw, stop }

class CgotherAddPage extends StatefulWidget {
  const CgotherAddPage({super.key, this.billData});

  final Map<String, dynamic>? billData;

  @override
  State<CgotherAddPage> createState() => _CgotherAddPageState();
}

class _CgotherAddPageState extends State<CgotherAddPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _buyerController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _supController = TextEditingController();
  final TextEditingController _outController = TextEditingController();
  final TextEditingController _validdateController = TextEditingController();
  final TextEditingController _refbillController = TextEditingController();

  // ---- PDA 扫码枪 ----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;

  int? _storeid;
  String? _storename;
  int? _storetype;

  /// 登录机构类型（对齐 Vue cgother/edit.vue isZyjmStore 取 userStore().store.storetype），
  /// 初始化时读取一次，不随收货机构选择/单据详情变化
  int? _loginStoretype;
  String? _buyerid;
  String? _buyername;
  String? _supid;
  String? _supname;
  String? _supselltype;
  int? _outsid;
  String? _outstorename;
  DateTime? _validdate;
  String? _refbillno;
  String? _refbillid;

  _COAction _submitAction = _COAction.none;
  bool _detailLoading = false;
  bool _isTipNotMasterProduct = true; // 非供货资格商品校验标志
  // 进价校验放行标记（对齐 Vue cgother/edit.vue isTipInprice / isTipDoubleInprice，
  // 用户弹窗确认后置 false 防止重复弹出）
  bool _isTipInprice = true; // 入库价和档案价不同（cgProductPriceNotSellPriceFlag）
  bool _isTipDoubleInprice = true; // 进价达原进价两倍（cgInPriceHeightSellPriceFlag）

  late ScanSettings _scanSettings;

  bool _isSelectMode = false;
  Set<int> _selectedIndices = {};

  // ---- 多级审批 ----
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  bool _billSign = true;
  String _userCode = '';
  String _userid = '';

  Map<String, dynamic>? _billData;
  String? _newBillid;

  // ---- 附件 ----
  List<Map<String, dynamic>> _fileLists = [];

  bool get _isEdit =>
      (_newBillid != null && _newBillid!.isNotEmpty) ||
      (widget.billData != null && (widget.billData!['billid']?.toString().isNotEmpty ?? false));
  bool get _isSigned => _billData?['signflag']?.toString() == '1';
  bool get _isRejected => _billData?['signflag']?.toString() == '2';
  bool get _isWithdrawPending => _billData?['reviewsignflag']?.toString() == '2';

  /// 是否为自营/加盟门店（storetype 1=自营, 2=加盟）
  /// 对齐 Vue cgother/edit.vue：`isZyjmStore = computed(() => store.storetype == 1 || store.storetype == 2)`，
  /// 基于【登录机构】类型判断，而非所选收货机构类型（_storetype），
  /// 避免选择直营/加盟门店作为收货机构后底部按钮被误隐藏
  bool get _isZyjmStore => _loginStoretype == 1 || _loginStoretype == 2;

  // =================== 多级审批 ===================
  bool get _isAdmin => _userCode == '1001';

  /// 表单是否可编辑（对齐 Vue bolHandle）
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

  /// 是否有反审核权限（当前用户曾在审批流中审批过）
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
    // 加载登录机构类型（对齐 Vue cgother/edit.vue isZyjmStore 取 userStore().store.storetype）：
    // 新增/编辑模式均需读取，且不得被后续收货机构选择覆盖
    try {
      final String loginStoreStr = SpUtil.getString(Constant.store) ?? '';
      if (loginStoreStr.isNotEmpty) {
        final Map<String, dynamic> loginStoreMap =
            jsonDecode(loginStoreStr) as Map<String, dynamic>;
        _loginStoretype = _parseIntFlexible(loginStoreMap, ['storetype']);
      }
    } catch (_) {}
    if (_isEdit) {
      _loadDetail();
    } else {
      _loadNewModeDefaults();
    }
  }

  void _loadNewModeDefaults() {
    _isTipNotMasterProduct = true; // 对齐 Vue：重置非主供货商校验标志
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeid = _parseIntFlexible(storeMap, ['id', 'storeid', 'bsid']);
        _storename = storeMap['name']?.toString();
        _storetype = _parseIntFlexible(storeMap, ['storetype']);
        _storeController.text = storeMap['name']?.toString() ?? '';

        // 配送中心默认值：如果是配送中心(storetype==3)且非总店，默认为当前 store
        final isPsStore = _storetype == 3;
        final spid = _parseIntFlexible(storeMap, ['spid']);
        final isStore = _storeid != null && spid != null && _storeid == spid;
        if (isPsStore && !isStore) {
          _outsid = _storeid;
          _outstorename = _storename;
          _outController.text = _storename ?? '';
        }
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

    // 收货期限默认值：当前日期 + cgGoodsExpireDay（从 loginParamResp 读取，
    // 未配置默认30天，对齐后台 cgother/edit.vue formDefault）
    int expireDay = 30;
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
        final d = int.tryParse(cfg['cgGoodsExpireDay']?.toString() ?? '');
        if (d != null && d > 0) expireDay = d;
      }
    } catch (_) {}
    final defaultDate = DateTime.now().add(Duration(days: expireDay));
    _validdate = defaultDate;
    _validdateController.text =
        '${defaultDate.year}-${defaultDate.month.toString().padLeft(2, '0')}-${defaultDate.day.toString().padLeft(2, '0')}';

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
    _storeController.dispose();
    _buyerController.dispose();
    _remarkController.dispose();
    _supController.dispose();
    _outController.dispose();
    _validdateController.dispose();
    _refbillController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  // =================== 加载单据详情 ===================
  void _loadDetail([Map<String, dynamic>? overrideParams]) {
    setState(() {
      _detailLoading = true;
      _isTipNotMasterProduct = true; // 对齐 Vue getInfo：重置非主供货商校验标志
    });
    final Map<String, dynamic> params =
        overrideParams ?? Map<String, dynamic>.from(widget.billData!);

    request(HttpApi.cgotherGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _storeController.text = data['storename']?.toString() ?? '';
          _buyerController.text = data['buyername']?.toString() ?? '';
          _remarkController.text = data['remark']?.toString() ?? '';
          _supController.text = data['supname']?.toString() ?? '';
          _outController.text = data['outstorename']?.toString() ?? '';
          _refbillController.text = data['refbillno']?.toString() ?? '';
          _storeid = _parseIntFlexible(data, ['bsid', 'storeid']);
          _storename = data['storename']?.toString();
          _storetype = _parseIntFlexible(data, ['storetype']);
          _buyerid = data['buyerid']?.toString();
          _buyername = data['buyername']?.toString();
          _supid = data['billsupid']?.toString() ?? data['supid']?.toString();
          _supname = data['supname']?.toString();
          _supselltype = data['supselltype']?.toString();
          _outsid = _parseIntFlexible(data, ['outsid']);
          _outstorename = data['outstorename']?.toString();
          _refbillno = data['refbillno']?.toString();
          _refbillid = data['refbillid']?.toString();

          // 多级审批数据
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);

          // 附件
          final files = data['fileLists'];
          if (files is List) {
            _fileLists = files
                .whereType<Map<dynamic, dynamic>>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }

          // 收货期限
          final vdStr = data['validdate']?.toString() ?? '';
          if (vdStr.isNotEmpty) {
            try {
              _validdate = DateTime.parse(vdStr);
              _validdateController.text =
                  '${_validdate!.year}-${_validdate!.month.toString().padLeft(2, '0')}-${_validdate!.day.toString().padLeft(2, '0')}';
            } catch (_) {}
          }

          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
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

  // =================== 提交保存 ===================
  Future<void> _submit({bool withSign = false}) async {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('011503', showTip: false)) {
        Toast.show('你无权编辑直配订单，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('011502', showTip: false)) {
        Toast.show('你无权新增直配订单，请在后台修改权限');
        return;
      }
    }
    if (_storeid == null) {
      Toast.show('请选择收货机构');
      return;
    }
    if ((_supid ?? '').isEmpty) {
      Toast.show('请选择供应商');
      return;
    }
    if (_outsid == null) {
      Toast.show('请选择配送中心');
      return;
    }
    if (_validdate == null) {
      Toast.show('请选择收货期限');
      return;
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

    for (final row in submitItems) {
      final qty = double.tryParse(row.qtyController.text) ?? 0;
      if (qty == 0) {
        Toast.show('请填写数量');
        return;
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
            _submit(withSign: withSign);
          });
          return;
        }
      }
    }

    // 进价不一致 / 进价两倍差校验（对齐 Vue cgother/edit.vue save：
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
        _submit(withSign: withSign);
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
    } else {
      // 新增模式默认参数（对齐后台 cgother/edit.vue formDefault：
      // name/validdate/signflag/billtype:"1"/supselltype/fileLists）
      params = {
        'name': '',
        'signflag': 0,
        'billtype': '1',
        'supselltype': '',
      };
    }

    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt);
    params['detaillist'] = detaillist;
    params['remark'] = _remarkController.text.trim();
    params['bsid'] = _storeid ?? '';
    params['storename'] = _storename ?? '';
    params['buyerid'] = _buyerid ?? '';
    params['buyername'] = _buyername ?? '';
    // 对齐 Vue edit.vue save：cloneDeep(form) 含 supid，后端读取 supid，
    // 仅发 billsupid 会导致后端报“未选择供应商”，故两者同步发送
    params['billsupid'] = _supid ?? '';
    params['supid'] = _supid ?? '';
    params['supname'] = _supname ?? '';
    params['supselltype'] = _supselltype ?? '';
    params['outsid'] = _outsid ?? '';
    params['outstorename'] = _outstorename ?? '';
    params['billtype'] = '1';
    params['fileLists'] = _fileLists;
    params['validdate'] =
        '${_validdate!.year}-${_validdate!.month.toString().padLeft(2, '0')}-${_validdate!.day.toString().padLeft(2, '0')}';
    if (_refbillid != null && _refbillid!.isNotEmpty) {
      params['refbillid'] = _refbillid;
      params['refbillno'] = _refbillno ?? '';
    }

    request(HttpApi.cgotherSave, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '保存成功');
      _isTipNotMasterProduct = true; // 对齐 Vue：保存成功后重置
      _isTipInprice = true; // 对齐 Vue save finally：重置进价校验放行标记
      _isTipDoubleInprice = true;
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
        if (withSign) {
          _doSignAfterSave(retData);
        }
      } else {
        if (!_isEdit) Navigator.pop(context, true);
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
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

  /// 审核（已保存的单据直接审核，多级审批时弹出审批弹窗）
  Future<void> _sign() async {
    if (!PermissionUtils.checkPermission('011505', showTip: false)) {
      Toast.show('你无权审核直配订单，请在后台修改权限');
      return;
    }
    if (_billData == null) return;

    if (_reviewFlowUsers.isNotEmpty) {
      final approvalResult = await _showApprovalDialog();
      if (approvalResult == null || !mounted) return;
      _billData?['reviewsignflag'] = approvalResult['reviewsignflag'];
      _billData?['reviewremark'] = approvalResult['reviewremark'];
      _doSign();
      return;
    }

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

  /// 执行审核操作（对齐 Vue doSign）
  void _doSign() {
    if (_billData == null) return;
    final params = Map<String, dynamic>.from(_billData!);
    params['signflag'] = 1;
    params['billtype'] = '1';
    params['reviewremark'] = _billData?['reviewremark']?.toString() ?? '';
    final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
    if (reviewsignflag != 2 && reviewsignflag != 0) {
      params['reviewsignflag'] = 1;
    }
    setState(() => _submitAction = _COAction.sign);
    request(HttpApi.cgotherSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 反审核
  Future<void> _retsign() async {
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

    setState(() => _submitAction = _COAction.retsign);
    // 构造完整反审核参数（对齐 Vue fsignFn 发送 query.value 完整单据对象）：
    // 对后端强依赖的关键字段做兜底补充，避免写入审批流表时出现 NULL
    final params = Map<String, dynamic>.from(_billData!);
    params['billtype'] = '1';
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
      params['billtypeid'] = '0504';
    }
    final dl = params['detaillist'];
    if (dl is! List || dl.isEmpty) {
      params['detaillist'] = _buildSubmitDetailList();
    }
    request(HttpApi.cgotherRetsign, params).then((result) {
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

  /// 撤回操作
  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('011506', showTip: false)) {
      Toast.show('你无权反审核直配订单，请在后台修改权限');
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
    params['billtype'] = '1';
    request(HttpApi.cgotherSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 打印单据（对齐 Vue menuid: '050401'）
  Future<void> _print() async {
    if (_billData == null) return;
    setState(() => _submitAction = _COAction.print);
    request(HttpApi.cgotherPrint, {
      'menuid': '050401',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 终止单据（对齐 Vue stopBill）
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
    params['billtype'] = '1';
    request(HttpApi.cgotherStop, params).then((result) {
      if (!mounted) return;
      Toast.show('终止成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _COAction.none);
    });
  }

  /// 新增模式：初始化审批签字按钮可见性
  void _initSignUserBtn() {
    if (_isAdmin) return;
    if (!_isEdit && _storeid != null) {
      request(HttpApi.reviewTypeConfigGetNewBillSignUser, {
        'billtypeid': '0504',
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

  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('011504', showTip: false)) {
      Toast.show('你无权删除直配订单，请在后台修改权限');
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
    final params = Map<String, dynamic>.from(_billData!);
    params['billtype'] = '1';
    request(HttpApi.cgotherDelBill, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '删除成功');
      Navigator.pop(context, true);
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
      Toast.show('请先选择收货机构');
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
          ..._buildMergData(),
        });

        if (!mounted) return;
        final data = searchResult['data'];
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
    if (unmatched.isNotEmpty) {
      Toast.show('已匹配 $matchCount 项，未匹配：${unmatched.join("、")}');
    } else {
      Toast.show('已添加 $matchCount 项商品');
    }
  }

  // =================== 汇总 ===================
  String get _totalQty {
    double sum = 0;
    for (final row in _items) {
      sum += double.tryParse(row.qtyController.text) ?? 0;
    }
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
      // ===== oldprice 计算（对齐 Vue cgother/edit.vue handleProperty）=====
      // Vue 源码逻辑（edit.vue handleProperty）：
      //   未审核（signflag === 0）：oldprice = inprice || Number(oldprice)
      //   已审核：oldprice = Number(oldprice) || cgprice || 0
      // APP 端在此基础上扩展兜底链：末级回退当前单价（price）再回退 0，
      // 保证 oldprice 恒为有效数字，防止后端字段缺失时传 NULL，
      // 导致后端审核单据时收货明细表 oldprice 列 INSERT 失败
      final rawInprice = _parseNumField(item['inprice']);
      final rawOldprice = _parseNumField(item['oldprice']);
      final rawCgprice = _parseNumField(item['cgprice']);
      // 取值优先级：已审核 → oldprice → cgprice → 当前单价；
      // 未审核（含已驳回重新编辑）→ inprice → oldprice → cgprice → 当前单价
      final candidates = _isSigned
          ? <double>[rawOldprice, rawCgprice, price]
          : <double>[rawInprice, rawOldprice, rawCgprice, price];
      double oldpriceVal = 0;
      for (final candidate in candidates) {
        if (candidate != 0) {
          oldpriceVal = candidate;
          break;
        }
      }
      item['oldprice'] = oldpriceVal;
      return item;
    }).toList();
  }

  /// 数值字段防御性解析：null/空串/含空白的非法字符串统一回退 0
  /// （对齐 Vue Number(x) || 0 的兜底语义，避免后端字段缺失导致计算异常）
  static double _parseNumField(dynamic value) {
    if (value == null) return 0;
    return double.tryParse(value.toString().trim()) ?? 0;
  }

  /// 供应商/机构切换后刷新商品价格（对齐 Vue updateCgPrice）
  /// 使用批量 API /cgstockin/updateCgPrice 一次性更新所有商品价格
  Future<void> _refreshProductPrices() async {
    if (_items.isEmpty) return;

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
    if (detaillist.isEmpty) return;

    final params = <String, dynamic>{
      'bsid': _outsid ?? _storeid ?? '', // 直配用配送中心
      'supid': _supid ?? '',
      'counterid': '',
      'detaillist': detaillist,
    };
    // 编辑模式：带入已有单据信息（对齐 Vue cloneDeep(form)）
    if (_billData != null) {
      params['billid'] = _billData!['billid']?.toString() ?? _newBillid ?? '';
      params['billtypeid'] = _billData!['billtypeid']?.toString() ?? '0504';
    } else if (_newBillid != null && _newBillid!.isNotEmpty) {
      params['billid'] = _newBillid;
    }
    debugPrint(
        '[updateCgPrice-cgother] bsid=${params['bsid']}, supid=${params['supid']}, billid=${params['billid']}, items=${detaillist.length}');

    try {
      final result = await request(HttpApi.purchaseUpdateCgPrice, params);
      if (!mounted) return;

      final responseData = result['data'];
      final list = (responseData is List ? responseData : responseData?['list']) as List? ?? [];

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

      setState(() {
        _items.removeWhere((row) {
          final prodId = row.prodid ?? '';
          if (prodId.isEmpty) return false;
          final unitonlyid = row.rawData?['unitonlyid']?.toString() ?? '';
          final sizeonlyid = row.rawData?['sizeonlyid']?.toString() ?? '';
          final key = '${prodId}_${unitonlyid}_$sizeonlyid';
          return !priceMap.containsKey(key);
        });

        for (final row in _items) {
          final prodId = row.prodid ?? '';
          if (prodId.isEmpty) continue;
          final unitonlyid = row.rawData?['unitonlyid']?.toString() ?? '';
          final sizeonlyid = row.rawData?['sizeonlyid']?.toString() ?? '';
          final key = '${prodId}_${unitonlyid}_$sizeonlyid';
          final item = priceMap[key];
          if (item == null) continue;

          final cgprice = double.tryParse(item['cgprice']?.toString() ?? '') ?? 0;
          final price =
              cgprice != 0 ? cgprice : (double.tryParse(item['price']?.toString() ?? '') ?? 0);
          row.priceController.text = MathUtils.formatDecimal(2, price);
          row.stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;

          final qty = MathUtils.formatDecimalNum(1, double.tryParse(row.qtyController.text) ?? 0);
          row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
          row.amtController.text = MathUtils.formatDecimal(3, row.amt);
          if (row.rawData != null) row.rawData!['amt'] = row.amt;
        }
      });
    } catch (e) {
      debugPrint('[updateCgPrice] 刷新价格失败: $e');
    }
  }

  /// 构建商品查询参数（对齐 Vue mergDataFn - 直配 pstype=2, storeid 用配送中心）
  Map<String, dynamic> _buildMergData() {
    return {
      'stockflag': 1,
      'storeid': _outsid ?? _storeid ?? '',
      'counterid': '',
      'cgpriceflag': 1,
      'billsupid': _supid ?? '',
      'weekmonthflag': 1,
      'itemstatusin': '1,2',
      'itemtypenot': '5,8',
      'itemstatus': '1,2',
      'pstype': 2,
    };
  }

  bool get _readOnly => _isEdit && !_bolHandle;

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
          _isEdit ? (_isSigned ? '直配订单详情' : (_isRejected ? '直配订单详情' : '修改直配订单')) : '新增直配订单',
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

  // =================== 粘性表头 ===================
  static const double _stickyScanHeight = 68.0;
  static const double _stickyTitleHeight = 40.0;
  static const double _stickyColumnHeight = 36.0;
  static const double _stickyMinExtent = _stickyTitleHeight + _stickyColumnHeight;
  static const double _stickyMaxExtent = _stickyScanHeight + _stickyMinExtent;

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
              if (!_isSigned && !_scanSettings.showInfraredInput)
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _CgotherStickyHeaderDelegate(state: this),
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
                        onChanged: () => setState(() {}),
                        extBsid: _storeid?.toString(),
                        extBillsupid: _supid,
                        extPstype: 2,
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
    return _isEdit ? body : Form(key: _formKey, child: body);
  }

  Widget _buildStickyHeader() {
    return Align(
      alignment: Alignment.topCenter,
      child: ColoredBox(
        color: const Color(0xFFF5F5F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 对齐 Vue cgother/edit.vue：扫描/选品入口受 bolHandle && !isZyjmStore 门控
            if (!_isSigned && !_isZyjmStore && _scanSettings.showInfraredInput) ...[
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
                          if (!_isSigned && !_isZyjmStore) ...[
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
                            // TODO: 语音识别按钮暂时隐藏，后续可重新启用
                            if (false) ...[
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: _voiceRecognition,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.mic, size: 16, color: Color(0xFF006EFF)),
                                    SizedBox(width: 2),
                                    Text('语音',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF006EFF),
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],
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
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
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
      ),
    );
  }

  Widget _buildBillStatusWidget() {
    final data = _billData ?? {};
    final String billno = data['billno']?.toString() ?? '-';
    final String createtime = data['createtime']?.toString() ?? '-';
    final String buyername = data['buyername']?.toString() ?? '';
    final String signflag = data['signflag']?.toString() ?? '';

    String statusLabel = '待审核';
    Color statusColor = const Color(0xFFD54B5A);
    if (signflag == '1') {
      statusLabel = '已审核';
      statusColor = const Color(0xFF00A870);
    } else if (signflag == '2') {
      statusLabel = '已驳回';
      statusColor = const Color(0xFFFF9900);
    }

    return _buildCard(
      title: '单号：$billno',
      titleRight: Text(statusLabel,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
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

  /// 审核日志卡片
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
        _buildReadonlyField(label: '收货机构', value: _storeController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '供应商', value: _supController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '配送中心', value: _outController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '收货期限', value: _validdateController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        if (_refbillController.text.isNotEmpty) ...[
          _buildReadonlyField(label: '要货单据', value: _refbillController.text),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
        ],
        _buildReadonlyField(label: '经手人', value: _buyerController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '备注', value: _remarkController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildAttachButton(),
      ],
    );
  }

  /// 对齐 PC 后台 cgother/edit.vue restsid：
  /// 收货机构/配送中心选择后若两者相同（如同时为总部），清空配送中心并警告
  void _restsid() {
    if (_storeid != null && _storeid == _outsid) {
      setState(() {
        _outsid = null;
        _outstorename = null;
        _outController.text = '';
      });
      Toast.show('机构和配送中心不能同时为总部！');
    }
  }

  Widget _buildBillInfoEditable() {
    return Column(
      children: [
        SelectFieldItem(
          label: '收货机构',
          required: true,
          value: _storeController.text,
          onTap: () async {
            final oldStoreid = _storeid;
            // 对齐后台 cgother/edit.vue 收货机构 store-form-item merge-data：
            // supflag:1, stopflag:0, storetypes:[0,1,2]（不含配送中心类型 3）
            final result = await SelectStorePage.show(
              context,
              initialSelectedId: _storeid?.toString(),
              storetypes: const [0, 1, 2],
              supflag: '1',
              stopflag: '0',
            );
            if (result != null && mounted) {
              setState(() {
                _storeid = int.tryParse(result['storeid']?.toString() ?? '');
                _storename = result['storename']?.toString();
                _storetype = int.tryParse(result['storetype']?.toString() ?? '');
                _storeController.text = result['storename']?.toString() ?? '';
              });
              _restsid(); // 对齐 Vue：机构确认后校验不能与配送中心同为总部
              if (oldStoreid != _storeid) _refreshProductPrices();
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '供应商',
          required: true,
          value: _supController.text,
          onTap: () async {
            final oldSupid = _supid;
            final result = await SelectSupplierPage.show(context, initialSelectedId: _supid);
            if (result != null && mounted) {
              setState(() {
                _supid = result['supid']?.toString() ?? '';
                // 对齐 Vue selectSupFn：只保存供应商名称，不拼接编号
                _supname = result['name']?.toString() ?? result['supname']?.toString() ?? '';
                _supselltype = result['selltype']?.toString();
                _supController.text = _supname ?? '';
              });
              if (oldSupid != _supid) _refreshProductPrices();
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '配送中心',
          required: true,
          value: _outController.text,
          onTap: () async {
            final oldOutsid = _outsid;
            // 对齐后台 cgother/edit.vue 配送中心 store-form-item merge-data：
            // supflag:1, stopflag:0, storetypes:[0,3], applysid（按收货机构过滤其下属配送中心）
            final result = await SelectStorePage.show(
              context,
              initialSelectedId: _outsid?.toString(),
              storetypes: const [0, 3],
              supflag: '1',
              stopflag: '0',
              applysid: SelectStorePage.psCenterApplysid(_storeid),
            );
            if (result != null && mounted) {
              setState(() {
                _outsid = int.tryParse(result['storeid']?.toString() ?? '');
                _outstorename = result['storename']?.toString();
                _outController.text = result['storename']?.toString() ?? '';
              });
              _restsid(); // 对齐 Vue：配送中心确认后校验不能与机构同为总部
              if (oldOutsid != _outsid) _refreshProductPrices();
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '收货期限',
          required: true,
          value: _validdateController.text,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _validdate ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
            );
            if (picked != null && mounted) {
              setState(() {
                _validdate = picked;
                _validdateController.text =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '要货单据',
          value: _refbillController.text,
          onTap: _onTapRefbill,
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '经手人',
          value: _buyerController.text,
          onTap: () async {
            final result = await SelectBuyerPage.show(context, initialSelectedId: _buyerid);
            if (result != null && mounted) {
              setState(() {
                _buyerid = result['buyerid']?.toString();
                _buyername = result['buyername']?.toString();
                _buyerController.text = result['buyername']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildField(
          controller: _remarkController,
          label: '备注',
          hint: '请输入备注信息',
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildAttachButton(),
      ],
    );
  }

  // =================== 要货单据选择（对齐 Vue jumpPge + getYhInfo） ===================
  Future<void> _onTapRefbill() async {
    // 前置校验（对齐 Vue jumpPge）
    if (_storeid == null) {
      Toast.show('请选择收货机构');
      return;
    }
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请选择供应商');
      return;
    }
    if (_outsid == null) {
      Toast.show('请选择配送中心');
      return;
    }
    if (_validdate == null) {
      Toast.show('请选择收货期限');
      return;
    }

    // 有商品时弹出确认（对齐 Vue：选择要货申请单会清空当前商品）
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
      if (confirm != true || !mounted) return;
    }

    // 打开要货申请单选择页（对齐 Vue navPath chain/enquiry/search）
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectRefbillPage(
          customTypes: const [
            {
              'value': 10,
              'label': '要货申请单',
              'path': HttpApi.yhorderFindList,
              'infoPath': HttpApi.yhorderGetInfo
            },
          ],
          extraListParams: {
            'outsid': _outsid,
            'insid': _storeid,
            'outstorename': _outstorename ?? '',
            'hideoutdateflag': 1,
          },
          extraInfoParams: const {
            'cgflag': 1,
            'pstype': 2,
          },
        ),
      ),
    );
    if (result == null || !mounted) return;
    final info = result['info'];
    if (info is! Map<String, dynamic>) return;
    _fillItemsFromRefbill(info, result);
  }

  /// 填充要货申请单数据（对齐 Vue getYhInfo）
  void _fillItemsFromRefbill(Map<String, dynamic> info, Map<String, dynamic> refResult) {
    setState(() {
      _refbillno = info['billno']?.toString() ?? refResult['refbillno']?.toString() ?? '';
      _refbillid = info['billid']?.toString() ?? refResult['refbillid']?.toString() ?? '';
      _refbillController.text = _refbillno ?? '';

      // 填充基本信息（对齐 Vue getYhInfo 字段映射）
      final bsid = _parseIntFlexible(info, ['insid', 'bsid', 'storeid']);
      if (bsid != null) {
        _storeid = bsid;
        _storename = info['instorename']?.toString() ?? info['storename']?.toString();
        _storeController.text = _storename ?? '';
      }
      final outsid = _parseIntFlexible(info, ['outsid']);
      if (outsid != null) {
        _outsid = outsid;
        _outstorename = info['outstorename']?.toString();
        _outController.text = _outstorename ?? '';
      }
      if (info['remark']?.toString().isNotEmpty ?? false) {
        _remarkController.text = info['remark'].toString();
      }

      // 填充明细（对齐 Vue：filter pstype==2, 计算 jsqty, presentqty=0, camt）
      final allList = info['detaillist'] as List? ?? [];
      final list = allList.where((v) {
        if (v is! Map) return false;
        final pstype = int.tryParse(v['pstype']?.toString() ?? '') ?? 0;
        return pstype == 2;
      }).toList();

      for (final row in _items) {
        row.dispose();
      }
      _items.clear();
      for (final v in list) {
        if (v is! Map) continue;
        final c = Map<String, dynamic>.from(v);

        // 计算 jsqty = qty / packagenum（对齐 Vue）
        final qty = double.tryParse(c['qty']?.toString() ?? '') ?? 0;
        final packagenum = double.tryParse(c['packagenum']?.toString() ?? '') ?? 1;
        final jsqty = double.parse(
            MathUtils.formatDecimal(1, MathUtils.divide(qty, packagenum > 0 ? packagenum : 1)));
        c['jsqty'] = jsqty;
        c['presentqty'] = 0;

        // 计算 camt = sellamt - amt（对齐 Vue）
        final sellamt = double.tryParse(c['sellamt']?.toString() ?? '') ?? 0;
        final amt = double.tryParse(c['amt']?.toString() ?? '') ?? 0;
        c['camt'] = MathUtils.formatDecimal(3, MathUtils.subtract(sellamt, amt));

        // handleProperty 对齐 Vue
        final cgprice = double.tryParse(c['cgprice']?.toString() ?? '') ?? 0;
        final oldPrice = double.tryParse(c['price']?.toString() ?? '') ?? 0;
        final price = cgprice != 0 ? cgprice : oldPrice;
        c['price'] = double.parse(MathUtils.formatDecimal(2, price));

        final row = _DetailRow();
        row.prodid = c['prodid']?.toString() ?? c['productid']?.toString() ?? '';
        row.barcode = c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
        row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
        row.qtyController.text = MathUtils.formatDecimal(1, qty);
        row.priceController.text = MathUtils.formatDecimal(2, price);
        row.amt = MathUtils.formatDecimalNum(3, amt);
        row.amtController.text = row.amt!.toStringAsFixed(3);
        row.rawData = c;
        _items.add(row);
      }
    });
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
          if (_isEdit && !_isSigned) _buildEditUnsignedButtons(),
          if (_isEdit && _isSigned) _buildEditSignedButtons(),
          if (!_isEdit) _buildNewBillButtons(),
        ],
      ),
    );
  }

  /// 编辑模式 - 待审核/已驳回：更多(删除/打印) + 保存 + 审核 + 撤回
  Widget _buildEditUnsignedButtons() {
    final bool isLoading = _submitAction != _COAction.none;
    final buttons = <Widget>[];

    if (!_isWithdrawPending && _bolHandleTT) {
      buttons.add(PopupMenuButton<String>(
        onSelected: (val) {
          if (val == 'delete') _delBill();
          if (val == 'print') _print();
        },
        offset: const Offset(0, -120),
        itemBuilder: (ctx) => [
          // 对齐 Vue cgother/edit.vue 删除条件：signflag != 2 && bolHandleTT && !isZyjmStore
          if (!_isRejected && !_isZyjmStore)
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

    // 对齐 Vue cgother/edit.vue：编辑态保存/审核均要求 !isZyjmStore
    final showSaveAndAudit = !_isRejected &&
        !_isWithdrawPending &&
        (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT)) &&
        !_isZyjmStore;
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

    // 对齐 Vue cgother/edit.vue：反审核 bolHandleTTT && !isZyjmStore
    if (_bolHandleTTT && !_isZyjmStore) {
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

    // 终止按钮（对齐 Vue cgother/edit.vue：!isZyjmStore）
    if (!_isZyjmStore) {
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
      child: ElevatedButton(
        onPressed: isLoading ? null : () => _submit(),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF006EFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _submitAction == _COAction.save
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    ));

    // 对齐 Vue cgother/edit.vue：保存并审核 v-if="billSign && !isZyjmStore"
    if (_billSign && !_isZyjmStore) {
      buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: isLoading ? null : () => _submit(withSign: true),
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
                Text('全选 (${_selectedIndices.length}/${_items.length})',
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
            child: const Text('删除选中', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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

  // =================== 商品选择与扫码 ===================
  /// 构建选择页 selectList：将当前明细行转换为选择页所需的预选中格式
  /// 包含 productid、qty、price 等字段，对齐小程序 selectProduct.vue selectList 参数
  List<Map<String, dynamic>> _buildSelectList() {
    return _items.map((row) {
      final raw = row.rawData;
      final map = raw != null ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      map['productid'] = row.prodid ?? map['prodid'] ?? '';
      map['qty'] = double.tryParse(row.qtyController.text) ?? 1;
      map['giftqty'] = double.tryParse(map['giftqty']?.toString() ?? '0') ?? 0;
      map['price'] = double.tryParse(row.priceController.text) ?? 0;
      map['amt'] = row.amt ?? 0;
      map['unit'] = map['unit']?.toString() ?? '';
      map['size'] = map['size']?.toString() ?? '';
      return map;
    }).toList();
  }

  Future<void> _selectProducts({String? initialKeyword, FocusNode? returnFocusNode}) async {
    if (_storeid == null) {
      Toast.show('请先选择收货机构');
      return;
    }
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          storeid: _outsid ?? _storeid,
          mergData: _buildMergData(),
          selectList: _buildSelectList(),
          paramJust: const ['qty', 'jsqty', 'presentqty', 'price', 'amt', 'unit', 'size', 'remark'],
          initialKeyword: initialKeyword,
        ),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        for (final prod in result) {
          final prodId = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
          // 复合去重键对齐后台 ROW_KEYS：productid + unitonlyid + sizeonlyid，
          // 同一商品不同包装/规格视为不同行（切换单位后再选品不会覆盖已有行）
          final prodUnit = prod['unitonlyid']?.toString() ?? '';
          final prodSize = prod['sizeonlyid']?.toString() ?? '';
          final existing = _items.indexWhere((r) =>
              r.prodid == prodId &&
              (r.rawData?['unitonlyid']?.toString() ?? '') == prodUnit &&
              (r.rawData?['sizeonlyid']?.toString() ?? '') == prodSize);
          if (existing >= 0) {
            final oldQty = double.tryParse(_items[existing].qtyController.text) ?? 0;
            final addQty = double.tryParse(prod['qty']?.toString() ?? '1') ?? 1;
            _items[existing].qtyController.text = MathUtils.formatDecimal(1, oldQty + addQty);
            // 同步选择页返回的新价格（用户可能修改了价格，否则统计栏仍按旧价计算）
            // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
            final syncCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
            final newPrice = syncCgprice != 0
                ? syncCgprice
                : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
            if (newPrice > 0) {
              _items[existing].priceController.text = MathUtils.formatDecimal(2, newPrice);
              if (_items[existing].rawData != null) {
                _items[existing].rawData!['price'] = newPrice;
              }
            }
            // 对齐 Vue writeData：数量变化后重算 amt 并同步显示
            _recalcRow(_items[existing]);
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
            // 优先使用选择页返回的 amt（选择页可能手动修改小计金额，对齐 instore）
            final prodAmt = prod['amt']?.toString();
            if (prodAmt != null && prodAmt.isNotEmpty) {
              row.amt = MathUtils.formatDecimalNum(3, double.tryParse(prodAmt) ?? row.amt ?? 0);
            }
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
      Toast.show('请先选择收货机构');
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

  void _handleScannedBarcode(String code, {FocusNode? returnFocusNode}) {
    if (code.trim().isEmpty) return;
    if (_storeid == null) {
      Toast.show('请先选择收货机构');
      return;
    }

    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;

    request(HttpApi.productGetList, {
      'scancode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      ..._buildMergData(),
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
        _selectProducts(initialKeyword: searchCode, returnFocusNode: returnFocusNode);
        return;
      }
      final prod = primary ?? list.first as Map<String, dynamic>;
      final prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
      final barcode = prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? '';
      // 复合去重键对齐后台 ROW_KEYS：productid + unitonlyid + sizeonlyid，同一商品不同包装/规格视为不同行
      final unitonlyid = prod['unitonlyid']?.toString() ?? '';
      final sizeonlyid = prod['sizeonlyid']?.toString() ?? '';
      final existing = _items.indexWhere((r) =>
          r.prodid == prodid &&
          (r.rawData?['unitonlyid']?.toString() ?? '') == unitonlyid &&
          (r.rawData?['sizeonlyid']?.toString() ?? '') == sizeonlyid);

      setState(() {
        if (existing >= 0) {
          final oldQty = double.tryParse(_items[existing].qtyController.text) ?? 0;
          if (scaleInfo?.type == 'weight') {
            _items[existing].qtyController.text =
                MathUtils.formatDecimal(1, scaleInfo!.qty ?? oldQty + 1);
          } else if (scaleInfo?.type == 'amount') {
            final price = double.tryParse(_items[existing].priceController.text) ?? 0;
            if (price > 0) {
              _items[existing].qtyController.text =
                  MathUtils.formatDecimal(1, (scaleInfo!.amount ?? 0) / price);
            } else {
              _items[existing].qtyController.text = MathUtils.formatDecimal(1, oldQty + 1);
            }
          } else {
            _items[existing].qtyController.text = MathUtils.formatDecimal(1, oldQty + 1);
          }
          // 对齐 Vue writeData：数量变化后重算 amt 并同步显示
          _recalcRow(_items[existing]);
        } else {
          double qty = 1;
          if (scaleInfo?.type == 'weight') {
            qty = scaleInfo!.qty ?? 1;
          } else if (scaleInfo?.type == 'amount') {
            // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
            final scaleCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
            final price = scaleCgprice != 0
                ? scaleCgprice
                : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
            if (price > 0) {
              qty = (scaleInfo!.amount ?? 0) / price;
            }
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

      if (returnFocusNode != null && mounted) {
        returnFocusNode.requestFocus();
      }
    }).catchError((_) {
      if (mounted) Toast.show('查询商品失败');
    });
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

  /// 附件按钮行（布局参数与 SelectFieldItem 等表单字段一致：
  /// 标签宽 80、字号 14、行高 24 + 上下 12，右箭头同款 chevron）
  Widget _buildAttachButton() {
    return GestureDetector(
      onTap: () async {
        final result = await AttachPage.show(
          context,
          fileLists: _fileLists,
          menuid: '050401',
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
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : '-',
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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

// =================== 粘性表头代理 ===================
class _CgotherStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CgotherStickyHeaderDelegate({required this.state});
  final _CgotherAddPageState state;

  @override
  double get minExtent => _CgotherAddPageState._stickyMinExtent;

  @override
  double get maxExtent =>
      (state._isSigned || state._isZyjmStore || !state._scanSettings.showInfraredInput)
          ? _CgotherAddPageState._stickyMinExtent
          : _CgotherAddPageState._stickyMaxExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader();
  }

  @override
  bool shouldRebuild(covariant _CgotherStickyHeaderDelegate oldDelegate) => true;
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

// =================== 商品详情弹窗（含单位/规格选择） ===================
class _ProDetailSheet extends StatefulWidget {
  const _ProDetailSheet({
    required this.productData,
    required this.initialPrice,
    required this.initialQty,
    this.extBsid,
    this.extBillsupid,
    this.extPstype,
  });
  final Map<String, dynamic> productData;
  final double initialPrice;
  final double initialQty;

  /// 页面级上下文（对齐 Vue unit-form-item mergeData：bsid/billsupid/pstype）
  final String? extBsid;
  final String? extBillsupid;
  final int? extPstype;

  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;

  late String _currentUnit;
  late String _currentSize;
  late String _unitonlyid;
  late String _sizeonlyid;

  /// 单位可选条件（对齐 Vue edit.vue unit 列：
  /// :bolHandle="bolHandle && row.productid && !row.sizeonlyid"，
  /// 禁用状态随 sizeonlyid 动态重算，规格清空/切回原规格后单位自动解禁）
  bool get _unitCanSelect {
    final data = widget.productData;
    final productid = data['productid']?.toString() ?? data['prodid']?.toString() ?? '';
    return productid.isNotEmpty && _sizeonlyid.isEmpty;
  }

  /// 规格可选条件（对齐 Vue edit.vue size 列：v-if="row.specflag == 1 && !row.unitonlyid"）
  bool get _sizeCanSelect {
    final data = widget.productData;
    final specflag = data['specflag']?.toString() ?? '';
    return specflag == '1' && _unitonlyid.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: widget.initialPrice.toStringAsFixed(2));
    final qty = widget.initialQty;
    _qtyCtrl = TextEditingController(
      text: qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2),
    );
    _currentUnit = widget.productData['unit']?.toString() ?? '';
    _currentSize = widget.productData['size']?.toString() ?? '';
    _unitonlyid = widget.productData['unitonlyid']?.toString() ?? '';
    _sizeonlyid = widget.productData['sizeonlyid']?.toString() ?? '';
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.productData;
    final String name = data['productname']?.toString() ?? data['name']?.toString() ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildFormField(label: '数量', controller: _qtyCtrl, isDecimal: true),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildFormField(label: '单价', controller: _priceCtrl, isDecimal: true),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildUnitSelectField(),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildSizeSelectField(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                      Navigator.pop(context, {
                        'qty': MathUtils.formatDecimal(1, double.tryParse(_qtyCtrl.text) ?? 0.0),
                        'price':
                            MathUtils.formatDecimal(2, double.tryParse(_priceCtrl.text) ?? 0.0),
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
    );
  }

  static Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    bool isDecimal = false,
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
              keyboardType: isDecimal
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : const TextInputType.numberWithOptions(),
              inputFormatters:
                  isDecimal ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))] : null,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
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

  Future<void> _showExtendOptions(String type) async {
    final data = widget.productData;
    final String productid = data['productid']?.toString() ?? data['prodid']?.toString() ?? '';
    if (productid.isEmpty) {
      Toast.show('商品信息异常');
      return;
    }

    // 对齐后台 cgother/edit.vue unit-form-item mergeData：
    // bsid 用收货机构（form.bsid）、billsupid、weekmonthflag:1、pstype:2
    final params = <String, dynamic>{
      'productid': productid,
      'cgpriceflag': 1,
      'bsid': (widget.extBsid?.isNotEmpty ?? false)
          ? widget.extBsid
          : data['storeid']?.toString() ?? '',
      'billsupid': widget.extBillsupid ?? '',
      'weekmonthflag': 1,
      'itemtype': data['itemtype']?.toString() ?? '',
      'packageflag': data['packageflag']?.toString() ?? '',
      'specflag': data['specflag']?.toString() ?? '',
      'is_page': 1,
    };
    if (widget.extPstype != null) params['pstype'] = widget.extPstype;
    if (type == 'size') {
      params['counterid'] = data['counterid']?.toString() ?? '';
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

  /// 应用单位/规格选择结果（对齐 Vue edit.vue unitConfirm / changeSize 及
  /// unitSelect.vue 的选中回传逻辑）
  ///
  /// 关键点：名称与 id 均无条件覆盖。默认单位/默认规格对应的 unitonlyid /
  /// sizeonlyid 为空串，切回原单位/原规格时必须清空旧值，_unitCanSelect /
  /// _sizeCanSelect 才能按最新状态重新判定并解禁对方字段（对齐 Vue 单位禁用
  /// 条件 !row.sizeonlyid 基于行数据动态计算）；旧实现的 isNotEmpty 守卫
  /// 导致切回原规格时旧 sizeonlyid 无法清空，单位字段保持卡死禁用
  void _applyExtendResult(String type, Map<String, dynamic> result) {
    setState(() {
      final data = widget.productData;
      if (type == 'unit') {
        // 名称/id 无条件覆盖（对齐 unitSelect.vue 选中即 emit
        // update:id/update:name，空值 emit ""），后端字段缺失时兜底空串
        _currentUnit = result['unit']?.toString() ?? result['_name']?.toString() ?? '';
        _unitonlyid = result['unitonlyid']?.toString() ?? result['_id']?.toString() ?? '';
        data['unit'] = _currentUnit;
        data['unitonlyid'] = _unitonlyid;
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
        // 条码/编码更新（sbarcode / scode 优先，对齐 Vue unitConfirm）
        final nb = result['sbarcode']?.toString() ?? result['barcode']?.toString();
        if (nb != null) data['barcode'] = nb;
        final nc = result['scode']?.toString() ?? result['code']?.toString();
        if (nc != null) data['code'] = nc;
        final nr = result['sellprice']?.toString() ?? result['retailprice']?.toString();
        if (nr != null && nr.isNotEmpty) {
          data['sellprice'] = nr;
          data['retailprice'] = nr;
        }
        // packagenum：选了非默认单位后设为 1
        // （对齐 Vue unitConfirm：if (unitonlyid != "") packagenum = 1）
        if (_unitonlyid.isNotEmpty) data['packagenum'] = 1;
      } else {
        // 规格：名称/id 同样无条件覆盖，切回原规格时 sizeonlyid 为空，
        // 清空后 _unitCanSelect 重新为 true，单位字段恢复可选
        _currentSize = result['size']?.toString() ?? result['_name']?.toString() ?? '';
        _sizeonlyid = result['sizeonlyid']?.toString() ?? result['_id']?.toString() ?? '';
        data['size'] = _currentSize;
        data['sizeonlyid'] = _sizeonlyid;
        // 价格联动（对齐 Vue changeSize：cgprice/price、inprice、oldprice、批发价）
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
        // 条码/编码更新（sbarcode / scode 优先，对齐 Vue changeSize）
        final nb = result['sbarcode']?.toString() ?? result['barcode']?.toString();
        if (nb != null) data['barcode'] = nb;
        final nc = result['scode']?.toString() ?? result['code']?.toString();
        if (nc != null) data['code'] = nc;
        final nr = result['sellprice']?.toString() ?? result['retailprice']?.toString();
        if (nr != null && nr.isNotEmpty) {
          data['sellprice'] = nr;
          data['retailprice'] = nr;
        }
        // packagenum：选了非默认规格后设为 1
        // （对齐 Vue changeSize：if (sizeonlyid != "") packagenum = 1）
        if (_sizeonlyid.isNotEmpty) data['packagenum'] = 1;
      }
    });
  }
}

// =================== 数据行 ===================
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

  /// 门店库存（对齐 Vue stockqty）
  double stockqty = 0;

  /// 批次号
  String batchno = '';
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

// =================== 明细行 Widget ===================
class _DetailItem extends StatefulWidget {
  const _DetailItem({
    required this.row,
    required this.index,
    required this.isSelectMode,
    required this.isSelected,
    required this.readOnly,
    required this.onToggle,
    this.onChanged,
    this.extBsid,
    this.extBillsupid,
    this.extPstype,
  });

  final _DetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final VoidCallback onToggle;

  /// 失焦回调：行金额格式化/重算完成后通知父页面刷新底部合计
  final VoidCallback? onChanged;

  /// 页面级上下文（对齐 Vue unit-form-item mergeData：bsid/billsupid/pstype）
  final String? extBsid;
  final String? extBillsupid;
  final int? extPstype;

  @override
  State<_DetailItem> createState() => _DetailItemState();
}

class _DetailItemState extends State<_DetailItem> {
  TextEditingController get _priceCtrl => widget.row.priceController;
  TextEditingController get _qtyCtrl => widget.row.qtyController;
  TextEditingController get _amtCtrl => widget.row.amtController;

  late final VoidCallback _onPriceBlur;
  late final VoidCallback _onQtyBlur;
  late final VoidCallback _onAmtBlur;

  @override
  void initState() {
    super.initState();
    _onPriceBlur = () => _formatField(widget.row.priceFocusNode, _priceCtrl, 2);
    _onQtyBlur = () => _formatField(widget.row.qtyFocusNode, _qtyCtrl, 1);
    _onAmtBlur = () => _formatAmtField();
    widget.row.priceFocusNode.addListener(_onPriceBlur);
    widget.row.qtyFocusNode.addListener(_onQtyBlur);
    widget.row.amtFocusNode.addListener(_onAmtBlur);
    _syncAmtController();
  }

  @override
  void dispose() {
    widget.row.priceFocusNode.removeListener(_onPriceBlur);
    widget.row.qtyFocusNode.removeListener(_onQtyBlur);
    widget.row.amtFocusNode.removeListener(_onAmtBlur);
    super.dispose();
  }

  void _formatField(FocusNode node, TextEditingController ctrl, int col) {
    if (node.hasFocus) return;
    final value = double.tryParse(ctrl.text);
    if (value != null) {
      final text = MathUtils.formatDecimal(col, value);
      if (text != ctrl.text) ctrl.text = text;
    }
    _notifyChange();
    widget.onChanged?.call();
  }

  void _formatAmtField() {
    final node = widget.row.amtFocusNode;
    if (node.hasFocus) return;
    final value = double.tryParse(_amtCtrl.text);
    if (value != null) {
      final text = MathUtils.formatDecimal(3, value);
      if (text != _amtCtrl.text) _amtCtrl.text = text;
    }
    final amt = double.tryParse(_amtCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    if (price > 0) {
      final newQty = MathUtils.formatDecimal(2, amt / price);
      _qtyCtrl.text = newQty;
    }
    widget.row.amt = MathUtils.formatDecimalNum(3, amt);
    final raw = widget.row.rawData;
    if (raw != null) {
      raw['amt'] = widget.row.amt;
      raw['qty'] = double.tryParse(_qtyCtrl.text) ?? 0;
    }
    widget.onChanged?.call();
  }

  void _syncAmtController() {
    if (widget.row.amt != null) {
      _amtCtrl.text = MathUtils.formatDecimal(3, widget.row.amt);
    }
  }

  void _notifyChange() {
    final price = MathUtils.formatDecimalNum(2, double.tryParse(_priceCtrl.text) ?? 0);
    final qty = MathUtils.formatDecimalNum(1, double.tryParse(_qtyCtrl.text) ?? 0);
    widget.row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    _syncAmtController();
    final raw = widget.row.rawData;
    if (raw != null) {
      raw['price'] = price;
      raw['qty'] = qty;
      raw['amt'] = widget.row.amt;
    }
  }

  Future<void> _editDetail(BuildContext context) async {
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
          productData: widget.row.rawData != null
              ? Map<String, dynamic>.from(widget.row.rawData!)
              : <String, dynamic>{},
          initialPrice: double.tryParse(_priceCtrl.text) ?? 0,
          initialQty: double.tryParse(_qtyCtrl.text) ?? 0,
          extBsid: widget.extBsid,
          extBillsupid: widget.extBillsupid,
          extPstype: widget.extPstype,
        ),
      ),
    );
    if (result != null) {
      final qty =
          MathUtils.formatDecimalNum(1, double.tryParse(result['qty']?.toString() ?? '') ?? 0);
      final price =
          MathUtils.formatDecimalNum(2, double.tryParse(result['price']?.toString() ?? '') ?? 0);
      _qtyCtrl.text = qty.toStringAsFixed(1);
      _priceCtrl.text = price.toStringAsFixed(2);
      widget.row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
      _syncAmtController();
      if (widget.row.rawData != null) {
        widget.row.rawData!['unit'] = result['unit']?.toString() ?? '';
        widget.row.rawData!['size'] = result['size']?.toString() ?? '';
        widget.row.rawData!['unitonlyid'] = result['unitonlyid']?.toString() ?? '';
        widget.row.rawData!['sizeonlyid'] = result['sizeonlyid']?.toString() ?? '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.row.nameController.text;
    final unit = widget.row.rawData?['unit']?.toString() ?? '';
    final size = widget.row.rawData?['size']?.toString() ?? '';

    return GestureDetector(
      onTap: widget.isSelectMode
          ? widget.onToggle
          : (widget.readOnly ? null : () => _editDetail(context)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
        ),
        child: Row(
          children: [
            if (widget.isSelectMode) ...[
              Icon(widget.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20, color: const Color(0xFF006EFF)),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 5,
              child: Text(
                '$name${size.isNotEmpty ? '/$size' : ''}${unit.isNotEmpty ? '($unit)' : ''}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    border: OutlineInputBorder(),
                    enabledBorder:
                        OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                    focusedBorder:
                        OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF006EFF))),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
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
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    border: OutlineInputBorder(),
                    enabledBorder:
                        OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                    focusedBorder:
                        OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF006EFF))),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 34,
                child: TextField(
                  controller: _amtCtrl,
                  focusNode: widget.row.amtFocusNode,
                  readOnly: widget.readOnly,
                  enabled: !widget.readOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    border: OutlineInputBorder(),
                    enabledBorder:
                        OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                    focusedBorder:
                        OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF006EFF))),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
