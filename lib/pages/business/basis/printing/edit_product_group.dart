import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/pro_details_sheet.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/barcode_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// 商品分组管理页（新增/编辑/查看）
/// 业务逻辑参考 Vue boss 项目 subs/basis/printing/receipts/editproduct.vue
///
/// isEdit: 1 = 编辑模式，2 = 查看/选择模式
class EditProductGroupPage extends StatefulWidget {
  const EditProductGroupPage({
    super.key,
    this.groupId = '',
    this.isEdit = 1,
  });
  final String groupId;

  /// 1=编辑模式，2=查看模式
  final int isEdit;

  @override
  State<EditProductGroupPage> createState() => _EditProductGroupPageState();
}

class _EditProductGroupPageState extends State<EditProductGroupPage> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _textColor = Color(0xFF333333);
  static const Color _subTextColor = Color(0xFF7A7A7A);
  static const Color _bgColor = Color(0xFFF5F6FA);

  final TextEditingController _nameController = TextEditingController();

  /// 分组基本信息
  Map<String, dynamic> _groupInfo = {};

  /// 商品列表
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  bool _isDelMode = false; // 批量删除模式
  bool _allChecked = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _getAppBarTitle() {
    if (widget.isEdit == 1) {
      return widget.groupId.isNotEmpty ? '修改商品分组' : '新增商品分组';
    }
    return '商品分组详情';
  }

  String _getStoreId() {
    final storeStr = SpUtil.getString(Constant.store) ?? '';
    try {
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        return storeMap['id']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  // ─── 数据加载 ───

  Future<void> _loadData() async {
    if (widget.groupId.isEmpty) {
      // 新增模式
      setState(() => _loading = false);
      return;
    }

    try {
      final res = await request(
          HttpApi.labelProductGroupGetInfo,
          {
            'groupid': widget.groupId,
          },
          true);

      if (res['retcode'] == 0 && mounted) {
        final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
        final orders = (data['labelProductGroupDetailResps'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        for (final item in orders) {
          item['checked'] = false;
        }
        data.remove('labelProductGroupDetailResps');

        setState(() {
          _groupInfo = data;
          _orders = orders;
          _nameController.text = data['groupname']?.toString() ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── 商品操作 ───

  /// 扫码添加商品（对齐小程序 editproduct.vue scanFn）
  Future<void> _scanProduct() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (barcode == null || barcode.trim().isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }

    // 尝试解析条码秤生成的重量码/金额码（对齐小程序 scanFn）
    final scaleInfo = parseScaleBarcode(barcode);
    final searchCode = scaleInfo?.productCode ?? barcode;

    try {
      final res = await request(
          HttpApi.productGetList,
          {
            'scancode': searchCode,
            'is_page': 1,
            'page': 1,
            'pagesize': 10,
            'itemstatus': '1,2',
            'field': 'barcode',
            'type': 'desc',
          },
          true);
      if (!mounted) return;

      if (res['retcode'] != 0) return;
      final list = (res['data']?['list'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];

      // 未查询到商品或返回数据无效（无 productid）时友好提示
      if (list.isEmpty || (list[0]['productid']?.toString() ?? '').isEmpty) {
        Toast.show('未查询到该商品');
        return;
      }
      // 同码多条判定（对齐小程序 scanFn）：自编码命中多条 → 跳转选品页；
      // 无自编码命中且商品条码命中多条 → 跳转选品页，由用户手动挑选
      final codeList = list
          .where(
              (c) => (c['code']?.toString() ?? '').isNotEmpty && c['code'].toString() == searchCode)
          .toList();
      final barcodeList = list
          .where((c) =>
              (c['barcode']?.toString() ?? '').isNotEmpty && c['barcode'].toString() == searchCode)
          .toList();
      final needJump = codeList.length >= 2 || (codeList.isEmpty && barcodeList.length >= 2);
      if (needJump) {
        // 选品页按扫码词过滤候选商品，多选返回后覆盖明细（与 selectProductFn 一致）
        final result = await _openSelectProduct(keyword: searchCode);
        _applySelectProductResult(result);
        return;
      }
      // 单条命中：优先取与自编码/商品条码精确匹配的商品，否则取第一条（对齐小程序 scanFn）
      Map<String, dynamic> item = Map<String, dynamic>.from(list[0]);
      if (codeList.length == 1) {
        item = Map<String, dynamic>.from(codeList[0]);
      } else if (codeList.isEmpty && barcodeList.length == 1) {
        item = Map<String, dynamic>.from(barcodeList[0]);
      }
      // 接口无论扫主条码还是子单位条码均返回主商品行（barcode 恒为主条码），
      // 判重须以实际扫描条码为准：同一商品扫不同单位条码视为不同，不覆盖
      item['barcode'] = searchCode;
      item.remove('productbarcode');
      final existIdx = _orders.indexWhere((o) => _isSameProductItem(item, o));

      int targetIdx;
      if (existIdx >= 0) {
        // 相同商品（同条码）：覆盖已有行数据（保留原勾选状态）；
        // 同步刷新行条码为本次扫描码，保证重复扫同一子单位条码时仍命中覆盖
        final preservedChecked = _orders[existIdx]['checked'] == true;
        setState(() {
          _orders[existIdx] = item;
          _orders[existIdx]['checked'] = preservedChecked;
        });
        targetIdx = existIdx;
      } else {
        // 不同商品：新增到列表首位
        item['checked'] = false;
        setState(() {
          _orders.insert(0, item);
        });
        targetIdx = 0;
      }

      // 打开商品详情弹窗
      _openProDetails(targetIdx);
    } catch (_) {
      Toast.show('查询商品失败');
    }
  }

  /// 同一商品判断：按 productid + barcode 组合判重（对齐促销调价单 isSameProductItem）；
  /// 任一方条码为空时按 productid 判重
  static bool _isSameProductItem(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a['productid']?.toString() != b['productid']?.toString()) return false;
    final aBarcode = (a['productbarcode'] ?? a['barcode'])?.toString() ?? '';
    final bBarcode = (b['productbarcode'] ?? b['barcode'])?.toString() ?? '';
    if (aBarcode.isEmpty || bBarcode.isEmpty) return true;
    return aBarcode == bBarcode;
  }

  /// 打开商品详情弹窗（对齐小程序 proDetails 组件）
  Future<void> _openProDetails(int index) async {
    if (index < 0 || index >= _orders.length) return;
    final item = _orders[index];
    final storeid = _getStoreId();

    // 深拷贝，防止修改时污染原始数据；
    // 本页不需要 unitname/sizename 赋值给 unit/size 回显（对齐小程序 editFn 注释掉的回显）
    final clone = Map<String, dynamic>.from(item);
    final result = await ProDetailsSheet.show(
      context,
      item: clone,
      storeid: storeid,
      mergData: {'bsid': storeid},
      syncNameToValue: false,
    );

    if (result != null && mounted && index >= 0 && index < _orders.length) {
      setState(() {
        final target = _orders[index];
        // 对齐小程序 detailConfirm：直接比较单位/规格是否变更
        final unitChanged = result['unitonlyid']?.toString() != target['unitonlyid']?.toString();
        final sizeChanged = result['sizeonlyid']?.toString() != target['sizeonlyid']?.toString();
        if (result['barcode'] != null) target['productbarcode'] = result['barcode'];
        // 更新单位
        if (result['unit'] != null) target['unit'] = result['unit'];
        if (result['unitonlyid'] != null) target['unitonlyid'] = result['unitonlyid'];
        // 更新规格
        if (result['size'] != null) target['size'] = result['size'];
        if (result['sizeonlyid'] != null) target['sizeonlyid'] = result['sizeonlyid'];
        // 条码优先级 sbarcode > barcode
        final sbarcode = result['sbarcode']?.toString() ?? '';
        if (sbarcode.isNotEmpty) {
          target['productbarcode'] = result['sbarcode'];
        } else if (result['barcode'] != null) {
          target['productbarcode'] = result['barcode'];
        }
        // 自编码
        if (result['scode'] != null) {
          target['productcode'] = result['scode'];
        } else if (result['code'] != null) {
          target['productcode'] = result['code'];
        }
        // 单位名称：item.sunit || item.unit
        final sunit = result['sunit']?.toString() ?? '';
        final unitName = sunit.isNotEmpty ? result['sunit'] : result['unit'];
        if (unitName != null && unitName.toString().isNotEmpty) {
          target['unit'] = unitName;
        }
        // 单位变更时清空规格，规格变更时清空单位
        // if (unitChanged) target['size'] = '';
        // if (sizeChanged) target['unit'] = '';
        // 规格名称：item.sname || item.size
        final sname = result['sname']?.toString() ?? '';
        final sizeName = sname.isNotEmpty ? result['sname'] : result['size'];
        if (sizeName != null && sizeName.toString().isNotEmpty) {
          target['size'] = sizeName;
        }
        // 价格字段随单位/规格切换更新（弹窗已按新行同步价格白名单，列表零售价/会员价需跟随）
        for (final key in ProDetailsSheet.defaultPriceFields) {
          if (result[key] != null) target[key] = result[key];
        }
      });
    }
  }

  /// 选择商品（多选，对齐小程序 selectProductFn）
  Future<void> _selectProduct() async {
    final result = await _openSelectProduct();
    _applySelectProductResult(result);
  }

  /// 跳转商品选择页（多选），扫码同码多条时带关键词过滤候选商品（对齐小程序 selectProductFn/scanFn）
  Future<List<Map<String, dynamic>>?> _openSelectProduct({String? keyword}) async {
    final storeid = int.tryParse(_getStoreId());
    return Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          storeid: storeid,
          multiple: true,
          selectList: _orders,
          // 扫码词过滤：选品页按该关键词展示候选商品（对齐小程序 cond）
          initialKeyword: keyword,
        ),
      ),
    );
  }

  /// 选品页返回数据处理（对齐小程序 onSelectProduct：orders = res）
  void _applySelectProductResult(List<Map<String, dynamic>>? result) {
    if (result == null || !mounted) return;
    setState(() {
      _orders = result.map((item) {
        item['checked'] = false;
        return item;
      }).toList();
    });
  }

  // ─── 删除模式 ───

  void _toggleDelMode() {
    if (_orders.isEmpty) return;
    setState(() {
      _isDelMode = !_isDelMode;
      if (!_isDelMode) {
        _allChecked = false;
        for (final item in _orders) {
          item['checked'] = false;
        }
      }
    });
  }

  void _toggleAll() {
    final newVal = !_allChecked;
    setState(() {
      _allChecked = newVal;
      for (final item in _orders) {
        item['checked'] = newVal;
      }
    });
  }

  void _toggleItem(int index) {
    setState(() {
      _orders[index]['checked'] = !(_orders[index]['checked'] == true);
      _allChecked = _orders.every((e) => e['checked'] == true);
    });
  }

  /// 批量删除选中商品
  void _batchDelete() {
    final count = _orders.where((e) => e['checked'] == true).length;
    if (count == 0) {
      Toast.show('请选择要删除的商品');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: Text('确定删除$count条数据吗？', style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _orders.removeWhere((e) => e['checked'] == true);
                _isDelMode = false;
                _allChecked = false;
              });
            },
            child: const Text('确定', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  // ─── 保存 / 删除分组 ───

  Future<void> _save() async {
    final groupname = _nameController.text.trim();
    if (groupname.isEmpty) {
      Toast.show('请输入分组商品名称');
      return;
    }
    if (_orders.isEmpty) {
      Toast.show('请选择商品');
      return;
    }

    final params = <String, dynamic>{
      'groupid': widget.groupId,
      'groupname': groupname,
      'updatetype': 1,
      'datatype': _groupInfo['datatype'] ?? 0,
      'subtype': _groupInfo['subtype'] ?? 0,
      'orders': _orders
    };

    try {
      final res = await request(HttpApi.labelProductGroupSave, params, true);
      if (res['retcode'] == 0 && mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {}
  }

  Future<void> _deleteGroup() async {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: const Text('确定删除吗？', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final res = await request(HttpApi.labelProductGroupDelete, _groupInfo, true);
                if (res['retcode'] == 0 && mounted) {
                  Toast.show('删除成功');
                  Navigator.pop(context, true);
                }
              } catch (_) {}
            },
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 查看模式下确认选中
  void _confirmSelect() {
    final selected = _orders.where((e) => e['checked'] == true).toList();
    if (selected.isEmpty) {
      Toast.show('至少选择一条数据');
      return;
    }
    // 每个选中商品设置 qty=1
    for (final item in selected) {
      item['qty'] = 1;
    }
    Navigator.pop(context, selected);
  }

  // ─── 页面构建 ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MyAppBar(centerTitle: _getAppBarTitle()),
      backgroundColor: _bgColor,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 分组名称输入（编辑模式，独立卡片）
                  _buildNameInput(),
                  // 商品明细标题 + 列表（同一个白色卡片内）
                  Expanded(child: _buildDetailSection()),
                  // 底部按钮
                  _buildBottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildNameInput() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Text('*', style: TextStyle(fontSize: 14, color: Colors.red)),
          const Text('商品分组名称', style: TextStyle(fontSize: 14, color: _textColor)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _nameController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: '请输入',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// 商品明细区域（标题 + 列表 在同一个白色卡片内，对齐小程序 tm-sheet）
  Widget _buildDetailSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 商品明细标题 + 操作按钮
          _buildDetailHeader(),
          // 商品列表
          Expanded(child: _buildProductList()),
        ],
      ),
    );
  }

  Widget _buildDetailHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Row(
        children: [
          const Text('商品明细',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF000000))),
          const Spacer(),
          // 编辑模式下的操作按钮
          if (widget.isEdit == 1) ...[
            _buildActionBtn(
                icon: Icons.delete_outline,
                label: '删除',
                color: _primaryColor,
                onTap: _toggleDelMode),
            const SizedBox(width: 8),
            _buildActionBtn(
                icon: Icons.qr_code_scanner,
                label: '扫描',
                color: _primaryColor,
                onTap: _scanProduct),
            const SizedBox(width: 8),
            _buildActionBtn(
                icon: Icons.add_circle_outline,
                label: '新增',
                color: _primaryColor,
                onTap: _selectProduct),
          ],
        ],
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList() {
    // 对齐小程序：仅查看模式(isEdit==2)在单项显示复选框，删除模式只在底部全选
    final showItemCheckbox = widget.isEdit == 2 || _isDelMode;

    if (_orders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 50, color: Color(0xFFCCCCCC)),
            SizedBox(height: 8),
            Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
          ],
        ),
      );
    }

    return ListView.builder(
      cacheExtent: 800,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: _orders.length,
      itemBuilder: (ctx, i) {
        final item = _orders[i];
        final name = item['name']?.toString() ?? '';
        final size = item['size']?.toString() ?? '';
        final unit = item['unit']?.toString() ?? '';
        final mprice1 = double.tryParse(item['mprice1']?.toString() ?? '') ?? 0;
        final sellprice = double.tryParse(item['sellprice']?.toString() ?? '') ?? 0;
        final checked = item['checked'] == true;

        return RepaintBoundary(
          child: GestureDetector(
            onTap:
                (showItemCheckbox || _isDelMode) ? () => _toggleItem(i) : () => _openProDetails(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E2E2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$name${size.isNotEmpty ? '/$size' : ''}($unit)',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF000000)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text('会员价：${MathUtils.formatDecimal(2, mprice1)}',
                                  style: const TextStyle(fontSize: 12, color: _subTextColor)),
                            ),
                            Text('零售价：${MathUtils.formatDecimal(2, sellprice)}',
                                style: const TextStyle(fontSize: 12, color: _subTextColor)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showItemCheckbox) ...[
                    const SizedBox(width: 8),
                    Icon(
                      checked ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 22,
                      color: checked ? _primaryColor : const Color(0xFFCCCCCC),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final isEdit = widget.isEdit == 1;
    final checkedCount = _orders.where((e) => e['checked'] == true).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 删除模式 / 查看模式的全选
            if (_isDelMode || widget.isEdit == 2) ...[
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('全选，已选$checkedCount个',
                        style: const TextStyle(fontSize: 12, color: _subTextColor)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _toggleAll,
                      child: Icon(
                        _allChecked ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 22,
                        color: _allChecked ? _primaryColor : const Color(0xFFCCCCCC),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            // 按钮
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _isDelMode && isEdit
                  ? _buildDualButtons(
                      leftLabel: '取消',
                      leftOnTap: _toggleDelMode,
                      rightLabel: '删除',
                      rightOnTap: _batchDelete,
                    )
                  : isEdit && widget.groupId.isNotEmpty
                      ? _buildDualButtons(
                          leftLabel: '删除',
                          leftOnTap: _deleteGroup,
                          rightLabel: '保存',
                          rightOnTap: _save,
                        )
                      : isEdit
                          ? _buildDualButtons(
                              leftLabel: '取消',
                              leftOnTap: () => Navigator.pop(context),
                              rightLabel: '保存',
                              rightOnTap: _save,
                            )
                          : _buildDualButtons(
                              leftLabel: '取消',
                              leftOnTap: () => Navigator.pop(context),
                              rightLabel: '确定',
                              rightOnTap: _confirmSelect,
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDualButtons({
    required String leftLabel,
    required VoidCallback leftOnTap,
    required String rightLabel,
    required VoidCallback rightOnTap,
    Color rightColor = _primaryColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: leftOnTap,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: rightColor == Colors.red ? rightColor : _primaryColor),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(leftLabel,
                  style: TextStyle(
                      fontSize: 15,
                      color: rightColor == Colors.red ? const Color(0xFF666666) : _primaryColor)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: rightOnTap,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: rightColor,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(rightLabel,
                  style: const TextStyle(
                      fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }
}
