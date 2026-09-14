import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 收银流水 - 单据详情页
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\cashFlow\bill.vue
class CashFlowBillPage extends StatefulWidget {
  const CashFlowBillPage({super.key, required this.saleid, required this.sid});
  final String saleid;
  final String sid;

  @override
  State<CashFlowBillPage> createState() => _CashFlowBillPageState();
}

class _CashFlowBillPageState extends State<CashFlowBillPage> {
  bool _loading = true;
  Map<String, dynamic> _master = {};
  List<Map<String, dynamic>> _detailList = [];
  List<Map<String, dynamic>> _paywayList = [];

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  /// 格式化数值，保留指定小数位
  /// col 含义对齐 Vue formatDecimal: 1-数量 2-单价 3-金额
  static String _fmt(int col, dynamic value) {
    final num v = value is num ? value : (num.tryParse(value?.toString() ?? '0') ?? 0);
    // col: 1=数量 → 保留1位小数; 2=单价/抹零 → 保留2位; 3=金额 → 保留2位
    int digits;
    switch (col) {
      case 1:
        digits = 1;
        break;
      case 2:
      case 3:
      default:
        digits = 2;
        break;
    }
    return v.toStringAsFixed(digits);
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    return request(
            HttpApi.saleFindSaleFlowDeail,
            {
              'saleid': widget.saleid,
              'sid': widget.sid,
            },
            false,
            false)
        .then((result) {
          if (!mounted) return;
          final data = result['data'];
          if (data is Map<String, dynamic>) {
            setState(() {
              _master = data['saleMaster'] is Map<String, dynamic>
                  ? data['saleMaster'] as Map<String, dynamic>
                  : {};
              _detailList = (data['saleDetailList'] is List)
                  ? (data['saleDetailList'] as List).cast<Map<String, dynamic>>()
                  : [];
              _paywayList = (data['salePaywayList'] is List)
                  ? (data['salePaywayList'] as List).cast<Map<String, dynamic>>()
                  : [];
            });
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('收银流水详情', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
            )
          : RefreshIndicator(
              color: const Color(0xFF006EFF),
              onRefresh: _loadDetail,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 12),
                  _buildProductCard(),
                  const SizedBox(height: 12),
                  _buildSummaryCard(),
                  const SizedBox(height: 12),
                  _buildPaymentCard(),
                ],
              ),
            ),
    );
  }

  // ==================== 头部信息卡片 ====================
  Widget _buildHeaderCard() {
    return _Card(
      children: [
        // 单号
        _CardRow(
          left: Text(
            '单号：${_master['billno'] ?? '--'}',
            style: const TextStyle(fontSize: 15, color: Color(0xFF111827)),
          ),
        ),
        const SizedBox(height: 10),
        // 结算时间
        _CardRow(
          left: Text(
            '结算时间：${_master['billdate'] ?? '--'}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
          ),
        ),
        const SizedBox(height: 8),
        // 会员信息 + 机号
        Row(
          children: [
            Expanded(
              child: Text(
                _buildVipInfo(),
                style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '机号：${_master['machno'] ?? ''}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 收银员
        _CardRow(
          left: Text(
            '收银员：${_master['cashname'] ?? ''}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
          ),
        ),
        const SizedBox(height: 8),
        // 备注
        _CardRow(
          left: Text(
            '备注：${_master['memo'] ?? ''}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
          ),
        ),
      ],
    );
  }

  String _buildVipInfo() {
    final vipname = _master['vipname']?.toString() ?? '';
    final vipno = _master['vipno']?.toString() ?? '';
    if (vipname.isEmpty && vipno.isEmpty) return '会员信息：';
    final noStr = vipno.isNotEmpty ? '（$vipno）' : '';
    return '会员信息：$vipname$noStr';
  }

  // ==================== 商品明细 ====================
  Widget _buildProductCard() {
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      children: [
        const Text('商品明细',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        if (_detailList.isEmpty) ...[
          const SizedBox(height: 20),
          const Center(
            child: Text('暂无商品明细', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          ),
        ] else
          ..._detailList.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return _buildProductItem(item, i == _detailList.length - 1);
          }),
      ],
    );
  }

  Widget _buildProductItem(Map<String, dynamic> item, bool isLast) {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE8E8E8)),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 商品名称 + 金额
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item['productname']?.toString() ?? '--',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '￥${_fmt(3, item['rramt'] ?? 0)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 编码 | 单价 | 数量
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      item['productcode']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '单价：￥${_fmt(2, item['rrprice'] ?? 0)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'X${_fmt(1, item['qty'] ?? 0)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                    ),
                  ),
                ],
              ),
              // 营业员
              if ((item['salesname']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '营业员：${item['salesname'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                ),
              ],
            ],
          ),
        ),
        if (!isLast) const SizedBox(height: 8),
      ],
    );
  }

  // ==================== 合计信息 ====================
  Widget _buildSummaryCard() {
    return _Card(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '合计数量：${_fmt(1, _master['qty'] ?? 0)}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
            ),
            Text(
              '合计金额：${_fmt(3, _master['amt'] ?? 0)}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '抹零金额：${_fmt(2, _master['roundamt'] ?? 0)}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
            ),
            Text(
              '优惠金额：${_fmt(3, _master['discountamt'] ?? 0)}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== 支付方式 ====================
  Widget _buildPaymentCard() {
    return _Card(
      children: [
        // 实收金额
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('实收金额：',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF111827))),
            Text(
              '￥${_fmt(3, _master['amt'] ?? 0)}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFE02020)),
            ),
          ],
        ),
        const Divider(height: 24, color: Color(0xFFE2E2E2)),
        // 支付方式列表
        const Text('支付方式：', style: TextStyle(fontSize: 14, color: Color(0xFF111827))),
        const SizedBox(height: 8),
        if (_paywayList.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Center(
              child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
            ),
          )
        else
          ..._paywayList.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${item['payname'] ?? '--'}：￥${_fmt(3, item['payamt'] ?? 0)}',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                ),
              )),
      ],
    );
  }
}

// ==================== 通用卡片容器 ====================
class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = const EdgeInsets.all(14)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.left, this.right});
  final Widget left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: left),
        if (right != null) right!,
      ],
    );
  }
}
