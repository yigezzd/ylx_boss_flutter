import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 分类选择器（底部弹出树形选择）
/// 客户分类返回 {custtypeid, custtypename}
/// 商品分类返回 {protypeid, protypename}
class CustCategoryPicker extends StatefulWidget {
  final String initialId;
  final String apiPath;
  final String title;
  final String idKey;
  final String nameKey;

  const CustCategoryPicker({
    super.key,
    this.initialId = '',
    this.apiPath = 'customertype/getTypeListandCode',
    this.title = '选择客户分类',
    this.idKey = 'custtypeid',
    this.nameKey = 'custtypename',
  });

  /// 显示选择器，返回 {idKey, nameKey} 或 null
  static Future<Map<String, String>?> show(
    BuildContext context, {
    String initialId = '',
    String apiPath = 'customertype/getTypeListandCode',
    String title = '选择客户分类',
    String idKey = 'custtypeid',
    String nameKey = 'custtypename',
  }) {
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustCategoryPicker(
        initialId: initialId,
        apiPath: apiPath,
        title: title,
        idKey: idKey,
        nameKey: nameKey,
      ),
    );
  }

  @override
  State<CustCategoryPicker> createState() => _CustCategoryPickerState();
}

class _CustCategoryPickerState extends State<CustCategoryPicker> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _selectedId;
  String _selectedName = '';
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId.isEmpty ? null : widget.initialId;
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final result = await request(widget.apiPath, {
        'notwx': 1,
        'cond': _searchCtrl.text.trim(),
      });
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['children'] : null) as List? ?? [];
      if (mounted) {
        setState(() {
          _list = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
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
                        color: Color(0xFF111827)),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close,
                          size: 22, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => _loadData(),
                decoration: InputDecoration(
                  hintText: '输入分类名称/编码',
                  hintStyle:
                      const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                  prefixIcon: const Icon(Icons.search,
                      size: 20, color: Color(0xFF9CA3AF)),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 0),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTreeItem(
                          {'typeid': '', 'name': '全部分类', 'code': ''},
                          0,
                          [],
                        ),
                        ..._list.map((item) => _buildTreeItem(item, 0)),
                      ],
                    ),
                  ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context, {
                  widget.idKey: _selectedId ?? '',
                  widget.nameKey: _selectedName,
                });
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '确定',
                  style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeItem(Map<String, dynamic> node, int depth,
      [List<Map<String, dynamic>>? forcedChildren]) {
    final id = node['typeid']?.toString() ?? '';
    final name = node['name']?.toString() ?? '';
    final code = node['code']?.toString() ?? '';
    final label = code.isNotEmpty ? '[$code]$name' : name;
    final children = forcedChildren ??
        ((node['children'] as List?)?.cast<Map<String, dynamic>>() ?? []);
    final hasChildren = children.isNotEmpty;
    final isSelected = _selectedId == id ||
        (id.isEmpty && (_selectedId == null || _selectedId!.isEmpty));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedId = id.isEmpty ? null : id;
              _selectedName = id.isEmpty ? '' : name;
            });
          },
          child: Container(
            padding: EdgeInsets.only(
              left: 16.0 + depth * 20.0,
              right: 16,
              top: 14,
              bottom: 14,
            ),
            decoration: BoxDecoration(
              border: Border(
                  bottom:
                      BorderSide(color: const Color(0xFFE5E7EB), width: 0.5)),
            ),
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    onTap: () {
                      setState(() => _expandedIds.contains(id)
                          ? _expandedIds.remove(id)
                          : _expandedIds.add(id));
                    },
                    child: Icon(
                      _expandedIds.contains(id)
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 20,
                      color: const Color(0xFF9CA3AF),
                    ),
                  )
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 4),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 22,
                  color: isSelected
                      ? const Color(0xFF006EFF)
                      : const Color(0xFFD1D5DB),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: isSelected
                          ? const Color(0xFF006EFF)
                          : const Color(0xFF111827),
                      fontWeight:
                          isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasChildren && _expandedIds.contains(id))
          ...children.map((child) => _buildTreeItem(child, depth + 1)),
      ],
    );
  }
}
