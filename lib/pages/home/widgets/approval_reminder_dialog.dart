import 'package:flutter/material.dart';

/// 单据审批提醒弹窗（对齐 Vue approvalReminder.vue）
class ApprovalReminderDialog extends StatefulWidget {
  const ApprovalReminderDialog({
    super.key,
    required this.items,
    this.onItemTap,
  });
  final List<ApprovalItem> items;

  /// 点击单据项回调，返回 true 已跳转，false 未找到页面
  final bool Function(ApprovalItem item)? onItemTap;

  @override
  State<ApprovalReminderDialog> createState() => _ApprovalReminderDialogState();
}

class _ApprovalReminderDialogState extends State<ApprovalReminderDialog> {
  bool _dontRemind = false;

  void _handleItemTap(ApprovalItem item) {
    if (widget.onItemTap != null) {
      widget.onItemTap!(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 18, 0, 12),
              child: Text(
                '单据审批提醒',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            // 列表
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF5F5F5)),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return InkWell(
                    onTap: () => _handleItemTap(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(item.name,
                                style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4D4F),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${item.count}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right, size: 16, color: Color(0xFF999999)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // 底部
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  // 不再提醒
                  GestureDetector(
                    onTap: () => setState(() => _dontRemind = !_dontRemind),
                    child: Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _dontRemind ? const Color(0xFF006EFF) : Colors.white,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                                color: _dontRemind
                                    ? const Color(0xFF006EFF)
                                    : const Color(0xFFD0D0D0)),
                          ),
                          child: _dontRemind
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('本次登录不再提醒',
                            style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 知道了按钮
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006EFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => Navigator.of(context).pop(_dontRemind),
                      child: const Text('知道了',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ApprovalItem {
  const ApprovalItem({required this.billtypeid, required this.name, required this.count});
  final String billtypeid;
  final String name;
  final int count;
}
