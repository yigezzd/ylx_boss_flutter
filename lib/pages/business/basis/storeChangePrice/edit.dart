import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/pro_details_sheet.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 门店调价单 - 编辑/新增页
/// 参考 Vue boss 项目 storeChangePrice/edit.vue
class StoreChangePriceEditPage extends StatefulWidget {
  const StoreChangePriceEditPage({super.key, this.billid});

  final String? billid;

  @override
  State<StoreChangePriceEditPage> createState() => _StoreChangePriceEditPageState();
}

class _StoreChangePriceEditPageState extends State<StoreChangePriceEditPage> {
  final TextEditingController _billnameCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // ── 单据数据（对齐 Vue query）──
  String _billid = '';
  String _billno = '';
  String _createtime = '';
  String _createname = '';
  int _signflag = 0;
  String _reviewsignflag = '';
  String _reviewremark = '';
  String _mdstore = ''; // 调价机构 id
  String _mdstorename = ''; // 调价机构名称
  int _mdtype = 1; // 调价渠道（1=线下调价）
  int _executetype = 1; // 调价类型（1=立即执行 2=指定日期）
  String _executetime = ''; // 执行时间
  String _executestatus = ''; // 执行状态
  List<Map<String, dynamic>> _detailList = [];

  // ── 多级审批 ──
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  String _userCode = '';
  String _userid = '';
  Map<String, dynamic>? _savedSignData;

  /// 新单据时，根据机构查询是否需要审批签字，控制审核按钮显示（对齐 Vue billSign）
  bool _billSign = true;

  /// getInfo 返回的完整单据数据（对齐 Vue query = res.data），
  /// 保存/审核时整体回传，保证服务端字段不丢失
  Map<String, dynamic> _rawBill = {};

  // ── 批量删除 ──
  bool _isDelMode = false;
  Set<int> _delChecked = {};

  // ── 同步关联 ──
  bool _syncProductUnit = false;
  bool _syncProductSize = false;

  // ── PDA/扫码枪输入（参考采购入库单 add.dart 扫码交互）──
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  Timer? _scanDebounceTimer;
  bool _scanFieldFocused = false;
  bool _scanBusy = false;

  /// 吸顶区高度常量（对齐采购订货粘性表头）：扫码框区域 + 明细标题栏，区块固定高度确保总高精确无间隙
  static const double _scanStickyHeight = 68.0;
  static const double _stickyTitleHeight = 40.0;
  static const double _stickyExtent = _scanStickyHeight + _stickyTitleHeight;

  bool _loading = false;

  bool get _isEdit => _billid.isNotEmpty;
  bool get _isSigned => _signflag == 1;
  bool get _isRejected => _signflag == 2;
  bool get _isAdmin => _userCode == '1001';

  bool get _bolHandle {
    if (_signflag == 1) return false;
    if (_reviewFlowUsers.isEmpty) return true;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return !(firstIndex > 1);
  }

  bool get _disabled => !_bolHandle;

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

  bool get _canWithdraw {
    if (!_isEdit) return false;
    if (_isSigned) return false;
    if (_reviewFlowUsers.isEmpty) return false;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return firstIndex > 1;
  }

  // ── 调价范围（对齐 Vue priceOptions）──
  // key=query字段名, yprice=原价字段名, newpreice=新价格字段名
  static const List<Map<String, dynamic>> _priceOptionsDef = [
    {'label': '进价', 'key': 'mdinprice', 'yprice': 'inprice', 'newpreice': 'newinprice'},
    {'label': '零售价', 'key': 'mdsellprice', 'yprice': 'sellprice', 'newpreice': 'newsellprice'},
    {
      'label': '最低零售价',
      'key': 'mdminsellprice',
      'yprice': 'minsellprice',
      'newpreice': 'newminsellprice'
    },
    {'label': '会员价1', 'key': 'mdvip1', 'yprice': 'mprice1', 'newpreice': 'newmprice1'},
    {'label': '会员价2', 'key': 'mdvip2', 'yprice': 'mprice2', 'newpreice': 'newmprice2'},
    {'label': '会员价3', 'key': 'mdvip3', 'yprice': 'mprice3', 'newpreice': 'newmprice3'},
    {'label': '批发价1', 'key': 'mdpf1', 'yprice': 'pfprice1', 'newpreice': 'newpfprice1'},
    {'label': '批发价2', 'key': 'mdpf2', 'yprice': 'pfprice2', 'newpreice': 'newpfprice2'},
    {'label': '批发价3', 'key': 'mdpf3', 'yprice': 'pfprice3', 'newpreice': 'newpfprice3'},
    {'label': '配送价', 'key': 'mdpsprice', 'yprice': 'psprice', 'newpreice': 'newpsprice'},
    {
      'label': '商城零售价',
      'key': 'mdmallsell',
      'yprice': 'mallsellprice',
      'newpreice': 'newmallsellprice'
    },
  ];

  /// 调价范围可选项：商城调价(mdtype==2)仅展示商城零售价，
  /// 其余渠道展示普通价格类型（对齐小程序 showPriceOptions）
  List<Map<String, dynamic>> get _showPriceOptions {
    if (_mdtype == 2) {
      return _priceOptionsDef.where((opt) => opt['key'] == 'mdmallsell').toList();
    }
    return _priceOptionsDef.where((opt) => opt['key'] != 'mdmallsell').toList();
  }

  // 当前选中的调价范围（对应 query[key] 值，1=选中 0=未选中）
  Map<String, int> _priceScope = {};

  // 调价渠道选项（对齐小程序 mdtypeList）
  static const List<Map<String, dynamic>> _mdtypeList = [
    {'label': '线下调价', 'id': 1},
    {'label': '商城调价', 'id': 2},
    {'label': '商城/线下同步', 'id': 3},
  ];

  /// 切换调价渠道（对齐小程序 onChangemdtype）：
  /// 选中项与当前渠道一致时不处理；否则更新渠道并清空所有调价范围勾选
  void _onMdtypeChange(int id) {
    if (_mdtype == id) return;
    setState(() {
      _mdtype = id;
      for (final opt in _priceOptionsDef) {
        _priceScope[opt['key'] as String] = 0;
      }
    });
  }

  // 调价类型选项
  static const List<Map<String, dynamic>> _executetypeList = [
    {'label': '立即执行调价', 'id': 1},
    {'label': '指定日期调价', 'id': 2},
  ];

  // 执行状态选项
  static const List<Map<String, dynamic>> _executestatusList = [
    {'label': '未执行', 'id': 0},
    {'label': '已执行', 'id': 1},
    {'label': '执行失败', 'id': 2},
  ];

