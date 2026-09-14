import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 异常监控 - 单据详情页
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\exceptionMonitoring\bill.vue
///
/// 接受列表页传入的整行数据 row，请求接口时与 Vue 一致：
///   { ...row, is_page: 1, page: 1, pagesize: 999, field: '', type: '', name: '', cond: '' }
class ExceptionMonitoringDetailPage extends StatefulWidget {
  const ExceptionMonitoringDetailPage({super.key, required this.row});
  final Map<String, dynamic> row;

  @override
  State<ExceptionMonitoringDetailPage> createState() => _ExceptionMonitoringDetailPageState();
}

class _ExceptionMonitoringDetailPageState extends State<ExceptionMonitoringDetailPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _detailList = [];

  int get _opertype => int.tryParse(widget.row['opertype']?.toString() ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    return request(HttpApi.saleCashMonitorGetCashMonitorDetail, {
      ...widget.row,
      'is_page': 1,
      'page': 1,
      'pagesize': 999,
      'field': '',
      'type': '',
      'name': '',
      'cond': '',
    })
        .then((result) {
          if (!mounted) return;
          final data = result['data'];
          if (data is Map<String, dynamic>) {
            final list = (data['list'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            setState(() {
              _detailList = list;
            });
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('异常监控详情',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
            )
          : RefreshIndicator(
              color: const Color(0xFF006EFF),
              onRefresh: _loadDetail,
              child: _detailList.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 200),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                              SizedBox(height: 12),
                              Text('暂无数据',
                                  style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                            ],
                          ),
                        ),
                      ],
                    )
                  : _buildTable(),
            ),
    );
  }

  // ==================== 列定义（根据 opertype 动态生成） ====================

  List<_DetailColumn> _detailColumns() {
    return [
      _DetailColumn(
        label: '商品名称/条码',
        field: 'productname',
        isFixed: true,
        formatter: (row) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(row['productname']?.toString() ?? '-',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
              const SizedBox(height: 2),
              Text(row['productcode']?.toString() ?? '',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
            ],
          );
        },
      ),
      _col1(),
      _col2(),
      _col3(),
    ];
  }

  _DetailColumn _col1() {
    switch (_opertype) {
      case 1:
        return const _DetailColumn(label: '原售价', field: 'sellprice', fietype: 2);
      case 2:
        return const _DetailColumn(label: '单价', field: 'rrprice', fietype: 2);
      case 3:
        return const _DetailColumn(label: '单价', field: 'rrprice', fietype: 2);
      case 4:
        return const _DetailColumn(label: '原售价', field: 'sellprice', fietype: 2);
      case 5:
        return const _DetailColumn(label: '单价', field: 'rrprice', fietype: 2);
      case 6:
        return const _DetailColumn(label: '单价', field: 'rrprice', fietype: 2);
      case 7:
        return const _DetailColumn(label: '单价', field: 'rrprice', fietype: 2);
      case 8:
        return const _DetailColumn(label: '单价', field: 'rrprice', fietype: 2);
      default:
        return const _DetailColumn(label: '原售价', field: 'sellprice', fietype: 2);
    }
  }

  _DetailColumn _col2() {
    switch (_opertype) {
      case 1:
        return const _DetailColumn(label: '最新价', field: 'rrprice', fietype: 2);
      case 2:
        return const _DetailColumn(label: '删除数量', field: 'qty', fietype: 1);
      case 3:
        return const _DetailColumn(label: '退货数量', field: 'qty', fietype: 1);
      case 4:
        return const _DetailColumn(label: '最新价', field: 'rrprice', fietype: 2);
      case 5:
        return const _DetailColumn(label: '删除数量', field: 'qty', fietype: 1);
      case 6:
        return const _DetailColumn(label: '赠送数量', field: 'qty', fietype: 1);
      case 7:
        return const _DetailColumn(label: '挂单数量', field: 'qty', fietype: 1);
      case 8:
        return const _DetailColumn(label: '删单数量', field: 'qty', fietype: 1);
      default:
        return const _DetailColumn(label: '最新价', field: 'rrprice', fietype: 2);
    }
  }

  _DetailColumn _col3() {
    switch (_opertype) {
      case 1:
        return const _DetailColumn(label: '变动金额', field: 'bdamt', fietype: 3);
      case 2:
        return const _DetailColumn(label: '删除金额', field: 'rramt', fietype: 3);
      case 3:
        return const _DetailColumn(label: '退货金额', field: 'rramt', fietype: 3);
      case 4:
        return const _DetailColumn(label: '折扣金额', field: 'zkamt', fietype: 3);
      case 5:
        return const _DetailColumn(label: '删除金额', field: 'rramt', fietype: 3);
      case 6:
        return const _DetailColumn(label: '赠送金额', field: 'zsamt', fietype: 3);
      case 7:
        return const _DetailColumn(label: '挂单金额', field: 'rramt', fietype: 3);
      case 8:
        return const _DetailColumn(label: '删单金额', field: 'rramt', fietype: 3);
      default:
        return const _DetailColumn(label: '变动金额', field: 'bdamt', fietype: 3);
    }
  }

  // ==================== 表格 ====================

  Widget _buildTable() {
    final cols = _detailColumns();
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));

    return DataTable2(
      minWidth: 600,
      fixedLeftColumns: 1,
      horizontalMargin: 0,
      columnSpacing: 0,
      dataRowHeight: 56,
      headingRowHeight: 44,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
      border: const TableBorder(
        horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
        verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
      ),
      columns: [
        for (final col in cols)
          if (col.isFixed)
            DataColumn2(
              fixedWidth: 150,
              label: Padding(
                padding: const EdgeInsets.only(left: 5, right: 12),
                child: Text(col.label, style: headerStyle),
              ),
            )
          else
            DataColumn2(
              size: ColumnSize.L,
              numeric: col.fietype != null,
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(col.label,
                    textAlign: col.fietype != null ? TextAlign.right : TextAlign.center,
                    style: headerStyle),
              ),
            ),
      ],
      rows: [
        for (var i = 0; i < _detailList.length; i++) _buildRow(cols, _detailList[i], i),
        _buildSummaryRow(cols),
      ],
    );
  }

  DataRow2 _buildRow(List<_DetailColumn> cols, Map<String, dynamic> row, int index) {
    const cellPad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final isOdd = index.isOdd;

    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        for (final col in cols)
          DataCell(
            Padding(
              padding: cellPad,
              child: col.buildCellContent(row),
            ),
          ),
      ],
    );
  }

  DataRow2 _buildSummaryRow(List<_DetailColumn> cols) {
    const summaryStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827));
    const cellPad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    return DataRow2(
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        border: Border(right: BorderSide(color: Color(0xFFE1E9F3))),
      ),
      cells: [
        for (var i = 0; i < cols.length; i++)
          DataCell(
            Padding(
              padding: cellPad,
              child: Align(
                alignment: i == 0 ? Alignment.centerLeft : Alignment.centerRight,
                child: Text(
                  i == 0 ? '合计' : _buildSummaryValue(cols[i]),
                  style: summaryStyle,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _buildSummaryValue(_DetailColumn col) {
    if (col.fietype == null) return '';
    double total = 0;
    for (final row in _detailList) {
      final num v = num.tryParse(row[col.field]?.toString() ?? '') ?? 0;
      total += v.toDouble();
    }
    return fmtByType(col.fietype!, total);
  }
}

/// 详情列表列配置
class _DetailColumn {
  const _DetailColumn({
    required this.label,
    required this.field,
    this.fietype,
    this.isFixed = false,
    this.formatter,
  });
  final String label;
  final String field;
  final int? fietype; // 1=数量(1位) 2=单价(2位) 3=金额(2位)
  final bool isFixed;
  final Widget Function(Map<String, dynamic>)? formatter;

  Widget buildCellContent(Map<String, dynamic> row) {
    if (formatter != null) {
      return formatter!(row);
    }
    final value = row[field] ?? '';
    final text = fietype != null ? fmtByType(fietype!, value) : value.toString();
    return Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF333333)));
  }
}

/// 数值格式化工具函数（对齐 Vue formatDecimal: 1=数量→1位 2=单价→2位 3=金额→2位）
String fmtByType(int fietype, dynamic value) {
  final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
  switch (fietype) {
    case 1:
      return v.toStringAsFixed(1);
    case 2:
    case 3:
    default:
      return v.toStringAsFixed(2);
  }
}
