import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/chain/returnapplication/edit.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

/// 配退申请单查询/选择页（对齐 Vue chain/returnApplication/search.vue）
/// isSelect=true 时作为配退发货的"选择配退申请单"页面：
/// 标题"选择配退申请单"、时间默认今天、signflag=1、mergData 并入请求参数、点击回传整张单据
class ReturnApplicationSearchPage extends StatefulWidget {
  const ReturnApplicationSearchPage({super.key, this.isSelect = false, this.mergData});

  final bool isSelect;

  /// 原单选择透传参数（对齐 Vue search.vue：opt.mergData Object.assign 进 params）
  final Map<String, dynamic>? mergData;

  @override
  State<ReturnApplicationSearchPage> createState() => _ReturnApplicationSearchPageState();
}

class _ReturnApplicationSearchPageState extends State<ReturnApplicationSearchPage>
    with LogPageMixin<ReturnApplicationSearchPage> {
  @override
  String get logPageName => widget.isSelect ? '选择配退申请单' : '配退申请单';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  // 时间筛选（收银流水同款：昨天/今日/本周/本月/自定义，对齐配送收货单选择页）
  static const _quickLabels = ['昨天', '今日', '本周', '本月', '自定义'];
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 统一默认今天（对齐配送收货单选择页）
    final now = DateTime.now();
    _startDate = now;
    _endDate = now;
    _activeQuickTimeId = 1; // 默认"今日"
    _loadData();
    logEnter();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  /// 对齐 Vue retParam：重置页码并加载
  void _reload() {
    setState(() {
      _page = 1;
      _list = [];
      _hasMore = true;
    });
    _loadData();
  }

  /// 快捷时间切换（对齐配送收货单选择页：昨天/今日±1天、本周±7天起止、本月月首至月末）
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
      default: // 自定义（沿用当前已选区间）
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

  /// 日期区间平移（对齐配送收货单选择页：单日±1天/本周±7天/本月±1月；自定义无箭头）
  void _timeShift(int direction) {
    final id = _activeQuickTimeId ?? 1;
    DateTime start = _startDate;
    DateTime end = _endDate;
    switch (id) {
      case 0: // 昨天 → ±1 day
      case 1: // 今日 → ±1 day
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

  /// 对齐 Vue getList：psrefundapply/findList（isSelect 时拼 starttime/endtime 当天区间）
  void _loadData() {
    if (_loading || !_hasMore) return;
    _loading = true;
    final Map<String, dynamic> params = {
      'is_page': 1,
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'pagesize': 20,
      'billno': _searchController.text.trim(),
      'signflag': widget.isSelect ? '1' : '',
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'counterid': '',
      'countername': '',
      'createid': '',
      'createname': '',
    };
    // 对齐 Vue onLoad：opt.mergData 并入请求参数（outsid/insid 等机构过滤）
    if (widget.mergData != null) params.addAll(widget.mergData!);
    request(HttpApi.psrefundapplyFindList, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= 20;
      });
    }).catchError((_) {
      if (mounted) setState(() => _hasMore = false);
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(
          widget.isSelect ? '选择配退申请单' : '配退申请单',
          style:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: Column(children: [
        _buildSearchBar(),
        _buildTimeSelector(),
        Expanded(
            child: _list.isEmpty && !_loading
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                            SizedBox(height: 12),
                            Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    cacheExtent: 800,
                    itemCount: _list.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _list.length) {
                        return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                                child: Text('加载中...',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF999999)))));
                      }
                      final item = _list[index];
                      return RepaintBoundary(
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: _BillCard(
                                  item: item,
                                  onTap: () {
                                    if (widget.isSelect) {
                                      Navigator.pop(context, item);
                                    } else {
                                      // 对齐 Vue selectItemFn：非选择模式需 013308 查看权限
                                      if (!PermissionUtils.checkPermission('013308',
                                          showTip: false)) {
                                        Toast.show('你无权查看配退申请单，请在后台修改权限');
                                        return;
                                      }
                                      Navigator.push(
                                          context,
                                          MaterialPageRoute<ReturnApplicationEditPage>(
                                              builder: (_) =>
                                                  ReturnApplicationEditPage(billData: item)));
                                    }
                                  })));
                    },
                  )),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: TextField(
        controller: _searchController,
        onSubmitted: (_) => _reload(),
        onChanged: (_) => _onSearchChanged(),
        decoration: InputDecoration(
          hintText: '请输入单号',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _onSearchChanged();
                  },
                  child: Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF6B7280),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.close, size: 10, color: Colors.white),
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 24),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFF006EFF)),
          ),
        ),
      ),
    );
  }

  // =================== 时间选择器（收银流水同款，对齐配送收货单选择页） ===================

  Widget _buildTimeSelector() {
    final activeId = _activeQuickTimeId ?? 1;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        children: [
          // ── 分段控制器：昨天 今日 本周 本月 自定义 ──
          Container(
            height: 37,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: List.generate(_quickLabels.length, (i) {
                final selected = activeId == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onQuickTimeSelect(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF006EFF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _quickLabels[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? Colors.white : const Color(0xFF333333),
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
              child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF6B7280)),
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
              child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF6B7280)),
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
          style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
        ),
      ),
    );
  }

  Widget _buildDateToSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Text('至',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
    );
  }
}

