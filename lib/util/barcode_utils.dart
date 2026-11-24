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
    this.price,
  });

  /// 秤码类型：weight-重量码（带数量），amount-金额码
  final String type;

  /// 商品码（去掉了标识位等包装信息的真实商品条码）
  final String productCode;

  /// 重量码解析出的数量（按 webWeightInt 小数位还原）
  final double? qty;

  /// 金额码解析出的金额（按 webAmtInt 小数位还原）
  final double? amount;

  /// 秤码中的单价（仅 18 位重+单价/单价+重量且开启“18位秤码按秤价格优先”时返回）
  final double? price;
}

/// 默认标识位（后台未配置时的兜底值）
const String _defaultFlag = '22';

/// 后台未配置精度时的兜底小数位数（与原实现一致：按 3 位小数解析）
const int _defaultDigits = 3;

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

/// 10 的 [n] 次方
double _pow10(double n) {
  var result = 1.0;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}

/// 获取精度配置对应的缩放倍数
///
/// 后台「重量精度 / 金额精度 / 单价精度」配置的是小数位数（1/2/3/4），
/// 秤码数值段是放大后的整数，需除以 10^n 还原，与 C# JudgeElecProduct 中 RetBitsNum 的口径一致
double _getScale(dynamic scaleValue) {
  final digits = double.tryParse(scaleValue?.toString() ?? '');
  return _pow10(digits != null && digits > 0 ? digits : _defaultDigits.toDouble());
}

/// 安全截取（越界返回空串，避免 RangeError）
String _segment(String source, int start, int length) {
  if (start < 0 || start + length > source.length) {
    return '';
  }
  return source.substring(start, start + length);
}

/// 计算 13 位秤码的校验位（对齐 PC 端 GetBarCodeParityBit）
///
/// 取前 11 位：偶数位（下标 0、2、4…）求和 e，奇数位（下标 1、3、5…）求和 o，
/// 校验位 = (250 - (e + o * 3)) % 10
///
/// 位数不足或前 11 位存在非数字时返回空串
String getBarcodeParityBit(String barcode) {
  if (barcode.length < 12) {
    return '';
  }
  var even = 0;
  var odd = 0;
  for (var i = 0; i < 11; i += 2) {
    final first = int.tryParse(barcode[i]);
    final second = int.tryParse(barcode[i + 1]);
    if (first == null || second == null) {
      return '';
    }
    even += first;
    odd += second;
  }
  return ((250 - (even + odd * 3)) % 10).toString();
}

