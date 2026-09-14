import 'package:flutter/material.dart';
import 'package:flutter_deer/widgets/analysis_chart.dart';

import 'card_menu.dart';

/// 营业趋势卡片
class TrendCard extends StatelessWidget {
  const TrendCard({
    super.key,
    required this.trendList,
    required this.daytype,
    required this.trendType,
    required this.onTrendTypeChanged,
    required this.onCardPin,
    required this.onCardHide,
    required this.onCardManage,
  });
  final List<Map<String, dynamic>> trendList;
  final String daytype;
  final String trendType;
  final ValueChanged<String> onTrendTypeChanged;
  final VoidCallback onCardPin;
  final VoidCallback onCardHide;
  final VoidCallback onCardManage;

  // daytype 映射: 1=今日, 2=昨天, 3=本周, 4=本月, 5=上月
  int get _selectdatetype => (daytype == '1' || daytype == '2') ? 1 : 3;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TrendTab('营业额趋势', 'rramt', trendType, onTrendTypeChanged),
              const SizedBox(width: 20),
              _TrendTab('客流量趋势', 'billnum', trendType, onTrendTypeChanged),
              const Spacer(),
              CardMenu(fieldId: 'qs', onPin: onCardPin, onHide: onCardHide, onManage: onCardManage),
            ],
          ),
          const SizedBox(height: 16),
          if (_chartData.isEmpty)
            Container(
              height: 180,
              alignment: Alignment.center,
              child: const Text(
                '暂无趋势数据',
                style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              ),
            )
          else
            Expanded(
              child: AnalysisChart(
                data: _chartData,
                valueLabel: trendType == 'rramt' ? '营业额' : '客流量',
                showAllBottomLabels: _selectdatetype == 1 || daytype == '3',
                tooltipLabels: _chartTooltipLabels,
                valueDecimals: 2,
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 图表数据构建 ====================

  /// X 轴标签（短格式）—— 对齐 Vue totalChart.vue chartInit()
  List<({String label, double value})> get _chartData {
    final sorted = List<Map<String, dynamic>>.from(trendList)
      ..sort((a, b) {
        final ia = int.tryParse(a['isort']?.toString() ?? '0') ?? 0;
        final ib = int.tryParse(b['isort']?.toString() ?? '0') ?? 0;
        return ia.compareTo(ib);
      });

    // 按天（昨日/今日）：isort = 0~23 → 小时
    if (_selectdatetype == 1) {
      final data = List<double>.filled(24, 0);
      for (final row in sorted) {
        final idx = int.tryParse(row['isort']?.toString() ?? '') ?? 0;
        if (idx >= 0 && idx < 24) {
          data[idx] = double.tryParse(row[trendType]?.toString() ?? '0') ?? 0;
        }
      }
      return List.generate(24, (h) => (label: '$h', value: data[h]));
    }

    // 本周：isort = 1~7 → 周一~周日
    if (daytype == '3') {
      const weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final data = List<double>.filled(7, 0);
      for (final row in sorted) {
        final idx = (int.tryParse(row['isort']?.toString() ?? '') ?? 1) - 1;
        if (idx >= 0 && idx < 7) {
          data[idx] = double.tryParse(row[trendType]?.toString() ?? '0') ?? 0;
        }
      }
      return List.generate(7, (i) => (label: weekLabels[i], value: data[i]));
    }

    // 本月 / 上月：isort = 1~N → 日
    final maxDay = daytype == '4'
        ? DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day
        : DateTime(DateTime.now().year, DateTime.now().month, 0).day;
    final data = List<double>.filled(maxDay, 0);
    for (final row in sorted) {
      final idx = (int.tryParse(row['isort']?.toString() ?? '') ?? 1) - 1;
      if (idx >= 0 && idx < maxDay) {
        data[idx] = double.tryParse(row[trendType]?.toString() ?? '0') ?? 0;
      }
    }
    return List.generate(maxDay, (i) => (label: '${i + 1}', value: data[i]));
  }

  /// Tooltip 标签（长格式）
  List<String> get _chartTooltipLabels {
    if (_selectdatetype == 1) {
      final datePrefix =
          '${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      return List.generate(24, (h) => '$datePrefix ${h.toString().padLeft(2, '0')}:00');
    }
    return _chartData.map((d) => d.label).toList();
  }
}

class _TrendTab extends StatelessWidget {
  const _TrendTab(this.label, this.value, this.selected, this.onTap);
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF416EFD) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: isActive ? 15 : 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? const Color(0xFF1A1A2E) : const Color(0xFF6A6A6A),
          ),
        ),
      ),
    );
  }
}