/// 配退申请单卡片（对齐 list.dart _ReturnApplicationCard：
/// 单号+配退类型浅底标签+审核状态/申请门店+配送中心/单据金额+制单人/制单时间）
class _BillCard extends StatelessWidget {
  const _BillCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static String _statusLabel(String? signflag) {
    if (signflag == '1') return '已审核';
    if (signflag == '2') return '已驳回';
    if (signflag == '-1') return '已作废';
    return '待审核';
  }

  static Color _statusColor(String? signflag) {
    if (signflag == '1') return const Color(0xFF00A870);
    if (signflag == '2') return const Color(0xFFFF9900);
    if (signflag == '-1') return const Color(0xFFAAAAAA);
    return const Color(0xFFD54B5A);
  }

  static String _refundtypeLabel(String? refundtype) {
    if (refundtype == '1') return '配送差异';
    if (refundtype == '2') return '退货';
    return '';
  }

  static String _fmtAmt(dynamic value) {
    final v = double.tryParse(value?.toString() ?? '0') ?? 0.0;
    return v.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '-';
    final String outstorename = item['outstorename']?.toString() ?? '';
    final String instorename = item['instorename']?.toString() ?? '';
    final String billamt = _fmtAmt(item['billamt']);
    final String createname = item['createname']?.toString() ?? '-';
    final String createtime = item['createtime']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
    final String refundtypeLabel = _refundtypeLabel(item['refundtype']?.toString());
    final Color statusColor = _statusColor(signflag);
    final String statusLabel = _statusLabel(signflag);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第1行：单号 + 配退类型标签 + 审核状态
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(billno,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827)),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (refundtypeLabel.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: refundtypeLabel == '配送差异'
                                  ? const Color(0xFFEAF3FF)
                                  : const Color(0xFFFFF4E5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(refundtypeLabel,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: refundtypeLabel == '配送差异'
                                        ? const Color(0xFF006EFF)
                                        : const Color(0xFFFF9900))),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(statusLabel,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
                ],
              ),
              const SizedBox(height: 8),
              // 第2行：申请门店 + 配送中心
              Row(
                children: [
                  Expanded(
                    child: Text('申请门店：$outstorename',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Text('配送中心：$instorename',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 第3行：单据金额 + 制单人
              Row(
                children: [
                  Expanded(
                    child: Text('单据金额：$billamt',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Text('制单人：$createname',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              Container(
                height: 1,
                color: const Color(0xFFEBEBEB),
                margin: const EdgeInsets.symmetric(vertical: 8),
              ),
              // 第4行：制单时间
              Text('制单时间：$createtime',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            ],
          ),
        ),
      ),
    );
  }
}
