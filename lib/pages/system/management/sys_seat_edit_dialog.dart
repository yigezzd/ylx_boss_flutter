import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';

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

  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(context);
    if (result != null && mounted) {
      setState(() {
        _form['storeid'] = result['storeid']?.toString() ?? '';
        _form['storename'] = result['storename']?.toString() ?? '';
      });
    }
  }

  Future<void> _save() async {
    try {
      await request(HttpApi.machineCheck, _form);
      await request(HttpApi.machineUpdate, _form);
      if (mounted) {
        Toast.show('保存成功');
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) Toast.show('保存失败');
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
                  _readOnly('所属门店', _form['storename']),
                  _textField('设备名称', 'name'),
                  _readOnly('设备类型', _form['clienttypename']),
                  _readOnly('设备版本', _form['vcode']),
                  _readOnly('设备ID', _form['serialno']),
                  _switchField('授权状态', 'stopflag'),
                  _checkField('储卡充值', 'vipcharge'),
                  _checkField('储卡消费', 'vipmoney'),
                  _switchField('商城接单', 'getmallorder'),
                  _switchField('自动接单', 'getautoorderflag'),
                  _switchField('外卖接单', 'gettakeoutorder'),
                  _switchField('外卖自动接单', 'gettakeoutautoflag'),
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
              onSaved: (v) => _form[key] = v ?? '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchField(String label, String key, {String onLabel = '启用', String offLabel = '停用'}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
          const Spacer(),
          Switch(
            value: (_form[key] ?? 0) != 0,
            onChanged: (v) => setState(() => _form[key] = v ? 1 : 0),
          ),
        ],
      ),
    );
  }

  Widget _checkField(String label, String key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
          const Spacer(),
          Checkbox(
            value: (_form[key] ?? 0) == 1,
            onChanged: (v) => setState(() => _form[key] = v ?? false ? 1 : 0),
          ),
        ],
      ),
    );
  }
}
