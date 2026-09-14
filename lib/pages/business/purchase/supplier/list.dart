import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/purchase/supplier/add.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';

/// 供应商列表页面 —— 对齐 boss 项目 supRecord/index.vue
class SupplierListPage extends StatefulWidget {
  const SupplierListPage({super.key});

  @override
  State<SupplierListPage> createState() => _SupplierListPageState();
}

class _SupplierListPageState extends State<SupplierListPage> with LogPageMixin<SupplierListPage> {
  @override
  String get logPageName => '供应商列表';

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  final int _pageSize = 20;

  List<Map<String, dynamic>> _list = [];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ── 筛选参数 ──
  String _filterSuptype = '';
  String _filterTypename = '';
  String _filterStopflag = '';
  String _filterSupselltype = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    logEnter();
    // 查看权限校验
    if (!PermissionUtils.checkPermission('011101', showTip: false)) {
      Toast.show('你无权查看供应商，请在后台修改权限');
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

    return request(HttpApi.supplierList, {
      'is_page': 1,
      'field': 'name',
      'type': 'asc',
      'cond': _searchController.text.trim(),
      'page': _page,
      'pagesize': _pageSize,
      'typename': _filterTypename,
      'suptype': _filterSuptype,
      'stopflag': _filterStopflag,
      'supselltype': _filterSupselltype,
      'notwx': 1,
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
        _hasMore = rows.isNotEmpty && rows.length >= _pageSize;
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

  void _onSearch() {
    FocusScope.of(context).unfocus();
    logSearch(_searchController.text.trim());
    _page = 1;
    _list = [];
    _hasMore = true;
    _loadData();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _page = 1;
      _list = [];
      _hasMore = true;
      _loadData();
    });
  }

  // ── 筛选底部抽屉 ──
  void _openFilterSheet() {
    String tmpSuptype = _filterSuptype;
    String tmpTypename = _filterTypename;
    String tmpStopflag = _filterStopflag;
    String tmpSupselltype = _filterSupselltype;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.45,
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
                          // ── 状态 ──
                          const Text(
                            '状态',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              const _FilterTag('全部', ''),
                              const _FilterTag('正常', '0'),
                              const _FilterTag('冻结业务', '2'),
                              const _FilterTag('冻结账款', '3'),
                              const _FilterTag('停用', '1'),
                            ].map((tag) {
                              final active = tmpStopflag == tag.value;
                              return GestureDetector(
                                onTap: () => setSheetState(() => tmpStopflag = tag.value),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active ? const Color(0xFF006EFF) : Colors.white,
                                    border: Border.all(
                                      color: active
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFF999999),
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tag.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: active ? Colors.white : const Color(0xFF333333),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),

                          // ── 经销方式 ──
                          const Text(
                            '经销方式',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              const _FilterTag('全部', ''),
                              const _FilterTag('购销', '1'),
                              const _FilterTag('联营', '2'),
                              const _FilterTag('成本代销', '3'),
                              const _FilterTag('扣率代销', '4'),
                              const _FilterTag('租赁', '5'),
                            ].map((tag) {
                              final active = tmpSupselltype == tag.value;
                              return GestureDetector(
                                onTap: () => setSheetState(() => tmpSupselltype = tag.value),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active ? const Color(0xFF006EFF) : Colors.white,
                                    border: Border.all(
                                      color: active
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFF999999),
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tag.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: active ? Colors.white : const Color(0xFF333333),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
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
                                tmpSuptype = '';
                                tmpTypename = '';
                                tmpStopflag = '';
                                tmpSupselltype = '';
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
                                _filterSuptype = tmpSuptype;
                                _filterTypename = tmpTypename;
                                _filterStopflag = tmpStopflag;
                                _filterSupselltype = tmpSupselltype;
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

  // ── 分类选择弹窗（children 树形结构，参考商品分类） ──
  void _openClassSelect() {
    List<Map<String, dynamic>> treeData = [];
    bool treeLoading = true;

    request(HttpApi.supplierTypeGetList, <String, dynamic>{
      // 对齐 Vue selectSupClass 默认查询参数
      'is_page': '0',
      'stopflag': '',
      'cond': '',
    })
        .then((result) {
          final data = result['data'];
          if (data is Map<String, dynamic>) {
            final list = data['children'] as List? ?? data['alllist'] as List? ?? [];
            treeData = list.cast<Map<String, dynamic>>();
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          if (!mounted) return;
          treeLoading = false;
          _showTreeClassPicker(treeData, treeLoading);
        });
  }

  /// 将树形数据展平为带深度的列表
  List<_TreePickerNode> _flattenPickerTree(List<Map<String, dynamic>> nodes, int depth) {
    final result = <_TreePickerNode>[];
    for (final node in nodes) {
      result.add(_TreePickerNode(node: node, depth: depth));
      final children = node['children'] as List? ?? [];
      if (children.isNotEmpty) {
        result.addAll(_flattenPickerTree(children.cast<Map<String, dynamic>>(), depth + 1));
      }
    }
    return result;
  }

  void _showTreeClassPicker(List<Map<String, dynamic>> treeData, bool treeLoading) {
    final Set<String> expandedIds = {};

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final flatNodes = _flattenPickerTree(treeData, 0);

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
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
                            '选择供应商分类',
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
                  // 全部分类
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _filterSuptype = '';
                        _filterTypename = '';
                        _page = 1;
                        _list = [];
                        _hasMore = true;
                      });
                      Navigator.pop(ctx);
                      _loadData();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: _filterSuptype.isEmpty ? const Color(0xFFF0F7FF) : Colors.white,
                        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '全部分类',
                              style: TextStyle(
                                fontSize: 14,
                                color: _filterSuptype.isEmpty
                                    ? const Color(0xFF006EFF)
                                    : const Color(0xFF333333),
                                fontWeight:
                                    _filterSuptype.isEmpty ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          _buildRadio(_filterSuptype.isEmpty),
                        ],
                      ),
                    ),
                  ),
                  // 树形分类列表
                  if (treeLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
                    )
                  else if (flatNodes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child:
                          Text('暂无分类数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        cacheExtent: 800,
                        shrinkWrap: true,
                        itemCount: flatNodes.length,
                        itemBuilder: (_, i) {
                          final data = flatNodes[i];
                          final node = data.node;
                          // 对齐 Vue selectSupClass：valueKey 为 typeid（非 id）
                          final id = node['typeid']?.toString() ?? '';
                          final name = node['name']?.toString() ?? '';
                          final code = node['code']?.toString() ?? '';
                          final children = node['children'] as List? ?? [];
                          final hasChildren = children.isNotEmpty;
                          final isExpanded = expandedIds.contains(id);
                          final selected = _filterSuptype == id;

                          return RepaintBoundary(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() {
                                  _filterSuptype = id;
                                  // 对齐 Vue onMulCates：typename 仅传分类名称
                                  _filterTypename = name;
                                  _page = 1;
                                  _list = [];
                                  _hasMore = true;
                                });
                                Navigator.pop(ctx);
                                _loadData();
                              },
                              child: Container(
                                padding: EdgeInsets.only(
                                  left: 16.0 + data.depth * 28.0,
                                  right: 16,
                                  top: 12,
                                  bottom: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                                  border:
                                      const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                                ),
                                child: Row(
                                  children: [
                                    if (hasChildren)
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setSheetState(() {
                                            if (isExpanded) {
                                              expandedIds.remove(id);
                                            } else {
                                              expandedIds.add(id);
                                            }
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(
                                            isExpanded
                                                ? Icons.keyboard_arrow_down
                                                : Icons.chevron_right,
                                            size: 18,
                                            color: const Color(0xFF6B7280),
                                          ),
                                        ),
                                      )
                                    else
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: SizedBox(width: 18),
                                      ),
                                    Expanded(
                                      child: Text(
                                        code.isNotEmpty ? '[$code]$name' : name,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: selected
                                              ? const Color(0xFF006EFF)
                                              : const Color(0xFF333333),
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : (data.depth == 0
                                                  ? FontWeight.w500
                                                  : FontWeight.normal),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    _buildRadio(selected),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  SizedBox(height: MediaQuery.of(ctx).padding.bottom),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 构建单选框（参考商品分类选择样式）
  Widget _buildRadio(bool isSelected) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
          width: 2,
        ),
        color: isSelected ? const Color(0xFF006EFF) : Colors.white,
      ),
      child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
    );
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
        title: const Text(
          '供应商',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // 搜索框
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _searchController,
                        onSubmitted: (_) => _onSearch(),
                        onChanged: (_) => _onSearchChanged(),
                        decoration: InputDecoration(
                          hintText: '输入供应商编码/名称/手机号',
                          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                          prefixIconConstraints: const BoxConstraints(minWidth: 32),
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
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 筛选按钮
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
                          svgFile: 'fliter.svg', size: 22, color: Color(0xFF666666)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 新增按钮
                  GestureDetector(
                    onTap: () async {
                      if (!PermissionUtils.checkPermission('011102', showTip: false)) {
                        Toast.show('你无权新增供应商，请在后台修改权限');
                        return;
                      }
                      logAdd();
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SupplierAddPage(),
                        ),
                      );
                      _onRefresh();
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
          ),
        ),
      ),
      body: Column(
        children: [
          // ── 筛选条件栏 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Row(
              children: [
                // 分类
                _buildFilterChip(
                  label: _filterTypename.isNotEmpty ? _filterTypename : '全部分类',
                  onTap: _openClassSelect,
                ),
                const SizedBox(width: 8),
                // 状态
                _buildFilterChip(
                  label: _getStopflagLabel(_filterStopflag),
                  onTap: () {
                    // 快速切换状态
                    _showQuickStatusPicker();
                  },
                ),
                const SizedBox(width: 8),
                // 经销方式
                _buildFilterChip(
                  label: _getSupselltypeLabel(_filterSupselltype),
                  onTap: () {
                    _showQuickSupsellPicker();
                  },
                ),
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
                          child: _SupplierCard(
                            item: _list[index],
                            onTap: () async {
                              if (!PermissionUtils.checkPermission('011104', showTip: false)) {
                                Toast.show('你无权编辑供应商，请在后台修改权限');
                                return;
                              }
                              final id = _list[index]['id']?.toString() ??
                                  _list[index]['supid']?.toString() ??
                                  '';
                              logView(_list[index]['name']?.toString());
                              await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SupplierAddPage(
                                    supplierId: id,
                                    mode: 2, // 编辑模式
                                  ),
                                ),
                              );
                              _onRefresh();
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

  Widget _buildFilterChip({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE6E6E6)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF666666)),
          ],
        ),
      ),
    );
  }

  // ── 快速状态选择 ──
  void _showQuickStatusPicker() {
    final items = [
      {'label': '全部状态', 'value': ''},
      {'label': '正常', 'value': '0'},
      {'label': '冻结业务', 'value': '2'},
      {'label': '冻结账款', 'value': '3'},
      {'label': '停用', 'value': '1'},
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('选择状态',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ...items.map((item) {
                final selected = _filterStopflag == item['value'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _filterStopflag = item['value']!;
                      _page = 1;
                      _list = [];
                      _hasMore = true;
                    });
                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['label']!,
                            style: TextStyle(
                              fontSize: 14,
                              color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)),
                      ],
                    ),
                  ),
                );
              }),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  // ── 快速经销方式选择 ──
  void _showQuickSupsellPicker() {
    final items = [
      {'label': '全部经销', 'value': ''},
      {'label': '购销', 'value': '1'},
      {'label': '联营', 'value': '2'},
      {'label': '成本代销', 'value': '3'},
      {'label': '扣率代销', 'value': '4'},
      {'label': '租赁', 'value': '5'},
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('选择经销方式',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ...items.map((item) {
                final selected = _filterSupselltype == item['value'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _filterSupselltype = item['value']!;
                      _page = 1;
                      _list = [];
                      _hasMore = true;
                    });
                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['label']!,
                            style: TextStyle(
                              fontSize: 14,
                              color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)),
                      ],
                    ),
                  ),
                );
              }),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  static String _getStopflagLabel(String value) {
    switch (value) {
      case '0':
        return '正常';
      case '1':
        return '停用';
      case '2':
        return '冻结业务';
      case '3':
        return '冻结账款';
      default:
        return '全部状态';
    }
  }

  static String _getSupselltypeLabel(String value) {
    switch (value) {
      case '1':
        return '购销';
      case '2':
        return '联营';
      case '3':
        return '成本代销';
      case '4':
        return '扣率代销';
      case '5':
        return '租赁';
      default:
        return '全部经销';
    }
  }
}

/// 筛选标签数据
class _FilterTag {
  const _FilterTag(this.label, this.value);
  final String label;
  final String value;
}

/// 供应商列表卡片
class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static String _getSellTypeText(dynamic supselltype) {
    final v = supselltype?.toString() ?? '';
    switch (v) {
      case '1':
        return '购销';
      case '2':
        return '联营';
      case '3':
        return '成本代销';
      case '4':
        return '扣率代销';
      case '5':
        return '租赁';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = item['name']?.toString() ?? '-';
    final String linkman = item['linkman']?.toString() ?? '-';
    final String mobile = item['mobile']?.toString() ?? '-';
    final String address = item['address']?.toString() ?? '-';
    final String sellTypeText = _getSellTypeText(item['supselltype']);

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
              // 名称 + 经销方式标签
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  if (sellTypeText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF006EFF)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        sellTypeText,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF006EFF),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // 联系人 + 手机号
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '联系人：$linkman',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '手机号码：$mobile',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 地址
              Text(
                '地址：$address',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 树形选择器节点数据
class _TreePickerNode {
  _TreePickerNode({required this.node, required this.depth});
  final Map<String, dynamic> node;
  final int depth;
}
