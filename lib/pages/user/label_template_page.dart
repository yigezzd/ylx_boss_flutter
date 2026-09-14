import 'package:flutter/material.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 标签模板选择页面
/// 业务逻辑参考小程序 subs/user/printSet/labelTemplate.vue
class LabelTemplatePage extends StatefulWidget {
  const LabelTemplatePage({
    super.key,
    this.initialTemplate = 1,
  });

  /// 当前选中的模板 ID
  final int initialTemplate;

  @override
  State<LabelTemplatePage> createState() => _LabelTemplatePageState();
}

class _LabelTemplatePageState extends State<LabelTemplatePage> {
  static const Color _primaryColor = Color(0xFF006EFF);

  late int _selectedTemplate;

  static const List<_TemplateItem> _templates = [
    _TemplateItem(id: 1, name: '系统样式1 (60×40)', width: 240, height: 160),
    _TemplateItem(id: 2, name: '系统样式2 (50×30)', width: 200, height: 120),
    _TemplateItem(id: 3, name: '系统样式3 (40×30)', width: 160, height: 120),
    _TemplateItem(id: 4, name: '系统样式4 (45×20)', width: 180, height: 80),
  ];

  @override
  void initState() {
    super.initState();
    _selectedTemplate = widget.initialTemplate;
  }

  /// 选择模板并返回结果（对齐小程序 onUnload 时 emit templateResult）
  void _selectTemplate(int id) {
    setState(() => _selectedTemplate = id);
    // 选择后立即返回上一页，回传选中的模板 ID
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '选择打印模板'),
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _templates.length,
          cacheExtent: 800,
          itemBuilder: (context, index) {
            final tpl = _templates[index];
            return RepaintBoundary(
              child: _TemplateCard(
                template: tpl,
                isSelected: _selectedTemplate == tpl.id,
                onSelect: () => _selectTemplate(tpl.id),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── 模板数据 ───

class _TemplateItem {
  const _TemplateItem({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
  });

  final int id;
  final String name;
  final double width;
  final double height;
}

// ─── 模板卡片 ───

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.isSelected,
    required this.onSelect,
  });

  final _TemplateItem template;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：模板名称 + 默认/设为默认
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Text(
                  template.name,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
                ),
                const Spacer(),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: _LabelTemplatePageState._primaryColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '默认',
                      style: TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: onSelect,
                    child: const Text(
                      '设为默认',
                      style: TextStyle(fontSize: 14, color: _LabelTemplatePageState._primaryColor),
                    ),
                  ),
              ],
            ),
          ),
          // 标签预览区（对齐小程序 label-preview 样式）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: template.width,
              height: template.height,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                border: Border.all(
                    color: const Color(0xFFDDDDDD),
                    width: 0.5,
                    strokeAlign: BorderSide.strokeAlignOutside),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: template.id == 4 ? const EdgeInsets.all(4) : const EdgeInsets.all(10),
              child: _buildPreview(template),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 模板预览内容 ───

  static Widget _buildPreview(_TemplateItem template) {
    if (template.id == 4) {
      return _buildTemplate4Preview();
    }
    return _buildDefaultPreview();
  }

  static Widget _buildDefaultPreview() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '大米',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
        ),
        SizedBox(height: 4),
        Row(
          children: [
            Text('折后单价: 5.00', style: TextStyle(fontSize: 11, color: Color(0xFF666666))),
            Spacer(),
            Text('小计: 5.00', style: TextStyle(fontSize: 11, color: Color(0xFF666666))),
          ],
        ),
        SizedBox(height: 2),
        Row(
          children: [
            Text('零售价: 5.00', style: TextStyle(fontSize: 11, color: Color(0xFF666666))),
            Spacer(),
            Text('折扣: 100.00', style: TextStyle(fontSize: 11, color: Color(0xFF666666))),
          ],
        ),
        // 条码区域：自适应剩余空间，条码满宽
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: CustomPaint(
                  painter: _BarcodePainter(),
                  child: SizedBox.expand(),
                ),
              ),
              SizedBox(height: 2),
              Text(
                '21546545456',
                style: TextStyle(fontSize: 9, color: Color(0xFF666666)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildTemplate4Preview() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '08-21 18:21',
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
            ),
            Spacer(),
            Text(
              '原价：5.00',
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
            ),
            Spacer(),
            Text(
              '5.0折',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
            ),
          ],
        ),
        SizedBox(height: 1),
        Center(
          child: Text(
            '折扣价：5.00',
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
          ),
        ),
        SizedBox(height: 1),
        Text(
          '大米',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 1),
        SizedBox(
          height: 14,
          child: CustomPaint(
            painter: _BarcodePainter(),
            child: SizedBox.expand(),
          ),
        ),
        Text(
          '21546545456',
          style: TextStyle(fontSize: 7, color: Color(0xFF666666)),
        ),
      ],
    );
  }
}

/// 模拟 CODE128 条码竖线条纹绘制器
class _BarcodePainter extends CustomPainter {
  const _BarcodePainter();

  // 模拟 CODE128 条码 pattern（黑白交替宽度）
  static const List<int> _pattern = [
    2,
    1,
    1,
    2,
    3,
    1,
    2,
    1,
    1,
    3,
    2,
    1,
    1,
    2,
    3,
    1,
    1,
    2,
    1,
    3,
    2,
    1,
    3,
    1,
    1,
    2,
    2,
    1,
    1,
    3,
    1,
    2,
    1,
    2,
    3,
    1,
    1,
    2,
    2,
    1,
    3,
    1,
    1,
    2,
    1,
    2,
    3,
    2,
    1,
    1,
    2,
    1,
    3,
    1,
    2,
    1,
    2,
    3,
    1,
    1,
    2,
    1,
    2,
    1,
    1,
    3,
    2,
    1,
    3,
    1,
    2,
    1,
    1,
    2,
    3,
    1,
    2,
    1,
    2,
    3,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF333333);
    final totalModules = _pattern.fold<int>(0, (s, w) => s + w);
    final moduleWidth = size.width / totalModules;
    double x = 0;
    bool isBlack = true;
    for (final w in _pattern) {
      if (isBlack) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, w * moduleWidth, size.height),
          paint,
        );
      }
      x += w * moduleWidth;
      isBlack = !isBlack;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
