import 'package:flutter/material.dart';

/// 公共表单选择行组件
///
/// 左侧标签（支持必填 * 标记），右侧展示已选值或"请选择"占位文字，
/// 带右箭头，点击触发回调。
class SelectFieldItem extends StatelessWidget {
  const SelectFieldItem({
    super.key,
    required this.label,
    required this.value,
    this.hint = '请选择',
    required this.onTap,
    this.required = false,
    this.labelWidth = 80,
    this.enabled = true,
  });

  /// 标签文字
  final String label;

  /// 当前已选值（为空时显示 hint）
  final String value;

  /// 占位提示文字，默认"请选择"
  final String hint;

  /// 点击事件
  final VoidCallback onTap;

  /// 是否可点击，默认 true
  final bool enabled;

  /// 是否展示必填 * 标记
  final bool required;

  /// 标签宽度，默认 80（与 _buildTextField 等表单字段对齐）
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (required)
                      const Positioned(
                        left: -10,
                        top: 0,
                        child: Text(
                          '*',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value.isNotEmpty ? value : hint,
                  style: TextStyle(
                    fontSize: 14,
                    color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFF006EFF),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
