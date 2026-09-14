import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/chain/receivingnote/edit.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

/// 原单查询/选择共用页面（供配退申请/配退发货/调拨入库/配送发货等模块选单用）
/// 按 [SearchBillType] 区分：
/// - 配送收货单走 psstockin/findList + 收货单卡片（配退申请/配退发货）
/// - 调拨申请单走 dborder/findList + 调拨申请卡片（调拨入库/调拨出库）
/// - 要货申请单走 yhorder/findList + 要货申请卡片（配送发货）
/// isSelect=true 时点击回传整张单据；时间组件为收银流水同款
enum SearchBillType {
  /// 配送收货单（psstockin/findList）
  receivingnote,

  /// 调拨申请单（dborder/findList）
  allotApply,

  /// 要货申请单（yhorder/findList）
  enquiry,
}

class ReceivingnoteSearchPage extends StatefulWidget {
  const ReceivingnoteSearchPage({
    super.key,
    this.isSelect = false,
    this.mergData,
    this.billType = SearchBillType.receivingnote,
  });

  final bool isSelect;

  /// 单据类型：决定请求接口、标题与列表卡片样式
  final SearchBillType billType;

  /// 原单选择透传参数（对齐 Vue opt.mergData：Object.assign 进 params）
  final Map<String, dynamic>? mergData;

  @override
  State<ReceivingnoteSearchPage> createState() => _ReceivingnoteSearchPageState();
}

class _ReceivingnoteSearchPageState extends State<ReceivingnoteSearchPage>
    with LogPageMixin<ReceivingnoteSearchPage> {
  /// 调拨申请单模式（决定接口与卡片样式）
  bool get _isAllotApply => widget.billType == SearchBillType.allotApply;

  /// 要货申请单模式（决定接口与卡片样式）
  bool get _isEnquiry => widget.billType == SearchBillType.enquiry;

  /// 单据类型名（供标题与日志使用）
  String get _typeName => _isAllotApply ? '调拨申请单' : (_isEnquiry ? '要货申请单' : '配送收货单');

  /// 页面标题（选择模式加"选择"前缀）
  String get _pageTitle => widget.isSelect ? '选择$_typeName' : _typeName;

  @override
  String get logPageName => _pageTitle;

  // ── 列表状态 ──
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  // ── 时间筛选（收银流水同款：昨天/今日/本周/本月/自定义） ──
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
    final now = DateTime.now();
    // 统一默认今天
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

  /// 重置页码并加载
  void _reload() {
    setState(() {
      _page = 1;
      _list = [];
      _hasMore = true;
    });
    _loadData();
  }

  /// 对齐 Vue getList：按单据类型请求不同接口
  /// 配送收货单 psstockin/findList；调拨申请单 dborder/findList；要货申请单 yhorder/findList
  void _loadData() {
    if (_loading || !_hasMore) return;
    _loading = true;
    final Map<String, dynamic> common = {
      'is_page': 1,
      'type': 'desc',
      'page': _page,
      'pagesize': 20,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
    };
    if (widget.mergData != null) common.addAll(widget.mergData!);
    String api;
    if (_isAllotApply) {
      // 对齐 Vue：调拨申请单按审核时间倒序、仅已审核、配货完成
      common.addAll({
        'field': 'signtime',
        'billno': _searchController.text.trim(),
        'signflag': '1',
        'phstatusflag': 1,
      });
      api = HttpApi.dborderFindList;
    } else if (_isEnquiry) {
      // 对齐 Vue：要货申请单按制单时间倒序、仅已审核（hideoutdateflag/phstatusfilter 为原选择页固定过滤）
      common.addAll({
        'field': 'createtime',
        'billno': _searchController.text.trim(),
        'signflag': '1',
        'datetype': '1',
        'hideoutdateflag': 1,
        'phstatusfilter': 1,
      });
      api = HttpApi.yhorderFindList;
    } else {
      common.addAll({
        'field': 'createtime',
        'billno': _searchController.text.trim(),
        'signflag': widget.isSelect ? '1' : '',
        'datetype': '1',
      });
      api = HttpApi.psstockinFindList;
    }
    request(api, common).then((result) {
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

  // =================== 时间选择器（收银流水同款） ===================

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

  // =================== Build ===================

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
          _pageTitle,
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
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
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
                      final Widget card;
                      if (_isAllotApply) {
                        card = _AllotApplyCard(item: item, onTap: () => _handleCardTap(item));
                      } else if (_isEnquiry) {
                        card = _EnquiryApplyCard(item: item, onTap: () => _handleCardTap(item));
                      } else {
                        card = _BillCard(item: item, onTap: () => _handleCardTap(item));
                      }
                      return RepaintBoundary(
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4), child: card));
                    },
                  )),
      ]),
    );
  }

  /// 卡片点击：非收货单类型或选择模式直接回传整单；
  /// 配送收货单非选择模式进详情页（需 013208 查看权限）
  void _handleCardTap(Map<String, dynamic> item) {
    if (_isAllotApply || _isEnquiry || widget.isSelect) {
      Navigator.pop(context, item);
      return;
    }
    if (!PermissionUtils.checkPermission('013208', showTip: false)) {
      Toast.show('你无权查看配送收货单，请在后台修改权限');
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute<ReceivingnoteEditPage>(
            builder: (_) => ReceivingnoteEditPage(billData: item)));
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
}

