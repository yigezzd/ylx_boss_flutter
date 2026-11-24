import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/product_unit_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 预盘单商品单位/规格选择（对齐 lxAss 小程序 proDetails.vue + preOrderEdit.vue）
///
/// - 可选项：bi/product/getProductExtendList，packlist 为单位、sizelist 为规格
/// - 查询参数：对齐 lxAss 预盘单 unitMergData/sizeMergData
///   （bsid 盘点机构 + counterid 盘点仓库 + needbatchflag + stockflag）；
///   单位下拉额外带 packageflag/ptype，规格下拉额外带 pspriceflag（不传 packageflag）
/// - 选中后：同步单位/规格、零售价、条码、编码、货架号，并按批次重取库存与成本价
///   （对齐 lxAss selectUnitFn/selectSizeFn + syncStockByExtend、zmProMax unitConfirm/changeSize）
class SelectUnitSizeSheet {
  SelectUnitSizeSheet._();

  /// 单位可选：商品有包装单位（对齐 proDetails.vue unitCanSelect：packageflag == 1）
  static bool canSelectUnit(Map<String, dynamic> item) => item['packageflag']?.toString() == '1';

  /// 规格可选：商品有规格且未选包装单位（对齐 proDetails.vue sizeCanSelect）
  static bool canSelectSize(Map<String, dynamic> item) =>
      item['specflag']?.toString() == '1' && _isEmpty(item['unitonlyid']);

  /// 打开弹窗时记录主规格（对齐 proDetails.vue openFn 的 sizeRevert：defsize || size）
  /// 选包装单位后规格按主规格回退
  static void initMainSize(Map<String, dynamic> item) {
    if (!_isEmpty(item['_mainSize'])) return;
    final String defsize = item['defsize']?.toString() ?? '';
    item['_mainSize'] = defsize.isNotEmpty ? defsize : (item['size']?.toString() ?? '');
    final String defsizeid = item['defsizeid']?.toString() ?? '';
    item['_mainSizeonlyid'] =
        defsizeid.isNotEmpty ? defsizeid : (item['sizeonlyid']?.toString() ?? '');
  }

