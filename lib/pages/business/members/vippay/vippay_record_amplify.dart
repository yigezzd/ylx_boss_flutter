import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

/// 收款记录 - 放大表格页 —— 对齐 boss 项目 subs/comPages/amplifyTable.vue（收款记录场景）
///
/// - 6 列按比例铺满内容区（合计比例 1.0，无需横向滚动）：
///   单据编号 0.26 / 会员卡号 0.19 / 会员姓名 0.15 / 交易金额 0.15 / 本金 0.12 / 赠金 0.13；
/// - 单号列双行展示（billno 蓝 + billdate 灰，对齐默认 formatter）；
/// - 底部合计行固定在表格下方（首列"合计" + 按列名取 sumdata，对齐 getSummaries）；
/// - 右侧时间快捷栏（昨天/今天/本周/本月 + 自定义起止，宽 130）；
/// - 分页加载、下拉刷新。
class VippayRecordAmplifyPage extends StatefulWidget {
  const VippayRecordAmplifyPage({super.key, required this.params});

  /// 列表页透传的查询参数（含 field/type/cond/opertype/sids/sidsname/starttime/endtime 等）
  final Map<String, dynamic> params;

  @override
  State<VippayRecordAmplifyPage> createState() => _VippayRecordAmplifyPageState();
}

class _VippayRecordAmplifyPageState extends State<VippayRecordAmplifyPage> {
  static const int _pageSize = 20;
  static const double _timeBarWidth = 130;

  // ── 列表状态 ──
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _hasLoadedOnce = false;
  List<Map<String, dynamic>> _list = [];

  // ── 合计 ──
  Map<String, dynamic> _sumdata = {};

  // ── 时间（yyyy-MM-dd）──
  late String _startTime;
  late String _endTime;
  int? _activeQuickTimeId;

  /// 放大表格列配置（align/fietype 对齐 record.vue amplifyFn 传参）
  static const List<_AmplifyColumn> _columns = [
    _AmplifyColumn(name: 'billno', label: '单据编号', ratio: 0.26),
    _AmplifyColumn(name: 'vipno', label: '会员卡号', ratio: 0.19),
    _AmplifyColumn(name: 'vipname', label: '会员姓名', ratio: 0.15),
    _AmplifyColumn(name: 'addmoney', label: '交易金额', ratio: 0.15, align: 'right', fietype: 4),
    _AmplifyColumn(name: 'capitalmoney', label: '本金', ratio: 0.12, align: 'right', fietype: 4),
    _AmplifyColumn(name: 'givemoney', label: '赠金', ratio: 0.13, align: 'right', fietype: 4),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startTime = widget.params['starttime']?.toString() ?? _fmtDate(now);
    _endTime = widget.params['endtime']?.toString() ?? _fmtDate(now);
    _loadData();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ==================== 数据加载 ====================

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);

