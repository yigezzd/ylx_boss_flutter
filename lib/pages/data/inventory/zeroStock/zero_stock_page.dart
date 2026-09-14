import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_supplier.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart' as classify;
import 'package:flutter_deer/pages/data/inventory/_inventory_filter_sheet.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:sp_util/sp_util.dart';

/// 零库存（无时间选择器，默认当月）
class ZeroStockPage extends StatefulWidget {
  const ZeroStockPage({super.key});
  @override
  State<ZeroStockPage> createState() => _ZeroStockPageState();
}

class _ZeroStockPageState extends State<ZeroStockPage> {
  String _storeName = '', _activeStoreId = '';
  List<int> _sids = [];
  List<Map<String, dynamic>> _typeList = [];
  String _supid = '', _supname = '';
  String _cond = '', _brandid = '', _brandname = '';
  List<String> _itemstatus = [];
  int _recordflag = 1;
  int _days = 7;
  bool _loading = false, _hasMore = true;
  int _page = 1;
  List<Map<String, dynamic>> _list = [];

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时表格闪屏）
  bool _hasLoadedOnce = false;
  Map<String, dynamic> _sumData = {};
  int _productCodeDisabledFlag = 0;
  int _checkstockflag = 1;
  String _sortField = 'zerostockqtyday', _sortType = 'desc';
  static const _selecttype = 1;

