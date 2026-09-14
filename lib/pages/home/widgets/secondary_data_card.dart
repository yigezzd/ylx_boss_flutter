import 'package:flutter/material.dart';

/// 二级数据卡片（白色 — 6 项经营指标）
class SecondaryDataCard extends StatelessWidget {
  const SecondaryDataCard({
    super.key,
    required this.overview,
    required this.dayTypeName,
    required this.fmt,
    required this.fmtRate,
    required this.rateColor,
    required this.isWholesale,
    required this.myType,
  });
  final Map<String, dynamic> overview;
  final String dayTypeName;
  final String Function(dynamic) fmt;
  final String Function(dynamic) fmtRate;
  final Color Function(dynamic) rateColor;
  final bool isWholesale;
  final String myType;

  @override
  Widget build(BuildContext context) {
    final items = isWholesale
        ? [
            _MetricItem('订货金额', overview['orderAmount'], overview['orderAmountRate']),
            _MetricItem('销售金额', overview['saleAmount'], overview['saleAmountRate']),
            _MetricItem('预收订金', overview['advanceDeposit'], overview['advanceDepositRate']),
            _MetricItem('收款金额', overview['advanceDeposit'], overview['advanceDepositRate']),
            _MetricItem('销售收款', overview['receivedAmount'], overview['receivedAmountRate']),
            _MetricItem('销售退款', overview['refundAmount'], overview['refundAmountRate']),
          ]
        : myType == '1'
            ? [
                _MetricItem('充值金额', overview['vipaddamt'], overview['vipaddamtrate']),
                _MetricItem('赠送金额', overview['vipgiveamt'], overview['vipgiveamtrate']),
                _MetricItem('售卡金额', overview['vipcardsaleamt'], overview['vipcardsaleamtrate']),
                _MetricItem('储卡消费', overview['vipasaleamt'], overview['vipasaleamtrate']),
                _MetricItem('新增会员', overview['vipcardnum'], overview['vipcardnumrate']),
                _MetricItem('会员客流', overview['vipbillnum'], overview['vipbillnumrate']),
              ]
            : [
                _MetricItem('营业额', overview['saleamt'], overview['saleamtrate']),
                _MetricItem('退款金额', overview['returnamt'], overview['returnamtrate']),
                _MetricItem('毛利率', overview['gross'], overview['grossrate']),
                _MetricItem('客单数', overview['billnum'], overview['billnumrate']),
                _MetricItem('客单价', overview['billprice'], overview['billpricerate']),
                _MetricItem('毛利额', overview['profitamt'], overview['profitamtrate']),
              ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(children: [
            for (int row = 0; row < 2; row++) ...[
              Row(
                children: [
                  for (int col = 0; col < 3; col++)
                    Expanded(
                      child: _MetricCell(
                        item: items[row * 3 + col],
                        dayTypeName: dayTypeName,
                        fmt: fmt,
                        fmtRate: fmtRate,
                        rateColor: rateColor,
                        showBorder: col < 2,
                      ),
                    ),
                ],
              ),
              if (row == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    height: 1,
                    color: const Color(0xFFF0F0F0),
                  ),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _MetricItem {
  const _MetricItem(this.title, this.value, this.rate);
  final String title;
  final dynamic value;
  final dynamic rate;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.item,
    required this.dayTypeName,
    required this.fmt,
    required this.fmtRate,
    required this.rateColor,
    this.showBorder = false,
  });
  final _MetricItem item;
  final String dayTypeName;
  final String Function(dynamic) fmt;
  final String Function(dynamic) fmtRate;
  final Color Function(dynamic) rateColor;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: showBorder
          ? const BoxDecoration(
              border: Border(
                right: BorderSide(color: Color(0xFFEEEEEE)),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
          ),
          const SizedBox(height: 6),
          Text(
            fmt(item.value),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$dayTypeName环比 ',
                style: const TextStyle(fontSize: 10, color: Color(0xFF7A7A7A)),
              ),
              Text(
                fmtRate(item.rate),
                style: TextStyle(
                  fontSize: 10,
                  color: rateColor(item.rate),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
