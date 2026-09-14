import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 进价校验类型标识（对齐 Vue inPriceHeight.vue 组件 type 参数）
const String kInPriceHeightType = 'cgInPriceHeightSellPriceFlag';
const String kInPriceDiffType = 'cgProductPriceNotSellPriceFlag';

/// 进价校验弹窗结果（对齐 Vue handleInPriceHeightConfirm / 小程序 handleInPriceHeight）
enum InPriceHeightResult {
  /// 无违规项，直接通过
  pass,

  /// 取消 / 阻止模式关闭弹窗，不保存
  cancel,

  /// 警告模式用户确认继续保存
  continueSave,
}

/// 进价校验结果（携带触发的校验类型，供调用方按 Vue
/// handleInPriceHeightConfirm 逻辑置对应放行标记）
class InPriceCheckOutcome {
  const InPriceCheckOutcome(this.result, this.firedType);

  /// 校验结果
  final InPriceHeightResult result;

  /// 触发弹窗的校验类型（[kInPriceHeightType] / [kInPriceDiffType]，
  /// 无违规直接通过时为空串）
  final String firedType;
}

/// 读取登录参数指定 key 的 int 值（对齐 Vue userStore().loginParamResp），
/// 缺失或解析异常时返回 0
int _loginParamInt(String key) {
  final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
  if (cfgStr.isEmpty) return 0;
  try {
    final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
    return int.tryParse(cfg[key]?.toString() ?? '0') ?? 0;
  } catch (_) {
    return 0;
  }
}

/// 进价高于原进价两倍参数（1=允许不提示 / 2=允许但提示 / 3=不允许入库）
int getCgInPriceHeightSellPriceFlag() => _loginParamInt('cgInPriceHeightSellPriceFlag');

/// 入库价和档案价不同参数（1=允许不提示 / 2=允许但提示 / 3=不允许入库）
int getCgProductPriceNotSellPriceFlag() => _loginParamInt('cgProductPriceNotSellPriceFlag');

/// 比较基准价：inprice 有值取 inprice，否则取 oldprice（对齐 Vue comparePrice 取值）
double _comparePrice(Map<String, dynamic> item) {
  final inprice = item['inprice'];
  if (inprice != null && inprice.toString().trim().isNotEmpty) {
    return double.tryParse(inprice.toString()) ?? 0;
  }
  return double.tryParse(item['oldprice']?.toString() ?? '') ?? 0;
}

/// 筛选"现进价达到原进价两倍"的商品（对齐 Vue save：
/// o.price >= comparePrice * 2 && comparePrice != 0）
List<Map<String, dynamic>> filterDoubleInpriceItems(List<Map<String, dynamic>> items) {
  return items.where((o) {
    final prodid = o['prodid']?.toString() ?? o['productid']?.toString() ?? '';
    if (prodid.isEmpty) return false;
    final comparePrice = _comparePrice(o);
    final price = double.tryParse(o['price']?.toString() ?? '') ?? 0;
    return price >= MathUtils.multiply(comparePrice, 2) && comparePrice != 0;
  }).toList();
}

/// 筛选"现进价与原进价不一致"的商品（对齐 Vue save：
/// o.price != comparePrice && comparePrice != 0）
List<Map<String, dynamic>> filterPriceDiffItems(List<Map<String, dynamic>> items) {
  return items.where((o) {
    final prodid = o['prodid']?.toString() ?? o['productid']?.toString() ?? '';
    if (prodid.isEmpty) return false;
    final comparePrice = _comparePrice(o);
    final price = double.tryParse(o['price']?.toString() ?? '') ?? 0;
    return price != comparePrice && comparePrice != 0;
  }).toList();
}

