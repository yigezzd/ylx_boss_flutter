import 'package:flutter/material.dart';

/// 日期范围日历选择弹窗（底部弹窗，品牌蓝风格）
///
/// 交互：第一次点击选开始日期，第二次点击选结束日期，再点则重新开始选择。
/// 选定后点底部蓝色通栏「确定」按钮返回 (开始, 结束)；取消返回 null。
///
/// 用法：
/// ```dart
/// final range = await showDateRangeCalendarPicker(context);
/// if (range != null) {
///   final start = range.$1;
///   final end = range.$2;
/// }
/// ```
Future<(DateTime, DateTime)?> showDateRangeCalendarPicker(
  BuildContext context, {
  DateTime? initialStart,
  DateTime? initialEnd,
}) {
  return showModalBottomSheet<(DateTime, DateTime)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DateRangeCalendarSheet(
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );
}

class _DateRangeCalendarSheet extends StatefulWidget {
  const _DateRangeCalendarSheet({this.initialStart, this.initialEnd});

  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  State<_DateRangeCalendarSheet> createState() => _DateRangeCalendarSheetState();
}

class _DateRangeCalendarSheetState extends State<_DateRangeCalendarSheet> {
  static const Color _primary = Color(0xFF006EFF);
  static const List<String> _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  /// 当前展示的年月
  late DateTime _viewMonth;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    final anchor = _start ?? widget.initialEnd ?? DateTime.now();
    _viewMonth = DateTime(anchor.year, anchor.month);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _changeMonth(int delta) {
    setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta));
  }

  /// 本日：定位到当月并把范围重置为今天
  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _viewMonth = DateTime(now.year, now.month);
      _start = DateTime(now.year, now.month, now.day);
      _end = DateTime(now.year, now.month, now.day);
    });
  }

  void _onDayTap(DateTime day) {
    setState(() {
      if (_start == null || _end != null) {
        // 未开始选择或已完成一次选择：重新从开始选
        _start = day;
        _end = null;
      } else {
        // 第二次点击：结束日期，小的在前
        if (day.isBefore(_start!)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
      }
    });
  }

  void _confirm() {
    if (_start == null) {
      _showToast('请先选择开始日期');
      return;
    }
    Navigator.pop(context, (_start!, _end ?? _start!));
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 14)),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 标题栏 ──
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child:
                        const Text('取消', style: TextStyle(fontSize: 15, color: Color(0xFF666666))),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('选择日期范围',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            // ── 月份导航 ──
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _changeMonth(-1),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.chevron_left, size: 22, color: Color(0xFF666666)),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_viewMonth.year}-${_viewMonth.month.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _changeMonth(1),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.chevron_right, size: 22, color: Color(0xFF666666)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _goToday,
                    child: Container(
                      width: 52,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: _primary),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Text('本日', style: TextStyle(fontSize: 13, color: _primary)),
                    ),
                  ),
                ],
              ),
            ),
            // ── 星期表头 ──
            Row(
              children: [
                for (final w in _weekLabels)
                  Expanded(
                    child: Center(
                      child:
                          Text(w, style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // ── 日期网格 ──
            _buildCalendarGrid(),
            const SizedBox(height: 8),
            // ── 已选范围提示 ──
            Row(
              children: [
                Text('开始：${_start != null ? _fmt(_start!) : '--'}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
                const Spacer(),
                Text('结束：${_end != null ? _fmt(_end!) : '--'}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
              ],
            ),
            const SizedBox(height: 12),
            // ── 确认按钮（通栏蓝色）──
            GestureDetector(
              onTap: _confirm,
              child: Container(
                width: double.infinity,
                height: 44,
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('确定',
                    style:
                        TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 当月日历网格（固定 6 行，切换月份高度不变）
  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_viewMonth.year, _viewMonth.month);
    final daysInMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final leading = firstDay.weekday - 1; // 周一为 0
    const rows = 6;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      children: [
        for (int r = 0; r < rows; r++)
          Row(
            children: [
              for (int c = 0; c < 7; c++)
                Expanded(child: _buildDayCell(r * 7 + c - leading + 1, daysInMonth, today)),
            ],
          ),
      ],
    );
  }

  Widget _buildDayCell(int dayNum, int daysInMonth, DateTime today) {
    if (dayNum < 1 || dayNum > daysInMonth) {
      // 与有日期格子高度一致（44 + margin 4 = 48），保证每月总高度完全一致
      return const SizedBox(height: 48);
    }
    final day = DateTime(_viewMonth.year, _viewMonth.month, dayNum);
    final isStart = _start != null && _isSameDay(day, _start!);
    final isEnd = _end != null && _isSameDay(day, _end!);
    final inRange = _start != null && _end != null && day.isAfter(_start!) && day.isBefore(_end!);
    final isToday = _isSameDay(day, today);

    Color? bg;
    Color textColor = const Color(0xFF333333);
    if (isStart || isEnd) {
      bg = _primary;
      textColor = Colors.white;
    } else if (inRange) {
      bg = _primary.withOpacity(0.12);
      textColor = _primary;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onDayTap(day),
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: isToday && !isStart && !isEnd ? Border.all(color: _primary, width: 1.2) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$dayNum',
          style: TextStyle(fontSize: 14, color: textColor),
        ),
      ),
    );
  }
}
