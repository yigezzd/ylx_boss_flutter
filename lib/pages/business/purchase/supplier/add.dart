import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/select/select_buyer.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/purchase/supplier/file_edit.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 供应商新增/编辑/详情页面 —— 对齐 boss 项目 supRecord/edit.vue
///
/// mode: 1=新增, 2=编辑, 0=查看
class SupplierAddPage extends StatefulWidget {
  // 1=新增, 2=编辑, 0=查看

  const SupplierAddPage({super.key, this.supplierId, this.mode = 1});
  final String? supplierId;
  final int mode;

  @override
  State<SupplierAddPage> createState() => _SupplierAddPageState();
}

class _SupplierAddPageState extends State<SupplierAddPage>
    with SingleTickerProviderStateMixin, LogPageMixin<SupplierAddPage> {
  @override
  String get logPageName => _mode == 1 ? '供应商新增' : (widget.supplierId != null ? '供应商编辑' : '供应商新增');

  late TabController _tabController;
  bool _saving = false;

  // ── 证照信息（对齐 lxAss supplierFilesList，随供应商保存整体提交） ──
  List<Map<String, dynamic>> _supplierFiles = [];

  // ── 表单数据 ──
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _linkmanCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _faxCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _initamtCtrl = TextEditingController();
  final _advanceCtrl = TextEditingController();
  final _maxbillamtCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _bankaccountCtrl = TextEditingController();
  final _businesslicenseCtrl = TextEditingController();
  final _taxidCtrl = TextEditingController();
  final _deductionrateCtrl = TextEditingController(); // 扣率

  String _suptype = '';
  String _suptypename = '';
  int _supselltype = 1; // 默认购销
  String _salesmanid = '';
  String _salesmanname = '';
  String _supid = '';
  String _id = ''; // 记录ID，与boss项目 query.value.id 对齐，用于删除和编辑

  // 与 boss 项目 queryDefault 对齐的扩展字段
  String _mnemoniccode = ''; // 助记码
  int _initamtflag = 0; // 是否生成期初金额
  int _wxsupbillsignflag = 0; // 微信单据签名
  String _suparea = ''; // 供应商区域
  String _imgurl = ''; // 货商图片
  String _certoforigimgurl = ''; // 产品证明图片
  String _supusercode = ''; // 账户
  String _supuserpwd = ''; // 密码
  String _supuserrole = ''; // 货商角色
  String _infomore = ''; // 合同范本信息

  /// 保存 API 返回的完整原始数据（对齐 boss 项目 query.value = res）
  /// 保存时以此为基础合并编辑字段，确保不丢失后端下发的字段
  Map<String, dynamic> _originalData = {};

  late int _mode; // 当前模式

  // 经销方式列表
  static const List<Map<String, dynamic>> _supsellList = [
    {'label': '购销', 'id': 1},
    {'label': '联营', 'id': 2},
    {'label': '成本代销', 'id': 3},
    {'label': '扣率代销', 'id': 4},
    {'label': '租赁', 'id': 5},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 底部按钮栏需根据当前 Tab 变化（证照 Tab 显示添加证照按钮）
    _tabController.addListener(_onTabChanged);
    _mode = widget.mode;

    if (_mode == 1) {
      // 新增：自动生成编码
      _generateCode();
    } else if (widget.supplierId != null && widget.supplierId!.isNotEmpty) {
      // 编辑/查看：加载详情
      _getInfo(widget.supplierId!);
    }
    logEnter();
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _linkmanCtrl.dispose();
    _mobileCtrl.dispose();
    _faxCtrl.dispose();
    _addressCtrl.dispose();
    _initamtCtrl.dispose();
    _advanceCtrl.dispose();
    _maxbillamtCtrl.dispose();
    _remarkCtrl.dispose();
    _bankCtrl.dispose();
    _bankaccountCtrl.dispose();
    _businesslicenseCtrl.dispose();
    _taxidCtrl.dispose();
    _deductionrateCtrl.dispose();
    super.dispose();
  }

  bool get _isReadOnly => _mode == 0;

  /// 联营(2)、扣率代销(4)、租赁(5) 类型时显示扣率字段
  bool get _showDeductionRate => _supselltype == 2 || _supselltype == 4 || _supselltype == 5;

  String get _pageTitle {
    switch (_mode) {
      case 1:
        return '新增供应商';
      case 2:
        return '编辑供应商';
      default:
        return '供应商详情';
    }
  }

  /// 自动生成供应商编码
  void _generateCode() {
    request(HttpApi.supplierGenerateCode, <String, dynamic>{}).then((result) {
      final data = result['data'];
      if (mounted && data != null) {
        setState(() {
          _codeCtrl.text = data.toString();
        });
      }
    }).catchError((_) {});
  }

  /// 获取供应商详情
  void _getInfo(String id) {
    request(HttpApi.supplierGetInfo, id, true).then((result) {
      final res = result['data'];
      if (!mounted || res == null) return;
      final Map<String, dynamic> data = res is Map<String, dynamic> ? res : {};

      // 保留完整原始响应，保存时以此为基础合并（对齐 boss deepClone 模式）
      _originalData = Map<String, dynamic>.from(data);

      setState(() {
        _id = data['id']?.toString() ?? '';
        _supid = data['supid']?.toString() ?? data['id']?.toString() ?? '';
        _codeCtrl.text = data['code']?.toString() ?? '';
        _nameCtrl.text = data['name']?.toString() ?? '';
        _linkmanCtrl.text = data['linkman']?.toString() ?? '';
        _mobileCtrl.text = data['mobile']?.toString() ?? '';
        _faxCtrl.text = data['fax']?.toString() ?? '';
        _addressCtrl.text = data['address']?.toString() ?? '';
        _remarkCtrl.text = data['remark']?.toString() ?? '';
        _bankCtrl.text = data['bank']?.toString() ?? '';
        _bankaccountCtrl.text = data['bankaccount']?.toString() ?? '';
        _businesslicenseCtrl.text = data['businesslicense']?.toString() ?? '';
        _taxidCtrl.text = data['taxid']?.toString() ?? '';
        _suptype = data['suptype']?.toString() ?? '';
        _suptypename = data['suptypename']?.toString() ?? '';
        _supselltype = int.tryParse(data['supselltype']?.toString() ?? '1') ?? 1;
        _salesmanid = data['salesmanid']?.toString() ?? '';
        _salesmanname = data['salesmanname']?.toString() ?? '';

        // 证照资料列表（对齐 lxAss：getSupplierInfo 返回 supplierFilesList）
        _supplierFiles = _parseSupplierFiles(data['supplierFilesList']);

        // 扩展字段（与 boss 项目 queryDefault 对齐）
        _mnemoniccode = data['mnemoniccode']?.toString() ?? '';
        _initamtflag = int.tryParse(data['initamtflag']?.toString() ?? '0') ?? 0;
        _wxsupbillsignflag = int.tryParse(data['wxsupbillsignflag']?.toString() ?? '0') ?? 0;
        _suparea = data['suparea']?.toString() ?? '';
        _imgurl = data['imgurl']?.toString() ?? '';
        _certoforigimgurl = data['certoforigimgurl']?.toString() ?? '';
        _supusercode = data['supusercode']?.toString() ?? '';
        _supuserpwd = data['supuserpwd']?.toString() ?? '';
        _supuserrole = data['supuserrole']?.toString() ?? '';
        _infomore = data['infomore']?.toString() ?? '';

        // 金额字段格式化
        _initamtCtrl.text = _formatAmount(data['initamt']);
        _advanceCtrl.text = _formatAmount(data['advance']);
        _maxbillamtCtrl.text = _formatAmount(data['maxbillamt']);
        // 扣率字段
        final dr = data['joinrate'];
        _deductionrateCtrl.text = (dr != null && dr.toString().isNotEmpty) ? dr.toString() : '';
      });
    }).catchError((_) {});
  }

  String _formatAmount(dynamic val) {
    if (val == null) return '0.000';
    final d = double.tryParse(val.toString());
    if (d == null) return '0.000';
    return d.toStringAsFixed(3);
  }

  /// 保存
  Future<void> _save({bool continueAdd = false}) async {
    if (_saving) return;

    // 权限校验：区分新增/编辑
    if (_mode == 1) {
      if (!PermissionUtils.checkPermission('011102', showTip: false)) {
        Toast.show('你无权新增供应商，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('011104', showTip: false)) {
        Toast.show('你无权编辑供应商，请在后台修改权限');
        return;
      }
    }
    logSave(continueAdd ? '保存并继续新增' : '保存');

    // 校验
    if (_codeCtrl.text.trim().isEmpty) {
      Toast.show('请输入供应商编码');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      Toast.show('请输入供应商名称');
      return;
    }
    if (_suptype.isEmpty) {
      Toast.show('请选择供应商分类');
      return;
    }

    setState(() => _saving = true);

    // 以原始 API 数据为基础合并编辑字段（对齐 boss 项目 deepClone(query.value) 模式）
    // 确保后端下发的所有字段（含 joinrate 等）不丢失
    final Map<String, dynamic> params = Map<String, dynamic>.from(_originalData);

    // 覆盖用户可编辑的字段
    params['supid'] = _supid;
    params['id'] = _id.isNotEmpty ? _id : (widget.supplierId ?? '');
    params['code'] = _codeCtrl.text.trim();
    params['name'] = _nameCtrl.text.trim();
    params['mobile'] = _mobileCtrl.text.trim();
    params['fax'] = _faxCtrl.text.trim();
    params['linkman'] = _linkmanCtrl.text.trim();
    params['address'] = _addressCtrl.text.trim();
    params['supselltype'] = _supselltype;
    params['suptype'] = _suptype;
    params['suptypename'] = _suptypename;
    params['suparea'] = _suparea;
    params['salesmanid'] = _salesmanid;
    params['salesmanname'] = _salesmanname;
    params['bank'] = _bankCtrl.text.trim();
    params['bankaccount'] = _bankaccountCtrl.text.trim();
    params['taxid'] = _taxidCtrl.text.trim();
    params['businesslicense'] = _businesslicenseCtrl.text.trim();
    params['mnemoniccode'] = _mnemoniccode;
    params['remark'] = _remarkCtrl.text.trim();
    params['initamt'] = _initamtCtrl.text.trim();
    params['advance'] = _advanceCtrl.text.trim();
    params['maxbillamt'] = _maxbillamtCtrl.text.trim();
    params['initamtflag'] = _initamtflag;
    params['stopflag'] = 0;
    params['wxsupbillsignflag'] = _wxsupbillsignflag;
    params['imgurl'] = _imgurl;
    params['certoforigimgurl'] = _certoforigimgurl;
    params['supusercode'] = _supusercode;
    params['supuserpwd'] = _supuserpwd;
    params['supuserrole'] = _supuserrole;
    params['infomore'] = _infomore;

    // 证照资料随主表一起保存（对齐 lxAss：query.supplierFilesList 整体提交）
    params['supplierFilesList'] = _supplierFiles;

    // 扣率字段：对齐 boss 项目传参，始终传 joinrate（不做条件清空）
    // boss 项目在 getInfo 时将 joinrate 存入 query.value，保存时原样回传
    final String drText = _deductionrateCtrl.text.trim();
    if (drText.isNotEmpty) {
      // 尝试转为数值类型，与后端字段类型保持一致
      final double? drNum = double.tryParse(drText);
      params['joinrate'] = drNum ?? drText;
    } else {
      // 空值时保持原始数据中的值（不覆盖为空字符串）
      // 如果原始数据中也没有该字段，则设为 null
      if (!params.containsKey('joinrate')) {
        params['joinrate'] = null;
      }
    }

    try {
      await request(HttpApi.supplierSave, params);
      Toast.show('保存成功');
      if (continueAdd) {
        // 保存并继续：清空表单
        _clearForm();
        _generateCode();
      } else if (_mode == 2) {
        // 编辑模式保存后返回
        if (mounted) Navigator.pop(context, true);
      } else {
        if (mounted) Navigator.pop(context, true);
      }
    } catch (_) {
      // 错误已在 http_helper 中统一 Toast
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearForm() {
    setState(() {
      _id = '';
      _supid = '';
      _codeCtrl.clear();
      _nameCtrl.clear();
      _linkmanCtrl.clear();
      _mobileCtrl.clear();
      _faxCtrl.clear();
      _addressCtrl.clear();
      _initamtCtrl.text = '0.000';
      _advanceCtrl.text = '0.000';
      _maxbillamtCtrl.text = '0.000';
      _remarkCtrl.clear();
      _bankCtrl.clear();
      _bankaccountCtrl.clear();
      _businesslicenseCtrl.clear();
      _taxidCtrl.clear();
      _deductionrateCtrl.clear();
      _suptype = '';
      _suptypename = '';
      _supselltype = 1;
      _salesmanid = '';
      _salesmanname = '';
      _supplierFiles = [];
      _mnemoniccode = '';
      _initamtflag = 0;
      _wxsupbillsignflag = 0;
      _suparea = '';
      _imgurl = '';
      _certoforigimgurl = '';
      _supusercode = '';
      _supuserpwd = '';
      _supuserrole = '';
      _infomore = '';
    });
  }

  /// 删除
  void _delete() {
    if (!PermissionUtils.checkPermission('011103', showTip: false)) {
      Toast.show('你无权删除供应商，请在后台修改权限');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('提示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: const Text('确定删除吗？', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _doDelete();
              },
              child: const Text('确定', style: TextStyle(color: Color(0xFFD54B5A))),
            ),
          ],
        );
      },
    );
  }

  void _doDelete() {
    // 与boss项目一致：使用 id 字段删除（非 supid）
    final id = _id.isNotEmpty ? _id : (_supid.isNotEmpty ? _supid : (widget.supplierId ?? ''));
    if (id.isEmpty) return;

    request(HttpApi.supplierDelete, {'id': id}, true).then((_) {
      Toast.show('删除成功');
      if (mounted) Navigator.pop(context, true);
    }).catchError((_) {});
  }

  // ── 供应商分类选择（children 树形结构，参考商品分类） ──
  void _selectClass() {
    List<Map<String, dynamic>> treeData = [];
    bool treeLoading = true;

    request(HttpApi.supplierTypeGetList, <String, dynamic>{
      // 对齐 Vue selectSupClass 默认查询参数
      'is_page': '0',
      'stopflag': '',
      'cond': '',
    })
        .then((result) {
          final data = result['data'];
          if (data is Map<String, dynamic>) {
            final list = data['children'] as List? ?? data['alllist'] as List? ?? [];
            treeData = list.cast<Map<String, dynamic>>();
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          if (!mounted) return;
          treeLoading = false;
          _showTreeClassPicker(treeData, treeLoading);
        });
  }

  /// 将树形数据展平为带深度的列表
  List<_TreePickerNode> _flattenPickerTree(List<Map<String, dynamic>> nodes, int depth) {
    final result = <_TreePickerNode>[];
    for (final node in nodes) {
      result.add(_TreePickerNode(node: node, depth: depth));
      final children = node['children'] as List? ?? [];
      if (children.isNotEmpty) {
        result.addAll(_flattenPickerTree(children.cast<Map<String, dynamic>>(), depth + 1));
      }
    }
    return result;
  }

  void _showTreeClassPicker(List<Map<String, dynamic>> treeData, bool treeLoading) {
    final Set<String> expandedIds = {};

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final flatNodes = _flattenPickerTree(treeData, 0);

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        const SizedBox(width: 48),
                        const Expanded(
                          child: Text(
                            '选择供应商分类',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
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
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  if (treeLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
                    )
                  else if (flatNodes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child:
                          Text('暂无分类数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        cacheExtent: 800,
                        shrinkWrap: true,
                        itemCount: flatNodes.length,
                        itemBuilder: (_, i) {
                          final data = flatNodes[i];
                          final node = data.node;
                          // 对齐 Vue selectSupClass：valueKey 为 typeid（非 id）
                          final id = node['typeid']?.toString() ?? '';
                          final name = node['name']?.toString() ?? '';
                          final code = node['code']?.toString() ?? '';
                          final children = node['children'] as List? ?? [];
                          final hasChildren = children.isNotEmpty;
                          final isExpanded = expandedIds.contains(id);
                          final selected = _suptype == id;

                          return RepaintBoundary(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() {
                                  _suptype = id;
                                  _suptypename = code.isNotEmpty ? '[$code]$name' : name;
                                });
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: EdgeInsets.only(
                                  left: 16.0 + data.depth * 28.0,
                                  right: 16,
                                  top: 12,
                                  bottom: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                                  border:
                                      const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                                ),
                                child: Row(
                                  children: [
                                    // 展开/折叠图标
                                    if (hasChildren)
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setSheetState(() {
                                            if (isExpanded) {
                                              expandedIds.remove(id);
                                            } else {
                                              expandedIds.add(id);
                                            }
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(
                                            isExpanded
                                                ? Icons.keyboard_arrow_down
                                                : Icons.chevron_right,
                                            size: 18,
                                            color: const Color(0xFF6B7280),
                                          ),
                                        ),
                                      )
                                    else
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: SizedBox(width: 18),
                                      ),
                                    // 名称
                                    Expanded(
                                      child: Text(
                                        code.isNotEmpty ? '[$code]$name' : name,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: selected
                                              ? const Color(0xFF006EFF)
                                              : const Color(0xFF333333),
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : (data.depth == 0
                                                  ? FontWeight.w500
                                                  : FontWeight.normal),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    _buildRadio(selected),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  SizedBox(height: MediaQuery.of(ctx).padding.bottom),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 构建单选框（参考商品分类选择样式）
  Widget _buildRadio(bool isSelected) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
          width: 2,
        ),
        color: isSelected ? const Color(0xFF006EFF) : Colors.white,
      ),
      child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
    );
  }

  // ── 业务员选择 ──
  Future<void> _selectSalesman() async {
    final result = await SelectBuyerPage.show(context, initialSelectedId: _salesmanid);
    if (result != null && mounted) {
      setState(() {
        _salesmanid = result['buyerid']?.toString() ?? '';
        _salesmanname = result['buyername']?.toString() ?? '';
      });
    }
  }

  // ── 经销方式选择 ──
  void _selectSupselltype() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('选择经销方式',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ..._supsellList.map((item) {
                final selected = _supselltype == item['id'];
                return GestureDetector(
                  onTap: () {
                    setState(() => _supselltype = item['id'] as int);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)),
                      ],
                    ),
                  ),
                );
              }),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  String _getSupsellLabel() {
    for (final item in _supsellList) {
      if (item['id'] == _supselltype) return item['label'] as String;
    }
    return '购销';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _pageTitle,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: ColoredBox(
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
                Tab(text: '其他信息'),
                Tab(text: '证照信息'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBasicTab(),
          _buildOtherTab(),
          _buildFileTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ──────────── 基本信息 Tab ────────────
  Widget _buildBasicTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          children: [
            _buildInputRow('供应商编码', _codeCtrl, required: true, enabled: !_isReadOnly),
            _buildInputRow('供应商名称', _nameCtrl, required: true, enabled: !_isReadOnly),
            _buildSelectRow('供应商分类', _suptypename, onTap: () {
              if (!_isReadOnly) _selectClass();
            }, required: true),
            _buildInputRow('联系人', _linkmanCtrl, enabled: !_isReadOnly),
            _buildInputRow('手机号码', _mobileCtrl,
                enabled: !_isReadOnly, keyboard: TextInputType.phone),
            _buildInputRow('传真号码', _faxCtrl, enabled: !_isReadOnly),
            _buildSelectRow('业务员', _salesmanname, onTap: () {
              if (!_isReadOnly) _selectSalesman();
            }),
            _buildInputRow('地址', _addressCtrl, enabled: !_isReadOnly),
            _buildInputRow('期初金额', _initamtCtrl,
                enabled: !_isReadOnly,
                keyboard: const TextInputType.numberWithOptions(decimal: true)),
            _buildInputRow('预付款金额', _advanceCtrl,
                enabled: false, // 预付款金额不允许手动录入
                keyboard: const TextInputType.numberWithOptions(decimal: true)),
            _buildInputRow('年采购额度(0为不限制)', _maxbillamtCtrl,
                enabled: !_isReadOnly,
                keyboard: const TextInputType.numberWithOptions(decimal: true)),
            _buildSelectRow('经销方式', _getSupsellLabel(), onTap: () {
              if (!_isReadOnly) _selectSupselltype();
            }),
            // 联营(2)、扣率代销(4)、租赁(5) 时显示扣率
            if (_showDeductionRate)
              _buildInputRow(
                '扣率(%)',
                _deductionrateCtrl,
                enabled: !_isReadOnly,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_DeductionRateFormatter()],
              ),
            _buildInputRow('备注', _remarkCtrl, enabled: !_isReadOnly, maxLines: 3),
          ],
        ),
      ),
    );
  }

  // ──────────── 其他信息 Tab ────────────
  Widget _buildOtherTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          children: [
            _buildInputRow('开户行', _bankCtrl, enabled: !_isReadOnly),
            _buildInputRow('银行账户', _bankaccountCtrl, enabled: !_isReadOnly),
            _buildInputRow('营业执照', _businesslicenseCtrl, enabled: !_isReadOnly),
            _buildInputRow('税务登记号', _taxidCtrl, enabled: !_isReadOnly),
          ],
        ),
      ),
    );
  }

  // ──────────── 证照信息 Tab ────────────
  /// 解析后端返回的证照列表（对齐 lxAss getSupplierInfo 的 supplierFilesList）
  List<Map<String, dynamic>> _parseSupplierFiles(dynamic val) {
    if (val is! List) {
      return [];
    }
    final result = <Map<String, dynamic>>[];
    for (final item in val) {
      if (item is Map<String, dynamic>) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result;
  }

  /// 证照列表 Tab（对齐 lxAss edit.vue tab3：卡片展示证照图片/名称/编号/有效期/备注/上传信息）
  Widget _buildFileTab() {
    if (_supplierFiles.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                const Icon(Icons.perm_media_outlined, size: 56, color: Color(0xFFD1D5DB)),
                const SizedBox(height: 12),
                Text(
                  _isReadOnly ? '暂无证照信息' : '暂无证照信息，请添加',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      cacheExtent: 800,
      itemCount: _supplierFiles.length,
      itemBuilder: (_, i) {
        final item = _supplierFiles[i];
        return RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FileCard(
              item: item,
              readOnly: _isReadOnly,
              onTap: () => _openFileEdit(item),
            ),
          ),
        );
      },
    );
  }

  /// 打开证照编辑页（[row] 为空表示新增，对齐 lxAss openSupFileEdit）
  void _openFileEdit(Map<String, dynamic>? row) {
    if (_isReadOnly) {
      return;
    }
    if (!PermissionUtils.checkPermission('011104', showTip: false)) {
      Toast.show('你无权编辑供应商，请在后台修改权限');
      return;
    }
    if (row == null) {
      logAdd();
    }
    // 对齐 lxAss：spid/sid 取当前登录机构（store 缓存）
    String spid = '';
    String sid = '';
    try {
      final storeStr = SpUtil.getString('store') ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        spid = storeMap['spid']?.toString() ?? '';
        sid = storeMap['id']?.toString() ?? '';
      }
    } catch (_) {}

    Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierFileEditPage(
          row: row,
          supid: _supid.isNotEmpty ? _supid : (widget.supplierId ?? ''),
          spid: spid,
          sid: sid,
        ),
      ),
    ).then((result) {
      if (result == null || !mounted) {
        return;
      }
      final action = result['action']?.toString();
      final data = result['row'];
      if (data is! Map<String, dynamic>) {
        return;
      }
      final id = data['id']?.toString() ?? '';
      final tempkey = data['tempkey']?.toString() ?? '';
      // 按 id 或 tempkey 匹配（对齐 lxAss onSupFileSaved/onSupFileDeleted）
      final idx = _supplierFiles.indexWhere((c) {
        final cid = c['id']?.toString() ?? '';
        final ck = c['tempkey']?.toString() ?? '';
        return (id.isNotEmpty && cid == id) || (tempkey.isNotEmpty && ck == tempkey);
      });
      setState(() {
        if (action == 'save') {
          if (idx > -1) {
            _supplierFiles[idx] = data;
          } else {
            _supplierFiles.add(data);
          }
        } else if (action == 'delete' && idx > -1) {
          _supplierFiles.removeAt(idx);
        }
      });
    });
  }

  /// 添加证照（证照 Tab 底部按钮）
  void _addFile() {
    if (_isReadOnly) {
      return;
    }
    _openFileEdit(null);
  }

  // ──────────── 输入行组件 ────────────
  Widget _buildInputRow(
    String label,
    TextEditingController controller, {
    bool required = false,
    bool enabled = true,
    TextInputType? keyboard,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  if (required)
                    const Text('* ', style: TextStyle(fontSize: 13, color: Color(0xFFD54B5A))),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: keyboard,
              maxLines: maxLines,
              inputFormatters: inputFormatters,
              style: TextStyle(
                fontSize: 14,
                color: enabled ? const Color(0xFF111827) : const Color(0xFF999999),
              ),
              decoration: InputDecoration(
                hintText: enabled ? '请输入' : '',
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFC0C0C0)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 选择行组件 ────────────
  Widget _buildSelectRow(
    String label,
    String value, {
    required VoidCallback onTap,
    bool required = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Row(
                children: [
                  if (required)
                    const Text('* ', style: TextStyle(fontSize: 13, color: Color(0xFFD54B5A))),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : (_isReadOnly ? '' : '请选择'),
                style: TextStyle(
                  fontSize: 14,
                  color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFC0C0C0),
                ),
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
  }

  // ──────────── 底部按钮栏 ────────────
  Widget _buildBottomBar() {
    // 证照信息 Tab：在删除/保存按钮上方叠加“添加证照”按钮（对齐 lxAss tab3 布局）
    final bool showAddFile = _tabController.index == 2 && !_isReadOnly;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showAddFile) ...[
            GestureDetector(
              onTap: _addFile,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '添加证照',
                  style: TextStyle(fontSize: 15, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildModeButtons(),
        ],
      ),
    );
  }

  Widget _buildModeButtons() {
    if (_mode == 1) {
      // 新增模式：保存并继续 + 保存
      return Row(
        children: [
          Expanded(
            child: _buildButton(
              label: '保存并继续',
              onPressed: _saving ? null : () => _save(continueAdd: true),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildButton(
              label: '保存',
              isPrimary: true,
              onPressed: _saving ? null : () => _save(),
            ),
          ),
        ],
      );
    } else if (_mode == 0) {
      // 查看模式：删除 + 修改
      return Row(
        children: [
          Expanded(
            child: _buildButton(
              label: '删除',
              isDanger: true,
              onPressed: _delete,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildButton(
              label: '修改',
              isPrimary: true,
              onPressed: () {
                setState(() => _mode = 2);
              },
            ),
          ),
        ],
      );
    } else {
      // 编辑模式：删除 + 保存
      return Row(
        children: [
          Expanded(
            child: _buildButton(
              label: '删除',
              isDanger: true,
              onPressed: _delete,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildButton(
              label: _saving ? '保存中...' : '保存',
              isPrimary: true,
              onPressed: _saving ? null : () => _save(),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildButton({
    required String label,
    required VoidCallback? onPressed,
    bool isPrimary = false,
    bool isDanger = false,
  }) {
    final Color bgColor;
    final Color textColor;
    final Color borderColor;

    if (onPressed == null) {
      bgColor = const Color(0xFFF5F5F5);
      textColor = const Color(0xFFBDBDBD);
      borderColor = const Color(0xFFDEDEDE);
    } else if (isDanger) {
      bgColor = Colors.white;
      textColor = const Color(0xFFD54B5A);
      borderColor = const Color(0xFFD54B5A);
    } else if (isPrimary) {
      bgColor = const Color(0xFF006EFF);
      textColor = Colors.white;
      borderColor = const Color(0xFF006EFF);
    } else {
      bgColor = Colors.white;
      textColor = const Color(0xFF006EFF);
      borderColor = const Color(0xFF006EFF);
    }

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(fontSize: 15, color: textColor),
        ),
      ),
    );
  }
}

/// 树形选择器节点数据
class _TreePickerNode {
  _TreePickerNode({required this.node, required this.depth});
  final Map<String, dynamic> node;
  final int depth;
}

/// 扣率输入格式化：最大 100，两位小数
class _DeductionRateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // 只允许数字和小数点
    if (!RegExp(r'^[\d.]*$').hasMatch(text)) return oldValue;

    // 只允许一个小数点
    final dotCount = '.'.allMatches(text).length;
    if (dotCount > 1) return oldValue;

    // 小数点后最多两位
    if (dotCount == 1) {
      final parts = text.split('.');
      if (parts[1].length > 2) return oldValue;
    }

    // 数值不超过 100
    final val = double.tryParse(text);
    if (val != null && val > 100) return oldValue;

    return newValue;
  }
}

/// 证照信息卡片（对齐 lxAss edit.vue tab3：图片 + 名称/编号/有效期/备注/上传时间/上传人）
class _FileCard extends StatelessWidget {
  const _FileCard({required this.item, required this.readOnly, required this.onTap});
  final Map<String, dynamic> item;
  final bool readOnly;
  final VoidCallback onTap;

  static const Color _bgColor = Color(0xFFF5F5F5);

  /// 图片占位
  static Widget _placeholder() {
    return Container(
      width: 70,
      height: 70,
      color: _bgColor,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 30, color: Color(0xFFC0C0C0)),
    );
  }

  /// 兼容完整时间戳，统一输出 YYYY-MM-DD（无法解析时原样返回）
  static String _fmtValidtime(dynamic val) {
    if (val == null) {
      return '';
    }
    final raw = val.toString().trim();
    if (raw.isEmpty) {
      return '';
    }
    final dt = DateTime.tryParse(raw);
    if (dt == null) {
      return raw;
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// 图片地址兼容处理：完整 URL 直接使用，相对路径拼阿里云前缀（对齐 lxAss getFullUrl/attach_page）
  static String _fullUrl(String fileurl) {
    if (fileurl.isEmpty) {
      return '';
    }
    if (fileurl.startsWith('http')) {
      return fileurl;
    }
    return '${Constant.imageBaseUrl}/$fileurl';
  }

  @override
  Widget build(BuildContext context) {
    final fileurl = _fullUrl(item['fileurl']?.toString() ?? '');
    final name = item['documentname']?.toString() ?? '';
    final code = item['documentcode']?.toString() ?? '';
    final validtime = _fmtValidtime(item['validtime']);
    final remark = item['remark']?.toString() ?? '';
    final createtime = item['createtime']?.toString() ?? '';
    final opername = item['opername']?.toString() ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImage(fileurl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name.isEmpty ? '未命名证照' : name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!readOnly)
                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _infoLine('证照编号', code),
                  _infoLine('有效期', validtime),
                  _infoLine('备注', remark),
                  _infoLine('上传时间', createtime),
                  _infoLine('上传人', opername),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String fileurl) {
    return Container(
      width: 70,
      height: 70,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: fileurl.isNotEmpty
          ? Image.network(
              fileurl,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              cacheWidth: 140,
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label：$value',
        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
