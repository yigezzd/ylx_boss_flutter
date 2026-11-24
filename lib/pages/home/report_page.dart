import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/business/inventory/router.dart';
import 'package:flutter_deer/pages/data/businessReport/businessAnalysis/business_analysis_router.dart';
import 'package:flutter_deer/pages/data/businessReport/cashFlow/cash_flow_router.dart';
import 'package:flutter_deer/pages/data/businessReport/cashStatistics/cash_statistics_router.dart';
import 'package:flutter_deer/pages/data/businessReport/cashierMonitoring/cashier_monitoring_router.dart';
import 'package:flutter_deer/pages/data/businessReport/exceptionMonitoring/exception_monitoring_router.dart';
import 'package:flutter_deer/pages/data/businessReport/productABC/product_abc_router.dart';
import 'package:flutter_deer/pages/data/businessReport/salesRateAnalysis/sales_rate_analysis_router.dart';
import 'package:flutter_deer/pages/data/businessReport/typeABC/type_abc_router.dart';
import 'package:flutter_deer/pages/data/inventory/changQue/chang_que_router.dart';
import 'package:flutter_deer/pages/data/inventory/enterUnsold/enter_unsold_router.dart';
import 'package:flutter_deer/pages/data/inventory/inventoryWarn/inventory_warn_router.dart';
import 'package:flutter_deer/pages/data/inventory/loadStock/load_stock_router.dart';
import 'package:flutter_deer/pages/data/inventory/unsalable/unsalable_router.dart';
import 'package:flutter_deer/pages/data/inventory/vaildWarn/vaild_warn_router.dart';
import 'package:flutter_deer/pages/data/inventory/zeroStock/zero_stock_router.dart';
import 'package:flutter_deer/pages/data/member/addVipAnalysis/add_vip_analysis_router.dart';
import 'package:flutter_deer/pages/data/member/consumptionTop/consumption_top_router.dart';
import 'package:flutter_deer/pages/data/member/couponAnalysis/coupon_analysis_router.dart';
import 'package:flutter_deer/pages/home/widgets/seat_widgets.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/vas_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';

/// 报表 Tab 页面 —— 对齐 boss 项目 data.vue
///
/// 席位与版本机制（对齐 data.vue）：
/// - 标题展示"报表（专业版/基础版）"；
/// - 专业版：显示席位到期提醒条（距到期 15 天内）；
/// - 基础版：非免费白名单功能灰显，点击弹"功能受限"提示；
///   分区顺序调整为"经营报表、库存分析、会员报表"，且库存分析内部高频功能前置；
/// - 席位数据来自 [VasUtils]（vas/getVasList 与 sysSeat 缓存合并，sysSeat 优先）。
class ReportPage extends StatefulWidget {
  const ReportPage({super.key, this.onSwitchToMyTab});

  /// 切换到"我的"tab 的回调
  /// （对齐 Vue 席位续费弹窗"解绑席位"→ uni.switchTab 我的页）
  final VoidCallback? onSwitchToMyTab;

  @override
  State<ReportPage> createState() => ReportPageState();
}

class ReportPageState extends State<ReportPage> {
  // ──────────── 席位与版本状态（对齐 data.vue vasObj / isPro）────────────

  /// 是否专业版（席位 expiretime 未过期 且 vertype >= 0）
  bool _isPro = false;

  /// 是否显示席位到期提醒条（专业版 且 距到期 ±15 天内）
  bool _showSeatExpireTip = false;

  /// 席位号（无值时显示 "--"）
  String _seatCode = '--';

  /// 席位到期日期（YYYY-MM-DD）
  String _seatExpireDate = '';

  @override
  void initState() {
    super.initState();
    // 初始化席位与版本状态：先读缓存立即渲染，再异步拉取最新数据
    final _SeatViewState seatView = _computeSeatView();
    _isPro = seatView.isPro;
    _seatCode = seatView.seatCode;
    _seatExpireDate = seatView.expireDate;
    _showSeatExpireTip = seatView.showExpireTip;
    unawaited(refreshSeatInfo());
  }

  // ──────────── 席位与版本 ────────────