  @override
  void initState() {
    super.initState();
    // 读取用户信息
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _userid = userMap['userid']?.toString() ?? '';
        _userCode = userMap['code']?.toString() ?? '';
      }
    } catch (_) {}

    // 初始化调价范围（默认零售价=1，其他=0）
    for (final opt in _priceOptionsDef) {
      _priceScope[opt['key'] as String] = opt['key'] == 'mdsellprice' ? 1 : 0;
    }

    // 读取同步关联设置
    _syncProductUnit = SpUtil.getBool('syncProductUnit') ?? false;
    _syncProductSize = SpUtil.getBool('syncProductSize') ?? false;

    // 扫码枪输入框：回车提交；150ms 防抖兜底红外扫码枪逐字符写入（参考采购入库单）
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          final scanCode = _scanController.text.trim();
          if (scanCode.isNotEmpty) {
            _scanDebounceTimer?.cancel();
            _onScanInput(scanCode);
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
        _onScanInput(code);
      });
    });

    if (widget.billid != null && widget.billid!.isNotEmpty) {
      _billid = widget.billid!;
      _getInfo({'billid': _billid});
    } else {
      // 新增：默认当前门店
      try {
        final storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
          _mdstore = storeMap['id']?.toString() ?? '';
          _mdstorename = storeMap['name']?.toString() ?? '';
        }
      } catch (_) {}
      final now = DateTime.now();
      _createtime =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      _initSignUserBtn();
    }
  }

  @override
  void dispose() {
    _billnameCtrl.dispose();
    _scrollCtrl.dispose();
    _scanDebounceTimer?.cancel();
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  // =================== 数据加载 ===================
  Future<void> _getInfo(Map<String, dynamic> params) async {
    setState(() => _loading = true);
    try {
      final result = await request(HttpApi.storeChangePriceGetInfo, params);
      final data = result['data'];
      if (data != null && data is Map<String, dynamic>) {
        // 缓存完整单据数据（对齐 Vue query.value = res.data），保存/审核时整体回传
        _rawBill = Map<String, dynamic>.from(data);
        _billid = data['billid']?.toString() ?? _billid;
        _billno = data['billno']?.toString() ?? '';
        _createtime = data['createtime']?.toString() ?? '';
        _createname = data['createname']?.toString() ?? '';
        _signflag = int.tryParse(data['signflag']?.toString() ?? '0') ?? 0;
        _reviewsignflag = data['reviewsignflag']?.toString() ?? '';
        _reviewremark = data['reviewremark']?.toString() ?? '';
        _mdstore = data['mdstore']?.toString() ?? '';
        _mdstorename = data['mdstorename']?.toString() ?? '';
        _mdtype = int.tryParse(data['mdtype']?.toString() ?? '1') ?? 1;
        _executetype = int.tryParse(data['executetype']?.toString() ?? '1') ?? 1;
        _executetime = data['executetime']?.toString() ?? '';
        _executestatus = data['executestatus']?.toString() ?? '';
        _billnameCtrl.text = data['billname']?.toString() ?? '';

        // 审批数据
        _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
        _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);

        // 调价范围
        for (final opt in _priceOptionsDef) {
          final key = opt['key'] as String;
          _priceScope[key] = int.tryParse(data[key]?.toString() ?? '0') ?? 0;
        }

        // 明细列表
        final dl = data['detailList'];
        _detailList = (dl as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // 对齐 Vue getInfo：productbarcode 为空时用 barcode 补齐
        for (final item in _detailList) {
          if (!(item['productbarcode']?.toString().isNotEmpty ?? false)) {
            item['productbarcode'] = item['barcode'];
          }
        }

        // 初始化 new* 价格字段
        for (final item in _detailList) {
          for (final opt in _priceOptionsDef) {
            final newKey = opt['newpreice'] as String;
            final yKey = opt['yprice'] as String;
            item[newKey] = MathUtils.formatDecimal(2, item[newKey] ?? item[yKey] ?? 0);
          }
        }
      }
    } catch (e) {
      Toast.show('加载失败：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 新单据时，根据机构查询是否需要审批签字，控制审核按钮显示（对齐 Vue initSignUserBtn）
  Future<void> _initSignUserBtn() async {
    if (_isAdmin) return;
    if (!_isEdit && _mdstore.isNotEmpty) {
      try {
        final result = await request(HttpApi.reviewTypeConfigGetNewBillSignUser, {
          'billtypeid': '0105',
          'bsid': _mdstore,
        });
        final data = result['data'];
        final list = data is List ? data : <dynamic>[];
        if (list.isNotEmpty) {
          _billSign = list.any((item) => item is Map && item['userid']?.toString() == _userid);
        } else {
          _billSign = true;
        }
      } catch (_) {
        _billSign = false;
      }
      if (mounted) setState(() {});
    }
  }

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

  // =================== 门店选择 ===================
  Future<void> _selectStore() async {
    if (_disabled) return;
    final result = await SelectStorePage.show(
      context,
      initialSelectedId: _mdstore,
    );
    if (result != null && mounted) {
      setState(() {
        _mdstore = result['storeid']?.toString() ?? '';
        _mdstorename = result['storename']?.toString() ?? '';
      });
      _initSignUserBtn();
    }
  }

  // =================== 同步关联切换 ===================
  /// 切换同步关联包装单位（对齐 Vue watch(syncProductUnit)）
  Future<void> _toggleSyncProductUnit(bool value) async {
    setState(() => _syncProductUnit = value);
    SpUtil.putBool('syncProductUnit', value);
    try {
      await request(HttpApi.pluginsSetParam, {
        'name': 'syncProductUnit',
        'value': value ? '1' : '0',
      });
    } catch (_) {}
  }

  /// 切换同步关联规格（对齐 Vue watch(syncProductSize)）
  Future<void> _toggleSyncProductSize(bool value) async {
    setState(() => _syncProductSize = value);
    SpUtil.putBool('syncProductSize', value);
    try {
      await request(HttpApi.pluginsSetParam, {
        'name': 'syncProductSize',
        'value': value ? '1' : '0',
      });
    } catch (_) {}
  }

  // =================== 选择器辅助 ===================
  Future<void> _showActionSheet(
      String title, List<Map<String, dynamic>> list, ValueChanged<int> onSelect) async {
    if (_disabled) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                ),
              ]),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final opt = list[i];
                  return ListTile(
                    title: Text(opt['label']?.toString() ?? ''),
                    onTap: () => Navigator.pop(ctx, opt),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      onSelect(int.tryParse(result['id']?.toString() ?? '0') ?? 0);
    }
  }

  Future<void> _pickExecuteTime() async {
    if (_disabled) return;
    // 与筛选弹窗统一使用公共日期/时间滚轮组件（showCommonDatePicker/showCommonTimePicker）
    // 安全解析已保存的执行时间：空值/短于10位时直接 substring 会抛 RangeError
    DateTime initial = DateTime.now();
    if (_executetime.isNotEmpty) {
      final datePart = _executetime.length >= 10 ? _executetime.substring(0, 10) : _executetime;
      initial = DateTime.tryParse(datePart) ?? DateTime.now();
    }
    final picked = await showCommonDatePicker(context, initial: initial);
    if (picked == null || !mounted) {
      return;
    }
    final timeInit = _executetime.length > 11 ? _executetime.substring(11) : '00:00:00';
    final timePicked = await showCommonTimePicker(context, initial: timeInit);
    if (timePicked != null && mounted) {
      setState(() {
        _executetime =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')} '
            '$timePicked';
      });
    }
  }

  // =================== 调价范围选择 ===================
  void _openPriceScopeSheet() {
    if (_disabled) return;
    // 临时副本
    final tmpScope = Map<String, int>.from(_priceScope);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 50,
                    child: Row(children: [
                      const SizedBox(width: 48),
                      const Expanded(
                        child: Text('调价范围',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 48,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: _showPriceOptions.map((opt) {
                          final key = opt['key'] as String;
                          final label = opt['label'] as String;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(label,
                                    style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
                                Checkbox(
                                  value: (tmpScope[key] ?? 0) == 1,
                                  activeColor: const Color(0xFF006EFF),
                                  onChanged: (v) {
                                    setSheetState(() {
                                      tmpScope[key] = (v ?? false) ? 1 : 0;
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 12),
                    child: Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              for (final key in tmpScope.keys) {
                                tmpScope[key] = 0;
                              }
                            });
                          },
                          child: Container(
                            height: 42,
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFDEDEDE)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: const Text('重置',
                                style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _priceScope = Map<String, int>.from(tmpScope));
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF006EFF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: const Text('确定',
                                style: TextStyle(fontSize: 15, color: Colors.white)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 获取已选调价范围的显示文本（仅统计当前渠道可见项，对齐小程序 showPriceOptions 过滤）
  String get _priceScopeText {
    final selected = _showPriceOptions
        .where((opt) => (_priceScope[opt['key'] as String] ?? 0) == 1)
        .map((opt) => opt['label'] as String)
        .toList();
    return selected.isNotEmpty ? selected.join(',') : '';
  }

  // =================== 商品选择 ===================
  /// 打开选择页前已有明细的 productid 快照（对齐 Vue selectBeforeIds）：
  /// 选择页返回的是勾选全集，已有商品取消勾选即表示从明细中移除；
  /// 因 selectList 引用传递，选品页勾选新商品时可能先改动明细，故须在跳转前快照
  Set<String> _selectBeforeIds = {};

  Future<void> _selectProduct() async {
    if (_disabled) return;
    // 跳转前先快照已有明细（对齐小程序 selectProductFn/scanFn）
    _selectBeforeIds = _detailList.map((d) => d['productid']?.toString() ?? '').toSet();
    final result = await _openSelectProduct();
    await _applySelectProductResult(result);
  }

  /// 跳转商品选择页（多选），扫码同码多条时带关键词过滤候选商品（对齐小程序 selectProductFn/scanFn）
  Future<List<Map<String, dynamic>>?> _openSelectProduct({String? keyword}) async {
    final storeid = int.tryParse(_mdstore);
    return Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          storeid: storeid,
          multiple: true,
          checkboxMode: true,
          selectList: _detailList,
          paramJust: const ['unit', 'size'],
          mergData: {
            'itemstatus': '1,2',
            'storeid': _mdstore,
            // 商城调价渠道时，增加 mallflag 参数（对齐小程序 selectProductFn）
            if (_mdtype == 2) 'mallflag': 1,
          },
          // 扫码词过滤：选品页按该关键词展示候选商品（对齐小程序 cond）
          initialKeyword: keyword,
        ),
      ),
    );
  }

  /// 选品页返回数据处理（对齐小程序 onSelectProduct）：
  /// 已有商品保留（不覆盖已修改的 new* 价格），新商品初始化价格并按需展开多单位/多规格
  Future<void> _applySelectProductResult(List<Map<String, dynamic>>? result) async {
    if (!mounted) return;
    final flag = _getAddRepeatProductFlag();
    final rows = <Map<String, dynamic>>[];
    var hasDuplicateFlag = false;
    for (final item in result ?? <Map<String, dynamic>>[]) {
      final pid = item['productid']?.toString() ?? '';
      if (_selectBeforeIds.contains(pid)) {
        rows.add(item); // 已有商品：保留已修改的 new* 价格，不覆盖
        continue;
      }
      if (rows.any((r) => r['productid']?.toString() == pid)) {
        // 本批次重复商品：允许重复(flag==3)时继续添加，否则提示跳过（对齐选择页内部去重）
        if (flag == 3) {
          _initProductPrices(item);
          rows.addAll(await _expandProductRows(item));
        } else {
          hasDuplicateFlag = true;
        }
        continue;
      }
      // 新商品：将原价格字段赋值给 new* 价格字段（对齐 Vue handleProperty）
      _initProductPrices(item);
      // 按需展开多单位/多规格
      rows.addAll(await _expandProductRows(item));
    }
    if (hasDuplicateFlag) Toast.show('单据中已存在该商品');
    if (!mounted) return;
    setState(() => _detailList = rows);
  }

  /// 初始化商品 new* 价格字段（对齐小程序 handleProperty）
  void _initProductPrices(Map<String, dynamic> item) {
    for (final opt in _priceOptionsDef) {
      final newKey = opt['newpreice'] as String;
      final yKey = opt['yprice'] as String;
      if (item[newKey] == null) {
        item[newKey] = MathUtils.formatDecimal(2, item[yKey] ?? 0);
      }
    }
    // 商城调价渠道时，增加 mallflag 参数
    if (_mdtype == 2) {
      item['mallflag'] = 1;
    }
  }

  /// 对齐 JS 宽松比较 packageflag == 1（兼容数字 1 / 字符串 '1'）
  static bool _isTruthyFlag(dynamic v) => v?.toString() == '1';

  /// 同步关联包装单位/规格：根据主商品行拉取扩展数据并生成附加行
  /// （对齐小程序 edit.vue expandProductRows：主商品行保持原样，仅返回附加行，
  /// 返回 [mainRow, ...附加行] 便于调用方拼接）
  Future<List<Map<String, dynamic>>> _expandProductRows(Map<String, dynamic> mainRow) async {
    final productid = mainRow['productid']?.toString() ?? '';
    if (productid.isEmpty) return [mainRow];

    final result = <Map<String, dynamic>>[];
    // 对齐 Vue：多门店（mdstore 含逗号）时回退当前登录门店 id
    String bsid = _mdstore;
    if (bsid.contains(',')) {
      try {
        final storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          bsid = (jsonDecode(storeStr) as Map<String, dynamic>)['id']?.toString() ?? bsid;
        }
      } catch (_) {}
    }
    List<dynamic> packlist = [];
    List<dynamic> sizelist = [];

    // 多单位展开
    if (_syncProductUnit && _isTruthyFlag(mainRow['packageflag'])) {
      try {
        final res = await request(HttpApi.productGetExtendList, {
          'page': 1,
          'pagesize': 99999,
          'is_page': 0,
          'ptype': 1,
          'commonflag': 1,
          'productid': productid,
          'bsid': bsid,
          'itemtype': mainRow['itemtype']?.toString() ?? '',
          'packageflag': mainRow['packageflag']?.toString() ?? '',
        });
        final responseData = res['data'];
        packlist =
            (responseData is Map<String, dynamic> ? responseData['packlist'] : null) as List? ?? [];
      } catch (_) {}
    }

    // 多规格展开
    if (_syncProductSize && _isTruthyFlag(mainRow['specflag'])) {
      try {
        final res = await request(HttpApi.productGetExtendList, {
          'page': 1,
          'pagesize': 99999,
          'is_page': 0,
          'ptype': 1,
          'commonflag': 1,
          'productid': productid,
          'bsid': bsid,
          'itemtype': mainRow['itemtype']?.toString() ?? '',
          'specflag': mainRow['specflag']?.toString() ?? '',
        });
        final responseData = res['data'];
        sizelist =
            (responseData is Map<String, dynamic> ? responseData['sizelist'] : null) as List? ?? [];
      } catch (_) {}
    }

    // JS 真值判断（对齐 Vue || 运算符）：源值为非空/非零才覆盖
    bool truthy(dynamic v) {
      if (v == null) return false;
      final s = v.toString();
      return s.isNotEmpty && s != '0';
    }

    dynamic pick(dynamic src, dynamic fallback) => truthy(src) ? src : fallback;

    Map<String, dynamic>? toMap(dynamic e) {
      if (e is Map<String, dynamic>) return e;
      if (e is Map) return Map<String, dynamic>.from(e);
      return null;
    }

    void formatPrices(Map<String, dynamic> row) {
      for (final key in row.keys.toList()) {
        if (key.contains('price') && !key.contains('new')) {
          row[key] = MathUtils.formatDecimal(2, row[key]);
          row['new$key'] = MathUtils.formatDecimal(2, row[key]);
        }
      }
    }

    if (packlist.isEmpty && sizelist.isEmpty) return [mainRow];

    // packlist/sizelist 的第一条为默认主商品；录入多单位/多规格条码时 mainRow 是对应规格/单位，
    // 主商品改取第一条还原为基础单位/基础规格（只取一次，对齐小程序 effectiveMain）
    final first = toMap(packlist.isNotEmpty ? packlist[0] : sizelist[0]);
    final firstBarcode = pick(first?['sbarcode'], first?['barcode'])?.toString() ?? '';
    var effectiveMain = mainRow;
    if (firstBarcode.isNotEmpty && firstBarcode != (mainRow['barcode']?.toString() ?? '')) {
      final main = Map<String, dynamic>.from(mainRow);
      // 字段同步逻辑参考 changeUnit/changeSize
      main['inprice'] = pick(first?['inprice'], main['inprice']);
      main['sellprice'] = pick(first?['sellprice'], main['sellprice']);
      main['mprice1'] = pick(first?['mprice1'], main['mprice1']);
      main['mprice2'] = pick(first?['mprice2'], main['mprice2']);
      main['mprice3'] = pick(first?['mprice3'], main['mprice3']);
      main['pfprice1'] = pick(first?['pfprice1'], main['pfprice1']);
      main['pfprice2'] = pick(first?['pfprice2'], main['pfprice2']);
      main['pfprice3'] = pick(first?['pfprice3'], main['pfprice3']);
      main['mallsellprice'] = pick(first?['mallsellprice'], main['mallsellprice']);
      // 条码
      if (truthy(first?['sbarcode'])) {
        main['productbarcode'] = first?['sbarcode'];
        main['barcode'] = first?['sbarcode'];
      } else if (truthy(first?['barcode'])) {
        main['productbarcode'] = first?['barcode'];
        main['barcode'] = first?['barcode'];
      }
      // 自编码
      main['code'] = pick(first?['scode'], first?['code']);
      // 单位名称/规格名称：主商品行还原为基础单位/基础规格
      main['unitname'] = pick(first?['sunit'], pick(first?['unit'], main['unitname']));
      final firstSize = first?['size'];
      if (!packlist.isNotEmpty) {
        main['sizename'] = packlist[0]['size'];
        main['size'] = packlist[0]['size'];
      } else {
        main['sizename'] = truthy(firstSize) ? firstSize : '';
      }
      formatPrices(main);
      effectiveMain = main;
    }

    // 多单位附加行（基于 effectiveMain 克隆，对齐小程序）
    if (packlist.isNotEmpty) {
      // 接口返回第一条为主商品，上面已取，这里跳过
      for (final unitData in packlist.sublist(1)) {
        final ud = toMap(unitData);
        if (ud == null) continue;
        final newRow = Map<String, dynamic>.from(effectiveMain);
        newRow['inprice'] = pick(ud['inprice'], newRow['inprice']);
        newRow['sellprice'] = pick(ud['sellprice'], newRow['sellprice']);
        newRow['mprice1'] = pick(ud['mprice1'], newRow['mprice1']);
        newRow['mprice2'] = pick(ud['mprice2'], newRow['mprice2']);
        newRow['mprice3'] = pick(ud['mprice3'], newRow['mprice3']);
        newRow['pfprice1'] = pick(ud['pfprice1'], newRow['pfprice1']);
        newRow['pfprice2'] = pick(ud['pfprice2'], newRow['pfprice2']);
        newRow['pfprice3'] = pick(ud['pfprice3'], newRow['pfprice3']);
        newRow['mallsellprice'] = pick(ud['mallsellprice'], newRow['mallsellprice']);
        // 条码
        if (truthy(ud['sbarcode'])) {
          newRow['productbarcode'] = ud['sbarcode'];
          newRow['barcode'] = ud['sbarcode'];
          newRow['sizename'] = '';
        } else if (truthy(ud['barcode'])) {
          newRow['productbarcode'] = ud['barcode'];
          newRow['barcode'] = ud['barcode'];
        }
        // 自编码
        newRow['code'] = pick(ud['scode'], ud['code']);
        // 单位名称
        newRow['unitname'] = pick(ud['sunit'], pick(ud['unit'], newRow['unitname']));
        formatPrices(newRow);
        result.add(newRow);
      }
    }

    // 多规格附加行（基于 effectiveMain 克隆，对齐小程序）
    if (sizelist.isNotEmpty) {
      // 接口返回第一条为主商品，上面已取，这里跳过
      for (final sizeData in sizelist.sublist(1)) {
        final sd = toMap(sizeData);
        if (sd == null) continue;
        // 字段同步逻辑参考 changeSize
        final newRow = Map<String, dynamic>.from(effectiveMain);
        newRow['inprice'] = pick(sd['inprice'], newRow['inprice']);
        newRow['sellprice'] = pick(sd['sellprice'], newRow['sellprice']);
        newRow['mprice1'] = pick(sd['mprice1'], newRow['mprice1']);
        newRow['mprice2'] = pick(sd['mprice2'], newRow['mprice2']);
        newRow['mprice3'] = pick(sd['mprice3'], newRow['mprice3']);
        newRow['pfprice1'] = pick(sd['pfprice1'], newRow['pfprice1']);
        newRow['pfprice2'] = pick(sd['pfprice2'], newRow['pfprice2']);
        newRow['pfprice3'] = pick(sd['pfprice3'], newRow['pfprice3']);
        newRow['mallsellprice'] = pick(sd['mallsellprice'], newRow['mallsellprice']);
        // 条码
        if (truthy(sd['sbarcode'])) {
          newRow['productbarcode'] = sd['sbarcode'];
          newRow['barcode'] = sd['sbarcode'];
        } else if (truthy(sd['barcode'])) {
          newRow['productbarcode'] = sd['barcode'];
          newRow['barcode'] = sd['barcode'];
        }
        // 自编码
        newRow['code'] = pick(sd['scode'], sd['code']);
        newRow['size'] = '';
        // 规格名称
        newRow['sizename'] = pick(sd['sname'], pick(sd['size'], newRow['sizename']));
        formatPrices(newRow);
        result.add(newRow);
      }
    }

    return [effectiveMain, ...result];
  }

  // =================== 扫码 ===================
  Future<void> _scanBarcode() async {
    if (_disabled) return;
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code == null || !mounted) return;
    _handleScannedCode(code.toString());
    // _handleScannedCode('98545415511');
  }

  /// PDA/扫码枪输入统一入口（参考采购入库单）：
  /// 先清空输入框防重触发，复用摄像头扫码同一处理方法 _handleScannedCode（去重/展开/价格/弹窗一致），
  /// 处理完成（含商品详情弹窗关闭）后重新聚焦，支持连续扫码
  Future<void> _onScanInput(String code) async {
    _scanController.clear();
    _scanDebounceTimer?.cancel();
    if (_disabled) return;
    // 上一笔仍在查询/弹窗中时丢弃本次输入，避免并发插入明细造成数据竞争
    if (_scanBusy) return;
    _scanBusy = true;
    try {
      await _handleScannedCode(code);
    } finally {
      _scanBusy = false;
    }
    if (!mounted) return;
    _scanFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// 扫码枪输入框（参考采购入库单 _buildScanInput：白色圆角卡片包裹）
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

  /// 处理扫码结果（对齐小程序 scanFn）
  Future<void> _handleScannedCode(String code) async {
    if (code.trim().isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    try {
      // 尝试解析条码秤生成的重量码/金额码
      final scaleInfo = parseScaleBarcode(code);
      final searchCode = scaleInfo?.productCode ?? code;
      final result = await request(HttpApi.productGetList, {
        'barcode': searchCode,
        'is_page': 1,
        'indivunitsize': 1,
        'page': 1,
        'pagesize': 10,
        'storeid': _mdstore,
        // 商城调价渠道时，增加 mallflag 参数（对齐小程序 scanFn）
        if (_mdtype == 2) 'mallflag': 1,
      });
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      // 对齐小程序：未查询到商品或返回数据无效（无 productid）时友好提示
      var prod = list.isNotEmpty ? Map<String, dynamic>.from(list[0] as Map) : null;
      if (prod == null || (prod['productid']?.toString() ?? '').isEmpty) {
        Toast.show('未查询到该商品');
        return;
      }
      // 同码多条判定（对齐小程序 scanFn）：自编码命中多条 → 跳转选品页；
      // 无自编码命中且商品条码命中多条 → 跳转选品页，由用户手动挑选
      final codeList = list
          .where(
              (c) => (c['code']?.toString() ?? '').isNotEmpty && c['code'].toString() == searchCode)
          .toList();
      final barcodeList = list
          .where((c) =>
              (c['barcode']?.toString() ?? '').isNotEmpty && c['barcode'].toString() == searchCode)
          .toList();
      final needJump = codeList.length >= 2 || (codeList.isEmpty && barcodeList.length >= 2);
      if (needJump) {
        // 跳转前先快照已有明细（与 selectProductFn 一致），返回后按 onSelectProduct 逻辑合并
        _selectBeforeIds = _detailList.map((d) => d['productid']?.toString() ?? '').toSet();
        final result = await _openSelectProduct(keyword: searchCode);
        await _applySelectProductResult(result);
        return;
      }
      // 单条命中：优先取与自编码/商品条码精确匹配的商品，否则取第一条（对齐小程序 scanFn）
      if (codeList.length == 1) {
        prod = Map<String, dynamic>.from(codeList[0] as Map);
      } else if (codeList.isEmpty && barcodeList.length == 1) {
        prod = Map<String, dynamic>.from(barcodeList[0] as Map);
      }
      final scanned = prod;
      final exists = _detailList
          .any((item) => item['productid']?.toString() == scanned['productid']?.toString());
      // 对齐小程序 rowHandle：商品不存在 或 允许重复(flag==3) 时新增行
      final flag = _getAddRepeatProductFlag();
      if (!exists || flag == 3) {
        _initProductPrices(scanned);
        final expanded = await _expandProductRows(scanned);
        if (!mounted) return;
        setState(() {
          // 对齐小程序：[...expanded, ...query.detailList] 插入列表头部
          if (expanded.isNotEmpty) {
            _detailList.insertAll(0, expanded);
          } else {
            _detailList.insert(0, scanned);
          }
        });
        // 开启关联单位/规格时，主行会被还原为基础单位/规格（expanded[0]）；
        // 弹窗应展示本次扫描条码对应的那一行，按条码匹配定位，未命中时回退主行
        int detailIndex = 0;
        if (expanded.length > 1) {
          final matched = expanded.indexWhere((row) {
            final rowBarcode =
                row['productbarcode']?.toString() ?? row['barcode']?.toString() ?? '';
            return rowBarcode.isNotEmpty && rowBarcode == searchCode;
          });
          if (matched > 0) detailIndex = matched;
        }
        // 等待商品详情弹窗关闭后再返回，便于扫码枪输入框在弹窗确认后重新聚焦连续扫码
        await _showProductDetail(detailIndex);
      } else {
        // 商品已存在且不允许重复，显示提示
        Toast.show('单据中已存在该商品');
      }
    } catch (_) {
      Toast.show('查询商品失败');
    }
  }

  /// 读取登录参数 addRepeatProductFlag（是否允许重复添加商品，对齐小程序 loginParamResp）
  int _getAddRepeatProductFlag() {
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
        return int.tryParse(cfg['addRepeatProductFlag']?.toString() ?? '') ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  // =================== 商品详情弹窗 ===================
  Future<void> _showProductDetail(int index) async {
    if (_isDelMode) {
      setState(() {
        if (_delChecked.contains(index)) {
          _delChecked.remove(index);
        } else {
          _delChecked.add(index);
        }
      });
      return;
    }
    if (_disabled) return;
    final item = Map<String, dynamic>.from(_detailList[index]);
    final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
    final unitcopy = item['unit']?.toString() ?? '';
    final sizecopy = item['size']?.toString() ?? '';
    // 复用公共商品详情弹窗（单位/规格选择 + 价格同步）
    final updated = await ProDetailsSheet.show(
      context,
      item: item,
      storeid: _mdstore,
      disabled: _disabled,
      unitDisabled: _syncProductUnit,
      sizeDisabled: _syncProductSize,
      showShelves: false,
    );
    if (updated != null && mounted && index >= 0 && index < _detailList.length) {
      setState(() {
        final target = _detailList[index];
        // 对齐 Vue detailConfirm：直接比较单位/规格是否变更
        final unitChanged = updated['unitonlyid'] != target['unitonlyid'];
        final sizeChanged = updated['sizeonlyid'] != target['sizeonlyid'];
        target['unit'] = unitcopy;
        target['size'] = sizecopy;
        if (updated['barcode'] != null) target['barcode'] = updated['barcode'];
        // 对齐 Vue: target.code = item.scode || item.code（scode 为空时保留原 code）
        final scodeVal = updated['scode'];
        final scodeStr = scodeVal?.toString() ?? '';
        target['code'] = (scodeStr.isNotEmpty && scodeStr != '0') ? scodeVal : updated['code'];
        // 对齐 Vue: target.productbarcode = item.barcode || target.productbarcode
        final ub = updated['barcode'];
        target['productbarcode'] =
            (ub != null && ub.toString().isNotEmpty) ? ub : target['productbarcode'];
        if (updated['unitonlyid'] != null) target['unitonlyid'] = updated['unitonlyid'];
        if (updated['sizeonlyid'] != null) target['sizeonlyid'] = updated['sizeonlyid'];
        final unitName = updated['sunit'] ?? updated['unit'];
        if (unitName != null && unitName.toString().isNotEmpty) target['unitname'] = unitName;
        // 单位变更时清空规格名称（与 web 端 changeUnit 一致）
        // if (unitChanged) target['sizename'] = '';
        // if (sizeChanged) target['unitname'] = '';
        final sizeName = updated['sname'] ?? updated['size'];
        if (sizeName != null && sizeName.toString().isNotEmpty) target['sizename'] = sizeName;
        // 仅单位或规格变更时同步原始价格和新价格（对齐 Vue，避免覆盖用户已输入的新价格）
        if (unitChanged || sizeChanged) {
          const priceFields = [
            'inprice',
            'sellprice',
            'minsellprice',
            'mprice1',
            'mprice2',
            'mprice3',
            'pfprice1',
            'pfprice2',
            'pfprice3',
            'psprice',
            'mallsellprice',
          ];
          for (final key in priceFields) {
            if (updated[key] != null) {
              target[key] = updated[key];
              target['new$key'] = MathUtils.formatDecimal(2, updated[key]);
            }
          }
        }
      });
    }
  }

  // =================== 批量删除 ===================
  void _toggleDelMode() {
    if (_detailList.isEmpty) return;
    setState(() {
      _isDelMode = !_isDelMode;
      if (!_isDelMode) _delChecked.clear();
    });
  }

  void _toggleAllDel() {
    setState(() {
      if (_delChecked.length == _detailList.length) {
        _delChecked.clear();
      } else {
        _delChecked = Set<int>.from(List.generate(_detailList.length, (i) => i));
      }
    });
  }

  void _confirmDelete() {
    if (_delChecked.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text('确定删除${_delChecked.length}条数据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              setState(() {
                final sorted = _delChecked.toList()..sort();
                for (int i = sorted.length - 1; i >= 0; i--) {
                  _detailList.removeAt(sorted[i]);
                }
                _isDelMode = false;
                _delChecked.clear();
              });
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // =================== 保存 ===================
  bool _validate() {
    if (_mdstore.isEmpty) {
      Toast.show('机构不能为空');
      return false;
    }
    if (_detailList.every((item) => !(item['productid']?.toString().isNotEmpty ?? false))) {
      Toast.show('请选择商品');
      return false;
    }
    return true;
  }

  Map<String, dynamic> _buildSaveParams() {
    print('_buildSaveParams: $_detailList');
    return {
      // 编辑时以 getInfo 返回的完整单据字段为基底（对齐 Vue cloneDeep(query.value)），
      // 避免服务端字段（insid/mallsell 标记等）丢失导致后端处理异常
      ..._rawBill,
      'billid': _billid,
      'billno': _billno,
      'billname': _billnameCtrl.text.trim(),
      'createtime': _createtime,
      'createname': _createname,
      'mdstore': _mdstore,
      'mdstorename': _mdstorename,
      'mdtype': _mdtype,
      'executetype': _executetype,
      'executetime': _executetime,
      'executestatus': _executestatus,
      // 商城价格标记（对齐 Vue query 默认值，编辑时保留服务端返回值）
      'mdmallsell': _rawBill['mdmallsell'] ?? 0,
      'mdmallvip': _rawBill['mdmallvip'] ?? 0,
      'mdmallpro': _rawBill['mdmallpro'] ?? 0,
      'signflag': 0,
      'reviewsignflag': 0,
      'reviewremark': '',
      // 调价范围
      ...{for (final opt in _priceOptionsDef) opt['key'] as String: _priceScope[opt['key']] ?? 0},
      'detailList': _detailList.map((item) {
        final m = Map<String, dynamic>.from(item);
        // if()
        if (m['packageflag'] == 1 && m['unit'] == m['unitname']) {
          m['unitname'] = '';
        }
        if (m['specflag'] == 1 && m['size'] == m['sizename']) {
          m['sizename'] = '';
        }
        // 规格商品：specflag=1 且 size 与 sizename 相同时，sizename 置空

        m.remove('checked');
        return m;
      }).toList(),
    };
  }

  Future<void> _save() async {
    // 权限校验：区分新增/编辑
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('010503', showTip: false)) {
        Toast.show('你无权编辑门店调价，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('010502', showTip: false)) {
        Toast.show('你无权新增门店调价，请在后台修改权限');
        return;
      }
    }
    if (!_validate()) return;
    final params = _buildSaveParams();
    try {
      final result = await request(HttpApi.storeChangePriceSave, params);
      final data = result['data'];
      if (data != null) {
        final dataMap = data is Map<String, dynamic> ? data : null;
        _reviewFlowUsers = _parseReviewList(dataMap?['reviewFlowUsers']);
        _reviewBillFlows = _parseReviewList(dataMap?['reviewBillFlows']);
        final newBillid = dataMap?['billid'];
        if (newBillid != null) {
          _billid = newBillid.toString();
        }
        Toast.show('保存成功');
        _getInfo({'billid': _billid});
        if (mounted) setState(() {});
      }
    } catch (e) {
      Toast.show('保存失败：$e');
    }
  }

  Future<void> _saveAndAudit() async {
    await _saveThenSign();
  }

  /// 先保存最新明细再审核（对齐小程序 _saveAndAudit：保存 → 审批弹窗/直接审核）
  Future<void> _saveThenSign() async {
    if (!_validate()) return;
    final params = _buildSaveParams();
    try {
      final result = await request(HttpApi.storeChangePriceSave, params);
      final data = result['data'];
      if (data != null) {
        final dataMap = data is Map<String, dynamic> ? data : null;
        // 更新 billid，并缓存保存接口完整返回数据供 doSign 使用
        final newBillid = dataMap?['billid'];
        if (newBillid != null) {
          _billid = newBillid.toString();
        }
        _savedSignData = dataMap;
        // 对齐小程序：审批节点数据取自保存响应
        _reviewFlowUsers = _parseReviewList(dataMap?['reviewFlowUsers']);
        _reviewBillFlows = _parseReviewList(dataMap?['reviewBillFlows']);
        if (mounted) setState(() {});
        // 对齐小程序：刷新页面数据（异步，不阻塞弹窗）
        unawaited(_getInfo({'billid': _billid}));

        // 与小程序 auditCommon 对齐：有多级审批时弹窗，无多级审批时直接审核通过
        if (_reviewFlowUsers.isNotEmpty) {
          final approvalResult = await _openApprovalModal();
          if (approvalResult != null && mounted) {
            _reviewsignflag = approvalResult['reviewsignflag']?.toString() ?? '';
            _reviewremark = approvalResult['reviewremark']?.toString() ?? '';
            await _doSign(_reviewremark, _savedSignData);
          }
        } else {
          _reviewsignflag = '1';
          await _doSign('', _savedSignData);
        }
      }
    } catch (e) {
      Toast.show('保存失败：$e');
    }
  }

  // =================== 审核 ===================
  Future<void> _sign() async {
    if (!PermissionUtils.checkPermission('010505', showTip: false)) {
      Toast.show('你无权审核门店调价，请在后台修改权限');
      return;
    }
    // 对齐小程序：「审核」按钮绑定 saveAndAudit，先保存最新明细（含修改后的价格）再审核
    await _saveThenSign();
  }

  Future<Map<String, dynamic>?> _openApprovalModal() async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ApprovalDialog(),
    );
  }

  /// 执行审核操作（对齐小程序 doSign）
  /// [reviewremark] 审批备注
  /// [savedData] 保存接口返回的完整单据数据
  Future<void> _doSign(String reviewremark, [Map<String, dynamic>? savedData]) async {
    // 对齐小程序：非审批人且非撤回时提示警告
    final isWithdraw = _reviewsignflag == '2';
    if (!isWithdraw && _reviewFlowUsers.isNotEmpty && !_bolHandleT) {
      Toast.show('您不属于当前审批节点的审核人！');
      return;
    }
    // 完整单据数据（含 detailList）作基底，保存接口返回数据覆盖其上，
    // 与小程序 doSign 的 {...(savedData || cloneDeep(query.value)), ...} 等效，
    // 保证审核接口始终携带明细，后端才能据此更新商品档案价格
    final parmas = <String, dynamic>{
      ..._rawBill,
      if (savedData != null) ...savedData,
      'billid': _billid,
      'signflag': 1,
      'reviewremark': reviewremark,
      'reviewsignflag': _reviewsignflag,
    };
    // reviewsignflag: 1=审核通过  2=撤回  0=驳回（非撤回且非驳回的都强制为 1）
    final rsf = int.tryParse(parmas['reviewsignflag']?.toString() ?? '') ?? 1;
    if (rsf != 2 && rsf != 0) {
      parmas['reviewsignflag'] = 1;
    }
    try {
      final result = await request(HttpApi.storeChangePriceSign, parmas);
      await _getInfo({'billid': _billid});
      if (mounted) Toast.show(result['retmsg'] as String? ?? '审核成功');
    } catch (e) {
      Toast.show('审核失败：$e');
    }
  }

  /// 撤回操作（对齐小程序 restsignFn：确认后 reviewsignflag=2 走 doSign）
  Future<void> _restsignFn() async {
    // 对齐小程序：撤回按钮绑定 permission('010505')
    if (!PermissionUtils.checkPermission('010505', showTip: false)) {
      Toast.show('你无权审核门店调价，请在后台修改权限');
      return;
    }
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
    if (confirm ?? false) {
      _reviewsignflag = '2';
      // 对齐小程序 restsignFn：优先使用缓存的保存数据
      _doSign('', _savedSignData);
    }
  }

  // =================== 删除单据 ===================
  Future<void> _delBill() async {
    if (!PermissionUtils.checkPermission('010504', showTip: false)) {
      Toast.show('你无权删除门店调价，请在后台修改权限');
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
    if (confirm ?? false) {
      try {
        await request(HttpApi.storeChangePriceDelBill, {'billid': _billid});
        Toast.show('删除成功');
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        Toast.show('删除失败：$e');
      }
    }
  }

  // =================== 新增单据 ===================
  Future<void> _editNew() async {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const StoreChangePriceEditPage()),
    );
  }

  // =================== 审批日志 ===================
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

  // =================== BUILD ===================
  @override
  Widget build(BuildContext context) {
    final String title = _isEdit ? (_isSigned ? '门店调价单详情' : '修改门店调价单') : '新增门店调价单';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
    );
  }

  /// 键盘弹起时隐藏底部汇总+按钮栏，给商品明细列表留出更多空间（对齐采购入库等模块）
  Widget _buildBody() {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            controller: _scrollCtrl,
            cacheExtent: 800,
            slivers: [
              if (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _buildApprovalNodeCard(),
                  ),
                ),
              if (_isEdit)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _buildBillInfoCard(),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: _buildFormCard(),
                ),
              ),
              // 扫码枪输入框吸顶（对齐采购订货 SliverPersistentHeader）：
              // 初始位于表单与商品明细之间，滚动到顶部后粘住不滚走
              if (!_disabled)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ScanInputStickyDelegate(state: this),
                ),
              // 商品明细（可编辑态紧贴吸顶标题栏，无顶部间距）
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, _disabled ? 12 : 0, 12, 0),
                  child: _buildProductDetailSection(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
        // 键盘弹起时隐藏底部汇总+按钮栏，给商品明细列表留出更多空间
        if (!keyboardVisible) _buildBottomBar(),
      ],
    );
  }

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
      margin: const EdgeInsets.only(bottom: 8),
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
            Row(children: [
              Expanded(
                  child: Text(currentInfo,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
              GestureDetector(
                onTap: _showApprovalLogDialog,
                child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
              ),
            ])
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

  Widget _buildBillInfoCard() {
    String statusLabel;
    Color statusColor;
    if (_signflag == 0) {
      statusLabel = '待审核';
      statusColor = const Color(0xFFD54B5A);
    } else if (_signflag == 2) {
      statusLabel = '已驳回';
      statusColor = const Color(0xFFE0620D);
    } else {
      statusLabel = '已审核';
      statusColor = const Color(0xFF00A870);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('单号$_billno',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: statusColor),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('制单信息：$_createtime',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            const SizedBox(width: 16),
            Text(_createname, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ]),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // 调价机构
          _buildFormItem(
            label: '调价机构1',
            onTap: _disabled ? null : _selectStore,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _mdstorename.isNotEmpty ? _mdstorename : (_disabled ? '' : '请选择'),
                    style: TextStyle(
                      fontSize: 14,
                      color: _mdstorename.isNotEmpty
                          ? const Color(0xFF333333)
                          : const Color(0xFF9CA3AF),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_disabled) const Icon(Icons.chevron_right, size: 20, color: Color(0xFF999999)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 调价渠道
          _buildActionSheetItem(
            label: '调价渠道',
            options: _mdtypeList,
            currentValue: _mdtype,
            onSelected: _onMdtypeChange,
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 调价类型
          _buildActionSheetItem(
            label: '调价类型',
            options: _executetypeList,
            currentValue: _executetype,
            onSelected: (v) => setState(() => _executetype = v),
          ),
          // 执行时间（仅 executetype==2 时显示）
          if (_executetype == 2) ...[
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            _buildFormItem(
              label: '执行时间',
              onTap: _disabled ? null : _pickExecuteTime,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _executetime.isNotEmpty ? _executetime : (_disabled ? '' : '请选择'),
                      style: TextStyle(
                        fontSize: 14,
                        color: _executetime.isNotEmpty
                            ? const Color(0xFF333333)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  if (!_disabled)
                    const Icon(Icons.chevron_right, size: 20, color: Color(0xFF999999)),
                ],
              ),
            ),
          ],
          // 执行状态（仅 executetype==2 && executestatus 存在时显示）
          if (_executetype == 2 && _executestatus.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            _buildActionSheetItem(
              label: '执行状态',
              options: _executestatusList,
              currentValue: int.tryParse(_executestatus) ?? 0,
              onSelected: (v) => setState(() => _executestatus = v.toString()),
              enabled: _signflag == 0,
            ),
          ],
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 备注
          _buildFormItem(
            label: '备注',
            child: TextField(
              controller: _billnameCtrl,
              enabled: !_disabled,
              decoration: const InputDecoration(
                hintText: '请输入',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          // 调价范围
          _buildFormItem(
            label: '调价范围',
            child: GestureDetector(
              onTap: _openPriceScopeSheet,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _priceScopeText.isNotEmpty ? _priceScopeText : (_disabled ? '' : '请选择'),
                      style: TextStyle(
                        fontSize: 14,
                        color: _priceScopeText.isNotEmpty
                            ? const Color(0xFF333333)
                            : const Color(0xFF9CA3AF),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!_disabled)
                    const Icon(Icons.chevron_right, size: 20, color: Color(0xFF999999)),
                ],
              ),
            ),
          ),
          // 同步关联包装单位/规格（仅非只读时显示）
          if (!_disabled) ...[
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => _toggleSyncProductUnit(!_syncProductUnit),
                  child: Row(children: [
                    Checkbox(
                      value: _syncProductUnit,
                      onChanged: (v) => _toggleSyncProductUnit(v ?? false),
                      activeColor: const Color(0xFF006EFF),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text('同步关联包装单位', style: TextStyle(fontSize: 13)),
                  ]),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => _toggleSyncProductSize(!_syncProductSize),
                  child: Row(children: [
                    Checkbox(
                      value: _syncProductSize,
                      onChanged: (v) => _toggleSyncProductSize(v ?? false),
                      activeColor: const Color(0xFF006EFF),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text('同步关联规格', style: TextStyle(fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  /// 通用 ActionSheet 下拉选择表单项（整行可点击）
  Widget _buildActionSheetItem({
    required String label,
    required List<Map<String, dynamic>> options,
    required int currentValue,
    required ValueChanged<int> onSelected,
    bool enabled = true,
  }) {
    final displayLabel = options.firstWhere(
      (e) => e['id'] == currentValue,
      orElse: () => options[0],
    )['label'] as String;
    return _buildFormItem(
      label: label,
      onTap: enabled ? () => _showActionSheet(label, options, onSelected) : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            displayLabel,
            style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
          ),
          if (enabled) const Icon(Icons.chevron_right, size: 20, color: Color(0xFF999999)),
        ],
      ),
    );
  }

  Widget _buildFormItem({
    required String label,
    required Widget child,
    bool required = false,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Row(children: [
              if (required)
                const Text('*', style: TextStyle(fontSize: 14, color: Color(0xFFEF4444))),
              Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ]),
          ),
          Expanded(child: child),
        ],
      ),
    );
    // 传入 onTap 时整行可点击（含左侧 label 区域）
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: row,
      );
    }
    return row;
  }

  // ── 商品明细区域 ──
  /// 吸顶头部（对齐采购订货 _buildStickyHeader）：扫码输入框 + 商品明细标题栏（删除/扫描/新增）
  Widget _buildStickyHeader() {
    return Align(
      alignment: Alignment.topCenter,
      child: ColoredBox(
        color: const Color(0xFFF5F5F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 扫码框区域固定高度，内容顶部对齐（余量作为与标题栏的自然间距）
            SizedBox(
              height: _scanStickyHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(alignment: Alignment.topCenter, child: _buildScanInput()),
              ),
            ),
            // 标题栏固定高度，底边与明细卡片紧贴无间隙
            SizedBox(
              height: _stickyTitleHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildDetailTitleBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 商品明细标题栏（标题 + 删除/扫描/新增按钮），置于吸顶头部；
  /// 与下方明细卡片拼接，仅保留顶部圆角
  Widget _buildDetailTitleBar() {
    return Container(
      height: _stickyTitleHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
        border: Border(
          top: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
          left: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
          right: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('商品明细',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          Row(children: [
            _buildActionBtn('删除', const Color(0xFFEF4444), Icons.delete_outline, _toggleDelMode),
            const SizedBox(width: 8),
            _buildActionBtn('扫描', const Color(0xFF006EFF), Icons.qr_code_scanner, _scanBarcode),
            const SizedBox(width: 8),
            _buildActionBtn(
                '新增', const Color(0xFF006EFF), Icons.add_circle_outline, _selectProduct),
          ]),
        ],
      ),
    );
  }

  Widget _buildProductDetailSection() {
    // 可编辑态与吸顶标题栏拼接：仅底部圆角；详情态独立卡片全圆角
    final BorderRadius radius = _disabled
        ? BorderRadius.circular(10)
        : const BorderRadius.only(
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 详情态无吸顶头部时，卡片内保留标题
          if (_disabled)
            const Text('商品明细',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          if (_detailList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                  child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))),
            )
          else
            ...List.generate(_detailList.length, (i) => _buildProductCard(i)),
        ],
      ),
    );
  }

  Widget _buildActionBtn(String label, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildProductCard(int index) {
    final item = _detailList[index];
    final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
    final sizeName = item['sizename']?.toString() ?? '';
    final sizeVal = item['size']?.toString() ?? '';
    final size = sizeName.isNotEmpty ? sizeName : sizeVal;
    final unitName = item['unitname']?.toString() ?? '';
    final unitVal = item['unit']?.toString() ?? '';
    final unit = unitName.isNotEmpty ? unitName : unitVal;
    final barcode = item['productbarcode']?.toString() ?? item['barcode']?.toString() ?? '';
    final isChecked = _delChecked.contains(index);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showProductDetail(index),
            child: Container(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isDelMode) ...[
                    Checkbox(
                      value: isChecked,
                      onChanged: (v) {
                        setState(() {
                          if (v ?? false) {
                            _delChecked.add(index);
                          } else {
                            _delChecked.remove(index);
                          }
                        });
                      },
                      activeColor: const Color(0xFF006EFF),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$name${size.isNotEmpty ? '/$size' : ''}${unit.isNotEmpty ? '($unit)' : ''}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
                        ),
                        const SizedBox(height: 4),
                        Text(barcode,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 动态价格行（根据调价范围选中项显示）
          // 原价格标题行
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 80,
                child: Text('价格类型', style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
              ),
              Text('原价格', style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
              Spacer(),
              Text('新价格', style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
            ]),
          ),
          ..._buildDynamicPriceRows(item),
        ],
      ),
    );
  }

  /// 根据选中的调价范围动态生成价格行
  List<Widget> _buildDynamicPriceRows(Map<String, dynamic> item) {
    final rows = <Widget>[];
    for (final opt in _priceOptionsDef) {
      final key = opt['key'] as String;
      if ((_priceScope[key] ?? 0) != 1) continue;
      final label = opt['label'] as String;
      final yprice = opt['yprice'] as String;
      final newpreice = opt['newpreice'] as String;
      final origVal = MathUtils.formatDecimal(2, item[yprice] ?? 0);
      final newVal = item[newpreice]?.toString() ?? origVal;

      rows.add(const Divider(height: 1, color: Color(0xFFF3F4F6)));
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
          Text(origVal, style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
          const Spacer(),
          SizedBox(
            width: 100,
            child: Builder(
              builder: (inputCtx) {
                return TextField(
                  controller: TextEditingController(text: newVal),
                  enabled: !_disabled,
                  // 键盘弹出时预留滚动余量，确保输入框完整露出不被遮挡
                  scrollPadding: const EdgeInsets.only(bottom: 120),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  onTap: () {
                    // 键盘弹出会压缩视口，等键盘动画结束后再滚动到输入框，
                    // 避免“点击时可见、键盘弹出后被遮挡”的时序问题
                    Future.delayed(const Duration(milliseconds: 350), () {
                      if (!inputCtx.mounted) return;
                      try {
                        Scrollable.ensureVisible(
                          inputCtx,
                          alignment: 0.6,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      } catch (_) {
                        // 页面已关闭、widget 已从树中移除（deactivated）时忽略
                      }
                    });
                  },
                  decoration: InputDecoration(
                    hintText: '请输入',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF006EFF)),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  style: const TextStyle(fontSize: 13),
                  // 对齐小程序 v-model：每次输入实时同步到数据，保证保存取到最新值
                  onChanged: (v) {
                    item[newpreice] = v;
                  },
                  onSubmitted: (v) {
                    item[newpreice] = v;
                    _priceBlur(item, newpreice);
                    if (mounted) setState(() {});
                  },
                  onTapOutside: (_) {
                    // 失焦时格式化 + 自动加价（对齐小程序 priceBlur）
                    _priceBlur(item, newpreice);
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
          ),
        ]),
      ));
    }
    return rows;
  }

  /// 价格失焦处理（对齐小程序 priceBlur）：格式化 + 自动加价
  void _priceBlur(Map<String, dynamic> row, String key) {
    final raw = row[key]?.toString() ?? '';
    if (raw.isEmpty) return;
    row[key] = MathUtils.formatDecimal(2, raw);
    if (!['newinprice', 'newsellprice'].contains(key)) return;
    final val = double.tryParse(row[key]?.toString() ?? '') ?? 0;
    if (val <= 0) return;
    // 读取 loginParamResp 配置
    Map<String, dynamic> loginCfg = {};
    try {
      final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (cfgStr.isNotEmpty) {
        loginCfg = jsonDecode(cfgStr) as Map<String, dynamic>;
      }
    } catch (_) {
      return;
    }
    final productAutoPrice = loginCfg['productAutoPrice']?.toString() ?? '';
    final autoPriceArr =
        productAutoPrice.isNotEmpty ? productAutoPrice.split('') : List.filled(6, '0');
    // 门店调价单加价率
    final changePriceFlag = autoPriceArr.length > 3 ? autoPriceArr[3] : '0';
    final productGentPrice = double.tryParse(loginCfg['productGentPrice']?.toString() ?? '') ?? 0;
    if (changePriceFlag != '1' || productGentPrice <= 0) return;
    final matchGent = (productGentPrice == 1 && key == 'newinprice') ||
        (productGentPrice == 2 && key == 'newsellprice');
    if (!matchGent) return;
    final addprice = val;
    // 进价零售加价
    final productPrice = double.tryParse(loginCfg['productPrice']?.toString() ?? '') ?? 0;
    if (productPrice > 0 && key == 'newsellprice') {
      final rate = productPrice / 100;
      row['newsellprice'] = MathUtils.formatDecimal(2, val * rate);
    }
    // 其他加价
    final otherAddPrice = [
      double.tryParse(loginCfg['productPfPrice']?.toString() ?? '') ?? 0,
      double.tryParse(loginCfg['productVipPrice']?.toString() ?? '') ?? 0,
      double.tryParse(loginCfg['productPsPrice']?.toString() ?? '') ?? 0,
    ];
    const otherKeys = ['newpfprice1', 'newmprice1', 'newpsprice'];
    for (var i = 0; i < otherAddPrice.length; i++) {
      if (otherAddPrice[i] > 0) {
        final rate = otherAddPrice[i] / 100;
        row[otherKeys[i]] = MathUtils.formatDecimal(2, addprice * rate);
      }
    }
    final memberPriceLevel = int.tryParse(loginCfg['memberPriceLevel']?.toString() ?? '') ?? 0;
    final pfPriceLevel = int.tryParse(loginCfg['pfPriceLevel']?.toString() ?? '') ?? 0;
    if (memberPriceLevel > 2) row['newmprice2'] = row['newmprice1'];
    if (memberPriceLevel == 3) row['newmprice3'] = row['newmprice1'];
    if (pfPriceLevel >= 2) row['newpfprice2'] = row['newpfprice1'];
    if (pfPriceLevel == 3) row['newpfprice3'] = row['newpfprice1'];
  }

  // ── 底部操作按钮 ──
  Widget _buildBottomBar() {
    final bottom = MediaQuery.of(context).padding.bottom;

    if (_isDelMode) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _toggleAllDel,
              child: Row(children: [
                Checkbox(
                  value: _delChecked.length == _detailList.length,
                  onChanged: (_) => _toggleAllDel(),
                  activeColor: const Color(0xFF006EFF),
                  visualDensity: VisualDensity.compact,
                ),
                Text('全选，已选${_delChecked.length}个',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
              ]),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isDelMode = false;
                      _delChecked.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _confirmDelete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006EFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('删除'),
                ),
              ),
            ]),
          ],
        ),
      );
    }

    // 已审核：新增单据
    if (_isSigned) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _editNew,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('新增单据'),
          ),
        ),
      );
    }

    // 编辑中（有单据ID且未审核/已驳回）
    if (_isEdit && !_isSigned) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Row(children: [
          if (!_isRejected && _bolHandleTT)
            Expanded(
              child: OutlinedButton(
                onPressed: _delBill,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('删除'),
              ),
            ),
          if (!_isRejected && _bolHandleTT) const SizedBox(width: 8),
          if (!_isRejected && (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT))) ...[
            Expanded(
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('保存'),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 对齐小程序：审核按钮显示条件 bolHandleTT || (reviewFlowUsers.length > 0 && bolHandleT) || billSign
          if (!_isRejected &&
              (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT) || _billSign) &&
              _executetype != 2) ...[
            Expanded(
              child: ElevatedButton(
                onPressed: _sign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('审核'),
              ),
            ),
          ],
          if (_isRejected)
            Expanded(
              child: ElevatedButton(
                onPressed: _restsignFn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('撤回'),
              ),
            ),
          if (_canWithdraw) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _restsignFn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('撤回'),
              ),
            ),
          ],
        ]),
      );
    }

    // 新增
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('保存'),
          ),
        ),
        // 预约调价（executetype==2）不显示保存并审核
        if (_executetype != 2) ...[
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _saveAndAudit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('保存并审核'),
            ),
          ),
        ],
      ]),
    );
  }
}

