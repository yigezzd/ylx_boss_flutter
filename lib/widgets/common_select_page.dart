import 'dart:async';

import 'package:flutter/material.dart';

/// 通用选择列表页面
///
/// 支持单选/多选、搜索防抖、滚动分页加载。
/// 调用方通过 [fetchData] 提供数据请求，通过 [nameField] 指定展示字段。
class CommonSelectPage extends StatefulWidget {
  const CommonSelectPage({
    super.key,
    required this.title,
    this.searchHint = '搜索',
    required this.fetchData,
    this.nameField = 'name',
    this.codeField = 'code',
    this.multiSelect = false,
    this.mapResult,
    this.mapMultiResult,
  });

  /// 页面标题
  final String title;

  /// 搜索框提示文字
  final String searchHint;

  /// 数据请求函数，返回原始接口 result（需包含 result['list']）。
  /// 参数: (searchText, page)
  final Future<Map<String, dynamic>?> Function(String searchText, int page) fetchData;

  /// 列表中展示名称对应的字段名，如 'name'、'storename'、'countername'
  final String nameField;

  /// 列表中展示编码对应的字段名（用于格式化显示 [编码]名称）
  final String codeField;

  /// 是否支持多选，默认 false
  final bool multiSelect;

  /// 单选模式：点击条目后的结果转换函数。
  /// 入参为原始条目 Map，返回 pop 回去的结果。
  /// 若为 null，则直接 pop 原始条目。
  final Map<String, dynamic> Function(Map<String, dynamic> item)? mapResult;

  /// 多选模式：点击确认按钮时的结果转换函数。
  /// 入参为选中条目列表，返回 pop 回去的结果。
  final Map<String, dynamic> Function(List<Map<String, dynamic>> selected)? mapMultiResult;

  @override
  State<CommonSelectPage> createState() => _CommonSelectPageState();
}

class _CommonSelectPageState extends State<CommonSelectPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _list = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String _searchText = '';

  Timer? _debounceTimer;

  /// 多选已选中的条目索引集合
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onTextChanged);
    _loadData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onTextChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final text = _searchController.text.trim();
      if (text != _searchText) {
        _searchText = text;
        _page = 1;
        _hasMore = true;
        _list = [];
        _selectedIndices.clear();
        _loadData();
      }
    });
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
      final result = await widget.fetchData(_searchText, _page);
      if (result != null) {
        final list = result['list'] as List? ?? [];
        final rows = list.cast<Map<String, dynamic>>();
        setState(() {
          if (_page == 1) {
            _list = rows;
          } else {
            _list.addAll(rows);
          }
          _hasMore = rows.isNotEmpty;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } catch (_) {
      setState(() => _hasMore = false);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onTapItem(Map<String, dynamic> item, int index) {
    if (widget.multiSelect) {
      setState(() {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      });
    } else {
      final result = widget.mapResult != null ? widget.mapResult!(item) : item;
      Navigator.pop(context, result);
    }
  }

  void _onConfirmMulti() {
    final selected = _selectedIndices.map((i) => _list[i]).toList();
    if (selected.isEmpty) return;
    final result =
        widget.mapMultiResult != null ? widget.mapMultiResult!(selected) : {'selected': selected};
    Navigator.pop(context, result);
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
        centerTitle: true,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Color(0xFF9CA3AF)),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 列表
          Expanded(
            child: _list.isEmpty && !_loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                        SizedBox(height: 12),
                        Text(
                          '暂无数据',
                          style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
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
                      final item = _list[index];
                      final String name = item[widget.nameField]?.toString() ?? '';
                      final String code = item[widget.codeField]?.toString() ?? '';
                      final String displayName = code.isNotEmpty ? '[$code]$name' : name;
                      final bool isSelected = _selectedIndices.contains(index);
                      return GestureDetector(
                        onTap: () => _onTapItem(item, index),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              if (widget.multiSelect) ...[
                                Icon(
                                  isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                  size: 22,
                                  color: isSelected
                                      ? const Color(0xFF006EFF)
                                      : const Color(0xFFD1D5DB),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF111827),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!widget.multiSelect)
                                const Icon(Icons.chevron_right, size: 20, color: Color(0xFFD1D5DB)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // 多选模式底部确认按钮
          if (widget.multiSelect)
            Container(
              color: Colors.white,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(context).padding.bottom + 10,
              ),
              child: Row(
                children: [
                  Text(
                    '已选 ${_selectedIndices.length} 项',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 120,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _selectedIndices.isEmpty ? null : _onConfirmMulti,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006EFF),
                        disabledBackgroundColor: const Color(0xFFD1D5DB),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      child: const Text('确认', style: TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