/// 解析条码秤生成的重量码/金额码
///
/// 结构对齐 C# JudgeElecProduct：
/// 13位码：标识位(2) + 商品码(5) + 数值(5) + 校验位(1)
/// 18位码：标识位(2) + 商品码(5) + 数值A(5) + 数值B(5) + 校验位(1)
///
/// 各格式数值段含义：
/// - 1=13位重量码：数值=重量；2=13位金额码：数值=金额
/// - 3=重量+金额；4=重量+单价；5=金额+重量；6=单价+重量
///
/// 返回 null 表示不是秤码
ScaleBarcodeResult? parseScaleBarcode(String barcode) {
  if (barcode.isEmpty) {
    return null;
  }

  final cfg = _getLoginParamResp();
  // 对齐小程序 String(cfg.webBarcodeInt || DEFAULT_FLAG)：null/空串/0 均视为未配置，兜底为 22
  var flagValue = cfg['webBarcodeInt']?.toString() ?? '';
  if (flagValue.isEmpty || flagValue == '0') {
    flagValue = _defaultFlag;
  }
  final format = int.tryParse(cfg['wbBarcodeFormatInt']?.toString() ?? '') ?? 0;

  if (!barcode.startsWith(flagValue)) {
    return null;
  }

  // 位数校验对齐 C#：1~2 为 13 位码，3~6 为 18 位码；未配置格式时不限位数
  var expectLength = 0;
  if (format >= 1 && format <= 2) {
    expectLength = 13;
  } else if (format >= 3 && format <= 6) {
    expectLength = 18;
  }
  if (expectLength > 0) {
    if (barcode.length != expectLength) {
      return null;
    }
  } else if (barcode.length != 13 && barcode.length != 18) {
    return null;
  }

  // 判断校验位：后台开启 checkBarcodeCodeInt 时，仅对 13 位秤码比较末位与重算校验位（对齐 PC 端）
  if ((format == 1 || format == 2) && (cfg['checkBarcodeCodeInt']?.toString() ?? '') == '1') {
    final parityBit = getBarcodeParityBit(barcode);
    // 算不出校验位（如含非数字）时与 PC 端一致：跳过校验，继续按秤码解析
    if (parityBit.isNotEmpty && parityBit != barcode[12]) {
      return null;
    }
  }

  // 标识位之后依次为：商品码 5 位 + 数值A 5 位 + 数值B 5 位 + 校验位 1 位
  final start = flagValue.length;
  final productCode = _segment(barcode, start, 5);
  final valueA = int.tryParse(_segment(barcode, start + 5, 5));
  final valueB = int.tryParse(_segment(barcode, start + 10, 5));
  if (format >= 1 && valueA == null) {
    return null;
  }
  if (format >= 3 && valueB == null) {
    return null;
  }

  // 18 位秤码“按秤价格优先”开启时，单价段才参与计算
  final priceFirst = (cfg['eighteenPriceInt']?.toString() ?? '') == '1';

  switch (format) {
    // 13 位重量码：数值=重量
    case 1:
      return ScaleBarcodeResult(
        type: 'weight',
        productCode: productCode,
        qty: valueA! / _getScale(cfg['webWeightInt']),
      );

    // 13 位金额码：数值=金额，数量由页面按单价反算
    case 2:
      return ScaleBarcodeResult(
        type: 'amount',
        productCode: productCode,
        amount: valueA! / _getScale(cfg['webAmtInt']),
      );

    // 18 位重量金额码：重量 + 金额
    case 3:
      return ScaleBarcodeResult(
        type: 'weight',
        productCode: productCode,
        qty: valueA! / _getScale(cfg['webWeightInt']),
        amount: valueB! / _getScale(cfg['webAmtInt']),
      );

    // 18 位重量单价码：重量 + 单价
    case 4:
      final qty = valueA! / _getScale(cfg['webWeightInt']);
      return priceFirst
          ? ScaleBarcodeResult(
              type: 'weight',
              productCode: productCode,
              qty: qty,
              price: valueB! / _getScale(cfg['webPriceInt']),
            )
          : ScaleBarcodeResult(type: 'weight', productCode: productCode, qty: qty);

    // 18 位金额重量码：金额 + 重量
    case 5:
      final amount = valueA! / _getScale(cfg['webAmtInt']);
      final qty = valueB! / _getScale(cfg['webWeightInt']);
      // 按秤价格优先时与 C# 一致：用金额/数量反算单价
      return priceFirst && qty > 0
          ? ScaleBarcodeResult(
              type: 'weight',
              productCode: productCode,
              qty: qty,
              amount: amount,
              price: amount / qty,
            )
          : ScaleBarcodeResult(
              type: 'weight',
              productCode: productCode,
              qty: qty,
              amount: amount,
            );

    // 18 位单价重量码：单价 + 重量
    case 6:
      final qty = valueB! / _getScale(cfg['webWeightInt']);
      return priceFirst
          ? ScaleBarcodeResult(
              type: 'weight',
              productCode: productCode,
              qty: qty,
              price: valueA! / _getScale(cfg['webPriceInt']),
            )
          : ScaleBarcodeResult(type: 'weight', productCode: productCode, qty: qty);
  }

  // 兜底：已确认是秤码（标识位匹配）但格式类型未配置，仍返回商品码供查询使用
  return ScaleBarcodeResult(type: 'weight', productCode: productCode);
}

/// 判断是否为条码秤生成的秤码
bool isScaleBarcode(String barcode) {
  return parseScaleBarcode(barcode) != null;
}

