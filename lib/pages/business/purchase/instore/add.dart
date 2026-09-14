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

enum _PIAction { none, save, delete, print, retsign, withdraw }

class PurchaseInstoreAddPage extends StatefulWidget {
  const PurchaseInstoreAddPage({super.key, this.billData});

  /// 从列表页传入的整条单据数据（包含 billid 等全部字段）
  /// 有值表示编辑/查看模式，null 则为新增模式
  final Map<String, dynamic>? billData;

  @override
  State<PurchaseInstoreAddPage> createState() => _PurchaseInstoreAddPageState();
}

class _PurchaseInstoreAddPageState extends State<PurchaseInstoreAddPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _supController = TextEditingController();
  final TextEditingController _warehouseController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _buyerController = TextEditingController();
  final TextEditingController _refbillnoController = TextEditingController();

  // ---- 红外扫描输入框（PDA 扫码枪）----
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer; // 扫码防抖：扫码枪注入字符极快，停止变化后自动触发查询

  String? _supid;
  int? _storeid;
  String? _counterid;
  String? _buyerid;
  String? _buyername;
  String? _storename;
  int? _storetype;
  int? _refbilltype = 1; // 与 Vue 端一致，默认采购订货单
  String? _refbillidFromInfo; // 从原单 getInfo 获取的 refbillid
  int? _countertype; // 仓库存储方式（对齐 Vue countertype）
  bool _isTipNotMasterProduct = true; // 非供货资格商品校验标志
  // 进价校验放行标记（对齐 Vue isTipDoubleInprice / isTipInprice，
  // 用户弹窗确认后置 false 防止重复弹出）
  bool _isTipDoubleInprice = true; // 进价达原进价两倍（cgInPriceHeightSellPriceFlag）
  bool _isTipInprice = true; // 入库价和档案价不同（cgProductPriceNotSellPriceFlag）

  // ---- 多级审批 ----
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  bool _billSign = true;
  String _userCode = '';
  String _userid = '';

  _PIAction _submitAction = _PIAction.none;
  bool _detailLoading = false;

  // ---- 扫码设置 ----
  late ScanSettings _scanSettings;

  // ---- 批量选择模式 ----
  bool _isSelectMode = false;
  Set<int> _selectedIndices = {};

  // ---- 编辑模式数据 ----
  Map<String, dynamic>? _billData; // 接口返回的完整单据数据

  /// 新增后从接口返回获得的 billid（用于转换到编辑模式）
  String? _newBillid;

  /// 附件列表
  List<Map<String, dynamic>> _fileLists = [];

  bool get _isEdit =>
      (_newBillid != null && _newBillid!.isNotEmpty) ||
      (widget.billData != null && (widget.billData!['billid']?.toString().isNotEmpty ?? false));
  bool get _isSigned => _billData?['signflag']?.toString() == '1';
  bool get _isRejected => _billData?['signflag']?.toString() == '2';

  // 入库明细列表（新增模式使用）
  final List<_DetailRow> _items = [];

  @override
  void initState() {
    super.initState();
    // 读取扫码设置
    _scanSettings = ScanSettings.fromSp();
    // 红外扫描 FocusNode：onKeyEvent 需在 initState 中初始化，避免字段初始化器中访问 this
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
      _scanDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final code = _scanController.text.trim();
        if (code.isEmpty) return;
        debugPrint('[红外扫描] 防抖触发: "$code"');
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
      _loadNewModeDefaults(); // 新增模式：加载机构/经手人默认值
    }

    // 操作审计：进入页面
    FileLogWriter.instance.writeOperationLog(
      '采购入库${_isEdit ? "详情" : "新增"}',
      '进入页面',
      _isEdit ? '单号: ${widget.billData?['billno'] ?? ''}' : null,
    );
  }

  /// 新增模式：从本地存储加载默认值（入库机构、经手人），并自动拉取默认仓库
  void _loadNewModeDefaults() {
    try {
      // 入库机构：从 store cookie 读取（与 Boss 端 store.id → bsid 一致）
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      debugPrint('[入库新增] SpUtil store 原始值: "$storeStr"');
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        debugPrint('[入库新增] storeMap keys: ${storeMap.keys.toList()}');
        debugPrint('[入库新增] storeMap["id"] = ${storeMap['id']} '
            '(type: ${storeMap['id']?.runtimeType})');

        // 兼容多种数据类型（int/double/String）和多种字段名（id/storeid/bsid）
        _storeid = _parseIntFlexible(storeMap, ['id', 'storeid', 'bsid']);
        _storename = storeMap['name']?.toString();
        _storetype = _parseIntFlexible(storeMap, ['storetype']);
        _storeController.text = storeMap['name']?.toString() ?? '';

        debugPrint('[入库新增] 解析结果: _storeid=$_storeid, '
            '_storename=$_storename, _storetype=$_storetype');
      } else {
        debugPrint('[入库新增] SpUtil store 为空，未登录或数据未保存');
      }
    } catch (e) {
      debugPrint('[入库新增] _loadNewModeDefaults store 解析异常: $e');
    }

    try {
      // 经手人：从 user cookie 读取
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _buyerid = userMap['userid']?.toString();
        _buyername = userMap['name']?.toString();
        _buyerController.text = userMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    // 自动拉取默认仓库（取第一个）
    _loadDefaultWarehouse();

    // 新增模式：初始化审批签字按钮可见性
    _initSignUserBtn();
  }

  /// 自动拉取当前机构的默认入库仓库（对齐 Vue selectCom isInit + isCurrentIn 逻辑）
  /// 规则：区域中心(storetype==4)不赋值；过滤 inflag==1 的入库仓库，
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
      // 过滤入库仓库(inflag==1)，按 countertype 升序排序（对齐 Vue isCurrentIn）
      final candidates = list
          .whereType<Map<String, dynamic>>()
          .where((item) => item['inflag']?.toString() == '1')
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
      debugPrint('[入库新增] 默认仓库拉取失败: $e');
    });
  }

  /// 清除所有商品的批次信息（对齐 Vue clearBatchInfo）
  /// 当机构/仓库变更时调用，防止残留批次数据与新仓库不匹配
  void _clearBatchInfo() {
    for (final row in _items) {
      row.batchno = '';
      row.batchController.clear();
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
      params['billtypeid'] = _billData!['billtypeid']?.toString() ?? '0506';
    } else if (_newBillid != null && _newBillid!.isNotEmpty) {
      params['billid'] = _newBillid;
    }
    debugPrint(
        '[updateCgPrice-instore] bsid=${params['bsid']}, supid=${params['supid']}, billid=${params['billid']}, items=${detaillist.length}');

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
          final price = MathUtils.formatDecimalNum(
              2, cgprice != 0 ? cgprice : (double.tryParse(item['price']?.toString() ?? '') ?? 0));
          row.priceController.text = MathUtils.formatDecimal(2, price);

          // 更新库存
          row.stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;

          // 重算金额
          final qty = MathUtils.formatDecimalNum(1, double.tryParse(row.qtyController.text) ?? 0);
          row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
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
      'itemstatusin': '1,2',
      'itemtypenot': '5,8',
    };
    // 当仓库存储方式不为 0 且机构类型为普通门店(0)或配送中心(3) 时，
    // 按仓库存储方式过滤商品（对齐 Vue 端 memorytype 逻辑）
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

  /// 读取登录参数配置项（对齐 Vue userStore().loginParamResp），
  /// 返回指定 key 的 int 值，缺失或解析异常时返回 0
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

  /// 系统参数：只能按照订货单采购入库（对齐 Vue loginParamResp.cgOrderLinkDhFlag）。
  /// 开启后禁用"新增(选择商品)/扫描/红外扫码"等自由录入商品入口，
  /// 商品只能通过选择原单（订货单等）带入
  bool get _cgOrderLinkDhFlag => _loginParamInt('cgOrderLinkDhFlag') == 1;

  /// 系统参数：原单带入时数量清空手工录入
  /// （对齐 Vue orderConfirm：v.qty = cgOrderLinkDhQtyFlag == 1 ? "" : v.notorderedqty）
  bool get _cgOrderLinkDhQtyFlag => _loginParamInt('cgOrderLinkDhQtyFlag') == 1;

  /// 红外扫码框是否渲染（内容渲染与粘性表头高度计算的唯一判据，
  /// 两者共用同一 getter，避免条件不一致导致表头出现空白占位）
  bool get _showScanBox => !_readOnly && _scanSettings.showInfraredInput && !_cgOrderLinkDhFlag;

  /// 从 Map 中灵活解析 int 值，支持多种字段名和多种数据类型
  /// 兼容：int / double / String，以及 id / storeid / bsid 等字段名
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
      // 尝试 double 转 int（如 "142.0"）
      final d = double.tryParse(str);
      if (d != null) return d.toInt();
    }
    return null;
  }

  @override
  void dispose() {
    _scanDebounceTimer?.cancel();
    _supController.dispose();
    _warehouseController.dispose();
    _remarkController.dispose();
    _storeController.dispose();
    _buyerController.dispose();
    _refbillnoController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  // =================== 编辑模式：加载单据详情 ===================
  /// [overrideParams] 新增保存后传入 {billid: xxx}，其他情况可省略
  void _loadDetail([Map<String, dynamic>? overrideParams]) {
    setState(() {
      _detailLoading = true;
      _isTipNotMasterProduct = true; // 对齐 Vue getInfo: 重置非主供货商校验标志
    });
    // 优先用 overrideParams，其次用 widget.billData
    final Map<String, dynamic> params =
        overrideParams ?? Map<String, dynamic>.from(widget.billData!);

    request(HttpApi.purchaseInstoreGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
          _supController.text = data['supname']?.toString() ?? '';
          _storeController.text = data['storename']?.toString() ?? '';
          _warehouseController.text = data['countername']?.toString() ?? '';
          _buyerController.text = data['buyername']?.toString() ?? '';
          _refbillnoController.text = data['refbillno']?.toString() ?? '';
          _remarkController.text = data['remark']?.toString() ?? '';
          _fileLists = (data['fileLists'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          // 加载 ID 变量，待审核编辑时选择组件需要
          _supid = data['supid']?.toString();
          _storeid = _parseIntFlexible(data, ['bsid', 'storeid']);
          _storename = data['storename']?.toString();
          _storetype = _parseIntFlexible(data, ['storetype']);
          _counterid = data['counterid']?.toString();
          _buyerid = data['buyerid']?.toString();
          _buyername = data['buyername']?.toString();
          // 存储仓库存储方式
          _countertype = _parseIntFlexible(data, ['countertype']);
          // 加载原单号类型和ID
          _refbilltype = _parseIntFlexible(data, ['refbilltype']) ?? 1;
          _refbillidFromInfo = data['refbillid']?.toString();
          // 将 API 明细转换为统一的 _DetailRow 对象
          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            // 对齐 boss 项目 handleProperty：加载详情时用 cgprice 更新显示价格
            final cgprice = double.tryParse(c['cgprice']?.toString() ?? '') ?? 0;
            final oldPrice = double.tryParse(c['price']?.toString() ?? '') ?? 0;
            final price = cgprice != 0 ? cgprice : oldPrice;
            c['price'] = double.parse(price.toStringAsFixed(2));
            // 对齐 Vue handleProperty：amt 始终由 qty*price 重算
            final qtyLoad = double.tryParse(c['qty']?.toString() ?? '') ?? 0;
            final row = _DetailRow();
            row.prodid = c['prodid']?.toString() ?? c['productid']?.toString() ?? '';
            row.nameController.text = c['productname']?.toString() ?? c['name']?.toString() ?? '';
            row.qtyController.text =
                MathUtils.formatDecimal(1, double.tryParse(c['qty']?.toString() ?? '') ?? 0);
            row.priceController.text = price.toStringAsFixed(2);
            row.giftQtyController.text = MathUtils.formatDecimal(
                1,
                double.tryParse(c['presentqty']?.toString() ?? c['giftqty']?.toString() ?? '') ??
                    0);
            row.batchno = c['batchno']?.toString() ?? '';
            row.batchController.text = row.batchno!;
            row.barcodeController.text =
                c['barcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';
            row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qtyLoad, price));
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
  /// 统一提交（新增 / 编辑共用）
  Future<void> _submit({bool isDraft = false, bool withSign = false}) async {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('011703', showTip: false)) {
        Toast.show('你无权编辑采购入库，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('011702', showTip: false)) {
        Toast.show('你无权新增采购入库，请在后台修改权限');
        return;
      }
    }
    // 操作审计：提交保存
    final String actionName = _isEdit ? '保存修改' : '保存单据';
    final String? detail = isDraft ? '存为草稿' : (withSign ? '保存并审核' : null);
    FileLogWriter.instance.writeOperationLog(
      '采购入库${_isEdit ? "详情" : "新增"}',
      actionName,
      detail,
    );

    // ---------- 校验 ----------
    if (!_isSigned) {
      if (_supid == null || _supid!.isEmpty) {
        Toast.show('请选择供应商');
        return;
      }
      if (_storeid == null) {
        Toast.show('请选择入库机构');
        return;
      }
      if (_counterid == null || _counterid!.isEmpty) {
        Toast.show('请选择入库仓库');
        return;
      }
    }

    // 新增模式额外校验
    if (!_isEdit) {
      if (!_formKey.currentState!.validate()) return;
    }

    // 确定提交商品行：编辑模式全部提交，新增模式过滤有效行
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

    // 进价两倍差 / 入库价与档案价不一致校验
    // （对齐 Vue save 中 cgInPriceHeightSellPriceFlag / cgProductPriceNotSellPriceFlag，
    // 校验时机位于 cgpriceflag 之后、批次校验之前）
    final doubleFlag = getCgInPriceHeightSellPriceFlag();
    final diffFlag = getCgProductPriceNotSellPriceFlag();
    if ((_isTipDoubleInprice && (doubleFlag == 2 || doubleFlag == 3)) ||
        (_isTipDoubleInprice && _isTipInprice && (diffFlag == 2 || diffFlag == 3))) {
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
      );
      if (!mounted) return;
      if (outcome.result == InPriceHeightResult.cancel) return;
      if (outcome.result == InPriceHeightResult.continueSave) {
        // 对齐 Vue handleInPriceHeightConfirm：确认后仅置触发类型的放行标记，
        // 重新走保存流程（两倍差放行后不再校验进价不一致，
        // 对齐 Vue isTipDoubleInprice 联动逻辑）
        if (outcome.firedType == kInPriceHeightType) {
          _isTipDoubleInprice = false;
        } else {
          _isTipInprice = false;
        }
        _submit(isDraft: isDraft, withSign: withSign);
        return;
      }
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
            final batchno = row.batchController.text.trim();
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
            final batchno = row.batchController.text.trim();
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

    setState(() => _submitAction = _PIAction.save);

    // ---------- 构造参数 ----------
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
      // 编辑模式：计算 sellamt
      double totalSellAmt = 0;
      for (final item in detaillist) {
        totalSellAmt =
            MathUtils.add(totalSellAmt, double.tryParse(item['sellamt']?.toString() ?? '0') ?? 0);
      }
      params['billsellamt'] = MathUtils.roundTo(totalSellAmt);
      params['refbillid'] = _refbillidFromInfo ?? _billData!['refbillid']?.toString() ?? '';
    } else {
      final now = DateTime.now();
      String p2(int v) => v.toString().padLeft(2, '0');
      // 对齐后台 instore/edit.vue formDefault：billdate 含时分秒、
      // billtype:1、refbilltype:1、refbillno、status:3、freeamt:0、storetype
      final billdate =
          '${now.year}-${p2(now.month)}-${p2(now.day)} ${p2(now.hour)}:${p2(now.minute)}:${p2(now.second)}';
      params = {
        'name': '',
        'startdate': '',
        'enddate': '',
        'billtype': 1,
        'refbilltype': 1,
        'refbillno': '',
        'batchno': '',
        'billdate': billdate,
        'billsellamt': 0,
        'status': 3,
        'signflag': 0,
        'freeamt': 0,
        'storetype': _storetype ?? '',
        'fileLists': _fileLists,
        'refbillid': _refbillidFromInfo ?? '',
      };
    }

    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt);
    params['detaillist'] = detaillist;
    params['fileLists'] = _fileLists;
    params['remark'] = _remarkController.text.trim();
    params['supname'] = _supController.text.trim();
    params['supid'] = _supid ?? '';
    params['bsid'] = _storeid ?? '';
    params['storename'] = _storename ?? '';
    params['storetype'] = _storetype ?? '';
    params['counterid'] = _counterid ?? '';
    params['countername'] = _warehouseController.text.trim();
    params['buyerid'] = _buyerid ?? '';
    params['buyername'] = _buyername ?? '';
    params['refbilltype'] = _refbilltype ?? 1;
    params['refbillno'] = _refbillnoController.text.trim();

    request(HttpApi.purchaseInstoreSave, params).then((result) {
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
        // 保存后若需审核
        if (withSign) {
          _doSignAfterSave(retData);
        }
      } else {
        if (!_isEdit) Navigator.pop(context, true);
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PIAction.none);
    });
  }

  /// 将原单 getInfo 返回的明细填充到 _items，并回填供应商/机构/仓库等字段（对齐 Vue orderConfirm）
  void _fillItemsFromBillInfo(Map<String, dynamic> info, int refbilltype) {
    // 回填供应商
    final String supid = info['supid']?.toString() ?? '';
    final String supname = info['supname']?.toString() ?? '';
    // 回填机构（type==5 越库订单用 outsid/outstorename）
    final String bsid = refbilltype == 5
        ? (info['outsid']?.toString() ?? info['bsid']?.toString() ?? '')
        : (info['bsid']?.toString() ?? '');
    final String storename = refbilltype == 5
        ? (info['outstorename']?.toString() ?? info['storename']?.toString() ?? '')
        : (info['storename']?.toString() ?? '');
    // 回填仓库
    final String counterid = info['counterid']?.toString() ?? '';
    final String countername = info['countername']?.toString() ?? '';
    // refbillid
    final String refbillid = info['billid']?.toString() ?? '';

    if (supid.isNotEmpty) {
      _supid = supid;
      _supController.text = supname;
    }
    if (bsid.isNotEmpty) {
      _storeid = int.tryParse(bsid);
      _storename = storename;
      _storetype = int.tryParse(info['storetype']?.toString() ?? '');
      _storeController.text = storename;
    }
    if (counterid.isNotEmpty) {
      _counterid = counterid;
      _warehouseController.text = countername;
    }
    _refbillnoController.text = info['billno']?.toString() ?? _refbillnoController.text;
    if (refbillid.isNotEmpty) {
      // 存储 refbillid 供保存接口使用（通过 _refbillidFromInfo 传递）
      _refbillidFromInfo = refbillid;
    }

    // 提取明细列表
    List<dynamic>? detailList;
    final d = info['detaillist'];
    if (d is List) detailList = d;

    if (detailList == null || detailList.isEmpty) return;
    for (final row in _items) {
      row.dispose();
    }
    _items.clear();

    for (final v in detailList) {
      if (v is! Map) continue;
      final raw = Map<String, dynamic>.from(v);

      // 商品ID
      final String prodid = (raw['prodid'] ?? raw['productid'] ?? '').toString();
      if (prodid.isEmpty) continue;

      // 数量回填（对齐 Vue orderConfirm）：
      // cgOrderLinkDhQtyFlag==1 时数量清空由用户手工录入；
      // 否则取 notorderedqty（未订/未入库数量），notorderedqty 缺失时防御性回退 qty - orderedqty
      final double qty;
      if (_cgOrderLinkDhQtyFlag) {
        qty = 0;
      } else if (raw['notorderedqty'] != null) {
        qty = double.tryParse(raw['notorderedqty'].toString()) ?? 0;
      } else {
        qty = (double.tryParse(raw['qty']?.toString() ?? '') ?? 0) -
            (double.tryParse(raw['orderedqty']?.toString() ?? '') ?? 0);
      }
      // 对齐 Vue orderConfirm：记录订货数量/差异数量，提交前按 cyqty = qty - orderqty 重算
      raw['orderqty'] = qty;
      raw['cyqty'] = 0;

      // 进价（cgprice 优先，为空或为 0 时回退档案进价，对齐选择页取值规则）
      final double orderCgprice = double.tryParse(raw['cgprice']?.toString() ?? '') ?? 0;
      final double price =
          orderCgprice != 0 ? orderCgprice : (double.tryParse(raw['price']?.toString() ?? '') ?? 0);

      // 赠送数量
      final double giftqty =
          double.tryParse((raw['giftqty'] ?? raw['presentqty'] ?? '0').toString()) ?? 0;

      // 商品名称
      final String productname = (raw['productname'] ?? raw['name'] ?? '').toString();

      // 批次
      final String batchno = (raw['batchno'] ?? '').toString();

      // 条码
      final String barcode = (raw['barcode'] ?? raw['selfbarcode'] ?? '').toString();

      final row = _DetailRow();
      row.prodid = prodid;
      row.nameController.text = productname;
      // cgOrderLinkDhQtyFlag==1 时数量留空手工录入（对齐 Vue v.qty = ""）
      row.qtyController.text = _cgOrderLinkDhQtyFlag
          ? ''
          : (qty == qty.toInt() ? qty.toInt().toString() : qty.toString());
      row.priceController.text = price > 0 ? price.toString() : '';
      row.giftQtyController.text = giftqty.toString();
      row.batchno = batchno.isNotEmpty ? batchno : null;
      row.barcodeController.text = barcode;
      row.rawData = raw;
      _items.add(row);
    }

    // 对齐 Vue orderConfirm：按仓库存储方式过滤不一致商品
    if (_shouldFilterByMemoryType) {
      final ct = _countertype ?? 0;
      final hasInconsistent = _items.any((row) {
        final mt = int.tryParse(row.rawData?['memorytype']?.toString() ?? '') ?? -1;
        return mt >= 0 && mt != ct;
      });
      if (hasInconsistent) {
        final before = _items.length;
        _items.removeWhere((row) {
          final mt = int.tryParse(row.rawData?['memorytype']?.toString() ?? '') ?? -1;
          return mt >= 0 && mt != ct;
        });
        if (_items.length < before) {
          Toast.show('已过滤仓库存储方式不一致商品');
        }
      }
    }
  }

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

  /// 新单据时，根据机构(bsid)查询是否需要审批签字
  void _initSignUserBtn() {
    if (_isAdmin) return;
    if (!_isEdit && _storeid != null) {
      request(HttpApi.reviewTypeConfigGetNewBillSignUser, {
        'billtypeid': '0506',
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

  /// 审核（已保存的单据直接审核，多级审批时弹出审批弹窗）
  Future<void> _sign() async {
    if (!PermissionUtils.checkPermission('011705', showTip: false)) {
      Toast.show('你无权审核采购入库，请在后台修改权限');
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

  /// 执行审核操作（对齐 Vue doSign）
  void _doSign() {
    if (_billData == null) return;

    // 操作审计：审核/驳回（reviewsignflag: 0=驳回, 其他=通过）
    final int reviewsignflag = int.tryParse(_billData?['reviewsignflag']?.toString() ?? '') ?? -1;
    final String reviewRemark = _billData?['reviewremark']?.toString() ?? '';
    FileLogWriter.instance.writeOperationLog(
      '采购入库详情',
      reviewsignflag == 0 ? '驳回单据' : '审核单据',
      '单号: ${_billData?['billno'] ?? ''}'
          '${reviewRemark.isNotEmpty ? ' | 备注: $reviewRemark' : ''}',
    );

    final params = Map<String, dynamic>.from(_billData!);
    params['signflag'] = 1;
    params['reviewremark'] = _billData?['reviewremark']?.toString() ?? '';
    // reviewsignflag: 2=撤回保持不变，0=驳回保持不变，其余设为1（通过）
    final int reviewsignflag2 = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
    if (reviewsignflag2 != 2 && reviewsignflag2 != 0) {
      params['reviewsignflag'] = 1;
    }
    request(HttpApi.purchaseInstoreSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '审核成功');
      _loadDetail(_billData);
    });
  }

  /// 撤回操作
  Future<void> _restsign() async {
    if (!PermissionUtils.checkPermission('011706', showTip: false)) {
      Toast.show('你无权反审核采购入库，请在后台修改权限');
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

    // 操作审计：撤回单据
    FileLogWriter.instance.writeOperationLog(
      '采购入库详情',
      '撤回单据',
      '单号: ${_billData?['billno'] ?? ''}',
    );

    setState(() => _submitAction = _PIAction.withdraw);
    final params = Map<String, dynamic>.from(_billData!);
    params['reviewsignflag'] = 2;
    params['reviewremark'] = '';
    params['signflag'] = 1;
    request(HttpApi.purchaseInstoreSign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '撤回成功');
      _loadDetail(_billData);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PIAction.none);
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

  /// 打印单据
  Future<void> _print() async {
    if (_billData == null) return;
    // 操作审计：打印单据
    FileLogWriter.instance.writeOperationLog(
      '采购入库详情',
      '打印单据',
      '单号: ${_billData?['billno'] ?? ''}',
    );
    final printParams = {
      'menuid': '050601',
      'data': _billData,
    };
    setState(() => _submitAction = _PIAction.print);
    request(HttpApi.purchaseInstorePrint, printParams).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PIAction.none);
    });
  }

  /// 反审核
  Future<void> _retsign() async {
    if (_billData == null) return;
    final hasApproval = _reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text(hasApproval ? '反审核单据后，所有审批步骤需重新处理！确认要反审核单据？' : '确定反审核单据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    // 操作审计：反审核
    FileLogWriter.instance.writeOperationLog(
      '采购入库详情',
      '反审核',
      '单号: ${_billData?['billno'] ?? ''}',
    );

    setState(() => _submitAction = _PIAction.retsign);
    // 构造完整反审核参数（对齐 Vue fsignFn 发送 query.value 完整单据对象）：
    // Vue 端 query 初始即含 billdate/billtype/status 等字段，后端 retsign 写入
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
      params['billtypeid'] = '0506';
    }
    params['billtype'] ??= 1;
    final dl = params['detaillist'];
    if (dl is! List || dl.isEmpty) {
      params['detaillist'] = _buildSubmitDetailList();
    }
    request(HttpApi.purchaseInstoreRetsign, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '反审成功');
      setState(() {
        _reviewFlowUsers = [];
        _reviewBillFlows = [];
      });
      _loadDetail(params);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PIAction.none);
    });
  }

  /// 删除单据
  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('011704', showTip: false)) {
      Toast.show('你无权删除采购入库，请在后台修改权限');
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

    // 操作审计：删除单据
    FileLogWriter.instance.writeOperationLog(
      '采购入库详情',
      '删除单据',
      '单号: ${_billData?['billno'] ?? ''}',
    );

    setState(() => _submitAction = _PIAction.delete);
    request(HttpApi.purchaseInstoreDelBill, _billData).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PIAction.none);
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
      Toast.show('请先选择入库机构');
      return;
    }
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
      return;
    }

    final result = await VoiceRecognitionDialog.show(context);
    if (result == null || result.isEmpty || !mounted) return;

    // 对每个识别出的商品调用搜索 API 匹配
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
          final batchPrice = MathUtils.formatDecimalNum(
              2,
              double.tryParse(
                      (item['price'] ?? prod['cgprice'] ?? prod['price'] ?? 0).toString()) ??
                  0);
          final batchQty = MathUtils.formatDecimalNum(
              1, double.tryParse((item['quantity'] ?? 1).toString()) ?? 1);
          setState(() {
            _items.insert(
                0,
                _DetailRow()
                  ..nameController.text =
                      prod['productname']?.toString() ?? prod['name']?.toString() ?? name
                  ..qtyController.text = batchQty == batchQty.toInt()
                      ? batchQty.toInt().toString()
                      : batchQty.toString()
                  ..priceController.text = MathUtils.formatDecimal(2, batchPrice)
                  ..batchno = prod['batchno']?.toString() ?? ''
                  ..prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? ''
                  ..barcodeController.text =
                      prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? ''
                  ..amt = MathUtils.formatDecimalNum(3, MathUtils.mul(batchQty, batchPrice))
                  ..rawData = Map<String, dynamic>.from(prod));
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

  // =================== 计算汇总（统一模式）==

  /// 采购总数量：仅统计明细行 qty（不含赠送），对齐小程序 edit.vue comProNum
  /// 与提交参数 billqty 口径；formatDecimal(1) 按服务端 countLength 保留小数位
  String get _totalQty {
    double sum = 0;
    for (final row in _items) {
      sum = MathUtils.add(sum, double.tryParse(row.qtyController.text) ?? 0);
    }
    return MathUtils.formatDecimal(1, sum);
  }

  /// 合计金额：以行金额（row.amt）为准，未失焦确认的行按 qty × price 实时计算；
  /// formatDecimal(3) 对齐小程序 edit.vue comProAmt（amtLength 服务端配置）
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

  /// 构造提交用的 detaillist（统一新增/编辑模式）
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
      final giftqty =
          MathUtils.formatDecimalNum(1, double.tryParse(row.giftQtyController.text) ?? 0);
      final item =
          row.rawData != null ? Map<String, dynamic>.from(row.rawData!) : <String, dynamic>{};
      item['productname'] = row.nameController.text.trim();
      item['prodname'] = row.nameController.text.trim();
      item['qty'] = qty;
      // 差异数量（对齐 Vue handleProperty：提交前 cyqty = qty - orderqty 重算）
      final orderqty = double.tryParse(item['orderqty']?.toString() ?? '') ?? 0;
      item['cyqty'] = MathUtils.formatDecimalNum(1, MathUtils.subtract(qty, orderqty));
      item['price'] = price;
      item['amt'] = MathUtils.formatDecimalNum(3, row.amt ?? MathUtils.mul(qty, price));
      item['batchno'] = row.batchController.text.trim().isNotEmpty
          ? row.batchController.text.trim()
          : (row.batchno ?? '');
      item['giftqty'] = giftqty;
      item['presentqty'] = giftqty;
      item['prodid'] = row.prodid ?? item['productid'] ?? '';
      item['productid'] = item['productid'] ?? row.prodid ?? '';
      return item;
    }).toList();
  }

  bool get _readOnly => _isEdit && (_isSigned || !_bolHandle);

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
          _isEdit ? (_isSigned ? '采购入库详情' : '修改采购入库') : '新增采购入库',
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

  // =================== 统一 UI ===================

  /// 粘性表头区域高度常量（扫描框 + 商品明细标题 + 列头）
  /// 使用偏宽松的估值，避免因硬编码偏小导致内容溢出遮挡第一行
  static const double _stickyScanHeight = 68.0; // 扫描输入框(40) + padding(4+8) + gap(6) + 边框余量(10)
  static const double _stickyTitleHeight = 40.0; // 商品明细标题行(14+2*8) + divider(1) + 边框余量
  static const double _stickyColumnHeight = 36.0; // 列头（商品信息/采购进价/赠送/数量）(16+2*8+边框)
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
              // ---- 单号+状态（仅编辑模式，可滚动） ----
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
              // ---- 单据信息卡片（可滚动，随页面向上消失） ----
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: _buildCard(
                    title: '单据信息',
                    child: _readOnly ? _buildBillInfoReadonly() : _buildBillInfoEditable(),
                  ),
                ),
              ),
              // 不显示红外扫描框时，补充与粘性表头之间的间距
              // （linkDh 隐藏扫码框时同样需要补偿，避免卡片贴顶）
              if (!_readOnly && !_showScanBox) const SliverToBoxAdapter(child: SizedBox(height: 8)),
              // ---- 粘性表头：扫描框 + 商品明细标题 + 列头（滚到此处后固定） ----
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeaderDelegate(state: this),
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
                        bsid: _storeid,
                        counterid: _counterid,
                        onToggle: () => _toggleIndex(index),
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

  /// 构建粘性表头内容（扫描框 + 商品明细标题/操作按钮 + 列头）
  /// 外层用 Align 确保内容始终靠上对齐，避免 maxExtent 偏大时内容居中推挤明细行
  Widget _buildStickyHeader() {
    // cgOrderLinkDhFlag==1（只能按照订货单采购入库）时：
    // 隐藏红外扫码框，扫描/新增按钮置灰（对齐 Vue 选择商品/扫描/导入按钮 disabled）
    final bool linkDh = _cgOrderLinkDhFlag;
    final Color accentColor = linkDh ? const Color(0xFFC0C4CC) : const Color(0xFF006EFF);
    return Align(
      alignment: Alignment.topCenter,
      child: ColoredBox(
        color: const Color(0xFFF5F5F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 扫描输入框（仅非只读且设置了显示红外输入框，且未开启“只能按订货单入库”时显示）
            if (_showScanBox) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _buildScanInput(),
              ),
              const SizedBox(height: 8),
            ],
            // 商品明细卡片（仅标题栏 + 列头）
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    BossSvgIcon(svgFile: 'scan.svg', size: 12, color: accentColor),
                                    const SizedBox(width: 2),
                                    Text('扫描',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: accentColor,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            // 固定扫描（Web 调试用，对齐预盘单页面）
                            if (Device.isWeb) ...[
                              GestureDetector(
                                onTap: () => _handleScannedBarcode('00002'),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.qr_code,
                                        size: 14,
                                        color: linkDh
                                            ? const Color(0xFFC0C4CC)
                                            : const Color(0xFFFF6B00)),
                                    const SizedBox(width: 2),
                                    Text('固定扫描',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: linkDh
                                                ? const Color(0xFFC0C4CC)
                                                : const Color(0xFFFF6B00),
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            GestureDetector(
                              onTap: _selectProducts,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_circle_outline, size: 16, color: accentColor),
                                  const SizedBox(width: 2),
                                  Text('新增',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: accentColor,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
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
                              child: Text('采购进价',
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
      ),
    );
  }

  /// 单号+状态卡片（非 Sliver 版本，用于 ListView）
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
      titleRight: Text(
        statusLabel,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: statusColor,
        ),
      ),
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

  /// 单据信息 - 只读模式（已审核）
  Widget _buildBillInfoReadonly() {
    return Column(
      children: [
        _buildReadonlyField(label: '供应商', value: _supController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '入库机构', value: _storeController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '入库仓库', value: _warehouseController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '原单号', value: _refbillnoController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '经手人', value: _buyerController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(label: '备注', value: _remarkController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildAttachButton(),
      ],
    );
  }

  /// 单据信息 - 可编辑模式（新增 / 待审核编辑）
  Widget _buildBillInfoEditable() {
    return Column(
      children: [
        SelectFieldItem(
          label: '供应商',
          required: true,
          value: _supController.text,
          onTap: () async {
            final result = await SelectSupplierPage.show(context, initialSelectedId: _supid);
            if (result != null && mounted) {
              setState(() {
                _supid = result['supid']?.toString();
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
          label: '入库机构',
          required: true,
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
                // 对齐 Vue selectGodownFn：机构变更时清空仓库/原单号，刷新价格，清除批次
                _counterid = null;
                _countertype = null;
                _warehouseController.clear();
                _refbillnoController.clear();
                _refreshProductPrices();
                _clearBatchInfo();
              });
              // 机构变更时重新初始化审批签字按钮可见性
              _initSignUserBtn();
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '入库仓库',
          required: true,
          value: _warehouseController.text,
          onTap: () async {
            final result = await SelectWarehousePage.show(context,
                bsid: _storeid, initialSelectedId: _counterid);
            if (result != null && mounted) {
              setState(() {
                _counterid = result['counterid']?.toString();
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
          onTap: () => _onTapRefbill(),
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

  /// 原单号选择（新增模式有清空确认弹窗，编辑模式直接选择）
  Future<void> _onTapRefbill() async {
    // 对齐 Vue canNothandleFnT：选择原单前置校验（供应商/机构/仓库）
    if (_refbilltype != 2 && (_supid == null || _supid!.isEmpty)) {
      Toast.show('必须选择供应商后才能选择商品！');
      return;
    }
    if (_storeid == null) {
      Toast.show('必须选择入库机构后才能选择商品！');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('必须选择入库仓库后才能选择商品！');
      return;
    }
    if (!_isEdit) {
      final bool hasItems = _items.any((r) => r.prodid != null && r.prodid!.isNotEmpty);
      if (hasItems) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('提示'),
            content: const Text('选择单据会清空当前商品，是否继续？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续')),
            ],
          ),
        );
        if (confirm != true || !mounted) return;
      }
    }
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectRefbillPage(
          bsid: _storeid,
          storename: _storename,
          // 对齐 Vue refbilltype 选项展示规则（直配/越库受 storetype 限制）
          // 及 buildMergData billtype 过滤（自采/直配 billtype=1、越库 billtype=2）
          customTypes: _buildRefbillTypes(),
          // 对齐 Vue buildMergData：传入 counterid / memorytype 参数过滤原单列表
          extraListParams: <String, dynamic>{
            if (_counterid != null && _counterid!.isNotEmpty) 'counterid': _counterid,
            if (_shouldFilterByMemoryType) 'memorytype': _countertype ?? 0,
          },
        ),
      ),
    );
    if (result != null && mounted) {
      final int rType = int.tryParse(result['refbilltype']?.toString() ?? '') ?? 1;
      final Map<String, dynamic>? info = result['info'] as Map<String, dynamic>?;
      setState(() {
        _refbilltype = rType;
        _refbillnoController.text = result['refbillno']?.toString() ?? '';
        // 对齐 Vue refbilltypeChange：越库单据只能入库常温、冷藏、冷冻仓库
        if (rType == 5 && _countertype == 0) {
          Toast.show('越库单据只能入库常温、冷藏、冷冻仓库，请重新选择仓库！');
          _counterid = null;
          _warehouseController.text = '';
          _countertype = null;
        }
        if (info != null) {
          _fillItemsFromBillInfo(info, rType);
        }
      });
    }
  }

  /// 原单单据类型列表（对齐 Vue edit.vue refbilltype 选项展示规则及 buildMergData 过滤）：
  /// - 自采申请单/直配订单列表过滤 billtype=1，越库订单 billtype=2
  /// - 直配订单：已审核或 storetype != 3 时可选
  /// - 越库订单：已审核或 storetype 为 3/0 时可选
  List<Map<String, dynamic>> _buildRefbillTypes() {
    final st = _storetype ?? 0;
    return [
      {'value': 1, 'label': '采购订货单', 'path': 'cgorder/findList', 'infoPath': 'cgorder/getInfo'},
      {'value': 2, 'label': '采购计划单', 'path': 'cgplan/findList', 'infoPath': 'cgplan/getInfo'},
      {
        'value': 3,
        'label': '自采申请单',
        'path': 'cgzc/findList',
        'infoPath': 'cgzc/getInfo',
        'listParams': <String, dynamic>{'billtype': 1},
      },
      if (_isSigned || st != 3)
        {
          'value': 4,
          'label': '直配订单',
          'path': 'cgother/findList',
          'infoPath': 'cgother/getInfo',
          'listParams': <String, dynamic>{'billtype': 1},
        },
      if (_isSigned || st == 3 || st == 0)
        {
          'value': 5,
          'label': '越库订单',
          'path': 'cgothercd/findList',
          'infoPath': 'cgothercd/getInfo',
          'listParams': <String, dynamic>{'billtype': 2},
        },
    ];
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
          // 统计栏：单行汇总文本（对齐小程序 instore/edit.vue bottom-msg-box total-box：
          // “采购数量：X，共N项，总金额：Y”，fontSize 13 对应 26rpx），
          // 实时监听明细行数量/价格输入，输入过程中同步刷新
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
                      '采购数量：$_totalQty，共${_items.length}项，总金额：$_totalAmt',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              );
            },
          ),
          // 编辑模式 - 待审核/已驳回（signflag != 1）
          if (_isEdit && !_isSigned) _buildEditUnsignedButtons(),
          // 编辑模式 - 已审核：反审核 + 打印
          if (_isEdit && _isSigned) _buildEditSignedButtons(),
          // 新增模式：保存 + 审核
          if (!_isEdit) _buildNewBillButtons(),
        ],
      ),
    );
  }

  /// 编辑模式 - 待审核/已驳回：更多(删除) + 保存 + 审核 + 撤回
  Widget _buildEditUnsignedButtons() {
    final bool isLoading = _submitAction != _PIAction.none;
    final buttons = <Widget>[];

    // “更多”按钮（删除/打印）- reviewsignflag != 2 && bolHandleTT
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
          child: _submitAction == _PIAction.save
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
          child: const Text('审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
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
          child: _submitAction == _PIAction.withdraw
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
    final bool isLoading = _submitAction != _PIAction.none;
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
          child: _submitAction == _PIAction.retsign
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
        child: _submitAction == _PIAction.print
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
    final bool isLoading = _submitAction != _PIAction.none;
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
        child: _submitAction == _PIAction.save
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

  // =================== 商品选择与扫码 ===================
  // 检查是否已选供应商，未选则提示并返回 false
  bool _ensureSupplierSelected() {
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
      return false;
    }
    return true;
  }

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
      // 保证选择页详情抽屉价格回显/反算使用用户修改值而非档案原价
      map['cgprice'] = map['price'];
      map['amt'] = row.amt ?? 0;
      map['unit'] = map['unit']?.toString() ?? '';
      map['size'] = map['size']?.toString() ?? '';
      return map;
    }).toList();
  }

  Future<void> _selectProducts({String? initialKeyword, FocusNode? returnFocusNode}) async {
    // 对齐 Vue edit.vue：cgOrderLinkDhFlag==1 时选择商品按钮禁用，商品只能由原单带入
    if (_cgOrderLinkDhFlag) {
      Toast.show('只能按照订货单采购入库，请通过选择原单带入商品');
      return;
    }
    if (!_ensureSupplierSelected()) return;
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
          // 小计金额失焦反算（对齐 instore/edit.vue writeData key=amt 分支）：
          // cgSupChangeAmtFlag==2 → 反算数量 qty = amt / price（1 位小数），
          // 否则反算单价 price = amt / qty
          amtRecalcQty: _loginParamInt('cgSupChangeAmtFlag') == 2,
          amtQtyDecimals: 1,
          initialKeyword: initialKeyword,
        ),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        for (final prod in result) {
          final prodId = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
          if (prodId.isNotEmpty) {
            final existIdx = _items.indexWhere((row) => row.prodid == prodId);
            if (existIdx >= 0) {
              // 对齐 Vue onSelectProduct 合并语义：选择页返回的行整体替换已有行
              // （Map 去重后返回行覆盖旧行，qty/price/amt 均取返回值，不再累加）
              final row = _items[existIdx];
              final newQty = MathUtils.formatDecimalNum(
                  1, double.tryParse((prod['qty'] ?? 1).toString()) ?? 1);
              final newGiftqty = MathUtils.formatDecimalNum(
                  1, double.tryParse((prod['giftqty'] ?? 0).toString()) ?? 0);
              // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
              final syncCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
              final newPrice = MathUtils.formatDecimalNum(
                  2,
                  syncCgprice != 0
                      ? syncCgprice
                      : (double.tryParse(prod['price']?.toString() ?? '') ?? 0));
              // 优先使用返回数据中的 amt（选择页面已同步计算），否则按 qty × price 计算
              final prodAmtVal = prod['amt'];
              final newAmt = prodAmtVal != null
                  ? (double.tryParse(prodAmtVal.toString()) ?? MathUtils.mul(newQty, newPrice))
                  : MathUtils.mul(newQty, newPrice);
              final batchno = prod['batchno']?.toString() ?? '';
              row.prodid = prodId;
              row.nameController.text =
                  prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
              row.qtyController.text =
                  newQty == newQty.toInt() ? newQty.toInt().toString() : newQty.toString();
              row.giftQtyController.text = newGiftqty.toInt().toString();
              row.priceController.text = MathUtils.formatDecimal(2, newPrice);
              row.batchno = batchno;
              row.batchController.text = batchno;
              row.barcodeController.text =
                  prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? '';
              row.amt = MathUtils.formatDecimalNum(3, newAmt);
              row.rawData = Map<String, dynamic>.from(prod);
              continue;
            }
          }

          final batchno = prod['batchno']?.toString() ?? '';
          // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
          final rowCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
          final price = MathUtils.formatDecimalNum(
              2,
              rowCgprice != 0
                  ? rowCgprice
                  : (double.tryParse(prod['price']?.toString() ?? '') ?? 0));
          final qty =
              MathUtils.formatDecimalNum(1, double.tryParse((prod['qty'] ?? 1).toString()) ?? 1);
          final giftqty = MathUtils.formatDecimalNum(
              1, double.tryParse((prod['giftqty'] ?? 0).toString()) ?? 0);
          // 优先使用返回数据中的 amt（选择页面已同步计算），否则现场计算
          double amt;
          final prodAmt = prod['amt'];
          if (prodAmt != null) {
            amt = double.tryParse(prodAmt.toString()) ?? MathUtils.mul(qty, price);
          } else {
            amt = MathUtils.mul(qty, price);
          }
          _items.insert(
              0,
              _DetailRow()
                ..nameController.text =
                    prod['productname']?.toString() ?? prod['name']?.toString() ?? ''
                ..qtyController.text = qty == qty.toInt() ? qty.toInt().toString() : qty.toString()
                ..priceController.text = MathUtils.formatDecimal(2, price)
                ..giftQtyController.text = giftqty.toInt().toString()
                ..batchno = batchno
                ..batchController.text = batchno
                ..prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? ''
                ..barcodeController.text =
                    prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? ''
                ..amt = MathUtils.formatDecimalNum(3, amt)
                ..rawData = Map<String, dynamic>.from(prod));
        }
      });
    }
    // 扫码多条命中跳转选品返回后恢复焦点（红外连续扫码场景）
    if (returnFocusNode != null && mounted) {
      _focusAfterScan(returnFocusNode);
    }
  }

  /// 主扫码按钮：打开相机扫码页面，将结果填入最后一个空行
  Future<void> _scanBarcode() async {
    // 对齐 Vue edit.vue：cgOrderLinkDhFlag==1 时扫描按钮禁用
    if (_cgOrderLinkDhFlag) {
      Toast.show('只能按照订货单采购入库，请通过选择原单带入商品');
      return;
    }
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

  /// 处理扫码结果：若商品已存在则累加数量，否则找到最后一个空行赋值并新增空行
  /// [returnFocusNode] 有值时，扫码完成后焦点回到该节点（用于红外扫描框连续扫码）
  void _handleScannedBarcode(String code, {FocusNode? returnFocusNode}) {
    if (code.trim().isEmpty) return;
    // 对齐 Vue edit.vue：cgOrderLinkDhFlag==1 时禁用扫描，
    // 拦截红外扫码/固定扫描等全部扫码链路
    if (_cgOrderLinkDhFlag) {
      Toast.show('只能按照订货单采购入库，请通过选择原单带入商品');
      return;
    }
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
      return;
    }

    // 尝试解析条码秤生成的重量码/金额码
    final scaleInfo = parseScaleBarcode(code);
    final searchCode = scaleInfo?.productCode ?? code;

    debugPrint(
        '[红外扫描] 开始查询条码: $code, searchCode=$searchCode, storeid=$_storeid, counterid=$_counterid, supid=$_supid, isEdit=$_isEdit, scaleType=${scaleInfo?.type}');
    final params = {
      'scancode': searchCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      ..._buildMergData(),
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
          _selectProducts(initialKeyword: searchCode, returnFocusNode: returnFocusNode);
          return;
        }
        final prod = primary ?? list.first as Map<String, dynamic>;
        final String prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
        final String barcode = prod['barcode']?.toString() ?? prod['selfbarcode']?.toString() ?? '';
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
                final newQty = MathUtils.formatDecimalNum(1, curQty + qtyDelta);
                existing.qtyController.text =
                    newQty == newQty.toInt() ? newQty.toInt().toString() : newQty.toString();
                // 编辑模式：同步更新 amt
                if (existing.amt != null) {
                  final price = MathUtils.formatDecimalNum(
                      2, double.tryParse(existing.priceController.text) ?? 0);
                  existing.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(newQty, price));
                }
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
          final price = MathUtils.formatDecimalNum(
              2,
              scanCgprice != 0
                  ? scanCgprice
                  : (double.tryParse(prod['price']?.toString() ?? '') ?? 0));
          final qty = MathUtils.formatDecimalNum(1, qtyDelta);
          final batchno = prod['batchno']?.toString() ?? '';
          final row = _DetailRow()
            ..nameController.text =
                prod['productname']?.toString() ?? prod['name']?.toString() ?? ''
            ..barcodeController.text = barcode
            ..qtyController.text = qty == qty.toInt() ? qty.toInt().toString() : qty.toString()
            ..priceController.text = MathUtils.formatDecimal(2, price)
            ..giftQtyController.text = '0'
            ..batchno = batchno
            ..batchController.text = batchno
            ..prodid = prodid
            ..amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price))
            ..rawData = Map<String, dynamic>.from(prod);
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
        // 连续扫码关闭：焦点转移到数量输入框并全选文本
        if (targetRow != null) {
          if (targetRow.qtyFocusNode.hasFocus) {
            // 已聚焦时焦点监听不会重复触发，手动全选文本
            targetRow.qtyController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: targetRow.qtyController.text.length,
            );
          } else {
            // 聚焦后由 _addOnFocusSelectAll 监听自动全选文本
            targetRow.qtyFocusNode.requestFocus();
          }
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

  // =================== 条码扫描处理 ===================
  /// 处理条码：根据条码搜索商品，取第一条赋值给当前行，然后新增空行并转移焦点
  void _processBarcode(int rowIndex) {
    if (rowIndex >= _items.length) return;
    if (_supid == null || _supid!.isEmpty) {
      Toast.show('请先选择供应商');
      return;
    }
    final row = _items[rowIndex];
    final code = row.barcodeController.text.trim();
    if (code.isEmpty) return;

    final params = {
      'scancode': code,
      'is_page': 1,
      'page': 1,
      'pagesize': 1,
      ..._buildMergData(),
    };

    request(HttpApi.productGetList, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isNotEmpty) {
        final prod = list.first as Map<String, dynamic>;
        setState(() {
          row.nameController.text =
              prod['productname']?.toString() ?? prod['name']?.toString() ?? '';
          row.qtyController.text = '1';
          // 采购价优先，为空或为 0 时回退档案进价（对齐选择页取值规则）
          final bcCgprice = double.tryParse(prod['cgprice']?.toString() ?? '') ?? 0;
          row.priceController.text =
              bcCgprice != 0 ? prod['cgprice'].toString() : (prod['price'] ?? 0).toString();
          row.batchno = prod['batchno']?.toString() ?? '';
          row.giftQtyController.text = '0';
          row.prodid = prod['prodid']?.toString() ?? prod['productid']?.toString() ?? '';
          row.rawData = Map<String, dynamic>.from(prod);

          // 新增空白行
          _items.add(_DetailRow());
        });
        Toast.show('扫描添加成功');

        // 焦点转移到新行的条码输入框
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _items.length > rowIndex + 1) {
            _items[rowIndex + 1].barcodeFocusNode.requestFocus();
          }
        });
      } else {
        if (mounted) {
          Toast.show('未找到匹配商品，请重新扫码录入！');
        }
      }
    });
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
                  final code = value.trim();
                  debugPrint('[红外扫描] onSubmitted: "$code"');
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
                    _handleScannedBarcode(
                      code,
                      returnFocusNode: _scanFocusNode,
                    );
                    if (mounted) {
                      _scanController.clear();
                      _scanFocusNode.requestFocus();
                      // 重新聚焦后再次隐藏软键盘
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

  // =================== 通用组件 ===================
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

  Widget _buildCard({
    required String title,
    required Widget child,
    Widget? action,
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
                  ),
                ),
                if (titleRight != null) titleRight,
                if (action != null) action,
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
          menuid: '050601',
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

  // _buildSelectField 已提取为公共组件 SelectFieldItem (lib/widgets/select_field_item.dart)

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

  // +/- 按钮组件
  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 14, color: const Color(0xFF374151)),
      ),
    );
  }

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
          initialSellprice: double.tryParse(
                raw['sellprice']?.toString() ??
                    raw['retailprice']?.toString() ??
                    raw['saleprice']?.toString() ??
                    '',
              ) ??
              0,
          initialAmt: row.amt ??
              MathUtils.formatDecimalNum(
                  3,
                  MathUtils.mul(double.tryParse(row.qtyController.text) ?? 0,
                      double.tryParse(row.priceController.text) ?? 0)),
          initialBatch: row.batchno ?? '',
          initialBirthdate: raw['birthdate']?.toString() ?? '',
          initialValiddate: raw['validdate']?.toString() ?? '',
          initialRemark: raw['remark']?.toString() ?? '',
          bsid: _storeid,
          counterid: _counterid,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final newPrice = MathUtils.formatDecimalNum(2, result['price'] as double);
        final qty = result['qty'] as double;
        final giftQty = MathUtils.formatDecimalNum(1, result['giftqty'] as double);
        final newAmt = MathUtils.formatDecimalNum(3, (result['amt'] as num?)?.toDouble() ?? 0);
        row.priceController.text = MathUtils.formatDecimal(2, newPrice);
        row.qtyController.text =
            qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2);
        row.giftQtyController.text = giftQty.toInt().toString();
        row.batchno = result['batchno']?.toString() ?? '';
        // 金额：优先取弹窗返回值（用户手动修改过金额则反算进价），否则 qty * price
        row.amt =
            newAmt != 0 ? newAmt : MathUtils.formatDecimalNum(3, MathUtils.mul(qty, newPrice));
        row.rawData = {
          ...raw,
          'price': newPrice,
          'qty': qty,
          'amt': row.amt,
          'sellprice': result['sellprice'],
          'sellamt': result['sellamt'],
          'batchno': result['batchno']?.toString() ?? '',
          'giftqty': giftQty,
          'presentqty': giftQty,
          'birthdate': result['birthdate'],
          'validdate': result['validdate'],
          'remark': result['remark'],
        };
      });
    }
  }
}

