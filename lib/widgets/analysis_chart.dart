import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// 通用分析折线图
class AnalysisChart extends StatefulWidget {
  const AnalysisChart({
    super.key,
    required this.data,
    required this.valueLabel,
    this.lineColor = const Color(0xFF006EFF),
    this.showAllBottomLabels = false,
    this.tooltipLabels,
    this.valueDecimals = 0,
    this.valueSuffix = '',
  });
  final List<({String label, double value})> data;
  final String valueLabel;
  final Color lineColor;
  final bool showAllBottomLabels;
  final List<String>? tooltipLabels;
  final int valueDecimals;
  final String valueSuffix;

  @override
  State<AnalysisChart> createState() => _AnalysisChartState();
}

class _AnalysisChartState extends State<AnalysisChart> {
  int? _selectedIdx;

  List<({String label, double value})> get d => widget.data;
  Color get c => widget.lineColor;

  @override
  Widget build(BuildContext context) {
    if (d.isEmpty) return const SizedBox.shrink();
    final (rawMin, rawMax, hasNeg) = _calcRange();
    final interval = _niceInterval(rawMax - rawMin);
    final minY = (rawMin / interval).roundToDouble() * interval;
    final maxY = (rawMax / interval).ceilToDouble() * interval;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 12,
            height: 3,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(widget.valueLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: LayoutBuilder(builder: (ctx, cs) {
            final cw = cs.maxWidth, ch = cs.maxHeight;
            return Stack(clipBehavior: Clip.none, children: [
              LineChart(LineChartData(
                minX: 0,
                maxX: (d.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: _grid(hasNeg, interval),
                borderData: _bd,
                titlesData: _titles(interval, maxY),
                lineTouchData: _td,
                lineBarsData: _bars(hasNeg),
              )),
              if (_selectedIdx != null) _tooltip(cw, ch, minY, maxY),
            ]);
          }),
        ),
      ),
    ]);
  }

  static final _bd = FlBorderData(
    show: true,
    border: const Border(
      bottom: BorderSide(color: Color(0xFFE8E8E8), width: 0.5),
      left: BorderSide(color: Color(0xFFE8E8E8), width: 0.5),
    ),
  );

  FlGridData _grid(bool neg, double iv) => FlGridData(
        drawVerticalLine: false,
        horizontalInterval: iv,
        checkToShowHorizontalLine: (v) => true,
        getDrawingHorizontalLine: (v) => neg && v == 0
            ? const FlLine(color: Color(0xFF999999), strokeWidth: 1)
            : const FlLine(color: Color(0xFFE0E0E0), strokeWidth: 1, dashArray: [4, 4]),
      );

  FlTitlesData _titles(double iv, double maxY) => FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          interval: widget.showAllBottomLabels ? 1 : 2,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= d.length) return const SizedBox.shrink();
            if (!(widget.showAllBottomLabels || i.isEven || d[i].value != 0))
              return const SizedBox.shrink();
            final peak = d[i].value > 0 && (d[i].value / (maxY > 0 ? maxY : 1)) > 0.85;
            return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: peak
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFF333333), borderRadius: BorderRadius.circular(4)),
                        child: Text(d[i].label,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)))
                    : Text(d[i].label,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF999999))));
          },
        )),
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          interval: iv,
          getTitlesWidget: (v, _) => Text(_fmtY(v.abs() < 0.001 ? 0.0 : v),
              style: const TextStyle(fontSize: 9, color: Color(0xFF999999))),
        )),
      );

  LineTouchData get _td => LineTouchData(
        handleBuiltInTouches: false,
        touchSpotThreshold: 20,
        touchCallback: (e, r) {
          if (e is FlTapUpEvent) {
            final s = r?.lineBarSpots?.firstOrNull;
            if (s != null && s.x >= 0 && s.x < d.length) {
              final i = s.x.toInt();
              setState(() => _selectedIdx = _selectedIdx == i ? null : i);
            } else {
              setState(() => _selectedIdx = null);
            }
          }
        },
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => const Color(0xFFF8F9FA),
          tooltipBorder: const BorderSide(color: Color(0xFFD1D5DB), width: 0.5),
          tooltipRoundedRadius: 8,
          getTooltipItems: (s) => s.map((_) => null).toList(),
        ),
        getTouchedSpotIndicator: (_, spots) => spots
            .map((i) => TouchedSpotIndicatorData(
                  FlLine(color: c.withOpacity(0.3), strokeWidth: 1, dashArray: [3, 3]),
                  const FlDotData(show: false),
                ))
            .toList(),
      );

  List<LineChartBarData> _bars(bool neg) => [
        LineChartBarData(
          spots: List.generate(d.length, (i) => FlSpot(i.toDouble(), d[i].value)),
          color: c,
          isCurved: true,
          curveSmoothness: 0.25,
          preventCurveOverShooting: true,
          isStrokeCapRound: true,
          dotData: FlDotData(
              getDotPainter: (_, __, ___, ____) =>
                  FlDotCirclePainter(radius: 3.5, color: c, strokeColor: Colors.transparent)),
          belowBarData: BarAreaData(show: true, color: c.withOpacity(0.04), applyCutOffY: true),
          aboveBarData:
              neg ? BarAreaData(show: true, color: c.withOpacity(0.04), applyCutOffY: true) : null,
        )
      ];

  Widget _tooltip(double cw, double ch, double minY, double maxY) {
    final i = _selectedIdx!;
    final val = d[i].value;
    final tl = (widget.tooltipLabels != null && i < widget.tooltipLabels!.length)
        ? widget.tooltipLabels![i]
        : d[i].label;
    const lp = 52.0, rp = 10.0, bp = 36.0;
    final pw = cw - lp - rp, ph = ch - bp, rng = maxY - minY;
    final x = lp + (i / (d.length - 1).clamp(1, double.infinity)) * pw;
    final y = rng == 0 ? ph / 2 : (1 - (val - minY) / rng) * ph;
    final tip = GestureDetector(
      onTap: () => setState(() => _selectedIdx = null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD1D5DB), width: 0.5),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
            ]),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${val.toStringAsFixed(widget.valueDecimals)}${widget.valueSuffix}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c)),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${widget.valueLabel}  ',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
                Text(tl, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
              ]),
            ]),
      ),
    );
    const tw = 170.0, th = 58.0;
    return Positioned(
      left: (x - tw / 2).clamp(0.0, cw - tw),
      top: y > th + 8 ? y - th - 8 : y + 8,
      child: tip,
    );
  }

  (double, double, bool) _calcRange() {
    double mn = 0, mx = 0;
    for (final v in d) {
      if (v.value > mx) mx = v.value;
      if (v.value < mn) mn = v.value;
    }
    if (mx == 0 && mn == 0) return (0, 1, false);
    final amn = mn.abs(), amx = mx.abs(), ma = amn > amx ? amn : amx;
    return (
      mn - (amn * 0.25).clamp(ma * 0.05, double.infinity),
      mx + (amx * 0.25).clamp(ma * 0.05, double.infinity),
      mn < 0
    );
  }

  double _niceInterval(double r) {
    if (r <= 0) return 1;
    final m = pow(10, (log(r / 6) / ln10).floor().toDouble());
    final n = (r / 6) / m;
    final double k = n <= 1.5
        ? 1
        : n <= 3
            ? 2
            : n <= 7
                ? 5
                : 10;
    return k * m;
  }

  String _fmtY(double v) {
    final a = v.abs();
    if (a >= 10000) return '${(v / 10000).toStringAsFixed(1)}w';
    if (a >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toInt().toString();
  }
}
