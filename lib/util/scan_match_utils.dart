/// 扫码结果分流（对齐 lxAss scanFn：自编码/条码命中判断）
class ScanMatchResult {
  const ScanMatchResult({required this.needJump, this.primary});

  /// true → 多条命中，跳转选品页
  final bool needJump;

  /// 唯一命中项；无唯一命中时为 null（调用方兜底取 list.first）
  final Map<String, dynamic>? primary;
}

String _selfCode(Map<String, dynamic> c) =>
    c['code']?.toString() ?? c['scode']?.toString() ?? '';

String _barCode(Map<String, dynamic> c) =>
    c['barcode']?.toString() ?? c['sbarcode']?.toString() ?? c['selfbarcode']?.toString() ?? '';

/// 对齐 lxAss scanFn 分流：
/// 自编码命中：仅一条 → 优先匹配自编码商品不跳转；多条 → 跳转选品页
/// 无自编码命中：商品条码多条 → 跳转选品页；一条 → 优先匹配该商品
ScanMatchResult matchScanList(List<dynamic> list, String searchCode) {
  final rows = list.cast<Map<String, dynamic>>();
  final codeList =
      rows.where((c) => _selfCode(c).isNotEmpty && _selfCode(c) == searchCode).toList();
  final barcodeList =
      rows.where((c) => _barCode(c).isNotEmpty && _barCode(c) == searchCode).toList();

  final needJump = codeList.length >= 2 || (codeList.isEmpty && barcodeList.length >= 2);

  Map<String, dynamic>? primary;
  if (codeList.length == 1) {
    primary = codeList.first;
  } else if (codeList.isEmpty && barcodeList.length == 1) {
    primary = barcodeList.first;
  }

  return ScanMatchResult(needJump: needJump, primary: primary);
}
