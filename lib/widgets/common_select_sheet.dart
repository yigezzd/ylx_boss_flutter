import 'dart:async';

import 'package:flutter/material.dart';

/// 通用底部抽屉选择组件
///
/// 以 showModalBottomSheet 弹出半屏抽屉，支持搜索、分页加载。
/// 列表项格式：Radio 单选框 + [编码]名称（参考 boss selectCom.vue）。
/// 单选点击后自动关闭并返回结果。
class CommonSelectSheet extends StatefulWidget {
  const CommonSelectSheet({
    super.key,
    required this.title,
    this.searchHint = '搜索',
    required this.fetchData,
    this.nameField = 'name',
    this.codeField = 'code',
    this.idField = 'id',
    this.showAll = false,
    this.initialSelectedId,
    this.mapResult,
  });

  /// 抽屉标题
  final String title;

  /// 搜索框提示文字
  final String searchHint;

  /// 数据请求函数，返回原始接口 result（需包含 result['list']）。
  /// 参数: (searchText, page)
  final Future<Map<String, dynamic>?> Function(String searchText, int page) fetchData;

  /// 列表中展示名称对应的字段名
  final String nameField;

  /// 列表中展示编码对应的字段名（用于格式化显示 [编码]名称）
  final String codeField;

  /// 条目唯一标识字段名
  final String idField;

  /// 是否支持"全部"选项（列表第一项），默认 false
  final bool showAll;

  /// 初始选中条目 ID，用于打开时回显
  final String? initialSelectedId;

  /// 单选模式：点击条目后的结果转换函数。
  final Map<String, dynamic> Function(Map<String, dynamic> item)? mapResult;

  /// 便捷静态方法：打开底部抽屉并返回选择结果
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String title,
    String searchHint = '搜索',
    required Future<Map<String, dynamic>?> Function(String, int) fetchData,
    String nameField = 'name',
    String codeField = 'code',
    String idField = 'id',
    bool showAll = false,
    String? initialSelectedId,
    Map<String, dynamic> Function(Map<String, dynamic>)? mapResult,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => SafeArea(
        child: CommonSelectSheet(
          title: title,
          searchHint: searchHint,
          fetchData: fetchData,
          nameField: nameField,
          codeField: codeField,
          idField: idField,
          showAll: showAll,
          initialSelectedId: initialSelectedId,
          mapResult: mapResult,
        ),
      ),
    );
  }

  @override
  State<CommonSelectSheet> createState() => _CommonSelectSheetState();
}

class _CommonSelectSheetState extends State<CommonSelectSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _list = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String _searchText = '';

  Timer? _debounceTimer;

  /// 当前选中条目的 id，用于 Radio 展示
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
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
          _hasMore = result['has_more'] as bool? ?? rows.isNotEmpty;
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

  void _onTapItem(Map<String, dynamic> item) {
    final String id = item[widget.idField]?.toString() ?? '';
    setState(() => _selectedId = id);
    // 短暂延迟展示选中效果后关闭
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final result = widget.mapResult != null ? widget.mapResult!(item) : item;
      Navigator.pop(context, result);
    });
  }

  void _onTapAll() {
    // "全部"选项：返回空 id 和空 name
    final result = <String, dynamic>{
      widget.idField: '',
      widget.nameField: '',
    };
    if (widget.mapResult != null) {
      Navigator.pop(context, widget.mapResult!(result));
    } else {
      Navigator.pop(context, result);
    }
  }

  String _formatName(Map<String, dynamic> item) {
    final String name = item[widget.nameField]?.toString() ?? '';
    final String code = item[widget.codeField]?.toString() ?? '';
    if (code.isNotEmpty) {
      return '[$code]$name';
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textColor = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF111827);
    final Color subTextColor = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF9CA3AF);
    final Color dividerColor = isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB);
    final Color inputBgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // ── 标题栏 ──
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close, size: 22, color: subTextColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),
          // ── 搜索框 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  hintStyle: TextStyle(fontSize: 14, color: subTextColor),
                  prefixIcon: Icon(Icons.search, size: 20, color: subTextColor),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixIcon: _searchText.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                          },
                          child: Icon(Icons.clear, size: 18, color: subTextColor),
                        )
                      : null,
                  filled: true,
                  fillColor: inputBgColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          // ── 列表 ──
          Expanded(
            child: _list.isEmpty && !_loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: subTextColor),
                        const SizedBox(height: 8),
                        Text('暂无数据', style: TextStyle(fontSize: 13, color: subTextColor)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    cacheExtent: 800,
                    itemCount: _list.length +
                        (widget.showAll ? 1 : 0) +
                        (_loading ? 1 : (_hasMore ? 0 : 1)),
                    itemBuilder: (context, index) {
                      // "全部"选项
                      if (widget.showAll && index == 0) {
                        return _buildSelectItem(
                          label: '全部',
                          isSelected: _selectedId == null || _selectedId!.isEmpty,
                          onTap: _onTapAll,
                          textColor: textColor,
                          dividerColor: dividerColor,
                        );
                      }
                      final dataIndex = widget.showAll ? index - 1 : index;
                      if (dataIndex == _list.length) {
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
                            : Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Text('没有更多数据',
                                      style: TextStyle(fontSize: 12, color: subTextColor)),
                                ),
                              );
                      }
                      final item = _list[dataIndex];
                      final String id = item[widget.idField]?.toString() ?? '';
                      final bool isSelected = _selectedId == id;
                      return _buildSelectItem(
                        label: _formatName(item),
                        isSelected: isSelected,
                        onTap: () => _onTapItem(item),
                        textColor: textColor,
                        dividerColor: dividerColor,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectItem({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color textColor,
    required Color dividerColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: dividerColor, width: 0.5)),
        ),
        child: Row(
          children: [
            // Radio 单选框
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 22,
              color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: isSelected ? const Color(0xFF006EFF) : textColor,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
