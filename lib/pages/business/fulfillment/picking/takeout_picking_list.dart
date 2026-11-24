import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/fulfillment/picking/takeout_picking_detail.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 外卖拣货 - 列表页
/// 参考 Vue boss 项目 fulfillment/takeoutPicking.vue
class TakeoutPickingListPage extends StatefulWidget {
  const TakeoutPickingListPage({super.key});

  @override
  State<TakeoutPickingListPage> createState() => _TakeoutPickingListPageState();
}

class _TakeoutPickingListPageState extends State<TakeoutPickingListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  int _page = 1;

  /// 第三方平台来源渠道筛选值（takeouttype，'' = 全部）
  String _takeouttype = '';

  /// 排序下拉当前选中值（见 _sortOptions，'0' = 预计送达时间优先）
  String _sortValue = '0';

  bool _loading = false;
  bool _hasMore = false;
  final List<Map<String, dynamic>> _list = [];
  final ScrollController _scrollController = ScrollController();

  /// 第三方平台来源渠道筛选项（takeouttype：0=商城 2=美团零售 5=京东秒送 8=翱象，''=全部）
  static const List<Map<String, String>> _takeouttypeOptions = [
    {'value': '', 'label': '全部订单'},
    {'value': '2', 'label': '美团闪购'},
    {'value': '5', 'label': '京东秒送'},
    {'value': '0', 'label': '商城订单'},
    {'value': '8', 'label': '翱象'},
  ];

  /// takeouttype → 平台名称（0=商城 1=淘宝闪购 2=美团零售 5=京东秒送 8=翱象）
  static const Map<String, String> _takeouttypeNames = {
    '0': '商城',
    '1': '淘宝闪购',
    '2': '美团闪购',
    '5': '京东秒送',
    '8': '翱象',
  };

  /// 排序下拉选项（field/type 传给 saleselect/findSaleBill 做排序）
  static const List<Map<String, String>> _sortOptions = [
    {'value': '0', 'label': '预计送达时间优先', 'field': 'appointmenttime', 'type': 'desc'},
    {'value': '1', 'label': '下单时间优先', 'field': 'createtime', 'type': 'desc'},
    {'value': '2', 'label': '订单金额由高到低', 'field': 'amt', 'type': 'desc'},
    {'value': '3', 'label': '订单编号正序', 'field': 'billno', 'type': 'asc'},
    {'value': '4', 'label': '订单编号倒序', 'field': 'billno', 'type': 'desc'},
    {'value': '5', 'label': '商品数量多少排序', 'field': 'qty', 'type': 'desc'},
  ];

  static const List<Map<String, String>> _tabs = [
    {'key': '0', 'title': '待领取'},
    {'key': '1', 'title': '待拣货'},
    {'key': '2', 'title': '已拣货'},
    {'key': '3', 'title': '待下发'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _refreshData();
      }
    });
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _refreshData() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      // 全部订单/排序两个查询条件仅待领取 tab 生效，其余 tab 使用默认排序且不带来源筛选
      final isClaimTab = _tabs[_tabController.index]['key'].toString() == '0';
      // 排序字段/方向取自排序下拉选中项（订单编号正序/倒序为两个独立选项）
      final sortOpt = _sortOptions.firstWhere((e) => e['value'] == (isClaimTab ? _sortValue : '0'));
      final params = <String, dynamic>{
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        // pickflag 从当前 Tab 索引取值（0=待领取 1=待拣货 2=已拣货 3=待下发）
        'pickflag': _tabs[_tabController.index]['key'],
        'type': sortOpt['type'],
        'field': sortOpt['field'],
        'storagezoneflag': 1,
        if (isClaimTab && _takeouttype.isNotEmpty) 'takeouttype': _takeouttype,
      };
      final result = await request(HttpApi.saleSelectFindSaleBill, params);
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        if (_page == 1) {
          _list
            ..clear()
            ..addAll(rows);
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= 20;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _hasMore = false;
          _loading = false;
        });
    }
  }

  Future<void> _loadMore() async {
    _page++;
    await _loadData();
  }

  /// 卡片订单类型文案：优先按 takeouttype 映射，未知值回退 platform 字段
  String _platformLabel(Map<String, dynamic> order) {
    final String key = order['takeouttype']?.toString() ?? '';
    // 优先按 takeouttype 映射平台名称，未命中时回退 platform 字段，最终兜底空串
    return _takeouttypeNames[key] ?? '商城';
  }

  /// isort 补零拼接：1 → #0001、10 → #0010；空值不展示，非数字原样展示
  static String _formatIsort(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return '';
    final n = int.tryParse(s);
    if (n == null) return s;
    return '#${n.toString().padLeft(4, '0')}';
  }

  /// 倒计时基准时间：优先 billdate（交易时间），回退 createtime（下单时间）等别名
  static String _orderTime(Map<String, dynamic> order) {
    for (final key in ['billdate', 'createtime', 'ordertime']) {
      final value = order[key]?.toString() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  /// 领取任务（operate=1）
  Future<void> _claimTask(Map<String, dynamic> order) async {
    try {
      // 读取当前登录用户作为领取人（对齐项目通用写法：非空再解析，避免 jsonDecode('') 抛异常）
      String pickuserid = '';
      String pickname = '';
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        pickuserid = userMap['userid']?.toString() ?? '';
        pickname = userMap['name']?.toString() ?? '';
      }
      await request(HttpApi.saleSelectBillOperate, {
        'saleid': order['saleid'],
        'billno': order['billno'],
        'operate': 1,
        'pickuserid': pickuserid,
        'pickname': pickname,
      });
      if (!mounted) return;
      Toast.show('领取成功');
      _refreshData();
    } catch (_) {
      // 失败提示由拦截器统一弹出
    }
  }

  /// 跳转订单详情页；详情页内领取成功后返回刷新当前列表
  Future<void> _openDetail(Map<String, dynamic> order) async {
    final claimed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => TakeoutPickingDetailPage(
          order: order,
        ),
      ),
    );
    if ((claimed ?? false) && mounted) {
      _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          '外卖拣货',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF006EFF),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFF006EFF),
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: _tabs.map((t) => Tab(text: t['title'])).toList(),
        ),
      ),
      body: Column(
        children: [
          // 筛选栏（拣货状态 / 第三方平台来源渠道）
          _buildFilterBar(),
          Expanded(
            child: _list.isEmpty && !_loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 80),
                        Icon(Icons.inbox_outlined, size: 64, color: Color(0xFFD1D5DB)),
                        SizedBox(height: 16),
                        Text(
                          '暂无拣货任务',
                          style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refreshData,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      // PDA 低端设备优化：提前渲染屏幕外卡片，减少快速滑动掉帧
                      cacheExtent: 800,
                      itemCount: _list.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _list.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        // PDA 低端设备优化：隔离卡片重绘（卡片内含每秒刷新的领取倒计时）
                        return RepaintBoundary(child: _buildOrderCard(_list[index]));
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ──────────── 筛选栏（TabBar 下方） ────────────

  /// 选项 value → label
  String _optionLabel(List<Map<String, String>> options, String value) {
    for (final opt in options) {
      if (opt['value'] == value) {
        return opt['label'] ?? '';
      }
    }
    return options.first['label'] ?? '';
  }

  /// TabBar 下方筛选行：订单来源 + 排序方式（仅待领取 tab 展示）
  Widget _buildFilterBar() {
    if (_tabs[_tabController.index]['key'].toString() != '0') {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
      ),
      child: Row(
        children: [
          // 宽度自适应（参考商品档案筛选栏）：两个按钮各占一半
          Expanded(
            child: _buildFilterButton(
              label: _optionLabel(_takeouttypeOptions, _takeouttype),
              active: _takeouttype.isNotEmpty,
              onTap: () => _showFilterSheet(
                title: '订单来源',
                currentValue: _takeouttype,
                options: _takeouttypeOptions,
                onChanged: (value) {
                  setState(() => _takeouttype = value);
                  _refreshData();
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildFilterButton(
              label: _optionLabel(_sortOptions, _sortValue),
              active: _sortValue != '0',
              onTap: () => _showFilterSheet(
                title: '排序方式',
                currentValue: _sortValue,
                options: _sortOptions,
                onChanged: (value) {
                  setState(() => _sortValue = value);
                  _refreshData();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 下拉筛选按钮（对齐商品档案筛选栏：Expanded 自适应宽度，文字超长省略，选中时蓝色高亮）
  Widget _buildFilterButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: active ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: active ? const Color(0xFF006EFF) : const Color(0xFF333333)),
                  overflow: TextOverflow.ellipsis),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF999999)),
            ),
          ],
        ),
      ),
    );
  }

  /// 选项底部弹窗（对齐 add.dart _showDropdownDialog：标题 + 选项列表，点选即生效）
  /// 差异：选中项左侧蓝色圆点标记（对齐原型）
  void _showFilterSheet({
    required String title,
    required String currentValue,
    required List<Map<String, String>> options,
    required ValueChanged<String> onChanged,
  }) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            // 选项区可滚动，避免小屏设备选项过多时底部溢出
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...options.map((opt) {
                      final isSelected = opt['value'] == currentValue;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          onChanged(opt['value'] ?? '');
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                          child: Row(
                            children: [
                              // 选中项左侧蓝色圆点标记
                              SizedBox(
                                width: 14,
                                child: isSelected
                                    ? Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                            color: Color(0xFF006EFF), shape: BoxShape.circle),
                                      )
                                    : null,
                              ),
                              Text(opt['label'] ?? '',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isSelected
                                        ? const Color(0xFF006EFF)
                                        : const Color(0xFF374151),
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  )),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    // 整卡可点：点击卡片任意处进入详情；「领取任务」按钮内层手势优先，仅执行领取不跳转
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openDetail(order),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 平台图标
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _platformLabel(order),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF006EFF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _platformLabel(order),
                            style: const TextStyle(
                              fontSize: 18,
                              color: Color(0xFF374151),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatIsort(order['isort']),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF006EFF),
                          ),
                        ),
                        // 预订单标记（红字红边框）：仅在“待下发”tab 展示
                        if (_tabs[_tabController.index]['key'].toString() == '3') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFEF4444)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              '预订单',
                              style: TextStyle(fontSize: 10, color: Color(0xFFEF4444)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    _tabs[_tabController.index]['title'] ?? '',
                    style: const TextStyle(fontSize: 18, color: Color(0xFF374151)),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 4),
                  Text(
                    '预计: ${order['appointmenttime']?.toString() ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                  ),
                  const Spacer(),
                  // 领取倒计时：四个状态均展示；下单时间（billdate）+ N 分钟，归零展示 00分00秒 不隐藏
                  // 待下发（pickflag == 3）倒计时为 30 分钟，其余状态为 5 分钟
                  _ClaimCountdown(
                    billdate: _orderTime(order),
                    minutes: order['pickflag']?.toString() == '3' ? 30 : 5,
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Text(
                    '订单编号: ${order['billno']?.toString() ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Text(
                    '库区: ${order['storagezonename']?.toString() ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                  ),
                ],
              ),
              ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '备注: ${order['memo']?.toString() ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '共${order['qty']?.toString() ?? ''}件商品',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF006EFF),
                    ),
                  ),
                  const Spacer(),
                  // 「领取任务」按钮：内层手势优先响应，仅执行领取不跳详情
                  if (_tabs[_tabController.index]['key'].toString() == '0')
                    GestureDetector(
                      onTap: () => _claimTask(order),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF006EFF)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '领取任务',
                          style: TextStyle(fontSize: 12, color: Color(0xFF006EFF)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 领取任务倒计时：目标时间 = billdate + minutes 分钟（待下发 30 分钟，其余 5 分钟），每秒刷新
/// 剩余为 0 时展示「剩余: 00分00秒」不隐藏；颜色与预计时间文字一致
class _ClaimCountdown extends StatefulWidget {
  const _ClaimCountdown({required this.billdate, this.minutes = 5});

  final String? billdate;

  /// 倒计时时长（分钟）：待下发 30，其余状态 5
  final int minutes;

  @override
  State<_ClaimCountdown> createState() => _ClaimCountdownState();
}

class _ClaimCountdownState extends State<_ClaimCountdown> {
  Timer? _timer;
  DateTime? _target;

  /// 解析下单时间：兼容 "yyyy-MM-dd HH:mm:ss"、斜杠/紧凑格式与秒/毫秒时间戳
  static DateTime? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final trimmed = raw.trim();
    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return parsed;
    }
    // 斜杠分隔："yyyy/MM/dd HH:mm:ss"
    final slashParsed = DateTime.tryParse(trimmed.replaceAll('/', '-'));
    if (slashParsed != null) {
      return slashParsed;
    }
    // 纯数字紧凑格式：14 位 yyyyMMddHHmmss / 8 位 yyyyMMdd
    if (RegExp(r'^\d{14}$').hasMatch(trimmed)) {
      return DateTime.tryParse('${trimmed.substring(0, 4)}-${trimmed.substring(4, 6)}-'
          '${trimmed.substring(6, 8)} ${trimmed.substring(8, 10)}:'
          '${trimmed.substring(10, 12)}:${trimmed.substring(12, 14)}');
    }
    if (RegExp(r'^\d{8}$').hasMatch(trimmed)) {
      return DateTime.tryParse('${trimmed.substring(0, 4)}-${trimmed.substring(4, 6)}-'
          '${trimmed.substring(6, 8)}');
    }
    // 时间戳：10 位秒级 / 13 位毫秒级（兼容 "/Date(…)/" 等包裹格式）
    final numValue = num.tryParse(trimmed) ??
        num.tryParse(RegExp(r'\d{10,13}').firstMatch(trimmed)?.group(0) ?? '');
    if (numValue != null) {
      final ms = numValue >= 1000000000000 ? numValue.toInt() : numValue.toInt() * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _syncCountdown();
  }

  @override
  void didUpdateWidget(covariant _ClaimCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表项复用/数据刷新时 billdate 或倒计时时长会变化，需重算目标时间并重启计时
    if (oldWidget.billdate != widget.billdate || oldWidget.minutes != widget.minutes) {
      _syncCountdown();
    }
  }

  /// 重算目标时间（billdate + minutes 分钟）并按需启动每秒刷新计时
  void _syncCountdown() {
    _timer?.cancel();
    _timer = null;
    _target = _parseTime(widget.billdate)?.add(Duration(minutes: widget.minutes));
    if (_target != null && _target!.isAfter(DateTime.now())) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        if (!_target!.isAfter(DateTime.now())) {
          // 已超时：停止计时，保留展示「剩余: 00分00秒」
          _timer?.cancel();
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // billdate 无法解析时不渲染；剩余为 0 不隐藏，展示「剩余: 00:00」
    final target = _target;
    if (target == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final diff = target.isAfter(now) ? target.difference(now) : Duration.zero;
    final text = '剩余: ${diff.inMinutes.toString().padLeft(2, '0')}分'
        '${(diff.inSeconds % 60).toString().padLeft(2, '0')}秒';
    return Text(
      text,
      // 颜色与「预计」时间文字保持一致
      style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
    );
  }
}