// =================== 审批弹窗 ===================
class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog();

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  int _flag = 1;
  final _remarkCtrl = TextEditingController();
  static const int _maxLength = 200;

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
            Row(children: [
              const SizedBox(
                width: 14,
                child: Text('*',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, height: 1.2)),
              ),
              const Text('审批意见：', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
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
            ]),
            const SizedBox(height: 20),
            Row(children: [
              SizedBox(
                width: 14,
                child: _flag != 1
                    ? const Text('*',
                        style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, height: 1.2))
                    : null,
              ),
              Text(
                _flag == 1 ? '备注信息：' : '驳回原因：',
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ]),
            const SizedBox(height: 8),
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
            const SizedBox(height: 20),
            Row(children: [
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
            ]),
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
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              ),
            )
          : null,
    );
  }
}

// =================== 审批日志弹窗 ===================
class _ApprovalLogSheet extends StatelessWidget {
  const _ApprovalLogSheet({
    required this.reviewBillFlows,
    required this.scrollController,
  });

  final List<Map<String, dynamic>> reviewBillFlows;
  final ScrollController scrollController;

  static String _actionText(dynamic v) {
    final s = v?.toString();
    if (s == '1') return '通过';
    if (s == '0') return '驳回';
    if (s == '2') return '撤回';
    return '待审';
  }

