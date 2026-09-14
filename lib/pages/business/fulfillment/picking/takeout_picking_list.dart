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
      final params = <String, dynamic>{
        'is_page': 1,
        'page': _page,
        'pagesize': 20,
        // pickflag 从当前 Tab 索引取值（0=待领取 1=待拣货 2=已拣货 3=待下发）
        'pickflag': _tabs[_tabController.index]['key'],
        'type': 'desc',
        'field': 'createtime',
        if (_takeouttype.isNotEmpty) 'takeouttype': _takeouttype,
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
          statusTitle: _tabs[_tabController.index]['title'] ?? '',
          canClaim: _tabs[_tabController.index]['key'] == '0',
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
                      itemCount: _list.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _list.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        return _buildOrderCard(_list[index]);
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

  /// TabBar 下方筛选行：拣货状态 + 第三方平台来源渠道
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          _buildFilterButton(
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
          const Spacer(),
        ],
      ),
    );
  }

  /// 下拉筛选按钮（当前选中值 + 箭头，选中非「全部」时蓝色高亮）
  Widget _buildFilterButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: active ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: active ? const Color(0xFF006EFF) : const Color(0xFF333333))),
            Icon(Icons.arrow_drop_down,
                size: 16, color: active ? const Color(0xFF006EFF) : const Color(0xFF999999)),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
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
                      order['isort']?.toString() ?? '',
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
              if (_tabs[_tabController.index]['key'].toString() == '0')
                // 领取倒计时：billdate + 5 分钟，目标时间已过自动隐藏
                _ClaimCountdown(billdate: order['billdate']?.toString()),
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openDetail(order),
                child: Text(
                  '共${order['qty']?.toString() ?? ''}件商品',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF006EFF),
                  ),
                ),
              ),
              const Spacer(),
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
    );
  }
}

/// 领取任务倒计时：目标时间 = billdate + 5 分钟，每秒刷新
/// 目标时间已过则不渲染；剩余 ≤ 2 分钟橙色高亮，其余灰色
class _ClaimCountdown extends StatefulWidget {
  const _ClaimCountdown({required this.billdate});

  final String? billdate;

  @override
  State<_ClaimCountdown> createState() => _ClaimCountdownState();
}

class _ClaimCountdownState extends State<_ClaimCountdown> {
  Timer? _timer;
  DateTime? _target;

  /// 解析 billdate（兼容 "yyyy-MM-dd HH:mm:ss" 与秒/毫秒时间戳）
  static DateTime? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }
    final numValue = num.tryParse(raw);
    if (numValue != null) {
      // 10 位为秒级时间戳，13 位及以上为毫秒级
      final ms = numValue >= 1000000000000 ? numValue.toInt() : numValue.toInt() * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _target = _parseTime(widget.billdate)?.add(const Duration(minutes: 5));
    if (_target != null && _target!.isAfter(DateTime.now())) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        if (!_target!.isAfter(DateTime.now())) {
          // 已超时：停止计时并隐藏
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
    final target = _target;
    if (target == null || !target.isAfter(DateTime.now())) {
      return const SizedBox.shrink();
    }
    final diff = target.difference(DateTime.now());
    final urgent = diff.inSeconds <= 120;
    final text = '剩余 ${diff.inMinutes.toString().padLeft(2, '0')} 分'
        ' ${(diff.inSeconds % 60).toString().padLeft(2, '0')} 秒';
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: urgent ? FontWeight.w600 : FontWeight.normal,
        color: urgent ? const Color(0xFFE65100) : const Color(0xFF6B7280),
      ),
    );
  }
}
