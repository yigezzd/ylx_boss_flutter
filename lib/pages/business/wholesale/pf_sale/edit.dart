import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_batch.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
import 'package:flutter_deer/models/scan_settings.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/purchase/instore/search.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_order/search.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_customer.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_salesperson.dart';
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
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/load_image.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:flutter_deer/widgets/select_field_item.dart';
import 'package:sp_util/sp_util.dart';

enum _PFSaleAction { none, save, sign, delete, print, retsign, withdraw }

// -- lxAss aligned calculation helpers --
double _fd1(dynamic v) => MathUtils.formatDecimalNum(1, double.tryParse(v?.toString() ?? '0') ?? 0);
double _fd2(dynamic v) => MathUtils.formatDecimalNum(2, double.tryParse(v?.toString() ?? '0') ?? 0);
double _fd3(dynamic v) => MathUtils.formatDecimalNum(3, double.tryParse(v?.toString() ?? '0') ?? 0);

void _amtJudge(Map<String, dynamic> d) {
  final qty = _fd1(d['qty']);
  final price = _fd2(d['price']);
  final sellprice = _fd2(d['sellprice']);
  final presentqty = _fd1(d['presentqty']);
  final costprice = _fd2(d['costprice']);
  final inprice = _fd2(d['inprice']);
  final outtaxrate = _fd1(d['outtaxrate']);
  final amt = _fd3(MathUtils.mul(qty == 0 ? 1 : qty, price));
  d['amt'] = amt;
  d['refamt'] = _fd3(MathUtils.mul(qty == 0 ? 1 : qty, _fd2(d['refprice'])));
  d['notaxamt'] = _fd3(MathUtils.divide(amt, 1 + outtaxrate));
  d['sellamt'] = _fd3(MathUtils.mul(sellprice, qty + presentqty));
  d['inpriceamt'] = _fd3(MathUtils.mul(inprice, qty + presentqty));
  final costpriceamt = _fd3(MathUtils.mul(costprice, qty + presentqty));
  d['grossamt'] = _fd3(MathUtils.subtract(amt, costpriceamt));
  d['camt'] = _fd3(MathUtils.subtract(amt, _fd3(d['inpriceamt'])));
  d['notaxamt'] = _fd3(MathUtils.divide(amt, 1 + outtaxrate));
  d['grossrate'] =
      price == 0 ? _fd3(0) : _fd3(MathUtils.mul(MathUtils.divide(price - costprice, price), 100));
}

void _writeData(String key, Map<String, dynamic> d) {
  final pn = (_fd1(d['packagenum']) > 0 ? _fd1(d['packagenum']) : 1);
  switch (key) {
    case 'jsqty':
      d['jsqty'] = _fd1(d['jsqty']);
      d['qty'] = _fd1(MathUtils.mul(_fd1(d['jsqty']), pn));
      break;
    case 'presentqty':
      d['presentqty'] = _fd1(d['presentqty']);
      break;
    case 'qty':
      d['qty'] = _fd1(d['qty']);
      d['jsqty'] = _fd1(MathUtils.divide(_fd1(d['qty']), pn));
      break;
    case 'rate':
      d['rate'] = _fd1(d['rate']);
      d['price'] = _fd2(MathUtils.mul(MathUtils.divide(_fd1(d['rate']), 100), _fd2(d['refprice'])));
      break;
    case 'refprice':
      d['refprice'] = _fd2(d['refprice']);
      d['price'] = _fd2(MathUtils.divide(MathUtils.mul(_fd2(d['refprice']), _fd1(d['rate'])), 100));
      d['ckjamt'] = _fd3(MathUtils.mul(_fd2(d['refprice']), _fd1(d['qty'])));
      break;
    case 'price':
      d['price'] = _fd2(d['price']);
      final ref = _fd2(d['refprice']);
      d['rate'] = _fd1(MathUtils.mul(ref > 0 ? MathUtils.divide(_fd2(d['price']), ref) : 0, 100));
      break;
    case 'amt':
      d['amt'] = _fd3(d['amt']);
      final qty = _fd1(d['qty']);
      d['price'] = _fd2(qty == 0 ? _fd2(d['price']) : MathUtils.divide(_fd3(d['amt']), qty));
      final p2 = _fd2(d['price']);
      final ref2 = _fd2(d['refprice']);
      d['rate'] = _fd1(MathUtils.mul(ref2 > 0 ? MathUtils.divide(p2, ref2) : 0, 100));
      d['notaxamt'] = _fd3(MathUtils.divide(_fd3(d['amt']), 1 + _fd1(d['outtaxrate'])));
      break;
  }
  _amtJudge(d);
}

void _defValSet(Map<String, dynamic> d) {
  d['qty'] = _fd1(d['qty'] ?? 0);
  d['presentqty'] = _fd1(d['presentqty'] ?? 0);
  d['rate'] = _fd1(d['rate'] ?? 0);
  final pn = (_fd1(d['packagenum']) > 0 ? _fd1(d['packagenum']) : 1);
  d['jsqty'] = _fd1(MathUtils.divide(_fd1(d['qty']), pn));
  final cdd = _fd2(d['custdiscountprice']);
  final cp = _fd2(d['custprice']);
  d['price'] = _fd2(cdd > 0 ? cdd : (cp > 0 ? cp : _fd2(d['price'])));
  d['refprice'] = _fd2(d['refprice'] ?? d['custprice'] ?? 0);
  d['costprice'] = _fd2(d['costprice'] ?? 0);
  d['saleprice'] = _fd2(d['sellprice'] ?? 0);
  d['intaxrate'] = _fd1(d['intaxrate'] ?? 0);
  d['stockqty'] = _fd1(d['stockqty'] ?? 0);
  _writeData('price', d);
}

class PfSaleEditPage extends StatefulWidget {
  const PfSaleEditPage({super.key, this.billData});
  final Map<String, dynamic>? billData;

  @override
  State<PfSaleEditPage> createState() => _PfSaleEditPageState();
}

class _PfSaleEditPageState extends State<PfSaleEditPage> with LogPageMixin<PfSaleEditPage> {
  @override
  String get logPageName => _isEdit ? '批发销售详情' : '批发销售新增';

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _custController = TextEditingController();
  final TextEditingController _warehouseController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _salesController = TextEditingController();
  final TextEditingController _senderController = TextEditingController();

  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;
  late ScanSettings _scanSettings;

  // 参考单据
  final TextEditingController _refbillnoController = TextEditingController();
  String _refbillid = '';
  int _refbilltype = 1; // 1=订货单, 2=入库单
  Map<String, dynamic>? _refBillData;

  String? _custid;
  int? _storeid;
  String? _counterid;
  String? _salesid;
  String? _salesname;
  String? _sendercode;
  String? _sendername;
  String? _storename;
  int? _storetype;

  _PFSaleAction _submitAction = _PFSaleAction.none;
  bool _detailLoading = false;

  bool _isSelectMode = false;
  final Set<int> _selectedIndices = {};

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
  String? get _signflag => _billData?['signflag']?.toString();
  bool get _isSubmitted => _signflag == '2';

  final List<_PFSaleDetailRow> _items = [];

  @override
  void initState() {
    super.initState();
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          // 扫码头注入条码字符与 Enter 几乎同时到达，但字符走 IME 通道、
          // Enter 走按键通道，二者异步，立即读取会漏掉尚未提交的末尾字符。
          // 这里仅重置防抖延迟读取——末尾字符提交时会再次重置防抖，
          // 确保在条码完整后才发起查询（修复商米L3扫码"未找到商品"）。
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

    if (_isEdit) {
      _loadDetail();
    } else {
      _loadNewModeDefaults();
    }
    logEnter();
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
        _salesid = userMap['userid']?.toString();
        _salesname = userMap['name']?.toString();
        _salesController.text = userMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    _loadDefaultWarehouse();
    // 新增模式：初始化审批签字按钮可见性
    _initSignUserBtn();
  }

