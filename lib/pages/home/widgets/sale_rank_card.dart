import 'package:flutter/material.dart';

import 'card_menu.dart';

/// 销售排行榜卡片（分类销售榜 / 单品销售榜）
class SaleRankCard extends StatelessWidget {
  const SaleRankCard({
    super.key,
    required this.rankList,
    required this.rankType,
    required this.rankSort,
    required this.fmt,
    required this.onRankTypeChanged,
    required this.onRankSortChanged,
    required this.onCardPin,
    required this.onCardHide,
    required this.onCardManage,
  });
  final List<Map<String, dynamic>> rankList;
  final String rankType;
  final int rankSort;
  final String Function(dynamic) fmt;
  final ValueChanged<String> onRankTypeChanged;
  final ValueChanged<int> onRankSortChanged;
  final VoidCallback onCardPin;
  final VoidCallback onCardHide;
  final VoidCallback onCardManage;

  static const _rankColors = [
    Color(0xFFFF5237),
    Color(0xFFFF9900),
    Color(0xFFFFCC00),
  ];

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
              _RankTab('分类销售榜', 'SaleType', rankType, onRankTypeChanged),
              const SizedBox(width: 20),
              _RankTab('单品销售榜', 'SaleProd', rankType, onRankTypeChanged),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => onRankSortChanged(rankSort == 0 ? 1 : 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFD1D5DB)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      rankSort == 0 ? '按销售金额' : '按销售数量',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.swap_vert, size: 14, color: Color(0xFF666666)),
                  ]),
                ),
              ),
              const Spacer(),
              CardMenu(
                  fieldId: 'xsb', onPin: onCardPin, onHide: onCardHide, onManage: onCardManage),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
            ),
            child: Row(
              children: [
                const SizedBox(
                    width: 50,
                    child: Text('排名', style: TextStyle(fontSize: 12, color: Color(0xFF656565)))),
                Expanded(
                  child: Text(
                    rankType == 'SaleType' ? '分类名称' : '商品名称',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF656565)),
                  ),
                ),
                const SizedBox(
                    width: 70,
                    child: Text('销售数量',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, color: Color(0xFF656565)))),
                const SizedBox(
                    width: 80,
                    child: Text('销售金额',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, color: Color(0xFF656565)))),
              ],
            ),
          ),
          if (rankList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
              ),
            )
          else
            ...rankList.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value;
              final rank = idx + 1;
              return _RankRow(
                rank: rank,
                name: (item['typename'] ?? item['productname'])?.toString() ?? '',
                qty: double.tryParse(item['qty']?.toString() ?? '0') ?? 0,
                amount: double.tryParse(item['rramt']?.toString() ?? '0') ?? 0,
                fmt: fmt,
              );
            }),
        ],
      ),
    );
  }
}

class _RankTab extends StatelessWidget {
  const _RankTab(this.label, this.value, this.selected, this.onTap);
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

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.name,
    required this.qty,
    required this.amount,
    required this.fmt,
  });
  final int rank;
  final String name;
  final double qty;
  final double amount;
  final String Function(dynamic) fmt;

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isTop3 ? SaleRankCard._rankColors[rank - 1] : const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text('$rank',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isTop3 ? Colors.white : const Color(0xFF404040))),
              ),
            ),
          ),
          Expanded(
            child: Text(name,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 70,
            child: Text(fmt(qty),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
          SizedBox(
            width: 80,
            child: Text('¥${fmt(amount)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
          ),
        ],
      ),
    );
  }
}
