import 'package:flutter/widgets.dart';

/// 多单位商品：切换单位后同步商品名称（对齐 Vue 单据页 unitConfirm / 小程序 proDetails selectUnitFn）
///
/// 接口 bi/product/getProductExtendList 的 packlist 中：
/// - 下标 0 为主商品默认单位（基础单位），其 unitonlyid 为空串
/// - 其他行为包装单位，携带 packname（包装名称）
///
/// 规则：包装单位且 packname 有值时，商品名称取 packname；切回基础单位时还原主商品名称。
/// 主商品名称在首次切到包装单位时备份到 [item] 的 _mainProductname 字段（随行数据保存，供再次切回时还原）。
void syncUnitProductName(
  Map<String, dynamic> item,
  Map<String, dynamic> result, {
  required String unitonlyid,
}) {
  final String packname = result['packname']?.toString() ?? '';
  if (unitonlyid.isNotEmpty && packname.isNotEmpty) {
    if ((item['_mainProductname']?.toString() ?? '').isEmpty) {
      final String productname = item['productname']?.toString() ?? '';
      item['_mainProductname'] =
          productname.isNotEmpty ? productname : (item['name']?.toString() ?? '');
    }
    item['productname'] = packname;
    item['name'] = packname;
    return;
  }
  final String mainName = item['_mainProductname']?.toString() ?? '';
  if (mainName.isNotEmpty) {
    item['productname'] = mainName;
    item['name'] = mainName;
  }
}

/// 商品详情弹窗确定时附加的名称字段（配合 [syncUnitProductName] 使用）
///
/// 弹窗内的商品数据是行数据副本，确定时需把已同步的商品名称与主商品名称备份一并带出
Map<String, dynamic> unitNameFields(Map<String, dynamic> item) {
  return {
    'productname': item['productname']?.toString() ?? '',
    'name': item['name']?.toString() ?? '',
    '_mainProductname': item['_mainProductname']?.toString() ?? '',
  };
}

/// 商品详情弹窗确定后回写商品名称：行数据与行名称输入框
///
/// 行数据是弹窗数据的来源，名称输入框决定列表上展示的商品名称，二者需同时更新
void applyProductName(
  Map<String, dynamic>? target,
  Map<String, dynamic> source, {
  TextEditingController? nameController,
}) {
  if (target != null) {
    for (final key in const ['productname', 'name', '_mainProductname']) {
      final v = source[key]?.toString() ?? '';
      // 仅写入非空值：弹窗未带出的字段为空串，不能覆盖行数据已有名称
      if (v.isNotEmpty) {
        target[key] = v;
      }
    }
  }
  // productname 为 null 或空串时回退 name：部分商品数据只有 name 字段
  final productname = source['productname']?.toString() ?? '';
  final name = productname.isNotEmpty ? productname : (source['name']?.toString() ?? '');
  if (name.isNotEmpty) {
    nameController?.text = name;
  }
}
