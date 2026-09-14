import 'dart:convert';

import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 秤码解析结果
class ScaleBarcodeResult {
  const ScaleBarcodeResult({
    required this.type,
    required this.productCode,
    this.qty,
    this.amount,
  });

  /// 秤码类型：weight-重量码，amount-金额码
  final String type;

  /// 商品码（去掉了标识位等包装信息的真实商品条码）
  final String productCode;

  /// 重量码解析出的数量（仅 type=weight 时有值）
  final double? qty;

  /// 金额码解析出的金额（type=amount 或 18位重+金额 时有值）
  final double? amount;
}

/// 默认标识位（后台未配置时的兜底值）
const String _defaultFlag = '22';

/// 缩放因子映射（兼容新旧系统配置）
const Map<int, double> _scaleMap = {
  1: 1000,
  2: 100,
  3: 10,
  4: 1,
};

/// 获取精度配置对应的缩放倍数
double _getScale(dynamic scaleValue) {
  final val = double.tryParse(scaleValue?.toString() ?? '1') ?? 1;
  return _scaleMap[val.toInt()] ?? val;
}

/// 获取登录参数中的秤码配置
Map<String, dynamic> _getLoginParamResp() {
  try {
    final str = SpUtil.getString('loginParamResp') ?? '';
    if (str.isNotEmpty) {
      return jsonDecode(str) as Map<String, dynamic>;
    }
  } catch (_) {}
  return {};
}

/// 解析条码秤生成的重量码/金额码
///
/// 13位码结构：标识位(2) + 商品码(5) + 数值(5) + 校验位(1)
/// 18位码结构：标识位(2) + 商品码(5) + 数值A(5) + 数值B(5) + 校验位(1)
///
/// 支持格式：
/// - 13位重量码（lengthType=1 或未配置）
/// - 13位金额码（lengthType=2）
/// - 18位重+金额（lengthType=3）
/// - 18位重+单价（lengthType=4）
/// - 18位金额+重量（lengthType=5）
/// - 18位单价+重量（lengthType=6）
///
/// 返回 null 表示不是秤码
ScaleBarcodeResult? parseScaleBarcode(String barcode) {
  if (barcode.isEmpty) return null;
  if (barcode.length != 13 && barcode.length != 18) return null;

  final cfg = _getLoginParamResp();
  // 对齐小程序 String(cfg.webBarcodeInt || DEFAULT_FLAG)：null/空串/0 均视为未配置，兜底为 22
  String flagValue = cfg['webBarcodeInt']?.toString() ?? '';
  if (flagValue.isEmpty || flagValue == '0') {
    flagValue = _defaultFlag;
  }
  final lengthType = cfg['wbBarcodeFormatInt']?.toString() ?? '';

  if (!barcode.startsWith(flagValue)) return null;

  final productCode = barcode.substring(2, 7);

  // ===== 13位码 =====

  // 13位重量码（lengthType=1 或未配置时默认按重量码解析）
  if ((lengthType == '1' || lengthType.isEmpty) && barcode.length == 13) {
    final weightStr = barcode.substring(7, 12);
    final weightVal = int.tryParse(weightStr);
    if (weightVal == null) return null;
    final qty = weightVal / _getScale(cfg['webWeightInt']);
    return ScaleBarcodeResult(
      type: 'weight',
      productCode: productCode,
      qty: qty,
    );
  }

  // 13位金额码
  if (lengthType == '2' && barcode.length == 13) {
    final amountStr = barcode.substring(7, 12);
    final amountVal = int.tryParse(amountStr);
    if (amountVal == null) return null;
    final amount = amountVal / _getScale(cfg['webAmtInt']);
    return ScaleBarcodeResult(
      type: 'amount',
      productCode: productCode,
      amount: amount,
    );
  }

  // ===== 18位码 =====

  // 18位重+金额：标识(2) + 商品码(5) + 重量(5) + 金额(5) + 校验(1)
  if (lengthType == '3' && barcode.length == 18) {
    final weightRaw = barcode.substring(7, 12);
    final amountRaw = barcode.substring(12, 17);
    final weightVal = int.tryParse(weightRaw);
    final amountVal = int.tryParse(amountRaw);
    if (weightVal == null || amountVal == null) return null;
    final qty = weightVal / _getScale(cfg['webWeightInt']);
    final amount = amountVal / _getScale(cfg['webAmtInt']);
    return ScaleBarcodeResult(
      type: 'weight',
      productCode: productCode,
      qty: qty,
      amount: amount,
    );
  }

  // 18位重+单价：标识(2) + 商品码(5) + 重量(5) + 单价(5) + 校验(1)
  if (lengthType == '4' && barcode.length == 18) {
    final weightRaw = barcode.substring(7, 12);
    final weightVal = int.tryParse(weightRaw);
    if (weightVal == null) return null;
    final qty = weightVal / _getScale(cfg['webWeightInt']);
    return ScaleBarcodeResult(
      type: 'weight',
      productCode: productCode,
      qty: qty,
    );
  }

  // 18位金额+重量：标识(2) + 商品码(5) + 金额(5) + 重量(5) + 校验(1)
  if (lengthType == '5' && barcode.length == 18) {
    final amountRaw = barcode.substring(7, 12);
    final weightRaw = barcode.substring(12, 17);
    final amountVal = int.tryParse(amountRaw);
    final weightVal = int.tryParse(weightRaw);
    if (amountVal == null || weightVal == null) return null;
    final amount = amountVal / _getScale(cfg['webAmtInt']);
    final qty = weightVal / _getScale(cfg['webWeightInt']);
    return ScaleBarcodeResult(
      type: 'weight',
      productCode: productCode,
      qty: qty,
      amount: amount,
    );
  }

  // 18位单价+重量：标识(2) + 商品码(5) + 单价(5) + 重量(5) + 校验(1)
  if (lengthType == '6' && barcode.length == 18) {
    final weightRaw = barcode.substring(12, 17);
    final weightVal = int.tryParse(weightRaw);
    if (weightVal == null) return null;
    final qty = weightVal / _getScale(cfg['webWeightInt']);
    return ScaleBarcodeResult(
      type: 'weight',
      productCode: productCode,
      qty: qty,
    );
  }

  // 兜底：已确认是秤码（标识位匹配），但格式类型未匹配，仍返回商品码供查询使用
  return ScaleBarcodeResult(
    type: 'weight',
    productCode: productCode,
  );
}

