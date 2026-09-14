import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:reorderables/reorderables.dart';

/// 常用功能设置页面（对齐 Vue setCYList.vue）
class SetCyListPage extends StatefulWidget {
  const SetCyListPage({super.key, required this.allModules, this.initialSelected});

  /// 所有可选模块列表
  final List<CyModuleItem> allModules;

  /// 初始已选中的模块（从服务器加载）
  final List<CyModuleItem>? initialSelected;

  /// 默认常用功能列表
  static const List<CyModuleItem> defaultList = [
    CyModuleItem(title: '商品档案', svgFile: 'probook.svg'),
    CyModuleItem(title: '会员管理', svgFile: 'membermang.svg'),
    CyModuleItem(title: '采购入库', svgFile: 'pointmanage.svg'),
    CyModuleItem(title: '配送收货', svgFile: 'business_pssh.svg'),
  ];

  /// 最大可选数量
  static const int maxCount = 8;

  @override
  State<SetCyListPage> createState() => _SetCyListPageState();
}

class _SetCyListPageState extends State<SetCyListPage> {
  late List<CyModuleItem> _selectedList;
  late Map<String, bool> _showMap;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedList = List<CyModuleItem>.from(widget.initialSelected ?? SetCyListPage.defaultList);
    _initShowMap();
    _loadConfig();
  }

  void _initShowMap() {
    _showMap = <String, bool>{};
    for (final item in widget.allModules) {
      _showMap[item.title] = _selectedList.any((e) => e.title == item.title);
    }
  }

  Future<void> _loadConfig() async {
    try {
      final res = await request(HttpApi.menuCommonGetMenuCommon, <String, dynamic>{});
      final data = res['data'];
      final menujson = (data is Map<String, dynamic> ? data['menujson'] : null)?.toString();
      if (menujson != null && menujson.isNotEmpty) {
        final dynamic decoded = jsonDecode(menujson);
        if (decoded is List) {
          _selectedList = decoded
              .map((e) => CyModuleItem(
                    title: e['tit']?.toString() ?? '',
                    svgFile: e['img']?.toString() ?? '',
                  ))
              .toList();
          _initShowMap();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _handleRemove(int index) {
    setState(() {
      final removed = _selectedList.removeAt(index);
      _showMap[removed.title] = false;
    });
  }

  void _handleToggle(CyModuleItem item, bool value) {
    setState(() {
      _showMap[item.title] = value;
      if (value) {
        // 添加到选中列表
        if (_selectedList.length >= SetCyListPage.maxCount) {
          // 超过最大数量，移除最后一个
          final lastItem = _selectedList.removeLast();
          _showMap[lastItem.title] = false;
        }
        if (!_selectedList.any((e) => e.title == item.title)) {
          _selectedList.add(item);
        }
      } else {
        // 从选中列表移除
        _selectedList.removeWhere((e) => e.title == item.title);
      }
    });
  }

  void _handleReset() {
    setState(() {
      _selectedList = List<CyModuleItem>.from(SetCyListPage.defaultList);
      _initShowMap();
    });
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final menujson =
          jsonEncode(_selectedList.map((e) => {'tit': e.title, 'img': e.svgFile}).toList());
      await request(
        HttpApi.menuCommonSaveMenuCommon,
        {'menujson': menujson},
      );
      if (mounted) {
        Toast.show('保存成功');
        Navigator.of(context).pop(_selectedList);
      }
    } catch (_) {
      if (mounted) Toast.show('保存失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          '设置常用功能',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部：已选中的常用功能
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _buildSelectedSection(),
          ),
          // 提示信息
          _buildInfoBar(),
          // 模块列表
          Expanded(child: _buildModuleList()),
          // 底部按钮
          _buildBottomButtons(),
        ],
      ),
    );
  }

  Widget _buildSelectedSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '常用功能',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / 4;
              return ReorderableWrap(
                onReorder: (int oldIndex, int newIndex) {
                  setState(() {
                    final item = _selectedList.removeAt(oldIndex);
                    _selectedList.insert(newIndex, item);
                  });
                },
                children: [
                  for (int i = 0; i < _selectedList.length; i++) _buildSelectedItem(i, itemWidth),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedItem(int index, double itemWidth) {
    final item = _selectedList[index];
    return GestureDetector(
      onTap: () => _handleRemove(index),
      child: SizedBox(
        width: itemWidth,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BossSvgIcon(svgFile: item.svgFile),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: itemWidth / 2 - 20,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cancel,
                  size: 16,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '开关控制显示和隐藏，最多显示8个',
              style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleList() {
    return ListView.builder(
      itemCount: widget.allModules.length,
      itemBuilder: (context, index) {
        final item = widget.allModules[index];
        final isOn = _showMap[item.title] ?? false;
        return Container(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 1),
          child: ListTile(
            leading: BossSvgIcon(svgFile: item.svgFile, size: 28),
            title: Text(
              item.title,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
            ),
            trailing: Switch.adaptive(
              value: isOn,
              onChanged: (v) => _handleToggle(item, v),
              activeColor: const Color(0xFF3B82F6),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _handleReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF374151),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('恢复默认', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('保存', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 常用功能模块项
class CyModuleItem {
  const CyModuleItem({required this.title, required this.svgFile});

  factory CyModuleItem.fromJson(Map<String, dynamic> json) {
    return CyModuleItem(
      title: json['tit']?.toString() ?? '',
      svgFile: json['img']?.toString() ?? '',
    );
  }

  final String title;
  final String svgFile;

  Map<String, dynamic> toJson() => {'tit': title, 'img': svgFile};
}
