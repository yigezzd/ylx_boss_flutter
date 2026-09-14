import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/members/basic/add.dart';
import 'package:flutter_deer/pages/business/members/basic/detail.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 会员管理列表页 —— 对齐 boss 项目 subs/member/members/index.vue
///
/// 权限点（与 Vue 端一致）：
/// - 010701：查看/进入会员详情
/// - 010702：新增会员（会员开卡）
class MembersListPage extends StatefulWidget {
  const MembersListPage({super.key});

  @override
  State<MembersListPage> createState() => _MembersListPageState();
}

class _MembersListPageState extends State<MembersListPage> {
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];
  int _total = 0;
  Map<String, dynamic> _sumdata = {};

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ── 机构筛选（对齐 Vue query.issuesids / issuesidname）──
  String _storeId = '';
  String _storeName = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initStore();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// 读取当前登录机构作为默认筛选（对齐 Vue getCookie("store")）
  void _initStore() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeId = storeMap['id']?.toString() ?? '';
        _storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    // 对齐 Vue query 参数：field=vipno, type=asc, notwx=true
    return request(HttpApi.vipInfoGetVipList, {
      'field': 'vipno',
      'type': 'asc',
      'cond': _searchController.text.trim(),
      'page': _page,
      'is_page': 1,
      'pagesize': 20,
      'issuesids': _storeId.isNotEmpty ? [_storeId] : null,
      'sharevipids': <String>[],
      'cardstatus': -1,
      'notwx': true,
    }).then((result) {
      final data = result['data'];
      final Map<String, dynamic> dataMap =
          data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = dataMap['list'] as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _total = dataMap['total'] is num ? (dataMap['total'] as num).toInt() : 0;
        _sumdata = dataMap['sumdata'] is Map<String, dynamic>
            ? dataMap['sumdata'] as Map<String, dynamic>
            : <String, dynamic>{};
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

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  /// 搜索防抖（对齐 Vue debounce 350ms）
  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 1;
      _list = [];
      _hasMore = true;
      _loadData();
    });
  }

  // ── 机构选择（对齐 Vue jumpPge → selectStore）──
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _storeId,
    );
    if (result != null && mounted) {
      setState(() {
        _storeId = result['storeid']?.toString() ?? '';
        _storeName = result['storename']?.toString() ?? '';
        _page = 1;
        _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

  // ── 新增会员（权限 010702）──
  Future<void> _add() async {
    if (!PermissionUtils.checkPermission('010702')) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: '/业务/会员/会员开卡'),
        builder: (_) => const MemberAddPage(isAdd: 1),
      ),
    );
    if ((saved ?? false) && mounted) _onRefresh();
  }

  // ── 进入会员详情（权限 010701）──
  Future<void> _openDetail(Map<String, dynamic> item) async {
    if (!PermissionUtils.checkPermission('010701')) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: '/业务/会员/会员详情'),
        builder: (_) => MemberDetailPage(
          vipid: item['vipid']?.toString() ?? '',
          vipno: item['vipno']?.toString() ?? '',
        ),
      ),
    );
    if ((changed ?? false) && mounted) _onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('会员管理',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
      ),
      body: Column(
        children: [
          _buildTopBar(),
          _buildTotalCard(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  // ──────────── 顶部：机构选择 + 搜索 + 新增 ────────────
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          // 机构按钮（对齐 Vue store-btn）
          GestureDetector(
            onTap: _selectStore,
            child: Container(
              width: 115,
              height: 40,
              padding: const EdgeInsets.only(left: 10, right: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _storeName.isNotEmpty ? _storeName : '演示门店',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.black),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20, color: Colors.black54),
                ],
              ),
            ),
          ),
          // 搜索框
          Expanded(
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: Color(0xFF999999)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) {
                        setState(() {});
                        _onSearchChanged();
                      },
                      onSubmitted: (_) => _onSearchChanged(),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                        border: InputBorder.none,
                        hintText: '会员卡号/姓名/手机',
                        hintStyle: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged();
                      },
                      child: const Icon(Icons.cancel, size: 16, color: Color(0xFFCCCCCC)),
                    ),
                ],
              ),
            ),
          ),
          // 新增按钮（权限控制颜色，对齐 Vue permission('010702')）
          GestureDetector(
            onTap: _add,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                Icons.add,
                size: 24,
                color: PermissionUtils.hasPermission('010702')
                    ? Colors.black
                    : const Color(0xFF999999),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 统计卡片（对齐 Vue totalbox 渐变背景）────────────
  Widget _buildTotalCard() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE7EEF9), Colors.white],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _buildTotalItem('会员总数', '$_total'),
          _buildTotalItem('会员总余额', MathUtils.formatDecimal(3, _sumdata['nowmoney'])),
          Container(
            padding: const EdgeInsets.only(left: 15),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFFCCCCCC))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本金：${MathUtils.formatDecimal(3, _sumdata['capitalmoney'])}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
                ),
                const SizedBox(height: 4),
                Text(
                  '赠金：${MathUtils.formatDecimal(3, _sumdata['givemoney'])}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 列表 ────────────
  Widget _buildList() {
    if (!_loading && _list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Center(child: Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        cacheExtent: 800,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
        itemCount: _list.length + 1,
        itemBuilder: (context, index) {
          if (index == _list.length) {
            return _buildBottomTips();
          }
          return Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: RepaintBoundary(
              child: _VipItem(item: _list[index], onTap: () => _openDetail(_list[index])),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomTips() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: Text(
        _hasMore ? (_loading ? '加载中...' : '上拉加载更多') : '没有更多了',
        style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// 会员列表项（独立 Widget，复用机制优化低端设备滑动性能）
// ─────────────────────────────────────────────────
class _VipItem extends StatelessWidget {
  const _VipItem({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  bool get _isFemale => item['sex']?.toString() == '女';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE2E2E2))),
        ),
        child: Row(
          children: [
            // 性别头像（对齐 Vue vip-image：男蓝底/女粉底）
            Container(
              width: 65,
              height: 65,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: _isFemale ? const Color(0xFFFBEDF4) : const Color(0xFFE8EFFF),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.person,
                size: 40,
                color: _isFemale ? const Color(0xFFF9B9CE) : const Color(0xFF3269FF),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['vipno'] ?? ''}【${item['viptypename'] ?? ''}】',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text('姓名：${item['vipname'] ?? ''}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                      ),
                      Expanded(
                        child: Text('手机：${item['mobile'] ?? ''}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '余额：${MathUtils.formatDecimal(3, item['nowmoney'])}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '积分：${MathUtils.formatDecimal(4, item['nowpoint'])}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
