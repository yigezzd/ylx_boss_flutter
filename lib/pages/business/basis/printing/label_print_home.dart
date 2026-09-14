import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/pro_details_sheet.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/printing/router.dart';
import 'package:flutter_deer/pages/user/label_print_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/gprinter.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 标签打印主页
/// 业务逻辑参考 Vue boss 项目 subs/basis/printing/index.vue
class LabelPrintHomePage extends StatefulWidget {
  const LabelPrintHomePage({super.key});

  @override
  State<LabelPrintHomePage> createState() => _LabelPrintHomePageState();
}

class _LabelPrintHomePageState extends State<LabelPrintHomePage> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _textColor = Color(0xFF333333);
  static const Color _bgColor = Color(0xFFF5F6FA);
  static const Color _borderColor = Color(0xFFDEDEDE);

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 商品列表
  List<Map<String, dynamic>> _dataList = [];

  /// 打印设置（含蓝牙配置 + 打印方式）
  Map<String, dynamic> _printSettings = {};

  /// 旧接口前台打印参数
  Map<String, dynamic> _labelPrintParams = {};

  /// 蓝牙打印进行中（全屏 loading 弹窗控制）
  bool _blePrinting = false;

  @override
  void initState() {
    super.initState();
    // 查看权限校验
    if (PermissionUtils.checkPermission('010601', showTip: false)) {
      _loadPrintSettings();
    } else {
      Toast.show('你无权查看标签打印，请在后台修改权限');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── 加载打印设置 ───

  /// 加载打印设置（含蓝牙配置 + 打印方式 + 旧接口前台打印状态）
  void _loadPrintSettings() {
    final clientId = _getClientId();
    request(HttpApi.getPrintSet, {'clientid': clientId}, false, false).then((res) {
      if (res['retcode'] == 0 && mounted) {
        setState(() => _printSettings = Map<String, dynamic>.from(res['data'] as Map? ?? {}));
      }
    }).catchError((_) {});

    request(HttpApi.getLabelPrintParams, {'type': 31}, false, false).then((res) {
      if (res['retcode'] == 0 && mounted) {
        setState(() => _labelPrintParams = Map<String, dynamic>.from(res['data'] as Map? ?? {}));
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
    if (wxopenid.isNotEmpty && sid.isNotEmpty) return '${wxopenid}_$sid';
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

  /// 搜索商品（对齐 Vue searchFn / scanFn）：
  /// - 扫码（带 [barcode] 参数）：解析条码秤 → scancode 精确查询，结果追加/累加到现有列表
  /// - 输入框回车（PDA 扫码枪录入亦经此路径）：barcode 模糊匹配（条码/品名/自编码），
  ///   单条结果追加/累加，多条打开商品选择页
  Future<void> _searchProduct([String? barcode]) async {
    final cond = barcode ?? _searchController.text.trim();
    if (cond.isEmpty) return;
    _searchController.clear();

    final isScan = barcode != null;
    // 尝试解析条码秤生成的重量码/金额码（对齐 Vue scanFn）
    final scaleInfo = parseScaleBarcode(cond);
    final searchCode = scaleInfo?.productCode ?? cond;

    try {
      final res = await request(
          HttpApi.productGetList,
          {
            // 秤码/扫码按商品码精确查询，输入框按 barcode 模糊匹配
            if (isScan || scaleInfo != null) 'scancode': searchCode else 'barcode': cond,
            'is_page': 1,
            'page': 1,
            'pagesize': 10,
          },
          true);

      if (res['retcode'] != 0) return;
      final list = (res['data']?['list'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];

      if (list.isEmpty) {
        Toast.show(isScan ? '未查询到该商品' : '未查询到商品');
        return;
      }
      if (list.length == 1 || isScan) {
        // 对齐 Vue scanFn：扫码直接取第一条处理；输入框单条结果同样追加/累加
        _handleScannedItem(list[0], scaleInfo);
      } else {
        // 输入框多条命中：打开商品选择页（对齐 Vue searchFn）
        _openSelectProduct(cond);
      }
    } catch (_) {}
  }

  /// 单商品结果处理（对齐 Vue scanFn）：
  /// 条码秤数量赋值 → 多规格商品弹窗选规格 → 其余商品直接追加/累加到列表
  void _handleScannedItem(Map<String, dynamic> rawItem, ScaleBarcodeResult? scaleInfo) {
    final item = Map<String, dynamic>.from(rawItem);

    // 条码秤解析的数量赋值（对齐 Vue scanFn）：重量码取重量，金额码按售价/进价反算
    double initQty = 1;
    if (scaleInfo?.type == 'weight') {
      initQty = scaleInfo?.qty ?? 1;
    } else if (scaleInfo?.type == 'amount') {
      // JS 真值语义：sellprice || inprice || 0
      final sp = item['sellprice']?.toString() ?? '';
      final priceSrc = (sp.isNotEmpty && sp != '0') ? item['sellprice'] : item['inprice'];
      final price = double.tryParse(priceSrc?.toString() ?? '') ?? 0;
      initQty = price > 0 ? (scaleInfo?.amount ?? 0) / price : 1;
    }
    // 打印份数为整数 1~20，与步进器/批量修改上限保持一致
    if (!initQty.isFinite || initQty <= 0) initQty = 1;
    item['qty'] = _clampQty(initQty.round());

    // 多单位/多规格商品打开商品详情弹窗选择单位/规格，确认后累加（对齐 Vue 扫码流程）
    if (item['specflag']?.toString() == '1' || item['packageflag']?.toString() == '1') {
      _showProductDetailSheet(item);
    } else {
      _addOrAccumulateItem(item);
    }
  }

  /// 商品追加/累加（对齐 Vue addOrAccumulateItem）：
  /// 列表中已存在（productid 匹配，barcode 兜底）则累加数量上限 20，否则新增
  void _addOrAccumulateItem(Map<String, dynamic> item) {
    item['qty'] = _clampQty(item['qty']);
    final newQty = item['qty'] as int;
    final productid = item['productid']?.toString() ?? '';
    final barcode = item['barcode']?.toString() ?? '';

    final existIdx = _dataList.indexWhere((d) {
      final dProductid = d['productid']?.toString() ?? '';
      final dBarcode = d['barcode']?.toString() ?? '';
      // 优先以 productid 匹配，部分场景可能缺失则用 barcode 兜底
      return (productid.isNotEmpty && dProductid == productid) ||
          (barcode.isNotEmpty && dBarcode.isNotEmpty && dBarcode == barcode);
    });

    setState(() {
      if (existIdx > -1) {
        // 已存在：累加数量，上限 20
        final oldQty = int.tryParse(_dataList[existIdx]['qty']?.toString() ?? '') ?? 1;
        final total = oldQty + newQty;
        _dataList[existIdx]['qty'] = total > 20 ? 20 : total;
      } else {
        // 不存在：新增到列表
        _dataList.add(Map<String, dynamic>.from(item));
      }
    });
  }

  /// 扫码搜索（摄像头扫码 → 追加/累加，支持连续扫码）
  Future<void> _scanBarcode() async {
    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (result == null || !mounted) return;
    final code = result.toString();
    if (code.isNotEmpty) {
      _searchProduct(code);
    }
  }

  /// 打开商品选择页（多选）
  Future<void> _openSelectProduct([String cond = '']) async {
    if (!PermissionUtils.checkPermission('010602', showTip: false)) {
      Toast.show('你无权新增标签打印商品，请在后台修改权限');
      return;
    }
    final storeid = int.tryParse(_getStoreId());
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          storeid: storeid,
          multiple: true,
          selectList: _dataList,
          // 带入当前搜索关键字，避免用户重复输入
          initialKeyword: cond,
          mergData: {
            'itemstatus': '1,2',
            'storeid': _getStoreId(),
            'bsid': _getStoreId(),
            'field': 'barcode',
            'type': 'desc',
          },
        ),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _dataList = result.map((item) {
          item['qty'] = _clampQty(item['qty']);
          return item;
        }).toList();
      });
    }
  }

  // ─── 商品详情弹窗（多单位/多规格商品，对齐 Vue proDetails）───

  /// 打开商品详情弹窗（复用公共组件 ProDetailsSheet）
  Future<void> _showProductDetailSheet(Map<String, dynamic> item) async {
    final shelves = item['shelves']?.toString() ?? '';
    final updated = await ProDetailsSheet.show(
      context,
      item: item,
      storeid: _getStoreId(),
      mergData: const {'cgpriceflag': 1},
      // 卡片式信息区（与促销调价一致）：名称 + 条码 + 零售价/货架号
      cardPairs: [
        ProDetailsInfoRow('零售价', MathUtils.formatDecimal(2, item['sellprice'] ?? '0')),
        ProDetailsInfoRow('货架号', shelves.isEmpty ? '暂无货架' : shelves),
      ],
      showQty: true,
      showCancel: false,
      priceFields: const [
        'sellprice',
        'inprice',
        'pfprice1',
        'pfprice2',
        'pfprice3',
        'mprice1',
        'mprice2',
        'mprice3',
      ],
    );
    if (updated != null && mounted) {
      // 确认后追加/累加（对齐 Vue detailConfirm + addOrAccumulateItem）
      _addOrAccumulateItem(updated);
    }
  }

  /// 打开单据列表页，选择商品后加入打印列表
  void _openReceiptsList() {
    NavigatorUtils.pushResult(
      context,
      PrintingRouter.receiptsList,
      (result) {
        if (result is List && result.isNotEmpty && mounted) {
          setState(() {
            for (final item in result) {
              if (item is Map<String, dynamic>) {
                item['qty'] = _clampQty(item['qty']);
                _dataList.add(item);
              }
            }
          });
        }
      },
    );
  }

  // ─── 打印 ───

  /// 执行打印
  Future<void> _print() async {
    if (_dataList.isEmpty) {
      Toast.show('至少选择一条明细');
      return;
    }

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
      await _blePrintLabels(deviceId);
      return;
    }

    // 分支 2：旧接口前台打印
    if (printType == 1) {
      final labelPrintType =
          int.tryParse(_labelPrintParams['labelPrintType']?.toString() ?? '') ?? 0;
      if (labelPrintType != 1) {
        _showGoSettingsDialog('提示', '前台打印未启用，请前往打印设置开启');
        return;
      }
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
            if (mounted) setState(() => _dataList = []);
          }
        } catch (_) {}
      });
      return;
    }

    // 分支 3：打印已关闭
    _showGoSettingsDialog('提示', '打印已关闭，请前往打印设置开启');
  }

  // ─── 蓝牙打印（分支 1）───

  ///
  /// 蓝牙打印标签（对齐小程序 blePrintLabels 流程）
  ///
  /// 权限检查 → 连接已保存的打印机（失败则提示跳转设置页）→ 逐商品发送 TSC 指令
  ///
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
    final template = int.tryParse(_printSettings['print_template']?.toString() ?? '') ?? 1;
    final items = _dataList.map((item) {
      final qty = _clampQty(item['qty'] ?? printNum);
      return <String, dynamic>{
        'name': item['name'] ?? item['productname'] ?? '',
        'size': item['size'] ?? '',
        'barcode': item['barcode'] ?? '',
        'mprice1': item['mprice1'] ?? 0,
        'sellprice': item['sellprice'] ?? 0,
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
      await GPrinter.printLabels(items, template: template);
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: qtyController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  hintText: '请输入',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '注：最多打印20份',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
              // 键盘弹出时底部留白，避免遮挡
              SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final val = int.tryParse(qtyController.text) ?? 0;
              if (val > 20) {
                Toast.show('数量不能超过20');
                return;
              }
              if (val < 1) {
                Toast.show('数量不能小于1');
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

  // ─── 列表项组件 ───

  static Widget _buildProductCard({
    required Map<String, dynamic> item,
    required int index,
    required VoidCallback onDelete,
    required ValueChanged<int> onQtyChanged,
  }) {
    const Color subTextColor = Color(0xFF7A7A7A);
    const Color borderColor = Color(0xFFE2E2E2);

    final name = item['name']?.toString() ?? item['productname']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    final unit = item['unit']?.toString() ?? '';
    final barcode = item['barcode']?.toString() ?? '';
    final mprice1 = MathUtils.formatDecimal(2, item['mprice1'] ?? '0');
    final sellprice = MathUtils.formatDecimal(2, item['sellprice'] ?? '0');
    final qty = int.tryParse(item['qty']?.toString() ?? '') ?? 1;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 商品名称 + 删除按钮
            Row(
              children: [
                Expanded(
                  child: Text(
                    size.isNotEmpty ? '$name($size)$unit' : '$name$unit',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.delete_outline, size: 20, color: subTextColor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 条码
            Text(barcode, style: const TextStyle(fontSize: 12, color: subTextColor)),
            const SizedBox(height: 4),
            // 会员价 + 零售价
            Row(
              children: [
                Expanded(
                  child: Text('会员价：$mprice1',
                      style: const TextStyle(fontSize: 12, color: subTextColor)),
                ),
                Text('零售价：$sellprice', style: const TextStyle(fontSize: 12, color: subTextColor)),
              ],
            ),
            const Divider(height: 16, thickness: 1, color: borderColor),
            // 打印份数 + 步进器
            Row(
              children: [
                Text('打印份数：$qty', style: const TextStyle(fontSize: 12, color: subTextColor)),
                const Spacer(),
                _Stepper(
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
    );
  }

  // ─── 页面构建 ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '标签打印'),
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
                      controller: _scrollController,
                      cacheExtent: 800,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _dataList.length,
                      itemBuilder: (ctx, i) => _buildProductCard(
                        item: _dataList[i],
                        index: i,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // 搜索输入框
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
                      hintText: '请输入条码/品名/自编码',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 有输入内容时显示清空按钮
                          if (value.text.isNotEmpty)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                // 仅清空输入框，保留已扫码商品列表（对齐小程序清空输入行为）
                                _searchController.clear();
                              },
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
                      fillColor: const Color(0xFFF5F5F5),
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
                    style: const TextStyle(fontSize: 13),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 自定义商品按钮
          _buildIconButton(
            icon: Icons.tune,
            onTap: _openSelectProduct,
          ),
          const SizedBox(width: 8),
          // 单据按钮
          _buildIconButton(
            icon: Icons.add,
            onTap: () => _openReceiptsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: _borderColor),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(icon, size: 22, color: _textColor),
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
              onTap: _showBatchModifyDialog,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: _primaryColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: const Text('批量修改', style: TextStyle(fontSize: 15, color: _primaryColor)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 打印标签
          Expanded(
            child: GestureDetector(
              onTap: _print,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: _primaryColor,
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

/// 步进器组件（打印份数 1-20）
class _Stepper extends StatelessWidget {
  const _Stepper({
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
