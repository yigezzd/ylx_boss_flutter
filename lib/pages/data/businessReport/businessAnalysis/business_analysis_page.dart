import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/cgfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/hyfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/kdfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/lsfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/mdfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/pffx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/spfx_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/xsth_page.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/subpage/yjfx_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 经营分析入口页
/// 参考 D:\VUE\ylx-boss\src\subs\data\businessReport\businessAnalysis\index.vue
class BusinessAnalysisPage extends StatefulWidget {
  const BusinessAnalysisPage({super.key});

  @override
  State<BusinessAnalysisPage> createState() => _BusinessAnalysisPageState();
}

class _BusinessAnalysisPageState extends State<BusinessAnalysisPage> {
  // ── 门店 ──
  String _storeName = '';
  String _storeId = '';
  String _activeStoreId = '';
  String _spId = '';
  bool _isZd = false;

  // ── 日期 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId;

  // ── 状态 ──
  bool _loading = true;
  Map<String, dynamic> _cardData = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = now;
    _startDate = now; // 默认当天
    _activeQuickTimeId = 1; // 默认今日
    _loadStoreInfo();
    _fetchData();
  }

  void _loadStoreInfo() {
    try {
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final store = jsonDecode(storeStr) as Map<String, dynamic>;
        setState(() {
          _storeName = store['name']?.toString() ?? '全部机构';
          _storeId = store['id']?.toString() ?? '';
          _spId = store['spid']?.toString() ?? '';
          _activeStoreId = _storeId;
          _isZd = _storeId == _spId;
        });
      }
    } catch (_) {}
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Vue selectTime 组件 timeIndex 映射
  int get _selectdatetype {
    switch (_activeQuickTimeId) {
      case 0:
        return 0; // 昨天
      case 1:
        return 1; // 今日
      case 2:
        return 2; // 本周
      case 3:
        return 3; // 本月
      case 4:
        return 4; // 自定义
      default:
        return 1;
    }
  }

  // ── 门店选择（底部抽屉，对齐 cash_flow_page）──
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _activeStoreId,
    );
    if (result != null && mounted) {
      setState(() {
        final storeId = result['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _storeId = storeId;
        _storeName = result['storename']?.toString() ?? '';
      });
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{
        'sids': _storeId.isEmpty || _storeId == '0' ? <String>[] : <String>[_storeId],
        'sidsname': _storeName,
        'starttime': '${_fmtDate(_startDate)} 00:00:00',
        'endtime': '${_fmtDate(_endDate)} 23:59:59',
        'selectdatetype': _selectdatetype,
      };
      final result = await request(HttpApi.bossJyfxGetData, params);
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() => _cardData = data);
      }
    } catch (_) {
      if (mounted) Toast.show('加载失败，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────────
  // 数值格式化
  // ─────────────────────────────────────────────────
  String _fmt(dynamic val, {int decimals = 3}) {
    if (val == null) return decimals == 1 ? '0' : '0.00';
    final d = double.tryParse(val.toString());
    if (d == null) return val.toString();
    if (d == d.roundToDouble() && decimals > 1) return d.toStringAsFixed(0);
    return d.toStringAsFixed(decimals);
  }

  // ── 卡片数据（对齐 Vue getList）──
  List<_AnalysisCard> get _cards => [
        _AnalysisCard('零售分析', '020502', [
          _MetricItem('销售额', _fmt(_cardData['ls_rramt'])),
          _MetricItem('毛利额', _fmt(_cardData['ls_grossamt'])),
          _MetricItem('毛利率', '${_fmt(_cardData['ls_grossrate'])}%'),
        ]),
        _AnalysisCard('客单分析', '020503', [
          _MetricItem('客单数', _fmt(_cardData['kd_billnum'], decimals: 1)),
          _MetricItem('客单价', _fmt(_cardData['kd_billprice'])),
          _MetricItem('营业额', _fmt(_cardData['kd_rramt'])),
        ]),
        _AnalysisCard('会员分析', '020504', [
          _MetricItem('新增会员', _fmt(_cardData['vip_addnum'], decimals: 1)),
          _MetricItem('充值金额', _fmt(_cardData['vip_vipaddamt'])),
          _MetricItem('消费金额', _fmt(_cardData['vip_rramt'])),
          _MetricItem('消费占比', '${_fmt(_cardData['vip_prop'])}%'),
        ]),
        _AnalysisCard('商品分析', '020505', [
          _MetricItem('商品', _cardData['product_name']?.toString() ?? ''),
          _MetricItem('分类', _cardData['product_typename']?.toString() ?? ''),
          _MetricItem('品牌', _cardData['product_brandname']?.toString() ?? ''),
          _MetricItem('供应商', _cardData['product_supname']?.toString() ?? ''),
        ]),
        _AnalysisCard('销售退货', '020506', [
          _MetricItem('退货数量', _fmt(_cardData['sale_retqty'], decimals: 1)),
          _MetricItem('退货金额', _fmt(_cardData['sale_retamt'])),
        ]),
        _AnalysisCard('采购分析', '020507', [
          _MetricItem('采购数量', _fmt(_cardData['cg_qty'], decimals: 1)),
          _MetricItem('采购金额', _fmt(_cardData['cg_amt'])),
        ]),
        _AnalysisCard('批发分析', '020508', [
          _MetricItem('销售额', _fmt(_cardData['pf_amt'])),
          _MetricItem('毛利额', _fmt(_cardData['pf_grossamt'])),
          _MetricItem('毛利率', '${_fmt(_cardData['pf_grossrate'])}%'),
        ]),
        _AnalysisCard('门店分析', '020509', [
          _MetricItem('营业额', _fmt(_cardData['store_amt'])),
          _MetricItem('毛利额', _fmt(_cardData['store_grossamt'])),
          _MetricItem('毛利率', '${_fmt(_cardData['store_grossrate'])}%'),
        ]),
        _AnalysisCard('业绩分析', '020510', [
          _MetricItem('销售数量', _fmt(_cardData['user_rrqty'], decimals: 1)),
          _MetricItem('销售金额', _fmt(_cardData['user_rramt'])),
          _MetricItem('提成金额', _fmt(_cardData['user_saleductamt'])),
        ]),
      ];

  // ==================== Build ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '经营分析',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                children: [
                  // ── 门店选择下拉（对齐 cash_flow_page）──
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStore,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _storeName.isNotEmpty ? _storeName : '全部机构',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── 时间筛选器（对齐 cash_flow_page）──
          _buildTimeSelector(),
          // ── 卡片网格 ──
          Expanded(
            child: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView(
                    cacheExtent: 800,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
                    children: [
                      for (int i = 0; i < _cards.length; i += 2)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: RepaintBoundary(
                                child: _AnalysisCardWidget(card: _cards[i]),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (i + 1 < _cards.length)
                              Expanded(
                                child: RepaintBoundary(
                                  child: _AnalysisCardWidget(card: _cards[i + 1]),
                                ),
                              )
                            else
                              const Expanded(child: SizedBox()),
                          ],
                        ),
                    ],
                  ),
                ),
                // 居中加载图标卡片（无遮罩，加载中内容保持可见）
                if (_loading) _loadingCard,
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 居中加载图标卡片（无全屏遮罩，加载中内容保持可见）
  static const Widget _loadingCard = Positioned.fill(
    child: Center(
      child: SizedBox(
        width: 72,
        height: 72,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border.fromBorderSide(BorderSide(color: Color(0xFFE1E9F3))),
          ),
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF)),
            ),
          ),
        ),
      ),
    ),
  );

  // ==================== 时间筛选器（对齐 cash_flow_page）====================
  Widget _buildTimeSelector() {
    final labels = ['昨天', '今日', '本周', '本月', '自定义'];
    final activeId = _activeQuickTimeId ?? 1;
    const borderColor = Color(0xFFD1D5DB);
    const primary = Color(0xFF006EFF);
    const onSurface = Color(0xFF333333);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        children: [
          // 分段控制器
          Container(
            height: 37,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: List.generate(labels.length, (i) {
                final selected = activeId == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onQuickTimeSelect(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? Colors.white : onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          // 日期导航行
          _buildDateNavigation(),
        ],
      ),
    );
  }

  void _onQuickTimeSelect(int id) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (id) {
      case 0: // 昨天
        start = now.subtract(const Duration(days: 1));
        end = start;
        break;
      case 1: // 今日
        start = now;
        end = now;
        break;
      case 2: // 本周
        final weekday = now.weekday;
        start = now.subtract(Duration(days: weekday - 1));
        end = start.add(const Duration(days: 6));
        break;
      case 3: // 本月
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      default: // 自定义
        start = _startDate;
        end = _endDate;
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _activeQuickTimeId = id;
    });
    _fetchData();
  }

  Widget _buildDateNavigation() {
    final isRange = _activeQuickTimeId == 2 || _activeQuickTimeId == 4; // 本周/自定义
    final isMonth = _activeQuickTimeId == 3; // 本月
    final showArrows = _activeQuickTimeId != 4; // 自定义模式隐藏箭头

    return Row(
      children: [
        // 左箭头
        if (showArrows)
          GestureDetector(
            onTap: () => _timeShift(-1),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF666666)),
            ),
          ),
        if (showArrows) const SizedBox(width: 8),
        // 日期区域
        Expanded(
          child: Row(
            children: [
              if (isRange) ...[
                Expanded(child: _buildDatePart(_startDate, isStart: true)),
                _buildDateToSeparator(),
                Expanded(child: _buildDatePart(_endDate, isEnd: true)),
              ] else
                Expanded(child: _buildDatePart(_startDate, isMonth: isMonth)),
            ],
          ),
        ),
        if (showArrows) const SizedBox(width: 8),
        // 右箭头
        if (showArrows)
          GestureDetector(
            onTap: () => _timeShift(1),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF666666)),
            ),
          ),
      ],
    );
  }

  void _timeShift(int direction) {
    final id = _activeQuickTimeId ?? 1;
    DateTime start = _startDate;
    DateTime end = _endDate;
    switch (id) {
      case 0: // 昨天
      case 1: // 今日
        start = start.add(Duration(days: direction));
        end = start;
        break;
      case 2: // 本周
        start = start.add(Duration(days: 7 * direction));
        end = end.add(Duration(days: 7 * direction));
        break;
      case 3: // 本月
        start = DateTime(_startDate.year, _startDate.month + direction);
        end = DateTime(start.year, start.month + 1, 0);
        break;
      default: // 自定义（无箭头，不会触发）
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    _fetchData();
  }

  Widget _buildDatePart(DateTime date,
      {bool isStart = false, bool isEnd = false, bool isMonth = false}) {
    String label;
    if (isMonth) {
      label = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    } else {
      label = _fmtDate(date);
    }

    Future<void> onTap() async {
      if (isMonth) {
        final picked = await showCommonMonthPicker(context, initial: date);
        if (picked != null && mounted) {
          setState(() {
            _startDate = DateTime(picked.year, picked.month);
            _endDate = DateTime(picked.year, picked.month + 1, 0);
          });
          _fetchData();
        }
        return;
      }
      final picked = await showCommonDatePicker(context, initial: date);
      if (picked != null && mounted) {
        setState(() {
          if (isEnd) {
            _endDate = picked;
          } else if (isStart) {
            _startDate = picked;
          } else {
            _startDate = picked;
            _endDate = picked;
          }
        });
        _fetchData();
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        margin: EdgeInsets.only(
          left: isStart ? 0 : 4,
          right: isEnd ? 0 : 4,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
      ),
    );
  }

  Widget _buildDateToSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text('至',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════════
class _AnalysisCard {
  const _AnalysisCard(this.title, this.menuid, this.metrics);
  final String title;
  final String menuid;
  final List<_MetricItem> metrics;
}

class _MetricItem {
  const _MetricItem(this.name, this.value);
  final String name;
  final String value;
}

// ═══════════════════════════════════════════════════════════
// 经营分析卡片 Widget
// ═══════════════════════════════════════════════════════════
class _AnalysisCardWidget extends StatelessWidget {
  const _AnalysisCardWidget({required this.card});
  final _AnalysisCard card;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (card.title == '零售分析') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LsfxPage(),
                settings: const RouteSettings(name: '/businessAnalysis/lsfx'),
              ));
          return;
        }
        if (card.title == '客单分析') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const KdfxPage(),
                settings: const RouteSettings(name: '/businessAnalysis/kdfx'),
              ));
          return;
        }
        if (card.title == '批发分析') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PffxPage(),
                settings: const RouteSettings(name: '/businessAnalysis/pffx'),
              ));
          return;
        }
        if (card.title == '会员分析') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const HyfxPage(),
                settings: const RouteSettings(name: '/businessAnalysis/hyfx'),
              ));
          return;
        }
        if (card.title == '销售退货') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const XsthPage(),
                settings: const RouteSettings(name: '/businessAnalysis/xsth'),
              ));
          return;
        }
        if (card.title == '采购分析') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CgfxPage(),
                settings: const RouteSettings(name: '/businessAnalysis/cgfx'),
              ));
          return;
        }
        if (card.title == '门店分析') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MdfxPage(),
                settings: const RouteSettings(name: '/businessAnalysis/mdfx'),
              ));
          return;
        }
        if (card.title == '业绩分析') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const YjfxPage(),
                settings: const RouteSettings(name: '/businessAnalysis/yjfx'),
              ));
          return;
        }
        if (card.title == '商品分析') {
          Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SpfxPage(),
                settings: const RouteSettings(name: '/businessAnalysis/spfx'),
              ));
          return;
        }
        Toast.show('${card.title} - 功能开发中');
      },
      child: Container(
        height: 150,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // 蓝色标题栏
            Container(
              width: double.infinity,
              height: 36,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(color: Color(0xFF006EFF)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      card.title,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
                ],
              ),
            ),
            // 内容区（靠上对齐）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: card.metrics.map((m) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Text(
                          '${m.name}：',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                        ),
                        Expanded(
                          child: Text(
                            m.value.isNotEmpty ? m.value : '--',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF333333),
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