  /// 刷新席位与版本信息：先用本地缓存刷新视图，再拉取最新增值服务列表后再次刷新
  ///
  /// [VasUtils.fetchVasList] 未登录不请求、10s 节流、并发不重入（对齐 Vue fetchVasList）
  Future<void> refreshSeatInfo() async {
    _applySeatState();
    await VasUtils.fetchVasList();
    _applySeatState();
  }

  /// 从缓存计算席位视图状态
  /// （对齐 data.vue vasObj → isPro / seatCode / seatExpireDate / showSeatExpireTip）
  static _SeatViewState _computeSeatView() {
    final Map<String, dynamic> seat = VasUtils.getSeatInfo();
    final bool isPro = VasUtils.isPro(seat);
    final String code = seat['code']?.toString() ?? '';
    return _SeatViewState(
      isPro: isPro,
      // 对齐 Vue showSeatExpireTip：与 isPro 同时成立才显示提醒条
      showExpireTip: isPro && VasUtils.isNearExpire(seat),
      seatCode: code.isEmpty ? '--' : code,
      expireDate: VasUtils.formatExpireDate(seat),
    );
  }

  /// 应用席位视图状态（有变化时才触发重建）
  void _applySeatState() {
    final _SeatViewState v = _computeSeatView();
    if (_isPro == v.isPro &&
        _seatCode == v.seatCode &&
        _seatExpireDate == v.expireDate &&
        _showSeatExpireTip == v.showExpireTip) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isPro = v.isPro;
      _seatCode = v.seatCode;
      _seatExpireDate = v.expireDate;
      _showSeatExpireTip = v.showExpireTip;
    });
  }

  /// 基础版（非专业版）免费开放的功能白名单（对齐 Vue FREE_TITLES）
  static const Set<String> _freeTitles = <String>{
    '收银流水',
    '收银统计',
    '销售监控',
    '异常监控',
    '经营分析',
    '库存查询',
    '库存预警',
    '有效期预警',
  };

  /// 判断功能项是否被锁定（对齐 Vue isItemLocked：非专业版 且 不在白名单）
  bool _isItemLocked(String title) {
    if (_isPro) {
      return false;
    }
    return !_freeTitles.contains(title);
  }

  /// 基础版库存分析内部前置条目（对齐 Vue STOCK_PRIORITY）
  static const List<String> _stockPriority = <String>['库存查询', '库存预警', '有效期预警', '零库存'];

  /// 分区显示顺序（对齐 Vue sortedList）：
  /// 专业版保持定义顺序；基础版将"库存分析"分区移动到"经营报表"之后
  List<int> get _visibleOrder {
    if (_isPro) {
      return List<int>.generate(_sectionTitles.length, (i) => i);
    }
    return <int>[
      _sectionTitles.indexOf('经营报表'),
      _sectionTitles.indexOf('库存分析'),
      _sectionTitles.indexOf('会员报表'),
    ];
  }

  /// 分区条目（基础版将库存分析内部高频功能前置，对齐 Vue sortedList 内部重排）
  List<_ReportItem> _itemsOfSection(int sectionIndex) {
    if (_isPro || _sectionTitles[sectionIndex] != '库存分析') {
      return _sectionItems[sectionIndex];
    }
    final List<_ReportItem> priority =
        _inventoryReportList.where((e) => _stockPriority.contains(e.title)).toList();
    final List<_ReportItem> rest =
        _inventoryReportList.where((e) => !_stockPriority.contains(e.title)).toList();
    return <_ReportItem>[...priority, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final List<int> order = _visibleOrder;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        // 对齐“我的”页标题左边距（20），去除隐式 leading 占位
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '报表',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            // 版本标识（对齐 Vue navtit：报表（专业版/基础版））
            Text(
              '（${_isPro ? '专业版' : '基础版'}）',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: Color(0xFF999999),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Color(0xFF9F9F9F)),
            onPressed: () => Toast.show('更多设置'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 席位到期提醒条 — 专业版且距到期 15 天内显示（对齐 Vue .seat-tip）
          if (_isPro && _showSeatExpireTip)
            SeatExpireTip(
              seatCode: _seatCode,
              expireDate: _seatExpireDate,
              onRenewTap: () => showSeatRenewDialog(
                context,
                expireDate: _seatExpireDate,
                onUnbind: widget.onSwitchToMyTab,
              ),
            ),
          Expanded(
            // 监听权限版本号：rolemap 刷新后自动重建，无权限入口即时隐藏
            child: ValueListenableBuilder<int>(
              valueListenable: PermissionUtils.revision,
              builder: (context, _, __) {
                return ListView.builder(
                  cacheExtent: 800,
                  // 底部留出导航栏高度（SafeArea ≈ 34 + navBar 56 ≈ 90），防止内容被遮挡
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                  itemCount: order.length + 1, // +1 for bottom spacing
                  itemBuilder: (context, index) {
                    if (index == order.length) {
                      return const SizedBox(height: 16);
                    }
                    final int i = order[index];
                    return _SectionCard(
                      title: _sectionTitles[i],
                      items: _itemsOfSection(i),
                      isItemLocked: _isItemLocked,
                      onLockedTap: () => showSeatLockedDialog(context),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 分区标题 ────────────
  static const List<String> _sectionTitles = [
    '经营报表',
    '会员报表',
    '库存分析',
  ];

  static final List<List<_ReportItem>> _sectionItems = [
    _businessReportList,
    _memberReportList,
    _inventoryReportList,
  ];

  // ──────────── 经营报表 ────────────
  static final List<_ReportItem> _businessReportList = [
    const _ReportItem('收银流水', '销售流水统计', 'cashwater.svg', menuId: '020101'),
    const _ReportItem('收银统计', '金额、币种、交班统计', 'cashcount.svg', menuId: '020201'),
    const _ReportItem('销售监控', '销售数据和异常监控', 'salesee.svg', menuId: '020301'),
    const _ReportItem('异常监控', '收银异常数据监控', 'salesee.svg', menuId: '020401'),
    const _ReportItem('经营分析', '门店经营数据分析', 'businessAnalysis.svg', menuId: '020501'),
    const _ReportItem('动销率分析', '商品销售效率分析', 'dxlfx.svg', menuId: '021801'),
    const _ReportItem('商品ABC分析', '商品销售占比分析', 'spABCfx.svg', menuId: '021901'),
    const _ReportItem('类别ABC分析', '类别销售占比分析', 'lbABCfx.svg', menuId: '022001'),
  ];

  // ──────────── 会员报表 ────────────
  static final List<_ReportItem> _memberReportList = [
    const _ReportItem('会员分析', '会员数据综合分析', 'memberAnalysis.svg', menuId: '020601'),
    const _ReportItem('新增会员', '新增会员分析', 'addmember.svg', menuId: '020701'),
    const _ReportItem('消费排行', '会员消费数据排行', 'xfisort.svg', menuId: '020801'),
    const _ReportItem('优惠券分析', '优惠券数据分析', 'quanAnalysis.svg', menuId: '020901'),
    const _ReportItem('变动记录', '销售流水统计', 'changehistory.svg', menuId: '021001'),
  ];

  // ──────────── 库存分析 ────────────
  static final List<_ReportItem> _inventoryReportList = [
    const _ReportItem('畅缺商品', '畅销缺货商品', 'changQue.svg', menuId: '021001'),
    const _ReportItem('滞销商品', '近期滞销商品', 'unsalable.svg', menuId: '021101'),
    const _ReportItem('库存查询', '商品库存数据查询', 'pfsum.svg', menuId: '021201'),
    const _ReportItem('库存预警', '库存预警数据查询', 'ordersum.svg', menuId: '021301'),
    const _ReportItem('有效期预警', '有效期预警数据查询', 'ordersum.svg', menuId: '021401'),
    const _ReportItem('零库存', '商品库存为0', '0stock.svg', menuId: '021501'),
    const _ReportItem('负库存', '商品库存为负数', 'loadStock.svg', menuId: '021601'),
    const _ReportItem('进货未销', '无销售记录商品', 'enterUnsold.svg', menuId: '021701'),
  ];
}

// ─────────────────────────────────────────────────
// 分区卡片 Widget（懒加载：仅可见时构建）
// ─────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.items,
    this.isItemLocked,
    this.onLockedTap,
  });
  final String title;
  final List<_ReportItem> items;

  /// 判断单个功能项是否被锁定（基础版非白名单功能灰显），为空时不锁定
  final bool Function(String title)? isItemLocked;

  /// 锁定项点击回调（弹"功能受限"提示）
  final VoidCallback? onLockedTap;

  @override
  Widget build(BuildContext context) {
    // 权限过滤：无权限的入口直接隐藏（对齐 boss 项目 data.vue 的前置校验表现）
    final List<_ReportItem> visibleItems =
        items.where((e) => e.menuId.isEmpty || PermissionUtils.hasPermission(e.menuId)).toList();
    // 分区内所有入口均无权限时不展示
    if (visibleItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
          ),
          // 两列布局
          for (int i = 0; i < visibleItems.length; i += 2)
            Row(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    child: _ReportCard(
                      item: visibleItems[i],
                      sectionTitle: title,
                      locked: isItemLocked?.call(visibleItems[i].title) ?? false,
                      onLockedTap: onLockedTap,
                    ),
                  ),
                ),
                if (i + 1 < visibleItems.length)
                  Expanded(
                    child: RepaintBoundary(
                      child: _ReportCard(
                        item: visibleItems[i + 1],
                        sectionTitle: title,
                        locked: isItemLocked?.call(visibleItems[i + 1].title) ?? false,
                        onLockedTap: onLockedTap,
                      ),
                    ),
                  )
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────────
class _ReportItem {
  const _ReportItem(this.title, this.subtitle, this.svgFile, {this.menuId = ''});
  final String title;
  final String subtitle;
  final String svgFile;

  /// 权限菜单 ID（对应 boss 项目 data.vue 中每个 item 的 menuid）
  /// 为空字符串时表示无需权限校验，直接放行
  final String menuId;
}

// ─────────────────────────────────────────────────
// 报表卡片 Widget（使用 boss 项目远程 SVG 图标）
// ─────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.item,
    required this.sectionTitle,
    this.locked = false,
    this.onLockedTap,
  });
  final _ReportItem item;

  /// 所属分区名称（如"经营报表"、"库存分析"），用于操作审计日志定位
  final String sectionTitle;

  /// 是否被锁定（基础版非白名单功能：灰显 + 点击拦截）
  final bool locked;

  /// 锁定项点击回调（弹"功能受限"提示）
  final VoidCallback? onLockedTap;

  /// 锁定项视觉滤镜（对齐 Vue .item-disabled：grayscale(100%) + opacity 0.8）
  ///
  /// 灰度矩阵同时把 alpha 衰减到 0.8，用单个 ColorFilter 完成两种效果，
  /// 避免 Opacity 额外图层在低端设备上的合成开销。
  static const ColorFilter _lockedFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 0.8, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    // 卡片内容（提取为变量，便于锁定滤镜包裹）
    final Widget content = Container(
      height: 76,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // SVG 图标
          BossSvgIcon(svgFile: item.svgFile, size: 38),
          const SizedBox(width: 10),
          // 标题 + 副标题
          Expanded(
            child: Builder(builder: (ctx) {
              // 反向补偿系统字体缩放，确保文字大小固定
              final sysScale = MediaQuery.textScalerOf(ctx).scale(1.0);
              final invScale = sysScale > 0 ? 1.0 / sysScale : 1.0;
              return Transform.scale(
                scale: invScale,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          // 右箭头
          const Icon(
            Icons.chevron_right,
            color: Color(0xFF9CA3AF),
            size: 18,
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // 操作审计：点击报表模块
        FileLogWriter.instance.writeOperationLog(
          '报表',
          '点击模块',
          '$sectionTitle/${item.title}',
        );

        // 功能锁定校验（对齐 Vue itemCli：非专业版非白名单功能弹"功能受限"）
        if (locked) {
          onLockedTap?.call();
          return;
        }

        // 有 menuId 时先做权限校验（对齐 boss 项目 navPath 逻辑）
        if (item.menuId.isNotEmpty) {
          if (!PermissionUtils.checkPermission(item.menuId)) {
            return; // 无权限，checkPermission 内部已弹 Toast
          }
        }

        // 库存查询：跳转到库存查询列表页
        if (item.title == '库存查询') {
          NavigatorUtils.push(context, InventoryRouter.inventorySearchList);
          return;
        }
        // 收银流水：跳转到收银流水页
        if (item.title == '收银流水') {
          NavigatorUtils.push(context, CashFlowRouter.cashFlowList);
          return;
        }
        // 销售监控：跳转到销售监控页
        if (item.title == '销售监控') {
          NavigatorUtils.push(context, CashierMonitoringRouter.root);
          return;
        }
        // 异常监控：跳转到异常监控页
        if (item.title == '异常监控') {
          NavigatorUtils.push(context, ExceptionMonitoringRouter.root);
          return;
        }
        // 收银统计：跳转到收银统计页
        if (item.title == '收银统计') {
          NavigatorUtils.push(context, CashStatisticsRouter.list);
          return;
        }
        // 经营分析：跳转到经营分析页
        if (item.title == '经营分析') {
          NavigatorUtils.push(context, BusinessAnalysisRouter.root);
          return;
        }
        // 动销率分析：跳转到动销率分析页
        if (item.title == '动销率分析') {
          NavigatorUtils.push(context, SalesRateAnalysisRouter.root);
          return;
        }
        // 商品ABC分析：跳转到商品ABC分析页
        if (item.title == '商品ABC分析') {
          NavigatorUtils.push(context, ProductAbcRouter.root);
          return;
        }
        // 类别ABC分析：跳转到类别ABC分析页
        if (item.title == '类别ABC分析') {
          NavigatorUtils.push(context, TypeAbcRouter.root);
          return;
        }
        // 畅缺商品
        if (item.title == '畅缺商品') {
          NavigatorUtils.push(context, ChangQueRouter.root);
          return;
        }
        // 滞销商品
        if (item.title == '滞销商品') {
          NavigatorUtils.push(context, UnsalableRouter.root);
          return;
        }
        // 零库存
        if (item.title == '零库存') {
          NavigatorUtils.push(context, ZeroStockRouter.root);
          return;
        }
        // 负库存
        if (item.title == '负库存') {
          NavigatorUtils.push(context, LoadStockRouter.root);
          return;
        }
        // 进货未销
        if (item.title == '进货未销') {
          NavigatorUtils.push(context, EnterUnsoldRouter.root);
          return;
        }
        // 库存预警
        if (item.title == '库存预警') {
          NavigatorUtils.push(context, InventoryWarnRouter.root);
          return;
        }
        // 有效期预警
        if (item.title == '有效期预警') {
          NavigatorUtils.push(context, VaildWarnRouter.root);
          return;
        }
        // 会员分析
        if (item.title == '会员分析') {
          NavigatorUtils.push(context, BusinessAnalysisRouter.hyfx);
          return;
        }
        // 新增会员
        if (item.title == '新增会员') {
          NavigatorUtils.push(context, AddVipAnalysisRouter.root);
          return;
        }
        // 消费排行
        if (item.title == '消费排行') {
          NavigatorUtils.push(context, ConsumptionTopRouter.root);
          return;
        }
        // 优惠券分析
        if (item.title == '优惠券分析') {
          NavigatorUtils.push(context, CouponAnalysisRouter.root);
          return;
        }
        Toast.show('${item.title} - 此功能暂未开放，敬请期待！');
      },
      // 功能锁定项灰显（对齐 Vue .item-disabled 效果）
      child: locked ? ColorFiltered(colorFilter: _lockedFilter, child: content) : content,
    );
  }
}

// ─────────────────────────────────────────────────
// 席位视图状态（由缓存/接口数据计算得出，用于构建页面头部与锁定逻辑）
// ─────────────────────────────────────────────────
class _SeatViewState {
  const _SeatViewState({
    required this.isPro,
    required this.showExpireTip,
    required this.seatCode,
    required this.expireDate,
  });

  /// 是否专业版（align Vue isPro）
  final bool isPro;

  /// 是否显示席位到期提醒条（isPro && 距到期 ±15 天内）
  final bool showExpireTip;

  /// 席位号（无值时 "--"）
  final String seatCode;

  /// 席位到期日期（YYYY-MM-DD）
  final String expireDate;
}
