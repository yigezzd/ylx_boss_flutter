import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 商品分类管理页面（树形结构）
/// - isSelect = true  ：选择模式（从新增商品/商品列表进入），底部显示确认/取消按钮
/// - isSelect = false ：管理模式（从业务 Tab 商品分类进入），节点显示编辑/新增图标，无底部按钮
class CategoryListPage extends StatefulWidget {
  const CategoryListPage({
    super.key,
    this.isSelect = false,
    this.isMultiSelect = false,
    this.initialSelectedIds,
    this.showAll = false,
  });
  final bool isSelect;
  final bool isMultiSelect;
  final List<String>? initialSelectedIds;

  /// 是否在列表顶部显示“全部分类”选项（仅多选模式有效）
  final bool showAll;

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _dividerColor = Color(0xFFE5E7EB);

  final TextEditingController _searchController = TextEditingController();

  bool _loading = false;
  List<Map<String, dynamic>> _tree = [];
  final Set<String> _expandedIds = {};
  Map<String, dynamic>? _selectedNode;
  final Set<String> _selectedIds = {};
  final List<Map<String, dynamic>> _selectedNodes = [];
  final Set<String> _indeterminateIds = {};
  String _searchText = '';
  bool _allSelected = false;

  /// 节点 ID -> 节点数据
  final Map<String, Map<String, dynamic>> _nodeMap = {};

  /// 节点 ID -> 父节点 ID
  final Map<String, String?> _parentMap = {};

