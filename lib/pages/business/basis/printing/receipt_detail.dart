import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 单据详情页（标签打印 → 单据明细 → 选择商品）
/// 业务逻辑参考 Vue boss 项目 subs/basis/printing/receipts/detail.vue
class ReceiptDetailPage extends StatefulWidget {
  const ReceiptDetailPage({
    super.key,
    this.billId = '',
    this.notype = 0,
    this.billInfo,
  });
  final String billId;
  final int notype;

  /// 单据基本信息（从列表页传入，用于头部展示）
  final Map<String, dynamic>? billInfo;

  @override
  State<ReceiptDetailPage> createState() => _ReceiptDetailPageState();
}

class _ReceiptDetailPageState extends State<ReceiptDetailPage> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _textColor = Color(0xFF333333);
  static const Color _subTextColor = Color(0xFF7A7A7A);
  static const Color _bgColor = Color(0xFFF5F6FA);

  List<Map<String, dynamic>> _detailList = [];
  bool _loading = true;
  bool _allChecked = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final res = await request(
          HttpApi.getLabelBillDetail,
          {
            'billid': widget.billId,
            'notype': widget.notype,
          },
          true);

      if (res['retcode'] == 0 && mounted) {
        final list =
            (res['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        // 添加 checked 字段
        for (final item in list) {
          item['checked'] = false;
        }
        setState(() {
          _detailList = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int get _checkedCount => _detailList.where((e) => e['checked'] == true).length;

  void _toggleAll() {
    final newVal = !_allChecked;
    setState(() {
      _allChecked = newVal;
      for (final item in _detailList) {
        item['checked'] = newVal;
      }
    });
  }

  void _toggleItem(int index) {
    setState(() {
      _detailList[index]['checked'] = !(_detailList[index]['checked'] == true);
      _allChecked = _detailList.every((e) => e['checked'] == true);
    });
  }

  void _confirm() {
    final selected = _detailList.where((e) => e['checked'] == true).toList();
    if (selected.isEmpty) {
      Toast.show('至少选择一条数据');
      return;
    }
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.billInfo ?? {};
    final billno = info['billno']?.toString() ?? '';
    final supname = info['supname']?.toString() ?? '';
    final createname = info['createname']?.toString() ?? '';
    final createtime = info['createtime']?.toString() ?? '';
    final signtime = info['signtime']?.toString() ?? '';
    final showSupplier = widget.notype == 1;

    return Scaffold(
      appBar: const MyAppBar(centerTitle: '单据详情'),
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部信息
            _buildHeader(
              billno: billno,
              supname: supname,
              createname: createname,
              createtime: createtime,
              signtime: signtime,
              showSupplier: showSupplier,
            ),
            // 商品列表（包裹在白色圆角卡片内，对齐小程序 tm-sheet）
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _detailList.isEmpty
                        ? _buildEmpty()
                        : _buildList(),
              ),
            ),
            // 底部：全选 + 确认
            _buildBottom(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required String billno,
    required String supname,
    required String createname,
    required String createtime,
    required String signtime,
    required bool showSupplier,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('单号：$billno',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textColor)),
          const SizedBox(height: 6),
          if (showSupplier && supname.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text('供应商：$supname',
                      style: const TextStyle(fontSize: 13, color: _subTextColor)),
                ),
                Text('制单人：$createname', style: const TextStyle(fontSize: 13, color: _subTextColor)),
              ],
            )
          else
            Text('制单人：$createname', style: const TextStyle(fontSize: 13, color: _subTextColor)),
          const SizedBox(height: 4),
          Text('制单时间：$createtime', style: const TextStyle(fontSize: 13, color: _subTextColor)),
          const SizedBox(height: 4),
          Text('审核时间：$signtime', style: const TextStyle(fontSize: 13, color: _subTextColor)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      cacheExtent: 800,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      itemCount: _detailList.length,
      itemBuilder: (ctx, i) => RepaintBoundary(
        child: _DetailCard(
          item: _detailList[i],
          showBatch: widget.notype != 2,
          onTap: () => _toggleItem(i),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: Color(0xFFCCCCCC)),
          SizedBox(height: 12),
          Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
        ],
      ),
    );
  }

  Widget _buildBottom() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 全选行（右对齐，与小程序 allcheck 一致）
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('全选，已选$_checkedCount个',
                      style: const TextStyle(fontSize: 12, color: _subTextColor)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _toggleAll,
                    child: Icon(
                      _allChecked ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 22,
                      color: _allChecked ? _primaryColor : const Color(0xFFCCCCCC),
                    ),
                  ),
                ],
              ),
            ),
            // 确定按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
              child: GestureDetector(
                onTap: _confirm,
                child: Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text('确定',
                      style: TextStyle(
                          fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 明细卡片组件（对齐小程序：平铺列表 + 底部分隔线）
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.item, required this.onTap, this.showBatch = true});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool showBatch;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    final unit = item['unit']?.toString() ?? '';
    final batchno = item['batchno']?.toString() ?? '';
    final qty = double.tryParse(item['qty']?.toString() ?? '') ?? 0;
    final sellprice = double.tryParse(item['sellprice']?.toString() ?? '') ?? 0;
    final checked = item['checked'] == true;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE2E2E2))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：名称 + 复选框
            Row(
              children: [
                Expanded(
                  child: Text(
                    // 对齐小程序：名称/规格(单位)
                    '$name${size.isNotEmpty ? '/$size' : ''}($unit)',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF000000)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  checked ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 22,
                  color: checked ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC),
                ),
              ],
            ),
            // 批次（notype!=2 时显示）
            if (showBatch) ...[
              const SizedBox(height: 6),
              Text('批次：$batchno', style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
            ],
            // 入库数量 + 零售价（notype!=2 时显示入库数量）
            const SizedBox(height: 6),
            Row(
              children: [
                if (showBatch)
                  Expanded(
                    child: Text('入库数量：${MathUtils.formatDecimal(1, qty)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
                  ),
                Text('零售价：${MathUtils.formatDecimal(2, sellprice)}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
