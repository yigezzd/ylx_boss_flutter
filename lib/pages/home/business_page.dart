import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/classify/list.dart';
import 'package:flutter_deer/pages/business/basis/commodity/list.dart';
import 'package:flutter_deer/pages/business/basis/newApplication/list.dart';
import 'package:flutter_deer/pages/business/basis/prepackPrice/prepack_price_home.dart';
import 'package:flutter_deer/pages/business/basis/printing/label_print_home.dart';
import 'package:flutter_deer/pages/business/basis/productChangePrice/list.dart';
import 'package:flutter_deer/pages/business/basis/promotionPlan/list.dart';
import 'package:flutter_deer/pages/business/basis/storeChangePrice/list.dart';
import 'package:flutter_deer/pages/business/chain/allot_apply/list.dart';
import 'package:flutter_deer/pages/business/chain/allot_delivery/list.dart';
import 'package:flutter_deer/pages/business/chain/allot_entry/list.dart';
import 'package:flutter_deer/pages/business/chain/deliver/list.dart';
import 'package:flutter_deer/pages/business/chain/enquiry/list.dart';
import 'package:flutter_deer/pages/business/chain/receivingnote/list.dart';
import 'package:flutter_deer/pages/business/chain/returentakedelivery/list.dart';
import 'package:flutter_deer/pages/business/chain/returnapplication/list.dart';
import 'package:flutter_deer/pages/business/chain/returndeliver/list.dart';
import 'package:flutter_deer/pages/business/finance/router.dart';
import 'package:flutter_deer/pages/business/fulfillment/delivery/delivery_order_list.dart';
import 'package:flutter_deer/pages/business/fulfillment/picking/takeout_picking_list.dart';
import 'package:flutter_deer/pages/business/inventory/costchange/list.dart';
import 'package:flutter_deer/pages/business/inventory/movewarehouse/list.dart';
import 'package:flutter_deer/pages/business/inventory/otherin/list.dart';
import 'package:flutter_deer/pages/business/inventory/otherout/list.dart';
import 'package:flutter_deer/pages/business/inventory/plan/list.dart';
import 'package:flutter_deer/pages/business/inventory/precheck/list.dart';
import 'package:flutter_deer/pages/business/inventory/quickcheck/list.dart';
import 'package:flutter_deer/pages/business/members/basic/list.dart';
import 'package:flutter_deer/pages/business/members/point/point_list.dart';
import 'package:flutter_deer/pages/business/members/recharge/recharge_list.dart';
import 'package:flutter_deer/pages/business/members/vippay/vippay_list.dart';
import 'package:flutter_deer/pages/business/purchase/cgorder/list.dart';
import 'package:flutter_deer/pages/business/purchase/cgother/list.dart';
import 'package:flutter_deer/pages/business/purchase/cgothercd/list.dart';
import 'package:flutter_deer/pages/business/purchase/cgplan/list.dart';
import 'package:flutter_deer/pages/business/purchase/cgth/list.dart';
import 'package:flutter_deer/pages/business/purchase/cgthsq/list.dart';
import 'package:flutter_deer/pages/business/purchase/cgzc/list.dart';
import 'package:flutter_deer/pages/business/purchase/instore/list.dart';
import 'package:flutter_deer/pages/business/purchase/supplier/list.dart';
import 'package:flutter_deer/pages/business/scan/scan_price.dart';
import 'package:flutter_deer/pages/business/wholesale/cust_manage/list.dart';
import 'package:flutter_deer/pages/business/wholesale/order_sum/list.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_order/list.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_return/list.dart';
import 'package:flutter_deer/pages/business/wholesale/pf_sale/list.dart';
import 'package:flutter_deer/pages/business/wholesale/receive_sum/list.dart';
import 'package:flutter_deer/pages/business/wms/launch/list.dart';
import 'package:flutter_deer/pages/business/wms/receive/list.dart';
import 'package:flutter_deer/pages/business/wms/restock/list.dart';
import 'package:flutter_deer/pages/business/wms/stockQuery/list.dart';
import 'package:flutter_deer/pages/business/wms/wmsSet/page.dart';
import 'package:flutter_deer/pages/home/set_cylist_page.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/review_config_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';

