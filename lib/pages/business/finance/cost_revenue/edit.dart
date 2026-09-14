import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 费用收支单编辑页 —— 对齐 boss 项目 costRevenueExpensesEdit.vue
class CostRevenueEditPage extends StatefulWidget {
  const CostRevenueEditPage({super.key, this.billid = ''});

  /// 单据ID，为空表示新增
  final String billid;

  @override
  State<CostRevenueEditPage> createState() => _CostRevenueEditPageState();
}

class _CostRevenueEditPageState extends State<CostRevenueEditPage> {
  // ── 状态 ──
  bool _loading = false;
  bool _saving = false;
  Map<String, dynamic> _formData = {};

  // ── 多级审批 ──
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _reviewBillFlows = [];
  String _userCode = '';
  String _userid = '';

  // ── 表单字段 ──
  String _bsid = '';
  String _bstorename = '';
  int _billtype = 1; // 1=收入单 2=支出单 3=转账单
  String _feeitem = '';
  String _feename = '';
  String _handlerid = '';
  String _handlername = '';
  String _payway = '';
  String _payname = '';
  String _bankid = '';
  String _bankidname = '';
  String _bankidother = '';
  String _bankidothername = '';
  String _paytime = ''; // 收支日期

  // ── Controllers ──
  final TextEditingController _remarkCtl = TextEditingController();
  final TextEditingController _payamtCtl = TextEditingController();

  // ── FocusNodes（失焦触发格式化，对齐 Vue @blur）──
  late final FocusNode _payamtFocus = FocusNode()
    ..addListener(() {
      if (!_payamtFocus.hasFocus && mounted) _payamtBlur();
    });

  // ── 枚举 ──
  int get _signflag => int.tryParse(_formData['signflag']?.toString() ?? '') ?? 0;
  bool get _isEdit =>
      widget.billid.isNotEmpty || (_formData['billid']?.toString().isNotEmpty ?? false);
  bool get _isReadonly => _signflag == 1 || _signflag == 2 || _signflag == -1;
  String get _billno => _formData['billno']?.toString() ?? '';

  // ── 多级审批计算 ──
  bool get _isAdmin => _userCode == '1001';

  bool get _bolHandleT {
    if (_isAdmin) return true;
    return _reviewFlowUsers.any((item) => item['userid']?.toString() == _userid);
  }

  bool get _bolHandleTT {
    if (_isAdmin) return true;
    if (_reviewFlowUsers.isEmpty) return true;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return firstIndex <= 1;
  }

  /// reviewsignflag==2 表示单据处于撤回待处理态
  bool get _isWithdrawPending => _formData['reviewsignflag']?.toString() == '2';