  /// 查询可选单位/规格并弹出选择抽屉，取消或无可选项时返回 null
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String type,
    required Map<String, dynamic> item,
    required String bsid,
    required String counterid,
  }) async {
    final String productid = item['productid']?.toString() ?? item['prodid']?.toString() ?? '';
    if (productid.isEmpty) {
      Toast.show('商品信息异常');
      return null;
    }

    final Map<String, dynamic> params = <String, dynamic>{
      'page': 1,
      'pagesize': 99999,
      'is_page': 1,
      'cond': '',
      'commonflag': 1,
      'productid': productid,
      'bsid': bsid,
      'counterid': counterid,
      'itemtype': item['itemtype']?.toString() ?? '',
      'specflag': item['specflag']?.toString() ?? '',
      'cgpriceflag': 1,
      // 预盘单 unitMergData/sizeMergData：按门店 + 盘点仓库查询批次与库存
      'needbatchflag': 1,
      'stockflag': 1,
      if (type == 'unit') ...<String, dynamic>{
        'ptype': 1,
        'packageflag': item['packageflag']?.toString() ?? '',
      } else
        'pspriceflag': 1,
    };

    late List<Map<String, dynamic>> list;
    try {
      final result = await request(HttpApi.productGetExtendList, params);
      final dynamic data = result['data'];
      final List<dynamic> rawList = (data is Map<String, dynamic>
              ? (type == 'size' ? data['sizelist'] : data['packlist'])
              : null) as List? ??
          [];
      // 字段映射对齐 selectCom：规格 size/sname、单位 unit/sunit
      list = rawList.map<Map<String, dynamic>>((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (type == 'size') {
          m['_name'] = m['size']?.toString() ?? m['sname']?.toString() ?? '';
          m['_id'] = m['sizeonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
        } else {
          m['_name'] = m['unit']?.toString() ?? m['sunit']?.toString() ?? '';
          m['_id'] = m['unitonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
        }
        return m;
      }).toList();
    } catch (_) {
      Toast.show('获取${type == 'unit' ? '单位' : '规格'}失败');
      return null;
    }
    if (!context.mounted) return null;
    if (list.isEmpty) {
      Toast.show('无可选${type == 'unit' ? '单位' : '规格'}');
      return null;
    }

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Text('选择${type == 'unit' ? '单位' : '规格'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                cacheExtent: 800,
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final opt = list[i];
                  return ListTile(
                    title: Text(opt['_name']?.toString() ?? ''),
                    onTap: () => Navigator.pop(ctx, opt),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 应用单位/规格选择结果，直接改写 [item]：
  /// unit/size、unitonlyid/sizeonlyid、packagenum、sellprice/saleprice、
  /// barcode/code、shelves、costprice、stockqty（[stockAllBatch] 为 true 时改写 allstockqty）
  ///
  /// 对齐 lxAss selectUnitFn/selectSizeFn（unitSizeSync、sizeRevert）
  /// 与 zmProMax preOrder unitConfirm/changeSize
  static Future<void> apply(
    Map<String, dynamic> item, {
    required String type,
    required Map<String, dynamic> result,
    required String bsid,
    required String counterid,
    bool stockAllBatch = false,
  }) async {
    if (type == 'unit') {
      final String unit = result['unit']?.toString() ?? result['_name']?.toString() ?? '';
      final String unitonlyid = result['unitonlyid']?.toString() ?? result['_id']?.toString() ?? '';
      item['unit'] = unit;
      item['unitonlyid'] = unitonlyid;
      // 切换单位时同步商品名称：包装单位以包装名称为准，基础单位还原主商品名称
      syncUnitProductName(item, result, unitonlyid: unitonlyid);
      item['defunit'] = unit;
      item['defunitid'] = unitonlyid;
      // 选包装单位后规格回退主规格（对齐 selectUnitFn sizeRevert 分支）
      if (!_isEmpty(unitonlyid)) {
        final String mainSize = item['_mainSize']?.toString() ?? '';
        if (mainSize.isNotEmpty) item['size'] = mainSize;
        item['sizeonlyid'] = item['_mainSizeonlyid']?.toString() ?? '';
      }
      // 选包装单位后 packagenum 置 1，否则取接口值（对齐 selectUnitFn）
      item['packagenum'] = !_isEmpty(unitonlyid) ? 1 : (result['packagenum'] ?? item['packagenum']);
      // 货架号随单位变化（对齐 unitSizeSync）
      if (result['shelves'] != null) item['shelves'] = result['shelves']?.toString() ?? '';
    } else {
      // 首次切换规格时备份当前规格为主规格（对齐 changeSize / sizeRevert）
      if (_isEmpty(item['_mainSize'])) {
        item['_mainSize'] = item['size']?.toString() ?? '';
        item['_mainSizeonlyid'] = item['sizeonlyid']?.toString() ?? '';
      }
      final String size = result['size']?.toString() ?? result['_name']?.toString() ?? '';
      final String sizeonlyid = result['sizeonlyid']?.toString() ?? result['_id']?.toString() ?? '';
      item['size'] = size;
      item['sizeonlyid'] = sizeonlyid;
      item['defsize'] = size;
      item['defsizeid'] = sizeonlyid;
      if (result['packagenum'] != null) item['packagenum'] = result['packagenum'];
    }

    // 零售价：sellprice → sellprice/saleprice（对齐 unitSizeSync 的 formatDecimal(2)）
    if (result['sellprice'] != null) {
      final String sellprice = MathUtils.formatDecimal(2, result['sellprice']);
      item['sellprice'] = sellprice;
      item['saleprice'] = sellprice;
    }
    // barcode = sbarcode || barcode；code = scode || code
    final String barcode = _firstNotEmpty(result, const <String>['sbarcode', 'barcode']);
    if (barcode.isNotEmpty) item['barcode'] = barcode;
    final String code = _firstNotEmpty(result, const <String>['scode', 'code']);
    if (code.isNotEmpty) item['code'] = code;

    await _syncBatchStock(item,
        type: type, result: result, bsid: bsid, counterid: counterid, stockAllBatch: stockAllBatch);
  }

  /// 查询批次库存（库存/成本价来源），对齐 zmProMax getUnitPrice → stockproduct/getBacthList
  ///
  /// - 普通库存单据（其他入库/出库、预盘单）传 [counterid]
  /// - 转仓单传 [outcounterid] + [incounterid]
  /// - 切换单位传 [unitonlyid]，切换规格传 [sizeonlyid]，二者只传其一
  /// - 仓库/单位类参数传 null 表示不带该字段（空串照常传给后端，与 zmProMax 一致）
  /// 返回接口 list（查询失败或无数据时返回空列表，由调用方用扩展项兜底）
  static Future<List<Map<String, dynamic>>> fetchBatchStock({
    required String productid,
    required String bsid,
    String batchno = '',
    String? counterid,
    String? outcounterid,
    String? incounterid,
    String? unitonlyid,
    String? sizeonlyid,
  }) async {
    if (productid.isEmpty) return <Map<String, dynamic>>[];
    try {
      final res = await request(HttpApi.stockproductGetBacthList, <String, dynamic>{
        'batchno': batchno,
        'productid': productid,
        'bsid': bsid,
        'costflag': 1,
        'exactflag': 1,
        if (counterid != null) 'counterid': counterid,
        if (outcounterid != null) 'outcounterid': outcounterid,
        if (incounterid != null) 'incounterid': incounterid,
        if (unitonlyid != null) 'unitonlyid': unitonlyid,
        if (sizeonlyid != null) 'sizeonlyid': sizeonlyid,
      });
      final dynamic data = res['data'];
      final List<dynamic> raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // 查询异常按无批次库存处理，走扩展项/原值兜底
      return <Map<String, dynamic>>[];
    }
  }

  /// 按批次重取库存与成本价（对齐 lxAss syncStockByExtend / zmProMax getUnitPrice）
  ///
  /// [stockAllBatch] 为 true（系统参数「盘点不管理批次」）时回写商品总库存 allstockqty，
  /// 否则回写批次库存 stockqty（对齐 lxAss myStockSyncFields 的字段切换）
  static Future<void> _syncBatchStock(
    Map<String, dynamic> item, {
    required String type,
    required Map<String, dynamic> result,
    required String bsid,
    required String counterid,
    bool stockAllBatch = false,
  }) async {
    final List<Map<String, dynamic>> list = await fetchBatchStock(
      productid: item['productid']?.toString() ?? item['prodid']?.toString() ?? '',
      bsid: bsid,
      batchno: item['batchno']?.toString() ?? '',
      counterid: counterid,
      unitonlyid: type == 'unit' ? (item['unitonlyid']?.toString() ?? '') : null,
      sizeonlyid: type == 'size' ? (item['sizeonlyid']?.toString() ?? '') : null,
    );
    if (list.isNotEmpty) {
      item['costprice'] = MathUtils.formatDecimal(2, list.first['costprice'] ?? 0);
      if (stockAllBatch) {
        // 不管理批次：库存取商品总库存 allstockqty（对齐 lxAss syncFields allstockqty）
        item['allstockqty'] =
            MathUtils.formatDecimal(2, list.first['allstockqty'] ?? item['allstockqty'] ?? 0);
      } else {
        item['stockqty'] = MathUtils.formatDecimal(2, list.first['stockqty'] ?? 0);
      }
    } else {
      // 无批次库存：回退 emptycostprice/emptybatchstockqty，再回退原值（对齐 unitConfirm/changeSize）
      item['costprice'] = MathUtils.formatDecimal(
          2, result['emptycostprice'] ?? result['costprice'] ?? item['costprice'] ?? 0);
      if (stockAllBatch) {
        item['allstockqty'] = MathUtils.formatDecimal(
            2, result['emptybatchstockqty'] ?? result['allstockqty'] ?? item['allstockqty'] ?? 0);
      } else {
        item['stockqty'] = MathUtils.formatDecimal(
            2, result['emptybatchstockqty'] ?? result['stockqty'] ?? item['stockqty'] ?? 0);
      }
    }
  }

  static bool _isEmpty(dynamic v) => v == null || v.toString().trim().isEmpty;

  static String _firstNotEmpty(Map<String, dynamic> m, List<String> keys) {
    for (final String key in keys) {
      final String v = m[key]?.toString() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }
}
