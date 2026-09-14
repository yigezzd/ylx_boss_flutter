import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 打印模板选择页面
/// 业务逻辑参考 boss 项目 subs/user/businessPrintSet/busBillTemp.vue
class BillTemplatePage extends StatefulWidget {
  const BillTemplatePage({super.key, this.airno = ''});
  final String airno;

  @override
  State<BillTemplatePage> createState() => _BillTemplatePageState();
}

class _BillTemplatePageState extends State<BillTemplatePage> {
  /// 分类列表（按 grouptype 分组）
  List<_CategoryGroup> _categories = [];
  int _selectedCatIndex = 0;
  String _selectedMcode = '';

  /// 模板列表
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  bool _settingDefault = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  /// 获取分类列表
  Future<void> _loadCategories() async {
    try {
      final result = await request(
        HttpApi.getModelList,
        {'is_page': 0},
        true,
      );
      final data = result['data'];
      if (data is List && data.isNotEmpty) {
        // 按 grouptype 分组
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (final item in data) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final String group = m['grouptype']?.toString() ?? '';
            if (group.isEmpty) continue;
            grouped.putIfAbsent(group, () => []).add(m);
          }
        }
        final cats = grouped.entries
            .where((e) => e.key != '其他')
            .map((e) => _CategoryGroup(name: e.key, items: e.value))
            .toList();

        if (cats.isEmpty) {
          setState(() {
            _categories = [];
            _templates = [];
            _loading = false;
          });
          return;
        }
        setState(() {
          _categories = cats;
          _selectedCatIndex = 0;
          _selectedMcode = cats.first.items.first['mcode']?.toString() ?? '';
        });
        await _loadTemplates();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 获取模板列表
  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    try {
      final result = await request(
        HttpApi.getTemplateListWx,
        {
          'menuid': _selectedMcode,
          if (widget.airno.isNotEmpty) 'airno': widget.airno,
          'is_page': 0,
        },
      );
      final data = result['data'];
      if (data is List) {
        setState(() {
          _templates = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } else {
        setState(() => _templates = []);
      }
    } catch (_) {
      if (mounted) setState(() => _templates = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 设为默认模板
  Future<void> _setDefault(Map<String, dynamic> item) async {
    if (_settingDefault) return;
    setState(() => _settingDefault = true);
    try {
      await request(
        HttpApi.setTemplateWxDef,
        {
          'menuid': item['menuid']?.toString() ?? '',
          'billid': item['billid']?.toString() ?? '',
        },
      );
      Toast.show('设置成功');
      // 刷新列表以更新默认标识
      await _loadTemplates();
    } catch (_) {
      // 接口异常由 http_helper 统一 Toast
    } finally {
      if (mounted) setState(() => _settingDefault = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '打印模板'),
      backgroundColor: const Color(0xFFF5F6FA),
      body: _loading && _categories.isEmpty
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : SafeArea(
              child: Row(
                children: [
                  // 左侧分类列表
                  SizedBox(
                    // 左侧类别宽度在原 120 基础上增加 1/3（120*4/3=160），避免长分类名截断
                    width: 160,
                    child: ColoredBox(
                      color: Colors.white,
                      child: _buildCategoryList(),
                    ),
                  ),
                  // 右侧模板列表
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : _buildTemplateList(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCategoryList() {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _categories.length,
      itemBuilder: (ctx, idx) {
        final cat = _categories[idx];
        final bool isSelected = idx == _selectedCatIndex;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 分组标题
            ColoredBox(
              color: isSelected ? const Color(0xFFF6F7FB) : Colors.white,
              child: ExpansionTileTheme(
                data: const ExpansionTileThemeData(
                  backgroundColor: Colors.transparent,
                  collapsedBackgroundColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  key: ValueKey('cat_$idx'),
                  initiallyExpanded: isSelected,
                  shape: const Border(),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    cat.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                    ),
                  ),
                  trailing: Icon(
                    isSelected ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: const Color(0xFF999999),
                  ),
                  children: cat.items.asMap().entries.map((entry) {
                    final item = entry.value;
                    final String mcode = item['mcode']?.toString() ?? '';
                    final String title = item['title']?.toString() ?? '';
                    final bool isActive = _selectedMcode == mcode;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedMcode = mcode;
                        });
                        _loadTemplates();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                        color: isActive ? const Color(0xFFF6F7FB) : Colors.white,
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            color: isActive ? const Color(0xFF006EFF) : const Color(0xFF666666),
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
          ],
        );
      },
    );
  }

  Widget _buildTemplateList() {
    if (_templates.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Color(0xFFCCCCCC)),
            SizedBox(height: 12),
            Text(
              '暂无模板',
              style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      cacheExtent: 800,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _templates.length,
      itemBuilder: (ctx, idx) {
        final item = _templates[idx];
        return RepaintBoundary(
          child: _TemplateCard(
            item: item,
            settingDefault: _settingDefault,
            onSetDefault: () => _setDefault(item),
          ),
        );
      },
    );
  }
}

/// 分类分组
class _CategoryGroup {
  _CategoryGroup({required this.name, required this.items});
  final String name;
  final List<Map<String, dynamic>> items;
}

/// 模板卡片（独立 Widget，遵循 listLoad 规则）
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.item,
    required this.settingDefault,
    required this.onSetDefault,
  });
  final Map<String, dynamic> item;
  final bool settingDefault;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final String name = item['template_name']?.toString() ?? '未命名模板';
    final bool isDefault = item['isdefault'] == true || item['isdefault'] == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const BoxDecoration(
                color: Color(0xFF006EFF),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: const Text(
                '默认',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: settingDefault ? null : onSetDefault,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF006EFF)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: settingDefault
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF006EFF)),
                        ),
                      )
                    : const Text(
                        '设为默认',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF006EFF),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
