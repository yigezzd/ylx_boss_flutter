import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 多批次选择底部抽屉 —— 统一收口在 components/select
///
/// 对齐 lxAss 项目 comPages/selectMultBatch 页面：
/// 以 showModalBottomSheet 弹出半屏抽屉，展示指定商品在某机构/仓库下的批次列表，
/// 支持搜索过滤、多选、每批次填写数量（数量>0 自动勾选）、全选、已选批次回显。
/// 确认后返回选中批次列表（每项含 batchno / stockqty / qtyType 数量等字段）。
class SelectMultBatchSheet extends StatefulWidget {
  final String productid;
  final String bsid;
  final String counterid;

  /// 数量字段名（对齐 lxAss qtyType，预盘单传 precheckqty）
  final String qtyType;

  /// 已选批次数据（回显，按 productid + batchno 匹配恢复数量和勾选）
  final List<Map<String, dynamic>> selectList;

  const SelectMultBatchSheet({
    super.key,
    required this.productid,
    required this.bsid,
    required this.counterid,
    this.qtyType = 'precheckqty',
    this.selectList = const [],
  });

  /// 便捷静态方法：打开底部抽屉并返回选中的批次列表
  static Future<List<Map<String, dynamic>>?> show(
    BuildContext context, {
    required String productid,
    required String bsid,
    required String counterid,
    String qtyType = 'precheckqty',
    List<Map<String, dynamic>> selectList = const [],
  }) {
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectMultBatchSheet(
        productid: productid,
        bsid: bsid,
        counterid: counterid,
        qtyType: qtyType,
        selectList: selectList,
      ),
    );
  }

  @override
  State<SelectMultBatchSheet> createState() => _SelectMultBatchSheetState();
}

class _SelectMultBatchSheetState extends State<SelectMultBatchSheet> {
  bool _loading = true;
  String _keyword = '';
  List<Map<String, dynamic>> _batchList = [];

  /// 每行数量输入控制器缓存（key 为 batchno+_ctrlKey），避免空批次共享同一控制器
  final Map<String, TextEditingController> _qtyCtrls = {};

  /// 每行唯一标识计数器，避免空批次（batchno=''）共享控制器（对齐 lxAss：每个 tm-stepper 独立绑定）
  int _nextCtrlKey = 0;

  @override
  void initState() {
    super.initState();
    _loadBatchList();
  }

  @override
  void dispose() {
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBatchList() async {
    setState(() => _loading = true);
    final params = <String, dynamic>{
      'productid': widget.productid,
      'bsid': widget.bsid,
      'counterid': widget.counterid,
      'costflag': 1,
    };
    request(HttpApi.stockproductGetBacthList, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      setState(() {
        // 对齐 lxAss selectMultBatch getList：初始数量 0 + 未勾选，selectList 按 productid+batchno 回显
        _batchList = list.map<Map<String, dynamic>>((c) {
          final m = Map<String, dynamic>.from(c as Map);
          m[widget.qtyType] = 0;
          m['check'] = false;
          m['_ctrlKey'] = (_nextCtrlKey++).toString();
          if (widget.selectList.isNotEmpty) {
            // 空批次不匹配 selectList（避免所有空批次行被自动勾选，对齐 lxAss：非空 batchno 才回显）
            final myBatchno = m['batchno']?.toString() ?? '';
            final idx = widget.selectList.indexWhere((k) =>
                (k['productid']?.toString() ?? '') == widget.productid &&
                myBatchno.isNotEmpty &&
                (k['batchno']?.toString() ?? '') == myBatchno);
            if (idx != -1) {
              m[widget.qtyType] =
                  double.tryParse(widget.selectList[idx][widget.qtyType]?.toString() ?? '0') ?? 0;
              m['check'] = true;
            }
          }
          return m;
        }).toList();
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

  bool get _allChecked {
    if (_filteredList.isEmpty) return false;
    return _filteredList.every((c) => c['check'] == true);
  }

  TextEditingController _qtyCtrlFor(Map<String, dynamic> item) {
    // 使用 _ctrlKey 作为 key（而非仅 batchno），避免空批次共享同一控制器（对齐 lxAss：每个 item 独立 v-model）
    final key = item['_ctrlKey']?.toString() ?? item['batchno']?.toString() ?? '';
    return _qtyCtrls.putIfAbsent(key, () {
      final v = double.tryParse(item[widget.qtyType]?.toString() ?? '') ?? 0;
      return TextEditingController(text: v == 0 ? '0' : v.toStringAsFixed(1));
    });
  }

  void _onQtyChanged(Map<String, dynamic> item, String v) {
    // 对齐 lxAss：输入框值写回行数据（对应 v-model 双向绑定），数量 > 0 时自动勾选
    final val = double.tryParse(v) ?? 0;
    item[widget.qtyType] = val;
    if (val > 0 && item['check'] != true) {
      setState(() => item['check'] = true);
    }
  }

  void _onToggleAll() {
    final v = !_allChecked;
    setState(() {
      for (final c in _filteredList) {
        c['check'] = v;
      }
    });
  }

  void _onConfirm() {
    // 对齐 lxAss sure()：过滤已勾选行，空则提示
    final selected = _filteredList.where((c) => c['check'] == true).toList();
    if (selected.isEmpty) {
      Toast.show('请勾选批次数据');
      return;
    }
    Navigator.pop(context, selected);
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827))),
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
                          child: Text('暂无数据',
                              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                        )
                      : ListView.builder(
                          cacheExtent: 800,
                          itemCount: _filteredList.length,
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom + 12,
                          ),
                          itemBuilder: (ctx, idx) {
                            final item = _filteredList[idx];
                            return _BatchItemCard(
                              item: item,
                              qtyCtrl: _qtyCtrlFor(item),
                              onToggleCheck: () => setState(() {
                                item['check'] = item['check'] != true;
                              }),
                              onQtyChanged: (v) => _onQtyChanged(item, v),
                            );
                          },
                        ),
            ),
            // ── 底部：全选 + 确认（对齐 lxAss footer） ──
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _onToggleAll,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _allChecked ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 20,
                          color: _allChecked ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
                        ),
                        const SizedBox(width: 6),
                        const Text('全选',
                            style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _onConfirm,
                    child: Container(
                      width: 120,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF006EFF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('确认',
                          style: TextStyle(
                              fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
                    ),
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

/// 多批次列表项：勾选 + 批次号 + 库存 + 数量输入
class _BatchItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final TextEditingController qtyCtrl;
  final VoidCallback onToggleCheck;
  final ValueChanged<String> onQtyChanged;

  const _BatchItemCard({
    required this.item,
    required this.qtyCtrl,
    required this.onToggleCheck,
    required this.onQtyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final batchno = item['batchno']?.toString() ?? '';
    final stockqty = double.tryParse(item['stockqty']?.toString() ?? '') ?? 0;
    final checked = item['check'] == true;
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onToggleCheck,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
          ),
          child: Row(
            children: [
              Icon(
                checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 22,
                color: checked ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
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
                        color: checked ? const Color(0xFF006EFF) : const Color(0xFF111827),
                        fontWeight: checked ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '库存：${stockqty.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 90,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                  onChanged: onQtyChanged,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0',
                    hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
