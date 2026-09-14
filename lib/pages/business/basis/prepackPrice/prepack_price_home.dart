import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/prepackPrice/prepack_detail_sheet.dart';
import 'package:flutter_deer/pages/user/label_print_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/gprinter.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 预包装改价主页
/// 业务逻辑参考小程序 subs/basis/prepackPrice/index.vue
class PrepackPriceHomePage extends StatefulWidget {
  const PrepackPriceHomePage({super.key});

  @override
  State<PrepackPriceHomePage> createState() => _PrepackPriceHomePageState();
}

class _PrepackPriceHomePageState extends State<PrepackPriceHomePage> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _bgColor = Color(0xFFF5F6FA);

  final TextEditingController _searchController = TextEditingController();

  /// 预包装商品列表
  List<Map<String, dynamic>> _dataList = [];

  /// 打印设置（含蓝牙配置 + 打印方式）
  Map<String, dynamic> _printSettings = {};

  /// 蓝牙打印进行中（全屏 loading 弹窗控制）
  bool _blePrinting = false;

  @override
  void initState() {
    super.initState();
    _loadPrintSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── 加载打印设置 ───

  /// 加载打印设置（对齐小程序 loadPrintSettings）
  void _loadPrintSettings() {
    final clientId = _getClientId();
    request(HttpApi.getPrintSet, {'clientid': clientId}, false, false).then((res) {
      if (res['retcode'] == 0 && mounted) {
        setState(() => _printSettings = Map<String, dynamic>.from(res['data'] as Map? ?? {}));
      }
    }).catchError((_) {});
  }

  /// 获取客户端设备标识
  String _getClientId() {
    final wxopenid = SpUtil.getString('wxopenid') ?? '';
    final storeStr = SpUtil.getString(Constant.store) ?? '';
    String sid = '';
    try {
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '';
      }
    } catch (_) {}
    if (wxopenid.isNotEmpty && sid.isNotEmpty) {
      return '${wxopenid}_$sid';
    }
    return wxopenid.isNotEmpty
        ? wxopenid
        : sid.isNotEmpty
            ? sid
            : 'default';
  }

  /// 获取当前门店 ID
  String _getStoreId() {
    final storeStr = SpUtil.getString(Constant.store) ?? '';
    try {
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap['id']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  // ─── 搜索 / 扫码 ───

  /// 搜索商品（对齐小程序 searchProduct：精确匹配单条计重/计份商品）
  Future<void> _searchProduct([ScaleBarcodeResult? scaleInfo]) async {
    String cond = _searchController.text.trim();
    if (cond.isEmpty) {
      Toast.show('请输入搜索条件');
      return;
    }

    // 手动输入时（未传入有效秤码解析结果），同样尝试解析条码秤生成的重量码/金额码
    if (scaleInfo?.type != 'weight' && scaleInfo?.type != 'amount') {
      final parsed = parseScaleBarcode(cond);
      if (parsed != null) {
        scaleInfo = parsed;
        cond = parsed.productCode;
        _searchController.text = cond;
      }
    }

    try {
      final res = await request(
          HttpApi.productGetList,
          {
            'cond': cond,
            'is_page': 1,
            'page': 1,
            // 取多条以支持同码多条判定（扫码/输入框搜索均可能命中相同条码）
            'pagesize': 10,
            'pricetypein': '2,3',
            'field': 'barcode',
            'type': 'asc'
          },
          true);
      _searchController.clear();
      if (res['retcode'] != 0) {
        return;
      }

      final list = ((res['data'] as Map?)?['list'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      if (list.isEmpty) {
        Toast.show('当前商品非计重/计份的商品');
        return;
      }
      // 同码多条判定（对齐小程序 searchProduct）：自编码命中或商品条码命中 >= 2 条视为同码多条
      final codeList = list
          .where((c) => (c['code']?.toString() ?? '').isNotEmpty && c['code'].toString() == cond)
          .toList();
      final barcodeList = list
          .where(
              (c) => (c['barcode']?.toString() ?? '').isNotEmpty && c['barcode'].toString() == cond)
          .toList();
      final needBatch = codeList.length >= 2 || barcodeList.length >= 2;
      if (needBatch) {
        // 同码多条：不跳转选品页，将所有匹配商品按重复录入策略批量加入列表；自编码命中优先
        _addBatchProducts(codeList.length >= 2 ? codeList : barcodeList, scaleInfo);
        return;
      }
      // 单条命中：优先取自编码/商品条码精确匹配的商品，否则取第一条
      Map<String, dynamic> primary = list[0];
      if (codeList.length == 1) {
        primary = codeList[0];
      } else if (codeList.isEmpty && barcodeList.length == 1) {
        primary = barcodeList[0];
      }

      final item = _buildPrepackItem(primary);
      _applyScaleInfo(item, scaleInfo);

      // 按重复录入策略处理（0=提示 1=累加 2=覆盖 3=允许重复），对齐小程序 addRepeatProductFlag
      final flag = _getAddRepeatProductFlag();
      final productid = item['productid']?.toString();
      final existIdx = _dataList.indexWhere((d) => d['productid']?.toString() == productid);

      if (flag == 3) {
        // 允许重复：不检查重复，直接推入列表末尾
        setState(() => _dataList.add(item));
        _openDetail(_dataList.length - 1);
        return;
      }
      if (existIdx == -1) {
        // 不存在：新增并打开弹窗
        setState(() => _dataList.add(item));
        _openDetail(_dataList.length - 1);
        return;
      }
      if (flag == 1) {
        // 累加模式：本次扫码数量累加到已有项，并重算金额/折扣/包装条码
        setState(() {
          final existRow = _dataList[existIdx];
          final existQty = double.tryParse(existRow['packQty']?.toString() ?? '') ?? 0;
          final itemQty = double.tryParse(item['packQty']?.toString() ?? '') ?? 0;
          final newQty = _round2(existQty + itemQty);
          final sellprice = double.tryParse(existRow['sellprice']?.toString() ?? '') ?? 0;
          existRow['packQty'] = newQty;
          // 扫码相关标记正确传递和保留
          existRow['qtyFromScan'] =
              (item['qtyFromScan'] == true) || (existRow['qtyFromScan'] == true);
          final newAmount = _round2(sellprice * newQty);
          existRow['packAmount'] = newAmount;
          existRow['packDiscount'] = _calcDiscount(sellprice, newQty, newAmount);
          existRow['packBarcode'] =
              generatePackageCode(newQty, newAmount, existRow['barcode'].toString());
        });
        _openDetail(existIdx);
        return;
      }
      if (flag == 2) {
        // 覆盖模式：用新扫码结果完全替换已有项数据（对齐小程序 Object.assign）
        setState(() {
          _dataList[existIdx] = {..._dataList[existIdx], ...item};
        });
        _openDetail(existIdx);
        return;
      }
      // 提示模式（flag == 0）：已存在时仅提示，不执行后续操作
      Toast.show('该商品已经录入');
    } catch (_) {}
  }

  /// 同码多条：将所有匹配商品按重复录入策略批量加入列表，并默认打开首条新增/更新项详情抽屉
  /// （对齐小程序 addBatchProducts）
  void _addBatchProducts(List<Map<String, dynamic>> products, ScaleBarcodeResult? scaleInfo) {
    final flag = _getAddRepeatProductFlag();
    var firstIndex = -1; // 首条新增/更新项的下标，用于默认打开详情抽屉
    var addedCount = 0;
    for (final product in products) {
      final item = _buildPrepackItem(product);
      _applyScaleInfo(item, scaleInfo);
      final productid = item['productid']?.toString();
      final existIdx = _dataList.indexWhere((d) => d['productid']?.toString() == productid);
      if (flag == 3 || existIdx == -1) {
        // 允许重复 / 不存在：直接推入列表末尾
        setState(() => _dataList.add(item));
        if (firstIndex == -1) firstIndex = _dataList.length - 1;
        addedCount++;
      } else if (flag == 1) {
        // 累加模式：本次扫码数量累加到已有项，并重算金额/折扣/包装条码
        setState(() {
          final existRow = _dataList[existIdx];
          final existQty = double.tryParse(existRow['packQty']?.toString() ?? '') ?? 0;
          final itemQty = double.tryParse(item['packQty']?.toString() ?? '') ?? 0;
          final newQty = _round2(existQty + itemQty);
          final sellprice = double.tryParse(existRow['sellprice']?.toString() ?? '') ?? 0;
          existRow['packQty'] = newQty;
          // 扫码相关标记正确传递和保留
          existRow['qtyFromScan'] =
              (item['qtyFromScan'] == true) || (existRow['qtyFromScan'] == true);
          final newAmount = _round2(sellprice * newQty);
          existRow['packAmount'] = newAmount;
          existRow['packDiscount'] = _calcDiscount(sellprice, newQty, newAmount);
          existRow['packBarcode'] =
              generatePackageCode(newQty, newAmount, existRow['barcode'].toString());
        });
        if (firstIndex == -1) firstIndex = existIdx;
        addedCount++;
      } else if (flag == 2) {
        // 覆盖模式：用新扫码结果完全替换已有项数据（对齐小程序 Object.assign）
        setState(() {
          _dataList[existIdx] = {..._dataList[existIdx], ...item};
        });
        if (firstIndex == -1) firstIndex = existIdx;
        addedCount++;
      }
      // 提示模式（flag == 0）：已存在的不重复加入，统一在下方提示
    }
    if (addedCount > 0) {
      if (addedCount < products.length) {
        Toast.show('${products.length - addedCount}个商品已经录入');
      }
      // 默认打开第一条新增商品的详情抽屉供编辑
      _openDetail(firstIndex);
    } else {
      Toast.show('该商品已经录入');
    }
  }

  /// 读取重复商品录入策略（0=提示 1=累加 2=覆盖 3=允许重复），
  /// 对齐小程序 loginParamResp.addRepeatProductFlag
  int _getAddRepeatProductFlag() {
    final v = _readLoginParamResp()['addRepeatProductFlag'];
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// 扫码搜索（对齐小程序 scanFn：尝试解析秤码后按商品码查询）
  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (result == null || result.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    final scaleInfo = parseScaleBarcode(result);
    // ===== 调试日志（定位秤码解析）=====
    final cfg = _readLoginParamResp();
    debugPrint('[扫码] 原始条码="$result" 长度=${result.length}');
    debugPrint('[扫码] 配置: webBarcodeInt=${cfg['webBarcodeInt']} '
        'wbBarcodeFormatInt=${cfg['wbBarcodeFormatInt']} '
        'webWeightInt=${cfg['webWeightInt']} '
        'webAmtInt=${cfg['webAmtInt']}');
    debugPrint('[扫码] 解析结果: type=${scaleInfo?.type} '
        'productCode=${scaleInfo?.productCode} '
        'qty=${scaleInfo?.qty} amount=${scaleInfo?.amount}');
    _searchController.text = scaleInfo?.productCode ?? result;
    _searchProduct(scaleInfo);
  }

  // ─── 数据构建（对齐小程序 buildPrepackItem）───

  /// 读取登录参数（调试用）
  Map<String, dynamic> _readLoginParamResp() {
    try {
      final str = SpUtil.getString('loginParamResp') ?? '';
      if (str.isNotEmpty) {
        return jsonDecode(str) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// 将 API 返回的商品数据转换为预包装列表项
  Map<String, dynamic> _buildPrepackItem(Map<String, dynamic> product) {
    final sellprice = double.tryParse(product['sellprice']?.toString() ?? '') ?? 0;
    final packQty = double.tryParse(product['packagenum']?.toString() ?? '') ?? 1;
    final packAmount = _round2(sellprice * packQty);
    debugPrint('[预包装] buildPrepackItem: productid=${product['productid']} '
        '原始sellprice=${product['sellprice']} 解析后=$sellprice '
        'packagenum=${product['packagenum']}');

    final item = <String, dynamic>{
      'productid': product['productid'] ?? '',
      'name': product['name'] ?? '',
      'barcode': product['barcode'] ?? '',
      'size': product['size'] ?? '',
      'sizeonlyid': product['sizeonlyid'] ?? '',
      'unit': (product['unit']?.toString() ?? '').isEmpty ? '包' : product['unit'],
      'unitonlyid': product['unitonlyid'] ?? '',
      'specflag': product['specflag'] ?? 0,
      'packageflag': product['packageflag'] ?? 0,
      'itemtype': product['itemtype'] ?? 1,
      'sellprice': sellprice,
      // 预包装字段
      'packQty': packQty,
      'packAmount': packAmount,
      'packDiscount': 100,
      // 打印份数
      'qty': 1,
      // 标记数量是否来自扫码（扫码获取的数量不可手动修改）
      'qtyFromScan': false,
    };
    // 根据条码秤规则自动生成包装条码
    item['packBarcode'] = generatePackageCode(packQty, packAmount, item['barcode'].toString());
    // 计算包装折扣(%) = 包装金额 / (包装数量 × 零售价) × 100
    item['packDiscount'] = _calcDiscount(sellprice, packQty, packAmount);
    return item;
  }

  /// 根据秤码解析结果设置数量/金额（对齐小程序 searchProduct 中秤码分支）
  void _applyScaleInfo(Map<String, dynamic> item, ScaleBarcodeResult? scaleInfo) {
    if (scaleInfo == null) {
      debugPrint('[秤码] _applyScaleInfo 跳过：scaleInfo=null（非秤码，数量取商品 packagenum）');
      return;
    }
    final sellprice = double.tryParse(item['sellprice']?.toString() ?? '') ?? 0;
    final barcode = item['barcode']?.toString() ?? '';

    if (scaleInfo.type == 'weight') {
      // 重量码：直接设置包装数量（对齐小程序 scaleInfo.qty || 1：null/0/NaN 均兜底为 1）
      final parsedQty = scaleInfo.qty;
      debugPrint('[秤码] weight 分支: parsedQty=$parsedQty sellprice=$sellprice');
      final qty = (parsedQty == null || parsedQty.isNaN || parsedQty <= 0) ? 1.0 : parsedQty;
      item['packQty'] = qty;
      item['qtyFromScan'] = parsedQty != null && !parsedQty.isNaN && parsedQty > 0;
      item['packAmount'] = _round2(sellprice * qty);
      item['packBarcode'] = generatePackageCode(qty, item['packAmount'] as double, barcode);
      item['packDiscount'] = _calcDiscount(sellprice, qty, item['packAmount'] as double);
    } else if (scaleInfo.type == 'amount') {
      // 金额码：根据金额和单价反算数量（对齐小程序 packQty = amount / sellprice）
      final amount = scaleInfo.amount ?? 0;
      debugPrint('[秤码] amount 分支: amount=$amount sellprice=$sellprice');
      if (sellprice > 0) {
        item['packQty'] = _round2(amount / sellprice);
        item['packAmount'] = amount;
        item['qtyFromScan'] = true;
        debugPrint('[秤码] amount 反算完成: packQty=${item['packQty']} '
            'packAmount=${item['packAmount']} qtyFromScan=true');
      } else {
        // sellprice<=0 无法反算，数量保持商品 packagenum（与小程序一致）
        item['packAmount'] = amount;
        debugPrint('[秤码] amount 分支: sellprice<=0 无法反算数量，packQty 保持 ${item['packQty']}');
      }
      item['packBarcode'] = generatePackageCode(
          double.tryParse(item['packQty']?.toString() ?? '') ?? 1,
          double.tryParse(item['packAmount']?.toString() ?? '') ?? 0,
          barcode);
      item['packDiscount'] = _calcDiscount(
          sellprice,
          double.tryParse(item['packQty']?.toString() ?? '') ?? 1,
          double.tryParse(item['packAmount']?.toString() ?? '') ?? 0);
    }
  }

  double _calcDiscount(double sellprice, double packQty, double packAmount) {
    final total = sellprice * packQty;
    return total > 0 ? _round2(packAmount / total * 100) : 100;
  }

  double _round2(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  // ─── 商品详情编辑抽屉 ───

  Future<void> _openDetail(int index) async {
    final updated = await PrepackDetailSheet.show(
      context,
      item: _dataList[index],
      storeid: _getStoreId(),
    );
    if (updated != null && mounted) {
      setState(() => _dataList[index] = updated);
    }
  }

  // ─── 打印 ───

  /// 执行打印（对齐小程序 print 三分支）
  Future<void> _print() async {
    if (_dataList.isEmpty) {
      Toast.show('至少选择一条明细');
      return;
    }

    // 注意：不能用 ?? 1 兜底，printType=0 表示关闭打印，是有效业务值
    final printType = _printSettings['printType'] != null
        ? int.tryParse(_printSettings['printType'].toString()) ?? 1
        : 1;

    // 分支 1：蓝牙打印（佳博 SDK2，标签内容与小程序保持一致）
    if (printType == 2) {
      final bleStatus = int.tryParse(_printSettings['lableBluetoothStatus']?.toString() ?? '') ?? 0;
      final deviceId = _printSettings['lableDeviceid']?.toString() ?? '';
      // 未连接打印机或系统蓝牙未开启：统一提示并跳转标签打印设置页连接
      bool btOn = true;
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          btOn = await GPrinter.isBluetoothEnabled;
        } catch (_) {}
      }
      if (bleStatus != 1 || deviceId.isEmpty || !btOn) {
        _showGoSettingsDialog('提示', '尚未在应用内连接蓝牙打印机，请前往打印设置连接');
        return;
      }
      _showConfirmDialog('确定打印 ${_dataList.length} 个标签吗？', () => _blePrintLabels(deviceId));
      return;
    }

    // 分支 2：旧接口前台打印
    if (printType == 1) {
      _showConfirmDialog('确定打印吗？', () async {
        try {
          final res = await request(
              HttpApi.setLabelPrintFlow,
              {
                'detailList': _dataList,
              },
              true);
          if (res['retcode'] == 0) {
            Toast.show('打印成功');
            if (mounted) {
              setState(() => _dataList = []);
            }
          }
        } catch (_) {}
      });
      return;
    }

    // 分支 3：打印已关闭
    _showGoSettingsDialog('提示', '打印已关闭，请前往打印设置开启');
  }

  // ─── 蓝牙打印（分支 1）───

  /// 蓝牙打印预包装标签（复用标签打印的连接/权限流程）
  Future<void> _blePrintLabels(String savedDeviceId) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      Toast.show('蓝牙打印暂仅支持 Android 设备');
      return;
    }
    if (_blePrinting) {
      return;
    }

    final granted = await GPrinter.requestPermissions();
    if (!granted) {
      Toast.show('蓝牙权限被拒绝，无法打印');
      return;
    }

    final String mac = savedDeviceId;
    bool connected = false;

    // 已连接则直接打印，否则先尝试连接已保存的打印机
    try {
      connected = await GPrinter.isConnected;
    } catch (_) {}
    if (!connected && mac.isNotEmpty && mounted) {
      _showBleLoading('正在连接打印机...');
      try {
        connected = await GPrinter.connect(mac);
      } catch (_) {
        connected = false;
      }
      _hideBleLoading();
    }

    // 连接失败：不在当前页弹窗连接，提示并跳转标签打印设置页
    if (!connected) {
      if (!mounted) {
        return;
      }
      _showGoSettingsDialog('提示', '尚未在应用内连接蓝牙打印机，请前往打印设置连接');
      return;
    }

    // 构建打印明细（份数已在 TSC PRINT 指令中设置）
    final printNum = int.tryParse(_printSettings['print_num']?.toString() ?? '') ?? 1;
    // 标签模板（读取打印设置，默认模板 1）
    final template = int.tryParse(_printSettings['print_template']?.toString() ?? '') ?? 1;
    final items = _dataList.map((item) {
      final qty = _clampQty(item['qty'] ?? printNum);
      // 折扣取弹窗（PrepackDetailSheet）修改后实时计算的 packDiscount
      final packAmount = double.tryParse(item['packAmount']?.toString() ?? '') ?? 0;
      final packQty = double.tryParse(item['packQty']?.toString() ?? '') ?? 1;
      final discount = double.tryParse(item['packDiscount']?.toString() ?? '') ?? 0;
      return <String, dynamic>{
        'name': item['name'] ?? '',
        'size': item['size'] ?? '',
        'barcode': item['barcode'] ?? '',
        'sellprice': item['sellprice'] ?? 0,
        'packQty': packQty,
        'packAmount': packAmount,
        'packDiscount': discount,
        'packBarcode': item['packBarcode'] ?? '',
        'qty': qty,
        'copies': qty,
      };
    }).toList();

    if (!mounted) {
      return;
    }
    _showBleLoading('打印中...');
    _blePrinting = true;
    try {
      await GPrinter.printPrepackLabels(items, template: template);
      Toast.show('打印成功');
      if (mounted) {
        setState(() => _dataList = []);
      }
    } on PlatformException catch (e) {
      Toast.show(e.message ?? '打印失败');
    } catch (_) {
      Toast.show('打印失败');
    } finally {
      _blePrinting = false;
      _hideBleLoading();
    }
  }

  /// 蓝牙打印全屏 loading 弹窗
  void _showBleLoading(String text) {
    if (!mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(text, style: const TextStyle(fontSize: 13, color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideBleLoading() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _showGoSettingsDialog(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(content, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const LabelPrintPage()),
              );
              // 设置页返回后刷新打印配置，保证用户可直接重试打印
              if (mounted) {
                _loadPrintSettings();
              }
            },
            child: const Text('去设置', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog(String content, VoidCallback onConfirm) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: Text(content, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('确定', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  // ─── 批量修改 ───

  void _showBatchModifyDialog() {
    final TextEditingController qtyController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量修改', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                hintText: '请输入打印份数',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '注：最多打印20份',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final val = int.tryParse(qtyController.text) ?? 0;
              if (val < 1) {
                Toast.show('请输入有效数量');
                return;
              }
              if (val > 20) {
                Toast.show('数量不能超过20');
                return;
              }
              setState(() {
                for (final item in _dataList) {
                  item['qty'] = val;
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('确定', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  // ─── 工具方法 ───

  int _clampQty(dynamic val) {
    final qty = int.tryParse(val?.toString() ?? '') ?? 1;
    return qty.clamp(1, 20);
  }

  void _deleteItem(int index) {
    _showConfirmDialog('确定删除吗？', () {
      setState(() => _dataList.removeAt(index));
    });
  }

  // ─── 页面构建 ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '预包装改价'),
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部搜索区域
            _buildSearchBar(),
            // 商品列表
            Expanded(
              child: _dataList.isEmpty
                  ? _buildEmptyView()
                  : ListView.builder(
                      cacheExtent: 800,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _dataList.length,
                      itemBuilder: (ctx, i) => _PrepackCard(
                        item: _dataList[i],
                        onTap: () => _openDetail(i),
                        onDelete: () => _deleteItem(i),
                        onQtyChanged: (val) {
                          setState(() => _dataList[i]['qty'] = val);
                        },
                      ),
                    ),
            ),
            // 底部按钮
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, _) {
                  return TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _searchProduct(),
                    decoration: InputDecoration(
                      hintText: '输入条码/品名/自编码',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 有输入内容时显示清空按钮
                          if (value.text.isNotEmpty)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _searchController.clear(),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.cancel, size: 16, color: Color(0xFFBFBFBF)),
                              ),
                            ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _scanBarcode,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child:
                                  Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFF666666)),
                            ),
                          ),
                        ],
                      ),
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: const Color.fromRGBO(245, 245, 245, 1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: Color(0xFF006EFF)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 搜索按钮
          GestureDetector(
            onTap: () => _searchProduct(),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: const Text('搜索', style: TextStyle(fontSize: 14, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: Color(0xFFCCCCCC)),
          SizedBox(height: 12),
          Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          // 批量修改
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!PermissionUtils.checkPermission('015702')) return;
                _showBatchModifyDialog();
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: PermissionUtils.hasPermission('015702')
                          ? _primaryColor
                          : const Color(0xFFCCCCCC)),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text('批量修改',
                    style: TextStyle(
                        fontSize: 15,
                        color: PermissionUtils.hasPermission('015702')
                            ? _primaryColor
                            : const Color(0xFF999999))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 打印标签
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!PermissionUtils.checkPermission('015707')) return;
                _print();
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: PermissionUtils.hasPermission('015707')
                      ? _primaryColor
                      : const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: const Text('打印标签',
                    style:
                        TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 预包装商品卡片（对齐小程序列表卡片布局）
class _PrepackCard extends StatelessWidget {
  const _PrepackCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
    required this.onQtyChanged,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<int> onQtyChanged;

  static const Color _subTextColor = Color(0xFF7A7A7A);
  static const Color _borderColor = Color(0xFFE2E2E2);

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    final unit = item['unit']?.toString() ?? '';
    final barcode = item['barcode']?.toString() ?? '';
    final sellprice = MathUtils.formatDecimal(2, item['sellprice'] ?? '0');
    final packQty = MathUtils.formatDecimal(1, item['packQty'] ?? 1);
    final packDiscount = MathUtils.formatDecimal(2, item['packDiscount'] ?? 100);
    final packAmount = MathUtils.formatDecimal(2, item['packAmount'] ?? 0);
    final packBarcode = item['packBarcode']?.toString() ?? '';
    final qty = int.tryParse(item['qty']?.toString() ?? '') ?? 1;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 商品名称 + 零售价 + 删除
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Text(
                      size.isNotEmpty ? '$name($size)' : name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '零售价: $sellprice/$unit',
                        style: const TextStyle(fontSize: 12, color: _subTextColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onDelete,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.delete, size: 20, color: _subTextColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 商品条码 + 包装数量
              Row(
                children: [
                  Expanded(
                    child: Text('商品条码: $barcode',
                        style: const TextStyle(fontSize: 12, color: _subTextColor)),
                  ),
                  Text('包装数量: $packQty',
                      style: const TextStyle(fontSize: 12, color: _subTextColor)),
                ],
              ),
              const SizedBox(height: 4),
              // 包装折扣 + 包装金额
              Row(
                children: [
                  Expanded(
                    child: Text('包装折扣: $packDiscount%',
                        style: const TextStyle(fontSize: 12, color: _subTextColor)),
                  ),
                  Text('包装金额: $packAmount',
                      style: const TextStyle(fontSize: 12, color: _subTextColor)),
                ],
              ),
              const SizedBox(height: 4),
              // 包装条码
              Text('包装条码: $packBarcode',
                  style: const TextStyle(fontSize: 12, color: _subTextColor)),
              const Divider(height: 16, thickness: 1, color: _borderColor),
              // 打印份数 + 步进器
              Row(
                children: [
                  Text('打印份数：$qty', style: const TextStyle(fontSize: 12, color: _subTextColor)),
                  const Spacer(),
                  _IntStepper(
                    value: qty,
                    min: 1,
                    max: 20,
                    onChanged: onQtyChanged,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 步进器组件（打印份数 1-20）
class _IntStepper extends StatelessWidget {
  const _IntStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBtn(
          icon: Icons.remove,
          enabled: value > min,
          onTap: () => onChanged(value - 1),
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text('$value', style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
        ),
        _buildBtn(
          icon: Icons.add,
          enabled: value < max,
          onTap: () => onChanged(value + 1),
        ),
      ],
    );
  }

  Widget _buildBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? const Color(0xFFDEDEDE) : const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
        ),
      ),
    );
  }
}
