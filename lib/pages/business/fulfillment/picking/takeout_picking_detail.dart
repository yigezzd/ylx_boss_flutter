import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 拣货状态颜色区分：待拣货红色、已拣货蓝色，其余状态用 fallback（默认灰）
Color _statusColor(String status, [Color fallback = const Color(0xFF374151)]) {
  if (status == '待拣货') return const Color(0xFFEF4444);
  if (status == '已拣货') return const Color(0xFF006EFF);
  return fallback;
}

/// pickflag → 状态文案（0 待领取 / 1 待拣货 / 2 已拣货 / 3 待下发）
String _pickflagTitle(dynamic pickflag) {
  switch (pickflag?.toString()) {
    case '0':
      return '待领取';
    case '1':
      return '待拣货';
    case '2':
      return '已拣货';
    case '3':
      return '待下发';
    default:
      return '';
  }
}

/// 外卖拣货 - 订单详情页
/// 明细接口 sale/findSaleBillDetail（参数 saleid，仅返回商品明细 list）
/// 主单信息（含 pickflag）由列表页跳转带入（widget.order）
/// 参考原型：订单信息卡片 + 商品拣货明细列表 + 底部「领取任务」按钮
class TakeoutPickingDetailPage extends StatefulWidget {
  const TakeoutPickingDetailPage({
    super.key,
    required this.order,
  });

  /// 列表返回的订单数据（提供 saleid 及未请求前的展示字段）
  final Map<String, dynamic> order;

  @override
  State<TakeoutPickingDetailPage> createState() => _TakeoutPickingDetailPageState();
}

class _TakeoutPickingDetailPageState extends State<TakeoutPickingDetailPage> {
  bool _loading = true;
  bool _claiming = false;
  bool _completing = false;
  Map<String, dynamic> _master = {};
  List<Map<String, dynamic>> _detailList = [];

  // ── PDA/扫码枪输入（参考促销调价单：回车提交 + 150ms 防抖兜底逐字符写入）──
  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  Timer? _scanDebounceTimer;
  bool _scanFieldFocused = false;
  bool _scanBusy = false;

