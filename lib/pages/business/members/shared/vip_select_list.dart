import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/members/basic/add.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 会员选择/业务列表页（共享）—— 对齐 boss 项目
/// subs/member/point/index.vue、recharge/index.vue、recharge/search.vue、vippay/index.vue
///
/// 三个子模块（积分管理/会员充值/会员收款）的会员列表结构完全一致：
/// 搜索框（含扫码）+ 会员列表，点击会员进入对应业务操作页。
///
/// - [selectMode] = true 时为“选择会员”模式（对齐 recharge/search.vue）：
///   点击会员直接 pop 返回该会员数据；
/// - [showAdd] = true 时右上角显示新增按钮（对齐 recharge index.vue，权限 010702）。
class VipSelectListPage extends StatefulWidget {
  const VipSelectListPage({
    super.key,
    required this.title,
    this.selectMode = false,
    this.showAdd = false,
    this.buildEditPage,
    this.editRouteName = '',
  });

  /// 页面标题（如 积分管理/会员充值/会员收款/选择会员）
  final String title;

  /// 选择模式：点击条目 pop 返回会员数据
  final bool selectMode;

  /// 是否显示右上角新增按钮（会员开卡，权限 010702）
  final bool showAdd;

  /// 非选择模式下点击会员要打开的页面构建器
  final Widget Function(Map<String, dynamic> item)? buildEditPage;

  /// 编辑页路由名（供审计日志）
  final String editRouteName;

  @override
  State<VipSelectListPage> createState() => _VipSelectListPageState();
}

class _VipSelectListPageState extends State<VipSelectListPage> {
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ── 默认机构（对齐 Vue getCookie("store") → issuesids）──
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
      'issuesidname': _storeName,
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

  /// 扫码搜索（对齐 Vue scanFn）
  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        settings: const RouteSettings(name: '/业务/会员/扫码'),
        builder: (_) => const QrCodeScannerPage(),
      ),
    );
    if (!mounted) return;
    if (code != null && code.isNotEmpty) {
      _searchController.text = code;
      setState(() {});
      _page = 1;
      _list = [];
      _hasMore = true;
      _loadData();
    } else {
      Toast.show('请扫描正确条码');
    }
  }

  // ── 新增会员（对齐 Vue add()，权限 010702）──
  Future<void> _add() async {
    if (!PermissionUtils.checkPermission('010702')) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: '/业务/会员/会员开卡'),
        builder: (_) => const MemberAddPage(isAdd: 1),
      ),
    );
    if (mounted) _onRefresh();
  }

  // ── 点击会员（对齐 Vue edit()，权限 010701）──
  Future<void> _onTapItem(Map<String, dynamic> item) async {
    if (!PermissionUtils.checkPermission('010701')) return;
    if (widget.selectMode) {
      Navigator.pop(context, item);
      return;
    }
    if (widget.buildEditPage == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        settings: RouteSettings(name: widget.editRouteName),
        builder: (_) => widget.buildEditPage!(item),
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
        title: Text(widget.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
      ),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  // ──────────── 顶部：搜索框 + 扫码 + 新增 ────────────
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
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
                        hintText: '请输入会员卡号/名称/手机号',
                        hintStyle: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() {});
                        _onSearchChanged();
                      },
                      child: const Icon(Icons.cancel, size: 16, color: Color(0xFFCCCCCC)),
                    ),
                  // 扫码按钮（对齐 Vue tmicon-scan）
                  GestureDetector(
                    onTap: _scan,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF666666)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 新增按钮（仅充值页显示，对齐 Vue recharge index.vue + 号）
          if (widget.showAdd) ...[
            const SizedBox(width: 8),
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
      child: Container(
        color: Colors.white,
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ListView.builder(
          controller: _scrollController,
          cacheExtent: 800,
          itemCount: _list.length + 1,
          itemBuilder: (context, index) {
            if (index == _list.length) {
              return _buildBottomTips();
            }
            return RepaintBoundary(
              child: _VipSimpleItem(item: _list[index], onTap: () => _onTapItem(_list[index])),
            );
          },
        ),
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
// 会员列表项（独立 Widget，优化低端设备滑动性能）
// 对齐 Vue vip-item：卡号【分类】+ 姓名/手机 + 余额/积分 + 零钱余额
// ─────────────────────────────────────────────────
class _VipSimpleItem extends StatelessWidget {
  const _VipSimpleItem({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const infoStyle = TextStyle(fontSize: 12, color: Color(0xFF7A7A7A));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE2E2E2))),
        ),
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
                Expanded(child: Text('姓名：${item['vipname'] ?? ''}', style: infoStyle)),
                Expanded(child: Text('手机：${item['mobile'] ?? ''}', style: infoStyle)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '储卡余额：${MathUtils.formatDecimal(3, item['nowmoney'])}',
                    style: infoStyle,
                  ),
                ),
                Expanded(
                  child: Text(
                    '积分：${MathUtils.formatDecimal(4, item['nowpoint'])}',
                    style: infoStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('零钱余额：${MathUtils.formatDecimal(3, item['pocketmoney'])}', style: infoStyle),
          ],
        ),
      ),
    );
  }
}