/// 业务 Tab 页面 —— 对齐 boss 项目 business.vue
///
/// 权限机制（对齐 boss 项目）：
/// - 切换到此 tab 时调用 [PermissionUtils.fetchRoleInfoRetMap] 刷新权限缓存（10s 节流）
/// - 点击业务 item 时通过 [PermissionUtils.checkPermission] 校验 menuId 权限
class BusinessPage extends StatefulWidget {
  const BusinessPage({super.key});

  @override
  State<BusinessPage> createState() => BusinessPageState();
}

class BusinessPageState extends State<BusinessPage> {
  /// 切换 tabbar 时由外部（home_page）调用，触发权限数据刷新
  ///
  /// 对齐 boss 项目 business.vue onShow → userStore.fetchRoleInfoRetMap()
  void refreshPermissions() {
    PermissionUtils.fetchRoleInfoRetMap();
    // 对齐 Vue fetchReviewBillTypeList 注释"用于 tabbar 切换时刷新审批类型数据"，
    // 保证各单据列表页进入时能读到最新审批配置（决定"已驳回"tab 是否显示）
    ReviewConfigUtils.refreshConfig();
  }

  @override
  void initState() {
    super.initState();
    _loadCyConfig();
    // 对齐 Vue business.vue onLoad → userStore.fetchReviewBillTypeList()（10s 节流保护）
    ReviewConfigUtils.refreshConfig();
  }

  /// 加载服务器保存的常用功能配置（对齐 Vue business.vue onLoad → HomeCard()）
  Future<void> _loadCyConfig() async {
    try {
      final res = await request(HttpApi.menuCommonGetMenuCommon, <String, dynamic>{});
      final data = res['data'];
      final menujson = (data is Map<String, dynamic> ? data['menujson'] : null)?.toString();
      if (menujson != null && menujson.isNotEmpty && mounted) {
        final dynamic decoded = jsonDecode(menujson);
        if (decoded is List) {
          setState(() {
            _cyList.clear();
            for (final e in decoded) {
              final title = e['tit']?.toString() ?? '';
              // 从其他模块找到对应的 _ModuleItem（保留 page/route 信息）
              for (int i = 1; i < _sectionItems.length; i++) {
                final found = _sectionItems[i].where((m) => m.title == title);
                if (found.isNotEmpty) {
                  _cyList.add(found.first);
                  break;
                }
              }
            }
          });
        }
      }
    } catch (_) {}
  }

