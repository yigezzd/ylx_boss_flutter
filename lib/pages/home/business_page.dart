import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
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
import 'package:flutter_deer/pages/business/wms/location/list.dart';
import 'package:flutter_deer/pages/business/wms/receive/list.dart';
import 'package:flutter_deer/pages/business/wms/restock/list.dart';
import 'package:flutter_deer/pages/business/wms/stockQuery/list.dart';
import 'package:flutter_deer/pages/business/wms/wmsSet/page.dart';
import 'package:flutter_deer/pages/home/set_cylist_page.dart';
import 'package:flutter_deer/pages/home/widgets/seat_widgets.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/review_config_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/vas_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';

/// 业务 Tab 页面 —— 对齐 boss 项目 business.vue
///
/// 权限机制（对齐 boss 项目）：
/// - 切换到此 tab 时调用 [PermissionUtils.fetchRoleInfoRetMap] 刷新权限缓存（10s 节流）
/// - 点击业务 item 时通过 [PermissionUtils.checkPermission] 校验 menuId 权限
/// - 入口可见性对齐 business.vue itemsCheckFn / moduleCheckFn：
///   menuid 权限 + 加盟店/自营店标题限制 + WMS 模块开关（id == spid 或 storetype == 3 且已开通 711）
///
/// 席位与版本机制（对齐 boss 项目 business.vue）：
/// - 标题展示"业务（专业版/基础版）"；
/// - 专业版（席位 expiretime 未过期且 vertype >= 0）：显示常用功能区与席位到期提醒条；
/// - 基础版：常用功能区隐藏，"管理"分区移动到"会员"之后，
///   非免费白名单功能灰显（grayscale + 降透明度），点击弹"功能受限"提示；
/// - 席位数据来自 [VasUtils]（vas/getVasList 与 sysSeat 缓存合并，sysSeat 优先）。
class BusinessPage extends StatefulWidget {
  const BusinessPage({super.key, this.onSwitchToMyTab});

  /// 切换到"我的"tab 的回调
  /// （对齐 Vue 席位续费弹窗"解绑席位"→ uni.switchTab 我的页）
  final VoidCallback? onSwitchToMyTab;

  @override
  State<BusinessPage> createState() => BusinessPageState();
}

class BusinessPageState extends State<BusinessPage> {
  // ──────────── 席位与版本状态（对齐 business.vue vasObj / isPro）────────────

  /// 是否专业版（席位 expiretime 未过期 且 vertype >= 0）
  bool _isPro = false;

  /// 是否显示席位到期提醒条（专业版 且 距到期 ±15 天内）
  bool _showSeatExpireTip = false;

  /// 席位号（无值时显示 "--"）
  String _seatCode = '--';

  /// 席位到期日期（YYYY-MM-DD）
  String _seatExpireDate = '';

  // ──────────── 入口可见性状态（对齐 business.vue itemsCheckFn / moduleCheckFn）────────────

  /// 登录门店类型（登录后不变，避免每帧重复解析 store JSON）
  late final String _storetype = SelectStorePage.loginStoreField('storetype');
  late final String _storeId = SelectStorePage.loginStoreField('id');
  late final String _storeSpid = SelectStorePage.loginStoreField('spid');

  /// WMS 模块是否开放（门店类型条件 且 isOpenVas(711)），初始化 / 增值服务刷新后更新
  bool _wmsEnabled = false;

  /// 切换 tabbar 时由外部（home_page）调用，触发权限 / 审批配置 / 席位数据刷新
  ///
  /// 对齐 boss 项目 business.vue onShow：
  /// fetchRoleInfoRetMap + fetchVasList({ verid: "701,704,712" })
  void refreshPermissions() {
    PermissionUtils.fetchRoleInfoRetMap();
    // 对齐 Vue fetchReviewBillTypeList 注释"用于 tabbar 切换时刷新审批类型数据"，
    // 保证各单据列表页进入时能读到最新审批配置（决定"已驳回"tab 是否显示）
    ReviewConfigUtils.refreshConfig();
    // tabbar 切换时刷新席位与版本信息（对齐 Vue onShow → fetchVasList）
    unawaited(refreshSeatInfo());
    // 同步刷新商户增值服务（含 WMS 711），保证入口可见性与后台配置一致
    unawaited(_refreshAddVerInfo());
  }

