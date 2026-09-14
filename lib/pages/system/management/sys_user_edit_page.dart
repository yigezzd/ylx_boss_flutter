import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 用户管理 - 新增/编辑（对齐 Vue sysuser/edit.vue）
class SysUserEditPage extends StatefulWidget {
  const SysUserEditPage({super.key, this.user});
  final String? user; // JSON string of user data (null = 新增)

  @override
  State<SysUserEditPage> createState() => _SysUserEditPageState();
}

class _SysUserEditPageState extends State<SysUserEditPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  bool _isEdit = false;
  String _oldPwd = '';
  bool _pwdModified = false;

  // 角色列表
  List<Map<String, dynamic>> _roleList = [];
  Map<String, dynamic>? _selectedRole;

  // 表单数据
  Map<String, dynamic> _form = {
    'id': '',
    'roleid': '',
    'rolename': '',
    'roletype': '',
    'code': '',
    'name': '',
    'pwd': '',
    'sid': '',
    'storename': '',
    'stopflag': 0,
    'mobile': '',
    // 登录权限
    'webflag': 1,
    'appsellflag': 1,
    'wxflag': 0,
    'pcflag': 0,
    'fjflag': 0,
    // 数据控制
    'reportcol': 2,
    'colsetflag': 1,
    'viewrepamtrate': '100',
    'costpriceflag': 1,
    'inpriceflag': 1,
    'pspriceflag': 1,
    'supflag': 1,
    'checkstockflag': 1,
    'supjointflag': 1,
    'cgpriceflag': 1,
    // 业务管理 - 零售
    'dsc': '',
    'maxround': '',
    'rfid': '',
    // 业务管理 - 批发
    'wholesaleflag': 0,
    'custupdateflag': 0,
    'pfdsc': '',
    'billprviflag': 1,
    // 授权范围
    'sysUserStoreList': <dynamic>[],
    'storeprviflag': 0,
  };

  // 输入框控制器
  final Map<String, TextEditingController> _controllers = {};

  // 下拉选项
  static const _colsetflagList = [
    {'label': '禁止列设定', 'id': 0},
    {'label': '个人列设定', 'id': 1},
    {'label': '个人和角色列设定', 'id': 2},
  ];
  static const _custupdateflagList = [
    {'label': '不限', 'id': 0},
    {'label': '不允许修改价格', 'id': 1},
    {'label': '不允许查看价格', 'id': 2},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  /// 获取/创建输入框控制器
  TextEditingController _controller(String key) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: _form[key]?.toString() ?? ''),
    );
  }

  Future<void> _initData() async {
    try {
      // 加载角色列表
      final roleRes = await request(HttpApi.roleFindList, {'is_page': 0});
      final roleData = roleRes['data'];
      _roleList =
          ((roleData is Map ? roleData['list'] : null) as List?)?.cast<Map<String, dynamic>>() ??
              [];

      if (widget.user != null) {
        // 编辑模式 - 传入完整用户数据给 getInfo
        _isEdit = true;
        final userData = jsonDecode(widget.user!) as Map<String, dynamic>;

        // 获取完整用户信息（对齐 Vue: getInfo(JSON.parse(data))）
        final infoRes = await request(HttpApi.sysUserGetInfo, userData);
        final data = infoRes['data'];
        if (data is Map<String, dynamic>) {
          _form = {..._form, ...data};
          _oldPwd = data['pwd']?.toString() ?? '';
          _form['pwd'] = '****'; // 编辑时显示****占位
          _pwdModified = false;

          // 对齐 Vue: if (query.value.code) { supflag = 1; checkstockflag = 1; }
          if (_form['code']?.toString().isNotEmpty ?? false) {
            _form['supflag'] = 1;
            _form['checkstockflag'] = 1;
          }
        }

        // 匹配角色
        for (final role in _roleList) {
          if (role['roleid']?.toString() == _form['roleid']?.toString()) {
            _selectedRole = role;
            _form['rolename'] = role['rolename'];
            _form['roletype'] = role['roletype'];
            break;
          }
        }
      } else {
        // 新增模式 - 自动生成工号
        try {
          final codeRes = await request(HttpApi.sysUserGenerateCode, <String, dynamic>{});
          _form['code'] = codeRes['data']?.toString() ?? '';
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// 是否禁用（admin 账号 1001）
  bool get _disabled => _isEdit && _form['code']?.toString() == '1001';

  // ============ 选择器 ============
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(context);
    if (result != null && mounted) {
      setState(() {
        _form['sid'] = result['storeid']?.toString() ?? '';
        _form['storename'] = result['storename']?.toString() ?? '';
      });
    }
  }

  void _selectRole(Map<String, dynamic> role) {
    setState(() {
      _selectedRole = role;
      _form['roleid'] = role['roleid'];
      _form['rolename'] = role['rolename'];
      _form['roletype'] = role['roletype'];
    });
    Navigator.pop(context);
  }

  // ============ 保存 ============
  Future<void> _save() async {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('014803', showTip: false)) {
        Toast.show('你无权编辑用户管理，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('014802', showTip: false)) {
        Toast.show('你无权新增用户管理，请在后台修改权限');
        return;
      }
    }
    if (_form['roleid']?.toString().isEmpty ?? true) {
      return Toast.show('角色不能为空');
    }
    if (_form['sid']?.toString().isEmpty ?? true) {
      return Toast.show('所属机构不能为空');
    }
    if (_form['code']?.toString().isEmpty ?? true) {
      return Toast.show('工号不能为空');
    }
    if (_form['name']?.toString().isEmpty ?? true) {
      return Toast.show('姓名不能为空');
    }
    if (!_isEdit && (_form['pwd']?.toString().isEmpty ?? true)) {
      return Toast.show('密码不能为空');
    }

    final data = Map<String, dynamic>.from(_form);

    // 密码 MD5 加密
    if ((data['pwd']?.toString().isNotEmpty ?? false) && data['pwd'] != '****') {
      data['pwd'] = md5.convert(utf8.encode(data['pwd'].toString())).toString();
    } else {
      data['pwd'] = _oldPwd;
    }

    // 处理授权范围
    final storeList = data['sysUserStoreList'] as List? ?? [];
    final hasAllStore = storeList.any((item) => item is Map && item['sid'] == 0);
    if (hasAllStore || storeList.isEmpty) {
      data['storeprviflag'] = 0;
      data['sysUserStoreList'] = <dynamic>[];
    } else {
      data['storeprviflag'] = 1;
    }

    try {
      await request(HttpApi.sysUserSave, data);
      if (mounted) {
        Toast.show('操作成功');
        Navigator.of(context).pop(true);
      }
    } catch (_) {}
  }

  // ============ 删除 ============
  void _delete() {
    if (!PermissionUtils.checkPermission('014804', showTip: false)) {
      Toast.show('你无权删除用户管理，请在后台修改权限');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定删除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              request(HttpApi.sysUserDelete, {
                'operateType': 0,
                'ids': [_form['id']],
              }).then((_) {
                Toast.show('删除成功');
                Navigator.of(context).pop(true);
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ============ Build ============
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
        centerTitle: true,
        title: Text(_isEdit ? '编辑用户' : '新增用户',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          // TabBar
          ColoredBox(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF006EFF),
              unselectedLabelColor: const Color(0xFF666666),
              indicatorColor: const Color(0xFF006EFF),
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 14),
              tabs: const [
                Tab(text: '基础信息'),
                Tab(text: '数据控制'),
                Tab(text: '业务管理'),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBasicTab(),
                _buildDataControlTab(),
                _buildBusinessTab(),
              ],
            ),
          ),
          // Bottom buttons
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ============ 基础信息 Tab ============
  Widget _buildBasicTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionCard([
          _selectorRow('员工角色', _roleLabel, onTap: _disabled ? null : _showRolePicker),
          _selectorRow('所属机构', _form['storename']?.toString() ?? '',
              placeholder: '请选择', onTap: _disabled ? null : _selectStore),
          if (_selectedRole?['roletype'] == 0)
            _selectorRow('授权范围', _authRangeLabel,
                placeholder: '全部', onTap: _disabled ? null : _selectAuthRange),
          _inputRow('员工工号', 'code', readOnly: _isEdit),
          _inputRow('员工姓名', 'name'),
          _inputRow('手机号', 'mobile', readOnly: _disabled, keyboard: TextInputType.phone),
          _inputRow('登录密码', 'pwd',
              obscure: true,
              readOnly: _disabled,
              onFocused: _isEdit && !_pwdModified
                  ? () {
                      // 编辑模式首次获焦点时清空****占位
                      _controllers['pwd']?.clear();
                      _form['pwd'] = '';
                      _pwdModified = true;
                    }
                  : null),
          _switchRow('启用状态', _form['stopflag'] == 0,
              disabled: _disabled,
              onChanged: _disabled
                  ? null
                  : (v) {
                      setState(() => _form['stopflag'] = v ? 0 : 1);
                    }),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('登录权限', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        _sectionCard([
          _checkboxGrid([
            _cbItem('后台', 'webflag'),
            _cbItem('移动端', 'appsellflag'),
            _cbItem('小程序', 'wxflag'),
          ]),
          _checkboxGrid([
            _cbItem('收银POS', 'pcflag'),
            _cbItem('分拣系统', 'fjflag'),
          ]),
        ]),
      ],
    );
  }

  // ============ 数据控制 Tab ============
  Widget _buildDataControlTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionCard([
          _selectorRow('报表列设定', _colsetflagLabel, onTap: () {
            _showOptionPicker('选择报表列设定', _colsetflagList, _form['colsetflag'], (v) {
              setState(() => _form['colsetflag'] = v);
            });
          }),
          _inputRow('报表金额比例', 'viewrepamtrate',
              suffix: '%', keyboard: const TextInputType.numberWithOptions(decimal: true)),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('控制参数', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        _sectionCard([
          _checkboxGrid([
            _cbItem('允许查看成本', 'costpriceflag'),
            _cbItem('允许查看进价', 'inpriceflag'),
          ]),
          _checkboxGrid([
            _cbItem('允许查看配送价', 'pspriceflag'),
            _cbItem('允许查看货商信息', 'supflag'),
          ]),
          _checkboxGrid([
            _cbItem('允许查看库存', 'checkstockflag'),
            _cbItem('联营扣率修改', 'supjointflag'),
          ]),
          _checkboxGrid([
            _cbItem('入库单进价只能改低不能改高', 'cgpriceflag'),
          ]),
        ]),
      ],
    );
  }

  // ============ 业务管理 Tab ============
  Widget _buildBusinessTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('零售业务', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        _sectionCard([
          _inputRow('最低折扣', 'dsc',
              suffix: '%',
              placeholder: '不限',
              keyboard: const TextInputType.numberWithOptions(decimal: true)),
          _inputRow('最大抹零', 'maxround',
              suffix: '元',
              placeholder: '不限',
              keyboard: const TextInputType.numberWithOptions(decimal: true)),
          _inputRow('收银授权码', 'rfid', obscure: true, keyboard: TextInputType.number),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('批发业务', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        _sectionCard([
          _selectorRow('改价权限', _custupdateflagLabel, onTap: () {
            _showOptionPicker('选择改价权限', _custupdateflagList, _form['custupdateflag'], (v) {
              setState(() => _form['custupdateflag'] = v);
            });
          }),
          _inputRow('最低折扣率', 'pfdsc',
              suffix: '%',
              placeholder: '不限',
              keyboard: const TextInputType.numberWithOptions(decimal: true)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _cbItem('仅查看本人所属客户的业务数据', 'billprviflag'),
          ),
        ]),
      ],
    );
  }

  // ============ 底部按钮 ============
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E2E2))),
      ),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _isEdit ? _delete : () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEDE)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(_isEdit ? '删除' : '取消',
                    style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _save,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF006EFF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Text('保存', style: TextStyle(fontSize: 15, color: Colors.white)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ============ Label 计算 ============
  String get _roleLabel {
    if (_selectedRole == null) return '';
    final type = _selectedRole!['roletype'] == 0 ? '集团' : '门店';
    return '[$type]${_selectedRole!['rolename'] ?? ''}';
  }

  String get _authRangeLabel {
    final list = _form['sysUserStoreList'] as List? ?? [];
    if (list.isEmpty) return '';
    return list.map((e) => e is Map ? e['name']?.toString() ?? '' : '').join(', ');
  }

  String get _colsetflagLabel {
    final id = _form['colsetflag'] ?? 1;
    return _colsetflagList.firstWhere((e) => e['id'] == id,
        orElse: () => _colsetflagList.first)['label']! as String;
  }

  String get _custupdateflagLabel {
    final id = _form['custupdateflag'] ?? 0;
    return _custupdateflagList.firstWhere((e) => e['id'] == id,
        orElse: () => _custupdateflagList.first)['label']! as String;
  }

  // ============ 选择器弹窗 ============
  void _showRolePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 50,
                child: Row(children: [
                  const SizedBox(width: 48),
                  const Expanded(
                    child: Text('选择角色',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                  ),
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ..._roleList.map((role) {
                final selected = role['roleid']?.toString() == _form['roleid']?.toString();
                final type = role['roletype'] == 0 ? '集团' : '门店';
                final label = '[$type]${role['rolename'] ?? ''}';
                return GestureDetector(
                  onTap: () => _selectRole(role),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(label,
                            style: TextStyle(
                              fontSize: 14,
                              color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                            )),
                      ),
                      if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectAuthRange() async {
    final result = await SelectStorePage.show(context, showAll: true);
    if (result != null && mounted) {
      setState(() {
        final id = result['storeid']?.toString() ?? '';
        final name = result['storename']?.toString() ?? '';
        if (id.isNotEmpty) {
          _form['sysUserStoreList'] = [
            ...(_form['sysUserStoreList'] as List? ?? []),
            {'sid': id, 'name': name}
          ];
        }
      });
    }
  }

  void _showOptionPicker(String title, List<Map<String, dynamic>> options, dynamic currentValue,
      void Function(dynamic) onSelect) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 50,
                child: Row(children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                  ),
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ...options.map((opt) {
                final selected = opt['id'] == currentValue;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelect(opt['id']);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(opt['label'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                            )),
                      ),
                      if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ============ 复用组件 ============
  Widget _sectionCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(children: children),
    );
  }

  Widget _inputRow(String label, String key,
      {bool readOnly = false,
      bool obscure = false,
      String? suffix,
      String? placeholder,
      TextInputType? keyboard,
      VoidCallback? onFocused}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
        Expanded(
          child: Focus(
            onFocusChange: (hasFocus) {
              if (hasFocus && onFocused != null) onFocused();
            },
            child: TextField(
              controller: _controller(key),
              readOnly: readOnly,
              obscureText: obscure,
              keyboardType: keyboard,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: placeholder ?? '请输入',
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                suffixText: suffix,
                suffixStyle: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
              ),
              onChanged: (v) {
                _form[key] = v;
                if (key == 'pwd') _pwdModified = true;
              },
            ),
          ),
        ),
      ]),
    );
  }

  Widget _selectorRow(String label, String value, {String? placeholder, VoidCallback? onTap}) {
    final displayText = value.isNotEmpty ? value : (placeholder ?? '请选择');
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
          Expanded(
            child: Text(displayText,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: value.isNotEmpty ? const Color(0xFF333333) : const Color(0xFF999999),
                )),
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right, size: 20, color: Color(0xFFBEBDBE)),
            ),
        ]),
      ),
    );
  }

  Widget _switchRow(String label, bool value,
      {bool disabled = false, ValueChanged<bool>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
        const Spacer(),
        Switch(
          value: value,
          onChanged: disabled ? null : onChanged,
        ),
      ]),
    );
  }

  Widget _checkboxGrid(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: children.map((c) => Expanded(child: c)).toList(),
      ),
    );
  }

  Widget _cbItem(String label, String key) {
    final val = (_form[key] ?? 0) == 1;
    return GestureDetector(
      onTap: () => setState(() => _form[key] = val ? 0 : 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: val,
              onChanged: (v) => setState(() => _form[key] = (v ?? false) ? 1 : 0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }
}
