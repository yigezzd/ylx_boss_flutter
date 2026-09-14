import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/analysis_chart.dart';
import 'package:sp_util/sp_util.dart';

/// 商品详情页
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\businessAnalysis\subpage\spfx\spfxBubpage\spBill.vue
class SpBillPage extends StatefulWidget {
  const SpBillPage({
    super.key,
    required this.productData,
    required this.sids,
    required this.startTime,
    required this.endTime,
    this.timeIndex = 1,
  });
  final Map<String, dynamic> productData;
  final List<int> sids;
  final String startTime;
  final String endTime;
  final int timeIndex;

  @override
  State<SpBillPage> createState() => _SpBillPageState();
}

class _SpBillPageState extends State<SpBillPage> {
  Map<String, dynamic> _info = {};
  List<Map<String, dynamic>> _chartData = [];

  bool _loading = true;
  String _listType = 'rramt';
  String _operStr = '按销售金额';
  int _checkstockflag = 1;
  int _inpriceflag = 1;

  @override
  void initState() {
    super.initState();
    _info = widget.productData;
    _loadCheckStockFlag();
    _fetchInfo();
  }

  /// 从用户信息读取库存/进价查看权限（对齐 enter_unsold_page.dart）
  void _loadCheckStockFlag() {
    try {
      final userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final u = jsonDecode(userStr) as Map<String, dynamic>;
        _checkstockflag = int.tryParse(u['checkstockflag']?.toString() ?? '1') ?? 1;
        _inpriceflag = int.tryParse(u['inpriceflag']?.toString() ?? '1') ?? 1;
      }
    } catch (_) {}
  }

  Future<void> _fetchInfo() async {
    try {
      // 对齐 Vue spBill.vue：图表与接口固定最近 7 天（今天往前 6 天 ~ 今天）
      final now = DateTime.now();
      final weekStart = now.subtract(const Duration(days: 6));
      String fmtDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final r = await request(HttpApi.bossJyfxGetSpfxInfo, {
        'is_page': 0,
        'productid': _info['productid']?.toString() ?? '',
        'starttime': '${fmtDate(weekStart)} 00:00:00',
        'endtime': '${fmtDate(now)} 23:59:59',
        'sids': widget.sids,
      });
      if (!mounted) return;
      final data = r['data'];
      if (data is Map<String, dynamic>) {
        final list = (data['list'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final pi = data['productinfo'];
        if (pi is Map<String, dynamic>) _info = pi;
        setState(() {
          _chartData = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 默认商品图（商品图片为空时展示）
  static const String _defaultProductImage =
      'https://byyoupic.oss-cn-shenzhen.aliyuncs.com/bycloud/zm/null/pro_489f220f8080097467ea9f952df40cca.png';

  static String _fmt(int digits, dynamic v) {
    final n = v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
    return n.toStringAsFixed(digits);
  }

  void _showTypePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height / 3,
        decoration: const BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: SafeArea(
            child: Column(children: [
          SizedBox(
              height: 50,
              child: Row(children: [
                const SizedBox(width: 48),
                const Expanded(
                    child: Text('选择类型',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
                SizedBox(
                    width: 48,
                    child: Center(
                        child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280))))),
              ])),
          const Divider(height: 1),
          _buildTypeOpt(ctx, 'rramt', '按销售金额'),
          _buildTypeOpt(ctx, 'qty', '按销售数量'),
        ])),
      ),
    );
  }

  Widget _buildTypeOpt(BuildContext ctx, String val, String label) {
    final sel = _listType == val;
    return ListTile(
      title: Text(label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: sel ? const Color(0xFF006EFF) : const Color(0xFF333333))),
      trailing: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: sel ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB), width: 2)),
          child: sel
              ? Center(
                  child: Container(
                      width: 10,
                      height: 10,
                      decoration:
                          const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF006EFF))))
              : null),
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          _listType = val;
          _operStr = label;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _info['name']?.toString() ?? '';
    final size = _info['size']?.toString() ?? '';
    final barcode = _info['barcode']?.toString() ?? '';
    final unit = _info['unit']?.toString() ?? '';
    final typename = _info['typename']?.toString() ?? '';
    final supname = _info['supname']?.toString() ?? '';
    final brandname = _info['brandname']?.toString() ?? '';
    final home = _info['home']?.toString() ?? '';

    // 商品图片：优先接口返回的 imageurl，为空时使用默认商品图
    final imagePath = _info['imageurl']?.toString() ??
        _info['imgurl']?.toString() ??
        _info['pic']?.toString() ??
        '';
    final imageUrl = imagePath.isEmpty
        ? _defaultProductImage
        : (imagePath.startsWith('http://') || imagePath.startsWith('https://')
            ? imagePath
            : '${Constant.imageBaseUrl}/$imagePath');

    final dp = analysisChartData;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
          title: const Text('商品详情', style: TextStyle(fontSize: 17)),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF333333),
          elevation: 0.5),
      body: Stack(children: [
        SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 商品信息卡片
          Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 5))
                  ]),
              child: Row(children: [
                Container(
                    width: 75,
                    height: 75,
                    decoration: BoxDecoration(
                        color: const Color(0xFFF1F1F1), borderRadius: BorderRadius.circular(4)),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          imageUrl,
                          width: 75,
                          height: 75,
                          fit: BoxFit.cover,
                          cacheWidth: 150,
                          cacheHeight: 150,
                          errorBuilder: (_, __, ___) => const Center(
                              child:
                                  Icon(Icons.image_outlined, size: 28, color: Color(0xFFD1D5DB))),
                        ))),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$name${size.isNotEmpty ? ' ($size)' : ''}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF333333))),
                  const SizedBox(height: 4),
                  Text(barcode, style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A))),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                        child: Text('单位：$unit',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A)))),
                    Expanded(
                        child: Text('分类：$typename',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A)))),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                        child: Text('货商：$supname',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A)))),
                    Expanded(
                        child: Text('品牌：$brandname',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A)))),
                  ]),
                  const SizedBox(height: 2),
                  Text('产地：$home', style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A))),
                ])),
              ])),
          // 指标卡片
          Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: _buildMetricCard(
                          '商品进价', _inpriceflag == 1 ? _fmt(3, _info['inprice']) : '****')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('零售价', _fmt(3, _info['sellprice']))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('会员价1', _fmt(3, _info['mprice1']))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _buildMetricCard('批发价1', _fmt(3, _info['pfprice1']))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _buildMetricCard(
                          '库存数量', _checkstockflag == 1 ? _fmt(1, _info['stockqty']) : '****')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _buildMetricCard(
                          '库存金额',
                          _checkstockflag == 1
                              ? _fmt(
                                  3,
                                  (num.tryParse(_info['stockqty']?.toString() ?? '0') ?? 0) *
                                      (num.tryParse(_info['inprice']?.toString() ?? '0') ?? 0))
                              : '****')),
                ]),
              ])),
          // 图表
          Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration:
                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(
                      child: Text('最近一周销售概况',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333)))),
                  GestureDetector(
                      onTap: _showTypePicker,
                      child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFDEDEDE)),
                              borderRadius: BorderRadius.circular(5)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_operStr,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF333333))),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                          ]))),
                ]),
                const SizedBox(height: 8),
                if (dp.isNotEmpty)
                  AspectRatio(
                      aspectRatio: 1.6,
                      child: AnalysisChart(
                          data: dp,
                          valueLabel: _operStr.replaceAll('按销售', ''),
                          valueDecimals: _listType == 'qty' ? 1 : 3,
                          showAllBottomLabels: true)),
              ])),
        ])),
        // 加载提示：仅居中图标卡片，无全屏遮罩（避免加载中页面泛白如白屏）
        if (_loading)
          const Positioned.fill(
            child: Center(
              child: SizedBox(
                width: 72,
                height: 72,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    border: Border.fromBorderSide(BorderSide(color: Color(0xFFE1E9F3))),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  List<({String label, double value})> get analysisChartData {
    // 对齐 Vue spBill.vue：只显示最近一周（今天往前 6 天 ~ 今天，共 7 天）
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 6));
    final end = now;
    final apiMap = <String, double>{};
    for (final e in _chartData) {
      final date = (e['billdate']?.toString() ?? '').replaceAll(RegExp(r'^\d{4}-'), '');
      apiMap[date] = (num.tryParse(e[_listType]?.toString() ?? '0') ?? 0).toDouble();
    }
    final result = <({String label, double value})>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final label = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      result.add((label: label, value: apiMap[label] ?? 0.0));
    }
    return result;
  }

  Widget _buildMetricCard(String label, String value) {
    return Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFDEDEDE)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))
            ]),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A))),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        ]));
  }
}
