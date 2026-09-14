import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wholesale/cust_manage/edit.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/cust_category_picker.dart';

class CustManageListPage extends StatefulWidget {
  const CustManageListPage({super.key});

  @override
  State<CustManageListPage> createState() => _CustManageListPageState();
}

class _CustManageListPageState extends State<CustManageListPage>
    with LogPageMixin<CustManageListPage> {
  @override
  String get logPageName => '客户管理列表';

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _list = [];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // 筛选参数
  String _custtypeid = '';
  String _custtypename = '';
  String _stopflag = '';

  /// 300ms 防抖
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    logEnter();
    // 查看权限校验
    if (!PermissionUtils.checkPermission('012101', showTip: false)) {
      Toast.show('你无权查客客户管理，请在后台修改权限');
    } else {
      _loadData();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
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

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    logQuery(_page);

    return request(HttpApi.customerFindList, {
      'cond': _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : '',
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'pagesize': 20,
      'notwx': 1,
      'custtypename': _custtypename,
      if (_custtypeid.isNotEmpty) 'custtypeid': _custtypeid,
      'stopflag': _stopflag,
    }).then((result) {
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
      setState(() => _hasMore = false);
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _onSearch() {
    FocusScope.of(context).unfocus();
    _page = 1;
    _list = [];
    _hasMore = true;
    _loadData();
  }

  void _onSearchChanged() {
    setState(() {}); // 刷新清除按钮显示状态（对齐采购入库）
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      if (!mounted) return;
      _page = 1;
      _list = [];
      _hasMore = true;
      _loadData();
    });
  }

  /// 客户分类选择（使用 selectCustClass 页面）
  Future<void> _selectCategory() async {
    final result = await CustCategoryPicker.show(
      context,
      initialId: _custtypeid,
    );
    if (result != null && mounted) {
      setState(() {
        _custtypeid = result['custtypeid'] ?? '';
        _custtypename = result['custtypename'] ?? '';
        _page = 1;
        _list = [];
        _hasMore = true;
      });
      _loadData();
    }
  }

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
          '客户管理',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── 工具栏：搜索 + 筛选 + 新增 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: (_) => _onSearch(),
                      onChanged: (_) => _onSearchChanged(),
                      decoration: InputDecoration(
                        hintText: '输入客户编码/名称/手机号',
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
                  ),
                ),
                const SizedBox(width: 6),
                // 分类筛选
                GestureDetector(
                  onTap: _selectCategory,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _custtypename.isNotEmpty ? _custtypename : '全部分类',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 新增按钮
                GestureDetector(
                  onTap: () async {
                    if (!PermissionUtils.checkPermission('012102', showTip: false)) {
                      Toast.show('你无权新增客户管理，请在后台修改权限');
                      return;
                    }
                    logAdd();
                    await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CustManageEditPage(),
                      ),
                    );
                    if (mounted) _onRefresh();
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Icon(Icons.add, size: 24, color: Color(0xFF333333)),
                  ),
                ),
              ],
            ),
          ),
          // ── 状态筛选栏 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _buildStatusTag('全部', ''),
                const SizedBox(width: 12),
                _buildStatusTag('启用', '0'),
                const SizedBox(width: 12),
                _buildStatusTag('停用', '1'),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // ── 列表 ──
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF006EFF),
              onRefresh: _onRefresh,
              child: _list.isEmpty && !_loading
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                              SizedBox(height: 12),
                              Text(
                                '暂无数据',
                                style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      cacheExtent: 800,
                      itemCount: _list.length + (_loading ? 1 : (_hasMore ? 0 : 1)),
                      itemBuilder: (context, index) {
                        if (index == _list.length) {
                          return _loading
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF006EFF),
                                      ),
                                    ),
                                  ),
                                )
                              : const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: Text(
                                      '没有更多数据',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                    ),
                                  ),
                                );
                        }
                        return RepaintBoundary(
                          child: _CustCard(
                            item: _list[index],
                            onTap: () async {
                              if (!PermissionUtils.checkPermission('012104', showTip: false)) {
                                Toast.show('你无权编辑客户管理，请在后台修改权限');
                                return;
                              }
                              logView(_list[index]['name']?.toString());
                              await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustManageEditPage(billData: _list[index]),
                                ),
                              );
                              if (mounted) _onRefresh();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTag(String label, String value) {
    final active = _stopflag == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _stopflag = value;
          _page = 1;
          _list = [];
          _hasMore = true;
        });
        _loadData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF006EFF) : Colors.white,
          border: Border.all(
            color: active ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: active ? Colors.white : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }
}

/// 客户列表卡片
class _CustCard extends StatelessWidget {
  const _CustCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = item['name']?.toString() ?? '-';
    final String code = item['code']?.toString() ?? '';
    final String linkman = item['linkman']?.toString() ?? '';
    final String mobile = item['mobile']?.toString() ?? '';
    final String custtypename = item['custtypename']?.toString() ?? '';
    final String address = item['address']?.toString() ?? '';
    final String stopflag = item['stopflag']?.toString() ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      code.isNotEmpty ? '$name[$code]' : name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  if (stopflag == '1')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFFF4D4F)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '停用',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFFF4D4F),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '联系人：${linkman.isNotEmpty ? linkman : "-"}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '手机号码：${mobile.isNotEmpty ? mobile : "-"}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '客户分类：${custtypename.isNotEmpty ? custtypename : "-"}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '地址：${address.isNotEmpty ? address : "-"}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
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