  void _loadDefaultWarehouse() {
    if (_storeid == null) return;
    request(HttpApi.counterGetList, {
      'sids': _storeid.toString(),
      'stopflag': 0,
      'cond': '',
      'is_page': 1,
      'page': 1,
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isNotEmpty) {
        final first = list.first as Map<String, dynamic>;
        setState(() {
          _counterid = first['counterid']?.toString();
          _warehouseController.text = first['countername']?.toString() ?? '';
        });
      }
    });
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
    _custController.dispose();
    _warehouseController.dispose();
    _remarkController.dispose();
    _storeController.dispose();
    _salesController.dispose();
    _senderController.dispose();
    _refbillnoController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  void _loadDetail([Map<String, dynamic>? overrideParams]) {
    setState(() => _detailLoading = true);
    final Map<String, dynamic> params =
        overrideParams ?? Map<String, dynamic>.from(widget.billData!);

    request(HttpApi.pfSellGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
          _custController.text = data['custname']?.toString() ?? '';
          _storeController.text = data['storename']?.toString() ?? '';
          _warehouseController.text = data['countername']?.toString() ?? '';
          _salesController.text = data['salesname']?.toString() ?? '';
          _senderController.text = data['sendername']?.toString() ?? '';
          _remarkController.text = data['remark']?.toString() ?? '';
          _refbillnoController.text = data['refbillno']?.toString() ?? '';
          _refbillid = data['refbillid']?.toString() ?? '';
          _refbilltype = int.tryParse(data['refbilltype']?.toString() ?? '1') ?? 1;
          final refMap = data['refMap'];
          _refBillData = refMap is Map ? Map<String, dynamic>.from(refMap) : null;

          _fileLists = (data['fileLists'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          _custid = data['custid']?.toString();
          _storeid = _parseIntFlexible(data, ['bsid', 'storeid']);
          _storename = data['storename']?.toString();
          _storetype = _parseIntFlexible(data, ['storetype']);
          _counterid = data['counterid']?.toString();
          _salesid = data['salesid']?.toString();
          _salesname = data['salesname']?.toString();
          _sendercode = data['sendercode']?.toString();
          _sendername = data['sendername']?.toString();

          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            final row = _PFSaleDetailRow();
            row.prodid = c['prodid']?.toString() ?? c['productid']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            row.qtyController.text = c['qty']?.toString() ?? '0';
            row.priceController.text = c['price']?.toString() ?? '0';
            row.presentQtyController.text = c['presentqty']?.toString() ?? '0';

            row.unit = c['unit']?.toString() ?? '';
            row.size = c['size']?.toString() ?? '';
            row.batchno = c['batchno']?.toString() ?? '';
            row.birthdate = c['birthdate']?.toString() ?? '';
            row.validdate = c['validdate']?.toString() ?? '';
            row.remark = c['remark']?.toString() ?? '';
            row.amt = double.tryParse(c['amt']?.toString() ?? '');
            row.costprice = double.tryParse(c['costprice']?.toString() ?? '0');
            row.refprice = double.tryParse(c['refprice']?.toString() ?? '0');
            row.rawData = c;
            _writeData('qty', c);
            _items.add(row);
          }
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  // ═══ 提交/保存 ═══
  void _submit({bool doSign = false}) {
    logSave(doSign ? '保存并审核' : _isEdit ? '保存修改' : '保存单据');
    if (!_isSigned) {
      if (_custid == null || _custid!.isEmpty) {
        Toast.show('请选择客户');
        return;
      }
      if (_storeid == null) {
        Toast.show('请选择机构');
        return;
      }
      if (_counterid == null || _counterid!.isEmpty) {
        Toast.show('请选择仓库');
        return;
      }
    }

    if (!_isEdit) {
      if (!_formKey.currentState!.validate()) return;
    }

    final List<_PFSaleDetailRow> submitItems;
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
        if (qty == 0) {
          Toast.show('请填写数量');
          return;
        }
      }
    }

    // 检查售价低于成本
    final salePriceDownInPriceFlag = SpUtil.getInt('salePriceDownInPriceFlag') ?? 0;
    if (salePriceDownInPriceFlag == 1) {
      for (final row in submitItems) {
        final price = double.tryParse(row.priceController.text) ?? 0;
        final cost = row.costprice ?? 0;
        if (cost > 0 && price < cost) {
          Toast.show('售价不能低于成本价');
          return;
        }
      }
    }

    setState(() => _submitAction = _PFSaleAction.save);

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
      final now = DateTime.now();
      final billdate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      params = {
        'billtype': 1,
        'billdate': billdate,
        'signflag': 0,
        'freeamt': 0,
        'fileLists': [],
      };
    }

    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt);
    params['detaillist'] = detaillist;
    params['fileLists'] = _fileLists;
    params['remark'] = _remarkController.text.trim();
    params['custname'] = _custController.text.trim();
    params['custid'] = _custid ?? '';
    params['bsid'] = _storeid ?? '';
    params['storename'] = _storename ?? '';
    params['storetype'] = _storetype ?? '';
    params['counterid'] = _counterid ?? '';
    params['countername'] = _warehouseController.text.trim();
    params['salesid'] = _salesid ?? '';
    params['salesname'] = _salesname ?? '';
    params['sendercode'] = _sendercode ?? '';
    params['sendername'] = _sendername ?? '';
    params['refbillno'] = _refbillnoController.text.trim();
    params['refbillid'] = _refbillid;
    params['refbilltype'] = _refbilltype;