/// 包装数量展示小数位：跟随后台条码秤重量精度（webWeightInt 为小数位数），未配置时按 2 位
int getScaleQtyDigits() {
  final digits = int.tryParse(_getLoginParamResp()['webWeightInt']?.toString() ?? '');
  return (digits != null && digits >= 1 && digits <= 4) ? digits : 2;
}

/// 包装数量展示：按条码秤重量精度格式化（对齐小程序 formatQty）
String formatScaleQty(dynamic value) {
  final num raw = value is num ? value : (double.tryParse(value?.toString() ?? '') ?? 0);
  return raw.toDouble().toStringAsFixed(getScaleQtyDigits());
}

// =================== 包装条码生成（对齐小程序 prepackPrice generatePackageCode） ===================

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
  final scalePrice = cfg['webPriceInt']?.toString() ?? '';
  final scaleAmount = cfg['webAmtInt']?.toString() ?? '';
  final scaleWeight = cfg['webWeightInt']?.toString() ?? '';
  var flagValue = cfg['webBarcodeInt']?.toString() ?? '';
  if (flagValue.isEmpty) {
    flagValue = _defaultFlag;
  }

  if (scalePrice.isEmpty || scaleAmount.isEmpty || scaleWeight.isEmpty) {
    Toast.show('请前往后台设置条码秤数据');
    return '';
  }

  // 商品代码统一截取为5位（包装条码结构：标识2位 + 商品5位 + 数值5位 + [数值5位] + 校验1位）
  final productCode = code.length > 5 ? code.substring(0, 5) : code;
  // 无商品条码时无法拼码，交由打印环节回退使用商品条码
  if (productCode.isEmpty) {
    return '';
  }

  // 13 位秤码的末位校验位：开启“判断校验位”时按 PC 端算法重算，否则沿用历史的固定末位
  final checkBarcodeCodeInt = cfg['checkBarcodeCodeInt']?.toString() ?? '';
  String withCheckBit(String body) {
    if (checkBarcodeCodeInt != '1') {
      return '${body}1';
    }
    final parityBit = getBarcodeParityBit(body);
    return '$body${parityBit.isEmpty ? '1' : parityBit}';
  }

  // 13位重量码
  if (lengthType == '1') {
    // 数值段 = 重量 × 10^n（n 为后台配置的重量精度小数位）
    final value = _getScale(scaleWeight) * qty;
    if (value > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return withCheckBit('$flagValue$productCode${_padBarcodeValue(value)}');
  }

  // 13位金额码
  if (lengthType == '2') {
    // 数值段 = 金额 × 10^n（n 为后台配置的金额精度小数位）
    final value = _getScale(scaleAmount) * price;
    if (value > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return withCheckBit('$flagValue$productCode${_padBarcodeValue(value)}');
  }

  // 18位重+金额
  if (lengthType == '3') {
    final value = _getScale(scaleWeight) * qty;
    final amountValue = _getScale(scaleAmount) * price;
    if (value > 99999 || amountValue > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$productCode${_padBarcodeValue(value)}${_padBarcodeValue(amountValue)}1';
  }

  // 18位重+单价
  if (lengthType == '4') {
    final value = _getScale(scaleWeight) * qty;
    final amountValue = _getScale(scalePrice) * (qty > 0 ? price / qty : 0);
    if (value > 99999 || amountValue > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$productCode${_padBarcodeValue(value)}${_padBarcodeValue(amountValue)}1';
  }

  // 18位金额+重量
  if (lengthType == '5') {
    final value = _getScale(scaleWeight) * qty;
    final amountValue = _getScale(scaleAmount) * price;
    if (value > 99999 || amountValue > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$productCode${_padBarcodeValue(amountValue)}${_padBarcodeValue(value)}1';
  }

  // 18位单价+重量
  if (lengthType == '6') {
    final value = _getScale(scaleWeight) * qty;
    final amountValue = _getScale(scalePrice) * (qty > 0 ? price / qty : 0);
    if (value > 99999 || amountValue > 99999) {
      Toast.show('非正常称重条码');
      return '';
    }
    return '$flagValue$productCode${_padBarcodeValue(amountValue)}${_padBarcodeValue(value)}1';
  }

  return '';
}
