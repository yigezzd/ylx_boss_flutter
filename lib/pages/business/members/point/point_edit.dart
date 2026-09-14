import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/members/shared/vip_select_list.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 积分操作页 —— 对齐 boss 项目 subs/member/point/edit.vue
///
/// 支持两种操作类型（对齐 Vue pointType）：
/// - 1 积分冲减（支持负数，受当前积分下限约束）
/// - 2 积分转储值（按分类 potoamt 规则自动计算兑换储值）
///
/// 权限点：010901 积分增加、010902 积分减少、010904 积分转储值
class MemberPointEditPage extends StatefulWidget {
  const MemberPointEditPage({super.key, required this.vipInfo});

  final Map<String, dynamic> vipInfo;

  @override
  State<MemberPointEditPage> createState() => _MemberPointEditPageState();
}

class _MemberPointEditPageState extends State<MemberPointEditPage> {
  Map<String, dynamic> _vipInfo = {};

  /// 操作类型：1 积分冲减 2 积分转储值（对齐 Vue query.operateType）
  int _operateType = 1;

  /// 剩余积分展示（对齐 Vue query.endpoint）
  String _endpoint = '';

  /// 兑换储值（对齐 Vue query.amt，仅展示不可编辑）
  double _amt = 0;

  final TextEditingController _pointController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  bool _submitting = false;

  static const List<Map<String, dynamic>> _pointTypes = [
    {'label': '积分冲减', 'id': 1},
    {'label': '积分转储值', 'id': 2},
  ];

  @override
  void initState() {
    super.initState();
    _vipInfo = Map<String, dynamic>.from(widget.vipInfo);
  }

