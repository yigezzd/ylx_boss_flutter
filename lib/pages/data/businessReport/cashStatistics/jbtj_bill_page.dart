import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 交班统计 - 详情页
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\cashStatistics\jbtjBill.vue
class JbtjBillPage extends StatefulWidget {
  const JbtjBillPage({super.key, required this.rowData});
  final Map<String, dynamic> rowData;

  @override
  State<JbtjBillPage> createState() => _JbtjBillPageState();
}

class _JbtjBillPageState extends State<JbtjBillPage> {
  static const _itypeMap = {
    1: '消费',
    2: '充值',
    3: '发卡',
    4: '退卡',
    5: '买次卡',
    6: '一卡通充值',
    7: '会员挂账还款',
    8: '积分兑换加价',
    9: '会员续费',
    10: '会员绑定',
    11: '批量充值',
  };

  static const _payTypeOptions = [
    {'text': '全部交易类型', 'id': ''},
    {'text': '消费', 'id': '1'},
    {'text': '充值', 'id': '2'},
    {'text': '发卡', 'id': '3'},
    {'text': '退卡', 'id': '4'},
    {'text': '买次卡', 'id': '5'},
    {'text': '一卡通充值', 'id': '6'},
    {'text': '会员挂账还款', 'id': '7'},
    {'text': '积分兑换加价', 'id': '8'},
    {'text': '会员续费', 'id': '9'},
    {'text': '会员绑定', 'id': '10'},
    {'text': '批量充值', 'id': '11'},
  ];

  bool _loading = true;
  Map<String, dynamic> _query = {};
  List<Map<String, dynamic>> _allList = [];
  List<Map<String, dynamic>> _filteredList = [];
  String _selectedPayType = '';

  String _fmtAmt(dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    return v.toStringAsFixed(2);
  }