    request(HttpApi.pfSellSave, params).then((result) {
      if (!mounted) return;
      if (!doSign) {
        Toast.show(result['retmsg']?.toString() ?? '保存成功');
      }
      final retData = result['data'];
      if (retData is Map<String, dynamic>) {
        if (_isEdit) {
          if (doSign) {
            setState(() => _billData = retData);
            _doSignAfterSave(retData);
          } else {
            _loadDetail(Map<String, dynamic>.from(retData));
          }
        } else {
          final String? newBillid = retData['billid']?.toString();
          if (newBillid != null && newBillid.isNotEmpty) {
            setState(() {
              _newBillid = newBillid;
              _billData = retData;
            });
            if (doSign) {
              _doSignAfterSave(retData);
            } else {
              _loadDetail(Map<String, dynamic>.from(retData));
            }
          } else {
            Navigator.pop(context, true);
          }
        }
      } else {
        if (!_isEdit) Navigator.pop(context, true);
      }
    }).whenComplete(() {
      if (mounted && !doSign) setState(() => _submitAction = _PFSaleAction.none);
    });
  }

  List<Map<String, dynamic>> _buildSubmitDetailList() {
    return _items.map((row) {
      final qty = double.tryParse(row.qtyController.text) ?? 0;
      final price = double.tryParse(row.priceController.text) ?? 0;
      final presentqty = double.tryParse(row.presentQtyController.text) ?? 0;
      final jsqty = MathUtils.add(qty, presentqty);
      final item =
          row.rawData != null ? Map<String, dynamic>.from(row.rawData!) : <String, dynamic>{};
      item['productname'] = row.nameController.text.trim();
      item['prodname'] = row.nameController.text.trim();
      item['qty'] = qty;
      item['price'] = price;
      item['amt'] = row.amt ?? MathUtils.mul(qty, price);
      item['jsqty'] = jsqty;
      item['presentqty'] = presentqty;
      item['batchno'] = row.batchno;
      item['birthdate'] = row.birthdate;
      item['validdate'] = row.validdate;
      item['prodid'] = row.prodid ?? '';
      item['unit'] = row.unit;
      item['size'] = row.size;
      item['remark'] = row.remark;
      // 显式提交零售价字段（sellprice + retailprice）
      if (row.rawData != null) {
        if (row.rawData!['sellprice'] != null) item['sellprice'] = row.rawData!['sellprice'];
        if (row.rawData!['retailprice'] != null) item['retailprice'] = row.rawData!['retailprice'];
      }
      return item;
    }).toList();
  }

  // ═══ 审核 ═══
  Future<void> _sign() async {
    if (!PermissionUtils.checkPermission('012305', showTip: false)) {
      Toast.show('你无权审核批发销售，请在后台修改权限');
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
          setState(() => _submitAction = _PFSaleAction.none);
        }
      });
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

    setState(() => _submitAction = _PFSaleAction.retsign);
    request(HttpApi.pfSellRetsign, _billData).then((result) {
      if (!mounted) return;
      Toast.show('反审成功');
      _loadDetail();
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFSaleAction.none);
    });
  }

  Future<void> _delBill() async {
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

    setState(() => _submitAction = _PFSaleAction.delete);
    request(HttpApi.pfSellDelBill, _billData).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFSaleAction.none);
    });
  }

  Future<void> _print() async {
    if (_billData == null) return;
    setState(() => _submitAction = _PFSaleAction.print);
    request('airprint/setWxPrintRw', {
      'menuid': '060202',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFSaleAction.none);
    });
  }

  /// 撤回审批（对齐 lxAss restsign：reviewsignflag=2 走 save 审核）
  Future<void> _restsign() async {
    if (_billData == null) return;
    if (!PermissionUtils.checkPermission('012306', showTip: false)) {
      Toast.show('你无权反审核批发销售，请在后台修改权限');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('撤回单据后，所有审批步骤需重新处理！是否撤回该批发销售单？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _submitAction = _PFSaleAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['signflag'] = 1;
    request(HttpApi.pfSellSave, params).then((result) {
      if (!mounted) return;
      Toast.show('撤回成功');
      _loadDetail();
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFSaleAction.none);
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

  /// signflag==2 表示单据已驳回（批发模块同时表示待提交，走撤回分支）
  bool get _isRejected => _billData?['signflag']?.toString() == '2';

  /// 新单据时，根据机构(bsid)查询是否需要审批签字
  void _initSignUserBtn() {
    if (_isAdmin) return;
    if (!_isEdit && _storeid != null) {
      request(HttpApi.reviewTypeConfigGetNewBillSignUser, {
        'billtypeid': '0602',
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

  /// 执行审核操作（多级审批：携带 reviewsignflag/reviewremark）
  void _doSign() {
    if (_billData == null) return;
    setState(() => _submitAction = _PFSaleAction.sign);
    final signParams = <String, dynamic>{
      ...(_billData ?? {}),
      'signflag': 1,
      'reviewremark': _billData?['reviewremark']?.toString() ?? '',
    };
    // reviewsignflag: 2=撤回保持不变，0=驳回保持不变，其余设为1（通过）
    final int rsf = int.tryParse(_billData?['reviewsignflag']?.toString() ?? '') ?? -1;
    if (rsf != 2 && rsf != 0) signParams['reviewsignflag'] = 1;
    request(HttpApi.pfSellSign, signParams).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFSaleAction.none);
    });
  }

  // ═══ 选择参考单据 ═══
  Future<void> _selectRefBill() async {
    // 1. 先弹窗选择单据类型
    final billType = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              alignment: Alignment.center,
              child:
                  const Text('选择单据类型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            ListTile(
              title: const Text('订货单'),
              onTap: () => Navigator.pop(ctx, 1),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            ListTile(
              title: const Text('入库单'),
              onTap: () => Navigator.pop(ctx, 2),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            ListTile(
              title: const Text('取消', textAlign: TextAlign.center),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (billType == null || !mounted) return;

    // 2. 前置校验
    if (_storeid == null) {
      Toast.show('请先选择机构');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请先选择仓库');
      return;
    }
    if (_custid == null || _custid!.isEmpty) {
      Toast.show('请先选择客户名称');
      return;
    }

    // 3. 检查是否有商品数据
    if (_items.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提示'),
          content: const Text('选择单据会清空当前商品，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    // 4. 跳转到对应页面
    if (billType == 1) {
      // 订货单 → 选择批发订货单
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => const PfOrderSearchPage(),
          settings: RouteSettings(arguments: {
            'isSelect': true,
            'mergData': {
              'sids': _storeid != null ? [_storeid!] : <int>[],
              if (_counterid != null) 'counterid': _counterid,
              'custid': _custid ?? '',
              if (_storeid != null) 'spid': _storeid,
              if (_storeid != null) 'storeid': _storeid,
              'pfflag': 1,
              'refdhflag': 1,
              'signflag': 1,
              if (_salesid != null && _salesid!.isNotEmpty) 'userid': _salesid,
            },
          }),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _refbillid = result['billid']?.toString() ?? '';
          _refbillnoController.text = result['billno']?.toString() ?? '';
          _refBillData = result;
          _refbilltype = 1;
        });
        _loadRefBillDetails(result);
      }
    } else {
      // 入库单 → 选择采购入库单
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => const PurchaseInstoreSearchPage(),
          settings: RouteSettings(arguments: {
            'isSelect': true,
            'mergData': {
              'sids': _storeid != null ? [_storeid!] : <int>[],
              if (_counterid != null) 'counterid': _counterid,
              'custid': _custid ?? '',
              if (_storeid != null) 'spid': _storeid,
              if (_storeid != null) 'storeid': _storeid,
              'pfflag': 1,
              'refdhflag': 1,
              'signflag': 1,
              if (_salesid != null && _salesid!.isNotEmpty) 'userid': _salesid,
            },
          }),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _refbillid = result['billid']?.toString() ?? '';
          _refbillnoController.text = result['billno']?.toString() ?? '';
          _refBillData = result;
          _refbilltype = 2;
        });
        _loadRefBillDetails(result);
      }
    }
  }

  void _loadRefBillDetails(Map<String, dynamic> refBill) {
    final billid = refBill['billid']?.toString();
    if (billid == null || billid.isEmpty) return;
    // 根据单据类型选择对应的获取详情 API
    final api = _refbilltype == 1 ? HttpApi.pfOrderGetInfo : HttpApi.purchaseInstoreGetInfo;
    request(api, refBill).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        final list = data['detaillist'] as List? ?? [];
        // 对齐 lxAss orderConfirm：if refbilltype==1 拷贝客户信息
        if (_refbilltype == 1) {
          _custid = data['custid']?.toString() ?? _custid;
          if ((data['custname']?.toString() ?? '').isNotEmpty) {
            _custController.text = data['custname']?.toString() ?? '';
          }
          _salesid = data['saleid']?.toString() ?? _salesid;
          if ((data['salename']?.toString() ?? '').isNotEmpty) {
            _salesname = data['salename']?.toString();
            _salesController.text = data['salename']?.toString() ?? '';
          }
          if ((data['remark']?.toString() ?? '').isNotEmpty) {
            _remarkController.text = data['remark']?.toString() ?? '';
          }
        }
        setState(() {
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            final row = _PFSaleDetailRow();
            row.prodid = c['prodid']?.toString() ?? c['productid']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            row.priceController.text = c['price']?.toString() ?? '0';

            row.unit = c['unit']?.toString() ?? '';
            row.size = c['size']?.toString() ?? '';
            row.batchno = c['batchno']?.toString() ?? '';
            row.birthdate = c['birthdate']?.toString() ?? '';
            row.validdate = c['validdate']?.toString() ?? '';
            row.remark = c['remark']?.toString() ?? '';
            row.rawData = c;

            // 对齐 lxAss orderConfirm：引用单据数量调整
            if (_refbilltype == 1) {
              // 订货单引用：qty = 未订量，presentqty = 未订赠品量
              row.rawData!['billqty'] = c['qty']; // 保存原始单据数量
              row.rawData!['originalQty'] = c['qty'];
              row.rawData!['qty'] = double.tryParse(c['notorderedqty']?.toString() ?? '0') ?? 0;
              row.rawData!['presentqty'] =
                  double.tryParse(c['notorderpresentqty']?.toString() ?? '0') ?? 0;
              row.rawData!['orderqty'] =
                  double.tryParse(c['notorderedqty']?.toString() ?? '0') ?? 0;
              row.rawData!['orderedqty'] =
                  double.tryParse(c['incompleteQty']?.toString() ?? '0') ?? 0;
            }

            _defValSet(row.rawData!);
            _writeData('qty', row.rawData!);
            // 同步格式化后的值到 controller
            row.qtyController.text = row.rawData!['qty']?.toString() ?? '0';
            row.presentQtyController.text = row.rawData!['presentqty']?.toString() ?? '0';
            row.priceController.text = row.rawData!['price']?.toString() ?? '0';
            row.amt = double.tryParse(row.rawData!['amt']?.toString() ?? '');
            row.costprice = double.tryParse(row.rawData!['costprice']?.toString() ?? '0');
            row.refprice = double.tryParse(row.rawData!['refprice']?.toString() ?? '0');
            _items.add(row);
          }
        });
      }
    });
  }

  // ═══ 选择商品（批发销售 mergData） ═══
  Future<void> _selectProducts({String? keyword}) async {
    if (_storeid == null) {
      Toast.show('请先选择机构');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请先选择仓库');
      return;
    }
    if (_custid == null || _custid!.isEmpty) {
      Toast.show('请先选择客户名称');
      return;
    }

    final mergData = {
      'bsid': _storeid,
      'counterid': _counterid,
      'custid': _custid ?? '',
      'pfpriceflag': 1,
      'needbatchflag': 1,
      'itemstatus': '1,2',
    };

    // 对齐 lxAss：将已有商品列表传入 selectList，预加载到选择页
    final selectList = _items.where((e) => e.rawData != null).map((e) => e.rawData!).toList();

    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          mergData: mergData,
          multiple: true,
          selectList: selectList,
          initialKeyword: keyword,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        // 对齐 lxAss：直接替换整个列表（而非追加）
        _items.clear();
        for (final prod in result) {
          final originalPrice = prod['price']; // 保存用户修改的价格
          final row = _PFSaleDetailRow();
          row.prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
          row.nameController.text =
              prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
          final qty = num.tryParse((prod['qty'] ?? 1).toString())?.toDouble() ?? 1;
          final giftQty = num.tryParse((prod['giftqty'] ?? 0).toString())?.toDouble() ?? 0;
          row.qtyController.text = MathUtils.formatDecimal(1, qty);
          row.priceController.text = MathUtils.formatDecimal(
              2,
              double.tryParse(
                      prod['pfprice1']?.toString() ?? prod['price']?.toString() ?? '0.00') ??
                  0);
          row.presentQtyController.text = MathUtils.formatDecimal(1, giftQty);

          row.unit = prod['unit']?.toString() ?? '';
          row.size = prod['size']?.toString() ?? '';
          row.costprice = double.tryParse(prod['costprice']?.toString() ?? '0');
          row.refprice = double.tryParse(prod['refprice']?.toString() ?? '0');
          row.rawData = Map<String, dynamic>.from(prod);
          // 确保 sellprice 与 retailprice 同步（API 可能返回不同值）
          if ((row.rawData!['sellprice'] == null || row.rawData!['sellprice'] == 0) &&
              row.rawData!['retailprice'] != null) {
            row.rawData!['sellprice'] = row.rawData!['retailprice'];
          }
          _defValSet(row.rawData!);
          // 对齐 lxAss：恢复用户修改的价格（避免被 defValSet 的 custprice 覆盖）
          if (originalPrice != null) {
            row.rawData!['price'] = originalPrice;
            row.priceController.text = originalPrice.toString();
          } else {
            row.priceController.text = row.rawData!['price']?.toString() ?? '0';
          }
          row.amt = _fd3(row.rawData!['amt']);
          // unshift 到列表首位（新增商品置顶显示）
          _items.insert(0, row);
        }
      });
    }
  }

  // ═══ 扫码 ═══
  Future<void> _scanBarcode() async {
    if (_storeid == null) {
      Toast.show('请先选择机构');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请先选择仓库');
      return;
    }
    if (_custid == null || _custid!.isEmpty) {
      Toast.show('请先选择客户名称');
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
    debugPrint('[扫码] 处理条码: "$code"');
    _handleScannedBarcode(code, returnFocusNode: _scanFocusNode);
    _scanController.clear();
    _scanFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _handleScannedBarcode(String scanCode, {FocusNode? returnFocusNode}) async {
    if (_storeid == null) {
      Toast.show('请先选择机构');
      returnFocusNode?.requestFocus();
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请先选择仓库');
      returnFocusNode?.requestFocus();
      return;
    }
    if (_custid == null || _custid!.isEmpty) {
      Toast.show('请先选择客户');
      returnFocusNode?.requestFocus();
      return;
    }

    // 对齐 lxAss scanFn：解析秤码（重量码/金额码），取真实商品码查询
    final scaleInfo = parseScaleBarcode(scanCode);
    final searchCode = scaleInfo?.productCode ?? scanCode;

    final result = await request(HttpApi.productGetList, {
      'scancode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      'storeid': _storeid ?? '',
      'counterid': _counterid ?? '',
      'custid': _custid ?? '',
      'pfpriceflag': 1,
      'needbatchflag': 1,
      'itemstatusin': '1,2',
    });

    if (!mounted) return;
    final data = result['data'];
    final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
    if (list.isEmpty) {
      Toast.show('未找到商品');
      returnFocusNode?.requestFocus();
      return;
    }

    // === 对齐 lxAss scanFn：自编码/条码命中分流 ===
    final match = matchScanList(list, searchCode);
    if (match.needJump) {
      _selectProducts(keyword: searchCode);
      return;
    }
    final prod = match.primary ?? (list.first as Map<String, dynamic>);

    // === 对齐 lxAss：defValSet 赋值商品初始值 ===
    final giftQty = num.tryParse((prod['giftqty'] ?? 0).toString())?.toDouble() ?? 0;
    final price = _getScanPrice(prod);
    // 对齐 lxAss scanFn：普通码数量 = 接口 qty + 1
    final double baseQty = num.tryParse((prod['qty'] ?? 0).toString())?.toDouble() ?? 0;
    final double qty;
    if (scaleInfo == null) {
      qty = baseQty + 1;
    } else if (scaleInfo.type == 'weight') {
      // 重量码：直接设置数量
      qty = scaleInfo.qty ?? 0;
    } else if (scaleInfo.type == 'amount') {
      // 金额码：按金额/单价反算，单价取 price → custprice → sellprice（对齐 lxAss）
      final scalePrice = num.tryParse(
              (prod['price'] ?? prod['custprice'] ?? prod['sellprice'] ?? 0).toString())
          ?.toDouble() ??
          0;
      qty = scalePrice > 0 ? (scaleInfo.amount ?? 0) / scalePrice : baseQty + 1;
    } else {
      qty = baseQty + 1;
    }

    // === 对齐 lxAss：按 barcode/productid/size/unit/supid/batchno 查重 ===
    final existingIndex = _findScanProductIndex(prod);

    if (_scanSettings.scanQtyMode == 0) {
      // ── 默认累加1模式：不弹窗 ──
      if (existingIndex >= 0) {
        // 已存在相同商品 → 数量直接 +1
        setState(() {
          final r = _items[existingIndex];
          final curQty = double.tryParse(r.qtyController.text) ?? 0;
          final newQty = curQty + qty;
          r.qtyController.text = MathUtils.formatDecimal(1, newQty);
          if (r.rawData != null) {
            r.rawData!['qty'] = newQty;
            _writeData('qty', r.rawData!);
            r.amt = _fd3(r.rawData!['amt']);
          }
        });
        Toast.show('扫描添加成功');
      } else {
        // 不存在相同商品 → 按默认值新增一行（数量1）
        _addScanRow(prod, qty, giftQty, price);
        Toast.show('扫描添加成功');
      }
    } else if (existingIndex >= 0 && mounted) {
      // ── 弹窗手动输入模式：重复商品 → 打开详情弹窗编辑已有行（回显已有数据） ──
      await _showProDetailDrawer(_items[existingIndex], existingIndex);
    } else if (mounted) {
      // ── 弹窗手动输入模式：新商品 → 先打开详情弹窗，确认后加入列表（默认值，数量1） ──
      final result2 = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ProDetailSheet(
          productData: Map<String, dynamic>.from(prod),
          initialPrice: price,
          initialQty: qty,
          initialGiftQty: giftQty,
          initialRemark: prod['remark']?.toString() ?? '',
          onSelectUnitSize: (type) => _showExtendOptions(type, prod),
          initialBatch: prod['batchno']?.toString() ?? '',
          initialBirthdate: prod['birthdate']?.toString() ?? '',
          initialValiddate: prod['validdate']?.toString() ?? '',
          bsid: _storeid,
          counterid: _counterid,
        ),
      );
      if (result2 != null && mounted) {
        setState(() {
          final row = _PFSaleDetailRow();
          row.prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
          row.nameController.text =
              prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
          row.qtyController.text = MathUtils.formatDecimal(1, (result2['qty'] as double?) ?? qty);
          row.priceController.text = MathUtils.formatDecimal(
              2, double.tryParse(result2['price']?.toString() ?? '') ?? price);
          row.presentQtyController.text =
              MathUtils.formatDecimal(1, (result2['presentqty'] as double?) ?? giftQty);
          row.rawData = Map<String, dynamic>.from(prod);
          row.rawData!['qty'] = double.tryParse(row.qtyController.text) ?? 0;
          row.rawData!['price'] = double.tryParse(row.priceController.text) ?? 0;
          row.rawData!['presentqty'] = double.tryParse(row.presentQtyController.text) ?? 0;
          row.batchno = result2['batchno']?.toString() ?? '';
          row.birthdate = result2['birthdate']?.toString() ?? '';
          row.validdate = result2['validdate']?.toString() ?? '';
          // 先同步弹窗中所有可能修改的字段，再 defValSet 格式化
          if (row.rawData != null) {
            _syncField(row.rawData, result2, 'remark');
            _syncField(row.rawData, result2, 'unit');
            _syncField(row.rawData, result2, 'unitonlyid');
            _syncField(row.rawData, result2, 'size');
            _syncField(row.rawData, result2, 'sizeonlyid');
            _syncField(row.rawData, result2, 'barcode');
            _syncField(row.rawData, result2, 'sellprice');
            _syncField(row.rawData, result2, 'retailprice');
            _syncField(row.rawData, result2, 'refprice');
            _syncField(row.rawData, result2, 'inprice');
            _syncField(row.rawData, result2, 'costprice');
            _syncField(row.rawData, result2, 'code');
            _syncField(row.rawData, result2, 'custprice');
            _syncField(row.rawData, result2, 'pfprice1');
            _syncField(row.rawData, result2, 'pfprice2');
            _syncField(row.rawData, result2, 'pfprice3');
            _syncField(row.rawData, result2, 'mprice1');
            _syncField(row.rawData, result2, 'mprice2');
            _syncField(row.rawData, result2, 'mprice3');
            _syncField(row.rawData, result2, 'psprice');
            _syncField(row.rawData, result2, 'packagenum');
            _syncField(row.rawData, result2, 'batchno');
            _syncField(row.rawData, result2, 'birthdate');
            _syncField(row.rawData, result2, 'validdate');
            // stockqty 同步
            final sq = result2['stockqty']?.toString();
            if (sq != null && sq.isNotEmpty) row.rawData!['stockqty'] = sq;
            // 确保 sellprice 不为空（从 retailprice 回退）
            if ((row.rawData!['sellprice'] == null || row.rawData!['sellprice'] == 0) &&
                row.rawData!['retailprice'] != null) {
              row.rawData!['sellprice'] = row.rawData!['retailprice'];
            }
          }
          // 所有字段同步完成后，统一定义默认值和金额（对齐 lxAss defValSet）
          _defValSet(row.rawData!);
          row.remark = result2['remark']?.toString() ?? '';
          // 同步 row 层级的单位/规格
          row.unit = result2['unit']?.toString() ?? row.unit;
          row.size = result2['size']?.toString() ?? row.size;
          row.amt = _fd3(row.rawData!['amt']);
          // unshift 到列表首位
          _items.insert(0, row);
        });
      }
    }

    returnFocusNode?.requestFocus();
  }

  /// 默认累加1模式：不弹窗，按默认值直接新增商品行（数量取商品默认值，通常为1）
  void _addScanRow(Map<String, dynamic> prod, double qty, double giftQty, double price) {
    setState(() {
      final row = _PFSaleDetailRow();
      row.prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
      row.nameController.text = prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
      row.qtyController.text = MathUtils.formatDecimal(1, qty);
      row.priceController.text = MathUtils.formatDecimal(2, price);
      row.presentQtyController.text = MathUtils.formatDecimal(1, giftQty);
      row.rawData = Map<String, dynamic>.from(prod);
      row.rawData!['qty'] = double.tryParse(row.qtyController.text) ?? 0;
      row.rawData!['price'] = double.tryParse(row.priceController.text) ?? 0;
      row.rawData!['presentqty'] = double.tryParse(row.presentQtyController.text) ?? 0;
      row.batchno = prod['batchno']?.toString() ?? '';
      row.birthdate = prod['birthdate']?.toString() ?? '';
      row.validdate = prod['validdate']?.toString() ?? '';
      row.remark = prod['remark']?.toString() ?? '';
      row.unit = prod['unit']?.toString() ?? '';
      row.size = prod['size']?.toString() ?? '';
      // 确保 sellprice 不为空（从 retailprice 回退）
      if ((row.rawData!['sellprice'] == null || row.rawData!['sellprice'] == 0) &&
          row.rawData!['retailprice'] != null) {
        row.rawData!['sellprice'] = row.rawData!['retailprice'];
      }
      // 统一定义默认值和金额（对齐 lxAss defValSet）
      _defValSet(row.rawData!);
      row.amt = _fd3(row.rawData!['amt']);
      // unshift 到列表首位
      _items.insert(0, row);
    });
  }

  // ═══ 批量操作 ═══

  /// 同步单个字段（跳过 null 和空字符串）
  static void _syncField(Map<String, dynamic>? target, Map<String, dynamic> source, String key) {
    final v = source[key];
    if (v != null) {
      final s = v.toString();
      if (s.isNotEmpty) target?[key] = v;
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) _selectedIndices.clear();
    });
  }

  Future<void> _showProDetailDrawer(_PFSaleDetailRow row, int index) async {
    final raw = row.rawData ?? {};
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProDetailSheet(
        productData: raw,
        initialPrice: double.tryParse(row.priceController.text) ?? 0,
        initialQty: double.tryParse(row.qtyController.text) ?? 0,
        initialGiftQty: double.tryParse(row.presentQtyController.text) ?? 0,
        initialRemark: raw['remark']?.toString() ?? '',
        readOnly: _readOnly,
        onSelectUnitSize: (type) => _showExtendOptions(type, raw),
        initialBatch: row.batchno,
        initialBirthdate: row.birthdate,
        initialValiddate: row.validdate,
        bsid: _storeid,
        counterid: _counterid,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final r = _items[index];
        r.priceController.text = MathUtils.formatDecimal(
            2,
            double.tryParse(result['price']?.toString() ?? '') ??
                double.tryParse(r.priceController.text) ??
                0);
        r.qtyController.text = (result['qty'] as double?)?.toString() ??
            result['qty']?.toString() ??
            r.qtyController.text;
        r.presentQtyController.text = MathUtils.formatDecimal(
            1,
            double.tryParse(result['presentqty']?.toString() ?? '') ??
                double.tryParse(r.presentQtyController.text) ??
                0);
        r.batchno = result['batchno']?.toString() ?? '';
        r.birthdate = result['birthdate']?.toString() ?? '';
        r.validdate = result['validdate']?.toString() ?? '';
        if (r.rawData != null) {
          r.rawData!['price'] = double.tryParse(r.priceController.text) ?? 0;
          r.rawData!['qty'] = double.tryParse(r.qtyController.text) ?? 0;
          r.rawData!['presentqty'] = double.tryParse(r.presentQtyController.text) ?? 0;
          r.rawData!['remark'] = result['remark']?.toString() ?? '';
          // 更新单位/规格
          _syncField(r.rawData, result, 'unit');
          _syncField(r.rawData, result, 'unitonlyid');
          _syncField(r.rawData, result, 'size');
          _syncField(r.rawData, result, 'sizeonlyid');
          _syncField(r.rawData, result, 'barcode');
          _syncField(r.rawData, result, 'sellprice');
          _syncField(r.rawData, result, 'retailprice');
          _syncField(r.rawData, result, 'refprice');
          _syncField(r.rawData, result, 'inprice');
          _syncField(r.rawData, result, 'costprice');
          _syncField(r.rawData, result, 'code');
          _syncField(r.rawData, result, 'custprice');
          _syncField(r.rawData, result, 'pfprice1');
          _syncField(r.rawData, result, 'pfprice2');
          _syncField(r.rawData, result, 'pfprice3');
          _syncField(r.rawData, result, 'mprice1');
          _syncField(r.rawData, result, 'mprice2');
          _syncField(r.rawData, result, 'mprice3');
          _syncField(r.rawData, result, 'psprice');
          _syncField(r.rawData, result, 'packagenum');
          // 同步 stockqty
          final sq = result['stockqty']?.toString();
          if (sq != null && sq.isNotEmpty) r.rawData!['stockqty'] = sq;
          // saleprice 始终从 sellprice 重新计算
          final sp = result['sellprice']?.toString();
          if (sp != null && sp.isNotEmpty) {
            r.rawData!['saleprice'] = _fd2(sp);
          } else if (r.rawData!['sellprice'] != null) {
            r.rawData!['saleprice'] = _fd2(r.rawData!['sellprice']);
          }
          // 确保 sellprice 不为空（从 retailprice 回退）
          if ((r.rawData!['sellprice'] == null || r.rawData!['sellprice'] == 0) &&
              r.rawData!['retailprice'] != null) {
            r.rawData!['sellprice'] = r.rawData!['retailprice'];
          }
          // 重算金额相关字段（对齐 lxAss writeData→amtJudge）
          _writeData('price', r.rawData!);
          // 同步 batchno/birthdate/validdate
          r.rawData!['batchno'] = r.batchno;
          r.rawData!['birthdate'] = r.birthdate;
          r.rawData!['validdate'] = r.validdate;
        }
        r.amt = _fd3(r.rawData?['amt']);
        // 同步更新 row 字段（用于列表显示和提交）
        r.unit = result['unit']?.toString() ?? r.unit;
        r.size = result['size']?.toString() ?? r.size;
        r.remark = result['remark']?.toString() ?? r.remark;
      });
    }
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

  void _batchDelete() {
    if (_selectedIndices.isEmpty) return;
    final count = _selectedIndices.length;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text('确定删除选中的 $count 条明细？'),
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
          _items[i].dispose();
          _items.removeAt(i);
        }
        _selectedIndices.clear();
        _isSelectMode = false;
      });
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.addAll(List.generate(_items.length, (i) => i));
      }
    });
  }

  bool get _readOnly => _isEdit && _isSigned;

  // ═══ 汇总计算 ═══
  String get _totalQty {
    double sum = 0;
    for (final row in _items) {
      sum += double.tryParse(row.qtyController.text) ?? 0;
      sum += double.tryParse(row.presentQtyController.text) ?? 0;
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

  /// 销售数量（仅主数量，不含赠送，对齐底部合计）
  String get _totalOrderQty {
    double sum = 0;
    for (final row in _items) {
      sum += double.tryParse(row.qtyController.text) ?? 0;
    }
    return MathUtils.formatDecimal(1, sum);
  }

  // ═══ 扩展选项（单位/规格选择） ═══
  Future<Map<String, dynamic>?> _showExtendOptions(String type, Map<String, dynamic> raw) async {
    final String productid = raw['prodid']?.toString() ?? raw['productid']?.toString() ?? '';
    if (productid.isEmpty) return null;

    final params = <String, dynamic>{
      'productid': productid,
      'cgpriceflag': 1,
      'bsid': _storeid?.toString() ?? '',
      'custid': _custid ?? '',
      'itemtype': raw['itemtype']?.toString() ?? '',
      'packageflag': raw['packageflag']?.toString() ?? '',
      'specflag': raw['specflag']?.toString() ?? '',
      'pfpriceflag': 1,
      'needbatchflag': 1,
      'itemstatus': '1,2',
      'is_page': 1,
    };
    if (type == 'size') {
      params['counterid'] = _counterid ?? '';
    }

    final result = await request(HttpApi.productGetExtendList, params);
    if (!mounted) return null;
    final data = result['data'];
    final rawList = (data is Map<String, dynamic>
            ? (type == 'size' ? data['sizelist'] : data['packlist'])
            : null) as List? ??
        [];
    if (rawList.isEmpty) {
      Toast.show('无可选${type == 'unit' ? '单位' : '规格'}');
      return null;
    }

    final list = rawList.map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      if (type == 'size') {
        m['_name'] = m['size']?.toString() ?? m['sname']?.toString() ?? '';
        m['_id'] = m['sizeonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
      } else {
        m['_name'] = m['unit']?.toString() ?? m['sunit']?.toString() ?? '';
        m['_id'] = m['unitonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
      }
      return m;
    }).toList();

    // 选择弹窗
    final selected = await _showPicker(
      title: type == 'unit' ? '选择单位' : '选择规格',
      list: list,
    );
    if (selected == null || !mounted) return null;

    final selId = selected['_id']?.toString() ?? '';
    final selName = selected['_name']?.toString() ?? '';

    // 对齐 lxAss 构建返回值（不直接修改 raw，由调用方处理）
    // lxAss selectUnitFn: price = custprice (pfsale)
    // lxAss selectSizeFn: price = sellprice (pfsale, pricetype=sellprice)
    final priceStr = type == 'size'
        ? (selected['sellprice']?.toString() ??
            selected['custprice']?.toString() ??
            selected['pfprice1']?.toString() ??
            selected['price']?.toString() ??
            '')
        : (selected['custprice']?.toString() ??
            selected['cgprice']?.toString() ??
            selected['pfprice1']?.toString() ??
            selected['sellprice']?.toString() ??
            selected['price']?.toString() ??
            '');

    final sellpriceStr =
        selected['sellprice']?.toString() ?? selected['retailprice']?.toString() ?? '';
    final retailpriceStr =
        selected['sellprice']?.toString() ?? selected['retailprice']?.toString() ?? '';

    return {
      'unit': type == 'unit' ? selName : (raw['unit']?.toString() ?? ''),
      'unitonlyid': type == 'unit' ? selId : (raw['unitonlyid']?.toString() ?? ''),
      'size': type == 'size' ? selName : (raw['size']?.toString() ?? ''),
      'sizeonlyid': type == 'size' ? selId : (raw['sizeonlyid']?.toString() ?? ''),
      'price': priceStr,
      'sellprice': sellpriceStr,
      'retailprice': retailpriceStr,
      'stockqty': selected['stockqty']?.toString() ?? selected['stock']?.toString() ?? '',
      'barcode': selected['sbarcode']?.toString() ?? selected['barcode']?.toString() ?? '',
      'custprice': selected['custprice']?.toString() ?? '',
      'refprice': selected['refprice']?.toString() ?? '',
      'inprice': selected['inprice']?.toString() ?? '',
      'costprice': selected['costprice']?.toString() ?? '',
      'code': selected['scode']?.toString() ?? selected['code']?.toString() ?? '',
      'pfprice1': selected['pfprice1']?.toString() ?? '',
      'pfprice2': selected['pfprice2']?.toString() ?? '',
      'pfprice3': selected['pfprice3']?.toString() ?? '',
      'mprice1': selected['mprice1']?.toString() ?? '',
      'mprice2': selected['mprice2']?.toString() ?? '',
      'mprice3': selected['mprice3']?.toString() ?? '',
      'psprice': selected['psprice']?.toString() ?? '',
      'packagenum': selected['packagenum']?.toString() ?? '',
    };
  }

  /// 通用选择器弹窗
  Future<Map<String, dynamic>?> _showPicker({
    required String title,
    required List<Map<String, dynamic>> list,
  }) async {
    if (list.isEmpty) return null;
    Map<String, dynamic>? selected;
    await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                itemBuilder: (context, index) {
                  final item = list[index];
                  final name = item['_name']?.toString() ?? '';
                  return ListTile(
                    title:
                        Text(name, style: const TextStyle(fontSize: 15, color: Color(0xFF111827))),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
                    onTap: () {
                      selected = item;
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    return selected;
  }

  /// lxAss 价格优先级：custdiscountprice > 0 ? custdiscountprice : (custprice ?? price)
  double _getScanPrice(Map<String, dynamic> prod) {
    final custdiscountprice = double.tryParse(prod['custdiscountprice']?.toString() ?? '') ?? 0;
    if (custdiscountprice > 0) return custdiscountprice;
    final custprice = double.tryParse(prod['custprice']?.toString() ?? '');
    if (custprice != null) return custprice;
    return double.tryParse(prod['price']?.toString() ?? '') ?? 0;
  }

  /// 按 barcode/productid/size/unit/supid/batchno 查找已在列表中的商品索引
  int _findScanProductIndex(Map<String, dynamic> prod) {
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i].rawData ?? {};
      if ((item['barcode']?.toString() ?? '') == (prod['barcode']?.toString() ?? '') &&
          ((item['productid']?.toString() ?? '') == (prod['productid']?.toString() ?? '') ||
              (item['prodid']?.toString() ?? '') == (prod['productid']?.toString() ?? '')) &&
          (item['size']?.toString() ?? '') == (prod['size']?.toString() ?? '') &&
          (item['unit']?.toString() ?? '') == (prod['unit']?.toString() ?? '') &&
          (item['supid']?.toString() ?? '') == (prod['supid']?.toString() ?? '') &&
          (item['batchno']?.toString() ?? '') == (prod['batchno']?.toString() ?? '')) {
        return i;
      }
    }
    return -1;
  }

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
          _isEdit ? (_isSigned ? '批发销售详情' : '修改批发销售') : '新增批发销售',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
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
              // ---- 审核日志卡片（多级审批） ----
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
              SliverPersistentHeader(
                pinned: true,
                delegate: _PFSaleStickyHeaderDelegate(state: this),
              ),
              if (_items.isNotEmpty)
                SliverList.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) => RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _PFSaleDetailItem(
                        row: _items[index],
                        index: index,
                        isSelectMode: _isSelectMode,
                        isSelected: _selectedIndices.contains(index),
                        readOnly: _readOnly,
                        refbillno: _refbillnoController.text,
                        onTap: () => _showProDetailDrawer(_items[index], index),
                        onToggle: () => _toggleIndex(index),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
    return _isEdit ? body : Form(key: _formKey, child: body);
  }

  Widget _buildBillStatusWidget() {
    final data = _billData ?? {};
    final String billno = data['billno']?.toString() ?? '-';
    final String createtime = data['createtime']?.toString() ?? '-';
    final String salesname = data['salesname']?.toString() ?? '';
    final String signtime = data['signtime']?.toString() ?? '';
    final String signusername =
        data['signusername']?.toString() ?? data['signname']?.toString() ?? '';
    return _buildCard(
      title: '单号：$billno',
      titleRight: Text(
        _signflag == '1' ? '已审核' : (_signflag == '2' ? '已驳回' : '待审核'),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _signflag == '1' ? const Color(0xFF00A870) : (_signflag == '2' ? const Color(0xFFFF9900) : const Color(0xFFD54B5A)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('制单信息：$createtime',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                const SizedBox(width: 16),
                Text(salesname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ],
            ),
            if (_isSigned && (signtime.isNotEmpty || signusername.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('审核信息：${signtime.isNotEmpty ? signtime : '-'}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                  const SizedBox(width: 16),
                  Text(signusername.isNotEmpty ? signusername : '-',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

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

  Widget _buildBillInfoReadonly() {
    return Column(
      children: [
        _buildReadonlyField(label: '机构', value: _storeController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '仓库', value: _warehouseController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '客户', value: _custController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '业务员', value: _salesController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        if (_senderController.text.isNotEmpty)
          _buildReadonlyField(label: '送货人', value: _senderController.text),
        if (_refbillnoController.text.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          _buildReadonlyField(label: '参考单据', value: _refbillnoController.text),
        ],
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '备注', value: _remarkController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildAttachButton(),
      ],
    );
  }

  Widget _buildBillInfoEditable() {
    return Column(
      children: [
        SelectFieldItem(
          label: '机构',
          value: _storeController.text,
          onTap: () async {
            final result =
                await SelectStorePage.show(context, initialSelectedId: _storeid?.toString());
            if (result != null && mounted) {
              setState(() {
                _storeid = int.tryParse(result['storeid']?.toString() ?? '');
                _storename = result['storename']?.toString();
                _storetype = int.tryParse(result['storetype']?.toString() ?? '');
                _storeController.text = result['storename']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '仓库',
          required: true,
          value: _warehouseController.text,
          onTap: () async {
            final result = await SelectWarehousePage.show(context,
                bsid: _storeid, initialSelectedId: _counterid);
            if (result != null && mounted) {
              setState(() {
                _counterid = result['counterid']?.toString();
                _warehouseController.text = result['countername']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '客户',
          required: true,
          value: _custController.text,
          onTap: () async {
            final result = await SelectCustomerPage.show(context, initialSelectedId: _custid);
            if (result != null && mounted) {
              setState(() {
                _custid = result['custid']?.toString();
                _custController.text = result['custname']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '业务员',
          value: _salesController.text,
          onTap: () async {
            final result = await SelectSalespersonPage.show(context, initialSelectedId: _salesid);
            if (result != null && mounted) {
              setState(() {
                _salesid = result['salesid']?.toString();
                _salesname = result['salesname']?.toString();
                _salesController.text = result['salesname']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '送货人',
          value: _senderController.text,
          onTap: () async {
            final result = await _selectSender();
            if (result != null && mounted) {
              setState(() {
                _sendercode = result['code']?.toString();
                _sendername = result['name']?.toString();
                _senderController.text = result['name']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: _refbilltype == 1 ? '订货单' : '入库单',
          value: _refbillnoController.text.isNotEmpty ? _refbillnoController.text : '请选择',
          onTap: _selectRefBill,
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

  /// 附件按钮行（对齐采购入库 _buildAttachButton）
  Widget _buildAttachButton() {
    return GestureDetector(
      onTap: () async {
        final result = await AttachPage.show(
          context,
          fileLists: _fileLists,
          menuid: '060202',
          billid: _billData?['billid']?.toString() ?? _newBillid ?? '',
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

  Future<Map<String, dynamic>?> _selectSender() async {
    if (_storeid == null) return null;
    return CommonSelectSheet.show(
      context,
      title: '选择送货人',
      searchHint: '输入送货人名称/编码',
      idField: 'code',
      fetchData: (searchText, page) => request(HttpApi.otherdataGetList, {
        'search_text': searchText,
        'plugins': ['user'],
        'sids': [_storeid],
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (item) => {
        'code': item['code']?.toString(),
        'name': item['name']?.toString(),
      },
    );
  }

  Widget _buildStickyHeader() {
    return Align(
      alignment: Alignment.topCenter,
      child: ColoredBox(
        color: const Color(0xFFF5F5F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 扫描输入框（仅非已审核且设置了显示红外输入框时显示）
            if (!_isSigned && _scanSettings.showInfraredInput) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _buildScanInput(),
              ),
              const SizedBox(height: 8),
            ],
            // 不显示红外扫描框时，补充与粘性表头之间的间距
            if (!_isSigned && !_scanSettings.showInfraredInput) const SizedBox(height: 8),
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
                          if (!_isSigned) ...[
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
                              flex: 2,
                              child: Text('价格',
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
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LoadAssetImage('state/zwsp', width: 80, height: 80),
                      SizedBox(height: 12),
                      Text('暂无商品明细', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 红外扫描输入框（PDA 扫码枪）——新增/编辑模式共用
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
                keyboardType: TextInputType.none, // 引擎层面阻止键盘弹出，PDA扫码器仍可注入
                enableInteractiveSelection: false, // 禁止选择菜单
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  // 与 onKeyEvent 相同的异步时序问题：不立即读取，重置防抖延迟读取。
                  // 机构/仓库/客户等前置校验统一在 _handleScannedBarcode 内处理。
                  _scanDebounceTimer?.cancel();
                  _scanDebounceTimer = Timer(const Duration(milliseconds: 150), _processScanInput);
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                  ),
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

  Widget _buildReadonlyField({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String hint = '',
    int maxLines = 1,
    double verticalPadding = 10,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 2),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_isSelectMode) {
      return _buildBatchDeleteBar();
    }
    // lxAss: 已审核 → [打印] [反审]
    if (_readOnly) {
      return _buildBottomRow(
        buttons: [
          _BottomBtn(label: '打印', onTap: _print, perm: '012307'),
          _BottomBtn(label: '反审', onTap: _retsign, perm: '012306', primary: false),
        ],
      );
    }
    // lxAss: 新增 → [保存] [审核]
    if (!_isEdit) {
      return _buildBottomRow(
        buttons: [
          _BottomBtn(
              label: '保存',
              onTap: () {
                if (!PermissionUtils.checkPermission('012302', showTip: false)) {
                  Toast.show('你无权新增批发销售，请在后台修改权限');
                  return;
                }
                _submit();
              },
              loading: _submitAction == _PFSaleAction.save),
          // 审核按钮 - billSign（保存并审核）
          if (_billSign)
            _BottomBtn(
                label: '审核',
                onTap: () {
                  if (!PermissionUtils.checkPermission('012305', showTip: false)) {
                    Toast.show('你无权审核批发销售，请在后台修改权限');
                    return;
                  }
                  _submit(doSign: true);
                },
                loading: _submitAction == _PFSaleAction.sign),
        ],
      );
    }
    // lxAss: 待提交 (signflag==2) → [撤回]
    if (_isSubmitted) {
      return _buildBottomRow(
        buttons: [
          _BottomBtn(label: '撤回', onTap: _restsign, perm: '012306', fillColor: const Color(0xFFFF9900)),
        ],
      );
    }
    // lxAss: 待审核 (signflag==0) → [更多] [保存] [审核]（多级审批控制按钮可见性）
    return _buildBottomRow(
      buttons: [
        // “更多”按钮 - reviewsignflag != 2 && bolHandleTT
        if (!_isWithdrawPending && _bolHandleTT)
          _BottomBtn(label: '更多', onTap: _showMoreSheet, perm: '012304', primary: false),
        // 保存/审核按钮 - signflag!=2 && reviewsignflag!=2 && (bolHandleTT || (审批流>0 && bolHandleT))
        if (!_isRejected &&
            !_isWithdrawPending &&
            (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT))) ...[
          _BottomBtn(
              label: '保存',
              onTap: () {
                if (!PermissionUtils.checkPermission('012303', showTip: false)) {
                  Toast.show('你无权编辑批发销售，请在后台修改权限');
                  return;
                }
                _submit();
              },
              loading: _submitAction == _PFSaleAction.save),
          _BottomBtn(
              label: '审核',
              onTap: () {
                if (!PermissionUtils.checkPermission('012305', showTip: false)) {
                  Toast.show('你无权审核批发销售，请在后台修改权限');
                  return;
                }
                _sign();
              },
              loading: _submitAction == _PFSaleAction.sign),
        ],
      ],
    );
  }

  /// 更多弹窗（删单 + 打印）
  void _showMoreSheet() {
    if (!PermissionUtils.checkPermission('012304', showTip: false)) {
      Toast.show('你无权删除批发销售，请在后台修改权限');
      return;
    }
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

  /// 统一底部行构建
  Widget _buildBottomRow({required List<_BottomBtn> buttons}) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  '数量：$_totalOrderQty，共${_items.length}项，总金额：¥$_totalAmt',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (int i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    label: buttons[i].label,
                    onTap: buttons[i].onTap,
                    loading: buttons[i].loading,
                    primary: buttons[i].primary,
                    fillColor: buttons[i].fillColor,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 批量删除栏
  Widget _buildBatchDeleteBar() {
    final selectedCount = _selectedIndices.length;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
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

  Widget _buildActionButton({
    required String label,
    required VoidCallback onTap,
    bool loading = false,
    bool primary = true,
    Color? fillColor,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: loading
              ? const Color(0xFFB0C4DE)
              : fillColor ?? (primary
                  ? const Color(0xFF006EFF)
                  : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: fillColor != null
              ? null
              : (primary ? null : Border.all(color: const Color(0xFFDEDEDE))),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: fillColor != null ? Colors.white : (primary ? Colors.white : const Color(0xFF333333)),
                ),
              ),
      ),
    );
  }
}

/// 底部按钮描述
class _BottomBtn {
  const _BottomBtn({
    required this.label,
    required this.onTap,
    this.loading = false,
    this.primary = true,
    this.perm,
    this.fillColor,
  });
  final String label;
  final VoidCallback onTap;
  final bool loading;
  final bool primary;
  final String? perm;
  final Color? fillColor;
}

/// 批发销售明细行数据
class _PFSaleDetailRow {
  _PFSaleDetailRow() {
    initFocusListeners();
  }

  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController(text: '1');
  final TextEditingController priceController = TextEditingController();
  final TextEditingController presentQtyController = TextEditingController(text: '0');
  final FocusNode priceFocusNode = FocusNode();
  final FocusNode presentQtyFocusNode = FocusNode();
  final FocusNode qtyFocusNode = FocusNode();
  String? prodid;
  String unit = '';
  String size = '';
  String remark = '';
  String batchno = '';
  String birthdate = '';
  String validdate = '';
  double? amt;
  double? costprice;
  double? refprice;
  Map<String, dynamic>? rawData;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    presentQtyController.dispose();
    priceFocusNode.dispose();
    presentQtyFocusNode.dispose();
    qtyFocusNode.dispose();
  }

  static void _addOnFocusSelectAll(FocusNode node, TextEditingController controller) {
    node.addListener(() {
      if (node.hasFocus && controller.text.isNotEmpty) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      }
    });
  }

  void initFocusListeners() {
    _addOnFocusSelectAll(priceFocusNode, priceController);
    _addOnFocusSelectAll(presentQtyFocusNode, presentQtyController);
    _addOnFocusSelectAll(qtyFocusNode, qtyController);
  }
}

/// 明细行 Widget
class _PFSaleDetailItem extends StatefulWidget {
  const _PFSaleDetailItem({
    required this.row,
    required this.index,
    this.isSelectMode = false,
    this.isSelected = false,
    this.readOnly = false,
    required this.refbillno,
    required this.onToggle,
    this.onTap,
  });
  final _PFSaleDetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final String refbillno;
  final VoidCallback onToggle;
  final VoidCallback? onTap;

  @override
  State<_PFSaleDetailItem> createState() => _PFSaleDetailItemState();
}

class _PFSaleDetailItemState extends State<_PFSaleDetailItem> {
  TextEditingController get _priceCtrl => widget.row.priceController;
  TextEditingController get _giftCtrl => widget.row.presentQtyController;
  TextEditingController get _qtyCtrl => widget.row.qtyController;
  final FocusNode _priceFocus = FocusNode();
  final FocusNode _giftFocus = FocusNode();
  final FocusNode _qtyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _PFSaleDetailRow._addOnFocusSelectAll(_priceFocus, _priceCtrl);
    _PFSaleDetailRow._addOnFocusSelectAll(_giftFocus, _giftCtrl);
    _PFSaleDetailRow._addOnFocusSelectAll(_qtyFocus, _qtyCtrl);
  }

  @override
  void dispose() {
    _priceFocus.dispose();
    _giftFocus.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  void _notifyChange() {
    final newPrice = double.tryParse(_priceCtrl.text) ?? 0;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final giftQty = double.tryParse(_giftCtrl.text) ?? 0;
    final raw = widget.row.rawData;
    if (raw != null) {
      raw['price'] = newPrice;
      raw['qty'] = qty;
      raw['presentqty'] = giftQty;
      _writeData('qty', raw);
    }
    widget.row.amt = _fd3(raw?['amt']);
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.row.rawData;
    final String barcode = raw?['barcode']?.toString() ?? raw?['selfbarcode']?.toString() ?? '';
    final String retailPrice = MathUtils.formatDecimal(
        2,
        double.tryParse(raw?['sellprice']?.toString() ?? raw?['retailprice']?.toString() ?? '0') ??
            0);

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
              Expanded(
                flex: 5,
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        () {
                          final productName =
                              raw?['productname']?.toString() ?? raw?['name']?.toString() ?? '';
                          final size = raw?['size']?.toString() ?? '';
                          final unit = raw?['unit']?.toString() ?? '';
                          final buf = StringBuffer(productName);
                          if (size.isNotEmpty) buf.write('/$size');
                          if (unit.isNotEmpty) buf.write('（$unit）');
                          return buf.toString();
                        }(),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (barcode.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(barcode,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      ],
                      const SizedBox(height: 2),
                      Text('零售价：¥$retailPrice',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      const SizedBox(height: 2),
                      Text('批次：${widget.row.batchno.isNotEmpty ? widget.row.batchno : '-'}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 34,
                            child: TextField(
                              controller: _priceCtrl,
                              focusNode: _priceFocus,
                              readOnly: widget.readOnly,
                              enabled: !widget.readOnly,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                              onChanged: (_) => _notifyChange(),
                              onSubmitted: (_) => _notifyChange(),
                              onEditingComplete: _notifyChange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 34,
                            child: TextField(
                              controller: _giftCtrl,
                              focusNode: _giftFocus,
                              readOnly: widget.readOnly,
                              enabled: !widget.readOnly,
                              keyboardType: const TextInputType.numberWithOptions(),
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
                              onChanged: (_) => _notifyChange(),
                              onSubmitted: (_) => _notifyChange(),
                              onEditingComplete: _notifyChange,
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
                              focusNode: _qtyFocus,
                              readOnly: widget.readOnly,
                              enabled: !widget.readOnly,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                              onChanged: (_) => _notifyChange(),
                              onSubmitted: (_) => _notifyChange(),
                              onEditingComplete: _notifyChange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ListenableBuilder(
                      listenable:
                          Listenable.merge([widget.row.qtyController, widget.row.priceController]),
                      builder: (_, __) {
                        final q = double.tryParse(widget.row.qtyController.text) ?? 0;
                        final p = double.tryParse(widget.row.priceController.text) ?? 0;
                        final a = MathUtils.formatDecimal(3, MathUtils.mul(q, p));
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('金额：¥$a',
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

/// 粘性表头代理
class _PFSaleStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PFSaleStickyHeaderDelegate({required this.state});
  final _PfSaleEditPageState state;

  @override
  double get minExtent => _PFMinExtent;

  @override
  double get maxExtent =>
      (state._isSigned || !state._scanSettings.showInfraredInput) ? _PFMinExtent : _PFMaxExtent;

  static const double _PFScanHeight = 62.0;
  static const double _PFTitleHeight = 40.0;
  static const double _PFColumnHeight = 36.0;
  static const double _PFMinExtent = _PFTitleHeight + _PFColumnHeight;
  static const double _PFMaxExtent = _PFScanHeight + _PFMinExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader();
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}

// =================== 商品详情抽屉 ===================
class _ProDetailSheet extends StatefulWidget {
  const _ProDetailSheet({
    required this.productData,
    required this.initialPrice,
    required this.initialQty,
    required this.initialGiftQty,
    required this.initialRemark,
    this.readOnly = false,
    this.onSelectUnitSize,
    this.initialBatch = '',
    this.initialBirthdate = '',
    this.initialValiddate = '',
    this.bsid,
    this.counterid,
  });
  final Map<String, dynamic> productData;
  final double initialPrice;
  final double initialQty;
  final double initialGiftQty;
  final String initialRemark;
  final bool readOnly;
  final Future<Map<String, dynamic>?> Function(String type)? onSelectUnitSize;
  final String initialBatch;
  final String initialBirthdate;
  final String initialValiddate;
  final int? bsid;
  final String? counterid;

  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late final Map<String, dynamic> _localData;
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _giftCtrl;
  late TextEditingController _remarkCtrl;
  late TextEditingController _batchCtrl;
  late TextEditingController _birthdateCtrl;
  late TextEditingController _validdateCtrl;

  @override
  void initState() {
    super.initState();
    // 深拷贝，防止修改时污染原始数据
    _localData = Map<String, dynamic>.from(widget.productData);
    _priceCtrl = TextEditingController(text: MathUtils.formatDecimal(2, widget.initialPrice));
    final qty = widget.initialQty;
    _qtyCtrl = TextEditingController(
      text: MathUtils.formatDecimal(1, qty),
    );
    _giftCtrl = TextEditingController(text: MathUtils.formatDecimal(1, widget.initialGiftQty));
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
    _batchCtrl = TextEditingController(text: widget.initialBatch);
    _birthdateCtrl = TextEditingController(text: _formatBatchDate(widget.initialBirthdate));
    _validdateCtrl = TextEditingController(text: _formatBatchDate(widget.initialValiddate));
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _giftCtrl.dispose();
    _remarkCtrl.dispose();
    _batchCtrl.dispose();
    _birthdateCtrl.dispose();
    _validdateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _localData;
    final String name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    final String barcode = data['barcode']?.toString() ?? '';
    // 健壮化：逐级读取 sellprice → retailprice → saleprice，跳过空字符串
    final double spVal = _readPrice(data);
    final String saleprice = MathUtils.formatDecimal(2, spVal);
    final String shelves = data['shelves']?.toString() ?? '';
    final String unit = data['unit']?.toString() ?? '';
    final String size = data['size']?.toString() ?? '';

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
              child: Row(
                children: [
                  // 左侧占位，平衡关闭按钮宽度，标题居中
                  const SizedBox(width: 24),
                  Expanded(
                    child: const Text(
                      '商品详情',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
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
                                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))
                          ],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('零售价：$saleprice',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              if (shelves.isNotEmpty) ...[
                                const SizedBox(width: 16),
                                Text('货架号：$shelves',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 单位选择
                    _buildSelectField(
                        label: '单位',
                        value: unit,
                        onTap: widget.readOnly
                            ? null
                            : (data['packageflag']?.toString() != '1' ||
                                    data['specflag']?.toString() == '1')
                                ? () => _onSelect('unit')
                                : null),
                    _buildDivider(),
                    // 规格选择
                    _buildSelectField(
                        label: '规格',
                        value: size,
                        onTap: widget.readOnly
                            ? null
                            : (data['specflag']?.toString() == '1' &&
                                    (data['unitonlyid'] == null ||
                                        (data['unitonlyid']?.toString().isEmpty ?? false)))
                                ? () => _onSelect('size')
                                : null),
                    _buildDivider(),
                    // 数量
                    _buildFormField(
                        label: '数量',
                        controller: _qtyCtrl,
                        isDecimal: true,
                        readOnly: widget.readOnly,
                        onChanged: (_) => setState(() {})),
                    _buildDivider(),
                    // 赠送数量
                    _buildFormField(
                        label: '赠送数量',
                        controller: _giftCtrl,
                        readOnly: widget.readOnly,
                        onChanged: (_) => setState(() {})),
                    _buildDivider(),
                    // 价格
                    _buildFormField(
                        label: '价格',
                        controller: _priceCtrl,
                        isDecimal: true,
                        readOnly: widget.readOnly,
                        onChanged: (_) => setState(() {})),
                    _buildDivider(),
                    // 金额（只读）
                    _buildAmountField(),
                    _buildDivider(),
                    // 商品批次
                    _buildBatchSelectField(),
                    _buildDivider(),
                    // 生产日期（只读）
                    _buildReadonlyDateField(label: '生产日期', text: _birthdateCtrl.text),
                    _buildDivider(),
                    // 有效期（只读）
                    _buildReadonlyDateField(label: '有效期', text: _validdateCtrl.text),
                    _buildDivider(),
                    // 备注
                    _buildFormField(
                        label: '备注',
                        controller: _remarkCtrl,
                        readOnly: widget.readOnly,
                        keyboardType: TextInputType.text,
                        maxLines: 2),
                  ],
                ),
              ),
            ),
            if (!widget.readOnly)
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
                          Navigator.pop(context, {
                            'price': double.tryParse(_priceCtrl.text) ?? 0.0,
                            'qty': double.tryParse(_qtyCtrl.text) ?? 0.0,
                            'presentqty': double.tryParse(_giftCtrl.text) ?? 0.0,
                            'remark': _remarkCtrl.text.trim(),
                            'unit': _localData['unit']?.toString() ?? '',
                            'unitonlyid': _localData['unitonlyid']?.toString() ?? '',
                            'size': _localData['size']?.toString() ?? '',
                            'sizeonlyid': _localData['sizeonlyid']?.toString() ?? '',
                            'barcode': _localData['barcode']?.toString() ?? '',
                            'batchno': _batchCtrl.text.trim(),
                            'birthdate': _birthdateCtrl.text.trim(),
                            'validdate': _validdateCtrl.text.trim(),
                            'retailprice': _localData['retailprice']?.toString() ?? '',
                            'sellprice': _localData['sellprice']?.toString() ?? '',
                            'stockqty': _localData['stockqty']?.toString() ??
                                _localData['stock']?.toString() ??
                                '',
                            'refprice': _localData['refprice']?.toString() ?? '',
                            'inprice': _localData['inprice']?.toString() ?? '',
                            'costprice': _localData['costprice']?.toString() ?? '',
                            'code': _localData['code']?.toString() ?? '',
                            'custprice': _localData['custprice']?.toString() ?? '',
                            'pfprice1': _localData['pfprice1']?.toString() ?? '',
                            'pfprice2': _localData['pfprice2']?.toString() ?? '',
                            'pfprice3': _localData['pfprice3']?.toString() ?? '',
                            'mprice1': _localData['mprice1']?.toString() ?? '',
                            'mprice2': _localData['mprice2']?.toString() ?? '',
                            'mprice3': _localData['mprice3']?.toString() ?? '',
                            'psprice': _localData['psprice']?.toString() ?? '',
                            'packagenum': _localData['packagenum']?.toString() ?? '',
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

  /// 选择规格或单位
  Future<void> _onSelect(String type) async {
    final result = await widget.onSelectUnitSize?.call(type);
    if (result == null || !mounted) return;
    final data = _localData;
    // 统一更新字段（lxAss selectUnitFn/selectSizeFn 对应字段映射）
    if (type == 'unit') {
      data['unit'] = _nonNullStr(result['unit']);
      final uoid = _nonNullStr(result['unitonlyid']);
      data['unitonlyid'] = uoid;
      if (uoid.isNotEmpty) {
        data['size'] = data['_mainSize']?.toString() ?? data['size'];
        data['sizeonlyid'] = data['_mainSizeonlyid']?.toString() ?? '';
      }
    } else if (type == 'size') {
      if (data['_mainSize'] == null) {
        data['_mainSize'] = data['size'];
        data['_mainSizeonlyid'] = data['sizeonlyid'] ?? '';
      }
      data['size'] = _nonNullStr(result['size']);
      data['sizeonlyid'] = _nonNullStr(result['sizeonlyid']);
    }
    // 价格
    final priceStr = _nonNullStr(result['price']);
    if (priceStr.isNotEmpty) {
      final price = num.tryParse(priceStr);
      if (price != null) {
        data['price'] = price;
        _priceCtrl.text = MathUtils.formatDecimal(2, price);
      }
    }
    // 零售价
    final sp = _nonNullStr(result['sellprice']);
    if (sp.isNotEmpty) {
      data['sellprice'] = sp;
      data['saleprice'] = _fd2(sp);
    }
    final rp = _nonNullStr(result['retailprice']);
    if (rp.isNotEmpty) data['retailprice'] = rp;
    // 其他字段
    final sq = _nonNullStr(result['stockqty']);
    if (sq.isNotEmpty) data['stockqty'] = sq;
    final bc = _nonNullStr(result['barcode']);
    if (bc.isNotEmpty) data['barcode'] = bc;
    final rfp = _nonNullStr(result['refprice']);
    if (rfp.isNotEmpty) data['refprice'] = rfp;
    final ip = _nonNullStr(result['inprice']);
    if (ip.isNotEmpty) data['inprice'] = ip;
    final cp = _nonNullStr(result['costprice']);
    if (cp.isNotEmpty) data['costprice'] = cp;
    final cd = _nonNullStr(result['code']);
    if (cd.isNotEmpty) data['code'] = cd;
    final cp1 = _nonNullStr(result['custprice']);
    if (cp1.isNotEmpty) data['custprice'] = cp1;
    final pp1 = _nonNullStr(result['pfprice1']);
    if (pp1.isNotEmpty) data['pfprice1'] = pp1;
    final pp2 = _nonNullStr(result['pfprice2']);
    if (pp2.isNotEmpty) data['pfprice2'] = pp2;
    final pp3 = _nonNullStr(result['pfprice3']);
    if (pp3.isNotEmpty) data['pfprice3'] = pp3;
    final mp1 = _nonNullStr(result['mprice1']);
    if (mp1.isNotEmpty) data['mprice1'] = mp1;
    final mp2 = _nonNullStr(result['mprice2']);
    if (mp2.isNotEmpty) data['mprice2'] = mp2;
    final mp3 = _nonNullStr(result['mprice3']);
    if (mp3.isNotEmpty) data['mprice3'] = mp3;
    final psp = _nonNullStr(result['psprice']);
    if (psp.isNotEmpty) data['psprice'] = psp;
    final pn = _nonNullStr(result['packagenum']);
    if (pn.isNotEmpty) data['packagenum'] = pn;
    setState(() {});
  }

  static String _nonNullStr(dynamic v) => v?.toString() ?? '';

  /// 健壮化读取零售价：sellprice → retailprice → saleprice，跳过空串和 0
  static double _readPrice(Map<String, dynamic> d) {
    double? tryParse(String? s) {
      if (s == null || s.isEmpty) return null;
      final v = double.tryParse(s);
      return v;
    }

    return tryParse(_nonNullStr(d['sellprice'])) ??
        tryParse(_nonNullStr(d['retailprice'])) ??
        tryParse(_nonNullStr(d['saleprice'])) ??
        0;
  }

  /// 可选择字段（单位/规格）
  Widget _buildSelectField({required String label, required String value, VoidCallback? onTap}) {
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
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: Color(0xFF9CA3AF),
              ),
          ],
        ),
      ),
    );
  }

  /// 金额只读字段
  Widget _buildAmountField() {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final amount = MathUtils.mul(qty, price);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 80,
            child: Text('金额', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
          ),
          Expanded(
            child: Text(
              MathUtils.formatDecimal(3, amount),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF111827),
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
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.number,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
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
              enabled: !readOnly,
              onChanged: onChanged,
              keyboardType:
                  isDecimal ? const TextInputType.numberWithOptions(decimal: true) : keyboardType,
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

  /// 商品批次选择
  Widget _buildBatchSelectField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: widget.readOnly
            ? null
            : () async {
                final productid =
                    _localData['productid']?.toString() ?? _localData['prodid']?.toString() ?? '';
                if (productid.isEmpty) {
                  Toast.show('商品信息异常');
                  return;
                }
                final result = await SelectBatchSheet.show(
                  context,
                  productid: productid,
                  bsid: (widget.bsid ?? '').toString(),
                  counterid: widget.counterid ?? '',
                  initialBatchNo: _batchCtrl.text,
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
              },
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text('商品批次',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                _batchCtrl.text.isNotEmpty ? _batchCtrl.text : '请选择',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: _batchCtrl.text.isNotEmpty
                      ? const Color(0xFF111827)
                      : const Color(0xFFD1D5DB),
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (!widget.readOnly)
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }

  /// 只读日期显示字段
  Widget _buildReadonlyDateField({required String label, required String text}) {
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
            child: Text(
              text.isNotEmpty ? text : '-',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: text.isNotEmpty ? const Color(0xFF6B7280) : const Color(0xFFD1D5DB),
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  static Widget _buildDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));
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
