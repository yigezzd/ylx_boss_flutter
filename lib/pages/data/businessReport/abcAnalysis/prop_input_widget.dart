import 'package:flutter/material.dart';

/// ABC 分析占比输入组件
/// 使用 StatefulWidget 管理自己的 TextEditingController，
/// 避免父级 StatefulBuilder 重建时替换 controller 导致失焦
class PropInputWidget extends StatefulWidget {
  const PropInputWidget({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final void Function(int) onChanged;

  @override
  State<PropInputWidget> createState() => _PropInputWidgetState();
}

class _PropInputWidgetState extends State<PropInputWidget> {
  late TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant PropInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在用户未手动编辑时才同步外部值（避免输入过程中被覆盖）
    if (!_isEditing && oldWidget.value != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(widget.label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        ),
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    controller: _controller,
                    onTap: () => setState(() => _isEditing = true),
                    onChanged: (v) {
                      setState(() => _isEditing = true);
                      final n = int.tryParse(v) ?? 0;
                      widget.onChanged(n);
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Text('%', style: TextStyle(fontSize: 14, color: Color(0xFF666666))),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
