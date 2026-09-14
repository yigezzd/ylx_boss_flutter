import 'dart:async';
import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:sp_util/sp_util.dart';

/// 优惠券分析
/// 参考 D:\VUE\ylx-boss\src\subs\data\member\couponAnalysis\couponAnalysis.vue
class CouponAnalysisPage extends StatefulWidget {
  const CouponAnalysisPage({super.key});
  @override
  State<CouponAnalysisPage> createState() => _CouponAnalysisPageState();
}

class _CouponAnalysisPageState extends State<CouponAnalysisPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  // ── 列表状态 ──
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时表格闪屏）
  bool _hasLoadedOnce = false;

  // ── 门店 ──
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';

  // ── 排序 ──
  String _sortField = '';
  String _sortType = 'desc';

  // ── 汇总 ──
  Map<String, dynamic> _sumData = {};

  // ── 礼券类型 ──
  String _ftype = '';
  String _ftypeName = '';

  static const _statusList = ['全部', '未生效', '生效中', '已过期', '已终止', '已作废'];
  static const _statusValues = ['-1', '0', '1', '3', '4', '5'];
  static const _ftypeList = ['全部类型', '代金券', '充值券', '折扣券'];
  static const _ftypeValues = ['', '1', '2', '3'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusList.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
        _page = 1;
        _hasMore = true;
        _loadData();
      }
    });
    _loadStore();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    try {
      final s = SpUtil.getString('store') ?? '';
      if (s.isNotEmpty) {
        final m = jsonDecode(s);
        final id = m['id']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _storeName = m['name']?.toString() ?? '';
            _activeStoreId = id;
            _sids = id.isNotEmpty ? [int.tryParse(id) ?? 0] : [];
          });
          _loadData();
        }
      }
    } catch (_) {}
  }

  Future<void> _selectStore() async {
    final r = await SelectStorePage.show(context, showAll: true, initialSelectedId: _activeStoreId);
    if (r != null && mounted) {
      setState(() {
        final storeId = r['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
        _storeName = r['storename']?.toString() ?? '';
        _page = 1;
        _hasMore = true;
        if (!_hasLoadedOnce) _list = [];
      });
      _loadData();
    }
  }

  static String _formatDecimal(int digits, dynamic v) {
    final num n = v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
    return n.toStringAsFixed(digits);
  }

  String get _status => _statusValues[_tabIndex];

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final r = await request(HttpApi.vipFavourableAnalysisList, {
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        'sids': _sids,
        'sidsname': _storeName,
        'status': _status,
        if (_ftype.isNotEmpty) 'ftype': _ftype,
        if (_sortField.isNotEmpty) 'field': _sortField,
        if (_sortType.isNotEmpty) 'type': _sortType,
      });
      final data = r['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      final sumdata = map['sumdata'];
      if (mounted) {
        setState(() {
          if (_page == 1) {
            _list = list;
          } else {
            _list.addAll(list);
          }
          _hasMore = list.length >= 20;
          if (_hasMore) _page++;
          _hasLoadedOnce = true;
          if (sumdata is Map<String, dynamic>) {
            _sumData = sumdata;
          } else {
            _sumData = {};
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _onSort(String f, String t) {
    setState(() {
      _sortField = f;
      _sortType = t;
    });
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  void _showFtypePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 50,
                child: Row(children: [
                  const SizedBox(width: 48),
                  const Expanded(
                    child: Text('选择礼券类型',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
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
              const Divider(height: 1),
              for (var i = 0; i < _ftypeList.length; i++)
                ListTile(
                  title: Text(_ftypeList[i],
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ftype == _ftypeValues[i]
                              ? const Color(0xFF006EFF)
                              : const Color(0xFF333333))),
                  trailing: _buildRadio(_ftype == _ftypeValues[i]),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _ftype = _ftypeValues[i];
                      _ftypeName = _ftypeList[i];
                      _page = 1;
                      _hasMore = true;
                    });
                    _loadData();
                  },
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildRadio(bool isSelected) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB), width: 2),
      ),
      child: isSelected
          ? Center(
              child: Container(
                  width: 10,
                  height: 10,
                  decoration:
                      const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF006EFF))))
          : null,
    );
  }

  // ==================== 核心概况（参考 cashier_monitoring_page） ====================

  Widget _buildOverview() {
    final items = [
      {'text': '发放数量', 'amt': _formatDecimal(0, _sumData['favcount'] ?? 0)},
      {'text': '领取数量', 'amt': _formatDecimal(0, _sumData['leavecount'] ?? 0)},
      {'text': '核销数量', 'amt': _formatDecimal(0, _sumData['usecount'] ?? 0)},
      {'text': '核销用户', 'amt': _formatDecimal(0, _sumData['usercount'] ?? 0)},
      {'text': '核销订单数', 'amt': _formatDecimal(0, _sumData['sumordercount'] ?? 0)},
      {'text': '核销金额', 'amt': _formatDecimal(2, _sumData['billamt'] ?? 0)},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('核心概况',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(item['text']!, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                const SizedBox(height: 4),
                Text(item['amt']!,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
              ]),
            );
          },
        ),
      ]),
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('优惠券分析', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: ColoredBox(
            color: Colors.white,
            child: Column(children: [
              // 门店 + 类型选择
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(children: [
                  Expanded(
                    child: _buildDropBtn(
                        label: _storeName.isNotEmpty ? _storeName : '全部机构', onTap: _selectStore),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDropBtn(
                        label: _ftypeName.isNotEmpty ? _ftypeName : '全部类型',
                        onTap: _showFtypePicker),
                  ),
                ]),
              ),
              // Tab 状态
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: const Color(0xFF006EFF),
                unselectedLabelColor: const Color(0xFF666666),
                indicatorColor: const Color(0xFF006EFF),
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: _statusList.map((t) => Tab(text: t)).toList(),
              ),
            ]),
          ),
        ),
      ),
      body: Column(children: [
        _buildOverview(),
        const SizedBox(height: 10),
        Expanded(
          child: _buildTableContent(),
        ),
      ]),
    );
  }

  Widget _buildDropBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
        ]),
      ),
    );
  }

  /// 居中加载图标卡片（无全屏遮罩，避免加载中页面泛白）
  static const Widget _loadingCard = Positioned.fill(
    child: Center(
      child: SizedBox(
        width: 72,
        height: 72,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border.fromBorderSide(BorderSide(color: Color(0xFFE1E9F3))),
          ),
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF)),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildTableContent() {
    if (_list.isEmpty && (!_loading || _hasLoadedOnce)) {
      // 空态：加载完成无数据，或已加载过刷新中（保留空态+图标卡片，避免表格骨架闪屏）
      return Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: _onRefresh,
          child: ListView(children: const [
            SizedBox(height: 200),
            Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
              SizedBox(height: 12),
              Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
            ])),
          ]),
        ),
        if (_loading) _loadingCard,
      ]);
    }
    return Stack(children: [
      _buildTable(),
      if (_loading && _hasLoadedOnce && _page == 1) _loadingCard,
    ]);
  }

  Widget _buildTable() {
    const hs = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.axis == Axis.vertical &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
            _hasMore &&
            !_loading) {
          _loadData();
        }
        return false;
      },
      child: DataTable2(
        horizontalMargin: 0,
        columnSpacing: 0,
        dataRowHeight: 52,
        headingRowHeight: 44,
        minWidth: 1200,
        fixedLeftColumns: 1,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
        border: const TableBorder(
          horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
          verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
        ),
        columns: [
          const DataColumn2(
              fixedWidth: 140,
              label: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8), child: Text('优惠券名称', style: hs))),
          DataColumn2(
              numeric: true,
              size: ColumnSize.S,
              label: _sortHeader('发放数量', 'favcount'),
              onSort: (_, __) => _onSort(
                  'favcount', _sortField == 'favcount' && _sortType == 'asc' ? 'desc' : 'asc')),
          DataColumn2(
              numeric: true,
              size: ColumnSize.S,
              label: _sortHeader('领取数量', 'leavecount'),
              onSort: (_, __) => _onSort(
                  'leavecount', _sortField == 'leavecount' && _sortType == 'asc' ? 'desc' : 'asc')),
          const DataColumn2(
              size: ColumnSize.S,
              label: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8), child: Text('领取率', style: hs))),
          DataColumn2(
              numeric: true,
              size: ColumnSize.S,
              label: _sortHeader('核销数量', 'usecount'),
              onSort: (_, __) => _onSort(
                  'usecount', _sortField == 'usecount' && _sortType == 'asc' ? 'desc' : 'asc')),
          const DataColumn2(
              size: ColumnSize.S,
              label: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8), child: Text('核销率', style: hs))),
          DataColumn2(
              numeric: true,
              size: ColumnSize.S,
              label: _sortHeader('核销用户数', 'usercount'),
              onSort: (_, __) => _onSort(
                  'usercount', _sortField == 'usercount' && _sortType == 'asc' ? 'desc' : 'asc')),
          DataColumn2(
              numeric: true,
              size: ColumnSize.S,
              label: _sortHeader('核销订单数', 'sumordercount'),
              onSort: (_, __) => _onSort('sumordercount',
                  _sortField == 'sumordercount' && _sortType == 'asc' ? 'desc' : 'asc')),
          DataColumn2(
              numeric: true,
              size: ColumnSize.S,
              label: _sortHeader('核销金额', 'billamt'),
              onSort: (_, __) => _onSort(
                  'billamt', _sortField == 'billamt' && _sortType == 'asc' ? 'desc' : 'asc')),
        ],
        rows: [
          for (var i = 0; i < _list.length; i++) _buildRow(_list[i], i),
          // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
          if (_loading && (_page > 1 || !_hasLoadedOnce))
            DataRow(cells: [
              const DataCell(SizedBox(
                  height: 44,
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF006EFF)))))),
              for (int j = 1; j < 9; j++) DataCell.empty,
            ]),
        ],
      ),
    );
  }

  DataRow2 _buildRow(Map<String, dynamic> row, int index) {
    const cs = TextStyle(fontSize: 13, color: Color(0xFF333333));
    return DataRow2(
      decoration: BoxDecoration(
        color: index.isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['name']?.toString() ?? '', style: cs))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_formatDecimal(0, row['favcount']), style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_formatDecimal(0, row['leavecount']), style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('${row['leaverate']?.toString() ?? '0'}%', style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_formatDecimal(0, row['usecount']), style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('${row['userate']?.toString() ?? '0'}%', style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_formatDecimal(0, row['usercount']), style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_formatDecimal(0, row['sumordercount']), style: cs)))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_formatDecimal(2, row['billamt']), style: cs)))),
      ],
    );
  }

  Widget _sortHeader(String label, String field) {
    final isActive = _sortField == field;
    final isAsc = _sortType == 'asc';
    return GestureDetector(
      onTap: () {
        final t = isActive ? (isAsc ? 'desc' : 'asc') : 'desc';
        _onSort(field, t);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
              child: Text(label,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)))),
          const SizedBox(width: 6),
          Icon(isActive ? (isAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
              size: 14, color: isActive ? const Color(0xFF006EFF) : const Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }
}
