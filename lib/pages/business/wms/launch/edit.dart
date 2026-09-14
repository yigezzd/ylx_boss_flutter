import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_location.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/launch/common.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 上架执行页（对齐 Vue wms/launch/edit.vue）
class WmsLaunchEditPage extends StatefulWidget {
  const WmsLaunchEditPage({super.key, required this.activeTab, required this.data});

  /// '0'=按单据 '1'=按商品
  final String activeTab;

  /// 上一页面传入的完整数据（对齐 Vue eventChannel acceptLaunchData）
  final Map<String, dynamic> data;

  @override
  State<WmsLaunchEditPage> createState() => _WmsLaunchEditPageState();
}

class _WmsLaunchEditPageState extends State<WmsLaunchEditPage> {
  /// 查询/提交数据（对齐 Vue query）
  late Map<String, dynamic> _query;

  /// 按 billid 分组数据（扫托盘码场景）
  List<Map<String, dynamic>> _billGroupedList = [];

  /// 商品明细展示列表
  List<Map<String, dynamic>> _mergeDetails = [];

  /// 货位号列表
  List<Map<String, dynamic>> _locationList = [];
  bool _locationLoaded = false;
  String _selectedLocationId = '';

  /// 明细中提取的收货暂存货位号 / 货位 id（对齐 Vue locationcode/locationid ref）
  String _displayLocationcode = '';
  String _initLocationId = '';

  bool _hasPerm = false;
  bool _saving = false;

  String _storeId = '';

  @override
  void initState() {
    super.initState();
    _hasPerm = PermissionUtils.checkPermission('011902', showTip: false);
    _loadLocalInfo();
    _initData();
    _loadLocationList();
  }

