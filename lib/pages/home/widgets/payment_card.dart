import 'package:flutter/material.dart';

import 'card_menu.dart';

/// 付款方式卡片
class PaymentCard extends StatelessWidget {
  const PaymentCard({
    super.key,
    required this.payList,
    required this.fmt,
    required this.onCardPin,
    required this.onCardHide,
    required this.onCardManage,
  });
  final List<Map<String, dynamic>> payList;
  final String Function(dynamic) fmt;
  final VoidCallback onCardPin;
  final VoidCallback onCardHide;
  final VoidCallback onCardManage;

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
              const Expanded(
                child: Text(
                  '付款方式',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              CardMenu(
                  fieldId: 'fkfs', onPin: onCardPin, onHide: onCardHide, onManage: onCardManage),
            ],
          ),
          const SizedBox(height: 16),
          if (payList.isEmpty)
            _buildEmptyState()
          else
            ...payList.take(5).map((item) => _PayRow(item: item, fmt: fmt)),
        ],
      ),
    );
  }

  static Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 24, color: Color(0xFFCCCCCC)),
            SizedBox(height: 8),
            Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          ],
        ),
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow({required this.item, required this.fmt});
  final Map<String, dynamic> item;
  final String Function(dynamic) fmt;

  @override
  Widget build(BuildContext context) {
    final proportion = double.tryParse(item['proportion']?.toString() ?? '0') ?? 0;
    final payamt = double.tryParse(item['payamt']?.toString() ?? '0') ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  item['payname']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '¥ ${fmt(payamt)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${fmt(proportion)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF9B9B9B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: const Color(0xFFF0F0F0),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth * (proportion / 100).clamp(0.0, 1.0);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: const Color(0xFF6EA8FE),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