  static Color _actionColor(dynamic v) {
    final s = v?.toString();
    if (s == '1') return const Color(0xFF16A34A);
    if (s == '0') return const Color(0xFFDC2626);
    if (s == '2') return const Color(0xFFD97706);
    return const Color(0xFF6B7280);
  }

  static Color _actionBg(dynamic v) {
    final s = v?.toString();
    if (s == '1') return const Color(0xFFF0FDF4);
    if (s == '0') return const Color(0xFFFEF2F2);
    if (s == '2') return const Color(0xFFFFFBEB);
    return const Color(0xFFF3F4F6);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
          ),
          child: Row(children: [
            const SizedBox(width: 40),
            const Expanded(
              child: Text('审核日志',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, size: 20, color: Color(0xFF999999)),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: reviewBillFlows.isEmpty
              ? const Center(
                  child: Text('暂无审批记录', style: TextStyle(fontSize: 13, color: Color(0xFFBFBFBF))))
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: reviewBillFlows.length,
                  itemBuilder: (ctx, i) {
                    final item = reviewBillFlows[i];
                    final flag = item['reviewsignflag'];
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: i < reviewBillFlows.length - 1
                            ? const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: const Color(0xFF006EFF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(item['username']?.toString() ?? '',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF333333))),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _actionBg(flag),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(_actionText(flag),
                                  style: TextStyle(fontSize: 11, color: _actionColor(flag))),
                            ),
                          ]),
                          Padding(
                            padding: const EdgeInsets.only(left: 26, top: 3),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    '节点：${item['stepname']?.toString() ?? item['stepno']?.toString() ?? ''}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                                Text(
                                    item['signtime']?.toString() ??
                                        item['createtime']?.toString() ??
                                        '',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                              ],
                            ),
                          ),
                          if ((item['reviewremark']?.toString() ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 3),
                              child: Text('备注：${item['reviewremark']}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
                            ),
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

/// 吸顶委托（对齐采购订货 _CgorderStickyDelegate）：
/// 扫码输入框 + 商品明细标题栏（删除/扫描/新增），初始位于表单与明细之间，滚动到顶部后粘住
class _ScanInputStickyDelegate extends SliverPersistentHeaderDelegate {
  _ScanInputStickyDelegate({required this.state});
  final _StoreChangePriceEditPageState state;

  @override
  double get minExtent => _StoreChangePriceEditPageState._stickyExtent;

  @override
  double get maxExtent => _StoreChangePriceEditPageState._stickyExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return state._buildStickyHeader();
  }

  @override
  bool shouldRebuild(covariant _ScanInputStickyDelegate oldDelegate) => true;
}
