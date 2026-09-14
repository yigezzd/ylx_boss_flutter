import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_salesperson.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

class CustManageEditPage extends StatefulWidget {
  const CustManageEditPage({super.key, this.billData});
  final Map<String, dynamic>? billData;

  @override
  State<CustManageEditPage> createState() => _CustManageEditPageState();
}

class _CustManageEditPageState extends State<CustManageEditPage>
    with SingleTickerProviderStateMixin, LogPageMixin<CustManageEditPage> {
  @override
  String get logPageName => _isEdit ? '客户管理编辑' : '客户管理新增';

  late TabController _tabController;

  final _formKey = GlobalKey<FormState>();

  // ── Tab 1: 基本信息 ──
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _linkmanCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _faxCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController(text: '100');
  final TextEditingController _wxminpayrateCtrl = TextEditingController(text: '0');
  final TextEditingController _remarkCtrl = TextEditingController();
  String? _custtypeid;
  String _custtypename = '';
  String? _custareaid;
  String _custareaname = '';
  String? _salesid;
  String _salesname = '';
  String? _pricetype = '1';
  bool _stopflag = false;

  // ── Tab 2: 资产信息 ──
  final TextEditingController _invoicetitleCtrl = TextEditingController();
  final TextEditingController _taxidCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _linkaddressCtrl = TextEditingController();
  final TextEditingController _bankCtrl = TextEditingController();
  final TextEditingController _bankaccountCtrl = TextEditingController();
  final TextEditingController _initamtCtrl = TextEditingController(text: '0');
  final TextEditingController _advanceCtrl = TextEditingController(text: '0');
  final TextEditingController _amountowedCtrl = TextEditingController(text: '0');
  final TextEditingController _debtamtCtrl = TextEditingController(text: '0');

  // ── Tab 3: 更多信息 ──
  bool _wxcustorderflag = true;
  String _wxcustorderstatus = '未绑定';
  String _createinfo = '';
  String _modifyinfo = '';

  bool _detailLoading = false;
  bool _isEdit = false;
  String _custId = '';
  Map<String, dynamic>? _detailData;

  List<Map<String, dynamic>>? _custTypeList;
  final bool _custTypeLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _isEdit = widget.billData != null;

    if (_isEdit) {
      _loadDetail();
    } else {
      _generateCode();
    }
    logEnter();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _linkmanCtrl.dispose();
    _mobileCtrl.dispose();
    _faxCtrl.dispose();
    _addressCtrl.dispose();
    _discountCtrl.dispose();
    _wxminpayrateCtrl.dispose();
    _remarkCtrl.dispose();
    _invoicetitleCtrl.dispose();
    _taxidCtrl.dispose();
    _phoneCtrl.dispose();
    _linkaddressCtrl.dispose();
    _bankCtrl.dispose();
    _bankaccountCtrl.dispose();
    _initamtCtrl.dispose();
    _advanceCtrl.dispose();
    _amountowedCtrl.dispose();
    _debtamtCtrl.dispose();
    super.dispose();
  }

  void _generateCode() {
    request(HttpApi.customerGenerateCode, {}).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is String && data.isNotEmpty) {
        _codeCtrl.text = data;
      }
    });
  }

  void _loadDetail() {
    setState(() => _detailLoading = true);
    final billId = widget.billData!['id']?.toString() ?? '';
    request(HttpApi.customerGetInfo, billId).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        _detailData = Map<String, dynamic>.from(data);
        setState(() {
          _codeCtrl.text = data['code']?.toString() ?? '';
          _nameCtrl.text = data['name']?.toString() ?? '';
          _custtypeid = data['custtypeid']?.toString() ?? '';
          _custtypename = data['custtypename']?.toString() ?? '';
          _custId = data['id']?.toString() ?? '';
          _custareaid = data['custareaid']?.toString() ?? '';
          _custareaname = data['custareaname']?.toString() ?? '';
          _linkmanCtrl.text = data['linkman']?.toString() ?? '';
          _mobileCtrl.text = data['mobile']?.toString() ?? '';
          _faxCtrl.text = data['fax']?.toString() ?? '';
          _salesid = data['salesid']?.toString() ?? '';
          _salesname = data['salesname']?.toString() ?? '';
          _addressCtrl.text = data['address']?.toString() ?? '';
          _pricetype = data['pricetype']?.toString() ?? '1';
          _discountCtrl.text = data['discount']?.toString() ?? '100';
          _wxminpayrateCtrl.text = data['wxminpayrate']?.toString() ?? '0';
          _stopflag = data['stopflag']?.toString() == '0';
          _remarkCtrl.text = data['remark']?.toString() ?? '';

          _invoicetitleCtrl.text = data['invoicetitle']?.toString() ?? '';
          _taxidCtrl.text = data['taxid']?.toString() ?? '';
          _phoneCtrl.text = data['phone']?.toString() ?? '';
          _linkaddressCtrl.text = data['linkaddress']?.toString() ?? '';
          _bankCtrl.text = data['bank']?.toString() ?? '';
          _bankaccountCtrl.text = data['bankaccount']?.toString() ?? '';
          _initamtCtrl.text = data['initamt']?.toString() ?? '0';
          _advanceCtrl.text = data['advance']?.toString() ?? '0';
          _amountowedCtrl.text = data['amountowed']?.toString() ?? '0';
          _debtamtCtrl.text = data['debtamt']?.toString() ?? '0';

          _wxcustorderflag = data['wxcustorderflag']?.toString() == '1';
          final int ws = int.tryParse(data['wxcustorderstatus']?.toString() ?? '') ?? 0;
          _wxcustorderstatus = ws == 0 ? '未绑定' : '已绑定';
          _createinfo = '';
          final String cn = data['createname']?.toString() ?? '';
          final String ct = data['createtime']?.toString() ?? '';
          if (cn.isNotEmpty || ct.isNotEmpty) {
            _createinfo = '$ct $cn';
          }
          _modifyinfo = '';
          final String mn = data['opername']?.toString() ?? '';
          final String mt = data['updatetime']?.toString() ?? '';
          if (mn.isNotEmpty || mt.isNotEmpty) {
            _modifyinfo = '$mt $mn';
          }
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  Future<void> _save() async {
    // 权限校验：区分新增/编辑
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('012104', showTip: false)) {
        Toast.show('你无权编辑客户管理，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('012102', showTip: false)) {
        Toast.show('你无权新增客户管理，请在后台修改权限');
        return;
      }
    }
    logSave(_isEdit ? '保存修改' : '保存');
    // 校验
    if (_codeCtrl.text.trim().isEmpty) {
      Toast.show('请输入客户编码');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      Toast.show('请输入客户名称');
      return;
    }
    if (_custtypeid == null || _custtypeid!.isEmpty) {
      Toast.show('请选择客户分类');
      return;
    }

    // 以完整数据为基础，覆盖表单修改的值
    final Map<String, dynamic> params = _isEdit && _detailData != null
        ? Map<String, dynamic>.from(_detailData!)
        : <String, dynamic>{};
    params['code'] = _codeCtrl.text.trim();
    params['name'] = _nameCtrl.text.trim();
    if (_custtypeid != null && _custtypeid!.isNotEmpty) {
      params['custtypeid'] = _custtypeid;
      params['custtypename'] = _custtypename;
    }
    if (_salesid != null && _salesid!.isNotEmpty) {
      params['salesid'] = _salesid;
      params['salesname'] = _salesname;
    }
    if (_linkmanCtrl.text.trim().isNotEmpty) {
      params['linkman'] = _linkmanCtrl.text.trim();
    }
    if (_mobileCtrl.text.trim().isNotEmpty) {
      params['mobile'] = _mobileCtrl.text.trim();
    }
    if (_faxCtrl.text.trim().isNotEmpty) {
      params['fax'] = _faxCtrl.text.trim();
    }
    if (_addressCtrl.text.trim().isNotEmpty) {
      params['address'] = _addressCtrl.text.trim();
    }
    params['pricetype'] = _pricetype ?? '1';
    params['discount'] = double.tryParse(_discountCtrl.text) ?? 100;
    params['wxminpayrate'] = double.tryParse(_wxminpayrateCtrl.text) ?? 0;
    params['stopflag'] = _stopflag ? '0' : '1';
    if (_remarkCtrl.text.trim().isNotEmpty) {
      params['remark'] = _remarkCtrl.text.trim();
    }
    if (_custareaid != null && _custareaid!.isNotEmpty) {
      params['custareaid'] = _custareaid;
      params['custareaname'] = _custareaname;
    }
    if (_invoicetitleCtrl.text.trim().isNotEmpty) {
      params['invoicetitle'] = _invoicetitleCtrl.text.trim();
    }
    if (_taxidCtrl.text.trim().isNotEmpty) {
      params['taxid'] = _taxidCtrl.text.trim();
    }
    if (_phoneCtrl.text.trim().isNotEmpty) {
      params['phone'] = _phoneCtrl.text.trim();
    }
    if (_linkaddressCtrl.text.trim().isNotEmpty) {
      params['linkaddress'] = _linkaddressCtrl.text.trim();
    }
    if (_bankCtrl.text.trim().isNotEmpty) {
      params['bank'] = _bankCtrl.text.trim();
    }
    if (_bankaccountCtrl.text.trim().isNotEmpty) {
      params['bankaccount'] = _bankaccountCtrl.text.trim();
    }
    params['initamt'] = double.tryParse(_initamtCtrl.text) ?? 0;
    params['amountowed'] = double.tryParse(_amountowedCtrl.text) ?? 0;
    params['wxcustorderflag'] = _wxcustorderflag ? '1' : '0';

    // 编辑模式带上 id
    if (_isEdit && _custId.isNotEmpty) {
      params['id'] = _custId;
    }

    request(HttpApi.customerSave, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '保存成功');
      Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? '编辑客户' : '新增客户',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        actions: [
          // 保存按钮
          GestureDetector(
            onTap: _save,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF006EFF),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: const Text(
                '保存',
                style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)))
          : Column(
              children: [
                // Tab 栏
                ColoredBox(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF006EFF),
                    unselectedLabelColor: const Color(0xFF6B7280),
                    indicatorColor: const Color(0xFF006EFF),
                    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    tabs: const [
                      Tab(text: '基本信息'),
                      Tab(text: '资产信息'),
                      Tab(text: '更多信息'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBasicInfoTab(),
                      _buildAssetInfoTab(),
                      _buildMoreInfoTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ═══ Tab 1: 基本信息 ═══
  Widget _buildBasicInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Form(
        key: _formKey,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
          ),
          child: Column(
            children: [
              _buildTextField(label: '客户编码', controller: _codeCtrl, required: true),
              _buildDivider(),
              _buildTextField(label: '客户名称', controller: _nameCtrl, required: true),
              _buildDivider(),
              _buildSelectField(
                label: '客户分类',
                value: _custtypename.isNotEmpty ? _custtypename : '请选择',
                onTap: () => _selectCustType(),
                required: true,
              ),
              _buildDivider(),
              _buildSelectField(
                label: '客户区域',
                value: _custareaname.isNotEmpty ? _custareaname : '请选择',
                onTap: () => _selectArea(),
              ),
              _buildDivider(),
              _buildTextField(label: '联系人', controller: _linkmanCtrl),
              _buildDivider(),
              _buildTextField(label: '手机号码', controller: _mobileCtrl),
              _buildDivider(),
              _buildTextField(label: '传真号码', controller: _faxCtrl),
              _buildDivider(),
              _buildSelectField(
                label: '业务员',
                value: _salesname.isNotEmpty ? _salesname : '请选择',
                onTap: () => _selectSalesperson(),
              ),
              _buildDivider(),
              _buildTextField(label: '地址', controller: _addressCtrl),
              _buildDivider(),
              _buildPriceTypeField(),
              _buildDivider(),
              _buildTextField(
                label: '批发折扣',
                controller: _discountCtrl,
                keyboardType: TextInputType.number,
              ),
              _buildDivider(),
              _buildTextField(
                label: '线上最低付款比例',
                controller: _wxminpayrateCtrl,
                keyboardType: TextInputType.number,
              ),
              _buildDivider(),
              _buildSwitchField(label: '状态', value: _stopflag),
              _buildDivider(),
              _buildTextField(label: '备注', controller: _remarkCtrl, maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }

  // ═══ Tab 2: 资产信息 ═══
  Widget _buildAssetInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Column(
          children: [
            _buildTextField(label: '发票抬头名称', controller: _invoicetitleCtrl),
            _buildDivider(),
            _buildTextField(label: '纳税人识别号', controller: _taxidCtrl),
            _buildDivider(),
            _buildTextField(label: '公司电话', controller: _phoneCtrl),
            _buildDivider(),
            _buildTextField(label: '公司地址', controller: _linkaddressCtrl),
            _buildDivider(),
            _buildTextField(label: '开户行', controller: _bankCtrl),
            _buildDivider(),
            _buildTextField(label: '银行账户', controller: _bankaccountCtrl),
            _buildDivider(),
            _buildTextField(
              label: '期初金额',
              controller: _initamtCtrl,
              keyboardType: TextInputType.number,
            ),
            _buildDivider(),
            _buildReadonlyField(label: '预付款金额', value: _advanceCtrl.text),
            _buildDivider(),
            _buildTextField(
              label: '信誉额度',
              controller: _amountowedCtrl,
              keyboardType: TextInputType.number,
            ),
            _buildDivider(),
            _buildReadonlyField(label: '欠款金额', value: _debtamtCtrl.text),
          ],
        ),
      ),
    );
  }

  // ═══ Tab 3: 更多信息 ═══
  Widget _buildMoreInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Column(
          children: [
            _buildSwitchField(
              label: '订货助手',
              value: _wxcustorderflag,
              subtitle: '允许客户通过订货助手自助下单',
            ),
            _buildDivider(),
            _buildReadonlyField(label: '绑定状态', value: _wxcustorderstatus),
            if (_createinfo.isNotEmpty) ...[
              _buildDivider(),
              _buildReadonlyField(label: '创建人/日期', value: _createinfo),
            ],
            if (_modifyinfo.isNotEmpty) ...[
              _buildDivider(),
              _buildReadonlyField(label: '最后修改人/日期', value: _modifyinfo),
            ],
          ],
        ),
      ),
    );
  }

  // ═══ 选择客户分类 ═══
  Future<void> _selectCustType() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CustCategorySelectSheet(
        initialId: _custtypeid ?? '',
        initialName: _custtypename,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _custtypeid = result['custtypeid'];
        _custtypename = result['custtypename'] ?? '';
      });
    }
  }

  Future<void> _selectArea() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AreaSelectSheet(
        initialId: _custareaid ?? '',
        initialName: _custareaname,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _custareaid = result['custareaid'] ?? '';
        _custareaname = result['custareaname'] ?? '';
      });
    }
  }

  Future<void> _selectSalesperson() async {
    final result = await SelectSalespersonPage.show(context, initialSelectedId: _salesid);
    if (result != null && mounted) {
      setState(() {
        _salesid = result['salesid']?.toString();
        _salesname = result['salesname']?.toString() ?? '';
      });
    }
  }

  // ═══ 批发价格选择 ═══
  Future<void> _selectPriceType() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PriceTypeSheet(initial: _pricetype),
    );
    if (result != null && mounted) {
      setState(() => _pricetype = result);
    }
  }

  // ═══ 通用 UI 组件 ═══

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 130,
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: required
                      ? const Text('*',
                          style: TextStyle(
                              color: Color(0xFFFF4D4F), fontSize: 14, fontWeight: FontWeight.w500))
                      : null,
                ),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              keyboardType: keyboardType,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectField({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool required = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: required
                        ? const Text('*',
                            style: TextStyle(
                                color: Color(0xFFFF4D4F),
                                fontSize: 14,
                                fontWeight: FontWeight.w500))
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: value == '请选择' ? const Color(0xFFD1D5DB) : const Color(0xFF111827),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }

  Widget _buildReadonlyField({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              readOnly: true,
              controller: TextEditingController.fromValue(
                TextEditingValue(text: value.isNotEmpty ? value : '-'),
              ),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9CA3AF),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchField({
    required String label,
    required bool value,
    String subtitle = '',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          Switch(
            value: value,
            onChanged: (v) => setState(() {
              if (label == '状态') {
                _stopflag = v;
              } else if (label == '订货助手') {
                _wxcustorderflag = v;
              }
            }),
            activeColor: const Color(0xFF006EFF),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceTypeField() {
    final List<String> labels = [
      '批发价1',
      '批发价2',
      '批发价3',
      '批发价4',
      '批发价5',
      '批发价6',
      '批发价7',
      '批发价8',
      '批发价9',
      '批发价10',
    ];
    final idx = (int.tryParse(_pricetype ?? '1') ?? 1) - 1;
    final display = (idx >= 0 && idx < labels.length) ? labels[idx] : '批发价1';
    return _buildSelectField(
      label: '批发价格',
      value: display,
      onTap: _selectPriceType,
    );
  }

  static Widget _buildDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));
}

// ═══ 客户分类底部选择 ═══
class _CustCategorySelectSheet extends StatefulWidget {
  const _CustCategorySelectSheet({this.initialId = '', this.initialName = ''});
  final String initialId;
  final String initialName;

  @override
  State<_CustCategorySelectSheet> createState() => _CustCategorySelectSheetState();
}

class _CustCategorySelectSheetState extends State<_CustCategorySelectSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _selectedId;
  String _selectedName = '';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId.isEmpty ? null : widget.initialId;
    _selectedName = widget.initialName;
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final result = await request('customertype/getTypeListandCode', {
        'notwx': 1,
        'cond': _searchCtrl.text.trim(),
      });
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['children'] : null) as List? ?? [];
      if (mounted) {
        setState(() {
          _list = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 48),
                const Expanded(
                  child: Text('选择客户分类',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => _loadData(),
                decoration: InputDecoration(
                  hintText: '输入分类名称/编码',
                  hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                  prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildTreeChildren(0),
                    ),
                  ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            child: GestureDetector(
              onTap: () => Navigator.pop(context, {
                'custtypeid': _selectedId ?? '',
                'custtypename': _selectedName,
              }),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '确定',
                  style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 树形递归节点 ──
  final Set<String> _expandedIds = {};

  List<Widget> _buildTreeChildren(int depth) {
    final list = _list.map((node) => _buildTreeItem(node, depth)).toList();
    return list;
  }

  Widget _buildTreeItem(Map<String, dynamic> node, int depth) {
    final id = node['typeid']?.toString() ?? '';
    final name = node['name']?.toString() ?? '';
    final code = node['code']?.toString() ?? '';
    final label = code.isNotEmpty ? '[$code]$name' : name;
    final children = (node['children'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final hasChildren = children.isNotEmpty;
    final isSelected = _selectedId == id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context, {
            'custtypeid': id,
            'custtypename': name,
          }),
          child: Container(
            padding: EdgeInsets.only(
              left: 16.0 + depth * 20.0,
              right: 16,
              top: 14,
              bottom: 14,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
            ),
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    onTap: () {
                      setState(() => _expandedIds.contains(id)
                          ? _expandedIds.remove(id)
                          : _expandedIds.add(id));
                    },
                    child: Icon(
                      _expandedIds.contains(id) ? Icons.expand_more : Icons.chevron_right,
                      size: 20,
                      color: const Color(0xFF9CA3AF),
                    ),
                  )
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 4),
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 22,
                  color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: isSelected ? const Color(0xFF006EFF) : const Color(0xFF111827),
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasChildren && _expandedIds.contains(id))
          ...children.map((child) => _buildTreeItem(child, depth + 1)),
      ],
    );
  }
}

// ═══ 客户区域选择 ═══
class _AreaSelectSheet extends StatefulWidget {
  const _AreaSelectSheet({this.initialId = '', this.initialName = ''});
  final String initialId;
  final String initialName;

  @override
  State<_AreaSelectSheet> createState() => _AreaSelectSheetState();
}

class _AreaSelectSheetState extends State<_AreaSelectSheet> {
  List<Map<String, dynamic>> _areas = [];
  bool _loading = true;
  String? _selectedId;
  String _selectedName = '';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId.isEmpty ? null : widget.initialId;
    _selectedName = widget.initialName;
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    try {
      final result = await request('customerarea/getList', {'notwx': 1});
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (mounted) {
        setState(() {
          _areas = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 48),
                const Expanded(
                  child: Text('选择客户区域',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context, {
                            'custareaid': '',
                            'custareaname': '',
                          });
                        },
                        child: _areaItem('全部区域', null, true),
                      ),
                      ..._areas.map((area) {
                        final id = area['areacode']?.toString() ?? '';
                        final name = area['areaname']?.toString() ?? '';
                        final areaid = area['areaid']?.toString() ?? id;
                        final label = id.isNotEmpty ? '[$id]$name' : name;
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context, {
                              'custareaid': areaid,
                              'custareaname': name,
                            });
                          },
                          child: _areaItem(label, id, false),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _areaItem(String label, String? id, bool isAll) {
    final isSelected = isAll ? (_selectedId == null || _selectedId!.isEmpty) : (_selectedId == id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 22,
            color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: isSelected ? const Color(0xFF006EFF) : const Color(0xFF111827),
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══ 批发价格选择 ═══
class _PriceTypeSheet extends StatelessWidget {
  const _PriceTypeSheet({this.initial});
  final String? initial;

  @override
  Widget build(BuildContext context) {
    final List<String> labels = [
      '批发价1',
      '批发价2',
      '批发价3',
      '批发价4',
      '批发价5',
      '批发价6',
      '批发价7',
      '批发价8',
      '批发价9',
      '批发价10',
    ];
    return Container(
      height: 420,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 48),
                const Expanded(
                  child: Text('选择批发价格',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: labels.length,
              itemBuilder: (_, i) {
                final val = '${i + 1}';
                final isSelected = initial == val;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, val),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 22,
                          color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 15,
                            color: isSelected ? const Color(0xFF006EFF) : const Color(0xFF111827),
                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