  @override
  void dispose() {
    _pointController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  double get _nowpoint => double.tryParse(MathUtils.formatDecimal(4, _vipInfo['nowpoint'])) ?? 0;

  /// 会员分类对象（列表数据中可能嵌套 viptype）
  Map<String, dynamic> get _viptype {
    final vt = _vipInfo['viptype'];
    return vt is Map<String, dynamic> ? vt : <String, dynamic>{};
  }

  // ──────────── 选择会员（对齐 Vue 顶部搜索框点击返回列表重选）────────────
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
        _pointController.clear();
        _endpoint = '';
        _amt = 0;
      });
    }
  }

  // ──────────── 操作类型切换（对齐 Vue onChangepointType）────────────
  Future<void> _showOperateTypeMenu() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                child:
                    const Text('操作类型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              for (final t in _pointTypes)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(ctx, t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5)),
                    ),
                    child: Text(
                      t['label'] as String,
                      style: TextStyle(
                        fontSize: 15,
                        color: t['id'] == _operateType
                            ? const Color(0xFF006EFF)
                            : const Color(0xFF333333),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _pointController.clear();
        _endpoint = '';
        _amt = 0;
        _operateType = result['id'] as int;
      });
    }
  }

  /// 积分冲减输入失焦校验（对齐 Vue handleInputFn：nowpoint + point < 0 时取 -nowpoint）
  void _onPointBlur() {
    final text = _pointController.text.trim();
    if (text.isEmpty || text == '-') return;
    final point = double.tryParse(text);
    if (point == null) {
      setState(() => _pointController.clear());
      return;
    }
    if (_nowpoint + point < 0) {
      setState(() {
        _pointController.text = MathUtils.formatDecimal(4, -_nowpoint);
      });
    }
  }

  /// 积分转储值输入变化（对齐 Vue handleInputFnT）
  void _onExchangePointChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _endpoint = MathUtils.formatDecimal(4, _nowpoint);
        return;
      }
      final point = double.tryParse(value);
      if (point == null) {
        _pointController.clear();
        _endpoint = MathUtils.formatDecimal(4, _nowpoint);
        return;
      }
      var p = point;
      if (_nowpoint < p) {
        p = _nowpoint;
        _pointController.text = MathUtils.formatDecimal(4, p);
        _endpoint = '0';
      } else {
        _endpoint = MathUtils.formatDecimal(4, _nowpoint - p);
      }

      if (_operateType == 2 && _viptype['potoamtflag'] != 1) {
        Toast.show('请前往后台设置积分转储');
        return;
      }
      if (_viptype['potoamtflag'] == 1 && _viptype['potoamtautoflag'] == 0) {
        final usePoint = double.tryParse(_viptype['potoamtusepoint']?.toString() ?? '') ?? 0;
        final getMoney = double.tryParse(_viptype['potoamtgetmoney']?.toString() ?? '') ?? 0;
        if (usePoint <= 0 || getMoney <= 0) {
          _amt = 0;
          return;
        }
        final money = (p / usePoint) * getMoney;
        _amt = double.parse(money.toStringAsFixed(2));
      }
    });
  }

  // ──────────── 确定（对齐 Vue pointbtn + pointfn）────────────
  Future<void> _onConfirm() async {
    if (_submitting) return;
    final cardstatus = int.tryParse(_vipInfo['cardstatus']?.toString() ?? '') ?? 0;
    if (cardstatus != 1) {
      const statusMap = {2: '挂失', 3: '作废', 4: '已过期'};
      final status = statusMap[cardstatus] ?? '无效';
      Toast.show('会员已$status,请联系商家处理。');
      return;
    }

    final pointText = _pointController.text.trim();
    if (pointText.isEmpty) {
      Toast.show('请输入积分');
      return;
    }
    final point = double.tryParse(pointText) ?? 0;
    if (_operateType == 2 && _amt == 0) {
      Toast.show('请输入兑换储值');
      return;
    }
    if (_operateType == 2 && _viptype['potoamtflag'] != 1) {
      Toast.show('请前往后台设置积分转储');
      return;
    }

    if (_operateType == 1 && point > 0 && !PermissionUtils.hasPermission('010901')) {
      Toast.show('暂无积分增加操作权限');
      return;
    }
    if (_operateType == 1 && point < 0 && !PermissionUtils.hasPermission('010902')) {
      Toast.show('暂无积分减少操作权限');
      return;
    }
    if (_operateType == 2 && !PermissionUtils.hasPermission('010904')) {
      Toast.show('暂无积分转储值操作权限');
      return;
    }

    setState(() => _submitting = true);
    try {
      // 16 位随机单号（对齐 Vue generate16DigitNumber）
      final billno = (Random().nextDouble() * 9000000000000000).floor() + 1000000000000000;
      final res = await request(
          HttpApi.vipInfoPointOperate,
          {
            'vipid': _vipInfo['vipid'],
            'vipno': _vipInfo['vipno'],
            'vipname': _vipInfo['vipname'],
            'typeid': _vipInfo['typeid'],
            'endpoint': _endpoint,
            'operateType': _operateType,
            'point': pointText,
            'amt': _amt,
            'saleid': '',
            'salename': '',
            'memo': _memoController.text.trim(),
            'billno': '$billno',
          },
          true);
      Toast.show(res['retmsg']?.toString().isNotEmpty ?? false ? res['retmsg'].toString() : '操作成功');
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('积分管理',
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
                _buildFormCard(),
              ],
            ),
          ),
          _buildBottomButton(),
        ],
      ),
    );
  }

  // ──────────── 顶部伪搜索框（点击进入选择会员，对齐 Vue navPath('./index')）────────────
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

  // ──────────── 会员卡头部（对齐 Vue wrapper + bg-img）────────────
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
                const SizedBox(height: 6),
                Text('积分：${MathUtils.formatDecimal(4, _vipInfo['nowpoint'])}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // 操作类型（对齐 Vue tm-action-menu）
          _formRow(
            label: '操作类型',
            child: GestureDetector(
              onTap: _showOperateTypeMenu,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _pointTypes.firstWhere((t) => t['id'] == _operateType)['label'] as String,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE)),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),
          if (_operateType == 1)
            // 积分冲减（允许负数，失焦时校验下限）
            _formRow(
              label: '冲减积分',
              child: Expanded(
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) _onPointBlur();
                  },
                  child: TextField(
                    controller: _pointController,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: '请输入积分',
                      hintStyle: TextStyle(fontSize: 15, color: Color(0xFF999999)),
                    ),
                    onSubmitted: (_) => _onPointBlur(),
                  ),
                ),
              ),
            )
          else ...[
            // 兑换积分
            _formRow(
              label: '兑换积分',
              child: Expanded(
                child: TextField(
                  controller: _pointController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: '请输入积分',
                    hintStyle: TextStyle(fontSize: 15, color: Color(0xFF999999)),
                  ),
                  onChanged: _onExchangePointChanged,
                ),
              ),
            ),
            const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),
            // 兑换储值（只读展示）
            _formRow(
              label: '兑换储值',
              child: Text(
                MathUtils.formatDecimal(3, _amt),
                style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
              ),
            ),
            const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),
            // 剩余积分
            _formRow(
              label: '剩余积分',
              child: Text(
                _endpoint.isNotEmpty ? _endpoint : MathUtils.formatDecimal(4, _nowpoint),
                style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
              ),
            ),
          ],
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

  // ──────────── 底部确定按钮 ────────────
  Widget _buildBottomButton() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: _submitting ? null : _onConfirm,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _submitting ? const Color(0xFFB3CFFF) : const Color(0xFF006EFF),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              _submitting ? '操作中...' : '确定',
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
