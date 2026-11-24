import 'package:flutter/material.dart';

/// 未保存修改确认弹窗 —— 对齐 boss 项目「有未保存的信息，确认保存吗？」弹窗
///
/// 返回值：true=保存，false=不保存，null=点击遮罩等方式关闭（视为取消，留在当前页）
Future<bool?> showUnsavedChangesDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => const UnsavedChangesDialog(),
  );
}

class UnsavedChangesDialog extends StatelessWidget {
  const UnsavedChangesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error, size: 22, color: Color(0xFFE6A23C)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '有未保存的信息，确认保存吗？',
                    style: TextStyle(fontSize: 15, color: Color(0xFF374151)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '不保存',
                      style: TextStyle(fontSize: 14, color: Color(0xFF374151)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF006EFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '保存',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