/// 入库明细行数据
class _DetailRow {
  _DetailRow() {
    initFocusListeners();
  }

  final TextEditingController barcodeController = TextEditingController();
  final FocusNode barcodeFocusNode = FocusNode();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController(text: '1');
  final TextEditingController priceController = TextEditingController();
  final TextEditingController giftQtyController = TextEditingController(text: '0');
  final TextEditingController batchController = TextEditingController();
  final FocusNode priceFocusNode = FocusNode();
  final FocusNode giftQtyFocusNode = FocusNode();
  final FocusNode qtyFocusNode = FocusNode();
  String? batchno;
  String? prodid;

  /// API 原始金额（编辑模式保留，新增模式为 null 由 qty*price 动态计算）
  double? amt;

  /// 门店库存（对齐 Vue stockqty，用于负库存校验）
  double stockqty = 0;

  /// 完整商品原始数据（从选择/扫描/语音获取），提交时与编辑值合并
  Map<String, dynamic>? rawData;

  void dispose() {
    barcodeController.dispose();
    barcodeFocusNode.dispose();
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    giftQtyController.dispose();
    batchController.dispose();
    priceFocusNode.dispose();
    giftQtyFocusNode.dispose();
    qtyFocusNode.dispose();
  }

  /// 为 FocusNode 添加聚焦全选监听
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
    _addOnFocusSelectAll(giftQtyFocusNode, giftQtyController);
    _addOnFocusSelectAll(qtyFocusNode, qtyController);
  }
}