/// 判断是否为条码秤生成的秤码
bool isScaleBarcode(String barcode) {
  return parseScaleBarcode(barcode) != null;
}

// =================== 包装条码生成（对齐小程序 prepackPrice generatePackageCode） ===================

/// 13位码精度缩放映射（1位小数→1000，2位→100，3位→10，4位→1）
const Map<int, double> _scale13Map = {
  1: 1000,
  2: 100,
  3: 10,
  4: 1,
};

/// 18位码精度缩放倍数（对齐小程序 getScaleValue：新版配置 1/2/3/4 表示小数位数）
double _getGenScale(dynamic scaleValue) {
  final scale = double.tryParse(scaleValue?.toString() ?? '') ?? 0;
  if (scale == 1) {
    return 10000;
  }
  if (scale == 2 || scale == 10) {
    return 1000;
  }
  if (scale == 3 || scale == 100) {
    return 100;
  }
  return 10;
}

/// 条码数值补位：四舍五入取整后前置补 0 到 5 位（对齐安卓 getCreateCode）
String _padBarcodeValue(double value) {
  String str = value.round().toString();
  if (str.length < 5) {
    str = str.padLeft(5, '0');
  }
  return str;
}

///
/// 生成预包装包装条码
///
/// [qty] 包装数量，[price] 包装金额，[code] 商品条码
/// 返回空字符串表示无法生成（配置缺失或数值超范围）
///
String generatePackageCode(double qty, double price, String code) {
  final cfg = _getLoginParamResp();
  final lengthType = cfg['wbBarcodeFormatInt']?.toString() ?? '';
  final scalePrice = cfg['webPriceInt']?.toString() ?? '1';
  final scaleAmount = cfg['webAmtInt']?.toString() ?? '1';
  final scaleWeight = cfg['webWeightInt']?.toString() ?? '1';
  String flagValue = cfg['webBarcodeInt']?.toString() ?? '';
  if (flagValue.isEmpty) {
    flagValue = _defaultFlag;
  }

  // 商品代码统一截取为5位（13位码标准：标识2位 + 商品5位 + 数值5位 + 校验1位）
  final productCode = code.length > 5 ? code.substring(0, 5) : code;

  // 13位重量码
  if (lengthType == '1') {
    final w = double.tryParse(scaleWeight) ?? 0;
    final weight = _scale13Map[w.toInt()] ?? w;
    final value = weight * qty;
    if (value > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$productCode${_padBarcodeValue(value)}1';
  }

  // 13位金额码
  if (lengthType == '2') {
    final a = double.tryParse(scaleAmount) ?? 0;
    final amount = _scale13Map[a.toInt()] ?? a;
    final value = amount * price;
    if (value > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$productCode${_padBarcodeValue(value)}1';
  }

  // 18位重+金额
  if (lengthType == '3') {
    final value = _getGenScale(scaleWeight) * qty;
    final amountValue = _getGenScale(scaleAmount) * price;
    if (value > 99999 || amountValue > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$code${_padBarcodeValue(value)}${_padBarcodeValue(amountValue)}1';
  }

  // 18位重+单价
  if (lengthType == '4') {
    final value = _getGenScale(scaleWeight) * qty;
    final amountValue = _getGenScale(scalePrice) * (qty > 0 ? price / qty : 0);
    if (value > 99999 || amountValue > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$code${_padBarcodeValue(value)}${_padBarcodeValue(amountValue)}1';
  }

  // 18位金额+重量
  if (lengthType == '5') {
    final value = _getGenScale(scaleWeight) * qty;
    final amountValue = _getGenScale(scaleAmount) * price;
    if (value > 99999 || amountValue > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$code${_padBarcodeValue(amountValue)}${_padBarcodeValue(value)}1';
  }

  // 18位单价+重量
  if (lengthType == '6') {
    final value = _getGenScale(scaleWeight) * qty;
    final amountValue = _getGenScale(scalePrice) * (qty > 0 ? price / qty : 0);
    if (value > 99999 || amountValue > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$code${_padBarcodeValue(amountValue)}${_padBarcodeValue(value)}1';
  }

  return '';
}