  void _loadLocalInfo() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeId = storeMap['id']?.toString() ?? '';
      }
    } catch (_) {}
  }

  /// 初始化数据（对齐 Vue eventChannel.on('acceptLaunchData')）
  void _initData() {
    final data = widget.data;
    _query = Map<String, dynamic>.from(data);
    _query['lunchqty'] = data['sumlunchqty'] ?? 0;

    // 存储按 billid 分组的数据（扫托盘码场景）
    final bg = data['billGroupedList'];
    if (bg is List && bg.isNotEmpty) {
      _billGroupedList = bg.whereType<Map<String, dynamic>>().toList();
    }

    // 处理商品明细：提取货位/托盘信息并补充 price/amt
    final detaillist = data['detaillist'];
    if (detaillist is List) {
      _query['detaillist'] = detaillist.whereType<Map<String, dynamic>>().map((c) {
        final lc = c['locationcode']?.toString() ?? '';
        if (lc.isNotEmpty) {
          _query['locationcode'] = lc;
          _displayLocationcode = lc;
        }
        final pc = c['palletcode']?.toString() ?? '';
        if (pc.isNotEmpty) _query['palletcode'] = pc;
        final li = c['locationid']?.toString() ?? '';
        if (li.isNotEmpty) _initLocationId = li;
        _handleProperty(c);
        return c;
      }).toList();
    }

    final md = data['mergeDetails'];
    if (md is List) {
      _mergeDetails = md.whereType<Map<String, dynamic>>().map((c) {
        _handleProperty(c);
        return c;
      }).toList();
    }

    // 如果传入了已选货位，设置勾选
    final qlid = _query['locationid']?.toString() ?? '';
    if (qlid.isNotEmpty) _selectedLocationId = qlid;
  }

  /// 对齐 Vue handleProperty：补充 productname/price/amt
  void _handleProperty(Map<String, dynamic> v) {
    final name = v['productname']?.toString() ?? '';
    if (name.isEmpty) v['productname'] = v['name'];
    final price = MathUtils.formatDecimal(2, _firstTruthyNum([v['cgprice'], v['price'], 0]));
    v['price'] = price;
    v['amt'] = MathUtils.formatDecimal(
      3,
      MathUtils.multiply(_num(v['qty']), double.tryParse(price) ?? 0),
    );
  }

  List<Map<String, dynamic>> get _detaillist =>
      (_query['detaillist'] as List? ?? []).whereType<Map<String, dynamic>>().toList();

  /// 对齐 Vue comProNum：明细数量合计（1位小数）
  String get _comProNum {
    double sum = 0;
    for (final p in _detaillist) {
      sum = MathUtils.add(sum, _num(p['qty']));
    }
    return MathUtils.formatDecimal(1, sum);
  }

  /// 对齐 Vue comProAmt：明细金额合计（3位小数）
  String get _comProAmt {
    double sum = 0;
    for (final p in _detaillist) {
      sum = MathUtils.add(sum, _num(p['amt']));
    }
    return MathUtils.formatDecimal(3, sum);
  }

  /// 对齐 Vue comPropsAmt：批发金额合计
  String get _comPropsAmt {
    double sum = 0;
    for (final p in _detaillist) {
      sum = MathUtils.add(
        sum,
        _firstTruthyNum([p['psamt'], MathUtils.multiply(_num(p['qty']), _num(p['psprice']))]),
      );
    }
    return MathUtils.formatDecimal(3, sum);
  }

  /// 对齐 Vue comProsellAmt：零售金额合计
  String get _comProsellAmt {
    double sum = 0;
    for (final p in _detaillist) {
      sum = MathUtils.add(
        sum,
        _firstTruthyNum([p['sellamt'], MathUtils.multiply(_num(p['qty']), _num(p['sellprice']))]),
      );
    }
    return MathUtils.formatDecimal(3, sum);
  }

  /// 获取货位号列表（对齐 Vue getLocationList）
  Future<void> _loadLocationList() async {
    try {
      final result = await request(HttpApi.wmsLocationList, {
        'stopflag': '',
        'storeid': _storeId,
        'locationid': _initLocationId,
      });
      if (!mounted) return;
      final data = result['data'];
      final raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      setState(() {
        _locationList = raw.whereType<Map<String, dynamic>>().toList();
        _locationLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _locationLoaded = true);
    }
  }

  /// 选择货位号（对齐 Vue selectLocation）
  void _selectLocation(Map<String, dynamic> loc) {
    setState(() {
      _selectedLocationId = loc['locationid']?.toString() ?? '';
      _query['locationid'] = loc['locationid'];
      _query['locationcode'] = loc['locationcode'];
      _query['locationname'] = loc['locationname'];
    });
  }

  /// 扫描货位号条码（对齐 Vue scanLocation）
  Future<void> _scanLocation() async {
    final code = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute<dynamic>(builder: (_) => const QrCodeScannerPage()),
    );
    if (!mounted) return;
    final scancode = code?.toString().trim() ?? '';
    if (scancode.isEmpty) {
      Toast.show('扫描失败，请重试');
      return;
    }
    try {
      final result = await request(HttpApi.locationGetList, {
        'code': scancode,
        'is_page': 1,
        'page': 1,
        'pagesize': 1,
        'stopflag': '',
        'storeid': _storeId,
        'zonetype': 2,
      });
      if (!mounted) return;
      final data = result['data'];
      final raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      final list = raw.whereType<Map<String, dynamic>>().toList();
      if (list.isEmpty) {
        Toast.show('未查询到该货位号');
        return;
      }
      final loc = list.first;
      setState(() {
        // 去重后插入列表顶部并选中
        final exists = _locationList
            .any((item) => item['locationid']?.toString() == loc['locationid']?.toString());
        if (!exists) _locationList.insert(0, loc);
        _selectLocation(loc);
      });
      Toast.show('扫描成功');
    } catch (_) {
      if (mounted) Toast.show('查询失败');
    }
  }

  /// 绑定其他位号（对齐 Vue openGodown + selectGodownFn2）
  Future<void> _openGodown() async {
    final result = await SelectLocationPage.show(
      context,
      zonetype: 2,
      withStopflag: true,
      title: '选择货位号',
      initialSelectedId: _selectedLocationId.isNotEmpty ? _selectedLocationId : null,
    );
    if (result == null || !mounted) return;
    setState(() {
      _query['locationid'] = result['locationid'];
      _query['locationcode'] = result['locationcode'];
      _query['locationname'] = result['locationname'];
      _selectedLocationId = result['locationid']?.toString() ?? '';
      // 将选中的货位号插入列表顶部（去重）
      final exists =
          _locationList.any((item) => item['locationid']?.toString() == _selectedLocationId);
      if (!exists) {
        _locationList.insert(0, {
          'locationid': result['locationid'],
          'locationcode': result['locationcode'],
          'locationname': result['locationname'],
        });
      }
    });
  }

  /// 保存（对齐 Vue save）
  Future<void> _save() async {
    if (!_hasPerm) {
      Toast.show('你无权上架确认，请在后台修改权限');
      return;
    }
    final qLocationId = _query['locationid']?.toString() ?? '';
    if (_selectedLocationId.isEmpty && qLocationId.isEmpty) {
      Toast.show('请选择货位号');
      return;
    }
    if (_saving) return;

    // 扫托盘码场景：按单据分别提交
    if (_billGroupedList.isNotEmpty) {
      await _saveBillGrouped();
      return;
    }

    final params = Map<String, dynamic>.from(_query);
    params['billqty'] = _comProNum;
    params['billamt'] = _comProAmt;
    params['ywpsamt'] = _comPropsAmt;
    params['ywsellamt'] = _comProsellAmt;
    params['detaillist'] = _detaillist.map((c) {
      return <String, dynamic>{
        ...c,
        'locationcode': _firstTruthyStr([c['locationcode'], _query['locationcode'], '']),
        'locationid': _firstTruthyStr([c['locationid'], _query['locationid'], '']),
        'palletcode': _firstTruthyStr([c['palletcode'], _query['palletcode'], '']),
        'sellamt': _firstTruthyNum(
            [c['sellamt'], MathUtils.multiply(_num(c['qty']), _num(c['sellprice']))]),
        'psamt':
            _firstTruthyNum([c['psamt'], MathUtils.multiply(_num(c['qty']), _num(c['psprice']))]),
      };
    }).toList();

    setState(() => _saving = true);
    try {
      await request(HttpApi.wmsLaunchSave, params);
      if (!mounted) return;
      // 按单据模式：index → detail → edit，返回 2 层；按商品模式返回 1 层
      _backAfterSave(widget.activeTab == '0' ? 2 : 1);
    } catch (_) {
      // 请求层已统一提示错误
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 扫托盘码场景：按 billid 分组逐单提交（对齐 Vue saveBillGrouped）
  Future<void> _saveBillGrouped() async {
    final locationCode = _query['locationcode']?.toString() ?? '';
    final locationId = _query['locationid']?.toString() ?? '';
    final palletCode = _query['palletcode']?.toString() ?? '';

    final requests = _billGroupedList.map((bill) {
      final details =
          (bill['detaillist'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
      double qtySum = 0;
      double amtSum = 0;
      double psSum = 0;
      double sellSum = 0;
      for (final d in details) {
        final qty = _num(d['qty']);
        qtySum = MathUtils.add(qtySum, qty);
        amtSum = MathUtils.add(
          amtSum,
          MathUtils.multiply(qty, _firstTruthyNum([d['cgprice'], d['price'], 0])),
        );
        psSum = MathUtils.add(
          psSum,
          _firstTruthyNum([d['psamt'], MathUtils.multiply(qty, _num(d['psprice']))]),
        );
        sellSum = MathUtils.add(
          sellSum,
          _firstTruthyNum([d['sellamt'], MathUtils.multiply(qty, _num(d['sellprice']))]),
        );
      }
      return <String, dynamic>{
        ...bill,
        'locationcode': locationCode,
        'locationid': locationId,
        'palletcode': palletCode,
        'billqty': MathUtils.formatDecimal(1, qtySum),
        'billamt': MathUtils.formatDecimal(3, amtSum),
        'ywpsamt': MathUtils.formatDecimal(3, psSum),
        'ywsellamt': MathUtils.formatDecimal(3, sellSum),
      };
    }).toList();

    setState(() => _saving = true);
    try {
      await request(HttpApi.wmsLaunchListSave, {'receiveList': requests});
      if (!mounted) return;
      // 扫托盘码场景：index → edit，返回 1 层
      _backAfterSave(1);
    } catch (_) {
      if (mounted) Toast.show('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 保存成功后延迟返回（对齐 Vue setTimeout 1500 navigateBack）
  void _backAfterSave(int delta) {
    Toast.show('保存成功');
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      if (delta > 1 && navigator.canPop()) navigator.pop();
    });
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  /// 对齐 JS `||`：返回第一个非 0 数值
  static num _firstTruthyNum(List<dynamic> values) {
    for (final v in values) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n != null && n != 0) return n;
    }
    return 0;
  }

  /// 对齐 JS `||`：返回第一个非空字符串
  static String _firstTruthyStr(List<dynamic> values) {
    for (final v in values) {
      final s = v?.toString() ?? '';
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final bool permEnabled = _hasPerm && !_saving;
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
        title: const Text(
          '商品上架',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        cacheExtent: 800,
        children: [
          // ── 基础信息 ──
          _buildCard(
            child: Column(
              children: [
                _buildInfoRow('收货暂存货位号', _displayLocationcode),
                _buildInfoRow('托盘码', _query['palletcode']?.toString() ?? ''),
                _buildInfoRow('待上架数', MathUtils.formatDecimal(3, _query['sumlunchqty'] ?? 0)),
                _buildInfoRow('上架数量', MathUtils.formatDecimal(3, _query['lunchqty'] ?? 0),
                    isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ── 商品明细 ──
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '商品明细',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                if (_mergeDetails.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                    ),
                  )
                else
                  ..._mergeDetails.map((item) => RepaintBoundary(child: _buildProItem(item))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ── 货位号选择 ──
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '选择货位号',
                        style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
                      ),
                    ),
                    GestureDetector(
                      onTap: _scanLocation,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_scanner, size: 16, color: Color(0xFF006EFF)),
                          SizedBox(width: 2),
                          Text('扫描', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _openGodown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF006EFF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '绑定其他位号',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_locationList.isEmpty && _locationLoaded)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                    ),
                  )
                else
                  ..._locationList.map((loc) => RepaintBoundary(child: _buildLocationItem(loc))),
              ],
            ),
          ),
        ],
      ),
      // ── 底部操作按钮 ──
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          12,
          10,
          12,
          MediaQuery.of(context).padding.bottom + 10,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: permEnabled ? Colors.white : const Color(0xFFF5F5F5),
                    border: Border.all(
                      color: permEnabled ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 16,
                      color: permEnabled ? const Color(0xFF006EFF) : const Color(0xFF999999),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: permEnabled ? const Color(0xFF006EFF) : const Color(0xFFB0C8EE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _saving ? '保存中...' : '确认',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: child,
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border:
            isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// 商品明细项（对齐 Vue edit 商品明细卡片）
  Widget _buildProItem(Map<String, dynamic> item) {
    final String name = item['productname']?.toString() ?? '-';
    final String size = item['size']?.toString() ?? '';
    final String barcode = item['barcode']?.toString() ?? '';
    final String billno = _firstTruthyStr([_query['billno'], item['billno'], '']);
    final String qty = MathUtils.formatDecimal(1, item['qty'] ?? 0);
    final billflag = item['billflag']?.toString() ?? '';
    // 对齐 Vue edit：billflag=1 显示"采购入库单"
    final typeLabel = launchBillTypeLabel(billflag);
    final String flagLabel = billflag == '1' ? '$typeLabel单' : typeLabel;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E2E2), width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  size.isEmpty ? name : '$name（$size）',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                flagLabel,
                style: const TextStyle(fontSize: 12, color: Color(0xFF006EFF)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '条码：$barcode',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Text(
                  '单号：$billno',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '数量：$qty',
            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
          ),
        ],
      ),
    );
  }

  /// 货位号列表项（对齐 Vue location-item radio 选择）
  Widget _buildLocationItem(Map<String, dynamic> loc) {
    final String locationid = loc['locationid']?.toString() ?? '';
    final String locationcode = loc['locationcode']?.toString() ?? '';
    final bool selected = _selectedLocationId == locationid;
    return GestureDetector(
      onTap: () => _selectLocation(loc),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F0FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.home_outlined, size: 16, color: Color(0xFF006EFF)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '存货位：$locationcode',
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? const Color(0xFF3764FF) : const Color(0xFFCCCCCC),
            ),
          ],
        ),
      ),
    );
  }
}
