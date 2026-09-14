import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/members/basic/add.dart';
import 'package:flutter_deer/pages/business/members/shared/vip_select_list.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// 会员充值页 —— 对齐 boss 项目 subs/member/recharge/edit.vue
///
/// 流程：选择会员 → 输入充值金额（自动匹配赠送规则 getVipRechargeRule）
/// → 选择支付方式/业务员 → 立即充值（vipInfo/addMoney，权限 010801）。
/// 微信/支付宝（payid 03/04）需先扫描 18 位付款码。
class MemberRechargeEditPage extends StatefulWidget {
  const MemberRechargeEditPage({super.key, required this.vipInfo});

  final Map<String, dynamic> vipInfo;

  @override
  State<MemberRechargeEditPage> createState() => _MemberRechargeEditPageState();
}

class _MemberRechargeEditPageState extends State<MemberRechargeEditPage> {
  Map<String, dynamic> _vipInfo = {};

  // ── 充值参数（对齐 Vue queryDefault）──
  String _ruleid = '';
  String _givepoint = '';
  String _payid = '01';
  String _payname = '现金';
  String _saleid = '';
  String _salename = '';
  String _authCode = '';

  final TextEditingController _amtController = TextEditingController();
  final TextEditingController _giveamtController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _vipInfo = Map<String, dynamic>.from(widget.vipInfo);
  }

  @override
  void dispose() {
    _amtController.dispose();
    _giveamtController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  /// 金额格式化：去除非法字符后按金额格式输出（对齐 Vue amtBlur）
  String _moneyFormat(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^\d.-]'), '');
    return MathUtils.formatDecimal(3, cleaned);
  }

  // ──────────── 选择会员（对齐 Vue 顶部搜索框 → ./search）────────────
  Future<void> _openSelectVip() async {
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute<Map<String, dynamic>>(
        settings: const RouteSettings(name: '/业务/会员/选择会员'),
        builder: (_) => const VipSelectListPage(title: '选择会员', selectMode: true),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _vipInfo = Map<String, dynamic>.from(selected);
        _amtController.clear();
        _giveamtController.clear();
        _ruleid = '';
        _givepoint = '';
        _authCode = '';
      });
    }
  }

  // ── 新增会员（对齐 Vue add()，权限 010702）──
  Future<void> _add() async {
    if (!PermissionUtils.checkPermission('010702')) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: '/业务/会员/会员开卡'),
        builder: (_) => const MemberAddPage(isAdd: 1),
      ),
    );
  }

  // ──────────── 充值金额失焦：格式化 + 拉取赠送规则（对齐 Vue getVipRechargeRule）────────────
  Future<void> _onAmtBlur() async {
    final formatted = _moneyFormat(_amtController.text);
    setState(() => _amtController.text = formatted);
    if (formatted.isEmpty) return;
    try {
      final res = await request(
          HttpApi.vipInfoGetVipRechargeRule,
          {
            'vipid': _vipInfo['vipid'],
            'vipno': _vipInfo['vipno'],
            'typeid': _vipInfo['typeid'],
            'amt': formatted,
          },
          false,
          false);
      final data = res['data'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() {
          _ruleid = data['ruleid']?.toString() ?? '';
          _givepoint = data['givepoint']?.toString() ?? '';
          _giveamtController.text = MathUtils.formatDecimal(3, data['giveamt'] ?? 0);
        });
      }
    } catch (_) {}
  }

  // ── 选择支付方式（对齐 Vue selectCom plugins/get filter="vipaddflag"）──
  Future<void> _selectPay() async {
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
        // 切换支付方式后重新扫码（对齐 Vue amount 清空逻辑）
        _authCode = '';
      });
    }
  }

  // ── 选择业务员（对齐 Vue selectCom sysuser/findList mergData={stopflag:0}）──
  Future<void> _selectUser() async {
    final result = await CommonSelectSheet.show(
      context,
      title: '选择业务员',
      searchHint: '输入业务员名称/编码',
      idField: 'userid',
      fetchData: (search, page) => request(HttpApi.sysUserList, {
        'cond': search,
        'page': page,
        'pagesize': 20,
        'stopflag': 0,
      }).then((r) {
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
    );
    if (result != null && mounted) {
      setState(() {
        _saleid = result['userid']?.toString() ?? '';
        _salename = result['name']?.toString() ?? '';
      });
    }
  }

  // ──────────── 立即充值（对齐 Vue paybtn + scanQrClose + payfn）────────────
  Future<void> _payBtn() async {
    if (_submitting) return;
    final cardstatus = int.tryParse(_vipInfo['cardstatus']?.toString() ?? '') ?? 0;
    if (cardstatus != 1) {
      const statusMap = {2: '挂失', 3: '作废', 4: '已过期'};
      final status = statusMap[cardstatus] ?? '无效';
      Toast.show('会员已$status,请联系商家处理。');
      return;
    }

    final amt = double.tryParse(_amtController.text.trim()) ?? 0;
    if (amt <= 0) {
      Toast.show('请输入充值金额');
      return;
    }

    // 微信/支付宝需扫 18 位付款码（对齐 Vue scanQrClose）
    if ((_payid == '03' || _payid == '04') && _authCode.isEmpty) {
      final code = await Navigator.push<String>(
        context,
        MaterialPageRoute<String>(builder: (_) => const QrCodeScannerPage()),
      );
      if (!mounted) return;
      if (code == null || code.length != 18) {
        Toast.show('请扫描正确的付款码');
        return;
      }
      _authCode = code;
    }

    await _payFn(amt);
  }

  Future<void> _payFn(double amt) async {
    setState(() => _submitting = true);
    try {
      // 16 位随机单号（对齐 Vue generate16DigitNumber）
      final billno = (Random().nextDouble() * 9000000000000000).floor() + 1000000000000000;
      final res = await request(
          HttpApi.vipInfoAddMoney,
          {
            'vipid': _vipInfo['vipid'],
            'vipno': _vipInfo['vipno'],
            'vipname': _vipInfo['vipname'],
            'typeid': _vipInfo['typeid'],
            'billno': '$billno',
            'amt': amt,
            'giveamt': _giveamtController.text.trim(),
            'givepoint': _givepoint,
            'ruleid': _ruleid,
            'authcode': _authCode,
            'auth_code': _authCode,
            'payid': _payid,
            'payname': _payname,
            'saleid': _saleid,
            'salename': _salename,
            'memo': _memoController.text.trim(),
          },
          true);
      final msg = res['retmsg']?.toString() ?? '';
      Toast.show(msg.isNotEmpty ? msg : '充值成功');
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) Navigator.pop(context, true);
        });
      }
    } catch (_) {
      // request 内部已弹错误提示
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPerm = PermissionUtils.hasPermission('010801');
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('会员充值',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
      ),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: ListView(
              cacheExtent: 800,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 8),
                _buildBalanceCard(),
                const SizedBox(height: 8),
                _buildFormCard(),
              ],
            ),
          ),
          // 底部立即充值按钮（权限 010801，对齐 Vue :disabled="!permission('010801')"）
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: (!hasPerm || _submitting) ? null : _payBtn,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (!hasPerm || _submitting)
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF006EFF),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    _submitting ? '充值中...' : '立即充值',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 顶部：伪搜索框 + 新增按钮 ────────────
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _openSelectVip,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFDEDEDE)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, size: 18, color: Color(0xFF999999)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '请输入会员卡号/名称/手机号',
                        style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                      ),
                    ),
                    Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF666666)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _add,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                Icons.add,
                size: 24,
                color: PermissionUtils.hasPermission('010702')
                    ? Colors.black
                    : const Color(0xFF999999),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 会员卡头部 ────────────
  Widget _buildHeaderCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              'http://byyoupic.oss-cn-shenzhen.aliyuncs.com/bycloud/zm/null/pro_bbaae44a7d8b64459f8f11e7a31bbcfe.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFF6E8), Color(0xFFFFE9C8)],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _vipInfo['vipno']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        _vipInfo['viptypename']?.toString() ?? '',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('会员姓名：${_vipInfo['vipname'] ?? ''}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
                const SizedBox(height: 6),
                Text('手机号码：${_vipInfo['mobile'] ?? ''}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 余额卡片（对齐 Vue boxbg 金色卡片）────────────
  Widget _buildBalanceCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEED2B4)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('储卡余额', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                      const SizedBox(height: 4),
                      Text(
                        MathUtils.formatDecimal(3, _vipInfo['nowmoney']),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本金：${MathUtils.formatDecimal(3, _vipInfo['capitalmoney'])}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '赠金：${MathUtils.formatDecimal(3, _vipInfo['givemoney'])}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEED2B4)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '会员积分：${MathUtils.formatDecimal(4, _vipInfo['nowpoint'])}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF7A7A7A)),
                  ),
                ),
                Expanded(
                  child: Text(
                    '零钱余额：${MathUtils.formatDecimal(3, _vipInfo['pocketmoney'])}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF7A7A7A)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 表单卡片 ────────────
  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // 充值金额（蓝色描边输入框，对齐 Vue myborder）
          _moneyInput(
            label: '充值金额：',
            controller: _amtController,
            onSubmitted: (_) => _onAmtBlur(),
            onBlur: _onAmtBlur,
          ),
          // 赠送金额
          _moneyInput(
            label: '赠送金额：',
            controller: _giveamtController,
            onBlur: () {
              setState(() {
                _giveamtController.text = _moneyFormat(_giveamtController.text);
              });
            },
          ),
          const Divider(height: 1, indent: 10, endIndent: 10, color: Color(0xFFEEEEEE)),
          // 支付方式
          _formRow(
            label: '支付方式：',
            child: GestureDetector(
              onTap: _selectPay,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _payname.isNotEmpty ? _payname : '请选择',
                    style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE)),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),
          // 业务员
          _formRow(
            label: '业务员',
            child: GestureDetector(
              onTap: _selectUser,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _salename.isNotEmpty ? _salename : '请选择',
                    style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE)),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),
          _formRow(
            label: '备注',
            child: Expanded(
              child: TextField(
                controller: _memoController,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: '请输入备注',
                  hintStyle: TextStyle(fontSize: 15, color: Color(0xFF999999)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 金额输入行（蓝色描边 + “元”后缀，对齐 Vue myborder + suffixLabel）
  Widget _moneyInput({
    required String label,
    required TextEditingController controller,
    VoidCallback? onBlur,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB7D5FF), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus && onBlur != null) onBlur();
        },
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF686868))),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: '0.00',
                  hintStyle: TextStyle(fontSize: 15, color: Color(0xFF999999)),
                ),
                onSubmitted: onSubmitted,
              ),
            ),
            const SizedBox(width: 6),
            const Text('元', style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
          ],
        ),
      ),
    );
  }

  Widget _formRow({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 115,
            child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF686868))),
          ),
          if (child is Expanded) child else Expanded(child: child),
        ],
      ),
    );
  }
}
