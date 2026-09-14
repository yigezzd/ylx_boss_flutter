import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/system/management/sys_user_edit_page.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 用户管理列表（对齐 Vue sysuser/index.vue）
class SysUserListPage extends StatefulWidget {
  const SysUserListPage({super.key});

  @override
  State<SysUserListPage> createState() => _SysUserListPageState();
}

class _SysUserListPageState extends State<SysUserListPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  final int _pageSize = 20;

  final _searchController = TextEditingController();
  List<int> _sids = [];
  String _sidsname = '';
  int _stopflag = -1; // -1=全部 0=启用 1=禁用

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (!PermissionUtils.checkPermission('014801', showTip: false)) {
      Toast.show('你无权查看用户管理，请在后台修改权限');
      return;
    }
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
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

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await request(HttpApi.sysUserList, {
        'is_page': 1,
        'page': _page,
        'pagesize': _pageSize,
        'cond': _searchController.text.trim(),
        'sids': _sids,
        'stopflag': _stopflag >= 0 ? _stopflag : '',
        'field': 'createtime',
        'type': 'asc',
      });
      final data = res['data'];
      final list = (data is Map ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= _pageSize;
      });
    } catch (_) {
      setState(() => _hasMore = false);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      // 回显当前选中的机构（空值时高亮“全部”）
      initialSelectedId: _sids.isNotEmpty && _sids.first > 0 ? _sids.first.toString() : '',
    );
    if (result != null && mounted) {
      setState(() {
        _sids = [int.tryParse(result['storeid']?.toString() ?? '') ?? 0];
        _sidsname = result['storename']?.toString() ?? '';
      });
      _page = 1;
      _list = [];
      _hasMore = true;
      _loadData();
    }
  }

  void _add() {
    if (!PermissionUtils.checkPermission('014802', showTip: false)) {
      Toast.show('你无权新增用户管理，请在后台修改权限');
      return;
    }
    Navigator.of(context).pushNamed('/system/sysUser/edit').then((v) {
      if (v == true) _onRefresh();
    });
  }

  void _edit(Map<String, dynamic> item) {
    if (!PermissionUtils.checkPermission('014803', showTip: false)) {
      Toast.show('你无权编辑用户管理，请在后台修改权限');
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<bool>(
      builder: (_) => SysUserEditPage(user: jsonEncode(item)),
    ))
        .then((v) {
      if (v ?? false) _onRefresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('用户管理', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
        actions: [
          GestureDetector(
            onTap: _add,
            child: Container(
              width: 48,
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 22, color: Color(0xFF333333)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '请输入用户名/工号',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 10, right: 6),
                  child: Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                ),
                prefixIconConstraints: const BoxConstraints(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                filled: true,
                fillColor: Colors.white,
              ),
              onSubmitted: (_) {
                _page = 1;
                _list = [];
                _hasMore = true;
                _loadData();
              },
            ),
          ),
          // 筛选
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    _sidsname.isNotEmpty ? _sidsname : '全部机构',
                    _selectStore,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDropdown(
                    _stopFlagLabel,
                    () => _showStopFlagPicker(),
                  ),
                ),
              ],
            ),
          ),
          // 列表
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: const Color(0xFF006EFF),
              child: _list.isEmpty && !_loading
                  ? ListView(children: const [
                      Padding(
                          padding: EdgeInsets.only(top: 120),
                          child: Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                            SizedBox(height: 12),
                            Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                          ])))
                    ])
                  : ListView.builder(
                      controller: _scrollController,
                      cacheExtent: 800,
                      itemCount: _list.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _list.length) {
                          return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Color(0xFF006EFF)))));
                        }
                        final item = _list[index];
                        final enabled = item['stopflag'] == 0;
                        return RepaintBoundary(
                          child: GestureDetector(
                            onTap: () => _edit(item),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.person,
                                      size: 48,
                                      color: enabled
                                          ? const Color(0xFF3764FF)
                                          : const Color(0xFFB0B0B0)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('[${item['code'] ?? ''}]${item['name'] ?? ''}',
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF333333))),
                                        const SizedBox(height: 6),
                                        Text('所属机构：${item['storename'] ?? '--'}',
                                            style: const TextStyle(
                                                fontSize: 13, color: Color(0xFF7A7A7A))),
                                        const SizedBox(height: 2),
                                        Text('角色：${item['rolename'] ?? '--'}',
                                            style: const TextStyle(
                                                fontSize: 13, color: Color(0xFF7A7A7A))),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: enabled
                                          ? const Color(0xFFE8F5E9)
                                          : const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(enabled ? '启用' : '停用',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: enabled
                                                ? const Color(0xFF4CAF50)
                                                : const Color(0xFFFF9800))),
                                  ),
                                ],
                              ),
                            ),
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

  String get _stopFlagLabel {
    return _stopflag == 0 ? '启用' : (_stopflag == 1 ? '禁用' : '全部状态');
  }

  void _showStopFlagPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      const SizedBox(width: 48),
                      const Expanded(
                        child: Text(
                          '选择状态',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
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
                ...[
                  {'label': '全部状态', 'value': -1},
                  {'label': '启用', 'value': 0},
                  {'label': '禁用', 'value': 1},
                ].map((opt) {
                  final val = opt['value']! as int;
                  final label = opt['label']! as String;
                  final selected = _stopflag == val;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _stopflag = val);
                      _onRefresh();
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(label,
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                                )),
                          ),
                          if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdown(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                  overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
          ],
        ),
      ),
    );
  }
}
