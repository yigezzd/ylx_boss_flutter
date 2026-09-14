import 'package:flutter/material.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 订单配送 - 列表页
/// 参考 Vue boss 项目 fulfillment/deliveryOrder.vue
/// 状态标签页：待配送 / 已配送
/// 时间筛选：昨日 / 今日 / 本周 / 本月 / 自定义
class DeliveryOrderListPage extends StatefulWidget {
  const DeliveryOrderListPage({super.key});

  @override
  State<DeliveryOrderListPage> createState() => _DeliveryOrderListPageState();
}

class _DeliveryOrderListPageState extends State<DeliveryOrderListPage> {
  int _statusTabIndex = 0; // 0=待配送 1=已配送
  int _activeQuickTimeId = 1; // 0=昨天 1=今天 2=本周 3=本月 4=自定义

  String _startDate = '';
  String _endDate = '';

  final bool _loading = false;
  final List<Map<String, dynamic>> _list = [];

  static const List<String> _statusTabs = ['待配送', '已配送'];

  /// 快速时间选项（对齐促销调价单 _QuickTimeTag）
  static const List<Map<String, dynamic>> _quickTimeList = [
    {'id': 0, 'label': '昨日'},
    {'id': 1, 'label': '今日'},
    {'id': 2, 'label': '本周'},
    {'id': 3, 'label': '本月'},
    {'id': 4, 'label': '自定义'},
  ];

