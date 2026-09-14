import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

/// ABC 分析表格模式
enum AbcTableMode { product, type }

/// 可复用的 ABC 分析表格组件
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\typeABC\ABCTable.vue
class AbcTableWidget extends StatefulWidget {
  const AbcTableWidget({
    super.key,
    required this.mode,
    required this.dataList,
    required this.sumData,
    required this.isLoading,
    required this.hasMore,
    required this.onLoadMore,
    required this.onRefresh,
    this.onSort,
    this.sortField,
    this.sortType,
    this.isRefreshLoading = false,
  });

  final AbcTableMode mode;
  final List<Map<String, dynamic>> dataList;
  final Map<String, dynamic> sumData;
  final bool isLoading;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;
  final void Function(String field, String type)? onSort;
  final String? sortField;
  final String? sortType;

  /// 是否为首页刷新（区别于加载更多）：刷新时在表格中央叠加图标卡片
  final bool isRefreshLoading;

  @override
  State<AbcTableWidget> createState() => _AbcTableWidgetState();
}

class _AbcTableWidgetState extends State<AbcTableWidget> {
  // 注：不向 DataTable2 传外部 horizontalScrollController（data_table_2 插件在
  // 重建/卸载时会访问已 dispose 的外部控制器导致崩溃），
  // 合计行同步完全依赖 ScrollNotification
  final ScrollController _summaryHCtrl = ScrollController();

  /// 是否已成功加载过一次（组件内部跟踪，首次加载后空数据刷新不再闪屏）
  bool _hasLoadedOnce = false;

  @override
  void dispose() {
    _summaryHCtrl.dispose();
    super.dispose();
  }

  bool get _isProduct => widget.mode == AbcTableMode.product;

