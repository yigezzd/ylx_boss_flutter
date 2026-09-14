import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// 付费卡售卡收款页 —— 对齐 boss 项目 subs/member/members/pay.vue
///
/// [query] 结构：{vipInfo, vipTypeRuleSet, labelInfoList}
/// 收款成功后调用 vipInfo/add 保存，cardstatus 置为 1（已发行）。
class MemberPayPage extends StatefulWidget {
  const MemberPayPage({super.key, required this.query});

  final Map<String, dynamic> query;

  @override
  State<MemberPayPage> createState() => _MemberPayPageState();
}

class _MemberPayPageState extends State<MemberPayPage> {
  late final Map<String, dynamic> _vipInfo;
  late final Map<String, dynamic> _vipTypeRuleSet;
  late final List<Map<String, dynamic>> _labelInfoList;
  late final Map<String, dynamic> _vipAddMoneyReq;

  String _payid = '01';
  String _payname = '现金';
  String _authCode = '';
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _vipInfo = widget.query['vipInfo'] is Map<String, dynamic>
        ? widget.query['vipInfo'] as Map<String, dynamic>
        : <String, dynamic>{};
    _vipTypeRuleSet = widget.query['vipTypeRuleSet'] is Map<String, dynamic>
        ? widget.query['vipTypeRuleSet'] as Map<String, dynamic>
        : <String, dynamic>{};
    _labelInfoList = widget.query['labelInfoList'] is List
        ? (widget.query['labelInfoList'] as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    _vipAddMoneyReq = widget.query['vipAddMoneyReq'] is Map<String, dynamic>
        ? widget.query['vipAddMoneyReq'] as Map<String, dynamic>
        : <String, dynamic>{};
  }

  /// 选择支付方式（对齐 Vue selectCom httplink=plugins/get retDataname=payway filter=vipaddflag）
  Future<void> _selectPayWay() async {
    final item = await CommonSelectSheet.show(
      context,
      title: '选择支付方式',
      searchHint: '输入支付名称/编码',
      idField: 'payid',
      initialSelectedId: _payid.isEmpty ? null : _payid,
      fetchData: (search, page) async {
        // 对齐小程序 selectCom mergData：搜索关键字走 cond，paywayParams.name 恒为空串
        final res = await request(HttpApi.pluginsGet, {
          'is_page': 0,
          'paywayParams': {'name': ''},
          'plugins': ['payway'],
          'cond': search,
        });
        final data = res['data'];
        // payway 返回结构为含 list 的 Map（对齐小程序 res.payway.list）
        final pw = data is Map<String, dynamic> ? data['payway'] : null;
        final List<dynamic> list =
            pw is Map<String, dynamic> ? (pw['list'] as List? ?? []) : (pw is List ? pw : []);
        // 过滤支持会员充值的支付方式（对齐 Vue filter="vipaddflag"：vipaddflag==1 且 payid!='02'）
        final rows = list
            .cast<Map<String, dynamic>>()
            .where((e) => e['vipaddflag']?.toString() == '1' && e['payid']?.toString() != '02')
            .toList();
        return {'list': rows};
      },
    );
    if (item != null && mounted) {
      setState(() {
        _payid = item['payid']?.toString() ?? '';
        _payname = item['name']?.toString() ?? '';
      });
    }
  }

  /// 扫描付款码（对齐 Vue scanQrClose：微信/支付宝需扫 18 位付款码）
  Future<void> _scanPayCode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(builder: (_) => const QrCodeScannerPage()),
    );
    if (!mounted) return;
    if (code == null || code.isEmpty || code.length != 18) {
      Toast.show('请扫描正确的付款码');
      return;
    }
    _authCode = code;
    _pay();
  }

  /// 立即充值（对齐 Vue paybtn）
  Future<void> _pay() async {
    if (_paying) return;
    final payamt = double.tryParse(_vipTypeRuleSet['payamt']?.toString() ?? '') ?? 0;
    _vipInfo['cardamt'] = _vipTypeRuleSet['nowmoney'];
    _vipInfo['amt'] = payamt;
    _vipInfo['cardstatus'] = 1;

    if (payamt <= 0) {
      Toast.show('金额异常');
      return;
    }

    // 微信/支付宝需付款码
    if ((_payid == '03' || _payid == '04') && _authCode.isEmpty) {
      _scanPayCode();
      return;
    }
    if (_authCode.isNotEmpty) {
      _vipInfo['auth_code'] = _authCode;
      _vipTypeRuleSet['auth_code'] = _authCode;
    }

    setState(() => _paying = true);
    try {
      await request(
          HttpApi.vipInfoAdd,
          {
            'vipInfo': _vipInfo,
            'vipTypeRuleSet': _vipTypeRuleSet,
            'labelInfoList': _labelInfoList,
            'vipAddMoneyReq': _vipAddMoneyReq,
            'payid': _payid,
            'payname': _payname,
            'cardamt': _vipInfo['cardamt'],
            'amt': _vipInfo['amt'],
            if (_authCode.isNotEmpty) 'auth_code': _authCode,
          },
          true);
      if (!mounted) return;
      Toast.show('保存档案成功，');
      // 成功后直接回退到会员列表（对齐 Vue navigateTo ./index + getTips(1)）
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('会员开卡',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              cacheExtent: 800,
              padding: const EdgeInsets.all(10),
              children: [
                // 待收金额卡片（对齐 Vue 带边框卡片）
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE6E6E6)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        const Text('待收金额',
                            style: TextStyle(fontSize: 14, color: Color(0xFF686868))),
                        const SizedBox(height: 8),
                        Text(
                          '¥${MathUtils.formatDecimal(3, _vipTypeRuleSet['payamt'])}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(
                              '售卡金额：${MathUtils.formatDecimal(3, _vipTypeRuleSet['payamt'])}',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                            ),
                            Text(
                              '开卡余额：${MathUtils.formatDecimal(3, _vipTypeRuleSet['nowmoney'])}',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 支付方式
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _selectPayWay,
                    child: Row(
                      children: [
                        const Text('支付方式：',
                            style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
                        const Spacer(),
                        Text(
                          _payname,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 底部立即充值按钮
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _paying ? null : _pay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006EFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                  child: _paying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('立即充值', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
