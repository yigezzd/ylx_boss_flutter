import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/business/basis/commodity/add_spec.dart';
import 'package:flutter_deer/util/math_utils.dart';

/// 多规格管理页面
/// 展示商品规格列表，支持新增/编辑/删除规格
/// 数据通过 Navigator.pop 返回给上一页
class CommoditySpecPage extends StatefulWidget {
  const CommoditySpecPage({
    super.key,
    required this.sizedata,
    this.productName = '',
    this.typecode = '',
    this.typeid = '',
    this.packpage = const [],
    this.barcode = '',
  });

  /// 当前规格数据列表
  final List<Map<String, dynamic>> sizedata;

  /// 商品名称（展示用）
  final String productName;

  /// 分类编码（生成条码用）
  final String typecode;

  /// 分类ID（生成条码用）
  final String typeid;

  /// 包装数据（校验条码冲突用）
  final List<Map<String, dynamic>> packpage;

  /// 商品主条码（校验条码冲突用）
  final String barcode;

  @override
  State<CommoditySpecPage> createState() => _CommoditySpecPageState();
}

class _CommoditySpecPageState extends State<CommoditySpecPage> {
  late List<Map<String, dynamic>> _sizedata;

  @override
  void initState() {
    super.initState();
    _sizedata = List<Map<String, dynamic>>.from(widget.sizedata);
  }

  Future<void> _addOrEditSpec({int? editIndex}) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddSpecPage(
          typecode: widget.typecode,
          typeid: widget.typeid,
          specData: editIndex != null && editIndex < _sizedata.length ? _sizedata[editIndex] : null,
          sizedata: _sizedata,
          packpage: widget.packpage,
          barcode: widget.barcode,
          editIndex: editIndex ?? -1,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        // 删除标记：移除该项
        if (result['_delete'] == true) {
          if (editIndex != null && editIndex < _sizedata.length) {
            _sizedata.removeAt(editIndex);
          }
        } else {
          // 若设置默认规格，取消其他默认
          if (result['defsizeflag'] == 1) {
            for (final item in _sizedata) {
              item['defsizeflag'] = 0;
            }
          }
          if (editIndex != null && editIndex < _sizedata.length) {
            _sizedata[editIndex] = result;
          } else {
            _sizedata.add(result);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 过滤有效规格（有条码的）
    final validSpecs = _sizedata
        .asMap()
        .entries
        .where((e) => e.value['sbarcode']?.toString().isNotEmpty ?? false)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context, _sizedata),
        ),
        centerTitle: true,
        title: const Text(
          '规格商品',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: validSpecs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('暂无规格', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              cacheExtent: 800,
              itemCount: validSpecs.length,
              itemBuilder: (context, idx) {
                final entry = validSpecs[idx];
                final spec = entry.value;
                final realIndex = entry.key;
                return RepaintBoundary(
                  child: _SpecItemCard(
                    productName: widget.productName,
                    spec: spec,
                    onTap: () => _addOrEditSpec(editIndex: realIndex),
                    onDelete: () {
                      setState(() => _sizedata.removeAt(realIndex));
                    },
                  ),
                );
              },
            ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        child: GestureDetector(
          onTap: () => _addOrEditSpec(),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF006EFF),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Text(
              '新增规格',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecItemCard extends StatelessWidget {
  const _SpecItemCard({
    required this.productName,
    required this.spec,
    required this.onTap,
    required this.onDelete,
  });
  final String productName;
  final Map<String, dynamic> spec;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sname = spec['sname']?.toString() ?? '';
    final sbarcode = spec['sbarcode']?.toString() ?? '';
    final sellprice = MathUtils.formatDecimal(2, spec['sellprice'] ?? '0');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Row(
          children: [
            // 左侧：商品名称 + 条码
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName.isNotEmpty ? productName : '-',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sbarcode.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(sbarcode,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            // 右侧：规格名称 + 零售价 + 箭头
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('规格名称: $sname',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
                    const SizedBox(height: 4),
                    Text('零售价: $sellprice',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 20, color: Color(0xFFBEBDBE)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
