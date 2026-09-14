import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/launch/common.dart';
import 'package:flutter_deer/pages/business/wms/launch/detail.dart';
import 'package:flutter_deer/pages/business/wms/launch/edit.dart';
import 'package:flutter_deer/pages/business/wms/launch/search.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 上架列表页（对齐 Vue wms/launch/index.vue）
class WmsLaunchListPage extends StatefulWidget {
  const WmsLaunchListPage({super.key});

  @override
  State<WmsLaunchListPage> createState() => _WmsLaunchListPageState();
}

class _WmsLaunchListPageState extends State<WmsLaunchListPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// 0=按单据 1=按商品（对齐 Vue activeTab）
  int _activeTab = 0;

  /// 搜索条件（搜索页回显用）
  String _cond = '';

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  int _requestSeq = 0;

  final List<Map<String, dynamic>> _billList = [];
  final List<Map<String, dynamic>> _productList = [];

  final ScrollController _scrollController = ScrollController();

  String _storeId = '';
  String _storeName = '';

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _onTabChange(_tabController.index);
      }
    });
    _scrollController.addListener(_onScroll);
    _loadLocalInfo();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 读取当前门店信息
  void _loadLocalInfo() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeId = storeMap['id']?.toString() ?? '';
        _storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
  }

  void _onTabChange(int index) {
    // 对齐 Vue tabsChange：切换 tab 清空搜索条件并重新查询
    setState(() {
      _activeTab = index;
      _cond = '';
      _page = 1;
      _hasMore = true;
    });
    _loadData();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  List<Map<String, dynamic>> get _currentList => _activeTab == 0 ? _billList : _productList;

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    final int seq = ++_requestSeq;
    final bool isFirstPage = _page == 1;
    final String apiUrl = _activeTab == 0 ? HttpApi.wmsLaunchList : HttpApi.wmsLaunchProList;

    final params = <String, dynamic>{
      'is_page': 1,
      // 对齐 Vue：按单据按制单时间排序，按商品不排序
      'field': _activeTab == 0 ? 'createtime' : 'billno',
      'type': 'desc',
      'page': _page,
      'pagesize': _pageSize,
      'sids': [_storeId],
      'sidsname': _storeName,
      'cond': _cond,
    };

    return request(apiUrl, params).then((result) {
      if (seq != _requestSeq || !mounted) return;
      final data = result['data'];
      final raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      final rows = raw.whereType<Map<String, dynamic>>().toList();
      setState(() {
        final target = _currentList;
        if (isFirstPage) {
          target
            ..clear()
            ..addAll(rows);
        } else {
          target.addAll(rows);
        }
        _hasMore = rows.length >= _pageSize;
      });
    }).catchError((_) {
      if (seq != _requestSeq || !mounted) return;
      setState(() => _hasMore = false);
    }).whenComplete(() {
      if (seq == _requestSeq && mounted) {
        setState(() => _loading = false);
      }
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  /// 打开搜索页（对齐 Vue 点击搜索框跳转 search?mode=activeTab）
  Future<void> _openSearch() async {
    await Navigator.push(
      context,
      MaterialPageRoute<dynamic>(
        builder: (_) => WmsLaunchSearchPage(mode: _activeTab.toString()),
      ),
    );
    // 对齐 Vue onShow：返回后刷新列表
    _onRefresh();
  }

  /// 搜索框内嵌扫码：按商品模式下扫商品条码搜索（对齐 Vue scanFn）
  Future<void> _scanPro() async {
    final code = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute<dynamic>(builder: (_) => const QrCodeScannerPage()),
    );
    if (!mounted) return;
    final scancode = code?.toString().trim() ?? '';
    if (scancode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    setState(() {
      _cond = scancode;
      _page = 1;
      _hasMore = true;
    });
    _loadData();
  }

  /// 悬浮按钮扫托盘码（对齐 Vue scanTrayFn）
  Future<void> _scanTray() async {
    final code = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute<dynamic>(builder: (_) => const QrCodeScannerPage()),
    );
    if (!mounted) return;
    final palletcode = code?.toString().trim() ?? '';
    if (palletcode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    try {
      final result = await request(HttpApi.wmsLaunchListByTray, {'palletcode': palletcode});
      if (!mounted) return;
      final data = result['data'];
      final raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      final billlist = raw.whereType<Map<String, dynamic>>().toList();
      if (billlist.isEmpty) {
        Toast.show('未找到该托盘的上架数据');
        return;
      }

      // 按 billid 分组（接口已分组），展平明细用于展示
      final List<Map<String, dynamic>> flat = [];
      for (final bill in billlist) {
        final details =
            (bill['detaillist'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
        double lunch = 0;
        for (final d in details) {
          lunch = MathUtils.add(lunch, _num(d['qty']));
        }
        bill['lunchqty'] = lunch;
        final mapped = details
            .map((d) => <String, dynamic>{...d, 'lunchqty': d['qty'], 'billno': bill['billno']})
            .toList();
        bill['detaillist'] = mapped;
        flat.addAll(mapped);
      }
      double sumlunchqty = 0;
      double lunchqty = 0;
      for (final d in flat) {
        sumlunchqty = MathUtils.add(sumlunchqty, _num(d['qty']));
        lunchqty = MathUtils.add(lunchqty, _num(d['lunchqty']));
      }

      await Navigator.push(
        context,
        MaterialPageRoute<dynamic>(
          builder: (_) => WmsLaunchEditPage(
            activeTab: '0',
            data: {
              'sumlunchqty': sumlunchqty,
              'lunchqty': lunchqty,
              'palletcode': palletcode,
              'mergeDetails': flat,
              'detaillist': flat,
              'billGroupedList': billlist,
            },
          ),
        ),
      );
      if (mounted) _onRefresh();
    } catch (_) {
      if (mounted) Toast.show('查询失败，请重试');
    }
  }

  /// 按单据点击（对齐 Vue selectItemFn）
  Future<void> _selectBillItem(Map<String, dynamic> item) async {
    if (!PermissionUtils.checkPermission('011901')) return;
    await Navigator.push(
      context,
      MaterialPageRoute<dynamic>(
        builder: (_) => WmsLaunchDetailPage(billInfo: Map<String, dynamic>.from(item)),
      ),
    );
    if (mounted) _onRefresh();
  }

  /// 按商品点击（对齐 Vue selectProItemFn）
  Future<void> _selectProItem(Map<String, dynamic> item) async {
    if (!PermissionUtils.checkPermission('011901')) return;
    item['qty'] = item['billqty'];
    await Navigator.push(
      context,
      MaterialPageRoute<dynamic>(
        builder: (_) => WmsLaunchEditPage(
          activeTab: '1',
          data: {
            'activeTab': '1',
            'billid': item['billid'],
            'billflag': item['billflag'],
            'billno': item['billno'],
            'locationcode': item['locationcode'] ?? '',
            'locationid': item['locationid'] ?? '',
            'palletcode': item['palletcode'] ?? '',
            'sumlunchqty': item['billqty'] ?? 0,
            'bsid': item['bsid'] ?? '',
            'counterid': item['counterid'] ?? '',
            'detaillist': [item],
            'mergeDetails': [item],
          },
        ),
      ),
    );
    if (mounted) _onRefresh();
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final list = _currentList;
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
          '上架',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(92),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                // ── Tab 栏 ──
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF006EFF),
                  unselectedLabelColor: const Color(0xFF6B7280),
                  indicatorColor: const Color(0xFF006EFF),
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 14),
                  tabs: const [
                    Tab(text: '按单据'),
                    Tab(text: '按商品'),
                  ],
                ),
                // ── 搜索框（点击跳搜索页，对齐 Vue）──
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                  child: GestureDetector(
                    onTap: _openSearch,
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        border: Border.all(color: const Color(0xFFDEDEDE)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _cond.isNotEmpty
                                  ? _cond
                                  : (_activeTab == 0 ? '请输入单号' : '输入条码/品名/自编码'),
                              style: TextStyle(
                                fontSize: 13,
                                color: _cond.isNotEmpty
                                    ? const Color(0xFF333333)
                                    : const Color(0xFF8B8B8B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_activeTab == 1)
                            GestureDetector(
                              onTap: _scanPro,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(
                                  Icons.qr_code_scanner,
                                  size: 18,
                                  color: Color(0xFF006EFF),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: const Color(0xFF006EFF),
            onRefresh: _onRefresh,
            child: list.isEmpty && !_loading
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                            SizedBox(height: 12),
                            Text(
                              '暂无数据',
                              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                    cacheExtent: 800,
                    itemCount: list.length + (_loading ? 1 : (_hasMore ? 0 : 1)),
                    itemBuilder: (context, index) {
                      if (index == list.length) {
                        return _loading
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF006EFF),
                                    ),
                                  ),
                                ),
                              )
                            : const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Text(
                                    '没有更多数据',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                  ),
                                ),
                              );
                      }
                      final item = list[index];
                      return RepaintBoundary(
                        child: _activeTab == 0
                            ? LaunchBillCard(item: item, onTap: () => _selectBillItem(item))
                            : LaunchProCard(item: item, onTap: () => _selectProItem(item)),
                      );
                    },
                  ),
          ),
          // ── 悬浮扫托盘码按钮（对齐 Vue float-scan-btn）──
          Positioned(
            right: 20,
            bottom: 40,
            child: GestureDetector(
              onTap: _scanTray,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE8F0FF)),
                ),
                child: const Icon(Icons.qr_code_scanner, size: 26, color: Color(0xFF006EFF)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