/// 明细行独立 Widget，配合 SliverList.builder 实现懒加载
class _DetailItem extends StatefulWidget {
  const _DetailItem({
    required this.row,
    required this.index,
    this.isSelectMode = false,
    this.isSelected = false,
    this.readOnly = false,
    this.bsid,
    this.counterid,
    required this.onToggle,
    this.onChanged,
  });
  final _DetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final int? bsid;
  final String? counterid;
  final VoidCallback onToggle;

  /// 失焦回调：行金额格式化/重算完成后通知父页面刷新底部合计
  final VoidCallback? onChanged;

  @override
  State<_DetailItem> createState() => _DetailItemState();
}

class _DetailItemState extends State<_DetailItem> {
  // 直接使用 _DetailRow 的控制器（共享引用，无需自建/同步/销毁）
  TextEditingController get _priceCtrl => widget.row.priceController;
  TextEditingController get _giftQtyCtrl => widget.row.giftQtyController;
  TextEditingController get _qtyCtrl => widget.row.qtyController;
  TextEditingController get _batchCtrl => widget.row.batchController;
  // 焦点节点统一使用 _DetailRow 持有的实例（构造时已挂聚焦全选监听），
  // 确保 _focusAfterScan 通过 row.qtyFocusNode 能聚焦到实际输入框

