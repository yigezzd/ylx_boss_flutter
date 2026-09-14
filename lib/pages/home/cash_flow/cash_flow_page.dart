import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

/// 收银流水页面
/// 样式与交互逻辑对齐「采购入库」页面
class CashFlowPage extends StatefulWidget {
  const CashFlowPage({super.key});

  @override
  State<CashFlowPage> createState() => _CashFlowPageState();
}

class _CashFlowPageState extends State<CashFlowPage> {
  // ── 列表状态 ──
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  // ── 门店 ──
  String _storeName = '';
  List<int> _sids = [];
  String _activeStoreId = '';

  // ── 日期 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  // ── 汇总 ──
  double _totalAmount = 0;
  int _totalCount = 0;

  // ── 筛选参数 ──
  String _billno = '';
  String _billflag = '';
  String _saletype = '';
  String _cashid = '';
  String _cashname = '';
  String _machno = '';
  String _payid = '';
  String _payname = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = now;
    _startDate = DateTime(now.year, now.month, now.day); // 默认今天
    _activeQuickTimeId = 1; // 默认选中"今天"
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);

    return request(HttpApi.saleSelectFindSaleBill, {
      'is_page': 1,
      'cond': '',
      'page': _page,
      'pagesize': 20,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'sids': _sids,
      if (_billno.isNotEmpty) 'billno': _billno,
      if (_billflag.isNotEmpty) 'billflag': _billflag,
      if (_saletype.isNotEmpty) 'saletype': _saletype,
      if (_cashid.isNotEmpty) 'cashid': _cashid,
      if (_machno.isNotEmpty) 'machno': _machno,
      if (_payid.isNotEmpty) 'payid': _payid,
    }).then((result) {
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?) ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.isNotEmpty;
        _totalCount = int.tryParse(map['total']?.toString() ?? '') ?? 0;
        final sumdata = map['sumdata'];
        _totalAmount =
            double.tryParse((sumdata is Map ? sumdata['amt']?.toString() : '') ?? '') ?? 0;
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

  // ── 门店选择（底部抽屉）──
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _activeStoreId,
    );
    if (result != null && mounted) {
      setState(() {
        final storeId = result['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _sids = storeId.isNotEmpty ? [int.tryParse(storeId) ?? 0] : [];
        _storeName = result['storename']?.toString() ?? '';
        _page = 1;
        _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

  // ==================== 筛选抽屉 ====================
  static const _billflagOptions = [
    {'label': '全部', 'value': ''},
    {'label': '销售单', 'value': '0'},
    {'label': '退货单', 'value': '1'},
    {'label': '整单退货', 'value': '2'},
  ];

  static const _saletypeOptions = [
    {'label': '全部', 'value': ''},
    {'label': 'PC端销售', 'value': '1'},
    {'label': '微信商城', 'value': '2'},
    {'label': 'APP', 'value': '3'},
    {'label': '自助收银', 'value': '4'},
    {'label': '其他平台', 'value': '5'},
    {'label': '门店助手', 'value': '6'},
    {'label': '安卓收银端', 'value': '7'},
  ];

  void _openFilterSheet() {
    // ── 临时筛选状态 ──
    String tmpBillno = _billno;
    String tmpBillflag = _billflag;
    String tmpSaletype = _saletype;
    String tmpCashid = _cashid;
    String tmpCashname = _cashname;
    String tmpMachno = _machno;
    String tmpPayid = _payid;
    String tmpPayname = _payname;

    final billnoCtrl = TextEditingController(text: _billno);
    final machnoCtrl = TextEditingController(text: _machno);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // 标题栏
                  SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        const SizedBox(width: 48),
                        const Expanded(
                          child: Text(
                            '筛选',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
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
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  // 内容
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── 输入单号 ──
                          _buildFilterLabel('输入单号'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: billnoCtrl,
                            onChanged: (v) => tmpBillno = v,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '输入单号',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(left: 10, right: 6),
                                child: Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                              ),
                              prefixIconConstraints: const BoxConstraints(),
                              suffixIcon: tmpBillno.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () {
                                        billnoCtrl.clear();
                                        setSheetState(() => tmpBillno = '');
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 10),
                                        child:
                                            Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
                                      ),
                                    )
                                  : null,
                              suffixIconConstraints: const BoxConstraints(),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFF006EFF)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),

                          // ── 交易方式 ──
                          _buildFilterLabel('交易方式'),
                          const SizedBox(height: 8),
                          _buildChipGroup(
                            options: _billflagOptions,
                            selectedValue: tmpBillflag,
                            onSelected: (v) => setSheetState(() => tmpBillflag = v),
                          ),
                          const SizedBox(height: 22),

                          // ── 单据来源 ──
                          _buildFilterLabel('单据来源'),
                          const SizedBox(height: 8),
                          _buildChipGroup(
                            options: _saletypeOptions,
                            selectedValue: tmpSaletype,
                            onSelected: (v) => setSheetState(() => tmpSaletype = v),
                          ),
                          const SizedBox(height: 22),

                          // ── 收银员 ──
                          _buildFilterLabel('收银员'),
                          const SizedBox(height: 8),
                          _buildSelectorRow(
                            label: tmpCashname.isNotEmpty ? tmpCashname : '全部收银员',
                            onTap: () => _openUserSelector(ctx, setSheetState, (id, name) {
                              setSheetState(() {
                                tmpCashid = id;
                                tmpCashname = name;
                              });
                            }),
                          ),
                          const SizedBox(height: 22),

                          // ── 机号 ──
                          _buildFilterLabel('机号'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: machnoCtrl,
                            onChanged: (v) => tmpMachno = v,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '输入机号',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFF006EFF)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),

                          // ── 支付方式 ──
                          _buildFilterLabel('支付方式'),
                          const SizedBox(height: 8),
                          _buildSelectorRow(
                            label: tmpPayname.isNotEmpty ? tmpPayname : '全部',
                            onTap: () => _openPaySelector(ctx, setSheetState, (id, name) {
                              setSheetState(() {
                                tmpPayid = id;
                                tmpPayname = name;
                              });
                            }),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  // ── 底部按钮 ──
                  Container(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(ctx).padding.bottom + 12,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setSheetState(() {
                                tmpBillno = '';
                                tmpBillflag = '';
                                tmpSaletype = '';
                                tmpCashid = '';
                                tmpCashname = '';
                                tmpMachno = '';
                                tmpPayid = '';
                                tmpPayname = '';
                                billnoCtrl.clear();
                                machnoCtrl.clear();
                              });
                            },
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFCCCCCC)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '重置',
                                style: TextStyle(fontSize: 15, color: Color(0xFF333333)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _billno = tmpBillno;
                                _billflag = tmpBillflag;
                                _saletype = tmpSaletype;
                                _cashid = tmpCashid;
                                _cashname = tmpCashname;
                                _machno = tmpMachno;
                                _payid = tmpPayid;
                                _payname = tmpPayname;
                                _page = 1;
                                _list = [];
                                _hasMore = true;
                              });
                              Navigator.pop(ctx);
                              _loadData();
                            },
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF006EFF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '确定',
                                style: TextStyle(fontSize: 15, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── 筛选辅助 Widget ──
  static Widget _buildFilterLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
    );
  }

  static Widget _buildChipGroup({
    required List<Map<String, String>> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final val = opt['value']!;
        final label = opt['label']!;
        final selected = selectedValue == val;
        return GestureDetector(
          onTap: () => onSelected(val),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF006EFF) : Colors.white,
              border: Border.all(
                color: selected ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : const Color(0xFF333333),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  static Widget _buildSelectorRow({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  // ── 时间选择器（主页面，参考 Vue selectTime 组件）──
  Widget _buildTimeSelector() {
    final labels = ['昨天', '今日', '本周', '本月', '自定义'];
    final activeId = _activeQuickTimeId ?? 1;
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    const borderColor = Color(0xFFD1D5DB);

    return Container(
      color: surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        children: [
          // ── 分段控制器：昨天 今日 本周 本月 自定义 ──
          Container(
            height: 37,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: List.generate(labels.length, (i) {
                final selected = activeId == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onQuickTimeSelect(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? onPrimary : onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          // ── 日期导航行 ──
          _buildDateNavigation(),
        ],
      ),
    );
  }

  void _onQuickTimeSelect(int id) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (id) {
      case 0: // 昨天
        start = now.subtract(const Duration(days: 1));
        end = start;
        break;
      case 1: // 今天
        start = now;
        end = now;
        break;
      case 2: // 本周
        final weekday = now.weekday;
        start = now.subtract(Duration(days: weekday - 1));
        end = start.add(const Duration(days: 6));
        break;
      case 3: // 本月
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      default: // 自定义
        start = _startDate;
        end = _endDate;
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _activeQuickTimeId = id;
      _page = 1;
      _list = [];
      _hasMore = true;
    });
    _loadData();
  }

  Widget _buildDateNavigation() {
    final isRange = _activeQuickTimeId == 2 || _activeQuickTimeId == 4;
    final isMonth = _activeQuickTimeId == 3;
    final showArrows = _activeQuickTimeId != 4;

    return Row(
      children: [
        // 左箭头
        if (showArrows)
          GestureDetector(
            onTap: () => _timeShift(-1),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(Icons.chevron_left,
                  size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        if (showArrows) const SizedBox(width: 8),
        // 日期区域
        Expanded(
          child: Row(
            children: [
              if (isRange) ...[
                Expanded(child: _buildDatePart(_startDate, isStart: true)),
                _buildDateToSeparator(),
                Expanded(child: _buildDatePart(_endDate, isEnd: true)),
              ] else
                Expanded(
                  child: _buildDatePart(_startDate, isMonth: isMonth),
                ),
            ],
          ),
        ),
        if (showArrows) const SizedBox(width: 8),
        // 右箭头
        if (showArrows)
          GestureDetector(
            onTap: () => _timeShift(1),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(Icons.chevron_right,
                  size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildDatePart(DateTime date,
      {bool isStart = false, bool isEnd = false, bool isMonth = false}) {
    String label;
    if (isMonth) {
      label = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    } else {
      label = _fmtDate(date);
    }

    Future<void> onTap() async {
      if (isMonth) {
        // 本月模式：只选年月
        final picked = await showCommonMonthPicker(context, initial: date);
        if (picked != null && mounted) {
          setState(() {
            _startDate = DateTime(picked.year, picked.month);
            _endDate = DateTime(picked.year, picked.month + 1, 0);
            _page = 1;
            _list = [];
            _hasMore = true;
          });
          _loadData();
        }
        return;
      }
      final picked = await showCommonDatePicker(context, initial: date);
      if (picked != null && mounted) {
        setState(() {
          if (isEnd) {
            _endDate = picked;
          } else if (isStart) {
            _startDate = picked;
          } else {
            // 单日模式：起止时间同步
            _startDate = picked;
            _endDate = picked;
          }
          _page = 1;
          _list = [];
          _hasMore = true;
        });
        _loadData();
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        margin: EdgeInsets.only(
          left: isStart ? 0 : 4,
          right: isEnd ? 0 : 4,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _buildDateToSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('至',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface)),
    );
  }

  void _timeShift(int direction) {
    final id = _activeQuickTimeId ?? 1;
    DateTime start = _startDate;
    DateTime end = _endDate;
    switch (id) {
      case 0: // 昨天 → ±1 day
      case 1: // 今天 → ±1 day
        start = start.add(Duration(days: direction));
        end = start;
        break;
      case 2: // 本周 → ±7 days
        start = start.add(Duration(days: 7 * direction));
        end = end.add(Duration(days: 7 * direction));
        break;
      case 3: // 本月 → ±1 month
        start = DateTime(_startDate.year, _startDate.month + direction);
        end = DateTime(start.year, start.month + 1, 0);
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _page = 1;
      _list = [];
      _hasMore = true;
    });
    _loadData();
  }

  // ── 收银员选择器 ──
  void _openUserSelector(
    BuildContext parentCtx,
    StateSetter setSheetState,
    void Function(String id, String name) onSelected,
  ) {
    showModalBottomSheet<void>(
      context: parentCtx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SelectorSheet(
          title: '选择收银员',
          apiPath: HttpApi.sysUserList,
          nameKey: 'name',
          idKey: 'userid',
          codeKey: 'code',
          onSelected: (String id, String name) {
            onSelected(id, name);
          },
        );
      },
    );
  }

  // ── 支付方式选择器 ──
  void _openPaySelector(
    BuildContext parentCtx,
    StateSetter setSheetState,
    void Function(String id, String name) onSelected,
  ) {
    showModalBottomSheet<void>(
      context: parentCtx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SelectorSheet(
          title: '选择支付方式',
          apiPath: HttpApi.paywayGetList,
          nameKey: 'name',
          idKey: 'payid',
          codeKey: 'code',
          params: _sids.isNotEmpty ? {'sids': _sids} : null,
          onSelected: (String id, String name) {
            onSelected(id, name);
          },
        );
      },
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
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '收银流水',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // ── 门店选择下拉（占满宽度）──
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStore,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _storeName.isNotEmpty ? _storeName : '全部机构',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // ── 筛选按钮 ──
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDEDEDE)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const BossSvgIcon(
                        svgFile: 'fliter.svg',
                        size: 22,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildTimeSelector(),
          if (_list.isEmpty && !_loading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                    SizedBox(height: 12),
                    Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
            )
          else ...[_buildSummaryBar(), Expanded(child: _buildTableArea())],
        ],
      ),
    );
  }

  /// 表格区域：DataTable2 — 固定单号列 + 横向滚动 + 表头固定
  Widget _buildTableArea() {
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

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100 &&
            !_loading &&
            _hasMore) {
          _page++;
          _loadData();
        }
        return false;
      },
      child: RefreshIndicator(
        color: const Color(0xFF006EFF),
        onRefresh: _onRefresh,
        child: DataTable2(
          fixedLeftColumns: 1,
          minWidth: 630,
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
            DataColumn2(
              fixedWidth: 150,
              label: Container(
                padding: const EdgeInsets.only(left: 5, right: 12),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('单号', style: headerStyle),
                    SizedBox(width: 2),
                    // Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFFF59E0B)),
                  ],
                ),
              ),
            ),
            const DataColumn2(
                label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('支付方式', style: headerStyle),
            )),
            const DataColumn2(
              label: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('销售金额', textAlign: TextAlign.right, style: headerStyle),
              ),
              numeric: true,
            ),
            const DataColumn2(
                label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('交易方式', style: headerStyle),
            )),
            const DataColumn2(
                label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('收银员', style: headerStyle),
            )),
            const DataColumn2(
                label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('单据来源', style: headerStyle),
            )),
          ],
          rows: [
            for (var i = 0; i < _list.length; i++) _buildDataRow(_list[i], i),
            if (_loading)
              const DataRow(cells: [
                DataCell(SizedBox(
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
                    ),
                  ),
                )),
                DataCell.empty,
                DataCell.empty,
                DataCell.empty,
                DataCell.empty,
                DataCell.empty,
              ]),
          ],
        ),
      ),
    );
  }

  // ==================== 统计栏 ====================
  Widget _buildSummaryBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
          children: [
            const TextSpan(text: '单据数量：'),
            TextSpan(
              text: '$_totalCount',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333)),
            ),
            const TextSpan(text: '   总金额：'),
            TextSpan(
              text: _totalAmount.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333)),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== DataRow 构建 ====================
  DataRow2 _buildDataRow(Map<String, dynamic> row, int index) {
    final billno = (row['billno'] ?? '-').toString();
    final billdate = (row['billdate'] ?? '-').toString();
    final paywayname = (row['paywayname'] ?? '-').toString();
    final payment = (row['payment'] ?? '0').toString();
    final cashname = (row['cashname'] ?? '-').toString();
    final saletype = (row['saletype'] ?? '-').toString();

    // ── 交易方式映射 ──
    String mapBillFlag(String? code) {
      switch (code?.toString()) {
        case '0':
          return '销售';
        case '1':
          return '退货';
        case '2':
          return '已整单退货';
        default:
          return code ?? '-';
      }
    }

    final billflagDisplay =
        mapBillFlag(row['billflag']?.toString() ?? row['billflagname']?.toString());

    const smallGrey = TextStyle(fontSize: 11, color: Color(0xFF999999));
    const cellStyle = TextStyle(fontSize: 13, color: Color(0xFF333333));
    const fixedStyle = TextStyle(fontSize: 13, color: Color(0xFF006EFF));
    const amountStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF333333));

    const cellPad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final isOdd = index.isOdd;

    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(
          right: BorderSide(color: Color(0xFFE1E9F3)),
        ),
      ),
      cells: [
        DataCell(Padding(
          padding: const EdgeInsets.fromLTRB(5, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(billno, maxLines: 1, overflow: TextOverflow.ellipsis, style: fixedStyle),
              const SizedBox(height: 4),
              Text(billdate, maxLines: 1, overflow: TextOverflow.ellipsis, style: smallGrey),
            ],
          ),
        )),
        DataCell(Padding(
          padding: cellPad,
          child: Text(paywayname, style: cellStyle),
        )),
        DataCell(Padding(
          padding: cellPad,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(payment, style: amountStyle),
          ),
        )),
        DataCell(Padding(
          padding: cellPad,
          child:
              Text(billflagDisplay, maxLines: 1, overflow: TextOverflow.ellipsis, style: cellStyle),
        )),
        DataCell(Padding(
          padding: cellPad,
          child: Text(cashname, maxLines: 1, overflow: TextOverflow.ellipsis, style: cellStyle),
        )),
        DataCell(Padding(
          padding: cellPad,
          child: Text(saletype, maxLines: 1, overflow: TextOverflow.ellipsis, style: cellStyle),
        )),
      ],
    );
  }
}