  /// 占位模拟数据（调 UI 用，上线后移除）
  static final List<Map<String, dynamic>> _mockPendingList = [
    {
      'deliveryTime': '08-22 10:00至10:30',
      'billno': '#0003',
      'type': '取', // 取/送
      'storeName': '门店1',
      'address': '深圳市龙华区民治品客小镇青创城E栋6楼',
      'contact': '张三',
      'phone': '13147099267',
      'remark': '显示客户备注信息',
      'totalQty': 3,
      'badgeNum': '9',
      'goods': [
        {'productname': 'AD钙奶300ml', 'productid': 'P1001', 'price': 6.5, 'qty': 1, 'amt': 6.5},
        {'productname': '娃哈哈300ml', 'productid': 'P1002', 'price': 5.0, 'qty': 1, 'amt': 5.0},
        {'productname': '农夫山泉550ml', 'productid': 'P1003', 'price': 2.0, 'qty': 1, 'amt': 2.0},
      ],
    },
    {
      'deliveryTime': '08-22 11:00至11:30',
      'billno': '#0001',
      'type': '送',
      'storeName': '门店2',
      'address': '深圳市福田区华强北路1001号',
      'contact': '李四',
      'phone': '13800138001',
      'remark': '货到前请电话联系',
      'totalQty': 8,
      'badgeNum': '10',
      'goods': [
        {'productname': 'AD钙奶300ml', 'productid': 'P1001', 'price': 6.5, 'qty': 1, 'amt': 6.5},
        {'productname': '娃哈哈300ml', 'productid': 'P1002', 'price': 5.0, 'qty': 2, 'amt': 10.0},
        {'productname': '农夫山泉550ml', 'productid': 'P1003', 'price': 2.0, 'qty': 1, 'amt': 2.0},
        {'productname': '怡宝555ml', 'productid': 'P1004', 'price': 2.0, 'qty': 1, 'amt': 2.0},
        {'productname': '可口可乐330ml', 'productid': 'P1005', 'price': 3.5, 'qty': 1, 'amt': 3.5},
        {'productname': '雪碧330ml', 'productid': 'P1006', 'price': 3.5, 'qty': 1, 'amt': 3.5},
        {'productname': '康师傅冰红茶500ml', 'productid': 'P1007', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
        {'productname': '统一绿茶500ml', 'productid': 'P1008', 'price': 3.0, 'qty': 1, 'amt': 3.0},
      ],
    },
    {
      'deliveryTime': '08-22 14:00至14:30',
      'billno': '#0003',
      'type': '取',
      'storeName': '门店3',
      'address': '深圳市南山区科技园南区A1栋',
      'contact': '王五',
      'phone': '13900139002',
      'remark': '',
      'totalQty': 2,
      'badgeNum': '4',
      'goods': [
        {'productname': '青岛啤酒500ml', 'productid': 'P2001', 'price': 8.0, 'qty': 2, 'amt': 16.0},
      ],
    },
  ];

  static final List<Map<String, dynamic>> _mockDeliveredList = [
    {
      'deliveryTime': '08-21 15:00:21',
      'billno': '#0003',
      'type': '取',
      'storeName': '门店1',
      'address': '深圳市龙华区民治品客小镇青创城E栋6楼',
      'contact': '张三',
      'phone': '13147099267',
      'remark': '显示客户备注信息',
      'totalQty': 3,
      'badgeNum': '7',
      'goods': [
        {'productname': 'AD钙奶300ml', 'productid': 'P1001', 'price': 6.5, 'qty': 2, 'amt': 13.0},
        {'productname': '娃哈哈300ml', 'productid': 'P1002', 'price': 5.0, 'qty': 1, 'amt': 5.0},
      ],
    },
    {
      'deliveryTime': '08-21 16:30:10',
      'billno': '#0004',
      'type': '送',
      'storeName': '门店4',
      'address': '深圳市宝安区新安街道海雅缤纷城',
      'contact': '赵六',
      'phone': '13700137003',
      'remark': '已签收',
      'totalQty': 1,
      'badgeNum': '5',
      'goods': [
        {'productname': '康师傅冰红茶500ml', 'productid': 'P1007', 'price': 3.0, 'qty': 1, 'amt': 3.0},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _updateQuickTimeRange(1);
    _loadMockData();
  }

  void _loadMockData() {
    setState(() {
      _list.clear();
      _list.addAll(_statusTabIndex == 0 ? _mockPendingList : _mockDeliveredList);
    });
  }

  void _updateQuickTimeRange(int id) {
    final now = DateTime.now();
    DateTime startDt, endDt;
    switch (id) {
      case 0: // 昨日
        startDt = now.subtract(const Duration(days: 1));
        endDt = startDt;
        break;
      case 1: // 今日
        startDt = now;
        endDt = now;
        break;
      case 2: // 本周
        final weekday = now.weekday;
        startDt = now.subtract(Duration(days: weekday - 1));
        endDt = startDt.add(const Duration(days: 6));
        break;
      case 3: // 本月
        startDt = DateTime(now.year, now.month);
        endDt = DateTime(now.year, now.month + 1, 0);
        break;
      default: // 自定义
        return;
    }
    _startDate = _formatDate(startDt);
    _endDate = _formatDate(endDt);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _onStatusTabTap(int index) {
    if (index == _statusTabIndex) return;
    setState(() {
      _statusTabIndex = index;
      _list.clear();
    });
    _loadMockData();
  }

  void _onQuickTimeTap(int id) {
    setState(() {
      _activeQuickTimeId = id;
      _updateQuickTimeRange(id);
    });
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
          '订单配送',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── 状态标签页：待配送 / 已配送 ──
          _buildStatusTabBar(),
          // ── 时间筛选行 ──
          _buildTimeFilter(),
          // ── 订单列表 ──
          Expanded(child: _buildOrderList()),
        ],
      ),
    );
  }

  // ──────────── 状态标签页 ────────────
  Widget _buildStatusTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Row(
        children: [
          for (int i = 0; i < _statusTabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => _onStatusTabTap(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      _statusTabs[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _statusTabIndex == i ? FontWeight.w600 : FontWeight.normal,
                        color: _statusTabIndex == i
                            ? const Color(0xFF006EFF)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 3,
                      width: 20,
                      decoration: BoxDecoration(
                        color: _statusTabIndex == i ? const Color(0xFF006EFF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────── 时间筛选 ────────────
  Widget _buildTimeFilter() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: _quickTimeList.map((tag) {
          final id = tag['id'] as int;
          final active = _activeQuickTimeId == id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onQuickTimeTap(id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF006EFF) : Colors.white,
                  border: Border.all(
                    color: active ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag['label'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: active ? Colors.white : const Color(0xFF333333),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ──────────── 订单列表 ────────────
  Widget _buildOrderList() {
    if (_list.isEmpty && !_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 120),
            Icon(Icons.inbox_outlined, size: 64, color: Color(0xFFD1D5DB)),
            SizedBox(height: 16),
            Text(
              '暂无配送订单',
              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      itemCount: _list.length,
      itemBuilder: (context, index) => _buildOrderCard(_list[index]),
    );
  }

  // ──────────── 配送订单卡片 ────────────
  Widget _buildOrderCard(Map<String, dynamic> order) {
    // 根据状态 tab 决定标题前缀
    final isPending = _statusTabIndex == 0;
    final timePrefix = isPending ? '预达' : '送达时间';
    final type = order['type']?.toString() ?? '取';
    final badgeNum = order['badgeNum']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 头部：时间 + 单号(带角标) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.access_time, size: 13, color: Color(0xFF6B7280)),
                const SizedBox(width: 4),
                Text(
                  '$timePrefix${order['deliveryTime'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const Spacer(),
                // 黄色角标
                if (badgeNum.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 4, bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badgeNum,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ),
                Text(
                  order['billno']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // ── 门店信息 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: type == '取' ? const Color(0xFF006EFF) : const Color(0xFF7C3AED),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    type,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  order['storeName']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          // ── 地址 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    order['address']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                  ),
                ),
              ],
            ),
          ),
          // ── 联系人 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                Text(
                  '${order['contact'] ?? ''} ${order['phone'] ?? ''}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Toast.show('联系客户功能待实现'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF006EFF)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '联系客户',
                      style: TextStyle(fontSize: 12, color: Color(0xFF006EFF)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── 备注 ──
          if ((order['remark']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 14, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '备注：${order['remark']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            ),
          // ── 分隔线 ──
          const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
          // ── 底部：件数 + 操作按钮 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                // 共X件
                GestureDetector(
                  onTap: () => _showDetailSheet(order),
                  child: Text(
                    '共${order['totalQty']?.toString() ?? '0'}件 >',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF006EFF),
                    ),
                  ),
                ),
                const Spacer(),
                if (isPending) ...[
                  // 待配送 → 操作按钮
                  GestureDetector(
                    onTap: () => Toast.show('导航功能待实现'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF006EFF)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '导航到送货地',
                        style: TextStyle(fontSize: 12, color: Color(0xFF006EFF)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Toast.show('取货功能待实现'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        type == '取' ? '我已取货' : '我已送达',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 商品明细底部弹窗（单据详情） ────────────
  /// 内容超出屏幕时可滚动，底部「确定」按钮固定不遮挡列表
  void _showDetailSheet(Map<String, dynamic> order) {
    final goods = (order['goods'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          children: [
            // 标题栏（对齐促销调价筛选弹窗：标题居中 + 右侧关闭图标）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  const Expanded(
                    child: Text(
                      '单据详情',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 40,
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
            // 商品明细列表（可滚动）
            Expanded(
              child: ListView.builder(
                cacheExtent: 800,
                itemCount: goods.length + 1,
                itemBuilder: (context, index) {
                  if (index == goods.length) return _buildGoodsTotal(goods);
                  return _buildGoodsItem(goods[index]);
                },
              ),
            ),
            // 底部固定按钮
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: double.infinity,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF006EFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '确定',
                      style:
                          TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 商品行：名称+ID（左） / 单价×数量+小计（右）
  Widget _buildGoodsItem(Map<String, dynamic> item) {
    final String name = item['productname']?.toString() ?? '-';
    final String productid = item['productid']?.toString() ?? '';
    final String price = ((item['price'] ?? 0) as num).toStringAsFixed(2);
    final String qty = ((item['qty'] ?? 0) as num).toString();
    final String amt = ((item['amt'] ?? 0) as num).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF111827))),
                if (productid.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('ID: $productid',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$price × $qty', style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563))),
              const SizedBox(height: 2),
              Text('小计：$amt',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF111827))),
            ],
          ),
        ],
      ),
    );
  }

  /// 合计金额行
  Widget _buildGoodsTotal(List<Map<String, dynamic>> goods) {
    final double total = goods.fold<double>(0, (sum, g) => sum + ((g['amt'] as num?) ?? 0));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text('合计金额：', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const Spacer(),
          Text(total.toStringAsFixed(2),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        ],
      ),
    );
  }
}