/// 配送收货单卡片（对齐截图样式：单号+状态标签/门店信息/金额+制单人/制单时间）
class _BillCard extends StatelessWidget {
  const _BillCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  String _statusLabel() {
    final signflag = item['signflag']?.toString() ?? '';
    if (signflag == '1') return '已审核';
    if (signflag == '2') return '已驳回';
    if (signflag == '-1') return '已作废';
    return '待审核';
  }

  Color _statusColor() {
    final signflag = item['signflag']?.toString() ?? '';
    if (signflag == '1') return const Color(0xFF00A870);
    if (signflag == '2') return const Color(0xFFFF9900);
    if (signflag == '-1') return const Color(0xFFAAAAAA);
    return const Color(0xFFD54B5A);
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = _statusLabel();
    final statusColor = _statusColor();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 行1：单号 + 状态标签
          Row(children: [
            Expanded(
                child: Text(item['billno']?.toString() ?? '',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // 行2：收货门店 + 配送中心
          Row(children: [
            Expanded(
                child: Text('收货门店：${item['instorename']?.toString() ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            Expanded(
                child: Text('配送中心：${item['outstorename']?.toString() ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          // 行3：单据金额（加粗）+ 制单人
          Row(children: [
            Expanded(
                child: Text('单据金额：${item['billamt']?.toString() ?? ''}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF333333)))),
            Text('制单人：${item['createname']?.toString() ?? ''}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ]),
          const SizedBox(height: 4),
          // 行4：制单时间
          Text('制单时间：${item['createtime']?.toString() ?? ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
        ]),
      ),
    );
  }
}

/// 调拨申请单卡片（样式对齐 allot_apply/list.dart 列表卡片：
/// 单号+状态/调入机构+调出机构/单据金额+制单人/分隔线/制单时间）
class _AllotApplyCard extends StatelessWidget {
  const _AllotApplyCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static Color _statusColor(String? signflag) {
    if (signflag == '1') return const Color(0xFF00A870);
    if (signflag == '2') return const Color(0xFFFF9900);
    if (signflag == '-1') return const Color(0xFFAAAAAA);
    return const Color(0xFFD54B5A);
  }

  static String _statusLabel(String? signflag) {
    if (signflag == '1') return '已审核';
    if (signflag == '2') return '已驳回';
    if (signflag == '-1') return '已作废';
    return '待审核';
  }

  static String _fmtAmt(dynamic value) {
    final v = double.tryParse(value?.toString() ?? '0') ?? 0.0;
    return v.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '-';
    final String instorename = item['instorename']?.toString() ?? '';
    final String outstorename = item['outstorename']?.toString() ?? '';
    final String billamt = _fmtAmt(item['billamt']);
    final String createname = item['createname']?.toString() ?? '-';
    final String createtime = item['createtime']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
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
              // 第1行：单号 + 审核状态
              Row(
                children: [
                  Expanded(
                    child: Text(billno,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                  ),
                  Text(statusLabel,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
                ],
              ),
              const SizedBox(height: 8),
              // 第2行：调入机构 + 调出机构
              Row(
                children: [
                  Expanded(
                    child: Text('调入机构：$instorename',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Text('调出机构：$outstorename',
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

/// 要货申请单卡片（参考 enquiry/list.dart _EnquiryCard：单号/要货门店/配送中心/单据金额/制单人/制单时间）
class _EnquiryApplyCard extends StatelessWidget {
  const _EnquiryApplyCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static Color _statusColor(String? signflag) {
    if (signflag == '1') return const Color(0xFF00A870);
    if (signflag == '2') return const Color(0xFFFF9900);
    if (signflag == '-1') return const Color(0xFFAAAAAA);
    return const Color(0xFFD54B5A);
  }

  static String _statusLabel(String? signflag) {
    if (signflag == '1') return '已审核';
    if (signflag == '2') return '已驳回';
    if (signflag == '-1') return '已作废';
    return '待审核';
  }

  static String _fmtAmt(dynamic value) {
    final v = double.tryParse(value?.toString() ?? '0') ?? 0.0;
    return v.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '-';
    final String instorename = item['instorename']?.toString() ?? '';
    final String outstorename = item['outstorename']?.toString() ?? '';
    final String billamt = _fmtAmt(item['billamt']);
    final String createname = item['createname']?.toString() ?? '-';
    final String createtime = item['createtime']?.toString() ?? '-';
    final String signflag = item['signflag']?.toString() ?? '';
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
              // 第1行：单号 + 审核状态
              Row(
                children: [
                  Expanded(
                    child: Text(billno,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                  ),
                  Text(statusLabel,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: statusColor)),
                ],
              ),
              const SizedBox(height: 8),
              // 第2行：要货门店 + 配送中心
              Row(
                children: [
                  Expanded(
                    child: Text('要货门店：$instorename',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: Text('配送中心：$outstorename',
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