  @override
  void initState() {
    super.initState();
    _loadStore();
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
      // 读取登录参数
      final loginCfg = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (loginCfg.isNotEmpty) {
        try {
          final cfg = jsonDecode(loginCfg) as Map<String, dynamic>;
          _productCodeDisabledFlag =
              int.tryParse(cfg['productCodeDisabledFlag']?.toString() ?? '0') ?? 0;
        } catch (_) {}
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

  Future<void> _selectBrand(
      BuildContext ctx, void Function(String id, String name) onSelected) async {
    showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SelectorSheet(
            title: '选择品牌',
            apiPath: 'bi/brand/getBrandList',
            nameKey: 'name',
            idKey: 'id',
            onSelected: onSelected));
  }

  Map<String, dynamic> _baseParams() => {
        'selecttype': _selecttype,
        'field': _sortField,
        'type': _sortType,
        'sids': _sids,
        'typeid': _typeList
            .map((e) => e['typeid']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
        'supid': _supid.isNotEmpty ? _supid : '',
        if (_cond.isNotEmpty) 'cond': _cond,
        if (_brandname.isNotEmpty) 'brandname': _brandname.replaceAll('|', ','),
        if (_itemstatus.isNotEmpty) 'itemstatusin': _itemstatus.join(','),
        'saleflag': _recordflag,
        if (_days > 0) 'days': _days,
      };
  void _openFilterSheet() {
    final initial = InventoryFilterData(
        cond: _cond,
        brandid: _brandid,
        brandname: _brandname,
        itemstatus: List.from(_itemstatus),
        mpbilltypeflag: _recordflag,
        days: _days);
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => InventoryFilterSheet(
            initial: initial,
            showMpbilltype: true,
            toggleLabel: '仅查询有业务记录商品',
            sids: _sids,
            onSelectBrand: _selectBrand,
            onConfirm: (data) {
              setState(() {
                _cond = data.cond;
                _brandid = data.brandid;
                _brandname = data.brandname;
                _itemstatus = data.itemstatus;
                _recordflag = data.mpbilltypeflag;
                _days = data.days;
              });
              _resetAndLoad();
            }));
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
      final r = await request(HttpApi.productErrGetList,
          {'is_page': 1, 'page': _page, 'pagesize': 20, ..._baseParams()});
      final data = r['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      final sumdata = map['sumdata'];
      if (mounted) {
        setState(() {
          if (_page == 1)
            _list = list;
          else
            _list.addAll(list);
          _hasMore = list.length >= 20;
          if (_hasMore) _page++;
          _hasLoadedOnce = true;
          if (sumdata is Map<String, dynamic>)
            _sumData = sumdata;
          else
            _sumData = {};
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
    _resetAndLoad();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
            title: const Text('零库存', style: TextStyle(fontSize: 17)),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF333333),
            elevation: 0.5),
        body: Column(children: [_buildHeader(), Expanded(child: _buildTableContent())]));
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
          const SizedBox(width: 8),
          GestureDetector(
              onTap: _openFilterSheet,
              child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(5)),
                  child:
                      const BossSvgIcon(svgFile: 'fliter.svg', size: 22, color: Color(0xFF666666))))
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
              ]),
            ),
          ]),
        ),
        if (_loading) _loadingCard,
      ]);
    }
    return Stack(children: [
      Column(
          children: [if (_sumData.isNotEmpty) _buildSummaryRow(), Expanded(child: _buildTable())]),
      if (_loading && _hasLoadedOnce && _page == 1) _loadingCard,
    ]);
  }

  Widget _buildSummaryRow() {
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: RichText(
            text:
                TextSpan(style: const TextStyle(fontSize: 13, color: Color(0xFF666666)), children: [
          const TextSpan(text: '总商品数：'),
          TextSpan(
              text: _checkstockflag == 1 ? '${_sumData['endqty'] ?? 0}' : '****',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333))),
          const TextSpan(text: '   库存金额：'),
          TextSpan(
              text: _checkstockflag == 1 ? _fmtAmt(_sumData['endamt']) : '****',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ])));
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
      child: RefreshIndicator(
        color: const Color(0xFF006EFF),
        onRefresh: _onRefresh,
        child: DataTable2(
          horizontalMargin: 0,
          columnSpacing: 0,
          dataRowHeight: 52,
          headingRowHeight: 44,
          minWidth: 1540,
          fixedLeftColumns: 2,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
          border: const TableBorder(
            horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
            verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
          ),
          columns: [
            const DataColumn2(
                fixedWidth: 40,
                label: Padding(
                    padding: EdgeInsets.only(left: 5, right: 4), child: Text('序号', style: hs))),
            const DataColumn2(
                fixedWidth: 160,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('商品名称/条码', style: hs))),
            DataColumn2(
                fixedWidth: 150,
                label: _sortHeader('零库存持续天数', 'zerostockqtyday'),
                onSort: (_, __) => _onSort('zerostockqtyday',
                    _sortField == 'zerostockqtyday' && _sortType == 'asc' ? 'desc' : 'asc')),
            const DataColumn2(
                fixedWidth: 110,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8), child: Text('机构名称', style: hs))),
            DataColumn2(
                fixedWidth: 110,
                label: _sortHeader('日均销量', 'avgqty'),
                onSort: (_, __) => _onSort(
                    'avgqty', _sortField == 'avgqty' && _sortType == 'asc' ? 'desc' : 'asc')),
            DataColumn2(
                fixedWidth: 135,
                label: _sortHeader('最后出库日期', 'outbilldate'),
                onSort: (_, __) => _onSort('outbilldate',
                    _sortField == 'outbilldate' && _sortType == 'asc' ? 'desc' : 'asc')),
            DataColumn2(
                fixedWidth: 120,
                label: _sortHeader('最后出库量', 'outqty'),
                onSort: (_, __) => _onSort(
                    'outqty', _sortField == 'outqty' && _sortType == 'asc' ? 'desc' : 'asc')),
            DataColumn2(
                fixedWidth: 135,
                label: _sortHeader('最后入库日期', 'inbilldate'),
                onSort: (_, __) => _onSort('inbilldate',
                    _sortField == 'inbilldate' && _sortType == 'asc' ? 'desc' : 'asc')),
            if (_productCodeDisabledFlag != 2)
              const DataColumn2(
                  fixedWidth: 90,
                  label: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8), child: Text('自编码', style: hs))),
            const DataColumn2(
                fixedWidth: 65,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8), child: Text('单位', style: hs))),
            const DataColumn2(
                fixedWidth: 75,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8), child: Text('规格', style: hs))),
            const DataColumn2(
                fixedWidth: 75,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8), child: Text('分类', style: hs))),
            const DataColumn2(
                fixedWidth: 100,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8), child: Text('主供应商', style: hs))),
            const DataColumn2(
                fixedWidth: 100,
                label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8), child: Text('商品状态', style: hs))),
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
                for (int j = 1; j < (_productCodeDisabledFlag != 2 ? 14 : 13); j++) DataCell.empty
              ]),
          ],
        ),
      ),
    );
  }

  DataRow2 _buildRow(Map<String, dynamic> row, int index) {
    const cs = TextStyle(fontSize: 13, color: Color(0xFF333333));
    const csSmall = TextStyle(fontSize: 11, color: Color(0xFF999999));
    final showCode = _productCodeDisabledFlag != 2;
    return DataRow2(
      decoration: BoxDecoration(
        color: index.isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        DataCell(Center(child: Text('${index + 1}', style: cs))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row['name']?.toString() ?? '',
                      style: cs, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if ((row['barcode']?.toString() ?? '').isNotEmpty)
                    Text(row['barcode']?.toString() ?? '',
                        style: csSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]))),
        DataCell(Align(
            alignment: Alignment.centerLeft,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(row['zerostockqtyday']?.toString() ?? '', style: cs)))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['storename']?.toString() ?? '', style: cs))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_fmtNum(row['avgqty']), style: cs)))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['outbilldate']?.toString() ?? '', style: cs))),
        DataCell(Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(_fmtNum(row['outqty']), style: cs)))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['inbilldate']?.toString() ?? '', style: cs))),
        if (showCode)
          DataCell(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(row['code']?.toString() ?? '', style: cs))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['unit']?.toString() ?? '', style: cs))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['size']?.toString() ?? '', style: cs))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['typename']?.toString() ?? '', style: cs))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['supname']?.toString() ?? '', style: cs))),
        DataCell(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(row['itemstatusname']?.toString() ?? '', style: cs))),
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
          if (isActive)
            Icon(isAsc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14, color: const Color(0xFF006EFF))
          else
            const Icon(Icons.unfold_more, size: 14, color: Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }

  static String _fmtNum(dynamic v) => v?.toString() ?? '0';
  static String _fmtAmt(dynamic v) {
    final num n = v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
    return n.toStringAsFixed(2);
  }
}