  @override
  void initState() {
    super.initState();
    _loadCyConfig();
    // 对齐 Vue business.vue onLoad → userStore.fetchReviewBillTypeList()（10s 节流保护）
    ReviewConfigUtils.refreshConfig();
    // 初始化席位与版本状态：先读缓存立即渲染，再异步拉取最新数据
    final _SeatViewState seatView = _computeSeatView();
    _isPro = seatView.isPro;
    _seatCode = seatView.seatCode;
    _seatExpireDate = seatView.expireDate;
    _showSeatExpireTip = seatView.showExpireTip;
    // 先按本地缓存计算 WMS 开关，再异步刷新商户增值服务列表（含 verid 711）
    _wmsEnabled = _computeWmsEnabled();
    unawaited(refreshSeatInfo());
    unawaited(_refreshAddVerInfo());
  }

  /// 刷新商户增值服务列表（对齐 Vue onLoad → getAddVerList，含 WMS verid 711）
  Future<void> _refreshAddVerInfo() async {
    await VasUtils.fetchAddVerList();
    if (!mounted) {
      return;
    }
    final bool enabled = _computeWmsEnabled();
    if (enabled == _wmsEnabled) {
      return;
    }
    // WMS 分区 / 入口可见性依赖 addverList，开关变化后重建页面
    setState(() => _wmsEnabled = enabled);
    // 已选常用功能同步剔除失效模块（如 WMS 未开通）
    await _loadCyConfig();
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
  /// （对齐 business.vue vasObj → isPro / seatCode / seatExpireDate / showSeatExpireTip）
  static _SeatViewState _computeSeatView() {
    final Map<String, dynamic> seat = VasUtils.getSeatInfo();
    final bool isPro = VasUtils.isPro(seat);
    final String code = seat['code']?.toString() ?? '';
    return _SeatViewState(
      isPro: isPro,
      // 对齐 Vue showSeatExpireTip：模板中与 isPro 同时成立才显示
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
    '商品分类',
    '商品档案',
    '新品申请',
    '快速调价',
    '会员管理',
    '授权管理',
    '用户管理',
  };

  /// 判断功能项是否被锁定（对齐 Vue isItemLocked：非专业版 且 不在白名单）
  bool _isItemLocked(String title) {
    if (_isPro) {
      return false;
    }
    return !_freeTitles.contains(title);
  }

  /// 加盟店（storetype == 2）需要隐藏的入口（对齐 Vue itemsCheckFn）
  static const Set<String> _franchiseHiddenTitles = <String>{
    '直配订单',
    '越库订单',
    '调拨申请',
    '调拨出库',
    '调拨入库',
    '配送发货',
    '配退收货',
  };

  /// 自营店（storetype == 1）需要隐藏的入口（对齐 Vue itemsCheckFn）
  static const Set<String> _selfStoreHiddenTitles = <String>{
    '直配订单',
    '越库订单',
    '配送发货',
    '配退收货',
  };

  /// 计算 WMS 模块开关（对齐 Vue moduleCheckFn）：
  /// 门店需为总部 / 配送中心（id == spid 或 storetype == 3）且已开通 verid 711
  bool _computeWmsEnabled() {
    final bool isSpid = (_storeSpid.isNotEmpty && _storeSpid == _storeId) || _storetype == '3';
    return isSpid && VasUtils.isOpenVas(VasUtils.wmsVerId);
  }

  /// 判断功能入口是否可见（对齐 Vue itemsCheckFn + moduleCheckFn）：
  /// 1. WMS 分区需满足门店类型条件且已开通 711；
  /// 2. 无 menuid 权限隐藏；
  /// 3. 加盟店 / 自营店按标题隐藏指定入口。
  bool _isItemVisible(int sectionIndex, _ModuleItem item) {
    if (_sectionTitles[sectionIndex] == 'WMS' && !_wmsEnabled) {
      return false;
    }
    if (item.menuId.isNotEmpty && !PermissionUtils.hasPermission(item.menuId)) {
      return false;
    }
    if (_storetype == '2' && _franchiseHiddenTitles.contains(item.title)) {
      return false;
    }
    if (_storetype == '1' && _selfStoreHiddenTitles.contains(item.title)) {
      return false;
    }
    return true;
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
            for (final e in decoded.whereType<Map<dynamic, dynamic>>()) {
              final title = e['tit']?.toString() ?? '';
              // 从其他模块找到对应的 _ModuleItem（保留 page/route 信息）
              for (int i = 1; i < _sectionItems.length; i++) {
                final found = _sectionItems[i].where((m) => m.title == title);
                if (found.isNotEmpty) {
                  // 仅保留当前可见模块（无权限 / 门店类型限制 / WMS 未开通的一并剔除）
                  if (_isItemVisible(i, found.first)) {
                    _cyList.add(found.first);
                  }
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

    // 收集所有可选模块（排除“常用功能”本身）：
    // 与业务 Tab 共用同一套可见性规则（menuid 权限 + 门店类型限制 + WMS 模块开关）
    final allModules = <CyModuleItem>[];
    for (int i = 1; i < _sectionItems.length; i++) {
      for (final item in _sectionItems[i]) {
        if (!_isItemVisible(i, item)) {
          continue;
        }
        allModules.add(
          CyModuleItem(title: item.title, svgFile: item.svgFile, menuId: item.menuId),
        );
      }
    }
    // 当前已选中的常用功能：仅保留可选列表中存在的模块，避免无权限模块残留在顶部
    final Set<String> allowedTitles = allModules.map((e) => e.title).toSet();
    final currentSelected = _sectionItems[0]
        .where((e) => allowedTitles.contains(e.title))
        .map((e) => CyModuleItem(title: e.title, svgFile: e.svgFile, menuId: e.menuId))
        .toList();

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

  /// 分区显示顺序（对齐 Vue sortedList）：
  /// 专业版保持定义顺序；基础版将"管理"分区移动到"会员"之后；
  /// 分区内所有入口均无权限时整块隐藏（标题不渲染，对齐小程序 moduleCheckFn）
  List<int> get _visibleOrder {
    final List<int> order = List<int>.generate(_sectionTitles.length - 1, (i) => i + 1);
    if (!_isPro) {
      final int manageIdx = _sectionTitles.indexOf('管理');
      final int memberIdx = _sectionTitles.indexOf('会员');
      if (manageIdx > 0 && memberIdx > 0) {
        order.remove(manageIdx);
        order.insert(order.indexOf(memberIdx) + 1, manageIdx);
      }
    }
    return order.where(_hasVisibleItems).toList();
  }

  /// 分区内是否至少有一个入口可见（与 _SectionCard 内过滤保持一致）
  bool _hasVisibleItems(int index) => _sectionItems[index].any((e) => _isItemVisible(index, e));

  @override
  Widget build(BuildContext context) {
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
              '业务',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            // 版本标识（对齐 Vue navtit：业务（专业版/基础版））
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
      // 监听权限版本号：rolemap 刷新后自动重建，无权限入口即时隐藏
      body: ValueListenableBuilder<int>(
        valueListenable: PermissionUtils.revision,
        builder: (context, _, __) {
          // 权限刷新后重算分区顺序，无权限分区（含标题）即时隐藏
          final List<int> order = _visibleOrder;
          return Column(
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
              // 常用功能 — 固定在顶部，不随列表滚动（对齐 Vue cy-fixed v-show="isPro"）
              if (_isPro)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _SectionCard(
                    title: '常用功能',
                    items: _sectionItems[0],
                    onSettingsTap: _openCySettings,
                    isItemLocked: _isItemLocked,
                    onLockedTap: () => showSeatLockedDialog(context),
                    isItemVisible: (item) => _isItemVisible(0, item),
                  ),
                ),
              // 其余模块 — 可滚动区域
              Expanded(
                child: ListView.builder(
                  cacheExtent: 800,
                  // 底部留出导航栏高度，防止内容被遮挡
                  padding: EdgeInsets.fromLTRB(12, _isPro ? 0 : 8, 12, 80),
                  itemCount: order.length,
                  itemBuilder: (context, index) {
                    final int i = order[index];
                    return _SectionCard(
                      title: _sectionTitles[i],
                      items: _sectionItems[i],
                      isItemLocked: _isItemLocked,
                      onLockedTap: () => showSeatLockedDialog(context),
                      isItemVisible: (item) => _isItemVisible(i, item),
                    );
                  },
                ),
              ),
            ],
          );
        },
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
    const _ModuleItem('预包装改价', 'yubaozhuanggaijia.svg',
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
    const _ModuleItem('货位管理', 'WMS-hwkccx.svg', menuId: '011201', page: WmsLocationListPage()),
    const _ModuleItem('WMS设置', 'WMS-sz.svg', menuId: '011201', page: WmsSetPage()),
  ];

  // ──────────── 管理 ────────────
  static final List<_ModuleItem> _guanliList = [
    const _ModuleItem('授权管理', 'business_sqyh.svg', menuId: '0147', route: '/system/sysSeatList'),
    const _ModuleItem('用户管理', 'business_yhgl.svg', menuId: '0148', route: '/system/sysUserList'),
  ];

  // ──────────── 履约 ────────────
  static final List<_ModuleItem> _lvyueList = [
    // const _ModuleItem('订单配送', 'lvyue_order_delivery.svg',
    //     menuId: '015001', page: DeliveryOrderListPage()),
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
    this.isItemLocked,
    this.onLockedTap,
    this.isItemVisible,
  });
  final String title;
  final List<_ModuleItem> items;
  final VoidCallback? onSettingsTap;

  /// 判断单个功能项是否被锁定（基础版非白名单功能灰显），为空时不锁定
  final bool Function(String title)? isItemLocked;

  /// 锁定项点击回调（弹"功能受限"提示）
  final VoidCallback? onLockedTap;

  /// 判断单个功能项是否可见（权限 + 门店类型限制 + WMS 模块开关），
  /// 为空时仅按 menuId 权限校验
  final bool Function(_ModuleItem item)? isItemVisible;

  @override
  Widget build(BuildContext context) {
    // 可见性过滤：无权限 / 门店类型不匹配 / WMS 未开通的入口直接隐藏（对齐 Vue itemsCheckFn + moduleCheckFn）
    final visibleItems = items.where((e) {
      final bool Function(_ModuleItem)? filter = isItemVisible;
      if (filter != null) {
        return filter(e);
      }
      return e.menuId.isEmpty || PermissionUtils.hasPermission(e.menuId);
    }).toList();
    // 分区内所有入口均无权限时不展示；常用功能保留卡片以提供“设置”入口
    if (visibleItems.isEmpty && onSettingsTap == null) {
      return const SizedBox.shrink();
    }

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
                  for (final item in visibleItems)
                    RepaintBoundary(
                      child: SizedBox(
                        width: itemWidth,
                        child: _GridItem(
                          item: item,
                          sectionTitle: title,
                          locked: isItemLocked?.call(item.title) ?? false,
                          onLockedTap: onLockedTap,
                        ),
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
  const _GridItem({
    required this.item,
    required this.sectionTitle,
    this.locked = false,
    this.onLockedTap,
  });
  final _ModuleItem item;

  /// 所属分区名称（如"采购"、"财务"），用于操作审计日志定位
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
    final Widget content = Padding(
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
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(context),
      // 功能锁定项灰显（对齐 Vue .item-disabled 效果）
      child: locked ? ColorFiltered(colorFilter: _lockedFilter, child: content) : content,
    );
  }

  /// 点击处理：功能锁定校验 → 权限校验 → 跳转（对齐 boss 项目 itemCli / navPath 逻辑）
  void _handleTap(BuildContext context) {
    // 操作审计：点击业务模块
    FileLogWriter.instance.writeOperationLog(
      '业务',
      '点击模块',
      '$sectionTitle/${item.title}',
    );

    // 功能锁定校验（对齐 Vue itemCli：非专业版非白名单功能弹"功能受限"）
    if (locked) {
      onLockedTap?.call();
      return;
    }

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
