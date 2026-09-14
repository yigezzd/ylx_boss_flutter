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
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';

/// 报表 Tab 页面 —— 对齐 boss 项目 data.vue
class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '报表',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Color(0xFF9F9F9F)),
            onPressed: () => Toast.show('更多设置'),
          ),
        ],
      ),
      body: ListView.builder(
        cacheExtent: 800,
        // 底部留出导航栏高度（SafeArea ≈ 34 + navBar 56 ≈ 90），防止内容被遮挡
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
        itemCount: _sectionTitles.length + 1, // +1 for bottom spacing
        itemBuilder: (context, index) {
          if (index == _sectionTitles.length) {
            return const SizedBox(height: 16);
          }
          return _SectionCard(
            title: _sectionTitles[index],
            items: _sectionItems[index],
          );
        },
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
  const _SectionCard({required this.title, required this.items});
  final String title;
  final List<_ReportItem> items;

  @override
  Widget build(BuildContext context) {
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
          for (int i = 0; i < items.length; i += 2)
            Row(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    child: _ReportCard(item: items[i], sectionTitle: title),
                  ),
                ),
                if (i + 1 < items.length)
                  Expanded(
                    child: RepaintBoundary(
                      child: _ReportCard(item: items[i + 1], sectionTitle: title),
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
  const _ReportCard({required this.item, required this.sectionTitle});
  final _ReportItem item;

  /// 所属分区名称（如"经营报表"、"库存分析"），用于操作审计日志定位
  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // 有 menuId 时先做权限校验（对齐 boss 项目 navPath 逻辑）
        if (item.menuId.isNotEmpty) {
          if (!PermissionUtils.checkPermission(item.menuId)) {
            return; // 无权限，checkPermission 内部已弹 Toast
          }
        }

        // 操作审计：点击报表模块
        FileLogWriter.instance.writeOperationLog(
          '报表',
          '点击模块',
          '$sectionTitle/${item.title}',
        );

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
      child: Container(
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
      ),
    );
  }
}
