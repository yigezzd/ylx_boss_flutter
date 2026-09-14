import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/select/select_brand.dart';
import 'package:flutter_deer/components/select/select_location.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/components/select/select_unit.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart';
import 'package:flutter_deer/pages/business/basis/commodity/add_package.dart';
import 'package:flutter_deer/pages/business/basis/commodity/bundle.dart';
import 'package:flutter_deer/pages/business/basis/commodity/more_price.dart';
import 'package:flutter_deer/pages/business/basis/commodity/prize.dart';
import 'package:flutter_deer/pages/business/basis/commodity/product.dart';
import 'package:flutter_deer/pages/business/basis/commodity/spec.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:flutter_deer/widgets/select_field_item.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sp_util/sp_util.dart';

/// 表单默认值（与 Vue boss 项目 queryDefault 对齐）
const Map<String, dynamic> _formDefault = {
  'barcode': '',
  'productname': '',
  'name': '',
  'shortname': '',
  'helpcode': '',
  'code': '',
  'imageurl': '',
  'typeid': '',
  'typename': '',
  'typecode': '',
  'size': '',
  'unit': '',
  'defcgunit': '',
  'defpfunit': '',
  'defpsunit': '',
  'brandname': '',
  'remark': '',
  'itemtype': 1,
  'pricetype': 1,
  'selltype': 1,
  'pstype': 1,
  'memorytype': 1,
  'supid': '',
  'supname': '',
  'inprice': '',
  'sellprice': '',
  'grossrate': '',
  'mprice1': '',
  'mprice2': '',
  'mprice3': '',
  'pfprice1': '',
  'pfprice2': '',
  'pfprice3': '',
  'psprice': '',
  'minsellprice': '',
  'maxstock': '',
  'minstock': '',
  'initstorage': '',
  'pointbase': '',
  'point': '',
  'promotionprice': '',
  'promotionbegintime': '',
  'promotionendtime': '',
  'intaxrate': '',
  'outtaxrate': '',
  'custorderqtymin': '',
  'stockflag': 1,
  'initstorageflag': 0,
  'pointflag': 1,
  'pointtype': 1,
  'validflag': 0,
  'sellflag': 1,
  'changepriceflag': 1,
  'snflag': 0,
  'freshflag': 0,
  'freepriceflag': 0,
  'nousecouponsflag': 0,
  'promotionflag': 1,
  'home': '',
  'itemstatus': 2,
  'deducttype': 1,
  'deductvalue': '',
  'dscflag': 1,
  'presentflag': 1,
  'validday': '',
  'locationcode': '',
  'locationid': '',
  'packagenum': 1,
  'extendlist': <Map<String, dynamic>>[],
  'prizelist': <Map<String, dynamic>>[],
};

class CommodityAddPage extends StatefulWidget {
  const CommodityAddPage({
    super.key,
    this.productData,
    this.applynewflag,
    this.status,
    this.initialTypeId,
    this.initialTypecode,
    this.initialTypename,
  });

  /// 从列表页传入的商品数据（包含 productid 等字段）
  /// 有值表示编辑/查看模式，null 则为新增模式
  final Map<String, dynamic>? productData;

  /// 新品申请标记，1 表示从新品申请入口进入
  final int? applynewflag;

  /// 新品申请状态（1-待提交 2-待审核 3-已审核 4-已驳回）
  final int? status;

  /// 列表页筛选的分类（新增时预填，对齐小程序 add()）
  final String? initialTypeId;
  final String? initialTypecode;
  final String? initialTypename;

  @override
  State<CommodityAddPage> createState() => _CommodityAddPageState();
}

class _CommodityAddPageState extends State<CommodityAddPage> with TickerProviderStateMixin {
  late TabController _tabController;

  // ── 表单中心数据对象（类似 Vue boss 项目的 query）──
  // 所有输入框通过 listener 自动同步到此 Map，下拉/开关直接更新 _form[key]
  // 保存时直接基于 _form 构建参数，无需逐字段手动收集
  late Map<String, dynamic> _form;

  // ── 非表单 UI 状态 ──
  bool _submitting = false;
  bool _detailLoading = false;
  bool _isZd = false; // 当前登录门店是否为主店（store.id == store.spid）
  Map<String, dynamic>? _productData; // 接口返回的完整数据（编辑模式）
  String _imageurl = '';
  bool _uploading = false;
  List<Map<String, dynamic>> _codes = [
    {'code': ''}
  ];
  bool _resettingForm = false; // 重置时禁止 listener 触发 setState

  bool get _isEdit =>
      widget.productData != null &&
      (widget.productData!['productid']?.toString().isNotEmpty ?? false);

  /// 只读模式：新品申请流程下，已审核(3) 或已驳回(4) 状态禁止编辑
  bool get _isReadOnly {
    final isApplyMode = widget.applynewflag != null;
    final status = widget.status?.toString();
    return isApplyMode && (status == '3' || status == '4');
  }

  /// 是否为新品申请模式
  bool get _isApplyMode => widget.applynewflag != null;

  /// 权限映射：根据当前上下文返回对应 menuId，确保商品档案/新品申请权限独立
  String _permId(String key) {
    switch (key) {
      case 'add':
        return _isApplyMode ? '010301' : '010202';
      case 'edit':
        return _isApplyMode ? '010305' : '010203';
      case 'delete':
        return _isApplyMode ? '010307' : '010204';
      case 'submit':
        return '010306'; // 仅新品申请使用
      default:
        return '';
    }
  }

  /// 权限提示文案映射
  String _permLabel(String key) {
    final label = _isApplyMode ? '新品申请' : '商品档案';
    switch (key) {
      case 'add':
        return '新增$label';
      case 'edit':
        return '编辑$label';
      case 'delete':
        return '删除$label';
      case 'submit':
        return '提交新品申请';
      default:
        return '操作$label';
    }
  }

  /// 统一权限校验入口：成功返回 true，失败则 Toast 精准提示
  bool _checkPerm(String key) {
    final menuId = _permId(key);
    if (menuId.isEmpty) return true; // 无映射则放行
    if (!PermissionUtils.checkPermission(menuId, showTip: false)) {
      Toast.show('你无权${_permLabel(key)}，请在后台修改权限');
      return false;
    }
    return true;
  }

  // 下拉选项常量
  static const List<Map<String, dynamic>> _itemTypeOptions = [
    {'label': '普通', 'value': 1},
    {'label': '拆分', 'value': 2},
    {'label': '组装', 'value': 3},
    {'label': '自动拆分', 'value': 4},
    {'label': '自动组装', 'value': 5},
    {'label': '特价打包', 'value': 8},
    {'label': '兑奖换购', 'value': 10},
  ];

  /// 商品类型选项（包装配置模式下动态追加「包装单位」，对齐小程序 itemypeList）
  List<Map<String, dynamic>> get _itemTypeOptionList => [
        ..._itemTypeOptions,
        if (_packagSettingMode == 2) {'label': '包装商品', 'value': 9},
      ];

