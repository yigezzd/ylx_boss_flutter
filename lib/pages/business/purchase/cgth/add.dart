import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/attach/attach_page.dart';
import 'package:flutter_deer/components/select/select_batch.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_refbill.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
import 'package:flutter_deer/models/scan_settings.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/not_master_product_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/load_image.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:flutter_deer/widgets/select_field_item.dart';
import 'package:flutter_deer/widgets/voice_recognition_dialog.dart';
import 'package:sp_util/sp_util.dart';

enum _CTAction { none, save, sign, delete, retsign, print, withdraw }

class PurchaseCgthAddPage extends StatefulWidget {
  const PurchaseCgthAddPage({super.key, this.billData});
  final Map<String, dynamic>? billData;

  @override
  State<PurchaseCgthAddPage> createState() => _PurchaseCgthAddPageState();
}

class _PurchaseCgthAddPageState extends State<PurchaseCgthAddPage>
    with LogPageMixin<PurchaseCgthAddPage> {
  @override
  String get logPageName => _isEdit ? '采购退货详情' : '采购退货新增';

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _supController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _buyerController = TextEditingController();
  final TextEditingController _warehouseController = TextEditingController();
  final TextEditingController _refbillnoController = TextEditingController();

  // ---- 红外扫描 ----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;
  late ScanSettings _scanSettings;

  String? _supid;
  int? _storeid;
  String? _counterid;
  String? _buyerid;
  String? _buyername;
  String? _storename;
  int? _storetype;
  int _refbilltype = 1; // 1=采购入库单, 2=退货申请单
  String? _refbillid; // 原单 ID（对齐 Vue refbillid，保存时随表单提交）
  int? _countertype; // 仓库存储方式（对齐 Vue countertype）
  bool _isTipNotMasterProduct = true; // 非供货资格商品校验标志

  _CTAction _submitAction = _CTAction.none;
  bool _detailLoading = false;

  // ---- 批量选择 ----
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

  /// 附件列表
  List<Map<String, dynamic>> _fileLists = [];

  bool get _isEdit =>
      (_newBillid != null && _newBillid!.isNotEmpty) ||
      (widget.billData != null && (widget.billData!['billid']?.toString().isNotEmpty ?? false));
  bool get _isSigned => _billData?['signflag']?.toString() == '1';
  bool get _isRejected => _billData?['signflag']?.toString() == '2';
  bool get _isWithdrawPending => _billData?['reviewsignflag']?.toString() == '2';

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
    } catch (e) {
      debugPrint('[退货新增] store 解析异常: $e');
    }
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

    // 新增模式：初始化审批签字按钮可见性
    if (!_isEdit) {
      _initSignUserBtn();
    }

    // 自动拉取默认仓库（取第一个）
    _loadDefaultWarehouse();
  }

  /// 自动拉取当前机构的默认退货仓库（对齐 Vue selectCom isInit + isCurrentOut 逻辑）
  /// 规则：区域中心(storetype==4)不赋值；过滤 retflag==1 的退货仓库，
  /// 按 countertype 升序排序取第一个
  void _loadDefaultWarehouse() {
    if (_storeid == null) return;
    // 区域中心不赋值默认仓库（对齐 Vue）
    if (_storetype == 4) return;
    request(HttpApi.counterGetList, {
      'sids': _storeid.toString(),
      'stopflag': 0,
      'cond': '',
      'is_page': 1,
      'page': 1,
      'pagesize': 50,
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      List<dynamic> list = [];
      if (data is Map<String, dynamic>) {
        list = (data['list'] as List?) ?? [];
      } else if (data is List) {
        list = data;
      }
      // 过滤退货仓库(retflag==1)，按 countertype 升序排序（对齐 Vue isCurrentOut）
      final candidates = list
          .whereType<Map<String, dynamic>>()
          .where((item) => item['retflag']?.toString() == '1')
          .toList()
        ..sort((a, b) {
          final ta = _parseIntFlexible(a, ['countertype']) ?? 0;
          final tb = _parseIntFlexible(b, ['countertype']) ?? 0;
          return ta.compareTo(tb);
        });
      // 过滤后为空时回退取第一个仓库，保证默认仓库功能生效
      final pool =
          candidates.isNotEmpty ? candidates : list.whereType<Map<String, dynamic>>().toList();
      if (pool.isEmpty) return;
      final first = pool.first;
      setState(() {
        _counterid = first['counterid']?.toString();
        _warehouseController.text = first['countername']?.toString() ?? '';
        _countertype = _parseIntFlexible(first, ['countertype']);
      });
    }).catchError((Object e) {
      debugPrint('[退货新增] 默认仓库拉取失败: $e');
    });
  }

  /// 清除所有商品的批次信息（对齐 Vue clearBatchInfo）
  void _clearBatchInfo() {
    for (final row in _items) {
      row.batchno = '';
      if (row.rawData != null) {
        row.rawData!['batchno'] = '';
        row.rawData!['birthdate'] = '';
        row.rawData!['validdate'] = '';
      }
    }
  }

  /// 供应商/机构/仓库切换后刷新商品价格（对齐 Vue updateCgPrice）
  /// 使用批量 API /cgstockin/updateCgPrice 一次性更新所有商品价格
  Future<void> _refreshProductPrices() async {
    if (_items.isEmpty) return;

    // 构建请求参数（对齐 Vue updateCgPrice）
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
      'bsid': _storeid ?? '',
      'supid': _supid ?? '',
      'counterid': _counterid ?? '',
      'detaillist': detaillist,
    };
    // 编辑模式：带入已有单据信息（对齐 Vue cloneDeep(form)）
    if (_billData != null) {
      params['billid'] = _billData!['billid']?.toString() ?? _newBillid ?? '';
      params['billtypeid'] = _billData!['billtypeid']?.toString() ?? '0507';
    } else if (_newBillid != null && _newBillid!.isNotEmpty) {
      params['billid'] = _newBillid;
    }
    debugPrint(
        '[updateCgPrice-cgth] bsid=${params['bsid']}, supid=${params['supid']}, billid=${params['billid']}, items=${detaillist.length}');

    try {
      final result = await request(HttpApi.purchaseUpdateCgPrice, params);
      if (!mounted) return;

      final responseData = result['data'];
      final list = (responseData is List ? responseData : responseData?['list']) as List? ?? [];

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

          // 更新库存
          row.stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;

          // 重算金额
          final qty = MathUtils.formatDecimalNum(1, double.tryParse(row.qtyController.text) ?? 0);
          row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
          row.amtController.text = MathUtils.formatDecimal(3, row.amt);
        }
      });
    } catch (e) {
      debugPrint('[updateCgPrice] 刷新价格失败: $e');
    }
  }

  /// 构建商品查询参数（对齐 Vue mergDataFn），含 memorytype 条件
  Map<String, dynamic> _buildMergData() {
    final obj = <String, dynamic>{
      'stockflag': 1,
      'storeid': _storeid ?? '',
      'counterid': _counterid ?? '',
      'cgpriceflag': 1,
      'billsupid': _supid ?? '',
      'itemstatusin': '1,2,3,4',
      'itemtypenot': '5,8',
    };
    final st = _storetype ?? 0;
    final ct = _countertype ?? 0;
    if ((st == 0 || st == 3) && !(st == 0 && ct == 0)) {
      obj['memorytype'] = ct;
    }
    return obj;
  }

  /// 判断是否需要按 memorytype 过滤商品
  bool get _shouldFilterByMemoryType {
    final st = _storetype ?? 0;
    final ct = _countertype ?? 0;
    return (st == 0 || st == 3) && !(st == 0 && ct == 0);
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
    _warehouseController.dispose();
    _refbillnoController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  // =================== 编辑模式：加载单据详情 ===================
  void _loadDetail([Map<String, dynamic>? overrideParams]) {
    setState(() => _detailLoading = true);
    _isTipNotMasterProduct = true; // 对齐 Vue getInfo：重置非主供货商校验标志
    final Map<String, dynamic> params =
        overrideParams ?? Map<String, dynamic>.from(widget.billData!);

    request(HttpApi.cgthGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _supController.text = data['supname']?.toString() ?? '';
          _storeController.text = data['storename']?.toString() ?? '';
          _buyerController.text = data['buyername']?.toString() ?? '';
          _remarkController.text = data['remark']?.toString() ?? '';
          _fileLists = (data['fileLists'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _warehouseController.text = data['countername']?.toString() ?? '';
          _refbillnoController.text = data['refbillno']?.toString() ?? '';
          _refbillid = data['refbillid']?.toString();
          _supid = data['supid']?.toString();
          _storeid = _parseIntFlexible(data, ['bsid', 'storeid']);
          _storename = data['storename']?.toString();
          _storetype = _parseIntFlexible(data, ['storetype']);
          _counterid = data['counterid']?.toString();
          _buyerid = data['buyerid']?.toString();
          _buyername = data['buyername']?.toString();
          _refbilltype = _parseIntFlexible(data, ['refbilltype']) ?? 1;
          _countertype = _parseIntFlexible(data, ['countertype']);
          // 多级审批数据
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            _items.add(_buildRowFromRaw(Map<String, dynamic>.from(v)));
          }
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  /// 由原始明细数据构建明细行（对齐 Vue handleProperty：price 优先取 cgprice，amt 由 qty*price 重算）
  _DetailRow _buildRowFromRaw(Map<String, dynamic> c) {
    final cgprice = double.tryParse(c['cgprice']?.toString() ?? '') ?? 0;
    final oldPrice = double.tryParse(c['price']?.toString() ?? '') ?? 0;
    final price = cgprice != 0 ? cgprice : oldPrice;
    c['price'] = double.parse(price.toStringAsFixed(2));
    final qtyLoad = double.tryParse(c['qty']?.toString() ?? '') ?? 0;
    final row = _DetailRow();
    row.prodid = c['prodid']?.toString() ?? c['productid']?.toString() ?? '';
    row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
    row.qtyController.text = MathUtils.formatDecimal(1, qtyLoad);
    row.priceController.text = MathUtils.formatDecimal(2, price);
    row.batchno = c['batchno']?.toString() ?? '';
    // 对齐 Vue handleProperty：amt 始终由 qty*price 重算
    row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qtyLoad, price));
    row.amtController.text = MathUtils.formatDecimal(3, row.amt);
    row.giftQtyController.text = c['presentqty']?.toString() ?? c['giftqty']?.toString() ?? '0';
    row.remarkController.text = c['remark']?.toString() ?? '';
    // 门店库存（对齐 Vue stockqty，用于负库存校验）
    row.stockqty = double.tryParse(c['stockqty']?.toString() ?? '') ?? 0;
    // 计算件数 = 数量 / 包装数
    final packagenum = double.tryParse(c['packagenum']?.toString() ?? '') ?? 1;
    row.jsQtyController.text = packagenum > 0 ? (qtyLoad / packagenum).toStringAsFixed(1) : '0';
    row.rawData = c;
    return row;
  }

  // =================== 原单号选择（对齐 Vue openRefbilltype + jumpPge + getYhInfo） ===================
  Future<void> _onTapRefbill() async {
    // 前置校验（对齐 Vue openRefbilltype）
    if (_storeid == null) {
      Toast.show('请选择收货机构');
      return;
    }
    if (_refbilltype == 1 && (_supid == null || _supid!.isEmpty)) {
      Toast.show('请选择供应商');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请选择退货仓库');
      return;
    }

    // 有商品时弹出确认（对齐 Vue jumpPge：选择单据会清空当前商品）
    if (_items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提示'),
          content: const Text('选择单据会清空当前商品，是否继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    // 对齐 Vue buildMergData：机构为总部/门店时按仓库存储方式过滤库存
    final Map<String, dynamic> extraListParams = {};
    if (_shouldFilterByMemoryType && _countertype != null) {
      extraListParams['memorytype'] = _countertype;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectRefbillPage(
          bsid: _storeid,
          storename: _storename,
          // 对齐 Vue refbilltypeList：采购入库单 / 退货申请单
          customTypes: const [
            {
              'value': 1,
              'label': '采购入库单',
              'path': HttpApi.purchaseInstoreList,
              'infoPath': HttpApi.purchaseInstoreGetInfo,
              'listParams': {'billtype': 1},
            },
            {
              'value': 2,
              'label': '退货申请单',
              'path': HttpApi.cgzcFindList,
              'infoPath': HttpApi.cgzcGetInfo,
              // 退货申请单列表不传 refdhflag（对齐小程序 cgthsq/search 参数，cgzc/findList 无此过滤项）
              'sendRefdhflag': false,
              'listParams': {'billtype': 2},
            },
          ],
          extraListParams: extraListParams.isEmpty ? null : extraListParams,
        ),
      ),
    );
    if (result != null && mounted) {
      _fillItemsFromRefbill(result);
    }
  }

  /// 回填原单数据（对齐 Vue getYhInfo + orderConfirm）
  void _fillItemsFromRefbill(Map<String, dynamic> result) {
    final rType = int.tryParse(result['refbilltype']?.toString() ?? '') ?? 1;
    final info = result['info'];
    if (info is! Map<String, dynamic>) return;
    setState(() {
      _refbilltype = rType;
      _refbillnoController.text =
          info['billno']?.toString() ?? result['refbillno']?.toString() ?? '';
      _refbillid = info['billid']?.toString() ?? result['refbillid']?.toString();

      // 回填机构（对齐 Vue orderConfirm）
      final bsid = _parseIntFlexible(info, ['bsid', 'storeid']);
      if (bsid != null) {
        _storeid = bsid;
        _storename = info['storename']?.toString();
        _storeController.text = _storename ?? '';
      }
      // 采购入库单额外回填供应商/退货仓库
      if (rType == 1) {
        _supid = info['supid']?.toString();
        _supController.text = info['supname']?.toString() ?? '';
        _counterid = info['counterid']?.toString();
        _warehouseController.text = info['countername']?.toString() ?? '';
      }

      // 回填明细（对齐 Vue orderConfirm：计算剩余可退数量）
      final list = info['detaillist'] as List? ?? [];
      for (final row in _items) {
        row.dispose();
      }
      _items.clear();
      for (final v in list) {
        if (v is! Map) continue;
        final c = Map<String, dynamic>.from(v);
        final qty = double.tryParse(c['qty']?.toString() ?? '') ?? 0;
        if (rType == 1) {
          final returnedqty = double.tryParse(c['returnedqty']?.toString() ?? '') ?? 0;
          c['qty'] = qty - returnedqty;
          final presentqty = double.tryParse(c['presentqty']?.toString() ?? '') ?? 0;
          final presentreturnedqty =
              double.tryParse(c['presentreturnedqty']?.toString() ?? '') ?? 0;
          c['presentqty'] = presentqty - presentreturnedqty;
        } else {
          final orderedqty = double.tryParse(c['orderedqty']?.toString() ?? '') ?? 0;
          c['qty'] = qty - orderedqty;
        }
        _items.add(_buildRowFromRaw(c));
      }
    });
  }

  // =================== 提交保存 ===================
  void _submit({bool isDraft = false, bool withSign = false}) {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('011903', showTip: false)) {
        Toast.show('你无权编辑采购退货，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('011902', showTip: false)) {
        Toast.show('你无权新增采购退货，请在后台修改权限');
        return;
      }
    }
    // 操作审计：提交保存
    logSave(_isEdit ? '保存修改' : (isDraft ? '存为草稿' : (withSign ? '保存并审核' : '保存单据')));

    if (!_isSigned) {
      if (_supid == null || _supid!.isEmpty) {
        Toast.show('请选择供应商');
        return;
      }
      if (_storeid == null) {
        Toast.show('请选择退货机构');
        return;
      }
      if (_counterid == null || _counterid!.isEmpty) {
        Toast.show('请选择退货仓库');
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

    // 数量校验：qty==0 && presentqty==0 时阻止保存（对齐 Vue _save 校验）
    for (final row in submitItems) {
      final qty = double.tryParse(row.qtyController.text) ?? 0;
      final presentqty = double.tryParse(row.giftQtyController.text) ?? 0;
      if (qty == 0 && presentqty == 0) {
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
            _submit(isDraft: isDraft, withSign: withSign);
          });
          return;
        }
      }
    }

    // 进价校验：商品进价只能改低不能改高（对齐 Vue cgpriceflag）
    final userStr = SpUtil.getString(Constant.user) ?? '';
    if (userStr.isNotEmpty) {
      try {
        final userMap = jsonDecode(userStr) as Map<String, dynamic>;
        final cgpriceflag = int.tryParse(userMap['cgpriceflag']?.toString() ?? '0') ?? 0;
        if (cgpriceflag == 1) {
          final priceViolations = submitItems.where((row) {
            final raw = row.rawData ?? {};
            final inprice = double.tryParse(raw['inprice']?.toString() ?? '') ?? -1;
            final oldprice = double.tryParse(raw['oldprice']?.toString() ?? '') ?? 0;
            final comparePrice = inprice >= 0 ? inprice : oldprice;
            final curPrice = double.tryParse(row.priceController.text) ?? 0;
            return (row.prodid ?? '').isNotEmpty && curPrice > comparePrice && comparePrice != 0;
          }).toList();
          if (priceViolations.isNotEmpty) {
            Toast.show('商品进价只能改低不能改高！');
            return;
          }
        }
      } catch (_) {}
    }

    // 批次校验（对齐 Vue batchValidateFlag / cgValidateProductBatchFlag）
    final loginCfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
    if (loginCfgStr.isNotEmpty) {
      try {
        final loginCfg = jsonDecode(loginCfgStr) as Map<String, dynamic>;
        // batchValidateFlag: 生产日期和批次必须同时录入
        final batchValidateFlag =
            int.tryParse(loginCfg['batchValidateFlag']?.toString() ?? '0') ?? 0;
        if (batchValidateFlag == 1) {
          final batchViolations = submitItems.where((row) {
            if ((row.prodid ?? '').isEmpty) return false;
            final batchno = row.batchno;
            final validdate = row.rawData?['validdate']?.toString() ?? '';
            return batchno.isEmpty || validdate.isEmpty;
          }).toList();
          if (batchViolations.isNotEmpty) {
            Toast.show('生产日期和批次必须同时录入！');
            return;
          }
        }
        // cgValidateProductBatchFlag: 管理保质期商品必须输入批次
        final cgValidateProductBatchFlag =
            int.tryParse(loginCfg['cgValidateProductBatchFlag']?.toString() ?? '0') ?? 0;
        if (cgValidateProductBatchFlag == 1) {
          final batchViolations = submitItems.where((row) {
            if ((row.prodid ?? '').isEmpty) return false;
            final batchno = row.batchno;
            final validflag = int.tryParse(row.rawData?['validflag']?.toString() ?? '0') ?? 0;
            return batchno.isEmpty && validflag == 1;
          }).toList();
          if (batchViolations.isNotEmpty) {
            Toast.show('管理保质期商品必须输入批次！');
            return;
          }
        }
      } catch (_) {}
    }

    setState(() => _submitAction = _CTAction.save);

    final detaillist = _buildSubmitDetailList();
    double totalQty = 0;
    double totalAmt = 0;
    double totalSellAmt = 0;
    for (final item in detaillist) {
      totalQty = MathUtils.add(totalQty, double.tryParse(item['qty']?.toString() ?? '0') ?? 0);
      totalAmt = MathUtils.add(totalAmt, double.tryParse(item['amt']?.toString() ?? '0') ?? 0);
      totalSellAmt =
          MathUtils.add(totalSellAmt, double.tryParse(item['sellamt']?.toString() ?? '0') ?? 0);
    }

    final Map<String, dynamic> params;
    if (_isEdit) {
      params = Map<String, dynamic>.from(_billData!);
    } else {
      final now = DateTime.now();
      String p2(int v) => v.toString().padLeft(2, '0');
      // 对齐后台 cgth/edit.vue formDefault：billdate 含时分秒、billtype:2、
      // freeamt:0、refbillno、batchno 等（refbilltype 由下方统一赋值，默认 1）
      final billdate =
          '${now.year}-${p2(now.month)}-${p2(now.day)} ${p2(now.hour)}:${p2(now.minute)}:${p2(now.second)}';
      params = {
        'name': '',
        'startdate': '',
        'enddate': '',
        'signflag': 0,
        'freeamt': 0,
        'refbillno': '',
        'batchno': '',
        'billtype': 2,
        'billdate': billdate,
        'status': 3,
        'fileLists': _fileLists,
      };
    }

    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt);
    params['billsellamt'] = MathUtils.roundTo(totalSellAmt);
    params['detaillist'] = detaillist;
    params['fileLists'] = _fileLists;
    params['remark'] = _remarkController.text.trim();
    params['supname'] = _supController.text.trim();
    params['supid'] = _supid ?? '';
    params['bsid'] = _storeid ?? '';
    params['storename'] = _storename ?? '';
    params['storetype'] = _storetype ?? '';
    params['buyerid'] = _buyerid ?? '';
    params['buyername'] = _buyername ?? '';
    params['counterid'] = _counterid ?? '';
    params['countername'] = _warehouseController.text.trim();
    params['refbilltype'] = _refbilltype;
    // 对齐 Vue：原单号/原单 ID 随表单提交（deepClone(query) 包含 refbillno/refbillid）
    params['refbillno'] = _refbillnoController.text.trim();
    params['refbillid'] = _refbillid ?? '';

    request(HttpApi.cgthSave, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '保存成功');
      _isTipNotMasterProduct = true; // 对齐 Vue：保存成功后重置
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
        // 保存后若需审核
        if (withSign) {
          _doSignAfterSave(retData);
        }
      } else {
        if (!_isEdit) Navigator.pop(context, true);
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _CTAction.none);
    });
  }

  /// 审核（已保存的单据直接审核，多级审批时弹出审批弹窗）
  Future<void> _sign() async {
    if (!PermissionUtils.checkPermission('011905', showTip: false)) {
      Toast.show('你无权审核采购退货，请在后台修改权限');
      return;
    }
    if (_billData == null) return;

    // 负库存校验（对齐 Vue checkStockLess）
    final stockOk = await _checkStockLess();
    if (!stockOk) return; // 用户取消或库存不足未处理

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

  /// 执行审核操作（对齐 Vue doSign）
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
    setState(() => _submitAction = _CTAction.sign);
    request(HttpApi.cgthSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _CTAction.none);
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

    // 负库存校验（对齐 Vue checkStockLess）
    _checkStockLess().then((stockOk) {
      if (!stockOk || !mounted) return;

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
    });
  }

  /// 负库存校验（对齐 Vue checkStockLess）
  /// 检查是否有商品退货数量超过门店库存（stockqty < qty），若有则弹窗提示用户修改数量或删除商品
  /// 返回 true 表示校验通过（无负库存或用户已处理），false 表示用户取消或阻止模式下仍有库存不足
  Future<bool> _checkStockLess() async {
    // 对齐 Vue 端 stocksaleflag → storageNotEnoughFlag 映射逻辑
    int storageNotEnoughFlag;
    final stocksaleflag = _billData?['stocksaleflag']?.toString() ?? '';
    if (stocksaleflag.isEmpty) {
      int? globalFlag;
      try {
        final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
        if (cfgStr.isNotEmpty) {
          final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
          globalFlag = int.tryParse(cfg['storageNotEnoughFlag']?.toString() ?? '');
        }
      } catch (_) {}
      // 缺少该参数时默认按 3（阻止校验）处理，保证负库存不能出库（对齐小程序端）
      storageNotEnoughFlag = globalFlag ?? 3;
    } else if (stocksaleflag == '1') {
      storageNotEnoughFlag = 2;
    } else if (stocksaleflag == '2') {
      storageNotEnoughFlag = 1;
    } else {
      storageNotEnoughFlag = int.tryParse(stocksaleflag) ?? 3;
    }
    // 与 Vue 端一致：仅 storageNotEnoughFlag 为 2 或 3 时执行负库存校验
    if (storageNotEnoughFlag != 2 && storageNotEnoughFlag != 3) return true;

    // 库存不足商品识别规则（对齐 Vue）：stockqty < qty
    List<_DetailRow> findInsufficient() => _items
        .where((row) =>
            (row.prodid ?? '').isNotEmpty &&
            row.stockqty < (double.tryParse(row.qtyController.text) ?? 0))
        .toList();

    final lessItems = findInsufficient();
    if (lessItems.isEmpty) return true; // 无负库存，校验通过

    // 弹窗文案对齐 Vue 端：警告模式(2)可继续审核，阻止模式(3)需修改数量后再审核
    final isWarning = storageNotEnoughFlag == 2;
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

    if (result == null) return false; // 用户取消

    // 用户确认后，更新 _items（删除的商品移除，数量修改已在弹窗确认时同步到 row.qtyController）
    setState(() {
      _items.removeWhere((row) => !result.contains(row));
    });

    // 阻止模式：修改后若仍有库存不足，禁止审核（避免负库存审核通过）
    if (!isWarning && findInsufficient().isNotEmpty) {
      Toast.show('库存不足，请修改数量后再审核');
      return false;
    }
    return true;
  }

  /// 审批操作弹窗（通过/驳回 + 备注）
  Future<Map<String, dynamic>?> _showApprovalDialog({int defaultFlag = 1}) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ApprovalDialog(defaultFlag: defaultFlag),
    );
  }

  /// 反审核
  Future<void> _retsign() async {
    if (_billData == null) return;

    // 多级审批提示
    String tipMsg = '确定反审核单据吗？';
    if (_reviewBillFlows.isNotEmpty) {
      tipMsg = '反审核后，所有审批步骤需重新处理！确定反审核吗？';
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

    setState(() => _submitAction = _CTAction.retsign);
    // 构造完整反审核参数（对齐 Vue fsignFn 发送 query.value 完整单据对象）：
    // Vue 端 query 初始即含 billdate/billtype/detaillist 等字段，后端 retsign 写入
    // t_supplier_flow 时强依赖 billdate，此处对缺失的关键字段做兜底补充
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
      params['billtypeid'] = '0507';
    }
    params['billtype'] ??= 2;
    final dl = params['detaillist'];
    if (dl is! List || dl.isEmpty) {
      params['detaillist'] = _buildSubmitDetailList();
    }
    request(HttpApi.cgthRetsign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '反审成功');
      _loadDetail(params);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _CTAction.none);
    });
  }

  /// 撤回操作
  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('011906', showTip: false)) {
      Toast.show('你无权反审核采购退货，请在后台修改权限');
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

    setState(() => _submitAction = _CTAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.cgthSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _CTAction.none);
    });
  }

  /// 新增模式：初始化审批签字按钮可见性
  void _initSignUserBtn() {
    if (_isAdmin) return;
    if (!_isEdit && _storeid != null) {
      request(HttpApi.reviewTypeConfigGetNewBillSignUser, {
        'billtypeid': '0507',
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

  /// 删除单据
  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('011904', showTip: false)) {
      Toast.show('你无权删除采购退货，请在后台修改权限');
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

    setState(() => _submitAction = _CTAction.delete);
    request(HttpApi.cgthDelBill, _billData).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _CTAction.none);
    });
  }

  /// 打印单据
  Future<void> _print() async {
    if (_billData == null) return;
    final printParams = {
      'menuid': '050701',
      'data': _billData,
    };
    setState(() => _submitAction = _CTAction.print);
    request(HttpApi.cgthPrint, printParams).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _CTAction.none);
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

  // =================== 扫码 ===================
  /// 处理扫码结果：若商品已存在则累加数量，否则新增商品行
  /// [returnFocusNode] 有值时，扫码完成后焦点回到该节点（用于红外扫描框连续扫码）
  void _handleScannedBarcode(String code, {FocusNode? returnFocusNode}) {
    if (code.trim().isEmpty) return;
    if (_storeid == null) {
      Toast.show('请先选择退货机构');
      return;
    }
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
      return;
    }

    // 尝试解析条码秤生成的重量码/金额码
    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;

    debugPrint('[退货扫描] 开始查询条码: $code, searchCode=$searchCode, scaleType=${scaleInfo?.type}');
    final params = {
      'scancode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      ..._buildMergData(),
    };
    request(HttpApi.productGetList, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
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

        // 根据条码秤类型计算数量增量
        double qtyDelta;
        if (scaleInfo?.type == 'weight') {
          qtyDelta = scaleInfo!.qty ?? 1;
        } else if (scaleInfo?.type == 'amount') {
          // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
          final scaleCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
          final price = scaleCgprice != 0
              ? scaleCgprice
              : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
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
                existing.qtyController.text = MathUtils.formatDecimal(1, newQty);
                final pn = double.tryParse(existing.rawData?['packagenum']?.toString() ?? '') ?? 1;
                existing.jsQtyController.text = pn > 0 ? (newQty / pn).toStringAsFixed(1) : '0';
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
          // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
          final scanCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
          final price = scanCgprice != 0
              ? scanCgprice
              : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
          final batchno = prod['batchno']?.toString() ?? '';
          final row = _DetailRow();
          row.prodid = prodid;
          row.nameController.text =
              prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
          row.qtyController.text = MathUtils.formatDecimal(1, qtyDelta);
          row.priceController.text = MathUtils.formatDecimal(2, price);
          row.batchno = batchno;
          row.rawData = Map<String, dynamic>.from(prod);
          final pn = double.tryParse(prod['packagenum']?.toString() ?? '') ?? 1;
          row.jsQtyController.text = pn > 0 ? (qtyDelta / pn).toStringAsFixed(1) : '0';
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
            _showNewModeDetailDrawer(targetIndex);
          }
        } else {
          // 默认累加1模式：焦点处理
          _focusAfterScan(returnFocusNode, targetRow: targetRow);
        }
      } else {
        if (mounted) Toast.show('未找到匹配商品，请重新扫码录入！');
        _focusAfterScan(returnFocusNode);
      }
    }).catchError((Object e) {
      debugPrint('[退货扫描] 接口异常: $e');
      if (mounted) Toast.show('查询商品失败: $e');
      _focusAfterScan(returnFocusNode);
    });
  }

  /// 扫码后焦点处理
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
        // 连续扫码关闭：焦点转移到数量输入框（退货页面无数输入框，回扫描框）
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

  /// 扫码弹窗模式：打开商品详情抽屉手动确认数量
  Future<void> _showNewModeDetailDrawer(int index) async {
    if (index >= _items.length) return;
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
          initialBatch: row.batchno,
          initialBirthdate: raw['birthdate']?.toString() ?? '',
          initialValiddate: raw['validdate']?.toString() ?? '',
          initialRemark: row.remarkController.text,
          bsid: _storeid,
          counterid: _counterid,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        row.priceController.text = MathUtils.formatDecimal(2, result['price'] as double);
        final qty = result['qty'] as double;
        row.qtyController.text = MathUtils.formatDecimal(1, qty);
        row.giftQtyController.text = MathUtils.formatDecimal(1, result['giftqty'] as double);
        row.remarkController.text = result['remark']?.toString() ?? '';
        row.batchno = result['batchno']?.toString() ?? '';
        row.rawData = {
          ...raw,
          'birthdate': result['birthdate'],
          'validdate': result['validdate'],
        };
        final pn = double.tryParse(raw['packagenum']?.toString() ?? '') ?? 1;
        row.jsQtyController.text = pn > 0 ? (qty / pn).toStringAsFixed(1) : '0';
        _recalcRow(row);
      });
    }
  }

  /// 语音识别录入商品
  Future<void> _voiceRecognition() async {
    if (_storeid == null) {
      Toast.show('请先选择退货机构');
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
          ..._buildMergData(),
        });

        if (!mounted) return;
        final data = searchResult['data'];
        final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
        if (list.isNotEmpty) {
          final prod = list.first as Map<String, dynamic>;
          setState(() {
            final row = _DetailRow();
            row.prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
            row.nameController.text =
                prod['productname']?.toString() ?? prod['name']?.toString() ?? name;
            row.qtyController.text = MathUtils.formatDecimal(
                1, double.tryParse((item['quantity'] ?? 1).toString()) ?? 1);
            row.priceController.text = MathUtils.formatDecimal(
                2,
                double.tryParse(
                        (item['price'] ?? prod['cgprice'] ?? prod['price'] ?? 0).toString()) ??
                    0);
            row.batchno = prod['batchno']?.toString() ?? '';
            row.rawData = Map<String, dynamic>.from(prod);
            final pn = double.tryParse(prod['packagenum']?.toString() ?? '') ?? 1;
            final qty = double.tryParse(row.qtyController.text) ?? 0;
            row.jsQtyController.text = pn > 0 ? (qty / pn).toStringAsFixed(1) : '0';
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

  void _recalcRow(_DetailRow row) {
    final qty = double.tryParse(row.qtyController.text) ?? 0;
    final price = double.tryParse(row.priceController.text) ?? 0;
    row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
    row.amtController.text = MathUtils.formatDecimal(3, row.amt);
  }

  // =================== 计算汇总 ===================
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
      item['amt'] = MathUtils.formatDecimalNum(
          3, double.tryParse(row.amtController.text) ?? row.amt ?? MathUtils.mul(qty, price));
      item['prodid'] = row.prodid ?? item['productid'] ?? '';
      item['batchno'] = row.batchno;
      item['giftqty'] =
          MathUtils.formatDecimalNum(1, double.tryParse(row.giftQtyController.text) ?? 0);
      item['presentqty'] =
          MathUtils.formatDecimalNum(1, double.tryParse(row.giftQtyController.text) ?? 0);
      item['remark'] = row.remarkController.text.trim();
      // 生产日期 / 有效日期 从 rawData 中取
      item['birthdate'] = row.rawData?['birthdate']?.toString() ?? '';
      item['validdate'] = row.rawData?['validdate']?.toString() ?? '';
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
      map['amt'] = row.amt ?? 0;
      map['unit'] = map['unit']?.toString() ?? '';
      map['size'] = map['size']?.toString() ?? '';
      return map;
    }).toList();
  }

  Future<void> _selectProduct({String? initialKeyword, FocusNode? returnFocusNode}) async {
    if (_storeid == null) {
      Toast.show('请先选择退货机构');
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
          counterid: _counterid,
          billsupid: _supid,
          mergData: _buildMergData(),
          selectList: _buildSelectList(),
          paramJust: const [
            'qty',
            'jsqty',
            'sellprice',
            'presentqty',
            'price',
            'amt',
            'unit',
            'size',
            'batchno',
            'birthdate',
            'validdate',
            'remark'
          ],
          initialKeyword: initialKeyword,
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      // 对齐 Vue cgRetProductQtyFlag：退货商品数量默认使用库存数量
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      int cgRetProductQtyFlag = 0;
      if (cfgStr.isNotEmpty) {
        try {
          final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
          cgRetProductQtyFlag = int.tryParse(cfg['cgRetProductQtyFlag']?.toString() ?? '0') ?? 0;
        } catch (_) {}
      }
      setState(() {
        for (final prod in result) {
          if (cgRetProductQtyFlag == 1) {
            final stockqty = double.tryParse(prod['stockqty']?.toString() ?? '') ?? 0;
            if (stockqty > 0) {
              prod['qty'] = stockqty;
            }
          }
          final prodId = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
          // 对齐采购入库：使用选择页面返回的 qty（用户通过 +/- 或详情抽屉修改后的数量）
          // cgRetProductQtyFlag==1 时上面已覆写为库存数量
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
            final row = _items[existIndex];
            final newQty = (double.tryParse(row.qtyController.text) ?? 0) + selectedQty;
            row.qtyController.text = MathUtils.formatDecimal(1, newQty);
            final newGiftQty = (double.tryParse(row.giftQtyController.text) ?? 0) + selectedGiftQty;
            row.giftQtyController.text = MathUtils.formatDecimal(1, newGiftQty);
            final pn = double.tryParse(row.rawData?['packagenum']?.toString() ?? '') ?? 1;
            row.jsQtyController.text = pn > 0 ? (newQty / pn).toStringAsFixed(1) : '0';
            // 同步选择页返回的新价格（用户可能修改了价格，否则统计栏仍按旧价计算）
            // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
            final syncCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
            final newPrice = syncCgprice != 0
                ? syncCgprice
                : (double.tryParse(prod['price']?.toString() ?? '') ?? 0);
            if (newPrice > 0) {
              row.priceController.text = MathUtils.formatDecimal(2, newPrice);
              if (row.rawData != null) row.rawData!['price'] = newPrice;
            }
            _recalcRow(row);
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
            row.priceController.text = MathUtils.formatDecimal(2, price);
            row.batchno = prod['batchno']?.toString() ?? '';
            final pn = double.tryParse(prod['packagenum']?.toString() ?? '') ?? 1;
            row.jsQtyController.text = pn > 0 ? (selectedQty / pn).toStringAsFixed(1) : '0';
            row.rawData = Map<String, dynamic>.from(prod);
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
          initialBatch: row.batchno,
          initialBirthdate: raw['birthdate']?.toString() ?? '',
          initialValiddate: raw['validdate']?.toString() ?? '',
          initialRemark: row.remarkController.text,
          bsid: _storeid,
          counterid: _counterid,
          readOnly: _readOnly,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        row.priceController.text = MathUtils.formatDecimal(2, result['price'] as double);
        final qty = result['qty'] as double;
        row.qtyController.text = MathUtils.formatDecimal(1, qty);
        row.giftQtyController.text = MathUtils.formatDecimal(1, result['giftqty'] as double);
        row.remarkController.text = result['remark']?.toString() ?? '';
        row.batchno = result['batchno']?.toString() ?? '';
        row.rawData = {
          ...raw,
          'birthdate': result['birthdate'],
          'validdate': result['validdate'],
        };
        // 同步单位/规格
        final unit = result['unit']?.toString();
        if (unit != null) row.rawData!['unit'] = unit;
        final size = result['size']?.toString();
        if (size != null) row.rawData!['size'] = size;
        final unitonlyid = result['unitonlyid']?.toString();
        if (unitonlyid != null) row.rawData!['unitonlyid'] = unitonlyid;
        final sizeonlyid = result['sizeonlyid']?.toString();
        if (sizeonlyid != null) row.rawData!['sizeonlyid'] = sizeonlyid;
        // 同步件数 = 数量 / 包装数
        final pn = double.tryParse(raw['packagenum']?.toString() ?? '') ?? 1;
        row.jsQtyController.text = pn > 0 ? (qty / pn).toStringAsFixed(1) : '0';
        _recalcRow(row);
      });
    }
  }

  // =================== Build ===================
  bool get _readOnly => _isEdit && !_bolHandle;

  /// 粘性表头区域高度常量
  static const double _stickyScanHeight = 68.0;
  static const double _stickyTitleHeight = 40.0;
  static const double _stickyColumnHeight = 36.0;
  static const double _stickyMinExtent = _stickyTitleHeight + _stickyColumnHeight;
  static const double _stickyMaxExtent = _stickyScanHeight + _stickyMinExtent;

  @override
  Widget build(BuildContext context) {
    final String title = _isEdit ? (_isSigned ? '采购退货单详情' : '修改采购退货') : '新增采购退货';

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
              if (_isEdit && _billData != null)
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
              SliverPersistentHeader(
                pinned: true,
                delegate: _CgthStickyDelegate(state: this),
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
                        onTap: () => _editDetail(index),
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
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
              const SizedBox(height: 4),
            ],
            // 不显示红外扫描框时，补充与粘性表头之间的间距
            if (!_isSigned && !_scanSettings.showInfraredInput) const SizedBox(height: 8),
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
                            const SizedBox(width: 10),
                            if (_scanSettings.showCameraButton) ...[
                              GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.push<String>(
                                    context,
                                    MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
                                  );
                                  if (result != null && result.isNotEmpty) {
                                    _handleScannedBarcode(result);
                                  }
                                },
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.qr_code_scanner, size: 16, color: Color(0xFF006EFF)),
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
                    _handleScannedBarcode(code, returnFocusNode: _scanFocusNode);
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

  // =================== 单据信息 ===================
  Widget _buildBillInfoReadonly() {
    return Column(children: [
      _buildReadonlyField(label: '供应商', value: _supController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '退货机构', value: _storeController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      _buildReadonlyField(label: '退货仓库', value: _warehouseController.text),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      if (_refbillnoController.text.isNotEmpty) ...[
        _buildReadonlyField(label: '原单号', value: _refbillnoController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
      ],
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

  Widget _buildBillInfoEditable() {
    return Column(children: [
      SelectFieldItem(
        label: '供应商',
        required: true,
        value: _supController.text,
        onTap: () async {
          final result = await SelectSupplierPage.show(context, initialSelectedId: _supid ?? '');
          if (result != null && mounted) {
            setState(() {
              _supid = result['supid']?.toString() ?? '';
              // 对齐 Vue selectSupFn：只保存供应商名称，不拼接编号
              _supController.text =
                  result['name']?.toString() ?? result['supname']?.toString() ?? '';
              // 对齐 Vue selectSupFn：供应商变更时刷新商品价格
              _refreshProductPrices();
            });
          }
        },
      ),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
        label: '退货机构',
        required: true,
        value: _storeController.text,
        onTap: () async {
          final result =
              await SelectStorePage.show(context, initialSelectedId: _storeid?.toString() ?? '');
          if (result != null && mounted) {
            setState(() {
              final storeId = result['storeid']?.toString() ?? '';
              _storeid = int.tryParse(storeId);
              _storename = result['storename']?.toString() ?? '';
              _storetype = int.tryParse(result['storetype']?.toString() ?? '') ?? _storetype;
              _storeController.text = result['storename']?.toString() ?? '';
              // 对齐 Vue selectGodownFn：机构变更时清空仓库/countertype/原单号，刷新价格，清除批次
              _counterid = null;
              _countertype = null;
              _warehouseController.text = '';
              _refbillnoController.clear();
              _refbillid = null; // 对齐清空原单号：同步清空关联的原单 ID
              _refreshProductPrices();
              _clearBatchInfo();
            });
          }
        },
      ),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
        label: '退货仓库',
        required: true,
        value: _warehouseController.text,
        onTap: () async {
          if (_storeid == null) {
            Toast.show('请先选择退货机构');
            return;
          }
          final result = await SelectWarehousePage.show(context,
              bsid: _storeid, initialSelectedId: _counterid ?? '');
          if (result != null && mounted) {
            setState(() {
              _counterid = result['counterid']?.toString() ?? '';
              _warehouseController.text = result['countername']?.toString() ?? '';
              // 对齐 Vue selectGodownFn2：仓库变更时存储 countertype，刷新价格，清除批次
              _countertype = int.tryParse(result['countertype']?.toString() ?? '');
              _refreshProductPrices();
              _clearBatchInfo();
            });
          }
        },
      ),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
      SelectFieldItem(
        label: '原单号',
        value: _refbillnoController.text,
        onTap: _onTapRefbill,
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

  /// 附件按钮行
  Widget _buildAttachButton() {
    return GestureDetector(
      onTap: () async {
        final result = await AttachPage.show(
          context,
          fileLists: _fileLists,
          menuid: '050701',
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
                child: Row(children: [
                  Text(
                    '共${_items.length}项，合计数量：$_totalQty，总金额：$_totalAmt',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ]),
              );
            },
          ),
          // 编辑模式 - 待审核/已驳回
          if (_isEdit && !_isSigned) _buildEditUnsignedButtons(),
          // 编辑模式 - 已审核：反审核 + 打印
          if (_isEdit && _isSigned) _buildEditSignedButtons(),
          // 新增模式：保存 + 审核
          if (!_isEdit) _buildNewBillButtons(),
        ],
      ),
    );
  }

  /// 编辑模式 - 待审核/已驳回：更多(删除/打印) + 保存 + 审核 + 撤回
  Widget _buildEditUnsignedButtons() {
    final bool isLoading = _submitAction != _CTAction.none;
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
          child: _submitAction == _CTAction.save
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
          child: _submitAction == _CTAction.sign
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
          child: _submitAction == _CTAction.withdraw
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

  /// 编辑模式 - 已审核：反审核 + 打印
  Widget _buildEditSignedButtons() {
    final bool isLoading = _submitAction != _CTAction.none;
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
          child: _submitAction == _CTAction.retsign
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
              : const Text('反审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ));
    }

    // 打印按钮
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
        child: _submitAction == _CTAction.print
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
    final bool isLoading = _submitAction != _CTAction.none;
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
        child: _submitAction == _CTAction.save
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
    // 同步 amtController 初始值
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

  /// 金额失焦处理：格式化金额 + 反向计算数量（qty = amt / price）
  void _formatAmtField() {
    final node = widget.row.amtFocusNode;
    if (node.hasFocus) return;
    final value = double.tryParse(_amtCtrl.text);
    if (value != null) {
      final text = MathUtils.formatDecimal(3, value);
      if (text != _amtCtrl.text) _amtCtrl.text = text;
    }
    // 金额编辑后反向计算数量：qty = amt / price
    final amt = double.tryParse(_amtCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    if (price > 0) {
      _qtyCtrl.text = MathUtils.formatDecimal(1, amt / price);
    }
    widget.row.amt = MathUtils.formatDecimalNum(3, amt);
    final raw = widget.row.rawData;
    if (raw != null) {
      raw['amt'] = widget.row.amt;
      raw['qty'] = double.tryParse(_qtyCtrl.text) ?? 0;
    }
    widget.onChanged?.call();
  }

  /// 同步 amtController 文本（外部更新 row.amt 后调用）
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

  @override
  Widget build(BuildContext context) {
    final raw = widget.row.rawData;
    final String productname = widget.row.nameController.text.isNotEmpty
        ? widget.row.nameController.text
        : (raw?['productname']?.toString() ?? raw?['name']?.toString() ?? '-');
    final String unit = raw?['unit']?.toString() ?? '';
    final String size = raw?['size']?.toString() ?? '';
    final String batchno =
        widget.row.batchno.isNotEmpty ? widget.row.batchno : (raw?['batchno']?.toString() ?? '');
    final displayName =
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
                      if (batchno.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('批次：$batchno',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 右侧：可编辑数值字段
              Expanded(
                flex: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(children: [
                      // 价格 flex:3
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
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFF006EFF))),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 数量 flex:3
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
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFF006EFF))),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 金额 flex:3（可编辑，失焦反向计算数量）
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
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFF006EFF))),
                            ),
                          ),
                        ),
                      ),
                    ]),
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
  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController(text: '1');
  final FocusNode qtyFocusNode = FocusNode();
  final TextEditingController priceController = TextEditingController();
  final FocusNode priceFocusNode = FocusNode();
  final TextEditingController amtController = TextEditingController();
  final FocusNode amtFocusNode = FocusNode();
  final TextEditingController giftQtyController = TextEditingController(text: '0');
  final TextEditingController jsQtyController = TextEditingController(text: '0');
  final TextEditingController remarkController = TextEditingController();
  String batchno = '';
  double? amt;

  /// 门店库存（对齐 Vue stockqty，用于负库存校验）
  double stockqty = 0;
  Map<String, dynamic>? rawData;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    qtyFocusNode.dispose();
    priceFocusNode.dispose();
    amtFocusNode.dispose();
    amtController.dispose();
    priceController.dispose();
    giftQtyController.dispose();
    jsQtyController.dispose();
    remarkController.dispose();
  }
}

