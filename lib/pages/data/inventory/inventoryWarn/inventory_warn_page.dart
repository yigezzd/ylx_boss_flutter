import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart' as classify;
import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 库存预警（无时间选择器，默认当月）
class InventoryWarnPage extends StatefulWidget {
  const InventoryWarnPage({super.key, this.currTab});
  final String? currTab; // '0'=库存不足 '1'=库存积压
  @override
  State<InventoryWarnPage> createState() => _InventoryWarnPageState();
}

class _InventoryWarnPageState extends State<InventoryWarnPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;
  String _storeName = '', _activeStoreId = '';
  List<int> _sids = [];
  List<Map<String, dynamic>> _typeList = [];
  String _supid = '', _supname = '';
  String _cond = '';
  final TextEditingController _condController = TextEditingController();
  Timer? _debounce;
  int _checkstockflag = 1;
  bool _loading = false, _hasMore = true;
  int _page = 1;
  List<Map<String, dynamic>> _list = [];

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时列表闪屏）
  bool _hasLoadedOnce = false;
  static const _tabs = ['库存不足', '库存积压'];
  static const _apis = [HttpApi.stockwarnGetStockLow, HttpApi.stockwarnGetStockOver];

  @override
  void initState() {
    super.initState();
    final initialIndex = int.tryParse(widget.currTab ?? '0') ?? 0;
    _tabController = TabController(length: 2, vsync: this, initialIndex: initialIndex.clamp(0, 1));
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
        _resetAndLoad();
      }
    });
    _condController.addListener(_onCondChanged);
    _loadStore();
  }

  void _onCondChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _cond = _condController.text);
        _resetAndLoad();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
    _condController.removeListener(_onCondChanged);
    _condController.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    try {
      final s = SpUtil.getString(Constant.store) ?? '';
      if (s.isNotEmpty) {
        final m = jsonDecode(s);
        final id = m['id']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _storeName = m['name']?.toString() ?? '';
            _activeStoreId = id;
            _sids = id.isNotEmpty ? [int.tryParse(id) ?? 0] : [];
          });
        }
      }
      // 读取用户信息
      final userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        try {
          final u = jsonDecode(userStr) as Map<String, dynamic>;
          _checkstockflag = int.tryParse(u['checkstockflag']?.toString() ?? '1') ?? 1;
        } catch (_) {}
      }
      if (mounted) _loadData();
    } catch (_) {}
  }

  Future<void> _selectStore() async {
    final r = await SelectStorePage.show(context, showAll: true, initialSelectedId: _activeStoreId);
    if (r != null && mounted) {
      setState(() {
        _storeName = r['storename']?.toString() ?? '';
        _activeStoreId = r['storeid']?.toString() ?? '';
        _sids = _activeStoreId.isNotEmpty ? [int.tryParse(_activeStoreId) ?? 0] : [];
      });
      _resetAndLoad();
    }
  }

  Future<void> _selectCategory() async {
    final ids =
        _typeList.map((e) => e['typeid']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
    final r = await Navigator.push<List<Map<String, dynamic>>>(
        context,
        MaterialPageRoute(
            builder: (_) => classify.CategoryListPage(
                isSelect: true, isMultiSelect: true, showAll: true, initialSelectedIds: ids)));
    if (r != null && mounted) {
      setState(() => _typeList = r);
      _resetAndLoad();
    }
  }

  String get _categoryLabel =>
      _typeList.isEmpty ? '全部分类' : _typeList.map((e) => e['name']?.toString() ?? '').join('|');
  Future<void> _openSupplierSelector() async {
    final result = await SelectSupplierPage.show(context, initialSelectedId: _supid);
    if (result != null && mounted) {
      setState(() {
        _supid = result['supid']?.toString() ?? '';
        _supname = result['supname']?.toString() ?? '';
      });
      _resetAndLoad();
    }
  }

  Map<String, dynamic> _baseParams() {
    final typeIds =
        _typeList.map((e) => e['typeid']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
    return {
      'bsid': _sids.isNotEmpty ? _sids.first : '',
      'sidsname': _storeName,
      'supid': _supid.isNotEmpty ? _supid : '',
      // 未选分类或选“全部分类”时，不传 typelist（与 Vue 行为一致）
      if (typeIds.isNotEmpty) 'typelist': typeIds,
      if (_cond.isNotEmpty) 'cond': _cond,
    };
  }

  void _resetAndLoad() {
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final r = await request(
          _apis[_tabIndex], {'is_page': 1, 'page': _page, 'pagesize': 20, ..._baseParams()});
      final data = r['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          if (_page == 1)
            _list = list;
          else
            _list.addAll(list);
          _hasMore = list.length >= 20;
          if (_hasMore) _page++;
          _hasLoadedOnce = true;
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

  num _jsNum(Map<String, dynamic> item) {
    final qty = num.tryParse(item['qty']?.toString() ?? '0') ?? 0;
    if (_tabIndex == 0) {
      return qty - (num.tryParse(item['minstock']?.toString() ?? '0') ?? 0);
    }
    return qty - (num.tryParse(item['maxstock']?.toString() ?? '0') ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
            title: const Text('库存预警', style: TextStyle(fontSize: 17)),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF333333),
            elevation: 0.5,
            bottom: PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: ColoredBox(
                    color: Colors.white,
                    child: TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF006EFF),
                        unselectedLabelColor: const Color(0xFF666666),
                        indicatorColor: const Color(0xFF006EFF),
                        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(fontSize: 14),
                        tabs: _tabs.map((t) => Tab(text: t)).toList())))),
        body: Column(
            children: [_buildHeader(), _buildSearchBox(), Expanded(child: _buildCardList())]));
  }

  Widget _buildHeader() {
    return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          Expanded(
              child: _buildDropBtn(
                  label: _storeName.isNotEmpty ? _storeName : '全部机构', onTap: _selectStore)),
          const SizedBox(width: 8),
          Expanded(child: _buildDropBtn(label: _categoryLabel, onTap: _selectCategory)),
          const SizedBox(width: 8),
          Expanded(
              child: _buildDropBtn(
                  label: _supname.isNotEmpty ? _supname : '全部供应商', onTap: _openSupplierSelector)),
        ]));
  }

  Widget _buildDropBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(5)),
            child: Row(children: [
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
              const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666))
            ])));
  }

  Widget _buildSearchBox() {
    return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: TextField(
            controller: _condController,
            onSubmitted: (v) {
              setState(() => _cond = v);
              _resetAndLoad();
            },
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
            decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF8B8B8B)),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                hintText: '请输入条码/品名/自编码',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5),
                    borderSide: const BorderSide(color: Color(0xFFDEDEDE))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5),
                    borderSide: const BorderSide(color: Color(0xFF006EFF))),
                suffixIcon: _condController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _condController.clear();
                          setState(() => _cond = '');
                          _resetAndLoad();
                        },
                        child: const Icon(Icons.clear, size: 18, color: Color(0xFF999999)))
                    : null)));
  }

  Widget _buildCardList() {
    if (_list.isEmpty && (!_loading || _hasLoadedOnce)) {
      // 空态：加载完成无数据，或已加载过刷新中（保留空态+图标卡片，避免列表骨架闪屏）
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
              ]),
            ),
          ]),
        ),
        if (_loading) _loadingCard,
      ]);
    }
    return Stack(children: [
      NotificationListener<ScrollNotification>(
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
        child: RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: _onRefresh,
          child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _list.length + ((_loading && (_page > 1 || !_hasLoadedOnce)) ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i >= _list.length) {
                  return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF006EFF)))));
                }
                return _buildCard(_list[i], i);
              }),
        ),
      ),
      if (_loading && _hasLoadedOnce && _page == 1) _loadingCard,
    ]);
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

  Widget _buildCard(Map<String, dynamic> item, int index) {
    final diff = _jsNum(item);
    final diffStr = (diff is int && diff == diff) ? diff.toString() : diff.toStringAsFixed(1);
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFE8E8E8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 第一行：商品名称(规格) | 差值
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: RichText(
                    text: TextSpan(
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                        children: [
                  TextSpan(text: item['name']?.toString() ?? ''),
                  if ((item['size']?.toString() ?? '').isNotEmpty)
                    TextSpan(
                        text: '(${item['size']})',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400)),
                ]))),
            const SizedBox(width: 8),
            Text(diffStr,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.red)),
          ]),
          // 第二行：条码
          if ((item['barcode']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item['barcode']!.toString(),
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ],
          // 第三行：当前库存 | 库存下限/上限
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('当前库存：${_checkstockflag == 1 ? _fmtNum(item['qty']) : '****'}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
            Text(
                _tabIndex == 0
                    ? '库存下限：${_fmtNum(item['minstock'])}'
                    : '库存上限：${_fmtNum(item['maxstock'])}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
          ]),
        ]),
      ),
    );
  }

  static String _fmtNum(dynamic v) {
    final n = num.tryParse(v?.toString() ?? '') ?? 0;
    return n == n.toInt() ? n.toInt().toString() : n.toStringAsFixed(1);
  }
}
