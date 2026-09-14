import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 外卖拣货 - 订单详情页
/// 明细接口 sale/findSaleFlowDeail（参数 saleid，返回 saleMaster / saleDetailList）
/// 参考原型：订单信息卡片 + 商品拣货明细列表 + 底部「领取任务」按钮
class TakeoutPickingDetailPage extends StatefulWidget {
  const TakeoutPickingDetailPage({
    super.key,
    required this.order,
    this.statusTitle = '',
    this.canClaim = false,
  });

  /// 列表返回的订单数据（提供 saleid 及未请求前的展示字段）
  final Map<String, dynamic> order;

  /// 订单状态文案（待领取/待拣货/已拣货/待下发）
  final String statusTitle;

  /// 是否显示底部「领取任务」按钮（仅待领取状态）
  final bool canClaim;

  @override
  State<TakeoutPickingDetailPage> createState() => _TakeoutPickingDetailPageState();
}

class _TakeoutPickingDetailPageState extends State<TakeoutPickingDetailPage> {
  bool _loading = true;
  bool _claiming = false;
  bool _completing = false;
  Map<String, dynamic> _master = {};
  List<Map<String, dynamic>> _detailList = [];

  @override
  void initState() {
    super.initState();
    _master = Map.of(widget.order);
    _loadDetail();
  }