  /// 失焦格式化监听器（绑定到对应 FocusNode，失焦时将输入值按 formatDecimal 规则格式化显示文本）
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

  /// 失焦时格式化输入框文本（不影响输入过程中的文本，只在完成编辑后格式化显示）
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

  /// 格式化商品名称（对齐 Vue proDetails.vue：productname/size(unit)）
  static String _formatProductName(String name, String size, String unit) {
    final sb = StringBuffer(name);
    if (size.isNotEmpty) sb.write('/$size');
    if (unit.isNotEmpty) sb.write('（$unit）');
    return sb.toString();
  }

  void _notifyChange() {
    final newPrice = MathUtils.formatDecimalNum(2, double.tryParse(_priceCtrl.text) ?? 0);
    final qty = MathUtils.formatDecimalNum(1, double.tryParse(_qtyCtrl.text) ?? 0);
    final giftQty = MathUtils.formatDecimalNum(1, double.tryParse(_giftQtyCtrl.text) ?? 0);
    // 同步到 rawData（编辑模式提交时从 rawData 构造参数）
    final raw = widget.row.rawData;
    if (raw != null) {
      raw['price'] = newPrice;
      raw['qty'] = qty;
      raw['amt'] = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, newPrice));
      raw['batchno'] = _batchCtrl.text.trim();
      raw['giftqty'] = giftQty;
      raw['presentqty'] = giftQty;
    }
    // 更新 _DetailRow 的 amt（用于汇总显示）
    widget.row.amt = MathUtils.formatDecimalNum(3, MathUtils.mul(qty, newPrice));
    widget.row.batchno = _batchCtrl.text.trim();
  }

  Future<void> _showProDetailDrawer() async {
    final raw = widget.row.rawData ?? {};
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
          initialPrice: double.tryParse(_priceCtrl.text) ?? 0,
          initialQty: double.tryParse(_qtyCtrl.text) ?? 0,
          initialGiftQty: double.tryParse(_giftQtyCtrl.text) ?? 0,
          initialSellprice: double.tryParse(
                raw['sellprice']?.toString() ??
                    raw['retailprice']?.toString() ??
                    raw['saleprice']?.toString() ??
                    '',
              ) ??
              0,
          initialAmt: widget.row.amt ??
              MathUtils.formatDecimalNum(
                  3,
                  MathUtils.mul(
                      double.tryParse(_qtyCtrl.text) ?? 0, double.tryParse(_priceCtrl.text) ?? 0)),
          initialBatch: _batchCtrl.text,
          initialBirthdate: raw['birthdate']?.toString() ?? '',
          initialValiddate: raw['validdate']?.toString() ?? '',
          initialRemark: raw['remark']?.toString() ?? '',
          bsid: widget.bsid,
          counterid: widget.counterid,
        ),
      ),
    );
    if (result != null && mounted) {
      final price = MathUtils.formatDecimalNum(2, (result['price'] as num).toDouble());
      final qty = MathUtils.formatDecimalNum(1, (result['qty'] as num).toDouble());
      final giftqty = MathUtils.formatDecimalNum(1, (result['giftqty'] as num).toDouble());
      final newAmt = MathUtils.formatDecimalNum(3, (result['amt'] as num?)?.toDouble() ?? 0);
      _priceCtrl.text = MathUtils.formatDecimal(2, price);
      _qtyCtrl.text = qty == qty.toInt()
          ? qty.toInt().toString()
          : qty.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      _giftQtyCtrl.text = giftqty.toInt().toString();
      _batchCtrl.text = result['batchno']?.toString() ?? '';
      // 金额：优先取弹窗返回值，否则 qty * price
      widget.row.amt =
          newAmt != 0 ? newAmt : MathUtils.formatDecimalNum(3, MathUtils.mul(qty, price));
      if (widget.row.rawData != null) {
        widget.row.rawData!['amt'] = widget.row.amt;
        widget.row.rawData!['sellprice'] = result['sellprice'];
        widget.row.rawData!['sellamt'] = result['sellamt'];
        widget.row.rawData!['birthdate'] = result['birthdate'];
        widget.row.rawData!['validdate'] = result['validdate'];
        widget.row.rawData!['remark'] = result['remark'];
        // 同步单位/规格选择结果到 rawData
        if (result['unit'] != null) widget.row.rawData!['unit'] = result['unit'];
        if (result['size'] != null) widget.row.rawData!['size'] = result['size'];
        if (result['unitonlyid'] != null) widget.row.rawData!['unitonlyid'] = result['unitonlyid'];
        if (result['sizeonlyid'] != null) widget.row.rawData!['sizeonlyid'] = result['sizeonlyid'];
      }
      _notifyChange();
      setState(() {});
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
    final String batchno = widget.row.batchno ?? '';
    final String code = raw?['barcode']?.toString() ?? raw?['selfbarcode']?.toString() ?? '';
    final String retailPrice =
        (double.tryParse(raw?['retailprice']?.toString() ?? raw?['sellprice']?.toString() ?? '0') ??
                0)
            .toStringAsFixed(2);

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
                // 列1: 商品信息 flex:5（点击弹商品详情抽屉）
                Expanded(
                  flex: 5,
                  child: GestureDetector(
                    onTap: widget.readOnly ? null : _showProDetailDrawer,
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
                        const SizedBox(height: 2),
                        Text('零售价：¥$retailPrice',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                        const SizedBox(height: 2),
                        Text(
                          batchno.isNotEmpty ? '批次：$batchno' : '无批次',
                          style: TextStyle(
                              fontSize: 11,
                              color: batchno.isNotEmpty
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF006EFF)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 右侧：输入字段 + 小计
                Expanded(
                  flex: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          // 列2: 采购进价 flex:3
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
                                textInputAction: TextInputAction.next,
                                textAlign: TextAlign.center,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                ],
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
                                onSubmitted: (_) {
                                  _notifyChange();
                                  widget.row.giftQtyFocusNode.requestFocus();
                                },
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
                                keyboardType: const TextInputType.numberWithOptions(),
                                textInputAction: TextInputAction.next,
                                textAlign: TextAlign.center,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*')),
                                ],
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
                                onSubmitted: (_) {
                                  _notifyChange();
                                  widget.row.qtyFocusNode.requestFocus();
                                },
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
                                textInputAction: TextInputAction.done,
                                textAlign: TextAlign.center,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                ],
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
                                onSubmitted: (_) {
                                  _notifyChange();
                                  widget.row.qtyFocusNode.unfocus();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      // 小计行（实时更新）
                      ListenableBuilder(
                        listenable: Listenable.merge(
                            [widget.row.qtyController, widget.row.priceController]),
                        builder: (_, __) {
                          final q = double.tryParse(widget.row.qtyController.text) ?? 0;
                          final p = double.tryParse(widget.row.priceController.text) ?? 0;
                          final a = widget.row.amt != null
                              ? widget.row.amt!.toStringAsFixed(2)
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
      ),
    );
  }
}

// =================== 商品详情抽屉 ===================
/// 字段与 boss proDetails.vue 对齐：采购进价/入库数量/赠送/零售价/金额/批次/生产日期/有效日期/备注
class _ProDetailSheet extends StatefulWidget {
  const _ProDetailSheet({
    required this.productData,
    required this.initialPrice,
    required this.initialQty,
    required this.initialGiftQty,
    required this.initialSellprice,
    required this.initialAmt,
    required this.initialBatch,
    required this.initialBirthdate,
    required this.initialValiddate,
    required this.initialRemark,
    this.bsid,
    this.counterid,
  });
  final Map<String, dynamic> productData;
  final double initialPrice;
  final double initialQty;
  final double initialGiftQty;

  /// 初始零售价（对齐 Vue edit.vue row.sellprice）
  final double initialSellprice;

  /// 初始金额（对齐 Vue edit.vue row.amt，编辑模式取接口返回值）
  final double initialAmt;
  final String initialBatch;
  final String initialBirthdate;
  final String initialValiddate;
  final String initialRemark;
  final int? bsid;
  final String? counterid;

  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _giftCtrl;
  late TextEditingController _sellpriceCtrl;
  late TextEditingController _amtCtrl;
  late TextEditingController _batchCtrl;
  late TextEditingController _birthdateCtrl;
  late TextEditingController _validdateCtrl;
  late TextEditingController _remarkCtrl;

  /// 金额是否被用户手动修改（对齐 Vue writeData 的 _amtManual）
  bool _amtManual = false;

  /// 程序性更新金额标志：避免 _syncAmt 回写文本时误标记手动修改
  bool _updatingAmt = false;

  /// 销售金额 = 零售价 ×（数量 + 赠送数量）（对齐 Vue writeData 通用 sellamt 逻辑）
  double _sellamt = 0;

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

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: widget.initialPrice.toStringAsFixed(2));
    final qty = widget.initialQty;
    _qtyCtrl = TextEditingController(
      text: qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2),
    );
    _giftCtrl = TextEditingController(text: widget.initialGiftQty.toStringAsFixed(0));
    // 零售价初始值：productData 的 sellprice/retailprice/saleprice
    final spVal = double.tryParse(
          widget.productData['sellprice']?.toString() ??
              widget.productData['retailprice']?.toString() ??
              widget.productData['saleprice']?.toString() ??
              '',
        ) ??
        widget.initialSellprice;
    _sellpriceCtrl = TextEditingController(text: spVal.toStringAsFixed(2));
    _amtCtrl = TextEditingController(text: MathUtils.formatDecimal(3, widget.initialAmt));
    _batchCtrl = TextEditingController(text: widget.initialBatch);
    _birthdateCtrl = TextEditingController(text: widget.initialBirthdate);
    _validdateCtrl = TextEditingController(text: widget.initialValiddate);
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
    // 初始化单位/规格状态
    _currentUnit = widget.productData['unit']?.toString() ?? '';
    _currentSize = widget.productData['size']?.toString() ?? '';
    _unitonlyid = widget.productData['unitonlyid']?.toString() ?? '';
    _sizeonlyid = widget.productData['sizeonlyid']?.toString() ?? '';
    // 价格/数量/赠送变化 → 联动重算金额与销售金额（对齐 Vue writeData）
    _priceCtrl.addListener(_onCalcChanged);
    _qtyCtrl.addListener(_onCalcChanged);
    _giftCtrl.addListener(_onCalcChanged);
    // 零售价变化 → 重算销售金额，并自动重算金额（未手动修改时）
    _sellpriceCtrl.addListener(_onSellpriceChanged);
    // 金额输入 → 标记手动修改（对齐 Vue writeData key==amt 的 _amtManual）
    _amtCtrl.addListener(_onAmtChanged);
    _syncSellamt();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _giftCtrl.dispose();
    _sellpriceCtrl.dispose();
    _amtCtrl.dispose();
    _batchCtrl.dispose();
    _birthdateCtrl.dispose();
    _validdateCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  // ─── 金额/销售金额联动（对齐 Vue edit.vue writeData）─────────────

  /// 价格/数量/赠送变化：重算销售金额，金额未手动修改时重算 amt = qty × price
  void _onCalcChanged() {
    if (_updatingAmt) return;
    _syncSellamt();
    _syncAmt();
  }

  /// 零售价变化：重算 sellamt = sellprice × (qty + presentqty)，未手动修改时重算 amt
  void _onSellpriceChanged() {
    _syncSellamt();
    _syncAmt();
  }

  /// 用户编辑金额 → 标记手动修改
  void _onAmtChanged() {
    if (_updatingAmt) return;
    _amtManual = true;
  }

  /// 金额自动重算（对齐 Vue writeData：!v._amtManual 时 amt = qty × price）
  void _syncAmt() {
    if (_amtManual) return;
    final q = double.tryParse(_qtyCtrl.text) ?? 0;
    final p = double.tryParse(_priceCtrl.text) ?? 0;
    _updatingAmt = true;
    _amtCtrl.text = MathUtils.formatDecimal(3, MathUtils.mul(q, p));
    _updatingAmt = false;
  }

  /// 销售金额重算（对齐 Vue writeData：sellamt = sellprice × (qty + presentqty)）
  void _syncSellamt() {
    final sp = double.tryParse(_sellpriceCtrl.text) ?? 0;
    final q = double.tryParse(_qtyCtrl.text) ?? 0;
    final gift = double.tryParse(_giftCtrl.text) ?? 0;
    _sellamt = MathUtils.formatDecimalNum(3, MathUtils.mul(sp, MathUtils.add(q, gift)));
  }

  /// 金额反算进价（对齐 Vue writeData key==amt：price = amt / qty）
  void _applyAmtToPrice() {
    final q = double.tryParse(_qtyCtrl.text) ?? 0;
    if (q <= 0) return;
    final amt = double.tryParse(_amtCtrl.text) ?? 0;
    _amtManual = true;
    _priceCtrl.text = MathUtils.formatDecimal(2, MathUtils.divide(amt, q));
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

  @override
  Widget build(BuildContext context) {
    final data = widget.productData;
    final String name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    final String barcode = data['barcode']?.toString() ?? '';
    final double spVal = double.tryParse(
          data['saleprice']?.toString() ??
              data['retailprice']?.toString() ??
              data['sellprice']?.toString() ??
              '0',
        ) ??
        0;
    final String saleprice = spVal.toStringAsFixed(2);
    final String shelves = data['shelves']?.toString() ?? '';
    // 原进价（采购价优先，为空或为 0 时回退档案进价，对齐选择页取值规则）
    final double origCgprice = double.tryParse(data['cgprice']?.toString() ?? '') ?? 0;
    final String origPrice =
        origCgprice != 0 ? data['cgprice'].toString() : (data['price']?.toString() ?? '0');

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
                  const Text(
                    '商品详情',
                    style: TextStyle(
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
                    // 原进价（只读）
                    _buildInfoRow('原进价', origPrice),
                    _buildDivider(),
                    // 单位（可点击选择，对齐 Vue proDetails.vue unit 字段）
                    _buildUnitSelectField(),
                    _buildDivider(),
                    // 规格（可点击选择，对齐 Vue proDetails.vue size 字段）
                    _buildSizeSelectField(),
                    _buildDivider(),
                    _buildFormField(label: '采购进价', controller: _priceCtrl, isDecimal: true),
                    _buildDivider(),
                    _buildFormField(label: '入库数量', controller: _qtyCtrl, isDecimal: true),
                    _buildDivider(),
                    _buildFormField(label: '赠送数量', controller: _giftCtrl),
                    _buildDivider(),
                    // 零售价（对齐 Vue edit.vue sellprice，变化时联动重算金额）
                    _buildFormField(label: '零售价', controller: _sellpriceCtrl, isDecimal: true),
                    _buildDivider(),
                    // 金额（对齐 Vue edit.vue amt，编辑后回车反算进价）
                    _buildFormField(
                      label: '金额',
                      controller: _amtCtrl,
                      isDecimal: true,
                      onSubmitted: (_) => _applyAmtToPrice(),
                    ),
                    _buildDivider(),
                    // 商品批次（使用 SelectBatchSheet 选择，带出日期）
                    _buildBatchSelectField(),
                    _buildDivider(),
                    _buildDateField(label: '生产日期', ctrl: _birthdateCtrl),
                    _buildDivider(),
                    _buildDateField(label: '有效日期', ctrl: _validdateCtrl),
                    _buildDivider(),
                    _buildFormField(
                        label: '备注',
                        controller: _remarkCtrl,
                        keyboardType: TextInputType.text,
                        maxLines: 2),
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
                        // 金额回车反算进价后再取当前值（对齐 Vue writeData key==amt）
                        _applyAmtToPrice();
                        Navigator.pop(context, {
                          'price': MathUtils.formatDecimalNum(
                              2, double.tryParse(_priceCtrl.text) ?? 0.0),
                          'qty':
                              MathUtils.formatDecimalNum(1, double.tryParse(_qtyCtrl.text) ?? 0.0),
                          'giftqty':
                              MathUtils.formatDecimalNum(1, double.tryParse(_giftCtrl.text) ?? 0.0),
                          'sellprice': MathUtils.formatDecimalNum(
                              2, double.tryParse(_sellpriceCtrl.text) ?? 0.0),
                          'amt':
                              MathUtils.formatDecimalNum(3, double.tryParse(_amtCtrl.text) ?? 0.0),
                          'sellamt': _sellamt,
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
    ValueChanged<String>? onSubmitted,
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
              keyboardType:
                  isDecimal ? const TextInputType.numberWithOptions(decimal: true) : keyboardType,
              inputFormatters:
                  isDecimal ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))] : null,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              onSubmitted: onSubmitted,
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

  Widget _buildDateField({required String label, required TextEditingController ctrl}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: () => _pickDate(ctrl),
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

  /// 批次选择字段：可输入文本 + 右侧箭头打开选择器，选中后自动带出生产日期和有效期
  /// 对齐 Vue proDetails.vue 的 batchno 字段交互（输入框 + selectCom 选择器）
  Widget _buildBatchSelectField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 80,
            child: Text('商品批次',
                style:
                    TextStyle(fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextField(
              controller: _batchCtrl,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '输入或选择',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () async {
              final productid = widget.productData['productid']?.toString() ??
                  widget.productData['prodid']?.toString() ??
                  '';
              if (productid.isEmpty) {
                Toast.show('商品信息异常');
                return;
              }
              // 收起软键盘
              FocusScope.of(context).unfocus();
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
                  // 选择批次后自动带出生产日期和有效期（对齐 web handleBatchConfirm）
                  final birthdate = _formatBatchDate(result['birthdate']);
                  _birthdateCtrl.text = birthdate;
                  final validdate = _formatBatchDate(result['validdate']);
                  _validdateCtrl.text = validdate.isEmpty ? birthdate : validdate;
                });
              }
            },
            child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFFD1D5DB)),
          ),
        ],
      ),
    );
  }

  /// 只读信息行
  Widget _buildInfoRow(String label, String value) {
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
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
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
        // cgpriceflag 模式：unitConfirm 价格逻辑
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
        // 条码/编码更新（sbarcode / scode 优先，对齐 Vue unitConfirm）
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
        // 货架号同步（对齐 Vue unitConfirm，仅接口返回时更新）
        final sh = result['shelves']?.toString();
        if (sh != null) data['shelves'] = sh;
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
        // 零售价更新
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

/// 粘性表头代理：将扫描框 + 商品明细标题/列头固定在滚动顶部
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.state});
  final _PurchaseInstoreAddPageState state;

  @override
  double get minExtent => _PurchaseInstoreAddPageState._stickyMinExtent;

  @override
  double get maxExtent => state._showScanBox
      ? _PurchaseInstoreAddPageState._stickyMaxExtent
      : _PurchaseInstoreAddPageState._stickyMinExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader();
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) => true;
}

/// 审批弹窗（通过/驳回 + 备注）
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
