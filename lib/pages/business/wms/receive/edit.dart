import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/receive/pallet_edit.dart';
import 'package:flutter_deer/pages/business/wms/receive/pro_edit.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 收货主页面（对齐 Vue wms/receiveTakList/edit.vue）
class WmsReceiveEditPage extends StatefulWidget {
  const WmsReceiveEditPage({super.key, required this.billid});

  final String billid;

  @override
  State<WmsReceiveEditPage> createState() => _WmsReceiveEditPageState();
}

class _WmsReceiveEditPageState extends State<WmsReceiveEditPage>
    with LogPageMixin<WmsReceiveEditPage> {
  @override
  String get logPageName => 'WMS收货';

  /// 单据数据（对齐 Vue query）
  Map<String, dynamic> _query = {};

  bool _loadingDetail = true;

  /// 当前激活 Tab：0=商品明细 1=托盘
  int _activeTab = 0;

  final TextEditingController _remarkController = TextEditingController();

  /// 已删除数据 id 映射（id -> productid），用于生成 delidlist（对齐 Vue deletedIdMap）
  final Map<String, String> _deletedIdMap = {};

  /// 门店信息
  String _storeId = '';
  String _storeName = '';

  /// 用户是否有查看供应商权限（user.supflag == 1）
  bool _supflag = false;

  @override
  void initState() {
    super.initState();
    _loadLocalInfo();
    _query = {
      'billid': widget.billid,
      'billno': '',
      'billflag': '',
      'signflag': 0,
      'supid': '',
      'supname': '',
      'bsid': _storeId,
      'storename': _storeName,
      'counterid': '',
      'countername': '',
      'remark': '',
      'createtime': '',
      'createname': '',
      'billqty': 0,
      'billreceiptqty': 0,
      'detaillist': <Map<String, dynamic>>[],
      'prosumlist': <Map<String, dynamic>>[],
      'palletlist': <Map<String, dynamic>>[],
    };
    logEnter();
    _getInfo();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  void _loadLocalInfo() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeId = storeMap['id']?.toString() ?? '';
        _storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _supflag = userMap['supflag']?.toString() == '1';
      }
    } catch (_) {}
  }

  // ────────────────────── 计算属性 ──────────────────────

  bool get _disabled => _query['signflag']?.toString() == '1';

  List<Map<String, dynamic>> get _detaillist =>
      (_query['detaillist'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  List<Map<String, dynamic>> get _prosumlist =>
      (_query['prosumlist'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  /// 单据收货状态标签（对齐 Vue billReceiptStatus，并补充 signflag 优先判断）
  /// signflag==1 表示单据已完成收货（对齐列表页 _status / Vue index 卡片状态），
  /// 否则按数量判断——避免“完成收货”后因数量未收满仍显示部分收货
  (String, Color) get _billReceiptStatus {
    if (_query['signflag']?.toString() == '1') return ('已收货', const Color(0xFF00A870));
    final billreceiptqty = double.tryParse(_query['billreceiptqty']?.toString() ?? '') ?? 0;
    final billqty = double.tryParse(_query['billqty']?.toString() ?? '') ?? 0;
    if (billreceiptqty <= 0) return ('待收货', const Color(0xFFD54B5A));
    if (billreceiptqty >= billqty) return ('已收货', const Color(0xFF00A870));
    return ('部分收货', const Color(0xFFFA8C16));
  }

  /// 商品汇总列表（对齐 Vue prosumList，兼容 name 字段）
  List<Map<String, dynamic>> get _prosumList {
    final list = _prosumlist.isNotEmpty ? _prosumlist : _detaillist;
    return list
        .map((item) => {
              ...item,
              'productname': item['productname']?.toString().isNotEmpty ?? false
                  ? item['productname']
                  : (item['name'] ?? '')
            })
        .toList();
  }

  /// 托盘分组列表（对齐 Vue palletListGrouped）
  List<Map<String, dynamic>> get _palletListGrouped {
    final map = <String, Map<String, dynamic>>{};
    for (final item in _detaillist) {
      final pc = item['palletcode']?.toString() ?? '';
      if (pc.isEmpty) continue;
      if (!map.containsKey(pc)) {
        map[pc] = {
          'palletcode': pc,
          'locationcode': item['locationcode']?.toString() ?? '',
          'locationid': item['locationid']?.toString() ?? '',
          'items': <Map<String, dynamic>>[],
        };
      }
      final group = map[pc]!;
      (group['items'] as List<Map<String, dynamic>>).add({
        ...item,
        'productname': item['productname']?.toString().isNotEmpty ?? false
            ? item['productname']
            : (item['name'] ?? ''),
      });
      if ((group['locationcode'] as String).isEmpty &&
          (item['locationcode']?.toString() ?? '').isNotEmpty) {
        group['locationcode'] = item['locationcode'];
      }
    }
    // 若 detaillist 中无托盘数据，回退到接口返回的 palletlist
    if (map.isEmpty) {
      final palletlist = (_query['palletlist'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return palletlist
          .where((p) => (p['palletcode']?.toString() ?? '').isNotEmpty)
          .map((p) => {
                'palletcode': p['palletcode'],
                'locationcode': p['locationcode']?.toString() ?? '',
                'locationid': p['locationid']?.toString() ?? '',
                'items': ((p['itemlist'] as List?) ?? [])
                    .cast<Map<String, dynamic>>()
                    .map((c) => {
                          ...c,
                          'productname': c['productname']?.toString().isNotEmpty ?? false
                              ? c['productname']
                              : (c['name'] ?? '')
                        })
                    .toList(),
              })
          .toList();
    }
    return map.values.toList();
  }

  /// 托盘码 → 货位号映射（对齐 Vue palletLocationMap）
  Map<String, Map<String, String>> get _palletLocationMap {
    final result = <String, Map<String, String>>{};
    for (final d in _detaillist) {
      final pc = d['palletcode']?.toString() ?? '';
      final lc = d['locationcode']?.toString() ?? '';
      if (pc.isNotEmpty && lc.isNotEmpty) {
        result[pc] = {
          'locationcode': lc,
          'locationid': d['locationid']?.toString() ?? '',
        };
      }
    }
    final palletlist = (_query['palletlist'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final p in palletlist) {
      final pc = p['palletcode']?.toString() ?? '';
      final lc = p['locationcode']?.toString() ?? '';
      if (pc.isNotEmpty && lc.isNotEmpty && !result.containsKey(pc)) {
        result[pc] = {
          'locationcode': lc,
          'locationid': p['locationid']?.toString() ?? '',
        };
      }
    }
    return result;
  }

  /// 订货总数
  String get _comOrderNum {
    double sum = 0;
    for (final p in _prosumList) {
      sum += double.tryParse(p['orderqty']?.toString() ?? '') ?? 0;
    }
    return MathUtils.formatDecimal(1, sum);
  }

  /// 收货总数
  String get _comReceiptNum {
    double sum = 0;
    for (final p in _prosumList) {
      sum += double.tryParse(p['receiptqty']?.toString() ?? '') ?? 0;
    }
    return MathUtils.formatDecimal(1, sum);
  }

  // ────────────────────── 数据请求 ──────────────────────

  /// 获取详情（对齐 Vue getInfo）
  Future<void> _getInfo() async {
    setState(() => _loadingDetail = true);
    try {
      final result = await request(HttpApi.wmsReceiveGetInfo, {
        'billid': widget.billid,
        'showflag': 2,
      });
      if (!mounted) return;
      final res = result['data'];
      if (res is! Map<String, dynamic>) {
        setState(() => _loadingDetail = false);
        return;
      }
      // 保存本地备注（防止被服务器空值覆盖，对齐 Vue）
      final localRemark = _query['remark']?.toString() ?? '';
      final detaillist = ((res['detaillist'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map((c) => {
                ...c,
                'productname': c['productname']?.toString().isNotEmpty ?? false
                    ? c['productname']
                    : (c['name'] ?? '')
              })
          .toList();
      final prosumlist = ((res['prosumlist'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map((c) => {
                ...c,
                'productname': c['productname']?.toString().isNotEmpty ?? false
                    ? c['productname']
                    : (c['name'] ?? ''),
                'itemlist': ((c['itemlist'] as List?) ?? [])
                    .cast<Map<String, dynamic>>()
                    .map((item) => {
                          ...item,
                          'productname': item['productname']?.toString().isNotEmpty ?? false
                              ? item['productname']
                              : (item['name'] ?? '')
                        })
                    .toList()
              })
          .toList();
      // 预先保存原始 bsid（...res 可能覆盖为 0/''）
      final originalBsid = _query['bsid'];
      _query = {
        ..._query,
        ...res,
        // 用真值回退对齐 Vue `res.outsid || res.sid || query.value.bsid`
        // Dart ?? 只检查 null；服务端返回 0 时 Vue 走 fallback 而 Flutter 不走 → bsid 丢失
        'bsid': (res['outsid']?.toString() ?? '').isNotEmpty
            ? res['outsid']
            : (res['sid']?.toString() ?? '').isNotEmpty
                ? res['sid']
                : originalBsid,
        'remark': (res['remark']?.toString() ?? '').isNotEmpty ? res['remark'] : localRemark,
        'detaillist': detaillist,
        'prosumlist': prosumlist,
        'palletlist': res['palletlist'] ?? <Map<String, dynamic>>[],
      };
      debugPrint('bsid=${_query["bsid"]}');
      _remarkController.text = _query['remark']?.toString() ?? '';
      setState(() => _loadingDetail = false);
    } catch (_) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  /// 同步 prosumlist 的 receiptqty（对齐 Vue syncProsumReceiptQty）
  /// 多规格商品：按 productid + barcode 精准匹配，仅汇总该规格/单位的收货数
  void _syncProsumReceiptQty(List<String> productIds) {
    final prosumlist = _prosumlist;
    for (int pi = 0; pi < prosumlist.length; pi++) {
      final p = prosumlist[pi];
      if (!productIds.contains(p['productid']?.toString() ?? '')) continue;
      double totalReceipt = 0;
      for (final d in _detaillist) {
        if (_sameSpec(d, p)) {
          totalReceipt += double.tryParse(d['receiptqty']?.toString() ?? '') ?? 0;
        }
      }
      prosumlist[pi] = {...p, 'receiptqty': totalReceipt};
    }
  }

  /// 保存收货数据（对齐 Vue saveReceiveTak）
  /// [productIds] 可选，指定只提交哪些商品的数据；null 则提交全部
  Future<void> _saveReceiveTak([List<String>? productIds]) async {
    final allList = _detaillist;
    final targetList = productIds == null
        ? allList
        : allList.where((d) => productIds.contains(d['productid']?.toString())).toList();

    // detaillist 已是扁平结构，直接格式化日期后提交
    final formattedList = targetList.map((d) {
      final row = Map<String, dynamic>.from(d);
      row['birthdate'] = _fmtDateStr(row['birthdate']);
      row['validdate'] = _fmtDateStr(row['validdate']);
      row.remove('itemlist');
      return row;
    }).toList();

    // 构建 delidlist：只包含与当前保存商品相关的已删除 id
    final targetProductIdSet = (productIds ?? []).toSet();
    final delidlist = <String>[];
    _deletedIdMap.forEach((id, pid) {
      if (productIds == null || targetProductIdSet.contains(pid)) {
        delidlist.add(id);
      }
    });

    final bsid = _query['bsid']?.toString() ?? '';
    if (bsid.isEmpty) {
      Toast.show('仓库信息缺失，请刷新页面重试');
      return;
    }
    Toast.show('保存中...', duration: 500);
    try {
      await request(HttpApi.wmsReceiveUpdate, {
        ..._query,
        'remark': _remarkController.text.trim(),
        'detaillist': formattedList,
        'delidlist': delidlist,
      });
      if (!mounted) return;
      logSave('保存收货');
      Toast.show('保存成功');
      // 保存成功后移除已提交的删除标记
      for (final id in delidlist) {
        _deletedIdMap.remove(id);
      }
      _getInfo();
    } catch (_) {}
  }

  /// 日期字符串截取 YYYY-MM-DD
  static String _fmtDateStr(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  /// 商品规格标识（对齐 Vue `barcode || code`）：优先条码，条码为空时回退商品编码
  static String _specKey(Map<String, dynamic> m) {
    final barcode = m['barcode']?.toString() ?? '';
    if (barcode.isNotEmpty) return barcode;
    return m['code']?.toString() ?? '';
  }

  /// 判定两行是否为同一商品同一规格（productid + barcode 完全一致），
  /// 多规格商品禁止仅凭 productid 匹配，避免串到其他规格的数据
  static bool _sameSpec(Map<String, dynamic> a, Map<String, dynamic> b) {
    return a['productid']?.toString() == b['productid']?.toString() && _specKey(a) == _specKey(b);
  }

  // ────────────────────── 扫码 ──────────────────────

  /// 扫码：商品条码（对齐 Vue scanProFn）
  Future<void> _scanPro() async {
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code == null || !mounted) return;
    final scancode = code.toString().trim();
    if (scancode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    try {
      final result = await request(HttpApi.productGetList, {
        'scancode': scancode,
        'is_page': 1,
        'page': 1,
        'pagesize': 10,
        'storeid': _storeId,
      });
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isNotEmpty) {
        final item = list[0] as Map<String, dynamic>;
        // 多规格商品需按 productid + barcode 精准匹配扫描结果（对齐 Vue scanProFn）
        final idx = _detaillist.indexWhere((d) => _sameSpec(d, item));
        if (idx > -1) {
          _goProDetail(Map<String, dynamic>.from(_detaillist[idx]));
        } else {
          Toast.show('未查询到该商品');
        }
      } else {
        Toast.show('未查询到该商品');
      }
    } catch (_) {}
  }

  /// 扫码：托盘码（对齐 Vue scanPalletFn）
  Future<void> _scanPallet() async {
    final Object? code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code == null || !mounted) return;
    final scancode = code.toString().trim();
    if (scancode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    final groups = _palletListGrouped;
    final pallet = groups.where((g) => g['palletcode'] == scancode).toList();
    if (pallet.isNotEmpty) {
      _goPalletDetail(pallet.first);
    } else {
      // 托盘不存在，打开新建托盘编辑页（对齐 Vue isNew=1）
      _openPalletEdit(
        palletcode: scancode,
        locationcode: '',
        locationid: '',
        items: const [],
        isNew: true,
      );
    }
  }

  // ────────────────────── 子页面跳转 ──────────────────────

  /// 跳转：商品收货编辑（对齐 Vue goProDetail）
  Future<void> _goProDetail(Map<String, dynamic> item) async {
    if (_disabled) {
      // 已收货只读查看
    }
    // 从 prosumlist 获取该商品完整数据（对齐 Vue goProDetail）
    // 多规格商品需按 productid + barcode 精准匹配，避免取到其他规格的数据
    final prosumItem = _prosumlist.firstWhere(
      (p) => _sameSpec(p, item),
      orElse: () => item,
    );
    // 该规格的收货明细行：优先从 detaillist 按 productid + barcode 过滤（本地最新数据），
    // 后端返回的 prosumItem.itemlist 冗余包含同 productid 下所有规格的行，不能直接使用
    final specDetailList = _detaillist.where((d) => _sameSpec(d, item)).toList();
    final batchlist = (specDetailList.isNotEmpty
            ? specDetailList
            : ((prosumItem['itemlist'] as List?) ?? [])
                .cast<Map<String, dynamic>>()
                .where((c) => _specKey(c) == _specKey(item))
                .toList())
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => WmsReceiveProEditPage(
          billInfo: {
            'billid': _query['billid'],
            'billno': _query['billno'],
            'billflag': _query['billflag'],
            'signflag': _query['signflag'],
          },
          item: {
            ...prosumItem,
            // 传参使用行副本（对齐 Vue deepClone），避免子页面修改影响父页数据
            'batchlist': batchlist,
          },
          disabled: _disabled,
          palletLocationMap: _palletLocationMap,
          bsid: _query['bsid']?.toString() ?? _storeId,
        ),
      ),
    );
    if (!mounted || result == null) return;
    _onProEditDone(result);
  }

  /// 商品编辑回传处理（对齐 Vue onProEditDone）
  void _onProEditDone(Map<String, dynamic> data) {
    final productid = data['productid']?.toString() ?? '';
    if (productid.isEmpty) return;
    final batchlist = ((data['batchlist'] as List?) ?? []).cast<Map<String, dynamic>>();
    _query['productid'] = productid;

    final detaillist = _detaillist;
    // 多规格商品需按 productid + barcode 精准匹配，仅操作当前规格/单位的记录；
    // 收集被删除的已保存数据 id
    final oldRows = detaillist.where((d) => _sameSpec(d, data)).toList();
    final newIds =
        batchlist.map((b) => b['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    for (final row in oldRows) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty && !newIds.contains(id)) {
        _deletedIdMap[id] = row['productid']?.toString() ?? '';
      }
    }
    // 获取该商品该规格的原始 detaillist 记录作为基础信息（找不到时回退 prosumlist 同规格行）
    final originalItem = detaillist.firstWhere(
      (d) => _sameSpec(d, data),
      orElse: () => _prosumlist.firstWhere(
        (p) => _sameSpec(p, data),
        orElse: () => <String, dynamic>{},
      ),
    );
    // 建立旧记录映射（按 id），用于保留原始 id
    final oldRowMap = <String, Map<String, dynamic>>{};
    for (final r in oldRows) {
      final id = r['id']?.toString() ?? '';
      if (id.isNotEmpty) oldRowMap[id] = r;
    }
    // 仅移除当前规格的旧记录，保留其他规格/单位的记录不受影响
    final newList = detaillist.where((d) => !_sameSpec(d, data)).toList();
    for (final b in batchlist) {
      final bid = b['id']?.toString() ?? '';
      final oldRow = bid.isNotEmpty ? oldRowMap[bid] : null;
      // 只有 id 完全匹配的旧记录才保留其 id，否则视为新增记录（id 为空）
      final id = (oldRow != null && oldRow['id']?.toString() == bid && bid.isNotEmpty)
          ? oldRow['id']
          : null;
      newList.add({
        ...originalItem,
        ...b,
        'id': id,
      });
      newList.last.remove('itemlist');
    }
    _query['detaillist'] = newList;
    setState(() {});
    _syncProsumReceiptQty([productid]);
    _saveReceiveTak([productid]);
  }

  /// 跳转：托盘编辑（对齐 Vue goPalletDetail）
  Future<void> _goPalletDetail(Map<String, dynamic> group) async {
    _openPalletEdit(
      palletcode: group['palletcode']?.toString() ?? '',
      locationcode: group['locationcode']?.toString() ?? '',
      locationid: group['locationid']?.toString() ?? '',
      items: ((group['items'] as List?) ?? []).cast<Map<String, dynamic>>(),
    );
  }

  Future<void> _openPalletEdit({
    required String palletcode,
    required String locationcode,
    required String locationid,
    required List<Map<String, dynamic>> items,
    bool isNew = false,
  }) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => WmsReceivePalletEditPage(
          billInfo: {
            'billid': _query['billid'],
            'billno': _query['billno'],
            'billflag': _query['billflag'],
            'signflag': _query['signflag'],
          },
          palletcode: palletcode,
          locationcode: locationcode,
          locationid: locationid,
          items: items.map((e) => Map<String, dynamic>.from(e)).toList(),
          palletLocationMap: _palletLocationMap,
          billProductList: _prosumlist.isNotEmpty ? _prosumlist : _detaillist,
          storeid: _storeId,
        ),
      ),
    );
    if (!mounted || result == null) return;
    _onPalletEditDone(result, isNew: isNew);
  }

  /// 托盘编辑回传处理（对齐 Vue onPalletEditDone）
  void _onPalletEditDone(Map<String, dynamic> data, {bool isNew = false}) {
    final items = ((data['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (items.isEmpty) return;
    final palletcode = data['palletcode']?.toString() ?? '';
    final locationcode = data['locationcode']?.toString() ?? '';
    final locationid = data['locationid']?.toString() ?? '';

    final detaillist = _detaillist;
    // 收集被删除的已保存数据 id（旧记录中有但新 items 中没有的 productid+batchno 组合）
    final oldRows = detaillist.where((d) => d['palletcode']?.toString() == palletcode).toList();
    final newKeys = items.map((p) => '${p['productid']}_${p['batchno'] ?? ''}').toSet();
    for (final row in oldRows) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty && !newKeys.contains('${row['productid']}_${row['batchno'] ?? ''}')) {
        _deletedIdMap[id] = row['productid']?.toString() ?? '';
      }
    }
    // 建立旧记录映射（按 productid + batchno），用于保留原始 id
    final oldRowMap = <String, Map<String, dynamic>>{};
    for (final r in oldRows) {
      oldRowMap['${r['productid']}_${r['batchno'] ?? ''}'] = r;
    }
    // 移除该托盘的旧 detaillist 记录，用新数据替换
    final newList = detaillist.where((d) => d['palletcode']?.toString() != palletcode).toList();
    for (final pitem in items) {
      final baseProduct = _prosumlist.firstWhere(
        (p) => p['productid']?.toString() == pitem['productid']?.toString(),
        orElse: () => <String, dynamic>{},
      );
      final oldRow = oldRowMap['${pitem['productid']}_${pitem['batchno'] ?? ''}'];
      // 只有 productid + batchno 完全匹配的旧记录才保留其 id；否则 id 为空（新增记录）
      final id = (oldRow != null && oldRow['batchno'] == pitem['batchno']) ? oldRow['id'] : null;
      // 排除 baseProduct 的 id，防止产品级 id 污染批次记录
      final baseWithoutId = Map<String, dynamic>.from(baseProduct);
      baseWithoutId.remove('id');
      newList.add({
        ...baseWithoutId,
        ...pitem,
        'id': id,
        'palletcode': palletcode,
        'locationcode': locationcode,
        'locationid': locationid,
      });
      newList.last.remove('itemlist');
    }
    _query['detaillist'] = newList;
    final affectedProductIds = items.map((p) => p['productid']?.toString() ?? '').toSet().toList();
    if (affectedProductIds.isNotEmpty) {
      _query['productid'] = affectedProductIds.first;
    }
    setState(() {});
    _syncProsumReceiptQty(affectedProductIds);
    _saveReceiveTak(affectedProductIds);
  }

  // ────────────────────── 操作 ──────────────────────

  /// 完成收货（对齐 Vue finishReceive）
  Future<void> _finishReceive() async {
    final list = _prosumList;
    if (list.isEmpty) {
      Toast.show('暂无商品明细');
      return;
    }
    final pendingItems = list.where((item) {
      final receiptqty = double.tryParse(item['receiptqty']?.toString() ?? '') ?? 0;
      return receiptqty <= 0;
    }).toList();
    if (pendingItems.isNotEmpty) {
      Toast.show('还有${pendingItems.length}项商品待收货');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确认完成收货？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final bsid = _query['bsid']?.toString() ?? '';
    if (bsid.isEmpty) {
      Toast.show('仓库信息缺失，请刷新页面重试');
      return;
    }
    try {
      await request(HttpApi.wmsFinishReceiveTak, {
        ..._query,
        'remark': _remarkController.text.trim(),
      });
      if (!mounted) return;
      logSave('完成收货');
      Toast.show('操作成功');
      Navigator.pop(context, true);
    } catch (_) {}
  }

  /// 打印（对齐 Vue setPrintData）
  Future<void> _print() async {
    try {
      await request(HttpApi.wmsReceivePrint, {
        'menuid': '011907',
        'data': _query,
      });
      if (!mounted) return;
      logSave('打印');
      Toast.show('打印成功');
    } catch (_) {}
  }

  // ────────────────────── UI ──────────────────────

  @override
  Widget build(BuildContext context) {
    final (String statusLabel, Color statusColor) = _billReceiptStatus;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '采购收货',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: _loadingDetail
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    cacheExtent: 800,
                    children: [
                      // ── 单据头信息 ──
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '单号：${_query['billno'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF111827),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                _StatusLabel(label: statusLabel, color: statusColor),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '制单：${_query['createtime'] ?? ''}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                                  ),
                                ),
                                Text(
                                  _query['createname']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ── 基本信息 ──
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              label: '供应商',
                              required: true,
                              child: Text(
                                _supflag ? (_query['supname']?.toString() ?? '') : '****',
                                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _buildInfoRow(
                              label: '仓库',
                              required: true,
                              showDivider: true,
                              child: Text(
                                _query['countername']?.toString() ?? '',
                                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // 备注（多行输入：标签与输入框顶对齐，与其他字段行基线一致）
                            _buildInfoRow(
                              label: '备注',
                              crossAxisAlignment: CrossAxisAlignment.start,
                              child: TextField(
                                controller: _remarkController,
                                enabled: !_disabled,
                                maxLines: 2,
                                // 输入实时回写 _query['remark']（对齐 Vue v-model.lazy=query.remark），
                                // 保证 getInfo 刷新/打印等路径取到的备注均为最新输入
                                onChanged: (v) => _query['remark'] = v,
                                decoration: InputDecoration(
                                  hintText: _disabled ? '' : '请输入备注',
                                  hintStyle:
                                      const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ── 商品明细 / 托盘 双Tab ──
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tab 切换头
                            Row(
                              children: [
                                _buildTabHead('商品明细', 0),
                                const SizedBox(width: 16),
                                _buildTabHead('托盘(${_palletListGrouped.length})', 1),
                                const Spacer(),
                                if (!_disabled)
                                  GestureDetector(
                                    onTap: _activeTab == 0 ? _scanPro : _scanPallet,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.qr_code_scanner,
                                            size: 15, color: Color(0xFF006EFF)),
                                        const SizedBox(width: 3),
                                        Text(
                                          _activeTab == 0 ? '扫描商品码' : '扫描托盘码',
                                          style: const TextStyle(
                                              fontSize: 13, color: Color(0xFF006EFF)),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // 商品明细列表
                            if (_activeTab == 0) ..._buildProsumList(),
                            // 托盘列表
                            if (_activeTab == 1) ..._buildPalletList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // ── 底部统计 + 操作按钮 ──
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                  ),
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 8,
                    bottom: MediaQuery.of(context).padding.bottom + 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '订货数：$_comOrderNum，收货数：$_comReceiptNum',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                      ),
                      const SizedBox(height: 8),
                      if (_disabled)
                        // 已收货：打印按钮
                        GestureDetector(
                          onTap: () {
                            if (!PermissionUtils.checkPermission('011907', showTip: false)) {
                              Toast.show('你无权打印，请在后台修改权限');
                              return;
                            }
                            _print();
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: PermissionUtils.checkPermission('011907', showTip: false)
                                  ? const Color(0xFF006EFF)
                                  : const Color(0xFFB0C8EE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              '打印',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                          ),
                        )
                      else
                        // 待收货：完成收货按钮
                        GestureDetector(
                          onTap: () {
                            if (!PermissionUtils.checkPermission('011902', showTip: false)) {
                              Toast.show('你无权完成收货，请在后台修改权限');
                              return;
                            }
                            _finishReceive();
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: PermissionUtils.checkPermission('011902', showTip: false)
                                  ? const Color(0xFF006EFF)
                                  : const Color(0xFFB0C8EE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              '完成收货',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTabHead(String label, int index) {
    final active = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? const Color(0xFF006EFF) : const Color(0xFF333333),
              ),
            ),
          ),
          Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF006EFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required Widget child,
    bool required = false,
    bool showDivider = false,
    // 多行输入（如备注）传 start，使标签与输入框首行顶对齐，与其他字段基线一致
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: showDivider ? const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))) : null,
      ),
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          SizedBox(
            width: 80,
            // 标签文字固定从列左缘排版；必填星号经 Stack 叠放于文字左外侧，
            // 不占位推挤文字，保证有无星号字段的标签左缘一致（对齐 SelectFieldItem）
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                ),
                if (required)
                  const Positioned(
                    left: -10,
                    top: 0,
                    child: Text(
                      '*',
                      style: TextStyle(fontSize: 14, color: Color(0xFFD54B5A)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// 商品明细列表
  List<Widget> _buildProsumList() {
    final list = _prosumList;
    if (list.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          ),
        ),
      ];
    }
    return [
      for (int i = 0; i < list.length; i++)
        RepaintBoundary(
          child: _ProsumItemCard(
            item: list[i],
            showTopDivider: i > 0,
            onTap: () => _goProDetail(list[i]),
          ),
        ),
    ];
  }

  /// 托盘分组列表
  List<Widget> _buildPalletList() {
    final groups = _palletListGrouped;
    if (groups.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          ),
        ),
      ];
    }
    return [
      for (final group in groups)
        RepaintBoundary(
          child: _PalletGroupCard(
            group: group,
            onTap: () => _goPalletDetail(group),
          ),
        ),
    ];
  }
}

/// 状态标签（待收货/部分收货/已收货）
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

/// 商品明细卡片（对齐 Vue prosumlist 项）
class _ProsumItemCard extends StatelessWidget {
  const _ProsumItemCard({
    required this.item,
    required this.onTap,
    this.showTopDivider = false,
  });
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool showTopDivider;

  static (String, Color) _status(Map<String, dynamic> item) {
    final receiptqty = double.tryParse(item['receiptqty']?.toString() ?? '') ?? 0;
    final qty = double.tryParse(item['qty']?.toString() ?? '') ?? 0;
    if (receiptqty > 0 && receiptqty >= qty) {
      return ('已收货', const Color(0xFF00A870));
    }
    if (receiptqty > 0) return ('部分收货', const Color(0xFFFA8C16));
    return ('待收货', const Color(0xFFD54B5A));
  }

  @override
  Widget build(BuildContext context) {
    final productname = item['productname']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    final barcode = item['barcode']?.toString().isNotEmpty ?? false
        ? item['barcode'].toString()
        : (item['code']?.toString() ?? '');
    final batchno = item['batchno']?.toString() ?? '';
    final orderqty = MathUtils.formatDecimal(1, item['orderqty'] ?? 0);
    final receiptqty = MathUtils.formatDecimal(1, item['receiptqty'] ?? 0);
    final (String statusLabel, Color statusColor) = _status(item);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: showTopDivider ? const Border(top: BorderSide(color: Color(0xFFE2E2E2))) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '$productname${size.isNotEmpty ? '（$size）' : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusLabel(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    barcode,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (batchno.isNotEmpty)
                  Text(
                    '批：$batchno',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '订货数：$orderqty',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
                ),
                Text(
                  '收货数：$receiptqty',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 托盘分组卡片（对齐 Vue pallet-group）
class _PalletGroupCard extends StatelessWidget {
  const _PalletGroupCard({required this.group, required this.onTap});
  final Map<String, dynamic> group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palletcode = group['palletcode']?.toString() ?? '';
    final locationcode = group['locationcode']?.toString() ?? '';
    final items = ((group['items'] as List?) ?? []).cast<Map<String, dynamic>>();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E2E2)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 组头：托盘号 + 货位号
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Row(
                children: [
                  const Text(
                    '托盘号：',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                  Text(
                    palletcode,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '货位号：${locationcode.isEmpty ? '-' : locationcode}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
                ],
              ),
            ),
            // 组内商品行
            for (int i = 0; i < items.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  border: i < items.length - 1
                      ? const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))
                      : null,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${items[i]['productname'] ?? ''}${(items[i]['size']?.toString() ?? '').isNotEmpty ? '（${items[i]['size']}）' : ''}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '批次：${items[i]['batchno'] ?? ''}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '条码：${items[i]['barcode'] ?? ''}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '数量：${MathUtils.formatDecimal(1, items[i]['receiptqty'] ?? 0)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