/// 商品详情抽屉（对齐采购入库 _ProDetailSheet 样式，字段按 Vue cgth paramJust 配置）
class _ProDetailSheet extends StatefulWidget {
  const _ProDetailSheet({
    required this.productData,
    required this.initialPrice,
    required this.initialQty,
    required this.initialGiftQty,
    required this.initialBatch,
    required this.initialBirthdate,
    required this.initialValiddate,
    required this.initialRemark,
    this.bsid,
    this.counterid,
    this.readOnly = false,
  });
  final Map<String, dynamic> productData;
  final double initialPrice;
  final double initialQty;
  final double initialGiftQty;
  final String initialBatch;
  final String initialBirthdate;
  final String initialValiddate;
  final String initialRemark;
  final int? bsid;
  final String? counterid;
  final bool readOnly;

  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _giftCtrl;
  late TextEditingController _jsQtyCtrl;
  late TextEditingController _batchCtrl;
  late TextEditingController _birthdateCtrl;
  late TextEditingController _validdateCtrl;
  late TextEditingController _remarkCtrl;

  // 单位/规格状态（对齐 Vue proDetails.vue cgpriceflag 逻辑）
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

  double get _packagenum =>
      double.tryParse(widget.productData['packagenum']?.toString() ?? '') ?? 1;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: widget.initialPrice.toStringAsFixed(2));
    final qty = widget.initialQty;
    _qtyCtrl = TextEditingController(
      text: qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2),
    );
    _giftCtrl = TextEditingController(text: widget.initialGiftQty.toStringAsFixed(0));
    _jsQtyCtrl = TextEditingController(
      text: _packagenum > 0 ? (qty / _packagenum).toStringAsFixed(1) : '0',
    );
    _batchCtrl = TextEditingController(text: widget.initialBatch);
    _birthdateCtrl = TextEditingController(text: widget.initialBirthdate);
    _validdateCtrl = TextEditingController(text: widget.initialValiddate);
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
    // 初始化单位/规格状态
    _currentUnit = widget.productData['unit']?.toString() ?? '';
    _currentSize = widget.productData['size']?.toString() ?? '';
    _unitonlyid = widget.productData['unitonlyid']?.toString() ?? '';
    _sizeonlyid = widget.productData['sizeonlyid']?.toString() ?? '';

    _qtyCtrl.addListener(_syncJsQty);
    _jsQtyCtrl.addListener(_syncQtyFromJs);
  }

  void _syncJsQty() {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final pn = _packagenum;
    final js = pn > 0 ? qty / pn : 0;
    _jsQtyCtrl.removeListener(_syncQtyFromJs);
    _jsQtyCtrl.text = js == js.toInt() ? js.toInt().toString() : js.toStringAsFixed(1);
    _jsQtyCtrl.addListener(_syncQtyFromJs);
  }

  void _syncQtyFromJs() {
    final js = double.tryParse(_jsQtyCtrl.text) ?? 0;
    final pn = _packagenum;
    final qty = js * pn;
    _qtyCtrl.removeListener(_syncJsQty);
    _qtyCtrl.text = qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2);
    _qtyCtrl.addListener(_syncJsQty);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _giftCtrl.dispose();
    _jsQtyCtrl.dispose();
    _batchCtrl.dispose();
    _birthdateCtrl.dispose();
    _validdateCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
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
    if (date != null && mounted) {
      final mo = date.month.toString().padLeft(2, '0');
      final dy = date.day.toString().padLeft(2, '0');
      setState(() {
        ctrl.text = '${date.year}-$mo-$dy';
      });
    }
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

  Widget _buildBatchSelectField({bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: readOnly
            ? null
            : () async {
                final productid = widget.productData['productid']?.toString() ??
                    widget.productData['prodid']?.toString() ??
                    '';
                if (productid.isEmpty) {
                  Toast.show('商品信息异常');
                  return;
                }
                final result = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => SelectBatchSheet(
                    productid: productid,
                    bsid: (widget.bsid ?? '').toString(),
                    counterid: widget.counterid ?? '',
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
                  color: readOnly
                      ? const Color(0xFF6B7280)
                      : _batchCtrl.text.isNotEmpty
                          ? const Color(0xFF111827)
                          : const Color(0xFFD1D5DB),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 16, color: readOnly ? const Color(0xFFE5E7EB) : const Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
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
                        label: '采购进价', controller: _priceCtrl, isDecimal: true, readOnly: ro),
                    _buildDivider(),
                    _buildFormField(
                        label: '数量', controller: _qtyCtrl, isDecimal: true, readOnly: ro),
                    _buildDivider(),
                    _buildFormField(
                        label: '件数', controller: _jsQtyCtrl, isDecimal: true, readOnly: ro),
                    _buildDivider(),
                    _buildFormField(label: '赠送数量', controller: _giftCtrl, readOnly: ro),
                    _buildDivider(),
                    _buildBatchSelectField(readOnly: ro),
                    _buildDivider(),
                    _buildDateField(label: '生产日期', ctrl: _birthdateCtrl, readOnly: ro),
                    _buildDivider(),
                    _buildDateField(label: '有效日期', ctrl: _validdateCtrl, readOnly: ro),
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
                        readOnly: ro),
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
                              Navigator.pop(context, {
                                'price': double.tryParse(_priceCtrl.text) ?? 0.0,
                                'qty': double.tryParse(_qtyCtrl.text) ?? 0.0,
                                'giftqty': double.tryParse(_giftCtrl.text) ?? 0.0,
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

  Widget _buildAmtField() {
    return ListenableBuilder(
      listenable: Listenable.merge([_qtyCtrl, _priceCtrl]),
      builder: (_, __) {
        final qty = double.tryParse(_qtyCtrl.text) ?? 0;
        final price = double.tryParse(_priceCtrl.text) ?? 0;
        final amt = qty * price;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const SizedBox(
                width: 80,
                child: Text('小计金额',
                    style: TextStyle(
                        fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
              ),
              Expanded(
                child: Text(
                  amt.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE74C3C),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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

  Widget _buildDateField(
      {required String label, required TextEditingController ctrl, bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: readOnly ? null : () => _pickDate(ctrl),
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
                ctrl.text.isNotEmpty ? ctrl.text : '请选择',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: readOnly
                      ? const Color(0xFF6B7280)
                      : ctrl.text.isNotEmpty
                          ? const Color(0xFF111827)
                          : const Color(0xFFD1D5DB),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 16, color: readOnly ? const Color(0xFFE5E7EB) : const Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }

  static Widget _buildDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));

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
      params['counterid'] = widget.counterid?.toString() ?? '';
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

/// 粘性表头委托
class _CgthStickyDelegate extends SliverPersistentHeaderDelegate {
  _CgthStickyDelegate({required this.state});
  final _PurchaseCgthAddPageState state;

  @override
  double get minExtent => _PurchaseCgthAddPageState._stickyMinExtent;

  @override
  double get maxExtent => (state._isSigned || !state._scanSettings.showInfraredInput)
      ? _PurchaseCgthAddPageState._stickyMinExtent
      : _PurchaseCgthAddPageState._stickyMaxExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader();
  }

  @override
  bool shouldRebuild(covariant _CgthStickyDelegate oldDelegate) => true;
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

/// 负库存提示弹窗（对齐 Vue checkStockLess 弹窗交互）
/// 显示库存不足的商品列表，允许用户修改数量或删除商品
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
            // 表头
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              color: const Color(0xFFF5F5F5),
              child: const Row(
                children: [
                  SizedBox(width: 26), // 删除按钮占位（18 图标 + 8 间距，与行内对齐）
                  Expanded(
                      child: Text('商品名称',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
                  // 固定列宽保证标题一行展示
                  SizedBox(
                    width: 64,
                    child: Text('门店库存',
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        textAlign: TextAlign.center),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text('退货数量',
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        textAlign: TextAlign.center),
                  ),
                ],
              ),
            ),
            // 商品列表
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (ctx, index) {
                  final item = widget.items[index];
                  final isDeleted = _toDelete.contains(item);
                  if (isDeleted) return const SizedBox.shrink();
                  return _StockLessItem(
                    row: item,
                    onDelete: () => setState(() => _toDelete.add(item)),
                    onQtyChanged: (value) => _qtyEdits[item] = value,
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

/// 负库存弹窗中的商品行项
class _StockLessItem extends StatefulWidget {
  const _StockLessItem({required this.row, required this.onDelete, required this.onQtyChanged});
  final _DetailRow row;
  final VoidCallback onDelete;

  /// 数量编辑回调，由父弹窗统一收集，确认时才写回
  final ValueChanged<String> onQtyChanged;

  @override
  State<_StockLessItem> createState() => _StockLessItemState();
}

class _StockLessItemState extends State<_StockLessItem> {
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
          // 门店库存（固定列宽，与表头对齐）
          SizedBox(
            width: 64,
            child: Text(
              MathUtils.formatDecimal(1, widget.row.stockqty),
              style: const TextStyle(fontSize: 12, color: Color(0xFFFF4D4F)),
              textAlign: TextAlign.center,
            ),
          ),
          // 退货数量（可编辑，固定列宽，与表头对齐）
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
