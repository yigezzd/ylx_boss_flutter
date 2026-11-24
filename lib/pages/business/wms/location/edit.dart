import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 读取接口字段并转为字符串（兼容 dynamic 返回）
String _pick(Map<String, dynamic> map, String key) {
  final Object? value = map[key];
  return value?.toString() ?? '';
}

/// WMS 货位新增/编辑页（对齐小程序 wms/location/edit.vue、PC rackCode/pop.vue）
class WmsLocationEditPage extends StatefulWidget {
  const WmsLocationEditPage({
    super.key,
    this.id,
    this.locationid,
    this.storeId,
    this.storeName,
  });

  /// 货位主键（两个字段都需要传递，后端按各自值匹配）
  final String? id;
  final String? locationid;

  /// 列表带入的机构（新增时优先使用，未传则取当前登录机构）
  final String? storeId;
  final String? storeName;

  @override
  State<WmsLocationEditPage> createState() => _WmsLocationEditPageState();
}

class _WmsLocationEditPageState extends State<WmsLocationEditPage> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _dangerColor = Color(0xFFD54B5A);

  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _channelCtrl = TextEditingController();
  final TextEditingController _pickorderCtrl = TextEditingController();
  final TextEditingController _warnQtyCtrl = TextEditingController();
  final TextEditingController _maxQtyCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();

  String _id = '';
  String _locationid = '';
  String _storeId = '';
  String _storeName = '';
  String _counterId = '';
  String _counterName = '';
  String _counterType = '';
  String _zoneId = '';
  String _zoneName = '';
  int _zoneType = 1;
  int _locationRule = 1;
  int _stopflag = 0;

  /// 绑定商品（小程序专属：单选，最多一条）
  Map<String, dynamic>? _bindProduct;

  bool _loading = false;
  bool _saving = false;

  bool get _isEdit => _id.isNotEmpty || _locationid.isNotEmpty;

  /// 通道：自定义规则拣货位、存货位、收货暂存时显示
  bool get _showChannel =>
      (_locationRule == 1 && _zoneType == 1) || _zoneType == 2 || _zoneType == 3;

  String get _zoneTypeLabel => const <int, String>{1: '拣货位', 2: '存货位', 3: '收货暂存'}[_zoneType] ?? '';

  String get _pageTitle => _isEdit ? '编辑货位' : '新增货位';

  @override
  void initState() {
    super.initState();
    final String id = widget.id ?? '';
    final String locationid = widget.locationid ?? '';
    if (id.isNotEmpty || locationid.isNotEmpty) {
      _loadDetail();
      return;
    }
    _initLoginStore();
    // 列表带入的机构优先，其次默认当前登录机构
    final String listStoreId = widget.storeId ?? '';
    if (listStoreId.isNotEmpty) {
      _storeId = listStoreId;
      _storeName = widget.storeName ?? '';
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _channelCtrl.dispose();
    _pickorderCtrl.dispose();
    _warnQtyCtrl.dispose();
    _maxQtyCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  /// 读取当前登录机构（默认值）
  void _initLoginStore() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(storeStr);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      _storeId = _pick(decoded, 'id');
      _storeName = _pick(decoded, 'name');
    } catch (_) {}
  }

  /// 详情：查询时必须带 queryproductflag=1，后端才会返回 productlist
  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> result = await request(
        HttpApi.locationGet,
        <String, dynamic>{
          'id': widget.id ?? '',
          'locationid': widget.locationid ?? '',
          'queryproductflag': 1,
        },
      );
      if (!mounted) {
        return;
      }
      final Object? raw = result['data'];
      final Map<String, dynamic> data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final Object? location = data['location'];
      final Map<String, dynamic> info = location is Map<String, dynamic> ? location : data;

      final Object? plist = data['productlist'] ?? info['productlist'];
      Map<String, dynamic>? bindProduct;
      if (plist is List && plist.isNotEmpty) {
        final Object? first = plist.first;
        if (first is Map<String, dynamic>) {
          bindProduct = Map<String, dynamic>.from(first);
        }
      }

      setState(() {
        // 返回体未带主键时用入参兜底，保证保存走 update 分支
        final String id = _pick(info, 'id');
        final String locationid = _pick(info, 'locationid');
        _id = id.isNotEmpty ? id : (widget.id ?? '');
        _locationid = locationid.isNotEmpty ? locationid : (widget.locationid ?? '');
        _codeCtrl.text = _pick(info, 'locationcode');
        _nameCtrl.text = _pick(info, 'locationname');
        _storeId = _pick(info, 'storeid');
        _storeName = _pick(info, 'storename');
        _counterId = _pick(info, 'counterid');
        _counterName = _pick(info, 'countername');
        _counterType = _pick(info, 'countertype');
        _zoneId = _pick(info, 'stockzoneid');
        _zoneName = _pick(info, 'zonename');
        _zoneType = int.tryParse(_pick(info, 'zonetype')) ?? 1;
        _locationRule = int.tryParse(_pick(info, 'locationrule')) ?? 1;
        _stopflag = int.tryParse(_pick(info, 'stopflag')) ?? 0;
        _channelCtrl.text = _pick(info, 'channel');
        _pickorderCtrl.text = _pick(info, 'pickorder');
        _warnQtyCtrl.text = _pick(info, 'replenishwarningqty');
        _maxQtyCtrl.text = _pick(info, 'maxstockqty');
        _remarkCtrl.text = _pick(info, 'remark');
        _bindProduct = bindProduct;
      });
    } catch (_) {
      // 请求层已统一提示错误
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ────────────────────────── 机构 / 仓库 / 库区 ──────────────────────────

  Future<void> _openStoreSelect() async {
    final Map<String, dynamic>? result = await SelectStorePage.show(
      context,
      initialSelectedId: _storeId.isNotEmpty ? _storeId : null,
    );
    if (result == null || !mounted) {
      return;
    }
    final String storeId = _pick(result, 'storeid');
    if (storeId.isEmpty || storeId == _storeId) {
      return;
    }
    setState(() {
      _storeId = storeId;
      _storeName = _pick(result, 'storename');
      // 机构变化后清空仓库、库区（与 PC 端一致）
      _counterId = '';
      _counterName = '';
      _counterType = '';
      _zoneId = '';
      _zoneName = '';
    });
  }

  Future<void> _openCounterSelect() async {
    if (_storeId.isEmpty) {
      Toast.show('请先选择机构');
      return;
    }
    final Map<String, dynamic>? result = await CommonSelectSheet.show(
      context,
      title: '选择仓库',
      searchHint: '输入仓库名称/编码',
      nameField: 'countername',
      codeField: 'countercode',
      idField: 'counterid',
      initialSelectedId: _counterId.isNotEmpty ? _counterId : null,
      fetchData: (String searchText, int page) => request(HttpApi.counterGetList, <String, dynamic>{
        'is_page': 1,
        'page': page,
        'pagesize': 20,
        'cond': searchText,
        'sids': <String>[_storeId],
      }).then((Map<String, dynamic> res) {
        final Object? data = res['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (Map<String, dynamic> item) => <String, dynamic>{
        'counterid': _pick(item, 'counterid'),
        'countername': _pick(item, 'countername'),
        'countertype': _pick(item, 'countertype'),
      },
    );
    if (result == null || !mounted) {
      return;
    }
    final String counterId = _pick(result, 'counterid');
    if (counterId.isEmpty || counterId == _counterId) {
      return;
    }
    setState(() {
      _counterId = counterId;
      _counterName = _pick(result, 'countername');
      _counterType = _pick(result, 'countertype');
      // 仓库变化后清空库区（与 PC 端一致）
      _zoneId = '';
      _zoneName = '';
    });
  }

  Future<void> _openZoneSelect() async {
    if (_counterId.isEmpty) {
      Toast.show('请先选择仓库');
      return;
    }
    final Map<String, dynamic>? result = await CommonSelectSheet.show(
      context,
      title: '选择库区',
      searchHint: '输入库区编码或名称',
      showAll: true,
      idField: 'stockzoneid',
      initialSelectedId: _zoneId.isNotEmpty ? _zoneId : null,
      fetchData: (String searchText, int page) =>
          request(HttpApi.storageZoneGetList, <String, dynamic>{
        'is_page': 1,
        'page': page,
        'pagesize': 20,
        'cond': searchText,
        'sids': _storeId,
        'counterid': _counterId,
      }).then((Map<String, dynamic> res) {
        final Object? data = res['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (Map<String, dynamic> item) => <String, dynamic>{
        'stockzoneid': _pick(item, 'stockzoneid'),
        'name': _pick(item, 'name'),
        'zonetype': item['zonetype'],
      },
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _zoneId = _pick(result, 'stockzoneid');
      _zoneName = _zoneId.isEmpty ? '' : _pick(result, 'name');
      // 库区类型跟随库区带出；清空库区时保留原类型
      final Object? zonetype = result['zonetype'];
      if (zonetype != null && zonetype.toString().isNotEmpty) {
        _zoneType = int.tryParse(zonetype.toString()) ?? 1;
      }
    });
  }

  // ────────────────────────── 绑定商品（小程序专属） ──────────────────────────

  /// 只保留后端需要的商品字段
  Map<String, dynamic> _toSaveProduct(Map<String, dynamic> item) {
    const List<String> keys = <String>[
      'productid',
      'barcode',
      'productname',
      'unit',
      'unitname',
      'unitonlyid',
      'spec',
      'packagenum',
      'packageflag',
    ];
    final Map<String, dynamic> row = <String, dynamic>{};
    for (final String key in keys) {
      if (item[key] != null) {
        row[key] = item[key];
      }
    }
    if (_pick(row, 'productname').isEmpty) {
      row['productname'] = _pick(item, 'name');
    }
    // 回填时名称统一为「商品名（单位）」：绑定行直接显示单位，保存后列表/回显也可直接使用
    row['productname'] = _bindProductDisplayName(row);
    return row;
  }

  Future<void> _openProductSelect() async {
    if (_storeId.isEmpty) {
      Toast.show('请先选择机构');
      return;
    }
    final List<Map<String, dynamic>>? result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute<List<Map<String, dynamic>>>(
        builder: (_) => SelectProductPage(
          storeid: int.tryParse(_storeId),
          apiUrl: HttpApi.productGetProductUnitList,
          mergData: <String, dynamic>{
            'stockflag': 1,
            'storeid': _storeId,
            'itemstatus': '1,2',
            if (_counterType.isNotEmpty) 'memorytype': _counterType,
          },
          // 单选：点击即选中，确认后回传数组
          singleSelectMode: true,
          // 按包装单位匹配已选：同一商品多个包装（箱/件/个）时仅回显当前绑定的那一个
          unitMatch: true,
          selectList: _bindProduct == null
              ? null
              : <Map<String, dynamic>>[Map<String, dynamic>.from(_bindProduct!)],
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    // 返回空列表（用户取消了全部选择）也同步清空绑定，
    // 避免 _bindProduct 残留旧商品导致保存时仍提交原商品 ID
    setState(() => _bindProduct = result.isEmpty ? null : _toSaveProduct(result.first));
  }

  // ────────────────────────── 保存 / 删除 ──────────────────────────

  Map<String, dynamic> _buildPayload() {
    return <String, dynamic>{
      'id': _id,
      // 保存货位商品需要 locationid 定位货位：主键缺失时用 id 兜底（对齐 PC 端 storeid 兜底思路），避免后端报"未传货位"
      'locationid': _locationid.isNotEmpty ? _locationid : _id,
      'locationcode': _codeCtrl.text.trim(),
      'locationname': _nameCtrl.text.trim(),
      'storeid': _storeId,
      'storename': _storeName,
      'counterid': _counterId,
      'countername': _counterName,
      'stopflag': _stopflag,
      'stockzoneid': _zoneId,
      'zonename': _zoneName,
      'locationrule': _locationRule,
      'zonetype': _zoneType,
      'channel': _channelCtrl.text.trim(),
      'pickorder': _pickorderCtrl.text.trim(),
      'replenishmethod': 1,
      'replenishwarningqty': _warnQtyCtrl.text.trim(),
      'maxstockqty': _maxQtyCtrl.text.trim(),
      'remark': _remarkCtrl.text.trim(),
      // 小程序端专属：提交绑定的商品列表
      'locationproductlist': _bindProduct == null
          ? <Map<String, dynamic>>[]
          : <Map<String, dynamic>>[Map<String, dynamic>.from(_bindProduct!)],
    };
  }

  /// 保存成功后的统一处理：提示 + 保存并继续重置 / 普通保存返回上一页
  void _onSaved(bool continueAdd) {
    Toast.show('保存成功');
    if (!continueAdd) {
      Navigator.pop(context, true);
      return;
    }
    // 保存并继续：仅清空货位号与绑定商品，其余沿用（与 PC 端一致）
    setState(() {
      _codeCtrl.clear();
      _bindProduct = null;
    });
  }

  /// 删除已绑定的商品：编辑态调用货位商品删除接口完成后端解绑（对齐 PC 端 rackGood 的 del），新增态仅前端移除
  Future<void> _unbindProduct() async {
    if (_bindProduct == null || _saving) {
      return;
    }
    if (!_isEdit) {
      setState(() => _bindProduct = null);
      return;
    }
    setState(() => _saving = true);
    try {
      // 删除接口为数组入参：货位字段与商品字段合并为一行（与 PC 端传入表格行的结构一致）
      final Map<String, dynamic> row = Map<String, dynamic>.from(_bindProduct!);
      row.addAll(<String, dynamic>{
        'id': _id,
        // 删除货位商品需要 locationid 定位货位：主键缺失时用 id 兜底
        'locationid': _locationid.isNotEmpty ? _locationid : _id,
        'locationcode': _codeCtrl.text.trim(),
        'storeid': _storeId,
        'storename': _storeName,
        'counterid': _counterId,
        'countername': _counterName,
        'stockzoneid': _zoneId,
      });
      await request(HttpApi.locationProductDelete, <Map<String, dynamic>>[row], true);
      if (!mounted) {
        return;
      }
      setState(() => _bindProduct = null);
      Toast.show('已解绑商品');
    } catch (_) {
      // 解绑失败：保持原状，请求层已统一提示错误
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// 识别"重复绑定"业务冲突错误（与请求层 ignoreRetmsgList 白名单文案保持一致）
  static bool _isDuplicateBindError(Map<String, dynamic> res) {
    final dynamic code = res['retcode'];
    final String msg = res['retmsg']?.toString() ?? '';
    return code?.toString() == '-1' && msg.contains('已存在相同单位的货位商品');
  }

  /// 二次确认覆盖更新：命中"重复绑定"错误时询问用户，确认后在原货位保存 payload 上追加 isdirectupdate 重新调用同一接口（对齐 PC 端 rackGood 的 confirmOverrideUpdate）
  Future<void> _confirmOverrideUpdate(String url, bool continueAdd) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('当前商品已绑定其他货位号，确定改为绑定当前货位号？',
            style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      // isdirectupdate：由后端在该参数下直接完成改绑（原 update 失败重提 update / 原 add 失败重提 add）
      final Map<String, dynamic> payload = _buildPayload()..['isdirectupdate'] = 1;
      await request(url, payload, true);
      if (!mounted) {
        return;
      }
      _onSaved(continueAdd);
    } catch (_) {
      // 改绑再次失败：请求层已统一提示错误
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _save({required bool continueAdd}) async {
    if (_saving) {
      return;
    }
    if (_codeCtrl.text.trim().isEmpty) {
      Toast.show('请输入货位号');
      return;
    }
    if (_zoneType == 1 && _locationRule == 0) {
      Toast.show('请选择货位规则');
      return;
    }
    if (_storeId.isEmpty) {
      Toast.show('请选择机构');
      return;
    }
    if (_counterId.isEmpty) {
      Toast.show('请选择仓库');
      return;
    }

    final String url = _isEdit ? HttpApi.locationUpdate : HttpApi.locationAdd;
    setState(() => _saving = true);
    try {
      // ignoreRetmsgList：仅命中"重复绑定"业务冲突时不弹全局错误提示，正常返回交由下方识别（对齐 PC 端同名配置）
      final Map<String, dynamic> res = await request(
        url,
        _buildPayload(),
        true,
        true,
        null,
        null,
        const <String>['已存在相同单位的货位商品'],
      );
      if (!mounted) {
        return;
      }
      // 白名单放行后在此拦截默认提示，改为二次确认改绑（与 PC 端 saveRow 一致）
      if (_isDuplicateBindError(res)) {
        _confirmOverrideUpdate(url, continueAdd);
        return;
      }
      _onSaved(continueAdd);
    } catch (e) {
      if (!mounted) {
        return;
      }
      // 兜底：白名单未命中（如后端文案有细微差异）被请求层以异常抛出时，再次识别重复绑定错误
      if (e.toString().contains('已存在相同单位的货位商品')) {
        _confirmOverrideUpdate(url, continueAdd);
        return;
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _delete() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('确定删除该货位吗？', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doDelete();
            },
            child: const Text('确定', style: TextStyle(color: _dangerColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _doDelete() async {
    setState(() => _saving = true);
    try {
      // 对齐小程序：删除接口为数组入参
      await request(HttpApi.locationDelete, <Map<String, dynamic>>[_buildPayload()], true);
      if (!mounted) {
        return;
      }
      Toast.show('删除成功');
      Navigator.pop(context, true);
    } catch (_) {
      // 请求层已统一提示错误
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// 货位规则说明（对应 PC 端货位规则后的提示图标）
  void _showRuleTip() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('货位号规则说明', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text(
          '一、自定义规则：自行编辑货位号，拣货顺序优先按通道号，再按拣货顺序号，默认最小数数字排最前。\n二、按系统规则：默认8位数字 01020304，前两位通道，第三四位货架，第五六位层，第七八位货位号，系统按通道、货架、层、货位号顺序拣货。',
          style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF333333)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  // ────────────────────────── 页面构建 ──────────────────────────

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
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Column(
                  children: <Widget>[
                    _buildInputRow('货位号', _codeCtrl,
                        required: true, maxLength: 10, digitsOnly: true),
                    _buildInputRow('货位名称', _nameCtrl, maxLength: 20),
                    if (_zoneType == 1) _buildRuleRow(),
                    _buildSelectRow('机构名称', _storeName, required: true, onTap: _openStoreSelect),
                    _buildSelectRow('仓库名称', _counterName,
                        required: true, onTap: _openCounterSelect),
                    _buildSelectRow('库区名称', _zoneName, onTap: _openZoneSelect),
                    _buildTextRow('库区类型', _zoneTypeLabel),
                    if (_showChannel)
                      _buildInputRow('通道', _channelCtrl, maxLength: 2, digitsOnly: true),
                    if (_zoneType == 1 && _locationRule == 1)
                      _buildInputRow('拣货顺序号', _pickorderCtrl, maxLength: 2, digitsOnly: true),
                    if (_zoneType == 1 || _zoneType == 2)
                      _buildInputRow('补货预警', _warnQtyCtrl, maxLength: 8, digitsOnly: true),
                    if (_zoneType == 1 || _zoneType == 2)
                      _buildInputRow('最大储存量', _maxQtyCtrl, maxLength: 8, digitsOnly: true),
                    _buildStatusRow(),
                    _buildInputRow('备注', _remarkCtrl, maxLines: 3),
                    // 仅拣货位库区可绑定商品，存货位/收货暂存库区不展示
                    if (_zoneType == 1) _buildProductRow(),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
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
      child: Row(
        children: <Widget>[
          Expanded(
            child: _isEdit
                ? _buildButton(label: '删除', isDanger: true, onPressed: _saving ? null : _delete)
                : _buildButton(
                    label: '保存并继续',
                    onPressed: _saving ? null : () => _save(continueAdd: true),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildButton(
              label: _saving ? '保存中...' : '保存',
              isPrimary: true,
              onPressed: _saving ? null : () => _save(continueAdd: false),
            ),
          ),
        ],
      ),
    );
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
      textColor = _dangerColor;
      borderColor = _dangerColor;
    } else if (isPrimary) {
      bgColor = _primaryColor;
      textColor = Colors.white;
      borderColor = _primaryColor;
    } else {
      bgColor = Colors.white;
      textColor = _primaryColor;
      borderColor = _primaryColor;
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
        child: Text(label, style: TextStyle(fontSize: 15, color: textColor)),
      ),
    );
  }

  // ────────────────────────── 表单行组件 ──────────────────────────

  Widget _buildLabel(String label, {bool required = false, double width = 118}) {
    return SizedBox(
      width: width,
      child: Row(
        children: <Widget>[
          if (required) const Text('* ', style: TextStyle(fontSize: 13, color: Color(0xFFD54B5A))),
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
        ],
      ),
    );
  }

  Widget _buildInputRow(
    String label,
    TextEditingController controller, {
    bool required = false,
    int? maxLength,
    bool digitsOnly = false,
    int maxLines = 1,
    String hint = '请输入',
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(vertical: maxLines > 1 ? 12 : 0),
            child: _buildLabel(label, required: required),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              keyboardType: digitsOnly ? TextInputType.number : TextInputType.text,
              inputFormatters: <TextInputFormatter>[
                if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
                if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
              ],
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFC0C0C0)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
          children: <Widget>[
            _buildLabel(label, required: required),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : '请选择',
                style: TextStyle(
                  fontSize: 14,
                  color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFC0C0C0),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: <Widget>[
          _buildLabel(label),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadio(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? _primaryColor : const Color(0xFFD1D5DB),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? _primaryColor : const Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: <Widget>[
          _buildLabel('货位规则', required: true, width: 90),
          _buildRadio('自定义规则', _locationRule == 1, () => setState(() => _locationRule = 1)),
          const SizedBox(width: 10),
          _buildRadio('按系统规则', _locationRule == 2, () => setState(() => _locationRule = 2)),
          const Spacer(),
          GestureDetector(
            onTap: _showRuleTip,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.help_outline, size: 18, color: _dangerColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: <Widget>[
          _buildLabel('状态', required: true),
          Expanded(
            child: Row(
              children: <Widget>[
                _buildRadio('启用', _stopflag == 0, () => setState(() => _stopflag = 0)),
                const SizedBox(width: 24),
                _buildRadio('停用', _stopflag == 1, () => setState(() => _stopflag = 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 绑定商品展示名：商品名（单位），区分同名商品的包装单位，与选择页展示口径一致；名称已含单位后缀时不重复拼接
  String _bindProductDisplayName(Map<String, dynamic> product) {
    final String name = _pick(product, 'productname').isNotEmpty
        ? _pick(product, 'productname')
        : _pick(product, 'name');
    if (name.isEmpty) {
      return '';
    }
    final String unit =
        _pick(product, 'unit').isNotEmpty ? _pick(product, 'unit') : _pick(product, 'unitname');
    if (unit.isEmpty) {
      return name;
    }
    if (name.contains('（$unit）') || name.contains('($unit)')) {
      return name;
    }
    return '$name（$unit）';
  }

  Widget _buildProductRow() {
    final Map<String, dynamic>? product = _bindProduct;
    final String name = product == null ? '' : _bindProductDisplayName(product);
    final String barcode = product == null ? '' : _pick(product, 'barcode');
    return GestureDetector(
      onTap: _openProductSelect,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            _buildLabel('绑定商品'),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name.isNotEmpty ? name : '请选择商品',
                    style: TextStyle(
                      fontSize: 14,
                      color: name.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFC0C0C0),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (barcode.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        barcode,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A)),
                      ),
                    ),
                ],
              ),
            ),
            if (product != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _unbindProduct,
                behavior: HitTestBehavior.opaque,
                // 删除按钮独立热区：单击仅清空绑定，不会触发外层 _openProductSelect 跳转
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Icon(Icons.delete_outline, size: 20, color: Color(0xFF999999)),
                ),
              ),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
  }
}
