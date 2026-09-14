import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_location.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/stockQuery/move_goods.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 货位库存查询页（对齐 Vue wms/stockQuery/index.vue）
class WmsStockQueryPage extends StatefulWidget {
  const WmsStockQueryPage({super.key});

  @override
  State<WmsStockQueryPage> createState() => _WmsStockQueryPageState();
}

class _WmsStockQueryPageState extends State<WmsStockQueryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// 0=商品库存 1=货位库存（对齐 Vue activeTab）
  int _activeTab = 0;

  // ── 仓库（两 tab 共用）──
  String _selectedCounterId = '';
  String _selectedCounterName = '';

  // ── 商品（商品库存 tab）──
  String _selectedProductId = '';
  Map<String, dynamic> _selectedProduct = {};
  Map<String, dynamic>? _productInfo;

  // ── 货位号（货位库存 tab）──
  String _selectedLocationId = '';
  String _selectedLocationCode = '';

  // ── 库存数据 ──
  final List<Map<String, dynamic>> _stockList = [];
  bool _dataLoaded = false;
  double _sumqty = 0;

  String _storeId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _onTabChange(_tabController.index);
      }
    });
    _loadLocalInfo();
    _initDefaultCounter();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  /// 初始化默认仓库（对齐 Vue onLoad：读取 wms 设置 type=31）
  Future<void> _initDefaultCounter() async {
    try {
      final result = await request(HttpApi.wmsSetGet, {'type': 31});
      if (!mounted) return;
      final res = result['data'];
      final wmscounterid =
          (res is Map<String, dynamic> ? res['wmscounterid'] : null)?.toString() ?? '';
      if (wmscounterid.isEmpty) return;
      _selectedCounterId = wmscounterid;
      // 获取仓库名称（与选择弹窗一致：排除零售仓 countertype=0，对齐 Vue countertype: "1,2,3,4"）
      final counterResult = await request(HttpApi.counterGetList, {
        'sids': [_storeId],
        'nosidsflag': 1,
        'stopflag': 0,
        'countertype': '1,2,3,4',
      });
      if (!mounted) return;
      // 用户已手动改选时，不再应用默认仓库解析结果，避免异步覆盖（对齐 Vue）
      if (_selectedCounterId != wmscounterid) return;
      final counterData = counterResult['data'];
      final list =
          (counterData is Map<String, dynamic> ? counterData['list'] : null) as List? ?? [];
      String? foundName;
      for (final c in list.whereType<Map<String, dynamic>>()) {
        if (c['counterid']?.toString() == wmscounterid) {
          foundName = c['countername']?.toString() ?? '';
          break;
        }
      }
      // 对齐 Vue：默认仓库为零售仓（已不可选）时清空，避免已选值不在可选项内
      setState(() {
        if (foundName != null) {
          _selectedCounterName = foundName;
        } else {
          _selectedCounterId = '';
          _selectedCounterName = '';
        }
      });
    } catch (_) {}
  }

  /// 切换 tab（对齐 Vue tabsChange：清空数据，条件满足时自动查询）
  void _onTabChange(int index) {
    setState(() {
      _activeTab = index;
      _stockList.clear();
      _dataLoaded = false;
      _productInfo = null;
    });
    if (_activeTab == 0 && _selectedCounterId.isNotEmpty && _selectedProductId.isNotEmpty) {
      _queryStockByProduct();
    } else if (_activeTab == 1 && _selectedCounterId.isNotEmpty && _selectedLocationId.isNotEmpty) {
      _queryStockByShelf();
    }
  }

  /// 选择仓库（对齐 Vue selectCom counter，接口 bi/counter/getList）
  Future<void> _openCounterSelect() async {
    Future<Map<String, dynamic>?> fetchData(String searchText, int page) {
      return request(HttpApi.counterGetList, {
        'sids': [_storeId],
        'nosidsflag': 1,
        'stopflag': 0,
        'countertype': '1,2,3,4',
        'cond': searchText,
        'is_page': 1,
        'page': page,
      }).then((result) {
        final data = result['data'];
        return data is Map<String, dynamic> ? data : null;
      });
    }

    final result = await CommonSelectSheet.show(
      context,
      title: '选择仓库',
      searchHint: '输入仓库名称/编码',
      fetchData: fetchData,
      nameField: 'countername',
      codeField: 'countercode',
      idField: 'counterid',
      initialSelectedId: _selectedCounterId.isNotEmpty ? _selectedCounterId : null,
      mapResult: (item) => {
        'counterid': item['counterid']?.toString() ?? '',
        'countername': item['countername']?.toString() ?? '',
      },
    );
    if (result == null || !mounted) return;
    // 对齐 Vue onCounterSelected：切换仓库后清空已有数据
    setState(() {
      _selectedCounterId = result['counterid']?.toString() ?? '';
      _selectedCounterName = result['countername']?.toString() ?? '';
      _stockList.clear();
      _dataLoaded = false;
      _productInfo = null;
      _selectedProductId = '';
      _selectedProduct = {};
      _selectedLocationId = '';
      _selectedLocationCode = '';
    });
  }

  /// 选择商品（对齐 Vue openProductSelect）
  Future<void> _openProductSelect() async {
    if (_selectedCounterId.isEmpty) {
      Toast.show('请先选择仓库');
      return;
    }
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => const SelectProductPage(
          mergData: {
            'stockflag': 1,
            'cgpriceflag': 1,
            'itemstatusin': '1,2,3,4',
            'itemtypenot': '5,8',
          },
          // 对齐 Vue openProductSelect：checked=1 && multiple=false → 单选 radio 模式
          singleSelectMode: true,
        ),
      ),
    );
    if (!mounted) return;
    final item = (result != null && result.isNotEmpty) ? result.first : null;
    if (item == null) return;
    setState(() {
      _selectedProductId = item['productid']?.toString() ?? '';
      _selectedProduct = item;
    });
    _queryStockByProduct();
  }

  /// 选择货位号（对齐 Vue openLocationSelect）
  Future<void> _openLocationSelect() async {
    if (_selectedCounterId.isEmpty) {
      Toast.show('请先选择仓库');
      return;
    }
    final result = await SelectLocationPage.show(
      context,
      zonetype: null,
      withStopflag: true,
      counterid: _selectedCounterId,
      title: '选择货位号',
      initialSelectedId: _selectedLocationId.isNotEmpty ? _selectedLocationId : null,
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedLocationId = result['locationid']?.toString() ?? '';
      _selectedLocationCode = result['locationcode']?.toString() ?? '';
    });
    _queryStockByShelf();
  }

  /// 查询商品库存（对齐 Vue queryStockByProduct）
  Future<void> _queryStockByProduct() async {
    if (_selectedCounterId.isEmpty || _selectedProductId.isEmpty) return;
    try {
      final result = await request(HttpApi.wmsStockByProduct, {
        'prolist': [_selectedProductId],
        'counterid': _selectedCounterId,
      });
      if (!mounted) return;
      final res = result['data'];
      final raw = (res is Map<String, dynamic> ? res['list'] : res) as List? ?? [];
      final list = raw.whereType<Map<String, dynamic>>().toList();
      final sumdata = res is Map<String, dynamic> ? res['sumdata'] : null;
      setState(() {
        _dataLoaded = true;
        _sumqty = _num(sumdata is Map ? sumdata['sumqty'] : null);
        if (list.isNotEmpty) {
          _productInfo = list.first;
          final locationlist = list.first['locationlist'];
          _stockList
            ..clear()
            ..addAll((locationlist is List ? locationlist : raw).whereType<Map<String, dynamic>>());
        } else {
          _productInfo = null;
          _stockList.clear();
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _dataLoaded = true;
          _stockList.clear();
        });
      }
    }
  }

  /// 查询货位库存（对齐 Vue queryStockByShelf）
  Future<void> _queryStockByShelf() async {
    if (_selectedCounterId.isEmpty || _selectedLocationId.isEmpty) return;
    try {
      final result = await request(HttpApi.wmsStockSumByShelf, {
        'locationlist': [_selectedLocationId],
        'counterid': _selectedCounterId,
      });
      if (!mounted) return;
      final res = result['data'];
      final raw = (res is Map<String, dynamic> ? res['list'] : res) as List? ?? [];
      setState(() {
        _dataLoaded = true;
        _stockList
          ..clear()
          ..addAll(raw.whereType<Map<String, dynamic>>());
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _dataLoaded = true;
          _stockList.clear();
        });
      }
    }
  }

  /// 打开移货页面（对齐 Vue openMoveGoods）
  Future<void> _openMoveGoods(Map<String, dynamic> item) async {
    // 根据当前 Tab 确定商品信息来源
    final Map<String, dynamic> productInfo = _activeTab == 0
        ? {
            'productname': _selectedProduct['name']?.toString() ?? '',
            'size': _selectedProduct['size']?.toString() ?? '',
            'productid': _selectedProductId,
          }
        : {
            'productname': item['name']?.toString() ?? '',
            'size': item['size']?.toString() ?? '',
            'productid': item['productid']?.toString() ?? '',
          };

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => WmsMoveGoodsPage(
          data: {
            ...item,
            'counterid': _selectedCounterId,
            'countername': _selectedCounterName,
            // 货位库存 Tab 下 item 里没有货位信息，从页面状态补充
            'fromlocationid': item['locationid']?.toString() ?? _selectedLocationId,
            'fromlocationcode': item['locationcode']?.toString() ?? _selectedLocationCode,
            ...productInfo,
          },
        ),
      ),
    );
    // 对齐 Vue acceptMoveData：移货成功后按当前 tab 刷新
    if ((result ?? false) && mounted) {
      if (_activeTab == 0) {
        _queryStockByProduct();
      } else {
        _queryStockByShelf();
      }
    }
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

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
        title: const Text(
          '货位库存查询',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(136),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF006EFF),
                  unselectedLabelColor: const Color(0xFF6B7280),
                  indicatorColor: const Color(0xFF006EFF),
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 14),
                  tabs: const [
                    Tab(text: '商品库存'),
                    Tab(text: '货位库存'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Column(
                    children: [
                      _buildFilterRow(
                        label: '仓库',
                        value: _selectedCounterName.isNotEmpty ? _selectedCounterName : '请选择',
                        isPlaceholder: _selectedCounterName.isEmpty,
                        onTap: _openCounterSelect,
                      ),
                      if (_activeTab == 0)
                        _buildFilterRow(
                          label: '商品',
                          value: _selectedProduct['name']?.toString().isNotEmpty ?? false
                              ? _selectedProduct['name'].toString()
                              : '请选择',
                          isPlaceholder: _selectedProduct['name']?.toString().isEmpty ?? true,
                          onTap: _openProductSelect,
                          isLast: true,
                        )
                      else
                        _buildFilterRow(
                          label: '货位号',
                          value: _selectedLocationCode.isNotEmpty ? _selectedLocationCode : '请选择',
                          isPlaceholder: _selectedLocationCode.isEmpty,
                          onTap: _openLocationSelect,
                          isLast: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        cacheExtent: 800,
        children: [
          // ── 库存明细标题 ──
          if (_stockList.isNotEmpty || _dataLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                '货位库存明细',
                style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
              ),
            ),
          if (_activeTab == 0) ...[
            // ── 商品信息卡片 ──
            if (_productInfo != null) _buildProductInfoCard(),
            if (_stockList.isNotEmpty)
              ..._stockList.map((item) => RepaintBoundary(
                    child: _StockItemCard(
                      item: item,
                      showLocation: true,
                      onMove: () => _openMoveGoods(item),
                    ),
                  ))
            else if (_dataLoaded && _selectedProductId.isNotEmpty)
              _buildEmpty(),
          ] else ...[
            if (_stockList.isNotEmpty)
              ..._stockList.map((item) => RepaintBoundary(
                    child: _StockItemCard(
                      item: item,
                      showLocation: false,
                      onMove: () => _openMoveGoods(item),
                    ),
                  ))
            else if (_dataLoaded && _selectedLocationId.isNotEmpty)
              _buildEmpty(),
          ],
          // ── 未选择时的提示（对齐 Vue empty-tip）──
          if (!_dataLoaded && _stockList.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(
                child: Text(
                  _activeTab == 0 ? '请选择仓库和商品查询库存' : '请选择仓库和货位号查询库存',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductInfoCard() {
    final info = _productInfo!;
    final String name = info['name']?.toString() ?? info['productname']?.toString() ?? '-';
    final String size = info['size']?.toString() ?? '';
    final String batchno = info['batchno']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '总库存：${MathUtils.formatDecimal(2, _sumqty)}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF)),
              ),
            ],
          ),
          if (batchno.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(batchno, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ],
          if (_stockList.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF9900),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${_stockList.length}',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '货位库存明细',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildEmpty() {
    return const Padding(
      padding: EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow({
    required String label,
    required String value,
    required bool isPlaceholder,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: isPlaceholder ? const Color(0xFF999999) : const Color(0xFF111827),
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF999999)),
          ],
        ),
      ),
    );
  }
}

/// 货位库存明细卡片（对齐 Vue stockQuery/index.vue 明细项）
class _StockItemCard extends StatelessWidget {
  const _StockItemCard({
    required this.item,
    required this.showLocation,
    required this.onMove,
  });

  final Map<String, dynamic> item;

  /// true=商品库存 tab（显示货位号），false=货位库存 tab（显示商品名）
  final bool showLocation;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final String qty = MathUtils.formatDecimal(2, item['qty'] ?? 0);
    final String batchno = item['batchno']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLocation)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '货位：${item['locationcode']?.toString() ?? ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF006EFF),
                    ),
                  ),
                ),
                Text(
                  '库存：$qty',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['name']?.toString() ?? '') +
                            ((item['size']?.toString().isNotEmpty ?? false)
                                ? ' (${item['size']})'
                                : ''),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                          height: 1.4,
                        ),
                      ),
                      if (batchno.isNotEmpty)
                        Text(
                          batchno,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '库存：$qty',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  showLocation ? batchno : '',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: onMove,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF006EFF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '移货',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
