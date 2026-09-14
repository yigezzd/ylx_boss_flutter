import 'package:flutter/material.dart';
import 'package:flutter_deer/routers/routers.dart';

/// 库存不足滚动提醒条（对齐 Vue stock-notice）
class StockNoticeBar extends StatefulWidget {
  const StockNoticeBar({
    super.key,
    required this.tips,
  });
  final List<String> tips;

  @override
  State<StockNoticeBar> createState() => _StockNoticeBarState();
}

class _StockNoticeBarState extends State<StockNoticeBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.tips.length > 1) {
      _scheduleNext();
    }
  }

  void _scheduleNext() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || widget.tips.length <= 1) return;
      _controller.forward(from: 0).then((_) {
        setState(() => _idx = (_idx + 1) % widget.tips.length);
        _controller.reset();
        _scheduleNext();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tips.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(Routes.stockWarning),
      child: Container(
        height: 43,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.volume_up, size: 16, color: Color(0xFF7A7A7A)),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.tips[_idx],
                    key: ValueKey(_idx),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: Color(0xFFFF4D4F), shape: BoxShape.circle),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF999999)),
          ],
        ),
      ),
    );
  }
}