  @override
  void initState() {
    super.initState();
    _master = Map.of(widget.order);
    _loadDetail();

    // 扫码枪输入框：回车提交；150ms 防抖兜底红外扫码枪逐字符写入（对齐促销调价单）
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          final scanCode = _scanController.text.trim();
          if (scanCode.isNotEmpty) {
            _scanDebounceTimer?.cancel();
            _onScanInput(scanCode);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _scanFocusNode.addListener(() {
      if (_scanFocusNode.hasFocus && !_scanFieldFocused) {
        _scanFieldFocused = true;
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } else if (!_scanFocusNode.hasFocus) {
        _scanFieldFocused = false;
      }
    });
    _scanController.addListener(() {
      _scanDebounceTimer?.cancel();
      final text = _scanController.text.trim();
      if (text.isEmpty) return;
      _scanDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final code = _scanController.text.trim();
        if (code.isEmpty) return;
        _onScanInput(code);
      });
    });
  }

  @override
  void dispose() {
    _scanDebounceTimer?.cancel();
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
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

  /// isort 补零拼接：1 → #0001、10 → #0010；空值不展示，非数字原样展示（与列表页一致）
  static String _formatIsort(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return '';
    final n = int.tryParse(s);
    if (n == null) return s;
    return '#${n.toString().padLeft(4, '0')}';
  }

  Future<void> _loadDetail() async {
    try {
      final result = await request(
        HttpApi.saleFindSaleBillDetail,
        {'saleid': widget.order['saleid'], 'defaultflag': 1, 'billno': widget.order['billno']},
      );
      final data = result['data'];
      if (!mounted) {
        return;
      }
      setState(() {
        // 接口仅返回商品明细 list；主单信息（含 pickflag）已由列表页跳转带入 widget.order（见 initState）
        final detail = data is Map<String, dynamic> ? data['list'] : null;
        if (detail is List) {
          _detailList = detail.cast<Map<String, dynamic>>();
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
                itemCount: _detailList.isEmpty ? 3 : _detailList.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildOrderCard();
                  }
                  if (index == 1) {
                    return _buildScanInput();
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
                  final item = _detailList[index - 2];
                  // pickflag == 0（待领取）或 == 2 时，点击商品明细不打开拣货弹窗
                  final pickflag = _master['pickflag']?.toString() ?? '';
                  final canOpenSheet = pickflag != '0' && pickflag != '2';
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == _detailList.length + 1 ? 0 : 10),
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
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// 点击商品明细项：打开商品详情弹窗（对齐原型：商品信息 + 拣货数量步进器）
  Future<void> _showGoodsDetail(Map<String, dynamic> item) async {
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
    // 状态优先取商品自身状态（确认拣货后变为"已拣货"），无则用订单级（pickflag）
    final status = item['_statusTitle']?.toString() ?? _pickflagTitle(_master['pickflag']);
    // 步进器初始值：本商品已在弹窗修改过拣货数量（确认拣货）时回显修改值；
    // 否则按单据状态：已拣货（pickflag == 2）回显 pickqty，待拣货/待下发默认订单数量 qty
    final pickflag = _master['pickflag']?.toString() ?? '';
    final pickedLocal = item['_statusTitle']?.toString() == '已拣货';
    final qtySource =
        (pickedLocal || pickflag == '2') ? (item['pickqty'] ?? item['qty']) : item['qty'];
    final qty = (num.tryParse(qtySource?.toString() ?? '') ?? 0).toInt();
    // 待拣货商品：拣货数量上限为接口返回的数量 qty，不能超拣（qty 缺失时不限制）
    final orderQty = (num.tryParse(item['qty']?.toString() ?? '') ?? 0).toInt();
    final maxQty = status == '待拣货' && orderQty > 0 ? orderQty : null;
    final picked = await showModalBottomSheet<int>(
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
        statusTitle: status,
        maxQty: maxQty,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      item['pickqty'] = picked;
      item['_statusTitle'] = '已拣货';
    });
    // 弹窗确认拣货数量后评估恢复扫描框焦点（连续扫码）
    _returnFocusToScanIfIdle();
  }

  // ──────────── 扫码枪（本地匹配）────────────

  /// 扫码枪输入统一入口：先清空输入框防重触发，处理完成后重新聚焦支持连续扫码
  Future<void> _onScanInput(String code) async {
    _scanController.clear();
    _scanDebounceTimer?.cancel();
    // 上一笔仍在弹窗中时丢弃本次输入，避免并发重复打开拣货弹窗
    if (_scanBusy) return;
    _scanBusy = true;
    try {
      await _handleScannedCode(code);
    } finally {
      _scanBusy = false;
    }
    if (!mounted) return;
    _scanFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// 扫码处理：仅在当前 _detailList 中本地匹配商品（不调接口），命中后直接打开拣货弹窗
  Future<void> _handleScannedCode(String code) async {
    final searchCode = code.trim();
    if (searchCode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    // pickflag == 0（待领取）或 == 2 时不允许扫码拣货（与列表项点击拦截规则保持一致）
    final pickflag = _master['pickflag']?.toString() ?? '';
    if (pickflag == '0' || pickflag == '2') {
      Toast.show('当前状态不支持扫码拣货');
      return;
    }
    if (_detailList.isEmpty) {
      Toast.show('暂无商品明细');
      return;
    }
    // 依次尝试 sbarcode / productbarcode / productcode / code / itemcode / barcode 字段匹配
    const keys = ['sbarcode', 'productbarcode', 'productcode', 'code', 'itemcode', 'barcode'];
    int matchedIndex = -1;
    for (int i = 0; i < _detailList.length; i++) {
      final item = _detailList[i];
      for (final key in keys) {
        final v = item[key]?.toString() ?? '';
        if (v.isNotEmpty && v == searchCode) {
          matchedIndex = i;
          break;
        }
      }
      if (matchedIndex >= 0) break;
    }
    if (matchedIndex < 0) {
      Toast.show('未查询到该商品');
      return;
    }
    await _showGoodsDetail(_detailList[matchedIndex]);
  }

  /// 扫描框始终渲染（列表首项固定展示）
  bool get _showScanInput => true;

  /// 拣货数量弹窗确认关闭后焦点“落空”时，将焦点恢复到红外扫描框，支持连续扫码；
  /// 焦点已落到其他输入框（用户主动点按）时不干预；弹窗收尾动画中最多重试 30 帧再评估
  void _returnFocusToScanIfIdle([int retryFrame = 0]) {
    if (!_showScanInput) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showScanInput) return;
      // 弹窗/其他页面覆盖中（商品详情弹窗、选品页等）不抢焦点；收尾动画中重试等待
      if (ModalRoute.of(context)?.isCurrent != true) {
        if (retryFrame < 30) _returnFocusToScanIfIdle(retryFrame + 1);
        return;
      }
      final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
      // 焦点已在某个具体控件上（其他输入框或扫描框自身）：不干预
      if (primaryFocus != null && primaryFocus is! FocusScopeNode) return;
      _scanFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  /// 扫码枪输入框（与促销调价单一致：白色圆角卡片包裹）
  Widget _buildScanInput() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: TextField(
          controller: _scanController,
          focusNode: _scanFocusNode,
          autofocus: true,
          showCursor: true,
          keyboardType: TextInputType.none,
          enableInteractiveSelection: false,
          style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '请将扫描枪对准商品条码',
            hintStyle: TextStyle(fontSize: 13, color: Color(0xFFD1D5DB)),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF006EFF)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
    );
  }

  /// 完成拣货（operate=2），成功后返回列表
  Future<void> _completePicking() async {
    if (_completing) {
      return;
    }
    // 所有商品均为待拣货（无任何确认拣货记录）时拦截提交，提示先拣货
    final pickedCount =
        _detailList.where((item) => item['_statusTitle']?.toString() == '已拣货').length;
    if (_detailList.isEmpty || pickedCount == 0) {
      Toast.show('请先拣货');
      return;
    }
    // 部分商品已拣货：二次确认，确定继续调拣货接口，取消关闭确认框
    if (pickedCount < _detailList.length) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提示'),
          content: const Text('当前有商品还未拣货，是否继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      );
      if (confirm != true) return;
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
      // 提示文案与底部按钮一致：pickflag == 3（待下发）显示“提前拣货”
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
                      _formatIsort(isort),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF006EFF),
                      ),
                    ),
                  ],
                ),
              ),
              if (_pickflagTitle(_master['pickflag']).isNotEmpty)
                Text(
                  _pickflagTitle(_master['pickflag']),
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
              const Spacer(),
              // 领取倒计时：四个状态均展示，与列表页一致，归零展示 00分00秒 不隐藏
              // 待下发（pickflag == 3）倒计时为 30 分钟，其余状态为 5 分钟
              _ClaimCountdown(
                billdate: _firstOf(_master, ['billdate', 'createtime', 'ordertime']),
                minutes: _master['pickflag']?.toString() == '3' ? 30 : 5,
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 4),
              Text(
                '订单编号: ${_firstOf(_master, ['billno'])}',
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
    // 单据状态为已拣货（pickflag == 2）展示实际拣货数量 pickqty；
    // 待拣货/待下发（pickflag == 1/3，待下发业务与待拣货一致）后端 pickqty 仍为 0，默认展示订单数量 qty；
    // 本商品已在弹窗修改过拣货数量（确认拣货）时，展示修改后的 pickqty
    final pickflag = _master['pickflag']?.toString() ?? '';
    final pickedLocal = item['_statusTitle']?.toString() == '已拣货';
    final usePickQty = pickflag == '2' || pickedLocal;
    final qty = (usePickQty ? item['pickqty'] : item['qty'])?.toString() ?? '';
    final unit = _firstOf(item, ['unit', 'unitname', 'stockunit']);
    // 右侧黄色角标（货架位/拣货序号等，值过长不展示）
    final tag = _firstOf(item, ['rackno', 'binno', 'gridno', 'sortno', 'pickno', 'rowno']);
    final showTag = tag.isNotEmpty && tag.length <= 6;

    // 每行右侧状态标签：优先取商品自身状态（确认拣货后变为"已拣货"），无则用订单级（pickflag）
    final statusTitle = item['_statusTitle']?.toString() ?? _pickflagTitle(_master['pickflag']);

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
                    // 状态标签：待拣货红色 / 已拣货蓝色，做视觉区分
                    if (statusTitle.isNotEmpty)
                      Text(
                        statusTitle,
                        style: TextStyle(fontSize: 18, color: _statusColor(statusTitle)),
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

  // ──────────── 底部按钮 ────────────

  /// 底部按钮：根据接口返回的 pickflag 判断
  /// 0 待领取 → 领取任务；1 待拣货 / 3 待下发 → 完成拣货（待下发文案为「提前拣货」）；2 已拣货 → 无按钮
  Widget? _buildBottomBar() {
    final String pickflag = _master['pickflag']?.toString() ?? '';
    switch (pickflag) {
      case '0':
        return _buildClaimBar();
      case '1':
      case '3':
        return _buildCompletePickingBar();
      case '2':
      default:
        return null;
    }
  }

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
    // pickflag == 3（待下发）时按钮文案显示“提前拣货”，否则“完成拣货”
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

/// 领取任务倒计时：目标时间 = billdate + minutes 分钟（待下发 30 分钟，其余 5 分钟），每秒刷新
/// 剩余为 0 时展示「剩余: 00分00秒」不隐藏；颜色与预计时间文字一致
class _ClaimCountdown extends StatefulWidget {
  const _ClaimCountdown({required this.billdate, this.minutes = 5});

  final String? billdate;

  /// 倒计时时长（分钟）：待下发 30，其余状态 5
  final int minutes;

  @override
  State<_ClaimCountdown> createState() => _ClaimCountdownState();
}

class _ClaimCountdownState extends State<_ClaimCountdown> {
  Timer? _timer;
  DateTime? _target;

  /// 解析下单时间：兼容 "yyyy-MM-dd HH:mm:ss"、斜杠/紧凑格式与秒/毫秒时间戳
  static DateTime? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final trimmed = raw.trim();
    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return parsed;
    }
    // 斜杠分隔："yyyy/MM/dd HH:mm:ss"
    final slashParsed = DateTime.tryParse(trimmed.replaceAll('/', '-'));
    if (slashParsed != null) {
      return slashParsed;
    }
    // 纯数字紧凑格式：14 位 yyyyMMddHHmmss / 8 位 yyyyMMdd
    if (RegExp(r'^\d{14}$').hasMatch(trimmed)) {
      return DateTime.tryParse('${trimmed.substring(0, 4)}-${trimmed.substring(4, 6)}-'
          '${trimmed.substring(6, 8)} ${trimmed.substring(8, 10)}:'
          '${trimmed.substring(10, 12)}:${trimmed.substring(12, 14)}');
    }
    if (RegExp(r'^\d{8}$').hasMatch(trimmed)) {
      return DateTime.tryParse('${trimmed.substring(0, 4)}-${trimmed.substring(4, 6)}-'
          '${trimmed.substring(6, 8)}');
    }
    // 时间戳：10 位秒级 / 13 位毫秒级（兼容 "/Date(…)/" 等包裹格式）
    final numValue = num.tryParse(trimmed) ??
        num.tryParse(RegExp(r'\d{10,13}').firstMatch(trimmed)?.group(0) ?? '');
    if (numValue != null) {
      final ms = numValue >= 1000000000000 ? numValue.toInt() : numValue.toInt() * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _syncCountdown();
  }

  @override
  void didUpdateWidget(covariant _ClaimCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据刷新/复用导致 billdate 或倒计时时长变化时，重算目标时间并重启计时
    if (oldWidget.billdate != widget.billdate || oldWidget.minutes != widget.minutes) {
      _syncCountdown();
    }
  }

  /// 重算目标时间（billdate + minutes 分钟）并按需启动每秒刷新计时
  void _syncCountdown() {
    _timer?.cancel();
    _timer = null;
    _target = _parseTime(widget.billdate)?.add(Duration(minutes: widget.minutes));
    if (_target != null && _target!.isAfter(DateTime.now())) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        if (!_target!.isAfter(DateTime.now())) {
          // 已超时：停止计时，保留展示「剩余: 00分00秒」
          _timer?.cancel();
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // billdate 无法解析时不渲染；剩余为 0 不隐藏，展示「剩余: 00:00」
    final target = _target;
    if (target == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final diff = target.isAfter(now) ? target.difference(now) : Duration.zero;
    final text = '剩余: ${diff.inMinutes.toString().padLeft(2, '0')}分'
        '${(diff.inSeconds % 60).toString().padLeft(2, '0')}秒';
    return Text(
      text,
      // 颜色与「预计」时间文字保持一致
      style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
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
    this.maxQty,
  });

  final String title;
  final String img;
  final String productcode;
  final String zone;
  final String pos;
  final String unit;
  final int qty;
  final String statusTitle;

  /// 拣货数量上限：待拣货商品为接口返回的数量 qty（不能超拣）；null 表示不限制
  final int? maxQty;

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
    // 待拣货商品：拣货数量不能超过接口返回的数量 qty
    if (widget.maxQty != null && next > widget.maxQty!) {
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
                        border: Border.all(
                            color: _statusColor(widget.statusTitle, const Color(0xFFEF4444))),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.statusTitle,
                        style: TextStyle(
                            fontSize: 11,
                            color: _statusColor(widget.statusTitle, const Color(0xFFEF4444))),
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
    // 待拣货商品：拣货数量达到接口返回的数量 qty 时禁用加号，不能超拣
    final canIncrease = widget.maxQty == null || pickqty < widget.maxQty!;
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
        _stepButton(Icons.add, canIncrease, () => _changeQty(1)),
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
