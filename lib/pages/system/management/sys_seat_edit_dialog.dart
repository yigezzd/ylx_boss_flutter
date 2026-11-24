import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 站点设备编辑弹窗（对齐 Vue sysseat editDrawerRef）
class SysSeatEditDialog extends StatefulWidget {
  const SysSeatEditDialog({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  State<SysSeatEditDialog> createState() => _SysSeatEditDialogState();
}

class _SysSeatEditDialogState extends State<SysSeatEditDialog> {
  late Map<String, dynamic> _form;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _form = Map<String, dynamic>.from(widget.item);
  }

  /// 绑定站点文案（对齐 Vue：editSiteForm.seatcode || seatCode || 未绑定）
  String get _seatcode {
    final String code = _form['seatcode']?.toString() ?? '';
    final String alt = _form['seatCode']?.toString() ?? '';
    final String value = code.isNotEmpty ? code : alt;
    return value.isNotEmpty ? value : '未绑定';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    _formKey.currentState?.save();
    try {
      // 对齐 Vue saveEditSite：先 checkMachine 再 update
      await request(HttpApi.machineCheck, _form);
      await request(HttpApi.machineUpdate, _form);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      // 失败提示由 http_helper 统一弹出后端 retmsg，此处不覆盖
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration:
                const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E2E2)))),
            child: Row(
              children: [
                const Expanded(
                    child: Center(
                        child: Text('设备编辑',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          // 表单
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _readOnly('设备编号', _form['code']),
                  _readOnly('绑定站点', _seatcode),
                  _readOnly('所属门店', _form['storename']),
                  _textField('设备名称', 'name'),
                  _readOnly('设备类型', _firstText([_form['clienttypeName'], _form['clienttypename']])),
                  _readOnly('设备版本', _form['vcode']),
                  _readOnly('设备ID', _form['serialno']),
                  _switchField('授权状态', 'stopflag', onValue: 0, offValue: 1),
                  _groupRow('储卡业务', [
                    _inlineCheck('储卡充值', 'vipcharge'),
                    const SizedBox(width: 12),
                    _inlineCheck('储卡消费', 'vipmoney'),
                  ]),
                  _groupRow('商城接单', [
                    _inlineSwitch('getmallorder'),
                    const SizedBox(width: 12),
                    _inlineCheck('自动接单', 'getautoorderflag',
                        enabled: _form['getmallorder']?.toString() == '1'),
                  ]),
                  _groupRow('外卖接单', [
                    _inlineSwitch('gettakeoutorder'),
                    const SizedBox(width: 12),
                    _inlineCheck('自动接单', 'gettakeoutautoflag',
                        enabled: _form['gettakeoutorder']?.toString() == '1'),
                  ]),
                  _readOnly('最后登录IP', _form['lastip']),
                  _readOnly('最后登录时间', _form['lasttime']),
                  _readOnly('最后登录用户', _form['lastuser']),
                ],
              ),
            ),
          ),
          // 底部按钮
          Container(
            padding: const EdgeInsets.all(12),
            decoration:
                const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E2E2)))),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context), child: const Text('取消')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006EFF), foregroundColor: Colors.white),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 多字段取值：返回第一个非空值（对齐 Vue `a || b || '--'`）
  static String? _firstText(List<dynamic> values) {
    for (final dynamic value in values) {
      final String text = value?.toString() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  Widget _readOnly(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
          Expanded(
              child: Text(value?.toString() ?? '--',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                  textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _textField(String label, String key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
          Expanded(
            child: TextFormField(
              initialValue: _form[key]?.toString() ?? '',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
              validator: (v) => (v ?? '').trim().isEmpty ? '请输入$label' : null,
              onSaved: (v) => _form[key] = v ?? '',
            ),
          ),
        ],
      ),
    );
  }

  /// 开关行：value 为 true 时写入 [onValue]，否则写入 [offValue]
  Widget _switchField(String label, String key, {int onValue = 1, int offValue = 0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
          const Spacer(),
          Switch(
            value: (_form[key]?.toString() ?? '') == onValue.toString(),
            onChanged: (v) => setState(() => _form[key] = v ? onValue : offValue),
          ),
        ],
      ),
    );
  }

  /// 组合行（储卡业务 / 商城接单 / 外卖接单）
  Widget _groupRow(String label, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
          const Spacer(),
          ...children,
        ],
      ),
    );
  }

  Widget _inlineSwitch(String key) {
    return Transform.scale(
      scale: 0.85,
      child: Switch(
        value: _form[key]?.toString() == '1',
        onChanged: (v) => setState(() => _form[key] = v ? 1 : 0),
      ),
    );
  }

  Widget _inlineCheck(String label, String key, {bool enabled = true}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.85,
          child: Checkbox(
            value: _form[key]?.toString() == '1',
            visualDensity: VisualDensity.compact,
            onChanged: enabled ? (v) => setState(() => _form[key] = (v ?? false) ? 1 : 0) : null,
          ),
        ),
        Text(label,
            style: TextStyle(
                fontSize: 13, color: enabled ? const Color(0xFF333333) : const Color(0xFF9CA3AF))),
      ],
    );
  }
}
