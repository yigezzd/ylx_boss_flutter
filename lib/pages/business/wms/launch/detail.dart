import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/launch/common.dart';
import 'package:flutter_deer/pages/business/wms/launch/edit.dart';
import 'package:flutter_deer/util/math_utils.dart';

/// WMS 上架单据明细页（对齐 Vue wms/launch/detail.vue）
class WmsLaunchDetailPage extends StatefulWidget {
  const WmsLaunchDetailPage({super.key, required this.billInfo});

  /// 单据基础信息（billid/billflag/showname/billno/createname/createtime/bsid）
  final Map<String, dynamic> billInfo;

  @override
  State<WmsLaunchDetailPage> createState() => _WmsLaunchDetailPageState();
}

class _WmsLaunchDetailPageState extends State<WmsLaunchDetailPage> {
  bool _loading = true;

  late Map<String, dynamic> _billInfo;
  final List<Map<String, dynamic>> _detailList = [];
  final List<Map<String, dynamic>> _mergeDetails = [];

  @override
  void initState() {
    super.initState();
    _billInfo = Map<String, dynamic>.from(widget.billInfo);
    _loadDetail();
  }

  /// 根据 billflag 决定调用哪个详情接口（对齐 Vue getApiConfig）
  (String, Map<String, dynamic>)? _apiConfig() {
    final String billid = _billInfo['billid']?.toString() ?? '';
    switch (_billInfo['billflag']?.toString()) {
      case '1': // 采购入库
        return (
          HttpApi.purchaseInstoreGetInfo,
          {'billid': billid, 'billtype': 1, 'MergeDetailsflag': 1, 'onlyShelfflag': 1}
        );
      case '2': // 批发退货
        return (
          HttpApi.pfSellGetInfo,
          {'billid': billid, 'MergeDetailsflag': 1, 'onlyShelfflag': 1}
        );
      case '3': // 调拨入库
        return (
          HttpApi.dbStockOutGetInfo,
          {'billid': billid, 'billtype': 2, 'MergeDetailsflag': 1, 'onlyShelfflag': 1}
        );
      case '4': // 配退收货
        return (
          HttpApi.psrefundinGetInfo,
          {'billid': billid, 'MergeDetailsflag': 1, 'onlyShelfflag': 1}
        );
    }
    return null;
  }

  Future<void> _loadDetail() async {
    final String billflag = _billInfo['billflag']?.toString() ?? '';
    final String billid = _billInfo['billid']?.toString() ?? '';
    if (billflag.isEmpty || billid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final config = _apiConfig();
    if (config == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final result = await request(config.$1, config.$2);
      if (!mounted) return;
      final res = result['data'];
      if (res is Map<String, dynamic>) {
        // 对齐 Vue：billInfo = {...res, ...billInfo}（路由参数优先）
        _billInfo = <String, dynamic>{...res, ..._billInfo};

        final String billno = _billInfo['billno']?.toString() ?? '';

        _detailList
          ..clear()
          ..addAll((res['detaillist'] as List? ?? []).whereType<Map<String, dynamic>>().map((item) {
            item['billflag'] = billflag;
            item['billid'] = billid;
            item['lunchqty'] = item['billqty'] ?? item['qty'];
            // 对齐 Vue index.vue scanTrayFn: detail.billno = item.billno
            if (item['billno'] == null || item['billno'].toString().isEmpty) {
              item['billno'] = billno;
            }
            return item;
          }));

        _mergeDetails
          ..clear()
          ..addAll(
              (res['mergeDetails'] as List? ?? []).whereType<Map<String, dynamic>>().map((item) {
            item['billflag'] = billflag;
            item['billid'] = billid;
            item['lunchqty'] = item['billqty'] ?? item['qty'];
            // mergeDetails 按商品聚合，从父单据注入 billno
            if (item['billno'] == null || item['billno'].toString().isEmpty) {
              item['billno'] = billno;
            }
            return item;
          }));

        double sum = 0;
        for (final item in _detailList) {
          sum = MathUtils.add(sum, _num(item['billqty'] ?? item['qty']));
        }
        _billInfo['sumlunchqty'] = sum;
      }
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 点击商品 → 上架执行页（对齐 Vue goEdit）
  Future<void> _goEdit(Map<String, dynamic> item) async {
    // 从 detailList 中找出 palletcode 相同的原始明细数据传递给 edit 页面
    final String palletcode = item['palletcode']?.toString() ?? '';
    final samePalletItems = palletcode.isNotEmpty
        ? _detailList.where((c) => c['palletcode']?.toString() == palletcode).toList()
        : <Map<String, dynamic>>[item];
    final mergeItem = palletcode.isNotEmpty
        ? _mergeDetails.where((c) => c['palletcode']?.toString() == palletcode).toList()
        : <Map<String, dynamic>>[item];

    double sumlunchqty = 0;
    for (final c in samePalletItems) {
      sumlunchqty = MathUtils.add(sumlunchqty, _num(c['billqty'] ?? c['qty']));
    }

    await Navigator.push(
      context,
      MaterialPageRoute<dynamic>(
        builder: (_) => WmsLaunchEditPage(
          activeTab: '0',
          data: {
            ..._billInfo,
            'activeTab': '0',
            'sumlunchqty': sumlunchqty,
            'detaillist': samePalletItems,
            'mergeDetails': mergeItem,
          },
        ),
      ),
    );
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final String source = launchBillSourceLabel(_billInfo['billflag']);
    final String showname = _billInfo['showname']?.toString() ?? '-';
    final String billno = _billInfo['billno']?.toString() ?? '-';
    final String createname = _billInfo['createname']?.toString() ?? '-';
    final String createtime = _billInfo['createtime']?.toString() ?? '-';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '上架明细',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        cacheExtent: 800,
        children: [
          // ── 单据信息卡片 ──
          Container(
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
                      launchBillTypeLabel(_billInfo['billflag']),
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
          const SizedBox(height: 10),
          // ── 商品明细列表 ──
          if (_mergeDetails.isEmpty && !_loading)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                    SizedBox(height: 12),
                    Text(
                      '暂无数据',
                      style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._mergeDetails.map((item) => RepaintBoundary(
                  child: LaunchProCard(
                    item: item,
                    onTap: () => _goEdit(item),
                  ),
                )),
        ],
      ),
    );
  }
}
