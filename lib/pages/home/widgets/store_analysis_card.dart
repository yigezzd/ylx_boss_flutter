import 'package:flutter/material.dart';

import 'card_menu.dart';

/// 门店分析卡片（对齐 Vue pages/index/child/storeAnalysis.vue）
///
/// 数据在首页统一请求并按 Vue 规则计算好（金额/毛利率/占比均保留两位小数，
/// 末行为接口 sumdata 组成的合计行），本组件只负责展示。
class StoreAnalysisCard extends StatelessWidget {
  const StoreAnalysisCard({
    super.key,
    required this.rows,
    required this.onCardPin,
    required this.onCardHide,
    required this.onCardManage,
  });

  /// 表格行：storename / saleamt / grossamt / grossrate / ratio（均已格式化）
  final List<Map<String, dynamic>> rows;
  final VoidCallback onCardPin;
  final VoidCallback onCardHide;
  final VoidCallback onCardManage;

  static const List<String> _labels = ['门店', '销售金额', '销售毛利', '毛利率(%)', '销售占比(%)'];

  /// 列占比：销售占比列适当加宽，避免表头“销售占比(%)”被截断
  static const List<double> _colRatios = [0.26, 0.19, 0.19, 0.16, 0.20];

  /// 列宽整体放大 1/3（总宽大于容器，表格横向滚动，避免列太窄文字挤压）
  static const double _colScale = 4 / 3;

  /// 表格区域固定高度（对齐 Vue tableH = 350）
  static const double _tableHeight = 350;

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
              const Text(
                '门店分析',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
              ),
              const Spacer(),
              CardMenu(
                fieldId: 'mdfx',
                onPin: onCardPin,
                onHide: onCardHide,
                onManage: onCardManage,
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final double tableWidth = constraints.maxWidth * _colScale;
              final List<double> widths = [for (final r in _colRatios) tableWidth * r];
              return SizedBox(
                height: _tableHeight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        _StoreAnalysisHeader(widths: widths, labels: _labels),
                        Expanded(
                          child: rows.isEmpty
                              ? const Center(
                                  child: Text(
                                    '暂无数据',
                                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                                  ),
                                )
                              : ListView.builder(
                                  cacheExtent: 800,
                                  padding: EdgeInsets.zero,
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) => RepaintBoundary(
                                    child: _StoreAnalysisRow(
                                      row: rows[index],
                                      widths: widths,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 表头行
class _StoreAnalysisHeader extends StatelessWidget {
  const _StoreAnalysisHeader({required this.widths, required this.labels});

  final List<double> widths;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FA),
        border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  labels[i],
                  textAlign: i == 0 ? TextAlign.center : TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 数据行（含合计行，合计行由首页按 sumdata 生成）
class _StoreAnalysisRow extends StatelessWidget {
  const _StoreAnalysisRow({required this.row, required this.widths});

  final Map<String, dynamic> row;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final bool isTotal = row['storename']?.toString() == '合计';
    final TextStyle textStyle = TextStyle(
      fontSize: 12,
      color: const Color(0xFF333333),
      fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
    );
    final List<String> values = [
      row['storename']?.toString() ?? '',
      row['saleamt']?.toString() ?? '',
      row['grossamt']?.toString() ?? '',
      row['grossrate']?.toString() ?? '',
      row['ratio']?.toString() ?? '',
    ];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isTotal ? const Color(0xFFFAFBFC) : Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          for (int i = 0; i < values.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  values[i],
                  textAlign: i == 0 ? TextAlign.center : TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
