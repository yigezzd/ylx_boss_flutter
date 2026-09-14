import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 动销/未动销品项数详情页
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\salesRateAnalysis\numMovingItem.vue
class NumMovingItemPage extends StatefulWidget {
  const NumMovingItemPage({
    super.key,
    required this.params,
    required this.selectflag,
    required this.title,
  });

  /// 父页面的查询参数（starttime, endtime, sids, typeid, supid, brandid, itemstatusin, level）
  final Map<String, dynamic> params;

  /// 1=动销品项数, 0=未动销品项数
  final int selectflag;

  /// 页面标题："动销品项数" 或 "未动销品项数"
  final String title;

  @override
  State<NumMovingItemPage> createState() => _NumMovingItemPageState();
}

class _NumMovingItemPageState extends State<NumMovingItemPage> {
  bool _loading = true;
  bool _hasMore = true;
  int _page = 1;
  static const int _pagesize = 20;
  final List<Map<String, dynamic>> _list = [];

  /// 是否已成功加载过一次（用于区分首次加载与后续刷新，避免空数据刷新时闪屏）
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_loading && _page > 1) return;
    setState(() => _loading = true);
    try {
      final result = await request(HttpApi.sellthroughProductSellThrough, {
        ...widget.params,
        'selectflag': widget.selectflag,
        'is_page': 1,
        'page': _page,
        'pagesize': _pagesize,
      });
      if (!mounted) return;
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      setState(() {
        if (_page == 1) {
          _list.clear();
          _list.addAll(list);
        } else {
          _list.addAll(list);
        }
        _hasMore = list.length >= _pagesize;
        if (_hasMore) _page++;
        _hasLoadedOnce = true;
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(children: [
        if (_loading && _list.isEmpty && !_hasLoadedOnce)
          const Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
          )
        else
          RefreshIndicator(
            color: const Color(0xFF006EFF),
            onRefresh: _onRefresh,
            child: _list.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 200),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                          SizedBox(height: 12),
                          Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                        ],
                      ),
                    ),
                  ])
                : _buildTable(),
          ),
        // 刷新时仅居中图标卡片，内容保持可见（避免闪屏）
        if (_loading && _hasLoadedOnce) _loadingCard,
      ]),
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

  Widget _buildTable() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));

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
        minWidth: 400,
        fixedLeftColumns: 2,
        dataRowHeight: 56,
        headingRowHeight: 44,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
        border: const TableBorder(
          horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
          verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
        ),
        columns: const [
          DataColumn2(
            fixedWidth: 40,
            label: Center(child: Text('排行', style: headerStyle)),
          ),
          DataColumn2(
            fixedWidth: 120,
            label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('机构名称', style: headerStyle),
            ),
          ),
          DataColumn2(
            label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('商品名称/条码', style: headerStyle),
            ),
          ),
          DataColumn2(
            label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('末次销售时间', style: headerStyle),
            ),
          ),
        ],
        rows: [
          for (var i = 0; i < _list.length; i++) _buildRow(_list[i], i),
          // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
          if (_loading && (_page > 1 || !_hasLoadedOnce))
            const DataRow(cells: [
              DataCell(SizedBox(
                  height: 44,
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF006EFF)))))),
              DataCell.empty,
              DataCell.empty,
              DataCell.empty,
            ]),
        ],
      ),
    );
  }

  DataRow2 _buildRow(Map<String, dynamic> row, int index) {
    final isOdd = index.isOdd;
    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        DataCell(Center(
            child: Text('${index + 1}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))))),
        DataCell(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(row['storename']?.toString() ?? '--',
              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        )),
        DataCell(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(row['productname']?.toString() ?? '--',
              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
        )),
        DataCell(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(row['lastsaledate']?.toString() ?? '--',
              style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
        )),
      ],
    );
  }
}