  /// 打开常用功能设置页面
  void _openCySettings() {
    // 操作审计：常用功能设置
    FileLogWriter.instance.writeOperationLog('业务', '打开常用功能设置');

    // 收集所有可选模块（排除“常用功能”本身）
    final allModules = <CyModuleItem>[];
    for (int i = 1; i < _sectionItems.length; i++) {
      for (final item in _sectionItems[i]) {
        allModules.add(CyModuleItem(title: item.title, svgFile: item.svgFile));
      }
    }
    // 当前已选中的常用功能
    final currentSelected =
        _sectionItems[0].map((e) => CyModuleItem(title: e.title, svgFile: e.svgFile)).toList();

    Navigator.push<List<CyModuleItem>>(
      context,
      MaterialPageRoute<List<CyModuleItem>>(
        builder: (_) => SetCyListPage(
          allModules: allModules,
          initialSelected: currentSelected,
        ),
      ),
    ).then((result) {
      if (result != null && mounted) {
        // 更新常用功能列表
        setState(() {
          _cyList.clear();
          for (final item in result) {
            // 尝试从其他模块找到对应的 _ModuleItem
            for (int i = 1; i < _sectionItems.length; i++) {
              final found = _sectionItems[i].where((e) => e.title == item.title);
              if (found.isNotEmpty) {
                _cyList.add(found.first);
                break;
              }
            }
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '业务',
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
      body: Column(
        children: [
          // 常用功能 — 固定在顶部，不随列表滚动（对齐 Vue cy-fixed）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _SectionCard(
              title: '常用功能',
              items: _sectionItems[0],
              onSettingsTap: _openCySettings,
            ),
          ),
          // 其余模块 — 可滚动区域
          Expanded(
            child: ListView.builder(
              cacheExtent: 800,
              // 底部留出导航栏高度，防止内容被遮挡
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
              itemCount: _sectionTitles.length - 1, // 跳过 index 0（常用功能已固定显示）
              itemBuilder: (context, index) {
                return _SectionCard(
                  title: _sectionTitles[index + 1],
                  items: _sectionItems[index + 1],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 分区标题 ────────────
  /// 设为 `true` 可隐藏未完成开发的分区/模块（当前仅履约模块），后续放开只需改为 `false`
  static const bool _hideExtra = true;

  static final List<String> _sectionTitles = [
    '常用功能',
    '档案',
    '会员',
    '采购',
    '库存',
    if (!_hideExtra) '履约',
    '批发',
    '连锁',
    '财务',
    'WMS',
    '管理',
  ];

  static final List<List<_ModuleItem>> _sectionItems = [
    _cyList,
    _danganList,
    _huiyuanList,
    _caigouList,
    _kucunList,
    if (!_hideExtra) _lvyueList,
    _pifaList,
    _liansuoList,
    _caiwuList,
    _wmsList,
    _guanliList,
  ];

  // ──────────── 常用功能（从服务器动态加载）────────────
  static final List<_ModuleItem> _cyList = [];

  // ──────────── 档案 ────────────
  static final List<_ModuleItem> _danganList = [
    const _ModuleItem('扫码查价', 'saomachajia.svg', menuId: '015601', page: ScanPricePage()),
    const _ModuleItem('商品分类', 'protype.svg', menuId: '010101', page: CategoryListPage()),
    const _ModuleItem('商品档案', 'probook.svg', menuId: '010201', page: CommodityListPage()),
    const _ModuleItem('新品申请', 'newsapply.svg', menuId: '010301', page: NewApplicationListPage()),
    const _ModuleItem('快速调价', 'prochangeprice.svg', menuId: '010401', page: ChangePriceListPage()),
    const _ModuleItem('促销调价', 'promotionprice.svg',
        menuId: '014901', page: PromotionPlanListPage()),
    const _ModuleItem('门店调价', 'storeprice.svg', menuId: '010501', page: StoreChangePriceListPage()),
    const _ModuleItem('标签打印', 'tagprint.svg', menuId: '010601', page: LabelPrintHomePage()),
    const _ModuleItem('预包装改价', 'prochangeprice.svg',
        menuId: '010602', page: PrepackPriceHomePage()),
  ];

  // ──────────── 会员 ────────────
  static final List<_ModuleItem> _huiyuanList = [
    const _ModuleItem('会员管理', 'membermang.svg', menuId: '010701', page: MembersListPage()),
    const _ModuleItem('会员充值', 'membercharge.svg', menuId: '0108', page: RechargeListPage()),
    const _ModuleItem('积分管理', 'pointmanage.svg', menuId: '0109', page: PointListPage()),
    const _ModuleItem('会员收款', 'memberback.svg', menuId: '0110', page: VippayListPage()),
  ];

  // ──────────── 采购 ────────────
  static final List<_ModuleItem> _caigouList = [
    const _ModuleItem('供应商', 'gongyingshang.svg', menuId: '011101', page: SupplierListPage()),
    const _ModuleItem('采购计划', 'caigoujihua.svg', menuId: '011201', page: CgplanListPage()),
    const _ModuleItem('采购订货', 'caigoudinghuo.svg',
        menuId: '011301', page: PurchaseCgorderListPage()),
    const _ModuleItem('自采申请单', 'zicaishenqing.svg', menuId: '011401', page: CgzcListPage()),
    const _ModuleItem('直配订单', 'zhipeidingdan.svg', menuId: '011501', page: CgotherListPage()),
    const _ModuleItem('越库订单', 'yuekudingdan.svg', menuId: '011601', page: CgothercdListPage()),
    const _ModuleItem('采购入库', 'caigouruku.svg', menuId: '011701', page: PurchaseInstoreListPage()),
    // const _ModuleItem('拍照入库', 'paizhaoruku.svg'),
    const _ModuleItem('采购退货', 'caigoutuihuo.svg', menuId: '011901', page: PurchaseCgthListPage()),
    const _ModuleItem('退货申请', 'tuihuoshenqing.svg', menuId: '012001', page: CgthsqListPage()),
  ];
  // ──────────── 批发 ────────────
  static final List<_ModuleItem> _pifaList = [
    const _ModuleItem('客户管理', 'khgl.svg', menuId: '012101', page: CustManageListPage()),
    const _ModuleItem('批发订货', 'pfdh.svg', menuId: '012201', page: PfOrderListPage()),
    const _ModuleItem('批发销售', 'pfxs.svg', menuId: '012301', page: PfSaleListPage()),
    const _ModuleItem('批发退货', 'pfth.svg', menuId: '012401', page: PfReturnListPage()),
    const _ModuleItem('订货汇总', 'dhhz.svg', menuId: '012501', page: OrderSumListPage()),
    const _ModuleItem('应收款汇总', 'yskhz.svg', menuId: '012601', page: ReceiveSumListPage()),
  ];

  // ──────────── 连锁 ────────────
  static final List<_ModuleItem> _liansuoList = [
    const _ModuleItem('调拨申请', 'business_tbsq.svg', menuId: '012701', page: AllotApplyListPage()),
    const _ModuleItem('调拨出库', 'business_tbck.svg', menuId: '012801', page: AllotDeliveryListPage()),
    const _ModuleItem('调拨入库', 'business_tbrk.svg', menuId: '012901', page: AllotEntryListPage()),
    const _ModuleItem('要货申请', 'business_yhsq.svg', menuId: '013001', page: EnquiryListPage()),
    const _ModuleItem('配送发货', 'business_psfh.svg', menuId: '013101', page: DeliverListPage()),
    const _ModuleItem('配送收货', 'business_pssh.svg', menuId: '013201', page: ReceivingnoteListPage()),
    const _ModuleItem('配退申请', 'business_ptsq.svg',
        menuId: '013301', page: ReturnApplicationListPage()),
    const _ModuleItem('配退发货', 'business_ptfh.svg', menuId: '013401', page: ReturnDeliverListPage()),
    const _ModuleItem('配退收货', 'business_ptsh.svg',
        menuId: '013501', page: ReturnTakeDeliveryListPage()),
  ];

  // ──────────── 财务 ────────────
  static final List<_ModuleItem> _caiwuList = [
    const _ModuleItem('供应商结算', 'hsjs.svg', menuId: '014401', route: FinanceRouter.supplierPayList),
    const _ModuleItem('客户结算单', 'khjs.svg', menuId: '014501', route: FinanceRouter.customerPayList),
    const _ModuleItem('门店结算单', 'mdjs.svg', menuId: '014601', route: FinanceRouter.storePayList),
    const _ModuleItem('费用收支单', 'ycd.svg', menuId: '014701', route: FinanceRouter.costRevenueList),
  ];

  // ──────────── WMS ────────────
  // 图标与小程序 business.vue WMS 模块保持一致（WMS-sh/sj/bh/hwkccx/sz.svg）
  static final List<_ModuleItem> _wmsList = [
    const _ModuleItem('收货', 'WMS-sh.svg', menuId: '011201', page: WmsReceiveListPage()),
    const _ModuleItem('上架', 'WMS-sj.svg', menuId: '011201', page: WmsLaunchListPage()),
    const _ModuleItem('补货', 'WMS-bh.svg', menuId: '011201', page: WmsRestockListPage()),
    const _ModuleItem('货位库存查询', 'WMS-hwkccx.svg', menuId: '011201', page: WmsStockQueryPage()),
    const _ModuleItem('WMS设置', 'WMS-sz.svg', menuId: '011201', page: WmsSetPage()),
  ];

  // ──────────── 管理 ────────────
  static final List<_ModuleItem> _guanliList = [
    const _ModuleItem('授权管理', 'business_sqyh.svg', menuId: '0147', route: '/system/sysSeatList'),
    const _ModuleItem('用户管理', 'business_yhgl.svg', menuId: '0148', route: '/system/sysUserList'),
  ];

  // ──────────── 履约 ────────────
  static final List<_ModuleItem> _lvyueList = [
    const _ModuleItem('订单配送', 'lvyue_order_delivery.svg',
        menuId: '015001', page: DeliveryOrderListPage()),
    const _ModuleItem('外卖拣货', 'lvyue_picking.svg',
        menuId: '015002', page: TakeoutPickingListPage()),
  ];

  // ──────────── 库存 ────────────
  static final List<_ModuleItem> _kucunList = [
    const _ModuleItem('盘点计划', 'business_pdjh.svg', menuId: '013601', page: InventoryPlanListPage()),
    const _ModuleItem('预盘单', 'business_ypd.svg',
        menuId: '013701', page: InventoryPrecheckListPage()),
    const _ModuleItem('快速盘点', 'business_kspd.svg',
        menuId: '013801', page: InventoryQuickcheckListPage()),
    const _ModuleItem('其他出库单', 'qtckd.svg', menuId: '013901', page: InventoryOtheroutListPage()),
    const _ModuleItem('其他入库单', 'qtrkd.svg', menuId: '014001', page: InventoryOtherinListPage()),
    const _ModuleItem('移仓单', 'ycd.svg', menuId: '014101', page: InventoryMovewarehouseListPage()),
    const _ModuleItem('成本变更单', 'cbbg.svg', menuId: '014201', page: InventoryCostchangeListPage()),
  ];
}

// ─────────────────────────────────────────────────
// 分区卡片 Widget（懒加载：仅可见时构建）
// ─────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.items,
    this.onSettingsTap,
  });
  final String title;
  final List<_ModuleItem> items;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                if (onSettingsTap != null)
                  GestureDetector(
                    onTap: onSettingsTap,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '设置',
                          style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Color(0xFF666666),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              // 每行 4 个，每个占 1/4 宽度，高度自适应内容
              final itemWidth = constraints.maxWidth / 4;
              return Wrap(
                children: [
                  for (final item in items)
                    RepaintBoundary(
                      child: SizedBox(
                        width: itemWidth,
                        child: _GridItem(item: item, sectionTitle: title),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────────
class _ModuleItem {
  const _ModuleItem(this.title, this.svgFile, {this.page, this.route, this.menuId = ''});
  final String title;
  final String svgFile;
  final Widget? page;

  /// 路由名称（优先使用，支持 Web 刷新保持页面）
  final String? route;

  /// 权限菜单 ID（对应 boss 项目 business.vue 中每个 item 的 menuid）
  /// 为空字符串时表示不做权限校验，直接放行
  final String menuId;
}

// ─────────────────────────────────────────────────
// 网格单项 Widget（使用 boss 项目远程 SVG 图标）
// ─────────────────────────────────────────────────
class _GridItem extends StatelessWidget {
  const _GridItem({required this.item, required this.sectionTitle});
  final _ModuleItem item;

  /// 所属分区名称（如"采购"、"财务"），用于操作审计日志定位
  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BossSvgIcon(svgFile: item.svgFile),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 点击处理：权限校验 → 跳转（对齐 boss 项目 navPath 逻辑）
  void _handleTap(BuildContext context) {
    // 操作审计：点击业务模块
    FileLogWriter.instance.writeOperationLog(
      '业务',
      '点击模块',
      '$sectionTitle/${item.title}',
    );

    // 有 menuId 时先做权限校验
    if (item.menuId.isNotEmpty) {
      if (!PermissionUtils.checkPermission(item.menuId)) {
        return; // 无权限，checkPermission 内部已弹 Toast
      }
    }

    if (item.route != null) {
      Navigator.pushNamed(context, item.route!);
    } else if (item.page != null) {
      // 传入模块中文名作为路由名，供全局路由观察者记录操作审计日志
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/业务/$sectionTitle/${item.title}'),
          builder: (_) => item.page!,
        ),
      );
    } else {
      Toast.show('${item.title} - 此功能暂未开放，敬请期待！');
    }
  }
}
