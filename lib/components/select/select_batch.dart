import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 批次选择底部抽屉 —— 统一收口在 components/select
///
/// 以 showModalBottomSheet 弹出半屏抽屉，展示指定商品在某机构/仓库下的批次列表。
/// 支持搜索过滤、单选后自动关闭并返回选中批次的完整数据。
class SelectBatchSheet extends StatefulWidget {
  const SelectBatchSheet({
    super.key,
    required this.productid,
    required this.bsid,
    required this.counterid,
    this.initialBatchNo = '',
    this.costflag = true,
    this.mergData,
  });
  final String productid;
  final String bsid;
  final String counterid;
  final String initialBatchNo;

  /// 是否附带成本信息（对齐 Vue：costflag 由调用页 mergeData 决定，
  /// 如配送发货等单据不传，库存类单据才传 costflag: 1）
  final bool costflag;

  /// 调用页透传的批次查询参数（对齐 Vue select-batch mergeData，如 insid/pspriceflag）
  final Map<String, dynamic>? mergData;

  /// 便捷静态方法：打开底部抽屉并返回选中的批次数据
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String productid,
    required String bsid,
    required String counterid,
    String initialBatchNo = '',
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectBatchSheet(
        productid: productid,
        bsid: bsid,
        counterid: counterid,
        initialBatchNo: initialBatchNo,
      ),
    );
  }

  @override
  State<SelectBatchSheet> createState() => _SelectBatchSheetState();
}

class _SelectBatchSheetState extends State<SelectBatchSheet> {
  bool _loading = true;
  String _keyword = '';
  List<Map<String, dynamic>> _batchList = [];
  String? _selectedBatchNo;

  @override
  void initState() {
    super.initState();
    _selectedBatchNo = widget.initialBatchNo.isNotEmpty ? widget.initialBatchNo : null;
    _loadBatchList();
  }

  Future<void> _loadBatchList() async {
    setState(() => _loading = true);
    final params = <String, dynamic>{
      'productid': widget.productid,
      'bsid': widget.bsid,
    };
    // 后台配送类单据批次查询不带 counterid（对齐 selectproductbatchs mergeData：productid + bsid）
    if (widget.counterid.isNotEmpty) params['counterid'] = widget.counterid;
    // 对齐 Vue selectproductbatchs：costflag 仅部分单据需要
    if (widget.costflag) params['costflag'] = 1;
    // 调用页透传参数（对齐 select-batch mergeData，如配退发货的 insid/pspriceflag）
    if (widget.mergData != null) params.addAll(widget.mergData!);
    request(HttpApi.stockproductGetBacthList, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      setState(() {
        _batchList = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  List<Map<String, dynamic>> get _filteredList {
    if (_keyword.trim().isEmpty) return _batchList;
    return _batchList.where((e) {
      final batchno = e['batchno']?.toString() ?? '';
      return batchno.contains(_keyword.trim());
    }).toList();
  }

  void _onTapItem(Map<String, dynamic> item) {
    final batchno = item['batchno']?.toString() ?? '';
    setState(() => _selectedBatchNo = batchno);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      Navigator.pop(context, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Text('选择批次',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _keyword = v),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                    hintText: '输入批次号',
                    hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            Flexible(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF006EFF)),
                    )
                  : _filteredList.isEmpty
                      ? const Center(
                          child: Text('暂无批次',
                              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                        )
                      : ListView.builder(
                          itemCount: _filteredList.length,
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom + 12,
                          ),
                          itemBuilder: (ctx, idx) {
                            final item = _filteredList[idx];
                            final batchno = item['batchno']?.toString() ?? '';
                            final stockqty =
                                double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;
                            final isSelected = _selectedBatchNo == batchno;
                            return GestureDetector(
                              onTap: () => _onTapItem(item),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: const BoxDecoration(
                                  border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      size: 22,
                                      color: isSelected
                                          ? const Color(0xFF006EFF)
                                          : const Color(0xFFD1D5DB),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '批次：$batchno',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isSelected
                                                  ? const Color(0xFF006EFF)
                                                  : const Color(0xFF111827),
                                              fontWeight:
                                                  isSelected ? FontWeight.w500 : FontWeight.normal,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '库存：${stockqty.toStringAsFixed(1)}',
                                            style: const TextStyle(
                                                fontSize: 12, color: Color(0xFF7A7A7A)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
