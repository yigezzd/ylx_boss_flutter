import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/members/shared/vip_select_list.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';

/// 会员收款页 —— 对齐 boss 项目 subs/member/vippay/edit.vue
///
/// 会员卡余额收款：输入收款金额（不超过储卡余额）→ 业务员/备注 →
/// 提交 vipInfo/pay（payid=02 会员卡，opertype=8，权限 0110）。
class MemberVippayEditPage extends StatefulWidget {
  const MemberVippayEditPage({super.key, required this.vipInfo});

  final Map<String, dynamic> vipInfo;

  @override
  State<MemberVippayEditPage> createState() => _MemberVippayEditPageState();
}

class _MemberVippayEditPageState extends State<MemberVippayEditPage> {
  Map<String, dynamic> _vipInfo = {};

  String _saleid = '';
  String _salename = '';

  final TextEditingController _amtController = TextEditingController();
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
    _memoController.dispose();
    super.dispose();
  }

  double get _nowmoney => double.tryParse(_vipInfo['nowmoney']?.toString() ?? '') ?? 0;

  // ──────────── 选择会员（对齐 Vue 顶部搜索框 → navPath('./index')）────────────
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

  /// 收款金额失焦：格式化并限制不超过储卡余额（对齐 Vue handleInputFn）
  void _onAmtBlur() {
    final text = _amtController.text.trim();
    if (text.isEmpty || text == '-') return;
    var amt = double.tryParse(text);
    if (amt == null) {
      setState(() => _amtController.clear());
      return;
    }
    if (_nowmoney < amt) {
      amt = _nowmoney;
    }
    setState(() {
      _amtController.text = MathUtils.formatDecimal(3, amt);
    });
  }

  // ──────────── 确定收款（对齐 Vue paybtn + payinfo）────────────
  Future<void> _payBtn() async {
    if (_submitting) return;
    final cardstatus = int.tryParse(_vipInfo['cardstatus']?.toString() ?? '') ?? 0;
    if (cardstatus != 1) {
      const statusMap = {2: '挂失', 3: '作废', 4: '已过期'};
      final status = statusMap[cardstatus] ?? '无效';
      Toast.show('会员已$status,请联系商家处理。');
      return;
    }

    final amtText = _amtController.text.trim();
    if (amtText.isEmpty || (double.tryParse(amtText) ?? 0) <= 0) {
      Toast.show('请输入收款金额');
      return;
    }

    setState(() => _submitting = true);
    try {
      final billno = (Random().nextDouble() * 9000000000000000).floor() + 1000000000000000;
      // 对齐 Vue payinfo：amt 放入 vipCardPay，payid 固定 02 会员卡，opertype 8
      final res = await request(
          HttpApi.vipInfoPay,
          {
            'vipid': _vipInfo['vipid'],
            'vipno': _vipInfo['vipno'],
            'vipname': _vipInfo['vipname'],
            'typeid': _vipInfo['typeid'],
            'saleid': _saleid,
            'salename': _salename,
            'memo': _memoController.text.trim(),
            'opertype': 8,
            'billno': '$billno',
            'vipCardPay': <String, dynamic>{
              'amt': amtText,
              'orderAmt': amtText,
              'addmoney': amtText,
            },
            'payid': '02',
            'payname': '会员卡',
          },
          true);
      final msg = res['retmsg']?.toString() ?? '';
      Toast.show(msg.isNotEmpty ? msg : '操作成功');
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
    final hasPerm = PermissionUtils.hasPermission('0110');
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('会员收款',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
      ),
      body: Column(
        children: [
          _buildFakeSearchBar(),
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
          // 底部确定按钮（权限 0110，对齐 Vue :disabled="!permission('0110')"）
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
                    _submitting ? '操作中...' : '确定',
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

  // ──────────── 顶部伪搜索框 ────────────
  Widget _buildFakeSearchBar() {
    return GestureDetector(
      onTap: _openSelectVip,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
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
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '赠金：${MathUtils.formatDecimal(3, _vipInfo['givemoney'])}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFEEEEEE)),
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
          // 收款金额（蓝色描边输入框，对齐 Vue myborder + suffixLabel="元"）
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFB7D5FF), width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) _onAmtBlur();
              },
              child: Row(
                children: [
                  const SizedBox(
                    width: 80,
                    child: Text('收款金额', style: TextStyle(fontSize: 15, color: Color(0xFF686868))),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _amtController,
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
                      onSubmitted: (_) => _onAmtBlur(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('元', style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 10, endIndent: 10, color: Color(0xFFEEEEEE)),
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
