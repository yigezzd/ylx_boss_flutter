import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/members/basic/pay.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';

/// 会员开卡/编辑页 —— 对齐 boss 项目 subs/member/members/add.vue + basis.vue
///
/// [isAdd] = 1 新增（会员开卡），2 编辑（会员编辑）
/// 权限点：010703 保存
class MemberAddPage extends StatefulWidget {
  const MemberAddPage({super.key, required this.isAdd, this.data});

  final int isAdd;

  /// 编辑时传入 {vipid, vipno}
  final Map<String, dynamic>? data;

  @override
  State<MemberAddPage> createState() => _MemberAddPageState();
}

class _MemberAddPageState extends State<MemberAddPage> {
  late int _isAdd;
  bool _saving = false;

  /// 会员档案主体（对齐 Vue queryDefault.vipInfo）
  final Map<String, dynamic> _vipInfo = {};

  /// 付费规则（viptype == 2 付费卡时使用）
  Map<String, dynamic> _vipTypeRuleSet = {};

  /// 会员标签
  List<Map<String, dynamic>> _labelInfoList = [];

  /// vipAddMoneyReq（对齐 Vue 提交结构）
  final Map<String, dynamic> _vipAddMoneyReq = {
    'saleid': '',
    'salename': '',
    'payid': '',
    'payname': '',
    'amt': 0,
    'giveamt': 0,
    'givepoint': 0,
    'authcode': '',
  };

  // ── 分类/规则数据 ──
  List<Map<String, dynamic>> _vipTypeList = [];
  List<Map<String, dynamic>> _ruleSets = [];
  int _viptype = 1;

  // ── 自定义扩展字段（vipSet/getVipMoreSetList）──
  List<Map<String, dynamic>> _vipFileSetList = [];
  List<Map<String, dynamic>> _textOrDate = [];
  final Map<String, dynamic> _rules = {}; // extracolumn → title（必填项）
  final Map<String, TextEditingController> _extraControllers = {};

  // ── 表单控制器 ──
  final TextEditingController _vipnoController = TextEditingController();
  final TextEditingController _vipnameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _idcardController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  /// 生日类型：0 公历 1 农历（对齐 Vue birthonoff）
  int _birthonoff = 0;

  String get _today => _fmtDate(DateTime.now());

  @override
  void initState() {
    super.initState();
    _isAdd = widget.isAdd;
    _initVipInfoDefault();
    _getVipMoreSetList();
    if (_isAdd == 2 && widget.data != null) {
      _getVipInfo(widget.data!);
      _getVipInfoOtherData(widget.data!);
    } else {
      _getVipTypeList(1);
    }
  }

