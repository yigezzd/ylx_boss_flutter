import 'package:flutter/material.dart';
import 'package:flutter_deer/util/math_utils.dart';

/// billflag → 单据类型名称（对齐 Vue wms/launch 映射）
String launchBillTypeLabel(dynamic billflag) {
  switch (billflag?.toString()) {
    case '1':
      return '采购入库';
    case '2':
      return '批发退货';
    case '3':
      return '调拨入库';
    case '4':
      return '配退收货';
  }
  return '';
}

/// billflag → 来源类型名称（对齐 Vue wms/launch 映射）
String launchBillSourceLabel(dynamic billflag) {
  switch (billflag?.toString()) {
    case '1':
      return '供应商';
    case '2':
      return '客户';
    case '3':
    case '4':
      return '门店';
  }
  return '';
}

/// 按单据列表卡片（对齐 Vue launch/index.vue 按单据卡片）
class LaunchBillCard extends StatelessWidget {
  const LaunchBillCard({super.key, required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String source = launchBillSourceLabel(item['billflag']);
    final String showname = item['showname']?.toString() ?? '-';
    final String billno = item['billno']?.toString() ?? '-';
    final String createname = item['createname']?.toString() ?? '-';
    final String createtime = item['createtime']?.toString() ?? '-';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    source.isEmpty ? showname : '$source：$showname',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  launchBillTypeLabel(item['billflag']),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '单号：$billno',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    '制单人：$createname',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            Container(
              height: 1,
              color: const Color(0xFFEBEBEB),
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),
            Text(
              '制单时间：$createtime',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 按商品列表卡片（对齐 Vue launch/index.vue 按商品卡片）
class LaunchProCard extends StatelessWidget {
  const LaunchProCard({super.key, required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = item['productname']?.toString() ?? '-';
    final String size = item['size']?.toString() ?? '';
    final String billno = item['billno']?.toString() ?? '-';
    final String qty = MathUtils.formatDecimal(1, item['billqty'] ?? item['qty'] ?? 0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    size.isEmpty ? name : '$name（$size）',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  launchBillTypeLabel(item['billflag']),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '单号：$billno',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '待上架数：$qty',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