    return request(HttpApi.vipTableGetVipCardDetailList, {
      ...widget.params,
      'is_page': 1,
      'page': _page,
      'pagesize': _pageSize,
      'starttime': '$_startTime 00:00:00',
      'endtime': '$_endTime 23:59:59',
    }).then((result) {
      final dynamic data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?) ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= _pageSize;
        _hasLoadedOnce = true;
        final dynamic sumdata = map['sumdata'];
        _sumdata = sumdata is Map ? sumdata.cast<String, dynamic>() : <String, dynamic>{};
      });
    }).catchError((_) {
      setState(() => _hasMore = false);
    }).whenComplete(() {
      setState(() => _loading = false);
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _reload() {
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification &&
        notification.metrics.axis == Axis.vertical &&
        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
    return false;
  }

  // ==================== 时间快捷栏 ====================

  void _onQuickTimeSelect(int index) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (index) {
      case 0: // 昨天
        start = now.subtract(const Duration(days: 1));
        end = start;
        break;
      case 1: // 今天
        start = now;
        end = now;
        break;
      case 2: // 本周
        final int weekday = now.weekday;
        start = now.subtract(Duration(days: weekday - 1));
        end = start.add(const Duration(days: 6));
        break;
      default: // 本月
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
    }
    setState(() {
      _startTime = _fmtDate(start);
      _endTime = _fmtDate(end);
      _activeQuickTimeId = index;
    });
    _reload();
  }

  Future<void> _pickTime(bool isStart) async {
    final DateTime initial = DateTime.tryParse(isStart ? _startTime : _endTime) ?? DateTime.now();
    final picked = await showCommonDatePicker(context, initial: initial);
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startTime = _fmtDate(picked);
        } else {
          _endTime = _fmtDate(picked);
        }
        _activeQuickTimeId = -1; // 自定义
      });
      _reload();
    }
  }

  Widget _buildTimeBar() {
    const List<String> tabs = ['昨天', '今天', '本周', '本月'];
    final Color customColor =
        _activeQuickTimeId == -1 ? const Color(0xFF006EFF) : const Color(0xFF333333);

    return Container(
      width: _timeBarWidth,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFF5F5F5), width: 4)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            GestureDetector(
              onTap: () => _onQuickTimeSelect(i),
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _activeQuickTimeId == i ? const Color(0xFF0081FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    color: _activeQuickTimeId == i ? Colors.white : const Color(0xFF333333),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 4),
          // ── 自定义起止时间 ──
          GestureDetector(
            onTap: () => _pickTime(true),
            child: Container(
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(_startTime, style: TextStyle(fontSize: 11, color: customColor)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('至', style: TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
          GestureDetector(
            onTap: () => _pickTime(false),
            child: Container(
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(_endTime, style: TextStyle(fontSize: 11, color: customColor)),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== build ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '收款记录',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double contentW = constraints.maxWidth;
                final List<double> widths = _columns.map((c) => contentW * c.ratio).toList();
                return Column(
                  children: [
                    Expanded(child: _buildTable(widths)),
                    _buildSummaryRow(widths),
                  ],
                );
              },
            ),
          ),
          // ── 右侧时间快捷栏 ──
          _buildTimeBar(),
        ],
      ),
    );
  }

  Widget _buildTable(List<double> widths) {
    const headerStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF374151),
    );

    if (_list.isEmpty && !_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }

    if (_list.isEmpty && !_hasLoadedOnce) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF)),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: RefreshIndicator(
        color: const Color(0xFF006EFF),
        onRefresh: _onRefresh,
        child: DataTable2(
          fixedLeftColumns: 1,
          minWidth: widths.fold<double>(0.0, (double sum, double w) => sum + w),
          horizontalMargin: 0,
          columnSpacing: 0,
          dataRowHeight: 58,
          headingRowHeight: 44,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
          border: const TableBorder(
            horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
            verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
          ),
          columns: [
            for (var i = 0; i < _columns.length; i++)
              DataColumn2(
                fixedWidth: widths[i],
                label: Align(
                  alignment:
                      _columns[i].align == 'right' ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      _columns[i].label,
                      style: headerStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
          rows: [
            for (var i = 0; i < _list.length; i++) _buildDataRow(_list[i], i),
            if (_loading && (_page > 1 || !_hasLoadedOnce))
              DataRow(cells: [
                const DataCell(SizedBox(
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
                    ),
                  ),
                )),
                for (var i = 1; i < _columns.length; i++) DataCell.empty,
              ]),
          ],
        ),
      ),
    );
  }

  DataRow2 _buildDataRow(Map<String, dynamic> row, int index) {
    final bool isOdd = index.isOdd;
    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(
          right: BorderSide(color: Color(0xFFE1E9F3)),
        ),
      ),
      cells: [
        // 单号列：双行展示（billno 蓝 + billdate 灰，对齐默认 formatter）
        DataCell(Padding(
          padding: const EdgeInsets.fromLTRB(5, 6, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (row['billno']?.toString() ?? '').isEmpty ? '--' : row['billno'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF)),
              ),
              const SizedBox(height: 4),
              Text(
                row['billdate']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
              ),
            ],
          ),
        )),
        for (var i = 1; i < _columns.length; i++) _buildCell(_columns[i], row),
      ],
    );
  }

  DataCell _buildCell(_AmplifyColumn col, Map<String, dynamic> row) {
    final dynamic raw = row[col.name];
    final String text;
    if (col.fietype != null) {
      text = MathUtils.formatDecimal(col.fietype!, raw ?? 0);
    } else {
      final String v = raw?.toString() ?? '';
      text = v.isEmpty ? '--' : v;
    }
    return DataCell(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: col.align == 'right' ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
          ),
        ),
      ),
    );
  }

  // ==================== 合计行 ====================

  /// 合计文本（对齐 amplifyTable.vue getSummaries：按列名取 sumdata，无值显示空）
  String _summaryText(_AmplifyColumn col) {
    final dynamic v = _sumdata[col.name];
    if (v == null) return '';
    if (col.fietype != null) return MathUtils.formatDecimal(col.fietype!, v);
    return v.toString();
  }

  Widget _buildSummaryRow(List<double> widths) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFE8F0FE),
        border: Border(
          top: BorderSide(color: Color(0xFFE1E9F3)),
          right: BorderSide(color: Color(0xFFE1E9F3)),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _columns.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment:
                      _columns[i].align == 'right' ? Alignment.centerRight : Alignment.centerLeft,
                  child: Text(
                    i == 0 ? '合计' : _summaryText(_columns[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500,
                      color: const Color(0xFF333333),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 放大表格列配置（比例为相对内容区的占比，合计为 1.0）
class _AmplifyColumn {
  const _AmplifyColumn({
    required this.name,
    required this.label,
    required this.ratio,
    this.align = 'left',
    this.fietype,
  });

  final String name;
  final String label;
  final double ratio;

  /// 对齐方式：left / right
  final String align;

  /// 数值格式化类型（>=2 时触发 formatDecimal）
  final int? fietype;
}