  /// 预展平的节点缓存，每次 build 时按需重建
  List<_FlatNodeData> _flatNodes = [];

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.initialSelectedIds ?? []);
    if (widget.showAll && _selectedIds.isEmpty) _allSelected = true;
    // 查看权限校验
    if (!PermissionUtils.checkPermission('010101', showTip: false)) {
      Toast.show('你无权查看商品分类，请在后台修改权限');
    } else {
      _loadCategories();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── 加载分类数据 ─────────────────────────────────────────
  Future<void> _loadCategories() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    return request(HttpApi.typeGetListandCode, {
      'field': 'typeid',
      'is_page': 0,
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['children'] : null) as List? ?? [];
      final categories = list.cast<Map<String, dynamic>>();
      setState(() {
        _tree = categories;
        _nodeMap.clear();
        _parentMap.clear();
        _buildNodeMaps(categories);
        if (widget.isMultiSelect) {
          // 初始回填：父级选中时自动级联选中其下所有子级
          _applyParentSelectionToChildren(categories);
          _refreshSelectedNodes();
          _recomputeIndeterminate();
        }
      });
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  // ─── 构建节点与父级映射（用于父子级联勾选） ────────────────
  void _buildNodeMaps(List<Map<String, dynamic>> nodes, [String? parentId]) {
    for (final node in nodes) {
      final id = node['typeid']?.toString() ?? '';
      if (id.isEmpty) continue;
      _nodeMap[id] = node;
      _parentMap[id] = parentId;
      final children = node['children'] as List? ?? [];
      _buildNodeMaps(children.cast<Map<String, dynamic>>(), id);
    }
  }

  // ─── 获取节点及其所有子孙节点的 ID ──────────────────────────
  List<String> _getDescendantIds(Map<String, dynamic> node) {
    final result = <String>[];
    final id = node['typeid']?.toString() ?? '';
    if (id.isNotEmpty) result.add(id);
    final children = node['children'] as List? ?? [];
    for (final child in children.cast<Map<String, dynamic>>()) {
      result.addAll(_getDescendantIds(child));
    }
    return result;
  }

  // ─── 判断节点是否存在被选中的子孙 ──────────────────────────
  bool _hasSelectedDescendant(Map<String, dynamic> node) {
    final children = node['children'] as List? ?? [];
    for (final child in children.cast<Map<String, dynamic>>()) {
      final id = child['typeid']?.toString() ?? '';
      if (_selectedIds.contains(id)) return true;
      if (_hasSelectedDescendant(child)) return true;
    }
    return false;
  }

  // ─── 根据 _selectedIds 刷新 _selectedNodes ─────────────────
  void _refreshSelectedNodes() {
    _selectedNodes.clear();
    for (final id in _selectedIds) {
      final node = _nodeMap[id];
      if (node != null) _selectedNodes.add(node);
    }
  }

  // ─── 重新计算半选节点集合 ──────────────────────────────────
  void _recomputeIndeterminate() {
    _indeterminateIds.clear();
    for (final entry in _nodeMap.entries) {
      final id = entry.key;
      final node = entry.value;
      if (_selectedIds.contains(id)) continue;
      if (_hasSelectedDescendant(node)) {
        _indeterminateIds.add(id);
      }
    }
  }

  // ─── 向上同步祖先节点的选中/半选状态 ────────────────────────
  void _syncUp(String? nodeId) {
    if (nodeId == null || nodeId.isEmpty) return;
    final parentId = _parentMap[nodeId];
    if (parentId == null || parentId.isEmpty) return;
    final parentNode = _nodeMap[parentId];
    if (parentNode == null) return;
    final descendantIds = _getDescendantIds(parentNode);
    final allSelected = descendantIds.isNotEmpty && descendantIds.every(_selectedIds.contains);
    if (allSelected) {
      _selectedIds.add(parentId);
    } else {
      _selectedIds.remove(parentId);
    }
    _syncUp(parentId);
  }

  // ─── 初始回填：父级选中时级联选中所有子孙 ──────────────────
  void _applyParentSelectionToChildren(List<Map<String, dynamic>> nodes) {
    for (final node in nodes) {
      final id = node['typeid']?.toString() ?? '';
      if (_selectedIds.contains(id)) {
        _selectedIds.addAll(_getDescendantIds(node));
      }
      final children = node['children'] as List? ?? [];
      _applyParentSelectionToChildren(children.cast<Map<String, dynamic>>());
    }
  }

  // ─── 搜索过滤 ─────────────────────────────────────────────
  List<Map<String, dynamic>> _filterTree(List<Map<String, dynamic>> nodes, String keyword) {
    if (keyword.isEmpty) return nodes;
    final kw = keyword.toLowerCase();
    final result = <Map<String, dynamic>>[];
    for (final node in nodes) {
      final name = (node['name']?.toString() ?? node['typename']?.toString() ?? '').toLowerCase();
      final code = (node['typecode']?.toString() ?? node['code']?.toString() ?? '').toLowerCase();
      final children = node['children'] as List? ?? [];
      final filteredChildren = _filterTree(children.cast<Map<String, dynamic>>(), keyword);
      if (name.contains(kw) || code.contains(kw) || filteredChildren.isNotEmpty) {
        result.add({
          ...node,
          if (filteredChildren.isNotEmpty) 'children': filteredChildren,
        });
      }
    }
    return result;
  }

  // ─── 确认选择（选择模式） ──────────────────────────────────
  void _confirm() {
    if (widget.isMultiSelect) {
      if (widget.showAll && _allSelected) {
        Navigator.pop(context, <Map<String, dynamic>>[]);
        return;
      }
      if (_selectedNodes.isEmpty) return;
      // 多选返回时，将 name 字段拼接为 [编码]名称 格式
      final results = _selectedNodes.map((node) {
        final name = node['name']?.toString() ?? node['typename']?.toString() ?? '';
        final code = node['typecode']?.toString() ?? node['code']?.toString() ?? '';
        return {
          ...node,
          'name': code.isNotEmpty ? '[$code]$name' : name,
          'typename': code.isNotEmpty ? '[$code]$name' : name,
        };
      }).toList();
      Navigator.pop(context, results);
      return;
    }
    if (_selectedNode == null) return;
    final name = _selectedNode!['name']?.toString() ?? _selectedNode!['typename']?.toString() ?? '';
    final code = _selectedNode!['typecode']?.toString() ?? _selectedNode!['code']?.toString() ?? '';
    final displayName = code.isNotEmpty ? '[$code]$name' : name;
    Navigator.pop(context, {
      'typeid': _selectedNode!['typeid']?.toString() ?? '',
      'typename': displayName,
      'typecode': code,
      'code': code,
    });
  }

  // ─── 获取自动编码 ─────────────────────────────────────────
  /// 与 Boss 项目保持一致：getCode 接口的 params 为父级编码的原始字符串
  /// Boss: http("/bi/type/getCode", code) → params = code（字符串）
  Future<String> _fetchCode([String parentCode = '0']) {
    return request(
      HttpApi.typeGetCode,
      parentCode,
      false,
      false,
    ).then((result) {
      return result['data']?.toString() ?? '';
    });
  }

  // ─── 打开新增/编辑弹窗 ────────────────────────────────────
  void _openEditSheet({
    Map<String, dynamic>? editNode,
    Map<String, dynamic>? parentNode,
  }) {
    final isEdit = editNode != null;
    final formNameCtrl = TextEditingController(
        text:
            isEdit ? (editNode['name']?.toString() ?? editNode['typename']?.toString() ?? '') : '');
    final formCodeCtrl = TextEditingController(
        text:
            isEdit ? (editNode['typecode']?.toString() ?? editNode['code']?.toString() ?? '') : '');
    bool stopflag = isEdit && (editNode['stopflag']?.toString() == '1');
    // 编辑时：通过 _parentMap 查找直接上级（对齐小程序 checkData.parents[0].name）
    // 新增子级时：传入的 parentNode 即为直接上级
    String parentName;
    if (isEdit) {
      final parentId = _parentMap[editNode['typeid']?.toString() ?? ''];
      final parentNodeFromMap = parentId != null ? _nodeMap[parentId] : null;
      if (parentNodeFromMap != null) {
        parentName = parentNodeFromMap['name']?.toString() ??
            parentNodeFromMap['typename']?.toString() ??
            '无';
      } else {
        final parenttypeid = editNode['parenttypeid']?.toString() ?? '';
        if (parenttypeid.isNotEmpty && parenttypeid != '0' && _nodeMap.containsKey(parenttypeid)) {
          parentName = _nodeMap[parenttypeid]?['name']?.toString() ??
              _nodeMap[parenttypeid]?['typename']?.toString() ??
              '无';
        } else {
          parentName = '无';
        }
      }
    } else {
      parentName = parentNode != null
          ? (parentNode['name']?.toString() ?? parentNode['typename']?.toString() ?? '')
          : '无';
    }
    final parenttypeid = parentNode?['typeid']?.toString() ?? '0';

    // 新增时自动获取编码
    if (!isEdit) {
      final baseCode = parentNode != null
          ? (parentNode['typecode']?.toString() ?? parentNode['code']?.toString() ?? '0')
          : '0';
      _fetchCode(baseCode).then((code) {
        if (code.isNotEmpty && formCodeCtrl.text.isEmpty) {
          formCodeCtrl.text = code;
        }
      });
    }

    final formNameFocusNode = FocusNode();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            final safeBottom = MediaQuery.of(ctx).padding.bottom;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 标题栏（居中标题 + 右侧关闭） ──
                SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      const SizedBox(width: 48),
                      Expanded(
                        child: Text(
                          isEdit ? '编辑商品分类' : '新增商品分类',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF9CA3AF)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _dividerColor),
                // ── 表单区（对齐小程序 center-content-box：padding 20rpx 5rpx） ──
                Container(
                  color: const Color(0xFFF6F7FB),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFormItem('上级分类', readOnlyValue: parentName, boldValue: true),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1, color: Color(0xFFE6E6E6)),
                      // 分类编码（编辑时直接显示文本，新增时显示输入框）
                      if (isEdit)
                        _buildFormItem('分类编码', readOnlyValue: formCodeCtrl.text, required: true)
                      else
                        _buildFormItem('分类编码',
                            controller: formCodeCtrl, hint: '请输入编码', required: true),
                      const Divider(height: 1, color: Color(0xFFE6E6E6)),
                      // 分类名称
                      _buildFormItem('分类名称',
                          controller: formNameCtrl,
                          hint: '请输入名称',
                          focusNode: formNameFocusNode,
                          required: true),
                      const Divider(height: 1, color: Color(0xFFE6E6E6)),
                      // 状态
                      _buildFormItem(
                        '状态',
                        trailing: Transform.translate(
                          offset: const Offset(-8, 0),
                          child: Switch(
                            value: !stopflag,
                            activeColor: _primaryColor,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (v) => setModalState(() => stopflag = !v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 键盘推起时的间距
                if (bottomInset > 0) SizedBox(height: bottomInset),
                // ── 按钮区（对齐小程序 btn-box：固定底部，高度 145rpx ≈ 72px） ──
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, safeBottom + 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE6E6E6))),
                  ),
                  child: Row(
                    children: [
                      if (isEdit)
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              Navigator.pop(ctx);
                              await _confirmDelete(editNode);
                            },
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: _primaryColor),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('删除',
                                  style: TextStyle(fontSize: 15, color: _primaryColor)),
                            ),
                          ),
                        ),
                      if (!isEdit)
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final name = formNameCtrl.text.trim();
                              final code = formCodeCtrl.text.trim();
                              if (name.isEmpty) {
                                Toast.show('请输入分类名称');
                                return;
                              }
                              if (code.isEmpty) {
                                Toast.show('请输入分类编码');
                                return;
                              }
                              final ok = await _saveCategory(
                                isEdit: false,
                                name: name,
                                code: code,
                                stopflag: stopflag ? 1 : 0,
                                parenttypeid: parenttypeid,
                              );
                              if (ok) {
                                formNameCtrl.clear();
                                formCodeCtrl.clear();
                                final baseCode = parentNode != null
                                    ? (parentNode['typecode']?.toString() ??
                                        parentNode['code']?.toString() ??
                                        '0')
                                    : '0';
                                _fetchCode(baseCode).then((c) {
                                  if (c.isNotEmpty) formCodeCtrl.text = c;
                                });
                              }
                            },
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: _primaryColor),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('保存并继续',
                                  style: TextStyle(fontSize: 15, color: _primaryColor)),
                            ),
                          ),
                        ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            // 编辑模式需校验编辑权限
                            if (isEdit &&
                                !PermissionUtils.checkPermission('010103', showTip: false)) {
                              Toast.show('你无权编辑商品分类，请在后台修改权限');
                              return;
                            }
                            final name = formNameCtrl.text.trim();
                            final code = formCodeCtrl.text.trim();
                            if (name.isEmpty) {
                              Toast.show('请输入分类名称');
                              return;
                            }
                            if (code.isEmpty) {
                              Toast.show('请输入分类编码');
                              return;
                            }
                            final ok = await _saveCategory(
                              isEdit: isEdit,
                              name: name,
                              code: code,
                              stopflag: stopflag ? 1 : 0,
                              parenttypeid: isEdit
                                  ? (editNode['parenttypeid']?.toString() ?? '0')
                                  : parenttypeid,
                              editNode: isEdit ? editNode : null,
                            );
                            if (ok) Navigator.pop(ctx);
                          },
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('确定',
                                style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    // 弹窗动画完成后聚焦分类名称输入框，拉起键盘（对齐小程序 setTimeout 300ms）
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) formNameFocusNode.requestFocus();
    });
  }

  // ─── 表单项行（对齐小程序 tm-form-item：labelWidth=230rpx≈115px） ──
  Widget _buildFormItem(String label,
      {TextEditingController? controller,
      String? readOnlyValue,
      bool enabled = true,
      bool readOnly = false,
      bool boldValue = false,
      String hint = '',
      Widget? trailing,
      FocusNode? focusNode,
      bool required = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Text(label, style: const TextStyle(fontSize: 15, color: _textPrimary)),
                if (required)
                  const Positioned(
                    left: -10,
                    top: 0,
                    child: Text('*', style: TextStyle(fontSize: 15, color: Colors.red)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: trailing != null
                ? Align(alignment: Alignment.centerLeft, child: trailing)
                : readOnlyValue != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(readOnlyValue,
                            style: TextStyle(
                                fontSize: 15,
                                color: _textPrimary,
                                fontWeight: boldValue ? FontWeight.w600 : FontWeight.normal)))
                    : TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: enabled,
                        readOnly: readOnly,
                        textAlign: TextAlign.left,
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: const TextStyle(fontSize: 15, color: Color(0xFF9CA3AF)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── 保存分类 ─────────────────────────────────────────────
  Future<bool> _saveCategory({
    required bool isEdit,
    required String name,
    required String code,
    required int stopflag,
    required String parenttypeid,
    Map<String, dynamic>? editNode,
  }) {
    final url = isEdit ? HttpApi.typeUpdateTypeInfo : HttpApi.typeAddTypeInfo;
    final Map<String, dynamic> data;
    if (isEdit && editNode != null) {
      // 与 pop.vue save() 保持一致：编辑提交节点完整数据（cloneDeep），仅剔除 alllist/children
      data = Map<String, dynamic>.from(editNode)
        ..remove('alllist')
        ..remove('children');
      data['name'] = name;
      data['code'] = code;
      data['stopflag'] = stopflag;
      data['id'] ??= editNode['typeid'];
    } else {
      data = <String, dynamic>{
        'parenttypeid': parenttypeid.isEmpty ? '0' : parenttypeid,
        'name': name,
        'code': code,
        'stopflag': stopflag,
      };
    }
    return request(url, data).then((result) {
      Toast.show('保存成功');
      _loadCategories();
      return true;
    });
  }

  // ─── 删除分类 ─────────────────────────────────────────────
  /// Boss: http("/bi/type/delTypeInfo", form.value.id)
  /// params 为原始 ID 字符串，不包装为对象
  Future<void> _confirmDelete(Map<String, dynamic> node) async {
    if (!PermissionUtils.checkPermission('010104', showTip: false)) {
      Toast.show('你无权删除商品分类，请在后台修改权限');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: const Text('确定删除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed ?? false) {
      final id = node['id']?.toString() ?? node['typeid']?.toString() ?? '';
      request(
        HttpApi.typeDelTypeInfo,
        id,
      ).then((result) {
        Toast.show('删除成功');
        _loadCategories();
      });
    }
  }

  // ─── 顶级新增按钮 ──────────────────────
  void _handleAddRoot() {
    if (!PermissionUtils.checkPermission('010102', showTip: false)) {
      Toast.show('你无权新增商品分类，请在后台修改权限');
      return;
    }
    _openEditSheet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '商品分类',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _textPrimary),
        ),
        centerTitle: true,
        actions: const [],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          const Divider(height: 1, color: _dividerColor),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _primaryColor))
                : _tree.isEmpty
                    ? const Center(
                        child:
                            Text('暂无分类数据', style: TextStyle(fontSize: 14, color: _textSecondary)))
                    : _buildTree(),
          ),
          if (widget.isSelect) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '请输入分类名称/编码',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                  // 有输入内容时显示清空按钮
                  suffixIcon: _searchText.isNotEmpty
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchText = '');
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.cancel, size: 16, color: Color(0xFFBFBFBF)),
                          ),
                        )
                      : null,
                  contentPadding: EdgeInsets.zero,
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
                onChanged: (v) => setState(() => _searchText = v.trim()),
              ),
            ),
            if (!widget.isSelect) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _handleAddRoot,
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
          ],
        ),
      ),
    );
  }

  Widget _buildTree() {
    final filtered = _filterTree(_tree, _searchText);
    final expandAll = _searchText.isNotEmpty;
    // 预展平树：一次遍历生成扁平列表，避免每个 item 都递归查找 O(N²)→O(N)
    _flatNodes = _flattenTree(filtered, expandAll);
    final showAllRow = widget.showAll && widget.isMultiSelect;
    return RefreshIndicator(
      color: _primaryColor,
      onRefresh: _loadCategories,
      child: ListView.builder(
        cacheExtent: 800,
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _flatNodes.length + (showAllRow ? 1 : 0),
        itemBuilder: (context, index) {
          if (showAllRow && index == 0) return _buildAllCategoryRow();
          final data = _flatNodes[index - (showAllRow ? 1 : 0)];
          return _buildTreeNodeWidget(data);
        },
      ),
    );
  }

  Widget _buildAllCategoryRow() {
    return GestureDetector(
      onTap: _handleSelectAll,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _dividerColor, width: 0.5)),
        ),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _allSelected ? _primaryColor : Colors.transparent,
              border: Border.all(
                color: _allSelected ? _primaryColor : const Color(0xFFD1D5DB),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _allSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('全部分类',
                style: TextStyle(fontSize: 14, color: _textPrimary, fontWeight: FontWeight.w500)),
          ),
        ]),
      ),
    );
  }

  void _handleSelectAll() {
    setState(() {
      _allSelected = true;
      _selectedIds.clear();
      _selectedNodes.clear();
      _indeterminateIds.clear();
    });
  }

  /// 一次 DFS 将树展平为列表，携带深度和树形元信息
  List<_FlatNodeData> _flattenTree(List<Map<String, dynamic>> nodes, bool expandAll,
      [int depth = 0, List<bool> ancestorIsLast = const []]) {
    final result = <_FlatNodeData>[];
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final isLast = i == nodes.length - 1;
      result.add(_FlatNodeData(
        node: node,
        depth: depth,
        isLast: isLast,
        ancestorIsLast: List<bool>.from(ancestorIsLast),
      ));
      final id = node['typeid']?.toString() ?? '';
      final children = node['children'] as List? ?? [];
      if (children.isNotEmpty && (expandAll || _expandedIds.contains(id))) {
        final newAncestors = List<bool>.from(ancestorIsLast)..add(isLast);
        result.addAll(_flattenTree(
            children.cast<Map<String, dynamic>>(), expandAll, depth + 1, newAncestors));
      }
    }
    return result;
  }

  /// 根据预展平数据构建节点 Widget
  Widget _buildTreeNodeWidget(_FlatNodeData data) {
    return _TreeNodeWidget(
      key: ValueKey(data.node['typeid']?.toString() ?? ''),
      node: data.node,
      depth: data.depth,
      isLast: data.isLast,
      ancestorIsLast: data.ancestorIsLast,
      expandAll: _searchText.isNotEmpty,
      isSelectMode: widget.isSelect,
      isMultiSelect: widget.isMultiSelect,
      selectedTypeId: _selectedNode?['typeid']?.toString(),
      selectedIds: _selectedIds,
      indeterminateIds: _indeterminateIds,
      expandedIds: _expandedIds,
      onToggleExpand: _handleToggleExpand,
      onSelect: _handleSelectNode,
      onEdit: () => _openEditSheet(editNode: data.node),
      onAddChild: () {
        if (!PermissionUtils.checkPermission('010102', showTip: false)) {
          Toast.show('你无权新增商品分类，请在后台修改权限');
          return;
        }
        _openEditSheet(parentNode: data.node);
      },
    );
  }

  void _handleToggleExpand(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _handleSelectNode(Map<String, dynamic> node) {
    if (widget.isMultiSelect) {
      final id = node['typeid']?.toString() ?? '';
      if (id.isEmpty) return;
      final descendantIds = _getDescendantIds(node);
      setState(() {
        _allSelected = false;
        if (_selectedIds.contains(id)) {
          // 取消：移除本节点及其所有子孙，并向上同步祖先状态
          _selectedIds.removeAll(descendantIds);
          _syncUp(id);
        } else {
          // 选中：加入本节点及其所有子孙，并向上同步祖先状态
          _selectedIds.addAll(descendantIds);
          _syncUp(id);
        }
        _refreshSelectedNodes();
        _recomputeIndeterminate();
      });
      return;
    }
    setState(() => _selectedNode = node);
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('取消', style: TextStyle(fontSize: 15, color: _textSecondary)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _confirm,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (widget.isMultiSelect
                          ? (_selectedNodes.isNotEmpty || _allSelected)
                          : _selectedNode != null)
                      ? _primaryColor
                      : const Color(0xFF93B8F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('确定',
                    style:
                        TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 预展平节点数据（轻量，不持有 Widget）
class _FlatNodeData {
  _FlatNodeData({
    required this.node,
    required this.depth,
    required this.isLast,
    required this.ancestorIsLast,
  });
  final Map<String, dynamic> node;
  final int depth;
  final bool isLast;
  final List<bool> ancestorIsLast;
}

/// 独立的树节点 Widget，利用 Flutter widget 复用机制提升列表性能
class _TreeNodeWidget extends StatelessWidget {
  const _TreeNodeWidget({
    super.key,
    required this.node,
    required this.depth,
    required this.isLast,
    required this.ancestorIsLast,
    required this.expandAll,
    required this.isSelectMode,
    required this.isMultiSelect,
    required this.selectedTypeId,
    required this.selectedIds,
    required this.indeterminateIds,
    required this.expandedIds,
    required this.onToggleExpand,
    required this.onSelect,
    required this.onEdit,
    required this.onAddChild,
  });
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _treeLineColor = Color(0xFFBDBDBD);
  static const Color _selectedBg = Color(0xFFEBF3FF);
  static const double _treeIndent = 28.0;

  final Map<String, dynamic> node;
  final int depth;
  final bool isLast;
  final List<bool> ancestorIsLast;
  final bool expandAll;
  final bool isSelectMode;
  final bool isMultiSelect;
  final String? selectedTypeId;
  final Set<String> selectedIds;
  final Set<String> indeterminateIds;
  final Set<String> expandedIds;
  final ValueChanged<String> onToggleExpand;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onEdit;
  final VoidCallback onAddChild;

  @override
  Widget build(BuildContext context) {
    final id = node['typeid']?.toString() ?? '';
    final name = node['name']?.toString() ?? node['typename']?.toString() ?? '';
    final code = node['typecode']?.toString() ?? node['code']?.toString() ?? '';
    final children = node['children'] as List? ?? [];
    final hasChildren = children.isNotEmpty;
    final isExpanded = expandAll || expandedIds.contains(id);
    final isSelected =
        isSelectMode && (isMultiSelect ? selectedIds.contains(id) : selectedTypeId == id);
    final isIndeterminate =
        isSelectMode && isMultiSelect && !isSelected && indeterminateIds.contains(id);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? _selectedBg : Colors.white,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.6),
          ),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            // ── 树形缩进 + 连接线区域 ──
            if (depth > 0) ...[
              for (int i = 0; i < depth - 1; i++)
                SizedBox(
                  width: _treeIndent,
                  child: CustomPaint(
                    size: const Size(_treeIndent, 44),
                    painter: _TreeGuidePainter(
                      type: (ancestorIsLast.length > i && ancestorIsLast[i])
                          ? _GuideType.blank
                          : _GuideType.vertical,
                      color: _treeLineColor,
                    ),
                  ),
                ),
              SizedBox(
                width: _treeIndent,
                child: CustomPaint(
                  size: const Size(_treeIndent, 44),
                  painter: _TreeGuidePainter(
                    type: isLast ? _GuideType.last : _GuideType.branch,
                    color: _treeLineColor,
                  ),
                ),
              ),
            ],
            // ── 节点图标（展开/折叠或叶子指示） ──
            _buildExpandButton(id, hasChildren, isExpanded, isSelected),
            // ── 文字（点击选中） ──
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isSelectMode ? () => onSelect(node) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    code.isNotEmpty ? '[$code]$name' : name,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSelected ? _primaryColor : _textPrimary,
                      fontWeight: depth == 0
                          ? FontWeight.w600
                          : (isSelected ? FontWeight.w600 : FontWeight.normal),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            // ── 右侧操作区 ──
            if (isSelectMode && isMultiSelect) _buildCheckbox(isSelected, isIndeterminate),
            if (isSelectMode && !isMultiSelect) _buildRadio(isSelected),
            if (!isSelectMode) ..._buildActionButtons(depth),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandButton(String id, bool hasChildren, bool isExpanded, bool isSelected) {
    if (hasChildren) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggleExpand(id),
        child: SizedBox(
          width: 36,
          height: 44,
          child: Center(
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                isExpanded ? Icons.keyboard_arrow_down : Icons.add,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 36,
      height: 44,
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isSelected ? _primaryColor : const Color(0xFF9CA3AF),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildRadio(bool isSelected) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(node),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? _primaryColor : const Color(0xFFD1D5DB),
              width: 2,
            ),
            color: isSelected ? _primaryColor : Colors.white,
          ),
          child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
        ),
      ),
    );
  }

  Widget _buildCheckbox(bool isSelected, bool isIndeterminate) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(node),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected || isIndeterminate ? _primaryColor : const Color(0xFFD1D5DB),
              width: 2,
            ),
            color: isSelected || isIndeterminate ? _primaryColor : Colors.white,
          ),
          child: isIndeterminate
              ? const Center(
                  child: SizedBox(
                    width: 8,
                    height: 2,
                    child: DecoratedBox(decoration: BoxDecoration(color: Colors.white)),
                  ),
                )
              : (isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null),
        ),
      ),
    );
  }

  /// 构建操作按钮（编辑 + 新增子分类）
  /// 参考 boss 项目 next-tree.vue：仅当节点层级 < 最大可新增层级时才显示「+」按钮
  /// API 限制最多4级，depth 0-indexed（depth=0 对应第1级），depth >= 3 时不允许再新增子级
  static const int _maxAddDepth = 3;

  List<Widget> _buildActionButtons(int depth) {
    return [
      GestureDetector(
        onTap: onEdit,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.edit_outlined, size: 17, color: _textSecondary),
        ),
      ),
      if (depth < _maxAddDepth)
        GestureDetector(
          onTap: onAddChild,
          child: Padding(
            padding: const EdgeInsets.only(left: 2, right: 8),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.add, size: 15, color: _textPrimary),
            ),
          ),
        ),
    ];
  }
}

/// 树形连接线类型
enum _GuideType { blank, vertical, branch, last }

/// 树形引导线绘制器
class _TreeGuidePainter extends CustomPainter {
  _TreeGuidePainter({required this.type, required this.color});
  final _GuideType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (type == _GuideType.blank) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final x = size.width * 0.5;
    final midY = size.height * 0.5;

    switch (type) {
      case _GuideType.vertical:
        // 纯竖线（祖先列延续）
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        break;
      case _GuideType.branch:
        // ├ 形：竖线贯穿 + 横线向右
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        canvas.drawLine(Offset(x, midY), Offset(size.width, midY), paint);
        break;
      case _GuideType.last:
        // └ 形：竖线到中间截止 + 横线向右
        canvas.drawLine(Offset(x, 0), Offset(x, midY), paint);
        canvas.drawLine(Offset(x, midY), Offset(size.width, midY), paint);
        break;
      case _GuideType.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TreeGuidePainter oldDelegate) =>
      type != oldDelegate.type || color != oldDelegate.color;
}