  @override
  void dispose() {
    _vipnoController.dispose();
    _vipnameController.dispose();
    _mobileController.dispose();
    _idcardController.dispose();
    _addressController.dispose();
    for (final c in _extraControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 截取 YYYY-MM-DD（对齐 Vue timeSplice）
  String _timeSplice(dynamic time) {
    final s = time?.toString() ?? '';
    if (s.isEmpty) return '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  /// 初始化默认会员信息（对齐 Vue queryDefault.vipInfo）
  void _initVipInfoDefault() {
    _vipInfo.addAll({
      'typeid': '',
      'typeidname': '',
      'vipid': '',
      'vipno': '',
      'vipname': '',
      'mobile': '',
      'address': '',
      'password': '',
      'sex': '男',
      'idcardno': '',
      'validflag': 0,
      'overflag': 0,
      'overmoney': 0,
      'nowpoint': 0,
      'nowmoney': 0,
      'pocketmoney': 0,
      'usedate': '',
      'cardstatus': 1,
      'memo': '',
      'status': 1,
      'createtime': _today,
      'validdate': _today,
      'birthday': _today,
      'birthdaylan': '',
      'capitalmoney': 0,
      'givemoney': 0,
      'validcode': '',
      'viptype': 1,
      'additionalcardflag': 0,
      'parentcardid': '1',
    });
  }

  // ──────────── 数据加载 ────────────

  /// 编辑模式：加载会员详情（对齐 Vue add.vue getVipInfo）
  Future<void> _getVipInfo(Map<String, dynamic> params) async {
    try {
      final res = await request(
          HttpApi.vipInfoGetVipInfo,
          {
            ...params,
            'notwx': true,
          },
          true);
      final data = res['data'];
      if (data is! Map<String, dynamic> || !mounted) return;
      final Map<String, dynamic> d = Map<String, dynamic>.from(data);
      setState(() {
        _vipInfo
          ..addAll(d)
          ..['typeidname'] = d['viptypename']?.toString() ?? ''
          ..['birthday'] = _timeSplice(d['birthday'])
          ..['birthdaylan'] = _timeSplice(d['birthdaylan'])
          ..['validdate'] = _timeSplice(d['validdate'])
          ..['typeid'] = (d['viptype'] is Map ? d['viptype']['typeid']?.toString() : '') ?? '';
        if ((_vipInfo['birthday'] ?? '').toString().isEmpty &&
            (_vipInfo['birthdaylan'] ?? '').toString().isNotEmpty) {
          _birthonoff = 1;
        }
        _vipnoController.text = _vipInfo['vipno']?.toString() ?? '';
        _vipnameController.text = _vipInfo['vipname']?.toString() ?? '';
        _mobileController.text = _vipInfo['mobile']?.toString() ?? '';
        _idcardController.text = _vipInfo['idcardno']?.toString() ?? '';
        _addressController.text = _vipInfo['address']?.toString() ?? '';
        _syncExtraControllers();
      });
      _getVipTypeList(2);
    } catch (_) {}
  }

  /// 编辑模式：加载会员标签等附属数据（对齐 Vue getVipInfoOtherData）
  Future<void> _getVipInfoOtherData(Map<String, dynamic> params) async {
    try {
      final res = await request(HttpApi.vipInfoGetVipInfoOtherData, params);
      final data = res['data'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() {
          final labels = data['labelInfoList'] as List? ?? [];
          _labelInfoList = labels.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  /// 加载会员分类列表（对齐 Vue basis.vue getVipTypeList）
  ///
  /// [initMode] 1=新增（自动选中第一个分类并取卡号） 2=编辑（仅匹配回显）
  Future<void> _getVipTypeList(int initMode) async {
    try {
      final res = await request(HttpApi.vipTypeGetVipTypeList, {
        'field': 'name',
        'type': 'asc',
        'is_page': 0,
      });
      final data = res['data'];
      final list = (data is Map<String, dynamic> ? data['list'] as List? : data as List?) ?? [];
      if (!mounted) return;
      setState(() => _vipTypeList = list.cast<Map<String, dynamic>>());

      if (initMode == 1 && _vipTypeList.isNotEmpty) {
        final first = _vipTypeList.first;
        setState(() {
          _vipInfo['typeid'] = first['typeid']?.toString() ?? '';
          _vipInfo['typeidname'] = first['name']?.toString() ?? '';
        });
        _getVipNo(first['code']?.toString() ?? '');
      }

      // 匹配当前分类，联动 viptype / cardstatus / usedate
      for (final it in _vipTypeList) {
        if (it['typeid']?.toString() == _vipInfo['typeid']?.toString()) {
          final vt = it['viptype'] is num ? (it['viptype'] as num).toInt() : 1;
          setState(() {
            _viptype = vt;
            _vipInfo['viptype'] = vt;
            if (vt == 2) {
              if (initMode == 1) {
                _vipInfo['usedate'] = '';
                _vipInfo['cardstatus'] = 0;
              }
              _getVipTypeInfo(it);
            } else {
              _vipInfo['usedate'] = _today;
              _vipInfo['cardstatus'] = 1;
            }
          });
          break;
        }
      }
    } catch (_) {}
  }

  /// 付费卡分类：加载付费规则 ruleSets（对齐 Vue getVipTypeInfo）
  Future<void> _getVipTypeInfo(Map<String, dynamic> it) async {
    try {
      final res = await request(HttpApi.vipTypeGetVipTypeInfo, {
        'typeid': it['typeid'],
      });
      final data = res['data'];
      final sets = (data is Map<String, dynamic> ? data['ruleSets'] as List? : data as List?) ?? [];
      if (!mounted) return;
      setState(() => _ruleSets = sets.cast<Map<String, dynamic>>());
      if (_ruleSets.isNotEmpty) {
        final matched = _ruleSets
            .where((e) => e['validcode']?.toString() == _vipInfo['validcode']?.toString())
            .toList();
        if (matched.isNotEmpty) {
          setState(() => _vipTypeRuleSet = matched.first);
        } else {
          _selectRuleFn(_ruleSets.first);
        }
      }
    } catch (_) {}
  }

  /// 获取会员卡号（对齐 Vue getVipNo）
  Future<void> _getVipNo(String typecode) async {
    try {
      final res = await request(HttpApi.vipInfoGetVipNo, {'typecode': typecode});
      if (!mounted) return;
      final vipno = res['data']?.toString() ?? '';
      setState(() {
        _vipInfo['vipno'] = vipno;
        _vipnoController.text = vipno;
      });
    } catch (_) {}
  }

  /// 加载会员档案自定义扩展字段（对齐 Vue getVipMoreSetList）
  Future<void> _getVipMoreSetList() async {
    try {
      final res = await request(HttpApi.vipSetGetVipMoreSetList, <String, dynamic>{});
      final data = res['data'];
      final list = (data is List ? data : <dynamic>[]);
      if (!mounted) return;
      setState(() {
        _vipFileSetList = list.cast<Map<String, dynamic>>();
        _textOrDate = _vipFileSetList
            .where((it) =>
                _toInt(it['coltype']) == 1 &&
                _toInt(it['status']) == 1 &&
                _toInt(it['onlinestatus']) == 1)
            .toList();
        // 必填规则：notnull==1 && status==1 && onlinestatus==1
        for (final item in _vipFileSetList) {
          if (_toInt(item['notnull']) == 1 &&
              _toInt(item['status']) == 1 &&
              _toInt(item['onlinestatus']) == 1) {
            final column = item['extracolumn']?.toString() ?? '';
            _rules[column] = item['title']?.toString() ?? item['extratext']?.toString() ?? column;
          }
        }
        _syncExtraControllers();
      });
    } catch (_) {}
  }

  int _toInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  /// 为文本型扩展字段创建/同步控制器
  void _syncExtraControllers() {
    for (final item in _textOrDate) {
      if (_toInt(item['columntype']) != 1) continue;
      final column = item['extracolumn']?.toString() ?? '';
      final value = _vipInfo[column]?.toString() ?? '';
      final existing = _extraControllers[column];
      if (existing == null) {
        _extraControllers[column] = TextEditingController(text: value);
      } else if (existing.text != value && existing.text.isEmpty) {
        existing.text = value;
      }
    }
  }

  /// 编辑模式下字段是否禁止修改（对齐 Vue isrules：modify==0）
  bool _isRules(String column) {
    return _isAdd == 2 &&
        _vipFileSetList.any(
            (item) => item['extracolumn']?.toString() == column && _toInt(item['modify']) == 0);
  }

  // ──────────── 交互逻辑 ────────────

  /// 选择会员分类（对齐 Vue selectCom → onChangeType）
  Future<void> _selectVipType() async {
    final item = await CommonSelectSheet.show(
      context,
      title: '选择会员分类',
      searchHint: '输入分类名称/编码',
      idField: 'typeid',
      initialSelectedId: _vipInfo['typeid']?.toString(),
      fetchData: (search, page) async {
        final res = await request(HttpApi.vipTypeGetVipTypeList, {
          'field': 'name',
          'type': 'asc',
          'is_page': 1,
          'page': page,
          'pagesize': 50,
          'cond': search,
        });
        final data = res['data'];
        return data is Map<String, dynamic> ? data : {'list': data};
      },
    );
    if (item != null && mounted) {
      setState(() {
        _vipInfo['typeidname'] = item['name']?.toString() ?? '';
        _vipInfo['typeid'] = item['typeid']?.toString() ?? '';
        _vipInfo['viptype'] = item['viptype'];
      });
      _addvipTypeChanges(item);
    }
  }

  /// 分类变更联动（对齐 Vue addvipTypeChanges）
  void _addvipTypeChanges(Map<String, dynamic> item) {
    final validdays = int.tryParse(item['validdays']?.toString() ?? '') ?? 0;
    setState(() {
      _vipInfo['validflag'] = validdays > 0 ? 1 : 0;
      // 有效期 = 当前日期 + validdays 天
      _vipInfo['validdate'] = _fmtDate(DateTime.now().add(Duration(days: validdays)));
    });
    for (final it in _vipTypeList) {
      if (it['typeid']?.toString() == item['typeid']?.toString()) {
        final vt = it['viptype'] is num ? (it['viptype'] as num).toInt() : 1;
        setState(() {
          _viptype = vt;
          _vipInfo['viptype'] = vt;
          if (vt == 2) {
            _vipInfo['usedate'] = '';
            _vipInfo['cardstatus'] = 0;
            _getVipTypeInfo(it);
          } else {
            _vipInfo['usedate'] = _today;
            _vipInfo['cardstatus'] = 1;
          }
        });
        break;
      }
    }
  }

  /// 选择付费规则（对齐 Vue staticSelectCom → selectruleFn）
  Future<void> _selectRuleSet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RuleSetSheet(ruleSets: _ruleSets, current: _vipTypeRuleSet),
    );
    if (result != null) _selectRuleFn(result);
  }

  void _selectRuleFn(Map<String, dynamic> e) {
    setState(() {
      if (_isAdd == 1) {
        _vipInfo['nowmoney'] = e['nowmoney'] ?? 0;
      }
      _vipInfo['validcode'] = e['validcode'] ?? '';
      _vipTypeRuleSet = e;
    });
  }

  /// 性别选择（对齐 Vue tm-action-menu sex）
  void _selectSex() {
    if (_isRules('sex')) return;
    _showActionSheet(
      title: '性别',
      options: const ['女', '男'],
      active: _vipInfo['sex'] == '女' ? 0 : 1,
      onChanged: (index) => setState(() => _vipInfo['sex'] = index == 0 ? '女' : '男'),
    );
  }

  /// 生日类型切换（对齐 Vue onChangebirthday）
  void _selectBirthdayType() {
    _showActionSheet(
      title: '生日类型',
      options: const ['公历', '农历'],
      active: _birthonoff,
      onChanged: (index) {
        setState(() {
          _birthonoff = index;
          if (index == 1) {
            _vipInfo['birthdaylan'] =
                (_vipInfo['birthday'] ?? '').toString().isEmpty ? _today : _vipInfo['birthday'];
            _vipInfo['birthday'] = '';
          } else {
            _vipInfo['birthday'] = (_vipInfo['birthdaylan'] ?? '').toString().isEmpty
                ? _today
                : _vipInfo['birthdaylan'];
            _vipInfo['birthdaylan'] = '';
          }
        });
      },
    );
  }

  /// 有效期类型选择（对齐 Vue onChangeperiod）
  void _selectPeriod() {
    _showActionSheet(
      title: '有效日期',
      options: const ['长期有效', '有效期'],
      active: _toInt(_vipInfo['validflag']),
      onChanged: (index) => setState(() => _vipInfo['validflag'] = index),
    );
  }

  /// 通用底部菜单（对齐 Vue tm-action-menu）
  void _showActionSheet({
    required String title,
    required List<String> options,
    required int active,
    required ValueChanged<int> onChanged,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
            ),
            const Divider(height: 1),
            for (int i = 0; i < options.length; i++)
              ListTile(
                title: Text(options[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        color: active == i ? const Color(0xFF006EFF) : const Color(0xFF333333))),
                onTap: () {
                  Navigator.pop(ctx);
                  onChanged(i);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 选择日期（生日/有效期/日期型扩展字段）
  Future<void> _pickDate(String key) async {
    final current = DateTime.tryParse((_vipInfo[key] ?? '').toString()) ?? DateTime.now();
    final picked = await showCommonDatePicker(context, initial: current);
    if (picked != null && mounted) {
      setState(() => _vipInfo[key] = _fmtDate(picked));
    }
  }

  /// 选择会员标签（多选，对齐 Vue selectCom multiple）
  Future<void> _selectTags() async {
    final result = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _TagSelectSheet(initialSelected: _labelInfoList),
    );
    if (result != null && mounted) {
      setState(() => _labelInfoList = result);
    }
  }

  /// 手机号失焦校验（对齐 Vue iphoneBlur）
  void _onMobileBlur() {
    final mobile = _mobileController.text.trim();
    if (mobile.isEmpty) return;
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(mobile)) {
      Toast.show('手机号格式不正确');
    }
  }

  /// 身份证号输入 → 自动识别生日（对齐 Vue shenfenzheng）
  void _onIdcardChanged(String idCard) {
    if (idCard.isEmpty) return;
    String birthday = '';
    if (idCard.length == 15) {
      birthday = '19${idCard.substring(6, 12)}';
    } else if (idCard.length == 18) {
      birthday = idCard.substring(6, 14);
    }
    if (birthday.isNotEmpty) {
      birthday =
          '${birthday.substring(0, 4)}-${birthday.substring(4, 6)}-${birthday.substring(6, 8)}';
      setState(() {
        _birthonoff = 0;
        _vipInfo['birthday'] = birthday;
      });
    }
  }

  // ──────────── 保存 ────────────

  /// 表单校验（对齐 Vue validateForm）
  bool _validateForm() {
    // 先同步扩展字段输入值
    for (final entry in _extraControllers.entries) {
      _vipInfo[entry.key] = entry.value.text.trim();
    }
    for (final entry in _rules.entries) {
      final value = _vipInfo[entry.key];
      if (value == null || value.toString().trim().isEmpty) {
        Toast.show('请选择${entry.value}');
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving) return;
    if ((_vipInfo['typeid'] ?? '').toString().isEmpty) {
      Toast.show('请选择会员分类');
      return;
    }
    if (!_validateForm()) return;

    // 付费卡且未发行 → 先进入收款页（对齐 Vue viptype==2 && cardstatus==0）
    if (_toInt(_vipInfo['viptype']) == 2 && _toInt(_vipInfo['cardstatus']) == 0) {
      final payResult = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          settings: const RouteSettings(name: '/业务/会员/售卡收款'),
          builder: (_) => MemberPayPage(query: {
            'vipInfo': Map<String, dynamic>.from(_vipInfo),
            'vipTypeRuleSet': Map<String, dynamic>.from(_vipTypeRuleSet),
            'labelInfoList': List<Map<String, dynamic>>.from(_labelInfoList),
            'vipAddMoneyReq': Map<String, dynamic>.from(_vipAddMoneyReq),
          }),
        ),
      );
      if ((payResult ?? false) && mounted) {
        Navigator.pop(context, true);
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await request(
          HttpApi.vipInfoAdd,
          {
            'vipInfo': _vipInfo,
            'vipTypeRuleSet': _vipTypeRuleSet,
            'labelInfoList': _labelInfoList,
            'vipAddMoneyReq': _vipAddMoneyReq,
          },
          true);
      if (!mounted) return;
      Toast.show('保存档案成功，');
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ──────────── UI ────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(_isAdd == 1 ? '会员开卡' : '会员编辑',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              cacheExtent: 800,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Column(children: [
                    // 会员分类
                    _buildSelectRow(
                      label: '会员分类',
                      required: true,
                      value: (_vipInfo['typeidname'] ?? '').toString().isEmpty
                          ? '请选择'
                          : _vipInfo['typeidname'].toString(),
                      onTap: _selectVipType,
                    ),
                    // 付费规则（付费卡且新增时显示）
                    if (_viptype == 2 && _isAdd == 1)
                      _buildSelectRow(
                        label: '付费规则',
                        value: (_vipTypeRuleSet['validname'] ?? '').toString().isEmpty
                            ? '请选择'
                            : _vipTypeRuleSet['validname'].toString(),
                        onTap: _selectRuleSet,
                      ),
                    // 会员卡号
                    _buildInputRow(
                      label: '会员卡号',
                      controller: _vipnoController,
                      enabled: _isAdd != 2,
                      onChanged: (v) => _vipInfo['vipno'] = v,
                    ),
                    // 会员姓名 + 性别
                    _buildNameRow(),
                    // 手机号码
                    _buildInputRow(
                      label: '手机号码',
                      controller: _mobileController,
                      enabled: !_isRules('mobile'),
                      hint: '请输入手机号',
                      keyboardType: TextInputType.phone,
                      onChanged: (v) => _vipInfo['mobile'] = v,
                      onEditingComplete: _onMobileBlur,
                    ),
                    // 会员生日
                    _buildBirthdayRow(),
                    // 身份证号
                    _buildInputRow(
                      label: '身份证号',
                      controller: _idcardController,
                      enabled: !_isRules('idcardno'),
                      hint: '请输入身份证号',
                      onChanged: (v) {
                        _vipInfo['idcardno'] = v;
                        _onIdcardChanged(v);
                      },
                    ),
                    // 有效日期
                    _buildValiddateRow(),
                    // 联系地址
                    _buildInputRow(
                      label: '联系地址',
                      controller: _addressController,
                      enabled: !_isRules('address'),
                      hint: '请输入联系地址',
                      onChanged: (v) => _vipInfo['address'] = v,
                    ),
                    // 会员标签
                    _buildSelectRow(
                      label: '会员标签',
                      value: _labelInfoList.isEmpty
                          ? '请选择'
                          : _labelInfoList.map((e) => e['name']).join('、'),
                      onTap: _selectTags,
                    ),
                    // 自定义扩展字段
                    for (final item in _textOrDate) _buildExtraRow(item),
                    // 售卡金额（付费卡）
                    if (_viptype == 2)
                      _buildTextRow(
                        label: '售卡金额',
                        value: MathUtils.formatDecimal(3, _vipTypeRuleSet['payamt']),
                      ),
                    // 初始余额
                    _buildTextRow(
                      label: '初始余额',
                      value: MathUtils.formatDecimal(3, _vipInfo['nowmoney']),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          // 底部保存按钮（对齐 Vue 底部 fixed 按钮，权限 010703）
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final hasPerm = _hasSavePerm();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: hasPerm && !_saving ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006EFF),
              disabledBackgroundColor: const Color(0xFFDDDDDD),
              foregroundColor: Colors.white,
              disabledForegroundColor: const Color(0xFF999999),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('保存', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }

  bool _hasSavePerm() {
    // 权限 010703（对齐 Vue permission('010703')）
    return PermissionUtils.hasPermission('010703');
  }

  // ──────────── 表单行 ────────────

  Widget _buildRowShell({
    required String label,
    bool required = false,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Row(
              children: [
                if (required) const Text('* ', style: TextStyle(color: Colors.red, fontSize: 15)),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// 选择型行（右箭头）
  Widget _buildSelectRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool required = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: _buildRowShell(
        label: label,
        required: required,
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  color: value == '请选择' ? const Color(0xFF999999) : const Color(0xFF333333),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFBEBDBE)),
          ],
        ),
      ),
    );
  }

  /// 输入型行
  Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    String hint = '请输入',
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
    VoidCallback? onEditingComplete,
  }) {
    return _buildRowShell(
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onEditingComplete: () {
          FocusScope.of(context).unfocus();
          onEditingComplete?.call();
        },
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 15,
          color: enabled ? const Color(0xFF333333) : const Color(0xFF999999),
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: enabled ? hint : '',
          hintStyle: const TextStyle(fontSize: 15, color: Color(0xFFCCCCCC)),
        ),
      ),
    );
  }

  /// 只读文本行
  Widget _buildTextRow({required String label, required String value}) {
    return _buildRowShell(
      label: label,
      child: Text(value,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
    );
  }

  /// 会员姓名行（右侧性别选择，对齐 Vue codeicon）
  Widget _buildNameRow() {
    return _buildRowShell(
      label: '会员姓名',
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _vipnameController,
              enabled: !_isRules('vipname'),
              onChanged: (v) => _vipInfo['vipname'] = v,
              style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: '请输入',
                hintStyle: TextStyle(fontSize: 15, color: Color(0xFFCCCCCC)),
              ),
            ),
          ),
          GestureDetector(
            onTap: _selectSex,
            child: Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Color(0xFFE6E6E6))),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_vipInfo['sex']?.toString() ?? '男',
                      style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 会员生日行（日期 + 公历/农历切换，对齐 Vue）
  Widget _buildBirthdayRow() {
    final isLunar = _birthonoff == 1;
    final dateValue = isLunar
        ? (_vipInfo['birthdaylan'] ?? '').toString()
        : (_vipInfo['birthday'] ?? '').toString();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isRules('birthday') ? null : () => _pickDate(isLunar ? 'birthdaylan' : 'birthday'),
      child: _buildRowShell(
        label: '会员生日',
        child: Row(
          children: [
            Expanded(
              child: Text(
                dateValue.isEmpty ? '请选择' : dateValue,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  color: dateValue.isEmpty ? const Color(0xFF999999) : const Color(0xFF333333),
                ),
              ),
            ),
            GestureDetector(
              onTap: _isRules('birthday') ? null : _selectBirthdayType,
              child: Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: Color(0xFFE6E6E6))),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isLunar ? '农历' : '公历',
                        style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 有效日期行（长期有效/有效期，对齐 Vue）
  Widget _buildValiddateRow() {
    final validflag = _toInt(_vipInfo['validflag']);
    final validdate = (_vipInfo['validdate'] ?? '').toString();
    return _buildRowShell(
      label: '有效日期',
      child: Row(
        children: [
          if (validflag == 1)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickDate('validdate'),
                child: Text(
                  validdate.isEmpty ? '请选择' : validdate,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    color: validdate.isEmpty ? const Color(0xFF999999) : const Color(0xFF333333),
                  ),
                ),
              ),
            )
          else
            const Expanded(child: SizedBox()),
          GestureDetector(
            onTap: _selectPeriod,
            child: Container(
              padding: EdgeInsets.only(left: validflag == 1 ? 10 : 0),
              decoration: BoxDecoration(
                border: validflag == 1
                    ? const Border(left: BorderSide(color: Color(0xFFE6E6E6)))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    validflag == 1 ? '有效期' : '长期有效',
                    style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 自定义扩展字段行（对齐 Vue textORdate：columntype 1=文本 2=日期）
  Widget _buildExtraRow(Map<String, dynamic> item) {
    final column = item['extracolumn']?.toString() ?? '';
    final title = '${item['title']?.toString() ?? item['extratext']?.toString() ?? ''}：';
    final required = _rules.containsKey(column);
    if (_toInt(item['columntype']) == 2) {
      final value = (_vipInfo[column] ?? '').toString();
      return _buildSelectRow(
        label: title,
        required: required,
        value: value.isEmpty ? '请选择' : value,
        onTap: () async {
          final current = DateTime.tryParse(value) ?? DateTime.now();
          final picked = await showCommonDatePicker(context, initial: current);
          if (picked != null && mounted) {
            setState(() => _vipInfo[column] = _fmtDate(picked));
          }
        },
      );
    }
    final controller = _extraControllers.putIfAbsent(column, () => TextEditingController());
    return _buildRowShell(
      label: title,
      required: required,
      child: TextField(
        controller: controller,
        onChanged: (v) => _vipInfo[column] = v,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: '请输入内容',
          hintStyle: TextStyle(fontSize: 15, color: Color(0xFFCCCCCC)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// 付费规则选择抽屉（对齐 Vue staticSelectCom showViplabel）
// ─────────────────────────────────────────────────
class _RuleSetSheet extends StatelessWidget {
  const _RuleSetSheet({required this.ruleSets, required this.current});

  final List<Map<String, dynamic>> ruleSets;
  final Map<String, dynamic> current;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            height: 50,
            child: Center(
              child: Text('选择付费规则',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: ruleSets.length,
              itemBuilder: (ctx, index) {
                final item = ruleSets[index];
                final selected = item['validcode']?.toString() == current['validcode']?.toString();
                return ListTile(
                  title: Text(
                    item['validname']?.toString() ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                    ),
                  ),
                  subtitle: Text(
                    '售卡金额：${MathUtils.formatDecimal(3, item['payamt'])}  开卡余额：${MathUtils.formatDecimal(3, item['nowmoney'])}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                  ),
                  trailing:
                      selected ? const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)) : null,
                  onTap: () => Navigator.pop(ctx, item),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// 会员标签多选抽屉（对齐 Vue selectCom multiple + selfList）
// ─────────────────────────────────────────────────
class _TagSelectSheet extends StatefulWidget {
  const _TagSelectSheet({required this.initialSelected});

  final List<Map<String, dynamic>> initialSelected;

  @override
  State<_TagSelectSheet> createState() => _TagSelectSheetState();
}

class _TagSelectSheetState extends State<_TagSelectSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  final Set<String> _selectedCodes = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    for (final item in widget.initialSelected) {
      _selectedCodes.add(item['code']?.toString() ?? '');
    }
    _loadTags();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final res = await request(HttpApi.labelSetGetLabelSetList, {'type': 1, 'is_page': 0});
      final data = res['data'];
      final list = (data is Map<String, dynamic> ? data['list'] as List? : data as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _all = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final search = _searchController.text.trim();
    if (search.isEmpty) return _all;
    return _all
        .where((e) =>
            (e['name']?.toString() ?? '').contains(search) ||
            (e['code']?.toString() ?? '').contains(search))
        .toList();
  }

  void _confirm() {
    final result = _all
        .where((e) => _selectedCodes.contains(e['code']?.toString()))
        .map((e) => {'code': e['code'], 'name': e['name']})
        .cast<Map<String, dynamic>>()
        .toList();
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 48),
                const Expanded(
                  child: Text('选择会员标签',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Color(0xFF999999)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 搜索框（本地过滤，对齐 Vue selfSearch + selfList）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                hintText: '输入标签名称/编码',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (ctx, index) {
                      final item = list[index];
                      final code = item['code']?.toString() ?? '';
                      final checked = _selectedCodes.contains(code);
                      return CheckboxListTile(
                        value: checked,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                        activeColor: const Color(0xFF006EFF),
                        title: Text('[${item['code'] ?? ''}]${item['name'] ?? ''}',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
                        onChanged: (v) {
                          setState(() {
                            if (v ?? false) {
                              _selectedCodes.add(code);
                            } else {
                              _selectedCodes.remove(code);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          // 底部按钮
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF333333),
                      side: const BorderSide(color: Color(0xFFDEDEDE)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('取消', style: TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006EFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('确定', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