  String _itypeName(dynamic itype) {
    final int code = itype is int ? itype : int.tryParse(itype?.toString() ?? '') ?? 0;
    return _itypeMap[code] ?? '--';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final result = await request(HttpApi.cashreconGetSaleJkdInfo, {
        ...widget.rowData,
      });
      final data = result['data'];
      if (data is Map<String, dynamic> && mounted) {
        final list = (data['detaillist'] is List)
            ? (data['detaillist'] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        setState(() {
          _query = data;
          _allList = list;
          _filter();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    if (_selectedPayType.isEmpty) {
      _filteredList = List.from(_allList);
    } else {
      _filteredList = _allList.where((e) => e['itype']?.toString() == _selectedPayType).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('交班详情', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
          : RefreshIndicator(
              color: const Color(0xFF006EFF),
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 12),
                  _buildFilterBar(),
                  const SizedBox(height: 8),
                  _buildDetailTable(),
                ],
              ),
            ),
    );
  }

  /// 顶部信息卡片
  Widget _buildInfoCard() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E9F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 收银员
          Row(
            children: [
              Text(
                '收银员：${_query['opername']?.toString() ?? '--'}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 当班时间 / 交班时间
          Text(
            '当班时间：${_query['logintime']?.toString() ?? '--'}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
          ),
          const SizedBox(height: 4),
          Text(
            '交班时间：${_query['logouttime']?.toString() ?? '--'}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
          ),
          const SizedBox(height: 8),
          // 当班金额 / 中途提款
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE1E9F3))),
            ),
            child: Row(
              children: [
                Text(
                  '当班金额：${_fmtAmt(_query['dutyamt'])}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
                ),
                const SizedBox(width: 24),
                Text(
                  '中途提款：${_fmtAmt(_query['halfdraw'])}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 收款合计 / 应交合计
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem('收款合计', _fmtAmt(_query['saleamt']), primary),
              ),
              Container(width: 1, height: 60, color: const Color(0xFFE1E9F3)),
              Expanded(
                child: _buildSummaryItem('应交合计', _fmtAmt(_query['payableamt']), primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color accent) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666))),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: accent)),
      ],
    );
  }

  /// 交易类型筛选
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE1E9F3)),
      ),
      child: Row(
        children: [
          const Text('交易类型：', style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPayType,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                onChanged: (v) {
                  setState(() {
                    _selectedPayType = v ?? '';
                    _filter();
                  });
                },
                items: _payTypeOptions.map((e) {
                  return DropdownMenuItem<String>(
                    value: e['id'],
                    child: Text(e['text']!, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 明细表格
  Widget _buildDetailTable() {
    const headerStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    const borderColor = Color(0xFFE1E9F3);

    // 计算合计
    num sumSale = 0;
    num sumPayable = 0;
    for (final r in _filteredList) {
      sumSale += num.tryParse(r['saleamt']?.toString() ?? '0') ?? 0;
      sumPayable += num.tryParse(r['payableamt']?.toString() ?? '0') ?? 0;
    }

    final rows = <TableRow>[];
    // 表头
    rows.add(const TableRow(
      decoration: BoxDecoration(color: Color(0xFFE8F0FE)),
      children: [
        _HeaderCell('序号', headerStyle, centered: true),
        _HeaderCell('交易类型', headerStyle, centered: true),
        _HeaderCell('应交款项', headerStyle, centered: true),
        _HeaderCell('收款金额', headerStyle, rightAligned: true),
        _HeaderCell('应交金额', headerStyle, rightAligned: true),
      ],
    ));

    // 数据行
    for (int i = 0; i < _filteredList.length; i++) {
      final r = _filteredList[i];
      final bgColor = i.isOdd ? const Color(0xFFF9F9F9) : Colors.white;
      rows.add(TableRow(
        decoration: BoxDecoration(color: bgColor),
        children: [
          _DataCell(Text('${i + 1}', style: cellStyle, textAlign: TextAlign.center),
              centered: true),
          _DataCell(Center(child: Text(_itypeName(r['itype']), style: cellStyle))),
          _DataCell(Center(
              child: Text(r['payway']?.toString() ?? '--',
                  style: cellStyle, textAlign: TextAlign.center))),
          _DataCell(Text(_fmtAmt(r['saleamt']), style: cellStyle), rightAligned: true),
          _DataCell(Text(_fmtAmt(r['payableamt']), style: cellStyle), rightAligned: true),
        ],
      ));
    }

    // 合计行
    const boldStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151));
    rows.add(const TableRow(
      decoration: BoxDecoration(color: Color(0xFFF0F4FF)),
      children: [
        _HeaderCell('', headerStyle),
        _HeaderCell('合计', boldStyle, centered: true),
        _HeaderCell('', headerStyle),
        _HeaderCell('', headerStyle, rightAligned: true),
        _HeaderCell('', headerStyle, rightAligned: true),
      ],
    ));
    // Replace empty cells with actual sum values
    rows[rows.length - 1] = TableRow(
      decoration: const BoxDecoration(color: Color(0xFFF0F4FF)),
      children: [
        const _DataCell(SizedBox.shrink()),
        const _DataCell(Center(child: Text('合计', style: boldStyle))),
        const _DataCell(SizedBox.shrink()),
        _DataCell(Text(_fmtAmt(sumSale), style: boldStyle), rightAligned: true),
        _DataCell(Text(_fmtAmt(sumPayable), style: boldStyle), rightAligned: true),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: const TableBorder(
          horizontalInside: BorderSide(color: borderColor),
          verticalInside: BorderSide(color: borderColor),
        ),
        columnWidths: const {
          0: FixedColumnWidth(48),
          1: FlexColumnWidth(3),
          2: FlexColumnWidth(3),
          3: FlexColumnWidth(2.8),
          4: FlexColumnWidth(2.8),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows,
      ),
    );
  }
}

/// 表头 Cell
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, this.style, {this.centered = false, this.rightAligned = false});
  final String label;
  final TextStyle style;
  final bool centered;
  final bool rightAligned;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: rightAligned
          ? Alignment.centerRight
          : centered
              ? Alignment.center
              : Alignment.centerLeft,
      child: Text(label, style: style),
    );
  }
}

/// 数据 Cell
class _DataCell extends StatelessWidget {
  const _DataCell(this.child, {this.centered = false, this.rightAligned = false});
  final Widget child;
  final bool centered;
  final bool rightAligned;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: rightAligned
          ? Alignment.centerRight
          : centered
              ? Alignment.center
              : Alignment.centerLeft,
      child: child,
    );
  }
}