  /// 读取登录参数 packagSettingMode（1=包装单位 Tab，2=包装配置模式，对齐小程序 loginParamResp）
  int get _packagSettingMode {
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
        return int.tryParse(cfg['packagSettingMode']?.toString() ?? '') ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  int get _formItemtype => int.tryParse(_form['itemtype'].toString()) ?? 1;

  /// 是否展示「包装单位」Tab（对齐小程序：packagSettingMode==1 且非拆分/组装类）
  bool get _showPackUnitTab => _packagSettingMode == 1 && ![2, 3, 4, 5].contains(_formItemtype);

  /// 是否展示「包装配置」Tab（对齐小程序：packagSettingMode==2 且 itemtype==9 包装单位商品）
  bool get _showPackConfigTab => _packagSettingMode == 2 && _formItemtype == 9;

  int get _tabLength => (_showPackUnitTab || _showPackConfigTab) ? 3 : 2;

  /// 商品类型变化时动态重建 TabController（长度随 packagSettingMode 与 itemtype 变化）
  void _syncTabController() {
    if (_tabController.length != _tabLength) {
      final index = _tabController.index.clamp(0, _tabLength - 1);
      final old = _tabController;
      // 先创建新 controller，旧 controller 延后到帧末 dispose：
      // 重建帧期间挂载中的 TabBar/TabBarView 仍需从旧 controller 安全退订
      _tabController = TabController(length: _tabLength, vsync: this, initialIndex: index);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  static const List<Map<String, dynamic>> _priceTypeOptions = [
    {'label': '普通商品', 'value': 1},
    {'label': '计重商品', 'value': 2},
    {'label': '计份商品', 'value': 3},
  ];

  static const List<Map<String, dynamic>> _sellTypeOptions = [
    {'label': '购销', 'value': 1},
    {'label': '联营', 'value': 2},
    {'label': '成本代销', 'value': 3},
    {'label': '扣率代销', 'value': 4},
    {'label': '租赁', 'value': 5},
  ];

  static const List<Map<String, dynamic>> _psTypeOptions = [
    {'label': '统配', 'value': 1},
    {'label': '直配', 'value': 2},
    {'label': '自采', 'value': 3},
    {'label': '越库', 'value': 4},
  ];

  static const List<Map<String, dynamic>> _memoryTypeOptions = [
    {'label': '常温', 'value': 1},
    {'label': '冷藏', 'value': 2},
    {'label': '冷冻', 'value': 3},
  ];

  // ── 基础信息 Controller ──
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _shortnameController = TextEditingController();
  final TextEditingController _helpcodeController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();
  final TextEditingController _brandnameController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _inpriceController = TextEditingController();
  final TextEditingController _sellpriceController = TextEditingController();
  final TextEditingController _grossrateController = TextEditingController();
  final TextEditingController _mprice1Controller = TextEditingController();
  final TextEditingController _mprice2Controller = TextEditingController();
  final TextEditingController _mprice3Controller = TextEditingController();
  final TextEditingController _pfprice1Controller = TextEditingController();
  final TextEditingController _pfprice2Controller = TextEditingController();
  final TextEditingController _pfprice3Controller = TextEditingController();
  final TextEditingController _pspriceController = TextEditingController();
  final TextEditingController _minsellpriceController = TextEditingController();

  // ── 更多信息 Controller ──
  final TextEditingController _homeController = TextEditingController();
  final TextEditingController _maxstockController = TextEditingController();
  final TextEditingController _minstockController = TextEditingController();
  final TextEditingController _initstorageController = TextEditingController();
  final TextEditingController _pointbaseController = TextEditingController();
  final TextEditingController _pointController = TextEditingController();
  final TextEditingController _promotionpriceController = TextEditingController();
  final TextEditingController _promotionbegintimeController = TextEditingController();
  final TextEditingController _promotionendtimeController = TextEditingController();
  final TextEditingController _intaxrateController = TextEditingController();
  final TextEditingController _outtaxrateController = TextEditingController();
  final TextEditingController _custorderqtyminController = TextEditingController();
  final TextEditingController _deductvalueController = TextEditingController();
  final TextEditingController _validdayController = TextEditingController();
  final TextEditingController _joinrateController = TextEditingController();

  // ── 失焦格式化用 FocusNode（对齐 Vue priceBlur）──
  final FocusNode _inpriceFocusNode = FocusNode();
  final FocusNode _sellpriceFocusNode = FocusNode();
  final FocusNode _grossrateFocusNode = FocusNode();
  final FocusNode _pspriceFocusNode = FocusNode();
  final FocusNode _minsellpriceFocusNode = FocusNode();
  final FocusNode _maxstockFocusNode = FocusNode();
  final FocusNode _minstockFocusNode = FocusNode();
  final FocusNode _initstorageFocusNode = FocusNode();
  final FocusNode _promotionpriceFocusNode = FocusNode();
  final FocusNode _pointbaseFocusNode = FocusNode();
  final FocusNode _pointFocusNode = FocusNode();
  final FocusNode _intaxrateFocusNode = FocusNode();
  final FocusNode _outtaxrateFocusNode = FocusNode();
  final FocusNode _deductvalueFocusNode = FocusNode();
  final FocusNode _joinrateFocusNode = FocusNode();

  /// controller → _form key 映射
  late final Map<TextEditingController, String> _ctrlKeyMap = {
    _barcodeController: 'barcode',
    _nameController: 'name',
    _shortnameController: 'shortname',
    _helpcodeController: 'helpcode',
    _codeController: 'code',
    _sizeController: 'size',
    _unitController: 'unit',
    _brandnameController: 'brandname',
    _remarkController: 'remark',
    _inpriceController: 'inprice',
    _sellpriceController: 'sellprice',
    _grossrateController: 'grossrate',
    _mprice1Controller: 'mprice1',
    _mprice2Controller: 'mprice2',
    _mprice3Controller: 'mprice3',
    _pfprice1Controller: 'pfprice1',
    _pfprice2Controller: 'pfprice2',
    _pfprice3Controller: 'pfprice3',
    _pspriceController: 'psprice',
    _minsellpriceController: 'minsellprice',
    _homeController: 'home',
    _maxstockController: 'maxstock',
    _minstockController: 'minstock',
    _initstorageController: 'initstorage',
    _pointbaseController: 'pointbase',
    _pointController: 'point',
    _promotionpriceController: 'promotionprice',
    _promotionbegintimeController: 'promotionbegintime',
    _promotionendtimeController: 'promotionendtime',
    _intaxrateController: 'intaxrate',
    _outtaxrateController: 'outtaxrate',
    _custorderqtyminController: 'custorderqtymin',
    _deductvalueController: 'deductvalue',
    _validdayController: 'validday',
    _joinrateController: 'joinrate',
  };

  @override
  void initState() {
    super.initState();
    _form = Map<String, dynamic>.from(_formDefault);
    _form['packlinkpro'] = [_packlinkproDefaultRow()];
    _tabController = TabController(length: _tabLength, vsync: this);
    // 判断当前门店是否为主店（isZd），用于新品申请审核按钮显示
    final storeStr = SpUtil.getString('store') ?? '';
    if (storeStr.isNotEmpty) {
      try {
        final storeMap = jsonDecode(storeStr);
        final id = storeMap['id']?.toString() ?? '';
        final spid = storeMap['spid']?.toString() ?? '';
        _isZd = id == spid;
      } catch (_) {}
    }
    // controller 文本变更自动同步到 _form
    for (final entry in _ctrlKeyMap.entries) {
      entry.key.addListener(() {
        if (!_resettingForm) {
          setState(() => _form[entry.value] = entry.key.text);
        }
      });
    }
    // 失焦格式化（对齐 Vue priceBlur）
    _addBlurListener(_inpriceFocusNode, _inpriceController, 2);
    _addBlurListener(_sellpriceFocusNode, _sellpriceController, 2);
    _addBlurListener(_grossrateFocusNode, _grossrateController, 2);
    _addBlurListener(_pspriceFocusNode, _pspriceController, 2);
    _addBlurListener(_minsellpriceFocusNode, _minsellpriceController, 2);
    _addBlurListener(_maxstockFocusNode, _maxstockController, 1);
    _addBlurListener(_minstockFocusNode, _minstockController, 1);
    _addBlurListener(_initstorageFocusNode, _initstorageController, 1);
    _addBlurListener(_promotionpriceFocusNode, _promotionpriceController, 2);
    _addBlurListener(_pointbaseFocusNode, _pointbaseController, 2);
    _addBlurListener(_pointFocusNode, _pointController, 1);
    _addBlurListener(_intaxrateFocusNode, _intaxrateController, 1, clampMax: 1);
    _addBlurListener(_outtaxrateFocusNode, _outtaxrateController, 1, clampMax: 1);
    _addBlurListener(_deductvalueFocusNode, _deductvalueController, 2);
    _addBlurListener(_joinrateFocusNode, _joinrateController, 1);
    if (_isEdit) {
      _loadDetail();
    } else if (widget.initialTypeId != null && widget.initialTypeId!.isNotEmpty) {
      // 对齐小程序 add()：从列表新增时预填分类并自动生成条码/自编码
      _form['typeid'] = widget.initialTypeId;
      _form['typecode'] = widget.initialTypecode ?? '';
      _form['typename'] = widget.initialTypename ?? '';
      // 延迟到下一帧执行，确保 controller listener 已就绪
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _autoGenBarcodeAndCode();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final ctrl in _ctrlKeyMap.keys) {
      ctrl.dispose();
    }
    for (final fn in [
      _inpriceFocusNode,
      _sellpriceFocusNode,
      _grossrateFocusNode,
      _pspriceFocusNode,
      _minsellpriceFocusNode,
      _maxstockFocusNode,
      _minstockFocusNode,
      _initstorageFocusNode,
      _promotionpriceFocusNode,
      _pointbaseFocusNode,
      _pointFocusNode,
      _intaxrateFocusNode,
      _outtaxrateFocusNode,
      _deductvalueFocusNode,
      _joinrateFocusNode,
    ]) {
      fn.dispose();
    }
    super.dispose();
  }

  // =================== 加载商品详情 ===================
  void _loadDetail() {
    setState(() => _detailLoading = true);
    request(HttpApi.productGetInfo, {
      'productid': widget.productData!['productid']?.toString() ?? '',
      'applynewflag': widget.applynewflag?.toString() ?? '',
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _productData = data;
          _fillFormFromData(data);
          // 加载后按 itemtype/packagSettingMode 同步 Tab 数量
          _syncTabController();
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  /// 从接口数据填充 _form 和 controllers（编辑模式加载详情时调用）
  void _fillFormFromData(Map<String, dynamic> data) {
    _resettingForm = true;

    // 将 API 数据合并到 _form（覆盖默认值）
    for (final entry in data.entries) {
      if (entry.value != null) {
        _form[entry.key] = entry.value;
      }
    }

    // 兼容 name/productname 双字段
    final name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    _form['name'] = name;
    _form['productname'] = name;

    // 同步 controller 显示值
    for (final entry in _ctrlKeyMap.entries) {
      final value = _form[entry.value]?.toString() ?? '';
      if (entry.key.text != value) {
        entry.key.text = value;
      }
    }

    // 设置小数位（对齐 Vue handleAfterParams）
    // 1位小数
    for (final key in ['initstorage', 'point', 'maxstock', 'minstock', 'intaxrate', 'outtaxrate']) {
      final raw = _form[key];
      if (raw != null && raw.toString().isNotEmpty) {
        _form[key] = MathUtils.formatDecimal(1, raw);
      }
    }
    // 2位小数
    for (final key in [
      'inprice',
      'sellprice',
      'mprice1',
      'mprice2',
      'mprice3',
      'pfprice1',
      'pfprice2',
      'pfprice3',
      'psprice',
      'minsellprice',
      'grossrate',
      'promotionprice',
      'pointbase',
    ]) {
      final raw = _form[key];
      if (raw != null && raw.toString().isNotEmpty) {
        _form[key] = MathUtils.formatDecimal(2, raw);
      }
    }
    // 提成金额/比例：按金额时2位，按比例时1位（默认2位，切换时再调整）
    final deductRaw = _form['deductvalue'];
    if (deductRaw != null && deductRaw.toString().isNotEmpty) {
      _form['deductvalue'] = MathUtils.formatDecimal(2, deductRaw);
    }

    // 重新计算毛利率（对齐 Vue edit.vue：加载详情后调用 jsGrossrate）
    _jsGrossrate();

    // 重新同步格式化后的值到 controller
    _resettingForm = true;
    for (final entry in _ctrlKeyMap.entries) {
      final value = _form[entry.value]?.toString() ?? '';
      if (entry.key.text != value) {
        entry.key.text = value;
      }
    }
    _resettingForm = false;

    // 图片
    _imageurl = data['imageurl']?.toString() ?? '';

    // 一品多码
    final codesList = data['codes'] as List? ?? [];
    _codes = codesList.isNotEmpty
        ? codesList.cast<Map<String, dynamic>>()
        : [
            {'code': ''}
          ];

    // 多规格
    final defaultSize = Map<String, dynamic>.from(_formDefault);
    final sizedataList = data['sizedata'] as List? ?? data['productSize7'] as List? ?? [];
    _form['sizedata'] =
        sizedataList.isNotEmpty ? sizedataList.cast<Map<String, dynamic>>() : [defaultSize];

    // 包装单位（API 返回 productSize6，对齐 Vue handleAfterParams）
    final packList = data['productSize6'] as List? ?? data['packpage'] as List? ?? [];
    _form['packpage'] = packList.cast<Map<String, dynamic>>();

    // 包装配置（对齐 Vue handleAfterParams：packlinkpro 为空时补默认行）
    final packlinkList = data['packlinkpro'] as List? ?? [];
    _form['packlinkpro'] = packlinkList.isNotEmpty
        ? packlinkList.cast<Map<String, dynamic>>()
        : [_packlinkproDefaultRow()];

    // 商品明细（成份）
    final extendlistList = data[_extendlistKey] as List? ?? [];
    _form[_extendlistKey] = extendlistList.cast<Map<String, dynamic>>();

    // 兑奖换购（itemtype=10）：明细取自 productSize10（与 Vue/Web 端一致）
    final itemtype = _parseIntOr(data['itemtype'], 1);
    if (itemtype == 10) {
      final prizeDetails = data['productSize10'] as List? ?? [];
      _form['prizelist'] = prizeDetails.cast<Map<String, dynamic>>();
    }

    // 确保整型字段正确
    final intFields = {
      'itemtype': 1,
      'pricetype': 1,
      'selltype': 1,
      'pstype': 1,
      'memorytype': 1,
      'stockflag': 1,
      'initstorageflag': 0,
      'pointflag': 0,
      'pointtype': 1,
      'validflag': 0,
      'sellflag': 1,
      'changepriceflag': 0,
      'snflag': 0,
      'freshflag': 0,
      'freepriceflag': 0,
      'promotionflag': 0,
      'itemstatus': 2,
      'deducttype': 1,
      'dscflag': 0,
      'presentflag': 0,
    };
    for (final entry in intFields.entries) {
      _form[entry.key] = _parseIntOr(data[entry.key], entry.value);
    }

    _resettingForm = false;
  }

  static int _parseIntOr(dynamic val, int defaultVal) {
    if (val == null) return defaultVal;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? defaultVal;
  }

  // =================== 毛利率联动计算（从 _form 读取） ===================

  /// 重算毛利率（对齐 Vue jsGrossrate：加载详情后调用）
  /// sellprice == 0 → 100；两价均存在 → (sellprice - inprice) / sellprice * 100，保留2位小数
  void _jsGrossrate() {
    final sellprice = double.tryParse(_form['sellprice']?.toString() ?? '') ?? 0;
    final inprice = double.tryParse(_form['inprice']?.toString() ?? '') ?? 0;
    String grossrate;
    if (sellprice == 0) {
      grossrate = '100';
    } else if (inprice != 0) {
      grossrate = MathUtils.formatDecimal(2, (sellprice - inprice) / sellprice * 100);
    } else {
      grossrate = '0';
    }
    _form['grossrate'] = grossrate;
    if (!_resettingForm && _grossrateController.text != grossrate) {
      _grossrateController.text = grossrate;
    }
  }

  /// 失焦时格式化数字字段（对齐 Vue priceBlur）
  void _addBlurListener(FocusNode node, TextEditingController ctrl, int col, {double? clampMax}) {
    node.addListener(() {
      if (!node.hasFocus) {
        var value = double.tryParse(ctrl.text) ?? 0;
        if (clampMax != null && value > clampMax) value = clampMax;
        if (value < 0) value = 0;
        final formatted = MathUtils.formatDecimal(col, value);
        if (formatted != ctrl.text) ctrl.text = formatted;
      }
    });
  }

  void _onInpriceChanged() {
    final inprice = double.tryParse(_form['inprice']?.toString() ?? '') ?? 0;
    final sellprice = double.tryParse(_form['sellprice']?.toString() ?? '') ?? 0;
    if (inprice > 0 && sellprice > 0) {
      _grossrateController.text =
          MathUtils.formatDecimal(2, (sellprice - inprice) / sellprice * 100);
    }
  }

  void _onSellpriceChanged() {
    final inprice = double.tryParse(_form['inprice']?.toString() ?? '') ?? 0;
    final sellprice = double.tryParse(_form['sellprice']?.toString() ?? '') ?? 0;
    if (inprice > 0 && sellprice > 0) {
      _grossrateController.text =
          MathUtils.formatDecimal(2, (sellprice - inprice) / sellprice * 100);
    }
  }

  void _onGrossrateChanged() {
    final inprice = double.tryParse(_form['inprice']?.toString() ?? '') ?? 0;
    final rate = double.tryParse(_form['grossrate']?.toString() ?? '') ?? 0;
    if (inprice > 0 && rate > 0 && rate < 100) {
      _sellpriceController.text = MathUtils.formatDecimal(2, inprice / (1 - rate / 100));
    }
  }

  // =================== 表单辅助方法 ===================

  /// 更新 _form 整型字段
  void _setIntField(String key, int value) {
    setState(() => _form[key] = value);
  }

  // ── 便捷 getter（从 _form 读取，供 UI 使用）──
  List<Map<String, dynamic>> get _packList =>
      (_form['packpage'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  /// 根据 itemtype 返回 extendlist 在 _form 中对应的 key
  String get _extendlistKey {
    final itemtype = _form['itemtype'] ?? 1;
    switch (itemtype) {
      case 2:
        return 'productSize2';
      case 3:
        return 'productSize3';
      case 4:
        return 'productSize4';
      case 5:
        return 'productSize5';
      case 8:
        return 'productSize8';
      case 10:
        return 'productSize10';
      default:
        return 'productSize2'; // 其余暂定
    }
  }

  List<Map<String, dynamic>> get _extendlistList =>
      (_form[_extendlistKey] as List?)?.cast<Map<String, dynamic>>() ?? [];
  List<Map<String, dynamic>> get _sizedata =>
      (_form['sizedata'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  /// 价格字段为空时默认返回 '0'
  static String _pv(dynamic val) {
    final v = val?.toString().trim() ?? '';
    return v.isEmpty ? '0' : v;
  }

  /// 表单校验（与 Vue edit.vue handleEdit + save 一致）
  bool _validate() {
    if ((_form['name']?.toString().trim() ?? '').isEmpty) {
      Toast.show('请填写商品名称');
      return false;
    }
    if ((_form['typeid']?.toString() ?? '').isEmpty) {
      Toast.show('请选择商品分类');
      return false;
    }
    if ((_form['barcode']?.toString().trim() ?? '').isEmpty) {
      Toast.show('请输入商品条码');
      return false;
    }
    final barcode = _form['barcode']!.toString().trim();

    // 读取 loginParamResp 配置（对齐 Vue loginParamResp.value）
    Map<String, dynamic> loginCfg = {};
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        loginCfg = jsonDecode(cfgStr) as Map<String, dynamic>;
      }
    } catch (_) {}

    // EAN13 国标校验（Vue L858-864：notAutoGenerateBarcode==1 && pricetype==1）
    if (loginCfg['notAutoGenerateBarcode']?.toString() == '1' && (_form['pricetype'] ?? 1) == 1) {
      if (!_validateEAN13(barcode)) {
        Toast.show('商品条码不符合国标');
        return false;
      }
    }
    if ((_form['unit']?.toString().trim() ?? '').isEmpty) {
      Toast.show('请选择单位');
      return false;
    }
    if ((_form['supid']?.toString() ?? '').isEmpty) {
      Toast.show('请选择供应商');
      return false;
    }
    // 采购/批发/配送单位必填（对齐 Vue edit.vue L904-913）
    if ((_form['defcgunit']?.toString().trim() ?? '').isEmpty) {
      Toast.show('请选择采购单位');
      return false;
    } else if ((_form['defpfunit']?.toString().trim() ?? '').isEmpty) {
      Toast.show('请选择批发单位');
      return false;
    } else if ((_form['defpsunit']?.toString().trim() ?? '').isEmpty) {
      Toast.show('请选择配送单位');
      return false;
    }
    // 特殊商品类型明细数据校验（Vue L875-888）
    final itemtype = (_form['itemtype'] ?? 1) as int;
    if ([2, 3, 4, 5].contains(itemtype)) {
      const typeNames = {2: '拆分商品', 3: '组装商品', 4: '自动拆分商品', 5: '自动组装商品'};
      if (_extendlistList.isEmpty) {
        Toast.show('请添加${typeNames[itemtype]}明细数据');
        return false;
      }
    } else if (itemtype == 8) {
      if (_extendlistList.isEmpty) {
        Toast.show('请添加特价打包商品明细数据');
        return false;
      }
    } else if (itemtype == 10) {
      // 兑奖换购：至少选择一个兑换商品，且兑换数量必填、大于0（与 Vue/Web 端校验一致）
      final prizeList = ((_form['prizelist'] ?? <Map<String, dynamic>>[]) as List)
          .where((c) => (c['packageid']?.toString() ?? '').isNotEmpty)
          .toList();
      if (prizeList.isEmpty) {
        Toast.show('请至少选择一个兑换商品');
        return false;
      }
      final invalidPrize = prizeList.cast<Map<String, dynamic>>().firstWhere(
        (c) {
          final v = c['prizenum'];
          if (v == null || v.toString().isEmpty) return true;
          return (double.tryParse(v.toString()) ?? 0) <= 0;
        },
        orElse: () => <String, dynamic>{},
      );
      if (invalidPrize.isNotEmpty) {
        final prizenum = invalidPrize['prizenum'];
        if (prizenum == null || prizenum.toString().isEmpty) {
          Toast.show('请输入兑换数量');
        } else {
          Toast.show('兑换数量必须大于0');
        }
        return false;
      }
    } else if (itemtype == 9 && _packagSettingMode == 2) {
      // 包装配置：已关联商品的包装数量必须 >= 1（Vue edit.vue L915-922）
      final invalid = _packlinkpro.any((item) =>
          (item['packageid']?.toString() ?? '').isNotEmpty &&
          !((double.tryParse(item['packagenum']?.toString() ?? '') ?? 0) >= 1));
      if (invalid) {
        Toast.show('包装数量必须大于等于1');
        return false;
      }
    }
    // 零售价 < 进价校验（Vue L461-463）
    final sellprice = double.tryParse(_form['sellprice']?.toString() ?? '') ?? 0;
    final inprice = double.tryParse(_form['inprice']?.toString() ?? '') ?? 0;
    final mprice1 = double.tryParse(_form['mprice1']?.toString() ?? '') ?? 0;
    if (loginCfg['salePriceLessInpriceFlag']?.toString() != '1' &&
        sellprice < inprice &&
        inprice > 0) {
      Toast.show('商品参数不允许零售价小于进价，请检查');
      return false;
    }
    // 零售价 < 会员价1校验（Vue L464-466）
    if (loginCfg['allowRetailLessMember']?.toString() != '1' &&
        sellprice < mprice1 &&
        mprice1 > 0) {
      Toast.show('商品参数不允许零售价小于会员价1，请检查');
      return false;
    }
    // 条码重复校验：商品条码不能和包装条码、规格条码相同（Vue L467-476）
    if (barcode.isNotEmpty) {
      final dupPack = _packList.any((item) =>
          (item['sbarcode']?.toString().isNotEmpty ?? false) &&
          item['sbarcode']?.toString() == barcode);
      if (dupPack) {
        Toast.show('商品条码不能和包装条码相同');
        return false;
      }
      final dupSpec = _sizedata.any((item) =>
          (item['sbarcode']?.toString().isNotEmpty ?? false) &&
          item['sbarcode']?.toString() == barcode);
      if (dupSpec) {
        Toast.show('商品条码不能和规格条码相同');
        return false;
      }
    }
    return true;
  }

  /// EAN-13 校验码验证（对齐 Vue edit.vue validateEAN13）
  static bool _validateEAN13(String code) {
    if (code.length != 13 || !RegExp(r'^\d{13}$').hasMatch(code)) {
      return false;
    }
    final digits = code.split('').map(int.parse).toList();
    int sum = 0;
    for (int i = 0; i < 12; i += 2) {
      sum += digits[i];
    }
    for (int i = 1; i < 12; i += 2) {
      sum += digits[i] * 3;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return digits[12] == checkDigit;
  }

  /// 构建保存参数（与 Vue edit.vue handleBeforeParams 一致）
  /// 直接从 _form 读取，无需逐字段手动收集
  Map<String, dynamic> _buildParams() {
    final params = <String, dynamic>{
      if (_isEdit && _productData != null) ...Map<String, dynamic>.from(_productData!),
      'applynewflag': widget.applynewflag ?? 0,
    };
    // _form 数据覆盖（确保用户输入优先）
    params.addAll({
      'barcode': _form['barcode']?.toString().trim() ?? '',
      'productname': _form['name']?.toString().trim() ?? '',
      'name': _form['name']?.toString().trim() ?? '',
      'shortname': _form['shortname']?.toString().trim() ?? '',
      'helpcode': _form['helpcode']?.toString().trim() ?? '',
      'code': _form['code']?.toString().trim() ?? '',
      'imageurl': _imageurl,
      'codes': _codes,
      'typeid': _form['typeid']?.toString() ?? '',
      'typename': _form['typename']?.toString() ?? '',
      'typecode': _form['typecode']?.toString() ?? '',
      'size': _form['size']?.toString().trim() ?? '',
      'unit': _form['unit']?.toString().trim() ?? '',
      'brandname': _form['brandname']?.toString().trim() ?? '',
      'remark': _form['remark']?.toString().trim() ?? '',
      'itemtype': _form['itemtype'] ?? 1,
      'pricetype': _form['pricetype'] ?? 1,
      'selltype': _form['selltype'] ?? 1,
      'pstype': _form['pstype'] ?? 1,
      'memorytype': _form['memorytype'] ?? 1,
      'supid': _form['supid']?.toString() ?? '',
      'supname': _form['supname']?.toString() ?? '',
      'inprice': _pv(_form['inprice']),
      'sellprice': _pv(_form['sellprice']),
      'grossrate': _pv(_form['grossrate']),
      'mprice1': _pv(_form['mprice1']),
      'mprice2': _pv(_form['mprice2']),
      'mprice3': _pv(_form['mprice3']),
      'pfprice1': _pv(_form['pfprice1']),
      'pfprice2': _pv(_form['pfprice2']),
      'pfprice3': _pv(_form['pfprice3']),
      'psprice': _pv(_form['psprice']),
      'minsellprice': _pv(_form['minsellprice']),
      'maxstock': _form['maxstock']?.toString().trim() ?? '',
      'minstock': _form['minstock']?.toString().trim() ?? '',
      'initstorage': _form['initstorage']?.toString().trim() ?? '',
      'pointbase': _form['pointbase']?.toString().trim() ?? '',
      'point': _form['point']?.toString().trim() ?? '',
      'promotionprice': _pv(_form['promotionprice']),
      'promotionbegintime': _form['promotionbegintime']?.toString() ?? '',
      'promotionendtime': _form['promotionendtime']?.toString() ?? '',
      'intaxrate': _form['intaxrate']?.toString().trim() ?? '',
      'outtaxrate': _form['outtaxrate']?.toString().trim() ?? '',
      'custorderqtymin': _pv(_form['custorderqtymin']),
      'defcgunit': _form['defcgunit']?.toString().trim() ?? '',
      'defpfunit': _form['defpfunit']?.toString().trim() ?? '',
      'defpsunit': _form['defpsunit']?.toString().trim() ?? '',
      'stockflag': _form['stockflag'] ?? 1,
      'initstorageflag': _form['initstorageflag'] ?? 0,
      'pointflag': _form['pointflag'] ?? 1,
      'pointtype': _form['pointtype'] ?? 1,
      'validflag': _form['validflag'] ?? 0,
      'sellflag': _form['sellflag'] ?? 1,
      'changepriceflag': _form['changepriceflag'] ?? 0,
      'snflag': _form['snflag'] ?? 0,
      'freshflag': _form['freshflag'] ?? 0,
      'freepriceflag': _form['freepriceflag'] ?? 0,
      'nousecouponsflag': _form['nousecouponsflag'] ?? 0,
      'promotionflag': _form['promotionflag'] ?? 0,
      'home': _form['home']?.toString().trim() ?? '',
      'itemstatus': _form['itemstatus'] ?? 2,
      'deducttype': _form['deducttype'] ?? 1,
      'deductvalue': _form['deductvalue']?.toString().trim() ?? '',
      'joinrate': _form['joinrate']?.toString().trim() ?? '',
      'dscflag': _form['dscflag'] ?? 0,
      'presentflag': _form['presentflag'] ?? 0,
      'validday': _form['validday']?.toString().trim() ?? '',
      'locationcode': _form['locationcode']?.toString().trim() ?? '',
      'locationid': _form['locationid']?.toString().trim() ?? '',
      'packagenum': _form['packagenum'] ?? 1,
      'packpage': _form['packpage'] ?? <Map<String, dynamic>>[],
      // 包装配置（对齐 Vue handleBeforeParams：仅提交已关联商品的行）
      'packlinkpro': ((_form['packlinkpro'] ?? <Map<String, dynamic>>[]) as List)
          .where((e) => (e['packageid']?.toString() ?? '').isNotEmpty)
          .toList(),
      'extendlist': _form[_extendlistKey] ?? <Map<String, dynamic>>[],
      'sizedata': ((_form['sizedata'] ?? <Map<String, dynamic>>[]) as List)
          .where((e) => e['sbarcode']?.toString().isNotEmpty ?? false)
          .toList(),
      // 兑奖换购（itemtype=10）：明细字段 prizelist 仅该类型保留（与 Vue/Web 端一致）
      'prizelist': ((_form['prizelist'] ?? <Map<String, dynamic>>[]) as List)
          .where((e) => (e['packageid']?.toString() ?? '').isNotEmpty)
          .toList(),
    });
    // prizelist 仅在 itemtype==10 时提交
    if (_form['itemtype'] != 10) {
      params.remove('prizelist');
    }
    // extendlist 仅在 itemtype 2/3/4/5/8 时提交
    if (![2, 3, 4, 5, 8].contains(_form['itemtype'])) {
      params.remove('extendlist');
    }
    return params;
  }

  // =================== 提交保存 ===================
  void _submit() {
    if (!_checkPerm(_isEdit ? 'edit' : 'add')) return;
    if (!_validate()) return;
    final params = _buildParams();

    setState(() => _submitting = true);
    request(HttpApi.productAddInfo, params).then((_) {
      if (!mounted) return;
      Toast.show(_isEdit ? '保存成功' : '新增成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitting = false);
    });
  }

  /// 保存并继续（新增模式）
  void _submitAndContinue() {
    if (!_checkPerm('add')) return;
    if (!_validate()) return;
    final params = _buildParams();

    setState(() => _submitting = true);
    request(HttpApi.productAddInfo, params).then((_) {
      if (!mounted) return;
      Toast.show('新增成功');
      _resetForm(keepType: true, keepSupplier: true, keepUnit: true);
      // 对齐小程序保存并继续：重置后重新获取条码和自编码
      _autoGenBarcodeAndCode();
    }).whenComplete(() {
      if (mounted) setState(() => _submitting = false);
    });
  }

  /// 重置表单（直接操作 _form，controller 通过 listener 自动同步）
  void _resetForm({bool keepType = false, bool keepSupplier = false, bool keepUnit = false}) {
    _resettingForm = true;
    // 重置前先快照需要保留的字段（新增模式下 _productData 为 null，须从当前 _form 取值）
    final oldForm = _form;
    // 重置所有 controller（清空文本）
    for (final entry in _ctrlKeyMap.entries) {
      entry.key.clear();
    }
    setState(() {
      // 重置 _form 到默认值
      _form = Map<String, dynamic>.from(_formDefault);

      // 保留分类
      if (keepType) {
        _form['typeid'] = oldForm['typeid'] ?? '';
        _form['typename'] = oldForm['typename'] ?? '';
        _form['typecode'] = oldForm['typecode'] ?? '';
      }
      // 保留供应商
      if (keepSupplier) {
        _form['supid'] = oldForm['supid'] ?? '';
        _form['supname'] = oldForm['supname'] ?? '';
      }
      // 保留单位
      if (keepUnit) {
        _form['unit'] = oldForm['unit'] ?? '';
      }

      _imageurl = '';
      _codes = [
        {'code': ''}
      ];
      _form['packpage'] = <Map<String, dynamic>>[];
      _form['packlinkpro'] = [_packlinkproDefaultRow()];
      _form[_extendlistKey] = <Map<String, dynamic>>[];
      _form['prizelist'] = <Map<String, dynamic>>[];
      _form['sizedata'] = [Map<String, dynamic>.from(_formDefault)];
    });
    // 保留单位时回写 controller 显示值（前面统一 clear 会清空）
    if (keepUnit) {
      _unitController.text = _form['unit']?.toString() ?? '';
    }
    _syncTabController();

    _resettingForm = false;
  }

  /// 删除商品
  Future<void> _deleteProduct() async {
    if (_productData == null) return;
    if (!_checkPerm('delete')) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定删除该商品吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitting = true);
    request(HttpApi.productDelInfo, _productData!['productid']).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitting = false);
    });
  }

  // =================== Build ===================
  @override
  Widget build(BuildContext context) {
    // 键盘弹出时隐藏底部操作栏，避免遮挡输入框（MediaQuery 依赖自动响应键盘变化）
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? '编辑商品' : '新增商品',
          style:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF006EFF),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFF006EFF),
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
          ),
          tabs: [
            const Tab(text: '基础信息'),
            const Tab(text: '更多信息'),
            if (_showPackUnitTab)
              const Tab(text: '包装单位')
            else if (_showPackConfigTab)
              const Tab(text: '包装配置'),
          ],
        ),
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBasisTab(),
                _buildMoreTab(),
                if (_showPackUnitTab)
                  _buildPackageTab()
                else if (_showPackConfigTab)
                  _buildPackConfigTab(),
              ],
            ),
      bottomNavigationBar: keyboardVisible ? null : _buildBottomBar(),
    );
  }

  // =================== 底部操作栏 ===================
  Widget _buildBottomBar() {
    final status = widget.status?.toString();
    final isApplyMode = widget.applynewflag != null;

    // 已审核 / 已驳回状态不显示底部按钮
    if (isApplyMode && (status == '3' || status == '4')) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: _buildBottomButtons(status, isApplyMode),
      ),
    );
  }

  /// 根据状态构建底部按钮
  List<Widget> _buildBottomButtons(String? status, bool isApplyMode) {
    // 新品申请模式下的按钮逻辑
    if (isApplyMode && status != null) {
      switch (status) {
        case '1': // 待提交
          return [
            _buildBtn('删除', const Color(0xFFEF4444), false, () => _handleApplication(0)),
            const SizedBox(width: 12),
            _buildBtn('保存并提交', const Color(0xFF006EFF), false, () => _submitApplyNew()),
            const SizedBox(width: 12),
            _buildBtn('保存', const Color(0xFF006EFF), true, () => _submit()),
          ];
        case '2': // 待审核
          return [
            _buildBtn('撤回', const Color(0xFF6B7280), false, () => _handleApplication(1)),
            if (_isZd) ...[
              const SizedBox(width: 12),
              _buildBtn('驳回', const Color(0xFFEF4444), false, () => _handleApplication(4)),
              const SizedBox(width: 12),
              _buildBtn('审核', const Color(0xFF006EFF), true, () => _handleApplication(3)),
            ],
          ];
        default:
          return [_buildBtn('保存', const Color(0xFF006EFF), true, () => _submit())];
      }
    }

    // 普通模式按钮
    if (_isEdit) {
      return [
        _buildBtn('删除', const Color(0xFFEF4444), false, _deleteProduct),
        const SizedBox(width: 12),
        _buildBtn('保存', const Color(0xFF006EFF), true, _submit),
      ];
    } else {
      return [
        _buildBtn('保存并继续', const Color(0xFF006EFF), false, _submitAndContinue),
        const SizedBox(width: 12),
        _buildBtn('保存', const Color(0xFF006EFF), true, _submit),
      ];
    }
  }

  /// 构建按钮组件
  Widget _buildBtn(String label, Color color, bool filled, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: _submitting ? null : onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: filled ? color : Colors.white,
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: _submitting && filled
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: filled ? Colors.white : color))
              : Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: filled ? Colors.white : color)),
        ),
      ),
    );
  }

  /// 新品申请操作（删除/撤回/审核/驳回）
  Future<void> _handleApplication(int actionStatus) async {
    final productid = widget.productData?['productid']?.toString() ?? '';
    if (productid.isEmpty) return;

    // 权限校验：新品申请的特殊操作（撤回/审核/驳回），商品档案的删除
    if (_isApplyMode) {
      // 新品申请模式：直接映射到对应权限
      final permMap = <int, String>{
        0: '010307', // 删除
        1: '010308', // 撤回
        3: '010303', // 审核
        4: '010308', // 驳回（与撤回共用）
      };
      final menuId = permMap[actionStatus];
      final labelMap = <int, String>{
        0: '删除',
        1: '撤回',
        3: '审核',
        4: '驳回',
      };
      if (menuId != null && !PermissionUtils.checkPermission(menuId, showTip: false)) {
        Toast.show('你无权${labelMap[actionStatus]}新品申请，请在后台修改权限');
        return;
      }
    } else if (actionStatus == 0) {
      // 商品档案删除
      if (!_checkPerm('delete')) return;
    }

    String actionText = '';
    switch (actionStatus) {
      case 0:
        actionText = '删除';
        break;
      case 1:
        actionText = '撤回';
        break;
      case 3:
        actionText = '审核';
        break;
      case 4:
        actionText = '驳回';
        break;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认$actionText'),
        content: Text('确认$actionText选中数据？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _submitting = true);
    try {
      await request(
          HttpApi.applyNewProUpdate,
          {
            'status': actionStatus,
            'plist': [productid],
          },
          true);
      if (!mounted) return;
      Toast.show('$actionText成功');
      Navigator.pop(context, true);
    } catch (_) {
      // 拦截器已统一 Toast 提示
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 新品申请 - 保存并提交
  /// 流程与 Vue boss 项目对齐：
  /// 1. 先调用 productAddInfo 保存商品（带 applynewflag=1）
  /// 2. 保存成功后取 productid，调用 updateApplynewPro 将状态设为 2（待审核）
  Future<void> _submitApplyNew() async {
    if (!_checkPerm('submit')) return;
    if (!_validate()) return;
    final params = _buildParams();
    params['applynewflag'] = 1;

    setState(() => _submitting = true);
    try {
      // 第一步：保存商品
      final result = await request(HttpApi.productAddInfo, params, true);
      if (!mounted) return;

      // 第二步：提交申请（status=2 待审核）
      final productid = result['data']?['productid']?.toString() ?? '';
      if (productid.isNotEmpty) {
        await request(
          HttpApi.applyNewProUpdate,
          {
            'status': 2,
            'plist': [productid],
          },
          true,
        );
      }

      if (!mounted) return;
      Toast.show('保存并提交成功');
      Navigator.pop(context, true);
    } catch (_) {
      // 拦截器已统一 Toast 提示
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // =================== Tab 1：基础信息（对齐小程序 basis.vue 扁平排列）===================
  Widget _buildBasisTab() {
    const kDivider = Divider(height: 1, color: Color(0xFFE6E6E6));
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Column(
          children: [
            // 商品图片
            _buildImageUpload(),
            kDivider,
            // 所属分类
            SelectFieldItem(
              label: '所属分类',
              required: true,
              value: _form['typename']?.toString() ?? '',
              enabled: !_isReadOnly,
              labelWidth: 90,
              onTap: () async {
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (_) => const CategoryListPage(isSelect: true)),
                );
                if (result != null && mounted) {
                  setState(() {
                    _form['typeid'] = result['typeid']?.toString();
                    _form['typename'] = result['typename']?.toString();
                    _form['typecode'] =
                        result['code']?.toString() ?? result['typecode']?.toString();
                  });
                  // 读取 loginParamResp 配置
                  Map<String, dynamic> loginCfg = {};
                  try {
                    final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
                    if (cfgStr.isNotEmpty) {
                      loginCfg = jsonDecode(cfgStr) as Map<String, dynamic>;
                    }
                  } catch (_) {}
                  _autoGenerateBarcode(isSc: true);
                  final codeOnlyBarcodeRecord = loginCfg['codeOnlyBarcodeRecord'];
                  if (codeOnlyBarcodeRecord == '1') {
                    _getCode();
                  }
                }
              },
            ),
            kDivider,
            // 商品条码
            _buildBarcodeRow(),
            kDivider,
            // 自编码
            _buildCodeRow(),
            kDivider,
            // 商品名称
            _buildTextField(
                controller: _nameController,
                label: '商品名称',
                hint: '请输入商品名称',
                required: true,
                readOnly: _isReadOnly),
            kDivider,
            // 拼音简码
            _buildTextField(
                controller: _helpcodeController,
                label: '拼音简码',
                hint: '拼音助记码',
                readOnly: _isReadOnly),
            kDivider,
            // 计价方式
            _buildDropdown(
              label: '计价方式',
              value: (_form['pricetype'] ?? 1) as int,
              options: _priceTypeOptions,
              enabled: !_isReadOnly,
              onChanged: (v) {
                _setIntField('pricetype', v);
                // 对齐小程序 onChangePricetype：计重(2)/计份(3)且条码非5位（PLU码特征）时获取 PLU 码
                if ([2, 3].contains(v) && (_form['barcode']?.toString().trim() ?? '').length != 5) {
                  request(HttpApi.productGetPlu, <String, dynamic>{}).then((result) {
                    if (!mounted) return;
                    final plu = result['data']?.toString() ?? '';
                    if (plu.isNotEmpty) {
                      setState(() => _barcodeController.text = plu);
                    }
                  });
                }
                // 对齐小程序：计重(2)且无单位时默认 KG
                if (v == 2 && (_form['unit']?.toString().trim() ?? '').isEmpty) {
                  setState(() {
                    _form['unit'] = 'KG';
                    _unitController.text = 'KG';
                  });
                }
                // 对齐小程序：计重(2)/计份(3)时自动勾选生鲜，否则取消
                if (v == 2 || v == 3) {
                  _setIntField('freshflag', 1);
                } else {
                  _setIntField('freshflag', 0);
                }
              },
            ),
            kDivider,
            // 单位
            _buildUnitRow(),
            kDivider,
            // 规格
            _buildSizeRow(),
            kDivider,
            // 供应商
            SelectFieldItem(
              label: '供应商',
              required: true,
              value: _form['supname']?.toString() ?? '',
              enabled: !_isReadOnly,
              labelWidth: 90,
              onTap: () async {
                final result = await SelectSupplierPage.show(
                  context,
                  initialSelectedId: _form['supid']?.toString(),
                  extraParams: {'supselltypes': '', 'stopflag': ''},
                );
                if (result != null && mounted) {
                  setState(() {
                    _form['supid'] = result['supid']?.toString();
                    _form['supname'] = result['supname']?.toString();
                    // 经销方式跟随供应商（对齐小程序 onChangesup：selltype = supselltype）
                    final selltype = int.tryParse(result['selltype']?.toString() ?? '');
                    final joinrate = double.tryParse(result['joinrate']?.toString() ?? '');
                    if (selltype != null) {
                      _form['selltype'] = selltype;
                    }
                    if (joinrate != null) {
                      _form['joinrate'] = joinrate;
                      _joinrateController.text = joinrate.toString();
                    }
                  });
                }
              },
            ),
            kDivider,
            // 经销方式（只读，联营/扣率代销/租赁时显示联营比例）
            _buildSelltypeRow(),
            kDivider,
            // 采购单位（必填，对齐小程序 basis.vue defcgunit）
            _buildSelectRow(
              label: '采购单位',
              value: _form['defcgunit']?.toString() ?? '',
              enabled: !_isReadOnly,
              required: true,
              labelWidth: 90,
              onTap: () async {
                final result = await SelectUnitPage.show(
                  context,
                  title: '选择采购单位',
                  initialSelectedId: _form['defcgunit']?.toString(),
                );
                if (result != null && mounted) {
                  setState(() {
                    _form['defcgunit'] = result['name']?.toString() ?? '';
                  });
                }
              },
            ),
            kDivider,
            // 批发单位（必填，对齐小程序 basis.vue defpfunit）
            _buildSelectRow(
              label: '批发单位',
              value: _form['defpfunit']?.toString() ?? '',
              enabled: !_isReadOnly,
              required: true,
              labelWidth: 90,
              onTap: () async {
                final result = await SelectUnitPage.show(
                  context,
                  title: '选择批发单位',
                  initialSelectedId: _form['defpfunit']?.toString(),
                );
                if (result != null && mounted) {
                  setState(() {
                    _form['defpfunit'] = result['name']?.toString() ?? '';
                  });
                }
              },
            ),
            kDivider,
            // 配送单位（必填，对齐小程序 basis.vue defpsunit）
            _buildSelectRow(
              label: '配送单位',
              value: _form['defpsunit']?.toString() ?? '',
              enabled: !_isReadOnly,
              required: true,
              labelWidth: 90,
              onTap: () async {
                final result = await SelectUnitPage.show(
                  context,
                  title: '选择配送单位',
                  initialSelectedId: _form['defpsunit']?.toString(),
                );
                if (result != null && mounted) {
                  setState(() {
                    _form['defpsunit'] = result['name']?.toString() ?? '';
                  });
                }
              },
            ),
            kDivider,
            // 进货价
            _buildNumberField(
                controller: _inpriceController,
                label: '进货价',
                readOnly: _isReadOnly,
                focusNode: _inpriceFocusNode,
                onChanged: (_) => _onInpriceChanged()),
            kDivider,
            // 零售价
            _buildNumberField(
                controller: _sellpriceController,
                label: '零售价',
                readOnly: _isReadOnly,
                focusNode: _sellpriceFocusNode,
                onChanged: (_) => _onSellpriceChanged()),
            kDivider,
            // 毛利率(%)
            _buildNumberField(
                controller: _grossrateController,
                label: '毛利率(%)',
                hint: '自动计算',
                readOnly: _isReadOnly,
                focusNode: _grossrateFocusNode,
                onChanged: (_) => _onGrossrateChanged()),
            kDivider,
            // 配送价
            _buildNumberField(
                controller: _pspriceController,
                label: '配送价',
                readOnly: _isReadOnly,
                focusNode: _pspriceFocusNode),
            kDivider,
            // 最低售价
            _buildNumberField(
                controller: _minsellpriceController,
                label: '最低售价',
                readOnly: _isReadOnly,
                focusNode: _minsellpriceFocusNode),
            kDivider,
            // 更多价格（跳转到独立页面，对齐小程序 moreprice.vue）
            _buildSelectRow(
              label: '更多价格',
              value: ' ',
              enabled: !_isReadOnly,
              onTap: _navigateToMorePrice,
            ),
            kDivider,
            // 商品类型
            _buildItemTypeRow(),
            kDivider,
            // 物流方式
            _buildDropdown(
              label: '物流方式',
              value: (_form['pstype'] ?? 1) as int,
              options: _psTypeOptions,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('pstype', v),
            ),
            kDivider,
            // 存储方式
            _buildDropdown(
              label: '存储方式',
              value: (_form['memorytype'] ?? 1) as int,
              options: _memoryTypeOptions,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('memorytype', v),
            ),
            kDivider,
            // 期初库存（对齐 Vue：仅新增可录入，编辑/isOK=1 时禁用）
            _buildNumberField(
              controller: _initstorageController,
              label: '期初库存',
              hint: _isEdit ? '' : '请输入',
              readOnly: _isReadOnly || _isEdit || _form['isOK']?.toString() == '1',
              focusNode: _initstorageFocusNode,
            ),
            kDivider,
            // 促销价（对齐 Vue：仅展示，失焦保留2位小数）
            ColoredBox(
              color: const Color(0xFFF6F7FB),
              child: _buildNumberField(
                controller: _promotionpriceController,
                label: '促销价',
                hint: '',
                readOnly: true,
                focusNode: _promotionpriceFocusNode,
              ),
            ),
            kDivider,
            // 促销开始时间（对齐 Vue：仅展示）
            ColoredBox(
              color: const Color(0xFFF6F7FB),
              child: _buildTextField(
                controller: _promotionbegintimeController,
                label: '促销开始时间',
                hint: '',
                readOnly: true,
                labelWidth: 96,
              ),
            ),
            kDivider,
            // 促销结束时间（对齐 Vue：仅展示）
            ColoredBox(
              color: const Color(0xFFF6F7FB),
              child: _buildTextField(
                controller: _promotionendtimeController,
                label: '促销结束时间',
                hint: '',
                readOnly: true,
                labelWidth: 96,
              ),
            ),
            kDivider,
            // 备注
            _buildTextField(
              controller: _remarkController,
              label: '备注',
              hint: '请输入备注信息',
              maxLines: 3,
              readOnly: _isReadOnly,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // =================== 更多价格页面导航（对齐小程序 moreprice.vue）===================
  Future<void> _navigateToMorePrice() async {
    if (_isReadOnly) return;
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => MorePricePage(
          mprice1: _mprice1Controller.text,
          mprice2: _mprice2Controller.text,
          mprice3: _mprice3Controller.text,
          pfprice1: _pfprice1Controller.text,
          pfprice2: _pfprice2Controller.text,
          pfprice3: _pfprice3Controller.text,
          readOnly: _isReadOnly,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _mprice1Controller.text = MathUtils.formatDecimal(2, result['mprice1'] ?? '');
        _mprice2Controller.text = MathUtils.formatDecimal(2, result['mprice2'] ?? '');
        _mprice3Controller.text = MathUtils.formatDecimal(2, result['mprice3'] ?? '');
        _pfprice1Controller.text = MathUtils.formatDecimal(2, result['pfprice1'] ?? '');
        _pfprice2Controller.text = MathUtils.formatDecimal(2, result['pfprice2'] ?? '');
        _pfprice3Controller.text = MathUtils.formatDecimal(2, result['pfprice3'] ?? '');
      });
    }
  }

  // =================== Tab 2：更多信息（对齐小程序 more.vue）===================
  Widget _buildMoreTab() {
    const kDivider = Divider(height: 1, color: Color(0xFFE6E6E6));

    // 提成方式选项
    final deducttype = (_form['deducttype'] ?? 1) as int;
    // 商品状态选项
    final itemstatus = (_form['itemstatus'] ?? 1) as int;
    // 积分方式
    final pointtype = (_form['pointtype'] ?? 1) as int;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(10),
      child: _buildCard(
        child: Column(
          children: [
            // ── 产地 ──
            _buildTextField(
              controller: _homeController,
              label: '产地',
              hint: _isReadOnly ? '' : '请输入',
              readOnly: _isReadOnly,
            ),
            kDivider,

            // ── 积分方式（下拉）──
            _buildDropdown(
              label: '积分方式',
              value: pointtype,
              labelWidth: 85,
              options: const [
                {'label': '按金额', 'value': 1},
                {'label': '按数量', 'value': 2},
              ],
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('pointtype', v),
            ),
            kDivider,

            // ── 积分详情（内联：消费 X 元/个 积分 X 分）──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: SizedBox(
                height: 24,
                child: Row(
                  children: [
                    const SizedBox(
                        width: 85,
                        child: Text('积分方式',
                            style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF374151),
                                fontWeight: FontWeight.w500))),
                    const SizedBox(width: 8),
                    const Text('消费', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 52,
                      child: TextField(
                        controller: _pointbaseController,
                        focusNode: _pointbaseFocusNode,
                        readOnly: _isReadOnly,
                        enabled: !_isReadOnly,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        style: TextStyle(
                            fontSize: 14,
                            color: _isReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: const InputDecoration(
                          border:
                              OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(pointtype == 1 ? '元' : '个',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
                    const SizedBox(width: 8),
                    const Text('积分', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 52,
                      child: TextField(
                        controller: _pointController,
                        focusNode: _pointFocusNode,
                        readOnly: _isReadOnly,
                        enabled: !_isReadOnly,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        style: TextStyle(
                            fontSize: 14,
                            color: _isReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: const InputDecoration(
                          border:
                              OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('分', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                  ],
                ),
              ),
            ),
            kDivider,

            // ── 品牌（左侧输入框 + 右侧选择，对齐小程序 more.vue）──
            _buildBrandRow(),
            kDivider,

            // ── 商品状态 ──
            _buildDropdown(
              label: '商品状态',
              value: itemstatus,
              options: const [
                {'label': '正常', 'value': 1},
                {'label': '新品', 'value': 2},
                {'label': '冻结', 'value': 3},
                {'label': '停购', 'value': 4},
                {'label': '停用', 'value': 5},
              ],
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('itemstatus', v),
            ),
            kDivider,

            // ── 提成方式 ──
            _buildDropdown(
              label: '提成方式',
              value: deducttype,
              options: const [
                {'label': '无', 'value': 1},
                {'label': '按金额', 'value': 2},
                {'label': '按比例', 'value': 3},
              ],
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('deducttype', v),
            ),

            // ── 提成金额/提成比例（条件显示）──
            if (deducttype == 2) ...[
              kDivider,
              _buildSuffixNumberField(
                controller: _deductvalueController,
                label: '提成金额',
                suffix: '元',
                readOnly: _isReadOnly,
                focusNode: _deductvalueFocusNode,
              ),
            ] else if (deducttype == 3) ...[
              kDivider,
              _buildSuffixNumberField(
                controller: _deductvalueController,
                label: '提成比例',
                suffix: '%',
                readOnly: _isReadOnly,
                focusNode: _deductvalueFocusNode,
              ),
            ],

            kDivider,

            // ── 库存上限 ──
            _buildNumberField(
              controller: _maxstockController,
              label: '库存上限',
              readOnly: _isReadOnly,
              focusNode: _maxstockFocusNode,
            ),
            kDivider,

            // ── 库存下限 ──
            _buildNumberField(
              controller: _minstockController,
              label: '库存下限',
              readOnly: _isReadOnly,
              focusNode: _minstockFocusNode,
            ),
            kDivider,

            // ── 开关组 ──
            _buildRightSwitchField(
              label: '可促销',
              value: (_form['promotionflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('promotionflag', v ? 1 : 0),
            ),
            kDivider,
            _buildRightSwitchField(
              label: '单品改价/打折',
              value: (_form['changepriceflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('changepriceflag', v ? 1 : 0),
            ),
            kDivider,
            _buildRightSwitchField(
              label: '整单打折',
              value: (_form['dscflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('dscflag', v ? 1 : 0),
            ),
            kDivider,
            _buildRightSwitchField(
              label: '可赠送',
              value: (_form['presentflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('presentflag', v ? 1 : 0),
            ),
            kDivider,
            _buildRightSwitchField(
              label: '可销售',
              value: (_form['sellflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('sellflag', v ? 1 : 0),
            ),
            kDivider,

            _buildRightSwitchField(
              label: '管理库存',
              value: (_form['stockflag'] ?? 1) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('stockflag', v ? 1 : 0),
            ),
            kDivider,
            _buildRightSwitchField(
              label: '参与积分',
              value: (_form['pointflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('pointflag', v ? 1 : 0),
            ),

            kDivider,
            // 生鲜商品（对齐 Vue：仅 pricetype 为 2 或 3 时可操作）
            _buildRightSwitchField(
              label: '生鲜商品',
              value: (_form['freshflag'] ?? 0) == 1,
              enabled: !_isReadOnly && [2, 3].contains(_form['pricetype'] ?? 1),
              onChanged: (v) => _setIntField('freshflag', v ? 1 : 0),
            ),
            kDivider,
            // 不定价商品（对齐 Vue：勾选后零售价置0且取消必填）
            _buildRightSwitchField(
              label: '不定价商品',
              value: (_form['freepriceflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) {
                _setIntField('freepriceflag', v ? 1 : 0);
                if (v) _sellpriceController.text = '0';
              },
            ),
            kDivider,
            // 不参与优惠（对齐 Vue basis.vue query.nousecouponsflag，默认 0）
            _buildRightSwitchField(
              label: '不参与优惠',
              value: (_form['nousecouponsflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('nousecouponsflag', v ? 1 : 0),
            ),
            kDivider,
            _buildRightSwitchField(
              label: '管理保质期',
              value: (_form['validflag'] ?? 0) == 1,
              enabled: !_isReadOnly,
              onChanged: (v) => _setIntField('validflag', v ? 1 : 0),
            ),

            // ── 保质天数（条件显示：validflag == 1）──
            if ((_form['validflag'] ?? 0) == 1) ...[
              kDivider,
              _buildNumberField(
                controller: _validdayController,
                label: '保质天数',
                readOnly: _isReadOnly,
              ),
            ],
            kDivider,

            // ── 货架编号（带选择箭头）──
            _buildSelectRow(
              label: '货架编号',
              value: _form['locationcode']?.toString() ?? '',
              enabled: !_isReadOnly,
              labelWidth: 90,
              onTap: () async {
                final result = await SelectLocationPage.show(
                  context,
                  initialSelectedId: _form['locationid']?.toString(),
                );
                if (result != null && mounted) {
                  setState(() {
                    _form['locationcode'] = result['locationcode']?.toString() ?? '';
                    _form['locationid'] = result['locationid']?.toString() ?? '';
                  });
                }
              },
            ),
            kDivider,

            // ── 进项税率 ──
            _buildSuffixNumberField(
              controller: _intaxrateController,
              label: '进项税率',
              suffix: '%',
              readOnly: _isReadOnly,
              focusNode: _intaxrateFocusNode,
            ),
            kDivider,

            // ── 销项税率 ──
            _buildSuffixNumberField(
              controller: _outtaxrateController,
              label: '销项税率',
              suffix: '%',
              readOnly: _isReadOnly,
              focusNode: _outtaxrateFocusNode,
            ),
            kDivider,

            // ── 批发起订量（对齐小程序 more.vue custorderqtymin）──
            _buildNumberField(
              controller: _custorderqtyminController,
              label: '批发起订量',
              hint: '请输入',
              readOnly: _isReadOnly,
            ),
          ],
        ),
      ),
    );
  }

  // =================== Tab 3：包装单位 ===================
  Widget _buildPackageTab() {
    // 拆分/组装类商品不显示包装单位
    final itemtype = _form['itemtype'] ?? 1;
    if (itemtype == 2 || itemtype == 3 || itemtype == 4 || itemtype == 5) {
      return const Center(
        child: Text('拆分/组装类商品不支持包装单位', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
      );
    }

    return Column(
      children: [
        // 列表
        Expanded(
          child: _packList.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFD1D5DB)),
                      SizedBox(height: 12),
                      Text('暂无包装单位', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _packList.length,
                  itemBuilder: (context, index) {
                    final pack = _packList[index];
                    return RepaintBoundary(
                      child: _PackageItem(
                        productName: _form['name']?.toString() ?? '',
                        pack: pack,
                        index: index,
                        readOnly: _isReadOnly,
                        onTap: _isReadOnly ? null : () => _editPackage(index),
                        onDelete: () {
                          setState(() {
                            final list = List<Map<String, dynamic>>.from(_packList);
                            list.removeAt(index);
                            _form['packpage'] = list;
                          });
                        },
                      ),
                    );
                  },
                ),
        ),
        // 新增按钮（底部，虚线边框）
        if (!_isReadOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
            child: GestureDetector(
              onTap: _addPackage,
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: const Color(0xFF006EFF),
                  dashLength: 6,
                  gapLength: 4,
                  borderRadius: 8,
                ),
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 18, color: Color(0xFF006EFF)),
                      SizedBox(width: 4),
                      Text('新增包装单位', style: TextStyle(fontSize: 14, color: Color(0xFF006EFF))),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 新增包装单位（跳转新页面）
  Future<void> _addPackage() async {
    if (!_checkPerm('add')) return;
    final existingBarcodes =
        _packList.map((p) => p['sbarcode']?.toString() ?? '').where((b) => b.isNotEmpty).toList();
    final specBarcodes =
        _sizedata.map((s) => s['sbarcode']?.toString() ?? '').where((b) => b.isNotEmpty).toList();
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPackagePage(
          existingBarcodes: existingBarcodes,
          mainBarcode: _form['barcode']?.toString().trim() ?? '',
          specBarcodes: specBarcodes,
          basicUnit: _form['unit']?.toString() ?? '',
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final list = List<Map<String, dynamic>>.from(_packList);
        list.add(result);
        _form['packpage'] = list;
      });
    }
  }

  /// 编辑包装单位（跳转新页面）
  Future<void> _editPackage(int index) async {
    if (index >= _packList.length) return;
    if (!_checkPerm('edit')) return;
    final existingBarcodes = _packList
        .asMap()
        .entries
        .where((e) => e.key != index)
        .map((e) => e.value['sbarcode']?.toString() ?? '')
        .where((b) => b.isNotEmpty)
        .toList();
    final specBarcodes =
        _sizedata.map((s) => s['sbarcode']?.toString() ?? '').where((b) => b.isNotEmpty).toList();
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPackagePage(
          editData: _packList[index],
          existingBarcodes: existingBarcodes,
          mainBarcode: _form['barcode']?.toString().trim() ?? '',
          specBarcodes: specBarcodes,
          basicUnit: _form['unit']?.toString() ?? '',
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final list = List<Map<String, dynamic>>.from(_packList);
        // 删除标记：移除该项
        if (result['_delete'] == true) {
          list.removeAt(index);
        } else {
          list[index] = result;
        }
        _form['packpage'] = list;
      });
    }
  }

  /// 跳转商品明细页面（根据 itemtype 跳转不同页面）
  /// itemtype 2/3/4/5 → CommodityPackPage（拆分/组装成份管理）
  /// itemtype 8     → CommodityBundlePage（特价打包商品管理）
  /// itemtype 10    → CommodityPrizePage（兑奖换购管理）
  Future<void> _goToPackPage() async {
    final itemtype = _form['itemtype'] ?? 1;
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (itemtype == 8) {
            return CommodityBundlePage(
              items: _extendlistList,
              productName: _form['name']?.toString().trim() ?? '',
            );
          }
          if (itemtype == 10) {
            return CommodityPrizePage(
              prizelist: ((_form['prizelist'] ?? <Map<String, dynamic>>[]) as List)
                  .cast<Map<String, dynamic>>(),
              productName: _form['name']?.toString().trim() ?? '',
              productSize: _form['size']?.toString().trim() ?? '',
              productBarcode: _form['barcode']?.toString().trim() ?? '',
              productSellprice: _form['sellprice']?.toString() ?? '',
              readOnly: _isReadOnly,
            );
          }
          return CommodityPackPage(
            items: _extendlistList,
            productName: _form['name']?.toString().trim() ?? '',
            productId: _form['productid']?.toString() ?? '',
            itemtype: itemtype.toString(),
          );
        },
      ),
    );
    if (result != null && mounted) {
      if (itemtype == 10) {
        setState(() => _form['prizelist'] = result);
      } else {
        setState(() => _form[_extendlistKey] = result);
      }
    }
  }

  void _showPackageDialog({int? editIndex}) {
    final packnameCtrl = TextEditingController();
    final packbarcodeCtrl = TextEditingController();
    final packrateCtrl = TextEditingController();
    final packpriceCtrl = TextEditingController();

    if (editIndex != null && editIndex < _packList.length) {
      final pack = _packList[editIndex];
      packnameCtrl.text = pack['packname']?.toString() ?? '';
      packbarcodeCtrl.text = pack['packbarcode']?.toString() ?? '';
      packrateCtrl.text = pack['packrate']?.toString() ?? '';
      packpriceCtrl.text = pack['packprice']?.toString() ?? '';
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AnimatedPadding(
        // 键盘避让：弹窗整体上移，避免输入框被键盘遮挡
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AlertDialog(
          title: Text(editIndex != null ? '编辑包装单位' : '新增包装单位'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: packnameCtrl,
                  decoration: const InputDecoration(
                    labelText: '包装名称',
                    hintText: '如：箱、件',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: packbarcodeCtrl,
                  decoration: const InputDecoration(labelText: '包装条码'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: packrateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '包装比率', hintText: '如：12'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: packpriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '包装价格'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                if (packnameCtrl.text.trim().isEmpty) {
                  Toast.show('请输入包装名称');
                  return;
                }

                final inputBarcode = packbarcodeCtrl.text.trim();

                // 校验包装条码是否与其他包装条码重复（排除自身）
                for (int i = 0; i < _packList.length; i++) {
                  if (i == editIndex) continue;
                  if (_packList[i]['packbarcode']?.toString() == inputBarcode &&
                      inputBarcode.isNotEmpty) {
                    Toast.show('包装条码已存在');
                    return;
                  }
                }

                // 校验包装条码是否与规格条码冲突
                for (final spec in _sizedata) {
                  if (spec['sbarcode']?.toString() == inputBarcode && inputBarcode.isNotEmpty) {
                    Toast.show('包装条码不能和规格条码相同');
                    return;
                  }
                }

                // 校验包装条码是否与商品主条码冲突
                final mainBarcode = _form['barcode']?.toString().trim() ?? '';
                if (inputBarcode == mainBarcode && inputBarcode.isNotEmpty) {
                  Toast.show('包装条码不能和商品条码相同');
                  return;
                }

                setState(() {
                  final newPack = {
                    'packname': packnameCtrl.text.trim(),
                    'packbarcode': packbarcodeCtrl.text.trim(),
                    'packrate': packrateCtrl.text.trim(),
                    'packprice': packpriceCtrl.text.trim(),
                  };
                  if (editIndex != null && editIndex < _packList.length) {
                    final list = List<Map<String, dynamic>>.from(_packList);
                    list[editIndex] = {...list[editIndex], ...newPack};
                    _form['packpage'] = list;
                  } else {
                    final list = List<Map<String, dynamic>>.from(_packList);
                    list.add(newPack);
                    _form['packpage'] = list;
                  }
                });
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  // =================== 包装配置（itemtype=9，对齐 Vue component/packconfig.vue） ===================

  /// 包装配置默认行（packageid 赋值为关联子商品的 productid）
  static Map<String, dynamic> _packlinkproDefaultRow() => {
        'itemtype': '',
        'barcode': '',
        'name': '',
        'unit': '',
        'size': '',
        'code': '',
        'inprice': '',
        'sellprice': '',
        'mprice1': '',
        'pfprice1': '',
        'packageid': '',
        'packagenum': '',
        'defpackageflag': 0,
      };

  List<Map<String, dynamic>> get _packlinkpro {
    final v = _form['packlinkpro'];
    return v is List ? v.cast<Map<String, dynamic>>() : [];
  }

  /// 当前商品 id（包装配置不能关联自身）
  String get _currentProductid =>
      _form['productid']?.toString() ??
      _productData?['productid']?.toString() ??
      widget.productData?['productid']?.toString() ??
      '';

  /// 包装配置 Tab（关联子商品行，无新增/删除按钮，对齐小程序单行交互）
  Widget _buildPackConfigTab() {
    if (_packlinkpro.isEmpty) {
      _form['packlinkpro'] = [_packlinkproDefaultRow()];
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
      cacheExtent: 800,
      itemCount: _packlinkpro.length,
      itemBuilder: (_, index) {
        final row = _packlinkpro[index];
        return RepaintBoundary(
          child: _PackConfigItem(
            key: ValueKey('pack_${index}_${row['packageid'] ?? ''}_${row['barcode'] ?? ''}'),
            row: row,
            index: index,
            readOnly: _isReadOnly,
            onBarcodeCommit: _handlePackBarcodeCommit,
            onDefFlagChanged: _changePackDefFlag,
            onSelectProduct: _selectPacklinkProduct,
            onScan: () => _scanPacklinkBarcode(index),
          ),
        );
      },
    );
  }

  /// 条码失焦/扫码后：按条码匹配关联商品并填充行（对齐 handleBarCodeBlur）
  Future<void> _handlePackBarcodeCommit(int index, String barcode) async {
    if (_isReadOnly) return;
    if (index < 0 || index >= _packlinkpro.length) return;
    _packlinkpro[index]['barcode'] = barcode;
    try {
      final res = await request(HttpApi.productFindBarcodeCode, {'barcode': barcode});
      if (!mounted) return;
      final raw = res['data'];
      final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final productid = data['productid']?.toString() ?? '';
      if (productid.isEmpty) {
        Toast.show('无效条码');
        _resetPacklinkRow(index);
        return;
      }
      if (productid == _currentProductid) {
        Toast.show('不能关联当前商品');
        _resetPacklinkRow(index);
        return;
      }
      if ((int.tryParse(data['itemtype']?.toString() ?? '') ?? 0) != 1) {
        Toast.show('只有普通商品才能关联');
        _resetPacklinkRow(index);
        return;
      }
      final dup = _packlinkpro
          .asMap()
          .entries
          .any((e) => e.key != index && (e.value['packageid']?.toString() ?? '') == productid);
      if (dup) {
        Toast.show('重复商品,已过滤');
        _resetPacklinkRow(index);
        return;
      }
      _addPacklinkRowData(data, index);
    } catch (_) {}
  }

  /// 重置包装配置行为默认空行
  void _resetPacklinkRow(int index) {
    setState(() {
      final list = List<Map<String, dynamic>>.from(_packlinkpro);
      if (index >= 0 && index < list.length) list[index] = _packlinkproDefaultRow();
      _form['packlinkpro'] = list;
    });
  }

  /// 填充关联商品到包装配置行（对齐 addRowData：packageid = 关联商品 productid）
  void _addPacklinkRowData(Map<String, dynamic> data, int index) {
    final old = (index > -1 && index < _packlinkpro.length) ? _packlinkpro[index] : null;
    final row = _packlinkproDefaultRow();
    for (final key in const [
      'itemtype',
      'barcode',
      'name',
      'unit',
      'size',
      'code',
      'inprice',
      'sellprice',
      'mprice1',
      'pfprice1'
    ]) {
      if (data[key] != null) row[key] = data[key];
    }
    row['packageid'] = data['productid']?.toString() ?? '';
    // 保留原行有效包装数量，否则默认 1（对齐小程序 addRowData）
    final oldNum = double.tryParse(old?['packagenum']?.toString() ?? '') ?? 0;
    row['packagenum'] = oldNum > 0 ? old!['packagenum'] : 1;
    row['defpackageflag'] = old?['defpackageflag'] ?? 0;
    setState(() {
      final list = List<Map<String, dynamic>>.from(_packlinkpro);
      if (index > -1 && index < list.length) {
        list[index] = row;
      } else {
        list.add(row);
      }
      _form['packlinkpro'] = list;
    });
  }

  /// “+”选择关联商品（单选、仅普通商品；替换首行，对齐 onSelectPacklinkpro）
  Future<void> _selectPacklinkProduct() async {
    if (_isReadOnly) return;
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => const SelectProductPage(
          mergData: {'itemtype': 1, 'baseproflag': 1},
        ),
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    final data = result.first;
    final productid = data['productid']?.toString() ?? '';
    if (productid.isEmpty) return;
    if (productid == _currentProductid) {
      Toast.show('不能关联当前商品');
      return;
    }
    if ((int.tryParse(data['itemtype']?.toString() ?? '') ?? 0) != 1) {
      Toast.show('只有普通商品才能关联');
      return;
    }
    _addPacklinkRowData(data, 0);
  }

  /// 扫码关联商品条码（对齐 scanFn）
  Future<void> _scanPacklinkBarcode(int index) async {
    if (_isReadOnly) return;
    final code = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const QrCodeScannerPage()));
    if (!mounted) return;
    final barcode = (code ?? '').trim();
    if (barcode.isEmpty) return;
    _handlePackBarcodeCommit(index, barcode);
  }

  /// 默认单位开关（对齐 changeSwitch：开启时其他行 defpackageflag 清零）
  void _changePackDefFlag(int index, bool value) {
    setState(() {
      final list = List<Map<String, dynamic>>.from(_packlinkpro);
      if (index >= 0 && index < list.length) {
        list[index]['defpackageflag'] = value ? 1 : 0;
        if (value) {
          for (var i = 0; i < list.length; i++) {
            if (i != index) list[i]['defpackageflag'] = 0;
          }
        }
      }
      _form['packlinkpro'] = list;
    });
  }

  // =================== 新增业务组件 ===================

  /// 商品图片上传
  Widget _buildImageUpload() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 90,
            child: Text('商品图片',
                style:
                    TextStyle(fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          if (_imageurl.isNotEmpty) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    '${Constant.imageBaseUrl}/$_imageurl',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.broken_image, size: 20, color: Color(0xFFD1D5DB)),
                    ),
                  ),
                ),
                if (!_isReadOnly)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: GestureDetector(
                      onTap: () => setState(() => _imageurl = ''),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration:
                            const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ] else if (!_isReadOnly) ...[
            GestureDetector(
              onTap: _uploading ? null : _pickAndUploadImage,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFC5CAE9)),
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFFF0F2FA),
                ),
                child: _uploading
                    ? const Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF006EFF))))
                    : const Icon(Icons.add, size: 20, color: Color(0xFFC0C4CC)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 选择并上传图片
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null || !mounted) return;
    setState(() => _uploading = true);
    final bytes = await image.readAsBytes();
    final base64Str = 'data:image/png;base64,${base64Encode(bytes)}';
    request(HttpApi.fileUpload, {'imageBase64': base64Str}).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final imgurl = (data is Map<String, dynamic>)
          ? (data['imgurl']?.toString() ?? '')
          : (data?.toString() ?? '');
      if (imgurl.isNotEmpty) {
        setState(() => _imageurl = imgurl);
      }
    }).whenComplete(() {
      if (mounted) setState(() => _uploading = false);
    });
  }

  /// 商品条码行（输入 + 生成条码 + 扫描）
  Widget _buildBarcodeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('商品条码',
                      style: TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                  Positioned(
                    left: -10,
                    top: 0,
                    child: Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _barcodeController,
                keyboardType: TextInputType.number,
                readOnly: _isReadOnly,
                enabled: !_isReadOnly,
                style: TextStyle(
                    fontSize: 14,
                    color: _isReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                decoration: const InputDecoration(
                  hintText: '请输入',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (!_isReadOnly) ...[
              Container(width: 1, height: 20, color: const Color(0xFFE5E7EB)),
              const SizedBox(width: 6),
              // 生成条码
              GestureDetector(
                onTap: _generateBarcode,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text('生成\n条码',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 8, color: Color(0xFF006EFF), height: 1.2)),
                ),
              ),
              const SizedBox(width: 6),
              // 扫描
              GestureDetector(
                onTap: _scanBarcode,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.qr_code_scanner, size: 16, color: Color(0xFF006EFF)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 自编码行（输入 + 生成条码 + 一品多码）
  Widget _buildCodeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text('自编码',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                readOnly: _isReadOnly,
                enabled: !_isReadOnly,
                style: TextStyle(
                    fontSize: 14,
                    color: _isReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                decoration: const InputDecoration(
                  hintText: '请输入',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (!_isReadOnly) ...[
              Container(width: 1, height: 20, color: const Color(0xFFE5E7EB)),
              const SizedBox(width: 6),
              // 生成编码（对齐小程序 getCode）
              GestureDetector(
                onTap: _getCode,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text('生成\n条码',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 8, color: Color(0xFF006EFF), height: 1.2)),
                ),
              ),
              const SizedBox(width: 6),
              // 一品多码
              GestureDetector(
                onTap: _showMultiCodeDialog,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text('一品\n多码',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 8, color: Color(0xFF006EFF), height: 1.2)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 单位选择行（左侧输入框 + 右侧选择按钮，对齐小程序）
  Widget _buildUnitRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('单位',
                      style: TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                  Positioned(
                    left: -10,
                    top: 0,
                    child: Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _unitController,
                readOnly: _isReadOnly,
                enabled: !_isReadOnly,
                style: TextStyle(
                    fontSize: 14,
                    color: _isReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                decoration: const InputDecoration(
                  hintText: '请输入',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (!_isReadOnly) ...[
              Container(width: 1, height: 20, color: const Color(0xFFE5E7EB)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () async {
                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(builder: (_) => const SelectUnitPage()),
                  );
                  if (result != null && mounted) {
                    setState(() {
                      _unitController.text = result['name']?.toString() ?? '';
                    });
                  }
                },
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text('选择', style: TextStyle(fontSize: 11, color: Color(0xFF006EFF))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 品牌行（左侧输入框 + 右侧选择品牌按钮，对齐小程序 more.vue）
  Widget _buildBrandRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text('品牌',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _brandnameController,
                readOnly: _isReadOnly,
                enabled: !_isReadOnly,
                style: TextStyle(
                    fontSize: 14,
                    color: _isReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                decoration: InputDecoration(
                  hintText: _isReadOnly ? '' : '请输入',
                  hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (!_isReadOnly) ...[
              Container(width: 1, height: 20, color: const Color(0xFFE5E7EB)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () async {
                  final result = await SelectBrandPage.show(
                    context,
                    initialSelectedId: _form['brandname']?.toString(),
                    showAll: false,
                  );
                  if (result != null && mounted) {
                    setState(() {
                      // 对齐 Vue selectbrandFn：query.brandname = e.name（取纯品牌名）
                      _brandnameController.text = result['rawName']?.toString() ?? '';
                    });
                  }
                },
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text('选择', style: TextStyle(fontSize: 11, color: Color(0xFF006EFF))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 规格行（输入 + 多规格按钮）
  Widget _buildSizeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text('规格',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _sizeController,
                readOnly: _isReadOnly,
                enabled: !_isReadOnly,
                style: TextStyle(
                    fontSize: 14,
                    color: _isReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                decoration: const InputDecoration(
                  hintText: '请输入',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (!_isReadOnly) ...[
              Container(width: 1, height: 20, color: const Color(0xFFE5E7EB)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _goToSpecPage,
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child:
                      const Text('多规格', style: TextStyle(fontSize: 11, color: Color(0xFF006EFF))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 商品类型（下拉 + 跳转）
  Widget _buildItemTypeRow() {
    final itemtype = _form['itemtype'] ?? 1;
    final selectedLabel = _itemTypeOptionList.firstWhere((option) => option['value'] == itemtype,
        orElse: () => _itemTypeOptionList.first)['label'] as String;
    // 是否显示右侧管理链接（拆分/组装/特价打包/兑奖换购类商品）
    final showLink = [2, 3, 4, 5, 8, 10].contains(itemtype);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text('商品类型',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            // 点击文字 + 箭头打开选择弹窗
            Expanded(
              child: GestureDetector(
                onTap: _isReadOnly
                    ? null
                    : () => _showDropdownDialog(selectedLabel, itemtype as int, _itemTypeOptionList,
                            (value) {
                          setState(() => _form['itemtype'] = value);
                          // 商品类型切换后 Tab 数量可能变化（itemtype=9 → 包装配置 Tab）
                          _syncTabController();
                        }),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(selectedLabel,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
                  ],
                ),
              ),
            ),
            // 右侧管理链接：itemtype 2/3/4/5 → 商品明细，itemtype 8 → 特价打包商品，itemtype 10 → 兑奖换购
            if (showLink && !_isReadOnly) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _goToPackPage,
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  child: Text(
                      itemtype == 8
                          ? '特价打包商品'
                          : itemtype == 10
                              ? '兑奖换购'
                              : selectedLabel,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF006EFF))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  // =================== 新增业务方法 ===================

  /// 自动生成条码和自编码（新增进入 / 保存并继续重置后调用，对齐小程序逻辑）
  /// isSc 模式下条码为空才重新生成；重置后 _form['barcode'] 已清空，会正常生成新值
  void _autoGenBarcodeAndCode() {
    _autoGenerateBarcode(isSc: true);
    _generateCode();
    // 读取 loginParamResp 配置，判断是否仅条码录入
    Map<String, dynamic> loginCfg = {};
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        loginCfg = jsonDecode(cfgStr) as Map<String, dynamic>;
      }
    } catch (_) {}
    if (loginCfg['codeOnlyBarcodeRecord'] == '1') {
      _getCode();
    }
  }

  /// 生成商品条码（手动点击）
  void _generateBarcode() {
    _autoGenerateBarcode(isSc: false);
  }

  /// 自动生成条码
  /// 与小程序 edit.vue getTypeOrSuppBarcode(params, isSc) 完全一致：
  ///   校验：typeid 或 supid 任一存在即可（Vue: !query.value.typeid && !params?.supid）
  ///   端点切换：notAutoGenerateBarcode==1 时使用 barCodeGeneration
  ///   isSc=true（自动调用）：已有条码则跳过
  void _autoGenerateBarcode({required bool isSc}) {
    if ((_form['typeid']?.toString() ?? '').isEmpty && (_form['supid']?.toString() ?? '').isEmpty) {
      Toast.show('请先选择商品分类');
      return;
    }

    final data = <String, dynamic>{
      'type': 1,
      'value': _form['typecode']?.toString() ?? '',
    };
    var url = HttpApi.productGetTypeOrSuppBarcode;

    // 读取 loginParamResp 配置（对齐 Vue loginParamResp.value）
    Map<String, dynamic> loginCfg = {};
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        loginCfg = jsonDecode(cfgStr) as Map<String, dynamic>;
      }
    } catch (_) {}

    // 切换到 barCodeGeneration 端点（Vue: loginParamResp.value?.notAutoGenerateBarcode==1）
    if (loginCfg['notAutoGenerateBarcode']?.toString() == '1') {
      data['typeid'] = _form['typeid']?.toString() ?? '';
      data['code'] = _form['code']?.toString() ?? '';
      url = HttpApi.productBarCodeGeneration;
    }

    // 已有条码且是自动调用时跳过（Vue: if (query.value.barcode && isSc) return;）
    if (isSc && (_form['barcode']?.toString().trim() ?? '').isNotEmpty) {
      return;
    }

    request(url, data).then((result) {
      if (!mounted) return;
      final barcode = result['data']?.toString() ?? '';
      if (barcode.isNotEmpty) {
        setState(() => _barcodeController.text = barcode);
      }
    });
  }

  /// 扫描条码
  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code != null && code.isNotEmpty && mounted) {
      setState(() => _barcodeController.text = code);
    }
  }

  /// 生成自编码
  /// 对齐 Vue edit.vue getTypeCode(params, isSc)：
  ///   pricetype 为 2/3 时走 changePriceType 逻辑（getPlu + 默认单位）
  ///   其他走 getTypeOfCode，params = { type, value, typeid, code }
  void _generateCode() {
    if ((_form['typeid']?.toString() ?? '').isEmpty) {
      Toast.show('请先选择商品分类');
      return;
    }
    final pricetype = (_form['pricetype'] ?? 1) as int;

    // 对齐 Vue changePriceType：pricetype 2/3 时获取 PLU 码
    if ([2, 3].contains(pricetype)) {
      final productid = _form['productid']?.toString() ?? '';
      final barcode = _form['barcode']?.toString().trim() ?? '';
      if (productid.isEmpty && barcode.length != 5) {
        request(HttpApi.productGetPlu, <String, dynamic>{}).then((result) {
          if (!mounted) return;
          final plu = result['data']?.toString() ?? '';
          if (plu.isNotEmpty) {
            setState(() => _barcodeController.text = plu);
          }
        });
      }
      // pricetype == 2 且无单位时默认 KG（对齐 Vue L196）
      if (pricetype == 2 && (_form['unit']?.toString().trim() ?? '').isEmpty) {
        setState(() {
          _form['unit'] = 'KG';
          _unitController.text = 'KG';
        });
      }
      return;
    }

    // 正常计价方式：调用 getTypeOfCode（对齐 Vue L659-669）
    request(HttpApi.productGetTypeOfCode, {
      'type': 1,
      'value': _form['typecode']?.toString() ?? '',
      'typeid': _form['typeid']?.toString() ?? '',
      'code': _form['code']?.toString() ?? '',
    }).then((result) {
      if (!mounted) return;
      final code = result['data']?.toString() ?? '';
      if (code.isNotEmpty) {
        setState(() => _codeController.text = code);
      }
    });
  }

  /// 自编码行 — 生成编码（对齐小程序 getCode）
  /// 调用 bi/type/getCode，params = typecode（字符串）
  void _getCode() {
    if ((_form['typeid']?.toString() ?? '').isEmpty) {
      Toast.show('请先选择商品分类');
      return;
    }
    final typecode = _form['typecode']?.toString() ?? '';

    request(
            HttpApi.getTypeOfCode,
            {
              'value': typecode,
              'type': 1,
            },
            false,
            false)
        .then((result) {
      if (!mounted) return;
      final code = result['data']?.toString() ?? '';
      if (code.isNotEmpty) {
        setState(() => _codeController.text = code);
      }
    });
  }

  /// 一品多码弹窗（表格布局：序号/条码/操作，样式对齐收银流水 DataTable2）
  void _showMultiCodeDialog() {
    if (_codes.isEmpty)
      _codes = [
        {'code': ''}
      ];
    final controllers = <TextEditingController>[];
    for (final item in _codes) {
      controllers.add(TextEditingController(text: item['code']?.toString() ?? ''));
    }

    // 表格视觉常量（对齐 cash_flow_page：表头 #E8F0FE / 文字 #374151 / 单元格 #333333 / 分隔线 #E1E9F3）
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // 键盘避让：sheet 内部 MediaQuery 的 viewInsets 已被移除，
          // 改用 View 读取真实键盘高度（View 不受 removeViewInsets 影响）
          final keyboardHeight = View.of(ctx).viewInsets.bottom;
          final keyboardVisible = keyboardHeight > 0;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: Container(
              constraints: BoxConstraints(
                // 键盘弹出时占满剩余空间，避免弹窗被过度压缩导致输入框不可见/溢出
                maxHeight: keyboardVisible
                    ? MediaQuery.of(ctx).size.height - keyboardHeight
                    : MediaQuery.of(ctx).size.height * 0.6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题（居中，右侧关闭按钮）
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        const SizedBox(width: 44),
                        const Expanded(
                          child: Text('一品多码',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827))),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.close, size: 20, color: Color(0xFF9CA3AF)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  // 表格：序号 | 条码 | 操作（行间分隔线与收银流水一致）
                  Flexible(
                    child: SingleChildScrollView(
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(48),
                          1: FlexColumnWidth(),
                          2: FixedColumnWidth(84),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        border: const TableBorder(
                          horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
                        ),
                        children: [
                          // 表头行
                          const TableRow(
                            decoration: BoxDecoration(color: Color(0xFFE8F0FE)),
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(12, 13, 8, 13),
                                child: Text('序号', style: headerStyle),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                                child: Text('条码', style: headerStyle),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(0, 13, 8, 13),
                                child: Text('操作', textAlign: TextAlign.right, style: headerStyle),
                              ),
                            ],
                          ),
                          // 数据行
                          for (var i = 0; i < controllers.length; i++)
                            TableRow(
                              decoration: BoxDecoration(
                                color: i.isOdd ? const Color(0xFFF9F9F9) : Colors.white,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                                  child: Text('${i + 1}', style: cellStyle),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Builder(
                                    builder: (inputCtx) {
                                      return TextField(
                                        controller: controllers[i],
                                        keyboardType: TextInputType.number,
                                        maxLength: 18,
                                        style: cellStyle,
                                        onTap: () {
                                          // 键盘弹出会压缩弹窗高度，等动画结束后再滚动到输入框，
                                          // 避免“点击时可见、键盘弹出后被遮挡”的时序问题
                                          Future.delayed(const Duration(milliseconds: 350), () {
                                            if (!inputCtx.mounted) return;
                                            try {
                                              Scrollable.ensureVisible(
                                                inputCtx,
                                                alignment: 0.5,
                                                duration: const Duration(milliseconds: 200),
                                                curve: Curves.easeOut,
                                              );
                                            } catch (_) {
                                              // 弹窗已关闭、widget 已从树中移除（deactivated）时忽略
                                            }
                                          });
                                        },
                                        decoration: const InputDecoration(
                                          hintText: '请输入条码',
                                          hintStyle:
                                              TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                                          border: OutlineInputBorder(
                                              borderRadius: BorderRadius.all(Radius.circular(6))),
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          counterText: '',
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                // 操作：删除行，最后一行追加“添加”按钮
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          setDialogState(() {
                                            if (controllers.length == 1) {
                                              controllers[0].clear();
                                            } else {
                                              controllers[i].dispose();
                                              controllers.removeAt(i);
                                            }
                                          });
                                        },
                                        child: const Icon(Icons.remove_circle_outline,
                                            size: 20, color: Color(0xFFEF4444)),
                                      ),
                                      if (i == controllers.length - 1) ...[
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () {
                                            setDialogState(() {
                                              controllers.add(TextEditingController());
                                            });
                                          },
                                          child: const Icon(Icons.add_circle_outline,
                                              size: 20, color: Color(0xFF006EFF)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 键盘弹出时隐藏底部按钮行，给输入区域留足空间，避免弹窗被过度压缩
                  if (!keyboardVisible)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFD1D5DB)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: const Text('取消',
                                    style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  // 过滤空条码行（对齐小程序：空行不保存）
                                  _codes = controllers
                                      .map((c) => {'code': c.text.trim()})
                                      .where((item) => (item['code']?.toString() ?? '').isNotEmpty)
                                      .toList();
                                });
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF006EFF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: const Text('确定',
                                    style: TextStyle(fontSize: 14, color: Colors.white)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      for (final c in controllers) {
        c.dispose();
      }
    });
  }

  /// 跳转多规格管理页
  Future<void> _goToSpecPage() async {
    if ((_form['typeid']?.toString() ?? '').isEmpty) {
      Toast.show('请先选择商品分类');
      return;
    }

    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => CommoditySpecPage(
          sizedata: _sizedata,
          productName: _form['name']?.toString().trim() ?? '',
          typecode: _form['typecode']?.toString() ?? '',
          typeid: _form['typeid']?.toString() ?? '',
          packpage: _packList,
          barcode: _form['barcode']?.toString().trim() ?? '',
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _form['sizedata'] = result);
    }
  }

  // =================== 通用组件 ===================
  Widget _buildCard({String? title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String hint = '请输入',
    bool required = false,
    int maxLines = 1,
    bool readOnly = false,
    double labelWidth = 90,
  }) {
    final row = Row(
      crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
              if (required)
                const Positioned(
                  left: -10,
                  top: 0,
                  child: Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            readOnly: readOnly,
            enabled: !readOnly,
            style: TextStyle(
                fontSize: 14, color: readOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
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
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: maxLines > 1 ? row : SizedBox(height: 24, child: row),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    String hint = '0',
    void Function(String)? onChanged,
    bool readOnly = false,
    double labelWidth = 90,
    FocusNode? focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: readOnly ? null : onChanged,
                readOnly: readOnly,
                enabled: !readOnly,
                style: TextStyle(
                    fontSize: 14,
                    color: readOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
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

  Widget _buildDropdown({
    required String label,
    required int value,
    required List<Map<String, dynamic>> options,
    required ValueChanged<int> onChanged,
    bool enabled = true,
    double labelWidth = 90,
  }) {
    final selectedLabel = options.firstWhere(
      (o) => o['value'] == value,
      orElse: () => options.first,
    )['label'] as String;

    return GestureDetector(
      onTap: enabled ? () => _showDropdownDialog(label, value, options, onChanged) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(selectedLabel,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  void _showDropdownDialog(String title, int currentValue, List<Map<String, dynamic>> options,
      ValueChanged<int> onChanged) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            // 选项区可滚动，避免小屏设备选项过多时底部溢出
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...options.map((opt) {
                      final isSelected = opt['value'] == currentValue;
                      return ListTile(
                        title: Text(opt['label'] as String,
                            style: TextStyle(
                              fontSize: 15,
                              color: isSelected ? const Color(0xFF006EFF) : const Color(0xFF374151),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            )),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF006EFF), size: 20)
                            : null,
                        onTap: () {
                          onChanged(opt['value'] as int);
                          Navigator.pop(ctx);
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchField({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Transform.translate(
            offset: const Offset(-8, 0),
            child: Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: const Color(0xFF006EFF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  /// 右对齐开关（标签左，Switch 右，对齐小程序 more.vue 的 switch 布局）
  Widget _buildRightSwitchField({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    double labelWidth = 90,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Transform.translate(
              offset: const Offset(-8, 0),
              child: SizedBox(
                height: 20,
                child: Switch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                  activeColor: const Color(0xFF006EFF),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 带后缀标签的数字输入（对齐小程序 suffixLabel）
  Widget _buildSuffixNumberField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    String hint = '请输入',
    bool readOnly = false,
    double labelWidth = 90,
    FocusNode? focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                readOnly: readOnly,
                enabled: !readOnly,
                style: TextStyle(
                    fontSize: 14,
                    color: readOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  suffixText: suffix,
                  suffixStyle: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 带选择箭头的字段（对齐小程序选择器样式）
  Widget _buildSelectRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool enabled = true,
    bool required = false,
    double labelWidth = 80,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                    if (required)
                      const Positioned(
                        left: -10,
                        top: 0,
                        child: Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(value.isEmpty ? '请选择' : value,
                      style: TextStyle(
                          fontSize: 14,
                          color:
                              value.isEmpty ? const Color(0xFFD1D5DB) : const Color(0xFF111827))),
                ),
              ),
              if (enabled) const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  /// 经销方式行（只读显示，联营/扣率代销/租赁时右侧显示联营比例输入框）
  Widget _buildSelltypeRow() {
    final selltype = (_form['selltype'] ?? 1) as int;
    final selltypeLabel = _sellTypeOptions.firstWhere((o) => o['value'] == selltype,
        orElse: () => _sellTypeOptions.first)['label'] as String;
    // selltype 2=联营, 4=扣率代销, 5=租赁 时显示联营比例
    final showJoinrate = [2, 4, 5].contains(selltype);
    // 编辑模式下联营比例只读，新增模式下可编辑
    final joinrateReadOnly = _isReadOnly;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text('经销方式',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(selltypeLabel,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
            ),
            if (showJoinrate) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _joinrateController,
                  focusNode: _joinrateFocusNode,
                  readOnly: joinrateReadOnly,
                  enabled: !joinrateReadOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 14,
                      color: joinrateReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF111827)),
                  decoration: InputDecoration(
                    hintText: joinrateReadOnly ? '' : '请输入',
                    hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    suffixText: '%',
                    suffixStyle: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 包装单位列表项
class _PackageItem extends StatelessWidget {
  const _PackageItem({
    required this.productName,
    required this.pack,
    required this.index,
    required this.onDelete,
    this.onTap,
    this.readOnly = false,
  });
  final String productName;
  final Map<String, dynamic> pack;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final String barcode = pack['sbarcode']?.toString() ?? pack['packbarcode']?.toString() ?? '';
    final String unit = pack['sunit']?.toString() ?? '';
    final String num = pack['packagenum']?.toString() ?? pack['packrate']?.toString() ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Row(
          children: [
            // 左侧：商品名称 + 条码
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(productName.isNotEmpty ? productName : '-',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
                  if (barcode.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(barcode,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                    ),
                ],
              ),
            ),
            // 右侧：包装单位 + 包装数量 + 箭头
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('包装单位: $unit',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
                    const SizedBox(height: 4),
                    Text('包装数量: $num',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 20, color: Color(0xFFBEBDBE)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 包装配置行卡片（对齐 Vue component/packconfig.vue，itemtype=9 包装单位商品）
class _PackConfigItem extends StatefulWidget {
  const _PackConfigItem({
    super.key,
    required this.row,
    required this.index,
    required this.readOnly,
    required this.onBarcodeCommit,
    required this.onDefFlagChanged,
    required this.onSelectProduct,
    required this.onScan,
  });

  final Map<String, dynamic> row;
  final int index;
  final bool readOnly;

  /// 条码失焦/扫码后提交匹配
  final Future<void> Function(int index, String barcode) onBarcodeCommit;

  /// 默认单位开关变更
  final void Function(int index, bool value) onDefFlagChanged;

  /// “+”打开商品选择页
  final VoidCallback onSelectProduct;

  /// 扫码
  final VoidCallback onScan;

  @override
  State<_PackConfigItem> createState() => _PackConfigItemState();
}

class _PackConfigItemState extends State<_PackConfigItem> {
  final _barcodeCtrl = TextEditingController();
  final _numCtrl = TextEditingController();
  final _barcodeFocus = FocusNode();
  final _numFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _barcodeCtrl.text = widget.row['barcode']?.toString() ?? '';
    _numCtrl.text = widget.row['packagenum']?.toString() ?? '';
    // 条码失焦后提交匹配（对齐 v-model.lazy + blur）
    _barcodeFocus.addListener(() {
      if (!_barcodeFocus.hasFocus) {
        final barcode = _barcodeCtrl.text.trim();
        if (barcode.isNotEmpty) widget.onBarcodeCommit(widget.index, barcode);
      }
    });
    // 包装数量实时同步 + 失焦格式化（1 位小数）
    _numCtrl.addListener(() => widget.row['packagenum'] = _numCtrl.text);
    _numFocus.addListener(() {
      if (!_numFocus.hasFocus && _numCtrl.text.isNotEmpty) {
        final v = double.tryParse(_numCtrl.text) ?? 0;
        _numCtrl.text = v.toStringAsFixed(1);
        widget.row['packagenum'] = _numCtrl.text;
      }
    });
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _numCtrl.dispose();
    _barcodeFocus.dispose();
    _numFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final name = row['name']?.toString() ?? '';
    const kDivider = Divider(height: 1, color: Color(0xFFE6E6E6));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
            ),
          _buildBarcodeRow(),
          kDivider,
          _buildReadRow('自编码', row['code']),
          kDivider,
          _buildReadRow('包装单位', row['unit']),
          kDivider,
          _buildNumRow(),
          kDivider,
          _buildReadRow('商品规格', row['size']),
          kDivider,
          _buildReadRow('包装进价', row['inprice']),
          kDivider,
          _buildReadRow('包装售价', row['sellprice']),
          kDivider,
          _buildReadRow('会员价一', row['mprice1']),
          kDivider,
          _buildReadRow('批发价一', row['pfprice1']),
          kDivider,
          _buildDefFlagRow(row),
        ],
      ),
    );
  }

  /// 商品条码行（可编辑 + 选择商品 + 扫码，样式对齐基本信息行）
  Widget _buildBarcodeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('商品条码',
                      style: TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                  Positioned(
                    left: -10,
                    top: 0,
                    child: Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _barcodeCtrl,
                focusNode: _barcodeFocus,
                enabled: !widget.readOnly,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                decoration: const InputDecoration(
                  hintText: '基本单位条码',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (!widget.readOnly) ...[
              Container(width: 1, height: 20, color: const Color(0xFFE5E7EB)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: widget.onSelectProduct,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.add, size: 14, color: Color(0xFF006EFF)),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: widget.onScan,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF006EFF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.qr_code_scanner, size: 14, color: Color(0xFF006EFF)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 只读展示行（自编码/包装单位/规格/价格等，样式对齐基本信息行）
  Widget _buildReadRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(value?.toString() ?? '',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
            ),
          ],
        ),
      ),
    );
  }

  /// 包装数量行（可编辑，必填星号在标题前，样式对齐基本信息行）
  Widget _buildNumRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            const SizedBox(
              width: 90,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('包装数量',
                      style: TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                  Positioned(
                    left: -10,
                    top: 0,
                    child: Text('*', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _numCtrl,
                focusNode: _numFocus,
                enabled: !widget.readOnly,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                decoration: const InputDecoration(
                  hintText: '请输入',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
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

  /// 默认单位开关行（defpackageflag，样式对齐基本信息开关行）
  Widget _buildDefFlagRow(Map<String, dynamic> row) {
    final def = row['defpackageflag']?.toString() == '1';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 90,
            child: Text('默认单位',
                style:
                    TextStyle(fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          Transform.translate(
            offset: const Offset(-8, 0),
            child: Switch(
              value: def,
              activeColor: const Color(0xFF006EFF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: widget.readOnly ? null : (v) => widget.onDefFlagChanged(widget.index, v),
            ),
          ),
        ],
      ),
    );
  }
}

/// 虚线边框绘制器
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1,
    this.dashLength = 5,
    this.gapLength = 3,
    this.borderRadius = 0,
  });
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        final extractPath = metric.extractPath(distance, end);
        canvas.drawPath(extractPath, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
