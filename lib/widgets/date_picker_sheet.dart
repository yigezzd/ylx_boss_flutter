import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 全应用统一的日期选择器（年/月/日），自动适配深色/浅色主题。
///
/// 用法：
/// ```dart
/// final picked = await showCommonDatePicker(context, initial: DateTime.now());
/// if (picked != null && mounted) { ... }
/// ```
Future<DateTime?> showCommonDatePicker(BuildContext context,
    {required DateTime initial, String title = ''}) async {
  DateTime tempDate = initial;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (c) {
      final textColor = Theme.of(c).colorScheme.onSurface;
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text('取消',
                        style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(title,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, tempDate),
                    child: Text('确定', style: TextStyle(color: Theme.of(c).colorScheme.primary)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(c).dividerColor),
            Expanded(
              child: Row(
                children: [
                  // 年
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.year - 2020,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        tempDate = DateTime(2020 + i, tempDate.month, tempDate.day);
                      },
                      children: List.generate(
                          20,
                          (i) => Center(
                              child: Text('${2020 + i}年',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                  // 月
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.month - 1,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        tempDate = DateTime(tempDate.year, i + 1, tempDate.day);
                      },
                      children: List.generate(
                          12,
                          (i) => Center(
                              child: Text('${i + 1}月',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                  // 日
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.day - 1,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        final maxDay = DateTime(tempDate.year, tempDate.month + 1, 0).day;
                        tempDate =
                            DateTime(tempDate.year, tempDate.month, (i + 1).clamp(1, maxDay));
                      },
                      children: List.generate(
                          31,
                          (i) => Center(
                              child: Text('${i + 1}日',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 全应用统一的月份选择器（仅年/月），自动适配深色/浅色主题。
///
/// 用于"本月"等仅需选择年月的场景。
/// 返回值中 day 字段为 1，调用方需自行计算起止日期。
///
/// 用法：
/// ```dart
/// final picked = await showCommonMonthPicker(context, initial: DateTime.now());
/// if (picked != null && mounted) {
///   final start = DateTime(picked.year, picked.month);
///   final end = DateTime(picked.year, picked.month + 1, 0);
/// }
/// ```
Future<DateTime?> showCommonMonthPicker(BuildContext context, {required DateTime initial}) async {
  DateTime tempDate = DateTime(initial.year, initial.month);
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (c) {
      final textColor = Theme.of(c).colorScheme.onSurface;
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text('取消',
                        style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(c, tempDate),
                    child: Text('确定', style: TextStyle(color: Theme.of(c).colorScheme.primary)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(c).dividerColor),
            Expanded(
              child: Row(
                children: [
                  // 年
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.year - 2020,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        tempDate = DateTime(2020 + i, tempDate.month);
                      },
                      children: List.generate(
                          20,
                          (i) => Center(
                              child: Text('${2020 + i}年',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                  // 月
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: tempDate.month - 1,
                      ),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        tempDate = DateTime(tempDate.year, i + 1);
                      },
                      children: List.generate(
                          12,
                          (i) => Center(
                              child: Text('${i + 1}月',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 全应用统一的时间选择器（时/分/秒），自动适配深色/浅色主题。
///
/// [initial] 格式为 "HH:mm:ss"，返回值同为 "HH:mm:ss"，取消返回 null。
///
/// 用法：
/// ```dart
/// final picked = await showCommonTimePicker(context, initial: '08:30:00');
/// if (picked != null && mounted) { ... }
/// ```
Future<String?> showCommonTimePicker(BuildContext context, {required String initial}) async {
  final parts = initial.split(':');
  int tempHour = int.tryParse(parts[0]) ?? 0;
  int tempMinute = int.tryParse(parts[1]) ?? 0;
  int tempSecond = int.tryParse(parts[2]) ?? 0;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (c) {
      final textColor = Theme.of(c).colorScheme.onSurface;
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text('取消',
                        style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(
                        c,
                        '${tempHour.toString().padLeft(2, '0')}'
                        ':${tempMinute.toString().padLeft(2, '0')}'
                        ':${tempSecond.toString().padLeft(2, '0')}'),
                    child: Text('确定', style: TextStyle(color: Theme.of(c).colorScheme.primary)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(c).dividerColor),
            Expanded(
              child: Row(
                children: [
                  // 时
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempHour),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => tempHour = i,
                      children: List.generate(
                          24,
                          (i) => Center(
                              child: Text('${i.toString().padLeft(2, '0')}时',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                  // 分
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempMinute),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => tempMinute = i,
                      children: List.generate(
                          60,
                          (i) => Center(
                              child: Text('${i.toString().padLeft(2, '0')}分',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                  // 秒
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempSecond),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => tempSecond = i,
                      children: List.generate(
                          60,
                          (i) => Center(
                              child: Text('${i.toString().padLeft(2, '0')}秒',
                                  style: TextStyle(fontSize: 16, color: textColor)))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 全应用统一的日期时间选择器（年/月/日 时/分/秒），自动适配深色/浅色主题。
///
/// [initial] 格式为 "YYYY-MM-DD HH:mm:ss" 或 "YYYY-MM-DD"，返回值同为 "YYYY-MM-DD HH:mm:ss"。
/// 取消返回 null。
///
/// 用法：
/// ```dart
/// final picked = await showCommonDateTimePicker(context, initial: '2026-07-29 14:30:00');
/// if (picked != null && mounted) { ... }
/// ```
Future<String?> showCommonDateTimePicker(BuildContext context, {required String initial}) async {
  final dt = DateTime.tryParse(initial) ?? DateTime.now();
  int tempYear = dt.year;
  int tempMonth = dt.month;
  int tempDay = dt.day;
  int tempHour = dt.hour;
  int tempMinute = dt.minute;
  int tempSecond = dt.second;

  String buildResult() {
    return '$tempYear-'
        '${tempMonth.toString().padLeft(2, '0')}-'
        '${tempDay.toString().padLeft(2, '0')} '
        '${tempHour.toString().padLeft(2, '0')}:'
        '${tempMinute.toString().padLeft(2, '0')}:'
        '${tempSecond.toString().padLeft(2, '0')}';
  }

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (c) {
      final textColor = Theme.of(c).colorScheme.onSurface;
      return SizedBox(
        height: 300,
        child: Column(
          children: [
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text('取消',
                        style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(c, buildResult()),
                    child: Text('确定', style: TextStyle(color: Theme.of(c).colorScheme.primary)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(c).dividerColor),
            Expanded(
              child: Row(
                children: [
                  // 年
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempYear - 2020),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => tempYear = 2020 + i,
                      children: List.generate(
                          20,
                          (i) => Center(
                              child: Text('${2020 + i}年',
                                  style: TextStyle(fontSize: 15, color: textColor)))),
                    ),
                  ),
                  // 月
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempMonth - 1),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => tempMonth = i + 1,
                      children: List.generate(
                          12,
                          (i) => Center(
                              child: Text('${i + 1}月',
                                  style: TextStyle(fontSize: 15, color: textColor)))),
                    ),
                  ),
                  // 日
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempDay - 1),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) {
                        final maxDay = DateTime(tempYear, tempMonth + 1, 0).day;
                        tempDay = (i + 1).clamp(1, maxDay);
                      },
                      children: List.generate(
                          31,
                          (i) => Center(
                              child: Text('${i + 1}日',
                                  style: TextStyle(fontSize: 15, color: textColor)))),
                    ),
                  ),
                  // 时
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempHour),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => tempHour = i,
                      children: List.generate(
                          24,
                          (i) => Center(
                              child: Text('${i.toString().padLeft(2, '0')}时',
                                  style: TextStyle(fontSize: 15, color: textColor)))),
                    ),
                  ),
                  // 分
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempMinute),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => tempMinute = i,
                      children: List.generate(
                          60,
                          (i) => Center(
                              child: Text('${i.toString().padLeft(2, '0')}分',
                                  style: TextStyle(fontSize: 15, color: textColor)))),
                    ),
                  ),
                  // 秒
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: tempSecond),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => tempSecond = i,
                      children: List.generate(
                          60,
                          (i) => Center(
                              child: Text('${i.toString().padLeft(2, '0')}秒',
                                  style: TextStyle(fontSize: 15, color: textColor)))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