  @override
  void initState() {
    super.initState();
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _userid = userMap['userid']?.toString() ?? '';
        _userCode = userMap['code']?.toString() ?? '';
      }
    } catch (_) {}
    if (_isEdit) _loadData();
  }

  @override
  void dispose() {
    _remarkCtl.dispose();
    _payamtCtl.dispose();
    _payamtFocus.dispose();
    super.dispose();
  }

  // =================== 数据加载 ===================

  Future<void> _loadData() async {
    if (_loading) return;
    final billid =
        widget.billid.isNotEmpty ? widget.billid : (_formData['billid']?.toString() ?? '');
    if (billid.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await request(HttpApi.financeCostRevenueGetInfo, {'billid': billid});
      final data = res['data'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() {
          _formData = Map<String, dynamic>.from(data);
          _bsid = _str(data['bsid']);
          _bstorename = _str(data['bstorename']);
          _billtype = int.tryParse(_str(data['billtype'])) ?? 1;
          _feeitem = _str(data['feeitem']);
          _feename = _str(data['feename']);
          _handlerid = _str(data['handlerid']);
          _handlername = _str(data['handlername']);
          _payway = _str(data['payway']);
          _payname = _str(data['payname']);
          _bankid = _str(data['bankid']);
          _bankidname = _str(data['bankidname']);
          _bankidother = _str(data['bankidother']);
          _bankidothername = _str(data['bankidothername']);
          _paytime = _str(data['paytime']);
          _remarkCtl.text = _str(data['remark']);
          _payamtCtl.text = MathUtils.formatDecimal(3, double.tryParse(_str(data['payamt'])) ?? 0);
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
        });
      }
    } catch (_) {
      if (mounted) Toast.show('加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =================== 选择器 ===================

  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(context, initialSelectedId: _bsid);
    if (result != null && mounted) {
      setState(() {
        _bsid = result['storeid']?.toString() ?? '';
        _bstorename = result['storename']?.toString() ?? '';
      });
    }
  }

  Future<void> _selectFeeitem() async {
    final result = await CommonSelectSheet.show(
      context,
      title: '选择收支项目',
      searchHint: '输入收支编码/名称',
      fetchData: (search, page) => request(HttpApi.feeitemGetList, {
        'cond': search,
        'is_page': 1,
        'page': page,
        'pagesize': 20,
      }).then((r) {
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      idField: 'itemid',
      nameField: 'itemname',
      showAll: true,
    );
    if (result != null && mounted) {
      setState(() {
        _feeitem = result['itemid']?.toString() ?? '';
        _feename = result['itemname']?.toString() ?? '';
      });
    }
  }

  Future<void> _selectHandler() async {
    final result = await CommonSelectSheet.show(
      context,
      title: '选择经手人',
      searchHint: '输入经手人名称/编码',
      fetchData: (search, page) => request(HttpApi.sysUserList, {
        'cond': search,
        'is_page': 1,
        'page': page,
        'pagesize': 20,
      }).then((r) {
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      idField: 'userid',
      showAll: true,
    );
    if (result != null && mounted) {
      setState(() {
        _handlerid = result['userid']?.toString() ?? '';
        _handlername = result['name']?.toString() ?? '';
      });
    }
  }

  Future<void> _selectPayway() async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      context,
      title: '选择收支方式',
      searchHint: '输入收支方式名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.paywayGetList, <String, dynamic>{});
          final data = r['data'];
          if (data is List) {
            cache = data.cast<Map<String, dynamic>>();
          } else if (data is Map<String, dynamic> && data['list'] is List) {
            cache = (data['list'] as List).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'payid',
      showAll: true,
    );
    if (result != null && mounted) {
      setState(() {
        _payway = result['payid']?.toString() ?? '';
        _payname = result['name']?.toString() ?? '';
      });
    }
  }

  Future<void> _selectBank() async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      context,
      title: '选择转入账户',
      searchHint: '输入账户名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.pluginsGet, {
            'plugins': ['bank'],
          });
          final data = r['data'];
          if (data is Map<String, dynamic> && data['bank'] is Map<String, dynamic>) {
            final bk = data['bank'] as Map<String, dynamic>;
            cache = ((bk['list'] as List?) ?? []).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'bankid',
      showAll: true,
    );
    if (result != null && mounted) {
      setState(() {
        _bankid = result['bankid']?.toString() ?? '';
        _bankidname = result['name']?.toString() ?? '';
      });
    }
  }

  Future<void> _selectBankOther() async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      context,
      title: '选择转出账户',
      searchHint: '输入账户名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.pluginsGet, {
            'plugins': ['bank'],
          });
          final data = r['data'];
          if (data is Map<String, dynamic> && data['bank'] is Map<String, dynamic>) {
            final bk = data['bank'] as Map<String, dynamic>;
            cache = ((bk['list'] as List?) ?? []).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'bankid',
      showAll: true,
    );
    if (result != null && mounted) {
      setState(() {
        _bankidother = result['bankid']?.toString() ?? '';
        _bankidothername = result['name']?.toString() ?? '';
      });
    }
  }

  Future<void> _selectPaytime() async {
    final initial = _paytime.isNotEmpty ? _paytime : DateTime.now().toString().substring(0, 19);
    final picked = await showCommonDateTimePicker(context, initial: initial);
    if (picked != null && mounted) {
      setState(() => _paytime = picked);
    }
  }

  // =================== 结算金额格式化 ===================

  void _payamtBlur() {
    final v = double.tryParse(_payamtCtl.text) ?? 0;
    _payamtCtl.text = MathUtils.formatDecimal(3, v);
  }

  // =================== 保存 / 审核 / 删除 / 作废 ===================

  Future<bool> _validate() async {
    if (_bsid.isEmpty) {
      Toast.show('请选择机构');
      return false;
    }
    if (_feeitem.isEmpty) {
      Toast.show('请选择收支项目');
      return false;
    }
    if (_payamtCtl.text.isEmpty) {
      Toast.show('请输入收支金额');
      return false;
    }
    if (_payway.isEmpty) {
      Toast.show('请选择收支方式');
      return false;
    }
    if ((_billtype == 1 || _billtype == 3) && _bankid.isEmpty) {
      Toast.show('请选择转入账户');
      return false;
    }
    if ((_billtype == 2 || _billtype == 3) && _bankidother.isEmpty) {
      Toast.show('请选择转出账户');
      return false;
    }
    return true;
  }

  Map<String, dynamic> _buildParams() {
    String bankid = _bankid;
    String bankidname = _bankidname;
    String bankidother = _bankidother;
    String bankidothername = _bankidothername;
    if (_billtype == 1) {
      bankidother = '';
      bankidothername = '';
    } else if (_billtype == 2) {
      bankid = '';
      bankidname = '';
    }
    return {
      if (_isEdit) 'billid': widget.billid.isNotEmpty ? widget.billid : _formData['billid'],
      'bsid': _bsid,
      'bstorename': _bstorename,
      'billtype': _billtype,
      'feeitem': _feeitem,
      'feename': _feename,
      'handlerid': _handlerid,
      'handlername': _handlername,
      'remark': _remarkCtl.text,
      'payamt': _payamtCtl.text,
      'payway': _payway,
      'payname': _payname,
      'bankid': bankid,
      'bankidname': bankidname,
      'bankidother': bankidother,
      'bankidothername': bankidothername,
      if (_paytime.isNotEmpty) 'paytime': _paytime,
    };
  }

  Future<void> _handleSave([int sign = 0]) async {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('015504', showTip: false)) {
        Toast.show('你无权编辑费用收支单，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('015503', showTip: false)) {
        Toast.show('你无权新增费用收支单，请在后台修改权限');
        return;
      }
    }
    final ok = await _validate();
    if (!ok) return;

    setState(() => _saving = true);
    try {
      final params = _buildParams();
      final url = _isEdit ? HttpApi.financeCostRevenueUpdate : HttpApi.financeCostRevenueAdd;
      final res = await request(url, params);
      final data = res['data'];
      if (mounted) {
        final isNew = !_isEdit;
        if (isNew && data is Map<String, dynamic>) {
          _formData = Map<String, dynamic>.from(data);
        }
        // 每次保存都更新审批流数据（对齐 Vue: reviewBillFlows/reviewFlowUsers）
        if (data is Map<String, dynamic>) {
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
        }
        Toast.show('保存成功');
        if (sign == 1) {
          _handleSignAfterSave(data is Map<String, dynamic> ? data : null);
        }
      }
    } catch (_) {
      if (mounted) Toast.show('保存失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleSignAfterSave(Map<String, dynamic>? savedData, {bool isWithdraw = false}) {
    if (_reviewFlowUsers.isNotEmpty && !_bolHandleT) {
      Toast.show('您不属于当前审批节点的审核人！');
      return;
    }
    if (isWithdraw) {
      _doSign(isWithdraw: true);
      return;
    }
    // 多级审批：弹出审批弹窗
    if (_reviewFlowUsers.isNotEmpty) {
      _showApprovalDialog().then((approvalResult) {
        if (approvalResult != null && mounted) {
          _formData['reviewsignflag'] = approvalResult['reviewsignflag'];
          _formData['reviewremark'] = approvalResult['reviewremark'];
          _doSign();
        }
      });
    } else {
      _doSign();
    }
  }

  Future<void> _handleSign() async {
    if (!PermissionUtils.checkPermission('015506', showTip: false)) {
      Toast.show('你无权审核费用收支单，请在后台修改权限');
      return;
    }
    if (_formData.isEmpty) return;

    // 多级审批：弹出审批操作弹窗
    if (_reviewFlowUsers.isNotEmpty) {
      final approvalResult = await _showApprovalDialog();
      if (approvalResult == null || !mounted) return;
      _formData['reviewsignflag'] = approvalResult['reviewsignflag'];
      _formData['reviewremark'] = approvalResult['reviewremark'];
      _doSign();
      return;
    }

    // 无多级审批配置：简单确认
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定审核单据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;
    _doSign();
  }

  /// 执行审核操作（对齐 Vue signApi / supplier_pay _doSign）
  void _doSign({bool isWithdraw = false}) {
    if (_formData.isEmpty) return;
    final params = Map<String, dynamic>.from(_formData);
    params['signflag'] = 0;
    params['reviewremark'] = _formData['reviewremark']?.toString() ?? '';
    if (isWithdraw) {
      params['reviewsignflag'] = 2;
    } else {
      final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
      if (reviewsignflag != 0) {
        params['reviewsignflag'] = 1;
      }
    }
    setState(() => _saving = true);
    request(HttpApi.financeCostRevenueSign, params).then((_) {
      if (mounted) {
        Toast.show('审核成功');
        _loadData();
      }
    }).catchError((_) {
      if (mounted) Toast.show('审核失败');
    }).whenComplete(() {
      if (mounted) setState(() => _saving = false);
    });
  }

  /// 审批操作弹窗（通过/驳回 + 备注）
  Future<Map<String, dynamic>?> _showApprovalDialog({int defaultFlag = 1}) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ApprovalDialog(defaultFlag: defaultFlag),
    );
  }

  /// 查看审批日志弹窗
  void _showApprovalLogDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: _ApprovalLogSheet(
            reviewBillFlows: _reviewBillFlows,
            scrollController: scrollCtrl,
          ),
        ),
      ),
    );
  }

  Future<void> _handleZf() async {
    if (!PermissionUtils.checkPermission('015507', showTip: false)) {
      Toast.show('你无权反审核费用收支单，请在后台修改权限');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定反审核该单据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await request(HttpApi.financeCostRevenueFsign, _formData);
      if (mounted) {
        Toast.show('反审核成功');
        await _loadData();
      }
    } catch (_) {
      if (mounted) Toast.show('反审核失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleDelete() async {
    if (!PermissionUtils.checkPermission('015505', showTip: false)) {
      Toast.show('你无权删除费用收支单，请在后台修改权限');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定删除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await request(HttpApi.financeCostRevenueDel, {'billid': _buildBillid()});
      if (mounted) {
        Toast.show('删除成功');
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) Toast.show('删除失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleRetsign() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回单据'),
        content: const Text('撤回单据后，所有审批步骤需重新处理！是否撤回该费用收支单？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _formData['reviewsignflag'] = '2';
    });
    await _handleSave(1);
  }

  String _buildBillid() {
    return widget.billid.isNotEmpty ? widget.billid : (_formData['billid']?.toString() ?? '');
  }

  // =================== 辅助 ===================

  String _str(dynamic v) => v?.toString() ?? '';

  List<Map<String, dynamic>> _parseReviewList(dynamic val) {
    if (val is List) {
      return val
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // =================== UI ===================

  @override
  Widget build(BuildContext context) {
    String statusText;
    Color statusColor;
    if (_signflag == 1) {
      statusText = '已审核';
      statusColor = const Color(0xFF00A870);
    } else if (_signflag == 2) {
      statusText = '已驳回';
      statusColor = const Color(0xFFFF9900);
    } else if (_signflag == -1) {
      statusText = '已作废';
      statusColor = const Color(0xFFAAAAAA);
    } else {
      statusText = _isEdit ? '待审核' : '新增';
      statusColor = const Color(0xFFD54B5A);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(_isEdit ? '费用收支单详情' : '新增费用收支单',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_isEdit) _buildInfoHeader(statusText, statusColor),
                // 审批节点卡片
                if (_isEdit && (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  _buildApprovalNodeCard(),
                ],
                const SizedBox(height: 16),
                _buildSectionTitle('单据信息'),
                const SizedBox(height: 8),
                _buildFormCard([
                  _buildSelectRow('机构名称', _bstorename,
                      onTap: !_isReadonly && !_isEdit ? _selectStore : null, required: true),
                  if (_isReadonly)
                    _buildReadonlyRow('业务类型', _billtypeLabel(), required: true)
                  else
                    _buildBilltypeTagRow(),
                  _buildSelectRow('收支项目', _feename,
                      onTap: !_isReadonly ? _selectFeeitem : null, required: true),
                  _buildSelectRow('经手人', _handlername, onTap: !_isReadonly ? _selectHandler : null),
                  _buildTextInputRow('备注', _remarkCtl, enabled: !_isReadonly),
                ]),
                const SizedBox(height: 16),
                _buildSectionTitle('结算信息'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(children: [
                    _buildSettleInputRow('收支金额', _payamtCtl,
                        focusNode: _payamtFocus, enabled: !_isReadonly),
                    _buildSelectRow('收支日期', _paytime.isNotEmpty ? _paytime : '',
                        onTap: !_isReadonly ? _selectPaytime : null, placeholder: '请选择日期时间'),
                    _buildSelectRow('收支方式', _payname,
                        onTap: !_isReadonly ? _selectPayway : null, required: true),
                    if (_billtype == 1 || _billtype == 3)
                      _buildSelectRow('转入账户', _bankidname,
                          onTap: !_isReadonly ? _selectBank : null, required: true),
                    if (_billtype == 2 || _billtype == 3)
                      _buildSelectRow('转出账户', _bankidothername,
                          onTap: !_isReadonly ? _selectBankOther : null, required: true),
                  ]),
                ),
                const SizedBox(height: 80),
              ]),
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // =================== Widget Helpers ===================

  String _billtypeLabel() {
    const labels = ['收入单', '支出单', '转账单'];
    return (_billtype >= 1 && _billtype <= 3) ? labels[_billtype - 1] : '';
  }

  Widget _buildInfoHeader(String statusText, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(_billno,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(statusText,
                style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500)),
          ),
        ]),
        const SizedBox(height: 8),
        _buildInfoRow('制单信息', '${_formData['createtime'] ?? ''}  ${_formData['createname'] ?? ''}'),
        if (_signflag == 1)
          _buildInfoRow('审核信息', '${_formData['signtime'] ?? ''}  ${_formData['signname'] ?? ''}'),
      ]),
    );
  }

  static Widget _buildInfoRow(String label, String value) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text('$label：', style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
          Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
        ]));
  }

  static Widget _buildSectionTitle(String title) {
    return Row(children: [
      Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
              color: const Color(0xFF006EFF), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
    ]);
  }

  static Widget _buildFormCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE))),
      child: Column(children: children),
    );
  }

  // ── 业务类型标签行 ──
  Widget _buildBilltypeTagRow() {
    const labels = ['收入单', '支出单', '转账单'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Row(children: [
        const SizedBox(
            width: 80,
            child: Row(children: [
              Text('*', style: TextStyle(fontSize: 14, color: Color(0xFFFF4D4F))),
              Expanded(
                  child: Text('业务类型', style: TextStyle(fontSize: 14, color: Color(0xFF374151)))),
            ])),
        Expanded(
          child: Row(
            children: List.generate(3, (i) {
              final selected = _billtype == (i + 1);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _billtype = i + 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF006EFF) : Colors.white,
                      border: Border.all(
                          color: selected ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 12,
                            color: selected ? Colors.white : const Color(0xFF333333))),
                  ),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }

  // ── 选择行 ──
  Widget _buildSelectRow(String label, String value,
      {VoidCallback? onTap, String placeholder = '请选择', bool required = false}) {
    final enabled = onTap != null;
    final displayValue = value.isNotEmpty ? value : (enabled ? placeholder : '');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration:
            const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
        child: Row(children: [
          SizedBox(
              width: 80,
              child: Row(children: [
                if (required)
                  const Text('*', style: TextStyle(fontSize: 14, color: Color(0xFFFF4D4F))),
                Expanded(
                    child: Text(label,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
              ])),
          Expanded(
              child: Text(displayValue,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 14,
                      color: enabled && value.isEmpty
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF374151)))),
          if (enabled) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE))
          ],
        ]),
      ),
    );
  }

  // ── 只读行 ──
  Widget _buildReadonlyRow(String label, String value, {bool required = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Row(children: [
        SizedBox(
            width: 80,
            child: Row(children: [
              if (required)
                const Text('*', style: TextStyle(fontSize: 14, color: Color(0xFFFF4D4F))),
              Expanded(
                  child:
                      Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
            ])),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
      ]),
    );
  }

  static Widget _buildTextInputRow(String label, TextEditingController controller,
      {bool enabled = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Row(children: [
        SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
        Expanded(
            child: TextField(
          controller: controller,
          enabled: enabled,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
          decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8)),
        )),
      ]),
    );
  }

  /// 结算输入行
  Widget _buildSettleInputRow(String label, TextEditingController controller,
      {bool enabled = true, FocusNode? focusNode}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Row(children: [
        SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
        Expanded(
            child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
          decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: enabled ? '请输入' : '',
              hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
        )),
      ]),
    );
  }

  // =================== 底部按钮栏（对齐供应商结算） ===================

  Widget _buildBottomBar() {
    if (!_isEdit) return _buildNewBillButtons();
    if (_signflag == -1) return _buildVoidedButtons();
    if (_signflag == 1) return _buildSignedButtons();
    if (_signflag == 2) return _buildRejectedButtons();
    return _buildPendingButtons();
  }

  Widget _wrapBottomBar(List<Widget> children) {
    return SafeArea(
        child: Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
      child: Row(children: children),
    ));
  }

  Widget _primaryBtn(String label, VoidCallback? onPressed, {bool loading = false}) {
    return Expanded(
        child: GestureDetector(
      onTap: loading ? null : onPressed,
      child: Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
            color: loading ? const Color(0xFF99C4FF) : const Color(0xFF006EFF),
            borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
            : Text(label,
                style: const TextStyle(
                    fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
      ),
    ));
  }

  Widget _outlinedBtn(String label, VoidCallback? onPressed) {
    return Expanded(
        child: GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF374151))),
      ),
    ));
  }

  /// 新增：保存
  Widget _buildNewBillButtons() {
    return _wrapBottomBar(
        [_primaryBtn('保存', _saving ? null : () => _handleSave(), loading: _saving)]);
  }

  /// 待审核
  Widget _buildPendingButtons() {
    final bool isLoading = _saving;
    final buttons = <Widget>[];

    if (!_isWithdrawPending && _bolHandleTT) {
      buttons.add(PopupMenuButton<String>(
        onSelected: (val) {
          if (val == 'delete') _handleDelete();
          if (val == 'print') Toast.show('打印功能暂未开放');
        },
        offset: const Offset(0, -100),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'delete', child: Text('删除')),
          const PopupMenuItem(value: 'print', child: Text('打印')),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(8)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('更多', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
            Icon(Icons.arrow_drop_up, size: 18, color: Color(0xFF6B7280)),
          ]),
        ),
      ));
    }

    final showSaveAndAudit =
        !_isWithdrawPending && (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT));
    if (showSaveAndAudit) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
        child: GestureDetector(
          onTap: isLoading ? null : () => _handleSave(),
          child: Container(
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
                color: isLoading ? const Color(0xFF99C4FF) : const Color(0xFF006EFF),
                borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                : const Text('保存',
                    style:
                        TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
          ),
        ),
      ));
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 8));
      buttons.add(Expanded(
        child: GestureDetector(
          onTap: isLoading ? null : _handleSign,
          child: Container(
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
                color: const Color(0xFF006EFF), borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Text('审核',
                style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
          ),
        ),
      ));
    }

    return _wrapBottomBar(buttons);
  }

  /// 已驳回：删除 + 撤回
  Widget _buildRejectedButtons() {
    return _wrapBottomBar([
      _outlinedBtn('删除', _handleDelete),
      _outlinedBtn('撤回', _handleRetsign),
    ]);
  }

  /// 已作废
  Widget _buildVoidedButtons() {
    return _wrapBottomBar([]);
  }

  /// 已审核：反审核
  Widget _buildSignedButtons() {
    return _wrapBottomBar([
      _primaryBtn('反审核', _handleZf),
    ]);
  }

  // ── 审批节点卡片 ──
  Widget _buildApprovalNodeCard() {
    Map<String, dynamic>? currentNode;
    String currentInfo = '';

    if (_reviewFlowUsers.isNotEmpty) {
      currentNode = _reviewFlowUsers[0];
      final index = currentNode['index']?.toString() ?? '1';
      final stepname = currentNode['stepname']?.toString() ?? '';
      final username = currentNode['username']?.toString() ?? '';
      currentInfo = '当前在第$index节点【$stepname】';
      if (username.isNotEmpty) currentInfo += '，审批人:$username';
    } else if (_reviewBillFlows.isNotEmpty) {
      currentNode = _reviewBillFlows[0];
      final stepname =
          currentNode['stepname']?.toString() ?? currentNode['stepno']?.toString() ?? '';
      final username = currentNode['username']?.toString() ?? '';
      currentInfo = '节点【$stepname】';
      if (username.isNotEmpty) currentInfo += '，审批人:$username';
    }

    final totalNodes = _reviewFlowUsers.isNotEmpty
        ? int.tryParse(_reviewFlowUsers[0]['allindex']?.toString() ?? '0') ?? 0
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('审核日志',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
              if (totalNodes > 0)
                Text('共$totalNodes个审批节点',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
            ],
          ),
          const SizedBox(height: 10),
          if (currentInfo.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(currentInfo,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
                ),
                GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('等待审核中...', style: TextStyle(fontSize: 13, color: Color(0xFFBFBFBF))),
                GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// =================== 审批弹窗 ===================

/// 审批操作弹窗（通过/驳回 + 备注）
class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({this.defaultFlag = 1});
  final int defaultFlag;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late int _flag;
  final _remarkCtrl = TextEditingController();
  static const int _maxLength = 200;

  @override
  void initState() {
    super.initState();
    _flag = widget.defaultFlag;
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('单据审批', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('*审批意见：', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => setState(() => _flag = 1),
                  child: Row(children: [
                    _buildRadio(1),
                    const SizedBox(width: 6),
                    const Text('通过', style: TextStyle(fontSize: 14)),
                  ]),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () => setState(() => _flag = 0),
                  child: Row(children: [
                    _buildRadio(0),
                    const SizedBox(width: 6),
                    const Text('驳回', style: TextStyle(fontSize: 14)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _flag == 1 ? '备注信息：' : '*驳回原因：',
              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remarkCtrl,
              maxLines: 3,
              maxLength: _maxLength,
              decoration: InputDecoration(
                hintText: _flag == 1 ? '请输入备注信息' : '请输入驳回原因',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBFBFBF)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_flag == 0 && _remarkCtrl.text.trim().isEmpty) {
                        Toast.show('驳回原因不能为空！');
                        return;
                      }
                      Navigator.pop(context, {
                        'reviewsignflag': _flag,
                        'reviewremark': _remarkCtrl.text.trim(),
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006EFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('确认'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadio(int value) {
    final isSelected = _flag == value;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC),
          width: 2,
        ),
        color: isSelected ? const Color(0xFF006EFF) : Colors.white,
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}

/// 审批日志弹窗（历史记录表格）
class _ApprovalLogSheet extends StatelessWidget {
  const _ApprovalLogSheet({
    required this.reviewBillFlows,
    required this.scrollController,
  });

  final List<Map<String, dynamic>> reviewBillFlows;
  final ScrollController scrollController;

  String _formatAction(dynamic v) {
    if (v == 1 || v?.toString() == '1') return '【通过】';
    if (v == 0 || v?.toString() == '0') return '【驳回】';
    if (v == 2 || v?.toString() == '2') return '【撤回】';
    return '';
  }

  Color _actionColor(dynamic v) {
    if (v == 1 || v?.toString() == '1') return const Color(0xFF00A870);
    if (v == 0 || v?.toString() == '0') return const Color(0xFFEF4444);
    if (v == 2 || v?.toString() == '2') return const Color(0xFFFF9900);
    return const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Expanded(
                child: Center(
                  child: Text('审批日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: Color(0xFF999999)),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Expanded(
          child: reviewBillFlows.isEmpty
              ? const Center(
                  child: Text('暂无审批记录', style: TextStyle(fontSize: 13, color: Color(0xFF999999))))
              : ListView.builder(
                  controller: scrollController,
                  itemCount: reviewBillFlows.length,
                  itemBuilder: (ctx, i) {
                    final item = reviewBillFlows[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: i.isEven ? Colors.white : const Color(0xFFFAFAFA),
                        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text('${i + 1}',
                                      style:
                                          const TextStyle(fontSize: 11, color: Color(0xFF666666))),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                item['username']?.toString() ?? '',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF333333)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatAction(item['reviewsignflag']),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _actionColor(item['reviewsignflag'])),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '节点：${item['stepname']?.toString() ?? ''}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                                ),
                              ),
                              Text(
                                item['signtime']?.toString() ??
                                    item['createtime']?.toString() ??
                                    '',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                              ),
                            ],
                          ),
                          if ((item['reviewremark']?.toString() ?? '').isNotEmpty) ...[
                            Text(
                              '备注：${item['reviewremark']}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