  static const _headerStyle =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
  static const _cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));

  static String _fmtAmt(dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(2);
  }

  static String _fmtQty(dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(1);
  }

  static String _fmtPct(dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return '${v.toStringAsFixed(1)}%';
  }

  static double? _parseDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  List<DataColumn2> _buildColumns() {
    final cols = <DataColumn2>[
      const DataColumn2(
        fixedWidth: 40,
        label: Padding(
          padding: EdgeInsets.only(left: 5, right: 4),
          child: Text('序号', style: _headerStyle),
        ),
      ),
      DataColumn2(
        fixedWidth: 120,
        label: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(_isProduct ? '商品名称/条码' : '类别名称', style: _headerStyle),
        ),
      ),
    ];

    cols.addAll([
      _buildSortableCol('qty', '销售数量'),
      _buildSortableCol('costamt', '销售成本'),
      _buildSortableCol('rramt', '销售金额'),
      _buildSortableCol('grossamt', '毛利额'),
      _buildSortableCol('grossrate', '毛利率'),
      _buildSortableCol('prop', '销售金额占比'),
      _buildSortableCol('sumprop', '累计占比'),
      const DataColumn2(
        label: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('ABC类型', style: _headerStyle),
        ),
      ),
    ]);

    if (_isProduct) {
      cols.addAll(const [
        DataColumn2(
          label: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('单位', style: _headerStyle),
          ),
        ),
        DataColumn2(
          label: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('规格', style: _headerStyle),
          ),
        ),
      ]);
    }

    return cols;
  }

  DataColumn2 _buildSortableCol(String name, String label) {
    final isActive = widget.sortField == name;
    final isAsc = widget.sortType == 'asc';
    return DataColumn2(
      numeric: true,
      label: GestureDetector(
        onTap: () {
          final newType = isActive ? (isAsc ? 'desc' : 'asc') : 'desc';
          widget.onSort?.call(name, newType);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, textAlign: TextAlign.right, style: _headerStyle)),
              if (isActive)
                Icon(isAsc ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14, color: const Color(0xFF006EFF))
              else
                const Icon(Icons.unfold_more, size: 14, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  int get _colCount => _isProduct ? 12 : 10;

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

  @override
  Widget build(BuildContext context) {
    // 加载结束（成功或失败）即视为已加载过一次
    if (!widget.isLoading) _hasLoadedOnce = true;

    if (widget.dataList.isEmpty && (!widget.isLoading || _hasLoadedOnce)) {
      // 空态：加载完成无数据，或已加载过刷新中（保留空态+图标卡片，避免表格骨架闪屏）
      return Stack(children: [
        RefreshIndicator(
          color: const Color(0xFF006EFF),
          onRefresh: widget.onRefresh,
          child: ListView(children: const [
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
          ]),
        ),
        if (widget.isLoading) _loadingCard,
      ]);
    }

    final columns = _buildColumns();

    return Stack(children: [
      Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollEndNotification &&
                    n.metrics.axis == Axis.vertical &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
                    widget.hasMore &&
                    !widget.isLoading) {
                  widget.onLoadMore();
                }
                // 横向滚动同步到合计行（DataTable2 水平滚动在嵌套深度 >=1 处）
                if (n is ScrollUpdateNotification && n.metrics.axis == Axis.horizontal) {
                  if (_summaryHCtrl.hasClients) {
                    try {
                      final target =
                          n.metrics.pixels.clamp(0.0, _summaryHCtrl.position.maxScrollExtent);
                      if (_summaryHCtrl.offset != target) {
                        _summaryHCtrl.jumpTo(target);
                      }
                    } catch (_) {}
                  }
                }
                return false;
              },
              child: RefreshIndicator(
                color: const Color(0xFF006EFF),
                onRefresh: widget.onRefresh,
                child: DataTable2(
                  fixedLeftColumns: 2,
                  minWidth: _isProduct ? 1000 : 880,
                  horizontalMargin: 0,
                  columnSpacing: 0,
                  dataRowHeight: 52,
                  headingRowHeight: 44,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
                    verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
                  ),
                  columns: columns,
                  rows: [
                    for (var i = 0; i < widget.dataList.length; i++)
                      _buildRow(widget.dataList[i], i),
                    // 加载行：仅首次加载或加载更多时显示（刷新时由居中图标卡片提示）
                    if (widget.isLoading && !widget.isRefreshLoading)
                      DataRow(cells: [
                        const DataCell(SizedBox(
                            height: 44,
                            child: Center(
                                child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Color(0xFF006EFF)))))),
                        for (int j = 1; j < _colCount; j++) DataCell.empty,
                      ]),
                  ],
                ),
              ),
            ),
          ),
          if (widget.sumData.isNotEmpty && widget.dataList.isNotEmpty) _buildSummaryRow(),
        ],
      ),
      if (widget.isRefreshLoading) _loadingCard,
    ]);
  }

  DataRow2 _buildRow(Map<String, dynamic> row, int index) {
    final isOdd = index.isOdd;

    final cells = <DataCell>[
      DataCell(Center(child: Text('${index + 1}', style: _cellStyle))),
    ];

    // 商品名称/条码 or 类别名称
    if (_isProduct) {
      final name = row['name']?.toString() ?? '--';
      final barcode = row['barcode']?.toString() ?? '';
      cells.add(DataCell(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: _cellStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (barcode.isNotEmpty)
              Text(barcode,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      )));
    } else {
      cells.add(DataCell(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(row['typename']?.toString() ?? '--', style: _cellStyle),
      )));
    }

    // 数值列
    final qty = _parseDouble(row['qty']);
    final costamt = _parseDouble(row['costamt']);
    final rramt = _parseDouble(row['rramt']);
    final grossamt = _parseDouble(row['grossamt']);

    cells.addAll([
      _numCell(_fmtQty(qty)),
      _numCell(_fmtAmt(costamt)),
      _numCell(_fmtAmt(rramt)),
      _numCell(_fmtAmt(grossamt)),
      _numCell(_fmtPct(row['grossrate'])),
      _numCell(_fmtPct(row['prop'])),
      _numCell(_fmtPct(row['sumprop'])),
      DataCell(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(row['abc']?.toString() ?? '--', style: _cellStyle),
      )),
    ]);

    if (_isProduct) {
      cells.addAll([
        DataCell(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(row['unit']?.toString() ?? '--', style: _cellStyle),
        )),
        DataCell(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(row['size']?.toString() ?? '--', style: _cellStyle),
        )),
      ]);
    }

    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: cells,
    );
  }

  static DataCell _numCell(String text) {
    return DataCell(Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(text, style: _cellStyle),
      ),
    ));
  }

  Widget _buildSummaryRow() {
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));

    // 冻结列：序号(40) + 名称(120) = 160
    // 非冻结列：8个数据列（type模式）或10个（product模式含单位/规格）
    final isProduct = _isProduct;
    final nonFrozenCols = isProduct ? 10 : 8;
    final minW = isProduct ? 1000.0 : 880.0;
    final colW = (minW - 160) / nonFrozenCols;

    // 显式列出每列：有合计值的列取 sumData 对应值，无合计值的列用空字符串占位
    // 每列都必须有明确宽度 colW，确保与表头列宽一致
    final cells = <Widget>[
      _numSumCell(_summaryValue('qty'), colW, boldStyle), // 销售数量
      _numSumCell(_summaryValue('costamt'), colW, boldStyle), // 销售成本
      _numSumCell(_summaryValue('rramt'), colW, boldStyle), // 销售金额
      _numSumCell(_summaryValue('grossamt'), colW, boldStyle), // 毛利额
      _numSumCell(_summaryValue('grossrate'), colW, boldStyle), // 毛利率
      _numSumCell(_summaryValue('prop'), colW, boldStyle), // 销售金额占比
      _numSumCell(_summaryValue('sumprop'), colW, boldStyle), // 累计占比
      _textSumCell('', colW, boldStyle), // ABC类型（文本左对齐）
    ];
    if (isProduct) {
      cells.addAll([
        _textSumCell('', colW, boldStyle), // 单位（文本左对齐）
        _textSumCell('', colW, boldStyle), // 规格（文本左对齐）
      ]);
    }

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        border: Border(top: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      child: Row(
        children: [
          // 冻结列：序号 + 名称
          const SizedBox(
            width: 160,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('合计', style: boldStyle),
            ),
          ),
          // 可滚动数据列：与表格横向滚动同步
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              controller: _summaryHCtrl,
              child: SizedBox(
                width: colW * nonFrozenCols,
                child: Row(children: cells),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 文本列单元格：对齐数据行 ABC/单位/规格 的布局（Padding symmetric，无 Align）
  Widget _textSumCell(String text, double width, TextStyle style) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  /// 数值列单元格：对齐数据行 _numCell 的布局（Align centerRight + Padding right:8）
  Widget _numSumCell(String text, double width, TextStyle style) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  String _summaryValue(String key) {
    final v = widget.sumData[key];
    if (v == null) return '--';
    if (key == 'qty') return _fmtQty(v);
    if (key == 'costamt' || key == 'rramt' || key == 'grossamt') return _fmtAmt(v);
    if (key == 'grossrate' || key == 'prop' || key == 'sumprop') return _fmtPct(v);
    return v.toString();
  }
}