/// 进价校验弹窗（对齐 Vue inPriceHeight.vue 组件 / 小程序 handleInPriceHeight）
///
/// [type] 取 [kInPriceHeightType]（两倍差）或 [kInPriceDiffType]（进价不一致）；
/// flag=3 阻止模式：仅提示不可继续；flag=2 警告模式：确认后继续保存。
/// 弹窗内按 type 再次过滤展示行（对齐 Vue inPriceHeight handleOpen）。
Future<InPriceHeightResult> showInPriceHeightDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
  required int flag,
  required String type,
}) async {
  final displayItems =
      type == kInPriceDiffType ? filterPriceDiffItems(items) : filterDoubleInpriceItems(items);
  final list = displayItems.isNotEmpty ? displayItems : items;

  // 对齐小程序：名称(原进价xx/现进价xx)，最多展示 3 条
  final nameStr = list.take(3).map((item) {
        final name = item['productname']?.toString() ?? item['name']?.toString() ?? '';
        final comparePrice = _comparePrice(item);
        final price = item['price']?.toString() ?? '0';
        return '$name(原进价$comparePrice/现进价$price)';
      }).join('、') +
      (list.length > 3 ? '...' : '');

  final bool isDouble = type == kInPriceHeightType;

  if (flag == 3) {
    // 阻止模式：仅提示，不可继续
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDouble ? '以下商品的进价是原进价的两倍，无法保存' : '以下商品的进价与原商品进价不一致，无法保存'),
        content: Text(nameStr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
    return InPriceHeightResult.cancel;
  }

  // 警告模式（flag=2）：确认后放行（对齐 Vue handleInPriceHeightConfirm）
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isDouble ? '以下商品的进价是原进价的两倍，请确认是否继续保存' : '以下商品的进价与原商品进价不一致，请确认是否继续保存'),
      content: Text(nameStr),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续保存')),
      ],
    ),
  );
  return confirmed ?? false ? InPriceHeightResult.continueSave : InPriceHeightResult.cancel;
}

/// 保存前进价校验（对齐 Vue save 中的校验逻辑，两种页面模式）：
/// - instore/cgqualified 模式（[diffFirst] = false）：先校验两倍差
///   （cgInPriceHeightSellPriceFlag），再校验进价不一致
///   （cgProductPriceNotSellPriceFlag，且仅在两倍差未触发放行时校验，
///   对齐注释"通过cgInPriceHeightSellPriceFlag两倍差不校验cgProductPriceNotSellPriceFlag"）；
/// - cgorder/cgother/cgothercd/cgzc 模式（[diffFirst] = true）：先校验
///   进价不一致（仅受 tipInprice 门控），再校验两倍差，两项相互独立。
///
/// 返回 [InPriceCheckOutcome]：result 为 pass 表示无违规可直接保存；
/// cancel 表示已弹窗拦截，调用方需 return；continueSave 表示用户确认继续，
/// 调用方需按 firedType 置对应放行标记（对齐 Vue isTipDoubleInprice /
/// isTipInprice）后重新走保存流程。
Future<InPriceCheckOutcome> checkInPriceHeight(
  BuildContext context,
  List<Map<String, dynamic>> items, {
  required bool tipDoubleInprice,
  required bool tipInprice,
  bool diffFirst = false,
}) async {
  // 进价不一致校验
  Future<InPriceCheckOutcome?> checkDiff() async {
    final diffFlag = getCgProductPriceNotSellPriceFlag();
    final gated = diffFirst ? tipInprice : (tipDoubleInprice && tipInprice);
    if (gated && (diffFlag == 2 || diffFlag == 3)) {
      final diffData = filterPriceDiffItems(items);
      if (diffData.isNotEmpty) {
        final result = await showInPriceHeightDialog(
          context,
          items: diffData,
          flag: diffFlag,
          type: kInPriceDiffType,
        );
        return InPriceCheckOutcome(result, kInPriceDiffType);
      }
    }
    return null;
  }

  // 进价两倍差校验
  Future<InPriceCheckOutcome?> checkDouble() async {
    final doubleFlag = getCgInPriceHeightSellPriceFlag();
    if (tipDoubleInprice && (doubleFlag == 2 || doubleFlag == 3)) {
      final doubleData = filterDoubleInpriceItems(items);
      if (doubleData.isNotEmpty) {
        final result = await showInPriceHeightDialog(
          context,
          items: doubleData,
          flag: doubleFlag,
          type: kInPriceHeightType,
        );
        return InPriceCheckOutcome(result, kInPriceHeightType);
      }
    }
    return null;
  }

  if (diffFirst) {
    // cgorder/cgother/cgothercd/cgzc：先不一致后两倍差
    final diff = await checkDiff();
    if (diff != null) return diff;
    final doubleR = await checkDouble();
    if (doubleR != null) return doubleR;
  } else {
    // instore/cgqualified：先两倍差后不一致
    final doubleR = await checkDouble();
    if (doubleR != null) return doubleR;
    final diff = await checkDiff();
    if (diff != null) return diff;
  }
  return const InPriceCheckOutcome(InPriceHeightResult.pass, '');
}
