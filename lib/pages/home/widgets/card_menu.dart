import 'package:flutter/material.dart';

/// 卡片右上角 ⋮ 设置菜单
class CardMenu extends StatelessWidget {
  const CardMenu({
    super.key,
    required this.fieldId,
    required this.onPin,
    required this.onHide,
    required this.onManage,
  });
  final String fieldId;
  final VoidCallback onPin;
  final VoidCallback onHide;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    // 菜单在图标正下方弹出（under）；Flutter 会自动根据按钮靠屏幕右边缘
    // 将菜单右边缘对齐按钮右边缘，无需手动水平偏移（否则菜单会偏离图标）
    return PopupMenuButton<int>(
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      padding: EdgeInsets.zero,
      color: Colors.white,
      elevation: 4,
      constraints: const BoxConstraints.tightFor(width: 120),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.more_horiz, size: 22, color: Color(0xFF9F9F9F)),
      ),
      onSelected: (v) {
        if (v == 1) return onPin();
        if (v == 2) return onHide();
        if (v == 3) return onManage();
      },
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          value: 1,
          padding: EdgeInsets.zero,
          child: GestureDetector(
            onTap: () {
              Navigator.pop(context, 1);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: const _MenuItem(icon: Icons.push_pin, label: '置顶卡片'),
            ),
          ),
        ),
        PopupMenuItem<int>(
          value: 2,
          padding: EdgeInsets.zero,
          child: GestureDetector(
            onTap: () {
              Navigator.pop(context, 2);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: const _MenuItem(icon: Icons.close, label: '关闭卡片'),
            ),
          ),
        ),
        PopupMenuItem<int>(
          value: 3,
          padding: EdgeInsets.zero,
          child: GestureDetector(
            onTap: () {
              Navigator.pop(context, 3);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: const _MenuItem(icon: Icons.settings, label: '管理卡片'),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3FF),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: const Color(0xFF333333)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
      ]),
    );
  }
}
