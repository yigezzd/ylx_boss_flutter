import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_page.dart';
import 'package:sp_util/sp_util.dart';

class InventoryPlanAddPage extends StatefulWidget {
  const InventoryPlanAddPage({super.key, this.billData});
  final Map<String, dynamic>? billData;

  @override
  State<InventoryPlanAddPage> createState() => _InventoryPlanAddPageState();
}

class _InventoryPlanAddPageState extends State<InventoryPlanAddPage>
    with LogPageMixin<InventoryPlanAddPage> {
  @override
  String get logPageName => _isEdit ? '盘点计划详情' : '盘点计划新增';

  final TextEditingController _plannameCtrl = TextEditingController();
  final TextEditingController _storeCtrl = TextEditingController();
  final TextEditingController _warehouseCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();

  String? _bsid; // 机构ID
  String? _storename;
  String? _counterid;
  String? _countername;
  String _clearflag = '1'; // 0=库存不变 1=库存清零
  String _openflag = '1'; // 1=营业中盘点 0=停业盘点
  int _checktype = 2; // 1=全场 2=分类 3=供应商 4=品牌
  List<Map<String, dynamic>> _typeList = []; // 分类/供应商/品牌列表

  bool _submitting = false;
  bool _detailLoading = false;
  Map<String, dynamic>? _billData;

  // ---- 批量选择模式 ----
  bool _isSelectMode = false;
  Set<int> _selectedIndices = {};

  bool get _isEdit => _billData != null && (_billData!['billid']?.toString().isNotEmpty ?? false);
  bool get _isSigned => _billData?['signflag']?.toString() == '1';

  @override
  void initState() {
    super.initState();
    if (widget.billData != null && (widget.billData!['billid']?.toString().isNotEmpty ?? false)) {
      _loadDetail();
    } else {
      _loadDefaults();
    }
    logEnter();
  }

  void _loadDefaults() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _bsid = storeMap['id']?.toString();
        _storename = storeMap['name']?.toString();
        _storeCtrl.text = _storename ?? '';
      }
    } catch (_) {}
  }

  void _loadDetail() {
    setState(() => _detailLoading = true);
    final params = Map<String, dynamic>.from(widget.billData!);
    request(HttpApi.stockplanGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _plannameCtrl.text = data['planname']?.toString() ?? '';
          _storeCtrl.text = data['storename']?.toString() ?? '';
          _warehouseCtrl.text = data['countername']?.toString() ?? '';
          _remarkCtrl.text = data['remark']?.toString() ?? '';
          _bsid = data['bsid']?.toString();
          _storename = data['storename']?.toString();
          _counterid = data['counterid']?.toString();
          _countername = data['countername']?.toString();
          _clearflag = data['clearflag']?.toString() ?? '1';
          _openflag = data['openflag']?.toString() ?? '1';
          _checktype = int.tryParse(data['checktype']?.toString() ?? '') ?? 2;
          final typeArr = data['stockPlanItemtypeResp'] as List? ?? [];
          _typeList = typeArr.cast<Map<String, dynamic>>();
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  @override
  void dispose() {
    _plannameCtrl.dispose();
    _storeCtrl.dispose();
    _warehouseCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  // ── 选择机构 ──
  Future<void> _selectStore() async {
    if (_isSigned) return;
    FocusScope.of(context).unfocus(); // 取消焦点，防止键盘弹出
    final result = await SelectStorePage.show(context);
    if (mounted) {
      // 抽屉关闭后取消焦点，防止焦点自动恢复到输入框
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusManager.instance.primaryFocus?.unfocus();
      });
      if (result != null) {
        setState(() {
          _bsid = result['storeid']?.toString();
          _storename = result['storename']?.toString();
          _storeCtrl.text = _storename ?? '';
          _counterid = null;
          _countername = null;
          _warehouseCtrl.text = '';
        });
      }
    }
  }

  // ── 选择仓库 ──
  Future<void> _selectWarehouse() async {
    if (_isSigned) return;
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请先选择机构');
      return;
    }
    FocusScope.of(context).unfocus(); // 取消焦点，防止键盘弹出
    final result = await SelectWarehousePage.show(
      context,
      bsid: int.tryParse(_bsid!),
      initialSelectedId: _counterid ?? '',
    );
    if (mounted) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusManager.instance.primaryFocus?.unfocus();
      });
      if (result != null) {
        setState(() {
          _counterid = result['counterid']?.toString();
          _countername = result['countername']?.toString();
          _warehouseCtrl.text = _countername ?? '';
        });
      }
    }
  }

  // ── 保存 ──
  void _save() {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('013603', showTip: false)) {
        Toast.show('你无权编辑盘点计划，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('013602', showTip: false)) {
        Toast.show('你无权新增盘点计划，请在后台修改权限');
        return;
      }
    }
    logSave('保存单据');
    if (_plannameCtrl.text.trim().isEmpty) {
      Toast.show('请输入计划名称');
      return;
    }
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请选择机构');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('请选择仓库');
      return;
    }
    if (_checktype != 1 && _typeList.isEmpty) {
      final tip = _checktype == 2
          ? '请选择分类'
          : _checktype == 3
              ? '请选择供应商'
              : '请选择品牌';
      Toast.show(tip);
      return;
    }

    setState(() => _submitting = true);
    final params = <String, dynamic>{
      'planname': _plannameCtrl.text.trim(),
      'bsid': _bsid,
      'storename': _storename,
      'counterid': _counterid,
      'countername': _countername,
      'clearflag': _clearflag,
      'openflag': _openflag,
      'checktype': _checktype,
      'remark': _remarkCtrl.text.trim(),
      'stockPlanItemtypeResp': _typeList,
    };
    if (_isEdit) params['billid'] = _billData!['billid'];

    request(HttpApi.stockplanSave, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() => _billData = data);
      }
      Toast.show('保存成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitting = false);
    });
  }

  // ── 删除 ──
  Future<void> _delBill() async {
    if (_billData == null) return;
    if (!PermissionUtils.checkPermission('013604', showTip: false)) {
      Toast.show('你无权删除盘点计划，请在后台修改权限');
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
    if (confirm != true) return;
    setState(() => _submitting = true);
    request(HttpApi.stockplanDelBill, _billData).then((result) {
      if (!mounted) return;
      Toast.show('删除成功');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitting = false);
    });
  }

  // ── 打印 ──
  Future<void> _print() async {
    if (_billData == null) return;
    setState(() => _submitting = true);
    request(HttpApi.purchaseInstorePrint, {
      'menuid': '081001',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show('打印成功');
    }).whenComplete(() {
      if (mounted) setState(() => _submitting = false);
    });
  }

  // ── 选择盘点范围 ──
  void _showChecktypeSheet() {
    if (_isSigned) return;
    FocusScope.of(context).unfocus(); // 取消焦点，防止键盘弹出
    final options = [
      {'label': '分类盘点', 'value': 2},
      {'label': '供应商盘点', 'value': 3},
      {'label': '品牌盘点', 'value': 4},
      {'label': '全场盘点', 'value': 1},
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('选择盘点范围', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ...options.map((opt) {
                final newVal = int.tryParse(opt['value']?.toString() ?? '') ?? 0;
                final isSelected = _checktype == newVal;
                return _buildRadioOption(
                  label: opt['label']?.toString() ?? '',
                  isSelected: isSelected,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (newVal == _checktype) {
                      return;
                    }
                    SchedulerBinding.instance.addPostFrameCallback((_) {
                      showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('提示'),
                          content: const Text('切换盘点范围将清空单据内容，是否继续切换？'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                            TextButton(
                                onPressed: () => Navigator.pop(c, true), child: const Text('确定')),
                          ],
                        ),
                      ).then((confirmed) {
                        if ((confirmed ?? false) && mounted) {
                          setState(() {
                            _checktype = newVal;
                            _typeList = [];
                          });
                        }
                      });
                    });
                  },
                );
              }),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) FocusManager.instance.primaryFocus?.unfocus();
        });
      }
    });
  }

  // ── 选择下拉（clearflag / openflag）──
  void _showOptionSheet({
    required String title,
    required String currentValue,
    required List<Map<String, String>> options,
    required ValueChanged<String> onSelected,
  }) {
    if (_isSigned) return;
    FocusScope.of(context).unfocus(); // 取消焦点，防止键盘弹出
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child:
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ...options.map((opt) {
                final isSelected = currentValue == opt['value'];
                return _buildRadioOption(
                  label: opt['label']!,
                  isSelected: isSelected,
                  onTap: () {
                    onSelected(opt['value']!);
                    Navigator.pop(ctx);
                  },
                );
              }),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) FocusManager.instance.primaryFocus?.unfocus();
        });
      }
    });
  }

  static Widget _buildRadioOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 22,
            color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                fontSize: 15,
                color: isSelected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              )),
        ]),
      ),
    );
  }

  String _checktypeName(int v) {
    switch (v) {
      case 1:
        return '全场盘点';
      case 2:
        return '分类盘点';
      case 3:
        return '供应商盘点';
      case 4:
        return '品牌盘点';
      default:
        return '';
    }
  }

  String _checktypeDetailLabel(int v) {
    switch (v) {
      case 2:
        return '商品分类明细';
      case 3:
        return '供应商明细';
      case 4:
        return '品牌明细';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _isSigned;

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
        title: Text(_isEdit ? '修改盘点计划' : '新增盘点计划',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 已编辑时显示单号信息 ──
                  if (_isEdit) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('单号：${_billData?['billno'] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827))),
                            const Spacer(),
                            Builder(builder: (_) {
                              final sf = _billData?['signflag']?.toString() ?? '';
                              final String statusLabel;
                              final Color statusColor;
                              if (sf == '1') {
                                statusLabel = '已盘点';
                                statusColor = const Color(0xFF00A870);
                              } else if (sf == '2') {
                                statusLabel = '盘点中';
                                statusColor = const Color(0xFF09B8EE);
                              } else {
                                statusLabel = '待盘点';
                                statusColor = const Color(0xFFD54B5A);
                              }
                              return Text(
                                statusLabel,
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500, color: statusColor),
                              );
                            }),
                          ]),
                          const SizedBox(height: 6),
                          Text('制单信息：${_billData?['createtime'] ?? ''}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                          const SizedBox(height: 4),
                          Text('制单人：${_billData?['createname'] ?? ''}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── 表单区 ──
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Column(children: [
                      _buildInputRow(
                          label: '盘点计划名称',
                          controller: _plannameCtrl,
                          disabled: disabled,
                          required: true),
                      _buildDivider(),
                      _buildSelectRow(
                          label: '盘点机构',
                          value: _storeCtrl.text,
                          onTap: _selectStore,
                          disabled: disabled),
                      _buildDivider(),
                      _buildSelectRow(
                          label: '盘点仓库',
                          value: _warehouseCtrl.text,
                          onTap: _selectWarehouse,
                          disabled: disabled,
                          required: true),
                      _buildDivider(),
                      _buildSelectRow(
                        label: '未盘商品处理',
                        value: _clearflag == '1' ? '库存清零' : '库存不变',
                        onTap: () => _showOptionSheet(
                          title: '选择未盘商品处理',
                          currentValue: _clearflag,
                          options: [
                            {'label': '库存不变', 'value': '0'},
                            {'label': '库存清零', 'value': '1'},
                          ],
                          onSelected: (v) => setState(() => _clearflag = v),
                        ),
                        disabled: disabled,
                      ),
                      _buildDivider(),
                      _buildSelectRow(
                        label: '盘点类型',
                        value: _openflag == '1' ? '营业中盘点' : '停业盘点',
                        onTap: () => _showOptionSheet(
                          title: '选择盘点类型',
                          currentValue: _openflag,
                          options: [
                            {'label': '营业中盘点', 'value': '1'},
                            {'label': '停业盘点', 'value': '0'},
                          ],
                          onSelected: (v) => setState(() => _openflag = v),
                        ),
                        disabled: disabled,
                      ),
                      _buildDivider(),
                      _buildSelectRow(
                        label: '盘点范围',
                        value: _checktypeName(_checktype),
                        onTap: _showChecktypeSheet,
                        disabled: disabled,
                      ),
                      _buildDivider(),
                      _buildInputRow(label: '备注', controller: _remarkCtrl, disabled: disabled),
                    ]),
                  ),

                  // ── 分类/供应商/品牌明细 ──
                  if (_checktype != 1) ...[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(children: [
                            Text(_checktypeDetailLabel(_checktype),
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827))),
                            const Spacer(),
                            if (!disabled) ...[
                              GestureDetector(
                                onTap: _toggleSelectMode,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isSelectMode ? Icons.close : Icons.delete_outline,
                                      size: 17,
                                      color: _isSelectMode
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFFFF4D4F),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      _isSelectMode ? '取消' : '删除',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _isSelectMode
                                            ? const Color(0xFF6B7280)
                                            : const Color(0xFFFF4D4F),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: _addTypeItem,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_circle_outline,
                                        size: 16, color: Color(0xFF006EFF)),
                                    SizedBox(width: 2),
                                    Text('新增',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF006EFF),
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],
                          ]),
                        ),
                        if (_typeList.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('暂无数据',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                            ),
                          )
                        else
                          ..._typeList.asMap().entries.map((entry) {
                            final item = entry.value;
                            final idx = entry.key;
                            final name = (item['stypename']?.toString() ?? '').isNotEmpty
                                ? item['stypename']?.toString() ?? ''
                                : item['stypeid']?.toString() ?? '';
                            final isSelected = _selectedIndices.contains(idx);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: const BoxDecoration(
                                border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
                              ),
                              child: Row(children: [
                                if (_isSelectMode) ...[
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: isSelected,
                                      activeColor: const Color(0xFF006EFF),
                                      onChanged: (_) => _toggleIndex(idx),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _isSelectMode ? () => _toggleIndex(idx) : null,
                                    behavior: HitTestBehavior.opaque,
                                    child: Text(
                                      name,
                                      style:
                                          const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                    ),
                                  ),
                                ),
                                if (!disabled && !_isSelectMode)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() => _typeList.removeAt(idx));
                                    },
                                    child: const Icon(Icons.delete_outline,
                                        size: 18, color: Color(0xFFD54B5A)),
                                  ),
                              ]),
                            );
                          }),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomBar(disabled),
    );
  }

  Widget _buildBottomBar(bool disabled) {
    if (_isSelectMode) {
      return _buildBatchDeleteBar();
    }
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(children: [
        if (!_isEdit) ...[
          Expanded(
            child: GestureDetector(
              onTap: _submitting ? null : _save,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('保存', style: TextStyle(fontSize: 15, color: Colors.white)),
              ),
            ),
          ),
        ] else if (_isSigned) ...[
          Expanded(
            child: GestureDetector(
              onTap: _submitting ? null : _print,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Text('打印', style: TextStyle(fontSize: 15, color: Colors.white)),
              ),
            ),
          ),
        ] else ...[
          Expanded(
            child: GestureDetector(
              onTap: _submitting ? null : _delBill,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFCCCCCC)),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Text('删除', style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: _submitting ? null : _save,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('保存', style: TextStyle(fontSize: 15, color: Colors.white)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  // =================== 批量选择 ===================
  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) {
        _selectedIndices.clear();
      }
    });
  }

  void _toggleIndex(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  bool get _isAllSelected {
    return _typeList.isNotEmpty && _selectedIndices.length == _typeList.length;
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedIndices.clear();
      } else {
        _selectedIndices = Set<int>.from(List.generate(_typeList.length, (i) => i));
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIndices.isEmpty) {
      return;
    }
    final count = _selectedIndices.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text('确定删除选中的 $count 条明细？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    setState(() {
      final sorted = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
      sorted.forEach(_typeList.removeAt);
      _selectedIndices.clear();
      _isSelectMode = false;
    });
  }

  Widget _buildBatchDeleteBar() {
    final selectedCount = _selectedIndices.length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleSelectAll,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _isAllSelected,
                    activeColor: const Color(0xFF006EFF),
                    onChanged: (_) => _toggleSelectAll(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('全选', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: selectedCount > 0 ? _batchDelete : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: selectedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('删除选中($selectedCount)',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  /// 添加分类/供应商/品牌项
  void _addTypeItem() {
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请先选择机构');
      return;
    }
    if (_checktype == 2) {
      _selectCategoryItems();
    } else if (_checktype == 3) {
      _selectSupplierItems();
    } else if (_checktype == 4) {
      _selectBrandItems();
    }
  }

  /// 选择商品分类（多选）
  Future<void> _selectCategoryItems() async {
    FocusScope.of(context).unfocus();
    final selectedIds = _typeList
        .map((e) => e['stypeid']?.toString())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList();
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryListPage(
          isSelect: true,
          isMultiSelect: true,
          initialSelectedIds: selectedIds,
        ),
      ),
    );
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusManager.instance.primaryFocus?.unfocus();
    });
    if (result == null) return;
    final newItems = result.map((item) {
      final typeid = item['typeid']?.toString() ?? '';
      final typename = item['name']?.toString() ?? item['typename']?.toString() ?? '';
      final typecode = item['typecode']?.toString() ?? item['code']?.toString() ?? '';
      return <String, dynamic>{
        'stypeid': typeid,
        'stypename': typename,
        'stypecode': typecode,
        'memo': '',
      };
    }).toList();
    _mergeTypeItems(newItems);
  }

  /// 合并去重并追加到 typeList
  void _mergeTypeItems(List<Map<String, dynamic>> newItems) {
    setState(() {
      final existIds = _typeList.map((e) => e['stypeid']?.toString()).whereType<String>().toSet();
      for (final item in newItems) {
        final id = item['stypeid']?.toString() ?? '';
        if (id.isNotEmpty && !existIds.contains(id)) {
          _typeList.add(item);
          existIds.add(id);
        }
      }
    });
  }

  /// 选择供应商（多选）
  Future<void> _selectSupplierItems() async {
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请先选择机构');
      return;
    }
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CommonSelectPage(
          title: '选择供应商',
          searchHint: '输入供应商名称/编码',
          fetchData: (searchText, page) {
            return request(HttpApi.supplierList, {
              'sids': [_bsid],
              'suptype': '0',
              'cond': searchText,
              'is_page': 1,
              'page': page,
              'pagesize': 20,
            }).then((result) {
              final data = result['data'];
              return data is Map<String, dynamic> ? data : null;
            });
          },
          multiSelect: true,
          mapMultiResult: (selected) {
            return {
              'selected': selected.map((item) {
                final supid = item['supid']?.toString() ?? '';
                final name = item['name']?.toString() ?? '';
                final code = item['code']?.toString() ?? '';
                return <String, dynamic>{
                  'stypeid': supid,
                  'stypename': code.isNotEmpty ? '[$code]$name' : name,
                  'stypecode': code,
                  'memo': '',
                };
              }).toList(),
            };
          },
        ),
      ),
    );
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusManager.instance.primaryFocus?.unfocus();
    });
    if (result == null) return;
    final selected = result['selected'] as List? ?? [];
    _mergeTypeItems(selected.cast<Map<String, dynamic>>());
  }

  /// 选择品牌（多选）
  Future<void> _selectBrandItems() async {
    if (_bsid == null || _bsid!.isEmpty) {
      Toast.show('请先选择机构');
      return;
    }
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CommonSelectPage(
          title: '选择品牌',
          searchHint: '输入品牌名称/编码',
          fetchData: (searchText, page) {
            return request(HttpApi.brandList, {
              'sids': [_bsid],
              'name': searchText,
              'is_page': 1,
              'page': page,
              'pagesize': 20,
            }).then((result) {
              final data = result['data'];
              return data is Map<String, dynamic> ? data : null;
            });
          },
          multiSelect: true,
          mapMultiResult: (selected) {
            return {
              'selected': selected.map((item) {
                final name = item['name']?.toString() ?? '';
                final code = item['code']?.toString() ?? '';
                return <String, dynamic>{
                  'stypeid': name,
                  'stypename': code.isNotEmpty ? '[$code]$name' : name,
                  'stypecode': code,
                  'memo': '',
                };
              }).toList(),
            };
          },
        ),
      ),
    );
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusManager.instance.primaryFocus?.unfocus();
    });
    if (result == null) return;
    final selected = result['selected'] as List? ?? [];
    _mergeTypeItems(selected.cast<Map<String, dynamic>>());
  }

  static Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    bool disabled = false,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // 星号固定占位，文字始终从同一起点对齐
          SizedBox(
            width: 8,
            child: required
                ? const Text('*',
                    style: TextStyle(fontSize: 14, color: Color(0xFFD54B5A)))
                : null,
          ),
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !disabled,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '请输入',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSelectRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool disabled = false,
    bool required = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          // 星号固定占位，文字始终从同一起点对齐
          SizedBox(
            width: 8,
            child: required
                ? const Text('*',
                    style: TextStyle(fontSize: 14, color: Color(0xFFD54B5A)))
                : null,
          ),
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '请选择',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (!disabled) const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
        ]),
      ),
    );
  }

  static Widget _buildDivider() =>
      const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 14, endIndent: 14);
}