  /// 依次尝试候选 key，返回第一个非空值
  static String _firstOf(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final v = map[key];
      if (v != null && v.toString().isNotEmpty) {
        return v.toString();
      }
    }
    return '';
  }

  Future<void> _loadDetail() async {
    try {
      final result = await request(
        HttpApi.saleFindSaleFlowDeail,
        {'saleid': widget.order['saleid']},
      );
      final data = result['data'];
      if (!mounted) {
        return;
      }
      setState(() {
        if (data is Map<String, dynamic>) {
          final master = data['saleMaster'];
          if (master is Map<String, dynamic>) {
            _master = {..._master, ...master};
          }
          final detail = data['saleDetailList'];
          if (detail is List) {
            _detailList = detail.cast<Map<String, dynamic>>();
          }
        }
        _loading = false;
      });
    } catch (_) {
      // 错误提示由拦截器统一弹出，保留列表数据继续展示
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    }
  }

  /// 领取任务（operate=1），成功后返回 true 供列表刷新
  Future<void> _claim() async {
    if (_claiming) {
      return;
    }
    setState(() => _claiming = true);
    try {
      await request(HttpApi.saleSelectBillOperate, {
        'saleid': _master['saleid'] ?? widget.order['saleid'],
        'billno': _master['billno'],
        'operate': 1,
      });
      if (!mounted) {
        return;
      }
      Toast.show('领取成功');
      Navigator.pop(context, true);
    } catch (_) {
      // 失败提示由拦截器统一弹出
      if (mounted) {
        setState(() => _claiming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          '订单详情',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
            )
          : RefreshIndicator(
              color: const Color(0xFF006EFF),
              onRefresh: _loadDetail,
              child: ListView.builder(
                cacheExtent: 800,
                padding: const EdgeInsets.all(12),
                itemCount: _detailList.isEmpty ? 2 : _detailList.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildOrderCard();
                  }
                  if (_detailList.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                            SizedBox(height: 12),
                            Text('暂无商品明细',
                                style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                          ],
                        ),
                      ),
                    );
                  }
                  final item = _detailList[index - 1];
                  // pickflag == 0（待领取）或 == 2 时，点击商品明细不打开拣货弹窗
                  final pickflag = _master['pickflag']?.toString() ?? '';
                  final canOpenSheet = pickflag != '0' && pickflag != '2';
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == _detailList.length ? 0 : 10),
                    child: RepaintBoundary(
                      child: GestureDetector(
                        onTap: canOpenSheet ? () => _showGoodsDetail(item) : null,
                        behavior: HitTestBehavior.opaque,
                        child: _buildGoodsItem(item),
                      ),
                    ),
                  );
                },
              ),
            ),
      bottomNavigationBar: widget.canClaim
          ? _buildClaimBar()
          : widget.statusTitle == '待拣货'
              ? _buildCompletePickingBar()
              : null,
    );
  }

  /// 点击商品明细项：打开商品详情弹窗（对齐原型：商品信息 + 拣货数量步进器）
  void _showGoodsDetail(Map<String, dynamic> item) {
    final name = _firstOf(item, ['productname', 'goodsname', 'name']);
    final size = _firstOf(item, ['size', 'productsize', 'spec']);
    final title = name.isNotEmpty && size.isNotEmpty ? '$name（$size）' : name;
    final img = _firstOf(item, ['productimg', 'imgurl', 'img', 'pic']);
    final productcode =
        _firstOf(item, ['sbarcode', 'productbarcode', 'productcode', 'code', 'itemcode']);
    final zoneRaw = _firstOf(item, ['storagezonename', 'storezonename', 'zonename']);
    final zone = zoneRaw.isNotEmpty ? zoneRaw : _master['storagezonename']?.toString() ?? '';
    final pos = _firstOf(item, ['positionno', 'locationcode', 'locationno', 'position']);
    final unit = _firstOf(item, ['unit', 'unitname', 'stockunit']);
    final qty = (num.tryParse(item['qty']?.toString() ?? '') ?? 0).toInt();
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GoodsDetailSheet(
        title: title,
        img: img,
        productcode: productcode,
        zone: zone,
        pos: pos,
        unit: unit,
        qty: qty,
        statusTitle: widget.statusTitle,
      ),
    ).then((picked) {
      if (picked == null || !mounted) return;
      setState(() {
        item['pickqty'] = picked;
        item['_statusTitle'] = '已拣货';
      });
    });
  }

  /// 完成拣货（operate=2），成功后返回列表
  Future<void> _completePicking() async {
    if (_completing) {
      return;
    }
    setState(() => _completing = true);
    try {
      // 读取当前登录用户（对齐列表页领取任务写法）
      String pickuserid = '';
      String pickname = '';
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        pickuserid = userMap['userid']?.toString() ?? '';
        pickname = userMap['name']?.toString() ?? '';
      }
      // pirnt('')
      // 打印列表数据
      print('completePicking: $_detailList');
      await request(HttpApi.saleSelectBillOperate, {
        'saleid': _master['saleid'] ?? widget.order['saleid'],
        'billno': _master['billno'],
        'operate': 2,
        'pickuserid': pickuserid,
        'pickname': pickname,
        'list': _detailList
            .map((item) => {
                  'id': item['id'],
                  'pickqty': item['pickqty'],
                })
            .toList(),
      });
      if (!mounted) {
        return;
      }
      // 提示文案与底部按钮一致：pickflag == 3 显示“提前拣货”
      Toast.show(_master['pickflag']?.toString() == '3' ? '提前拣货' : '完成拣货');
      Navigator.pop(context, true);
    } catch (_) {
      // 失败提示由拦截器统一弹出
      if (mounted) {
        setState(() => _completing = false);
      }
    }
  }

  // ──────────── 订单信息卡片 ────────────

  Widget _buildOrderCard() {
    // 平台/订单号
    final isort = _firstOf(_master, ['isort']);
    // 平台名称映射（与列表页 _platformLabel 一致）
    String label() {
      final key = _master['takeouttype']?.toString() ?? '';
      const names = {'0': '商城', '1': '淘宝闪购', '2': '美团闪购', '5': '京东秒送', '8': '翱象'};
      return names[key] ?? '商城';
    }

    // 预计时间
    final appointment = _firstOf(_master, ['appointmenttime', 'appointtime']);
    // 库区
    final zone = _firstOf(_master, ['storagezonename']);
    // 备注
    final memo = _firstOf(_master, ['memo']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 平台图标
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  label(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF006EFF),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label(),
                        style: const TextStyle(
                          fontSize: 18,
                          color: Color(0xFF374151),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isort,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF006EFF),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.statusTitle.isNotEmpty)
                Text(
                  widget.statusTitle,
                  style: const TextStyle(fontSize: 18, color: Color(0xFF374151)),
                ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 4),
              Text(
                '预计: $appointment',
                style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 4),
              Text(
                '库区: $zone',
                style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '备注: $memo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────── 商品拣货明细 ────────────

  Widget _buildGoodsItem(Map<String, dynamic> item) {
    final name = _firstOf(item, ['productname']);
    final img = _firstOf(item, ['imageurl']);
    // 库区（明细没有时兜底取订单级）
    final zone = _firstOf(item, ['storagezonename']);
    final productcode = _firstOf(item, ['productcode']);
    final pos = _firstOf(item, ['positionno', 'locationcode', 'locationno', 'position']);
    // 待拣货/已拣货（pickflag == 2 || 3）展示实际拣货数量 pickqty，其余状态展示订单数量 qty
    final pickflag = _master['pickflag']?.toString() ?? '';
    final usePickQty = pickflag == '2' || pickflag == '3' || pickflag == '1';
    final qty = (usePickQty ? item['pickqty'] : item['qty'])?.toString() ?? '';
    final unit = _firstOf(item, ['unit', 'unitname', 'stockunit']);
    // 右侧黄色角标（货架位/拣货序号等，值过长不展示）
    final tag = _firstOf(item, ['rackno', 'binno', 'gridno', 'sortno', 'pickno', 'rowno']);
    final showTag = tag.isNotEmpty && tag.length <= 6;

    // 每行右侧状态标签：优先取商品自身状态（确认拣货后变为"已拣货"），无则用订单级
    final statusTitle = item['_statusTitle']?.toString() ?? widget.statusTitle;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 商品图（无图时占位图标）
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: img.isNotEmpty
                ? Image.network(
                    img,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    cacheWidth: 88,
                    errorBuilder: (_, __, ___) => _buildImgPlaceholder(),
                  )
                : _buildImgPlaceholder(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：商品名称（右侧黄色角标）
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? '--' : name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showTag) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB800),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // 状态标签：与列表卡片一致的无边框纯文本（去掉原红色边框 badge）
                    if (statusTitle.isNotEmpty)
                      Text(
                        statusTitle,
                        style: const TextStyle(fontSize: 18, color: Color(0xFF374151)),
                      ),
                  ],
                ),
                // 第二行：条码 + 数量
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        productcode,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      '数量: $qty$unit',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                    ),
                  ],
                ),
                // 第三行：库区 + 货位号
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text('库区: $zone',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 14),
                    Text('货位号: $pos',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildImgPlaceholder() {
    return const Center(
      child: Icon(Icons.inventory_2_outlined, size: 22, color: Color(0xFFB6BCC4)),
    );
  }

  // ──────────── 底部领取任务 ────────────

  Widget _buildClaimBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: GestureDetector(
        onTap: _claim,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _claiming ? const Color(0xFF99C4FF) : const Color(0xFF006EFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '领取任务',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// 完成拣货底部按钮
  Widget _buildCompletePickingBar() {
    // pickflag == 3 时按钮文案显示“提前拣货”，否则“完成拣货”
    final isAdvance = _master['pickflag']?.toString() == '3';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: GestureDetector(
        onTap: _completePicking,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _completing ? const Color(0xFF99C4FF) : const Color(0xFF006EFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isAdvance ? '提前拣货' : '完成拣货',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// 商品明细详情弹窗（对齐原型截图）：商品信息 + 拣货数量步进器 + 取消/确认
class _GoodsDetailSheet extends StatefulWidget {
  const _GoodsDetailSheet({
    required this.title,
    required this.img,
    required this.productcode,
    required this.zone,
    required this.pos,
    required this.unit,
    required this.qty,
    required this.statusTitle,
  });

  final String title;
  final String img;
  final String productcode;
  final String zone;
  final String pos;
  final String unit;
  final int qty;
  final String statusTitle;

  @override
  State<_GoodsDetailSheet> createState() => _GoodsDetailSheetState();
}

class _GoodsDetailSheetState extends State<_GoodsDetailSheet> {
  late int pickqty = widget.qty;
  void _changeQty(int delta) {
    final next = pickqty + delta;
    if (next < 0) {
      return;
    }
    setState(() => pickqty = next);
  }

  static Widget _imgPlaceholder() {
    return const Center(
      child: Icon(Icons.inventory_2_outlined, size: 26, color: Color(0xFFB6BCC4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfo(),
          const Divider(height: 24, color: Color(0xFFF0F0F0)),
          _buildPickQtyRow(),
          const Spacer(),
          _buildButtons(),
        ],
      ),
    );
  }

  /// 顶部商品信息：图 + 名称/条码/库区 + 状态/数量/货位号
  Widget _buildInfo() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.img.isNotEmpty
              ? Image.network(
                  widget.img,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 128,
                  errorBuilder: (_, __, ___) => _imgPlaceholder(),
                )
              : _imgPlaceholder(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：商品名称 + 状态标签（右，对齐明细列表角标位置）
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.title.isEmpty ? '--' : widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.statusTitle.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFEF4444)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.statusTitle,
                        style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                      ),
                    ),
                  ],
                ],
              ),
              // 第二行：条码 + 数量（右）
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.productcode.isNotEmpty ? widget.productcode : '-',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '数量: ${widget.qty}${widget.unit}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                  ),
                ],
              ),
              // 第三行：库区 + 货位号（右）
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '库区: ${widget.zone}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '货位号: ${widget.pos}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 拣货数量步进器
  Widget _buildPickQtyRow() {
    return Row(
      children: [
        const Text('拣货数量',
            style: TextStyle(fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
        const Spacer(),
        _stepButton(Icons.remove, pickqty > 0, () => _changeQty(-1)),
        Container(
          width: 56,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDEDEDE)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('$pickqty', style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
        ),
        _stepButton(Icons.add, true, () => _changeQty(1)),
      ],
    );
  }

  Widget _stepButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon,
            size: 16, color: enabled ? const Color(0xFF333333) : const Color(0xFFCCCCCC)),
      ),
    );
  }

  /// 底部取消/确认
  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('取消', style: TextStyle(fontSize: 15, color: Color(0xFF006EFF))),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context, pickqty),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF006EFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('确认', style: TextStyle(fontSize: 15, color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }
}