/// 通用选择器底部弹窗（收银员/支付方式等）
class _SelectorSheet extends StatefulWidget {
  const _SelectorSheet({
    required this.title,
    required this.apiPath,
    required this.nameKey,
    required this.idKey,
    this.codeKey,
    this.params,
    required this.onSelected,
  });

  final String title;
  final String apiPath;
  final String nameKey;
  final String idKey;
  final String? codeKey;
  final Map<String, dynamic>? params;
  final void Function(String id, String name) onSelected;

  @override
  State<_SelectorSheet> createState() => _SelectorSheetState();
}

class _SelectorSheetState extends State<_SelectorSheet> {
  List<Map<String, dynamic>> _list = [];
  List<Map<String, dynamic>> _filteredList = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final params = <String, dynamic>{
      'is_page': 1,
      'pagesize': 999,
      if (widget.params != null) ...widget.params!,
    };
    try {
      final result = await request(widget.apiPath, params);
      final data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?) ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _list = rows;
          _filteredList = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String v) {
    setState(() {
      if (v.isEmpty) {
        _filteredList = _list;
      } else {
        _filteredList = _list.where((item) {
          final name = (item[widget.nameKey] ?? '').toString();
          final code = widget.codeKey != null ? (item[widget.codeKey!] ?? '').toString() : '';
          return name.contains(v) || code.contains(v);
        }).toList();
      }
    });
  }

  String _displayName(Map<String, dynamic> item) {
    final name = (item[widget.nameKey] ?? '').toString();
    final code = widget.codeKey != null ? (item[widget.codeKey!] ?? '').toString() : '';
    if (code.isNotEmpty) {
      return '[$code]$name';
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 标题栏
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '输入名称/编码',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 10, right: 6),
                  child: Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                ),
                prefixIconConstraints: const BoxConstraints(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF006EFF)),
                ),
              ),
            ),
          ),
          // 全部选项
          GestureDetector(
            onTap: () {
              widget.onSelected('', '');
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      '全部',
                      style: TextStyle(fontSize: 14, color: Color(0xFF006EFF)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredList.isEmpty
                    ? const Center(
                        child: Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF))),
                      )
                    : ListView.builder(
                        itemCount: _filteredList.length,
                        itemExtent: 48,
                        cacheExtent: 800,
                        itemBuilder: (ctx, i) {
                          final item = _filteredList[i];
                          final id = (item[widget.idKey] ?? '').toString();
                          final display = _displayName(item);
                          return RepaintBoundary(
                            child: GestureDetector(
                              onTap: () {
                                widget.onSelected(id, display);
                                Navigator.pop(context);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.centerLeft,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Color(0xFFF0F0F0)),
                                  ),
                                ),
                                child: Text(
                                  display,
                                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
