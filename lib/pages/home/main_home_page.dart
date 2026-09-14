import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/home/widgets/approval_reminder_helper.dart';
import 'package:flutter_deer/pages/home/widgets/payment_card.dart';
import 'package:flutter_deer/pages/home/widgets/sale_rank_card.dart';
import 'package:flutter_deer/pages/home/widgets/secondary_data_card.dart';
import 'package:flutter_deer/pages/home/widgets/stock_notice_bar.dart';
import 'package:flutter_deer/pages/home/widgets/trend_card.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 首页 —— 对齐 boss 项目数据看板
class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  // ── 状态 ──
  String _storeName = '欢迎使用';
  String _storeId = '';
  String _spId = '';
  String _activeStoreId = ''; // 机构选择回显
  int _dataBtn = 0; // 0=零售 1=批发
  int _timeIdx = 1; // 默认"今日"

  bool _loading = false;
  bool _hasLoaded = false; // 是否已完成首次加载

  /// 权限控制 —— 对齐 boss 项目 index.vue showHome()
  bool _hasPermission = true;
  bool _isCheckingPermission = true;

  // 卡片顺序（getHomeCard）
  List<Map<String, dynamic>> _cardList = [];
  // 完整卡片配置（含隐藏卡片），用于置顶/关闭操作
  final List<Map<String, dynamic>> _cardFullList = [];
  dynamic _rawHomeCardData; // getHomeCard 原始响应，供 saveHomeCard 回传
  // 默认卡片配置（对齐 Vue getHomeCardDetailList）
  static List<Map<String, dynamic>> get _defaultCardList => [
        <String, dynamic>{'fieldid': 'yysj', 'show': 1, 'isort': 1, 'fieldname': '营业/储值数据'},
        <String, dynamic>{'fieldid': 'yjxx', 'show': 1, 'isort': 2, 'fieldname': '预警信息'},
        <String, dynamic>{'fieldid': 'fkfs', 'show': 1, 'isort': 3, 'fieldname': '付款方式'},
        <String, dynamic>{'fieldid': 'qs', 'show': 1, 'isort': 4, 'fieldname': '营业额/客流量趋势'},
        <String, dynamic>{'fieldid': 'xsb', 'show': 1, 'isort': 5, 'fieldname': '分类/单品销售榜'},
      ];
  // 经营概览
  Map<String, dynamic> _overview = {};
  // 付款方式
  List<Map<String, dynamic>> _payList = [];
  // 趋势数据
  List<Map<String, dynamic>> _trendList = [];
  String _trendType = 'rramt'; // rramt=营业额 billnum=客流量
  String _myType = '0'; // 0=实销金额 1=会员充值
  // 库存不足提醒
  List<String> _stockTips = [];

  /// `false` 隐藏单据审批提醒 + 消息提醒，`true` 显示
  static const bool _showReminders = true;
  // 销售排行榜
  List<Map<String, dynamic>> _saleRankList = [];
  String _saleRankType = 'SaleType'; // SaleType=分类销售榜 SaleProd=单品销售榜
  int _saleRankSort = 0; // 0=按销售金额 1=按销售数量

  // 时间维度 daytype 映射
  static const List<_TimeTab> _timeTabs = [
    _TimeTab('昨天', '2'),
    _TimeTab('今日', '1'),
    _TimeTab('本周', '3'),
    _TimeTab('本月', '4'),
    _TimeTab('上月', '5'),
  ];

  @override
  void initState() {
    super.initState();
    // 初始化默认卡片数据，确保 API 返回前也能操作置顶/关闭
    _cardFullList.addAll(_defaultCardList);
    _cardList = _cardFullList.where((e) => e['show'] == 1).toList()
      ..sort((a, b) => (a['isort'] as int?)?.compareTo(b['isort'] as int? ?? 0) ?? 0);
    _loadStoreInfo();
    // 先检查权限，有权限再拉取业务数据
    _checkPermissionAndLoad();

    // 操作审计：进入首页
    FileLogWriter.instance.writeOperationLog('首页', '进入页面');
  }

  /// 权限检查 —— 对齐 boss 项目 index.vue showHome()
  ///
  /// 检查逻辑：
  /// 1. 无 rolemap 缓存 → 放行（兼容无权限管控场景）
  /// 2. rolemap["04"] 存在且值非 falsy → 放行
  /// 3. user.code == "1001" 或 user.roleid == "1001" → 超级管理员放行
  /// 4. 其他情况 → 无权限，不请求任何业务接口（仅允许 version/getversion、role/getInfoRetMap）
  void _checkPermissionAndLoad() {
    Map<String, dynamic>? rolemap;
    Map<String, dynamic>? user;

    try {
      final rolemapStr = SpUtil.getString(Constant.rolemap) ?? '';
      if (rolemapStr.isNotEmpty) {
        rolemap = jsonDecode(rolemapStr) as Map<String, dynamic>;
      }
      final userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        user = jsonDecode(userStr) as Map<String, dynamic>;
      }
    } catch (_) {}

    // 规则 1：无 rolemap → 放行
    if (rolemap == null) {
      _setPermissionAndLoad(true);
      return;
    }

    // 规则 2：rolemap["04"] 存在且非 falsy → 放行
    if (rolemap.containsKey('04')) {
      final val = rolemap['04'];
      if (val != null && val != false && val != 'false' && val != 0 && val != '0' && val != '') {
        _setPermissionAndLoad(true);
        return;
      }
    }

    // 规则 3：超级管理员放行
    if (user != null) {
      final code = user['code']?.toString() ?? '';
      final roleid = user['roleid']?.toString() ?? '';
      if (code == '1001' || roleid == '1001') {
        _setPermissionAndLoad(true);
        return;
      }
    }

    // 规则 4：无权限 → 不请求任何业务接口
    _setPermissionAndLoad(false);
  }

  void _setPermissionAndLoad(bool hasPerm) {
    setState(() {
      _hasPermission = hasPerm;
      _isCheckingPermission = false;
    });
    if (hasPerm) {
      _fetchAllData();
      if (_showReminders) {
        _fetchStockTips();
        _checkApproval();
      }
    }
    // 权限接口 role/getInfoRetMap 始终允许请求，尝试刷新权限缓存
    PermissionUtils.fetchRoleInfoRetMap();
  }

  void _loadStoreInfo() {
    try {
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final store = jsonDecode(storeStr) as Map<String, dynamic>;
        setState(() {
          _storeName = store['name']?.toString() ?? '欢迎使用';
          _storeId = store['id']?.toString() ?? '';
          _spId = store['spid']?.toString() ?? '';
          _activeStoreId = _storeId;
        });
      }
    } catch (_) {}
  }

  /// 切换机构（对齐采购入库 _selectStore）
  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _activeStoreId,
      title: '切换默认机构',
    );
    if (result != null && mounted) {
      setState(() {
        final storeId = result['storeid']?.toString() ?? '';
        _activeStoreId = storeId;
        _storeId = storeId;
        _storeName = result['storename']?.toString() ?? '全部机构';
        _spId = result['spid']?.toString() ?? '';
      });
      _fetchAllData();
    }
  }

  /// 构建通用请求参数（对齐 Boss 项目）
  Map<String, dynamic> _buildParams() {
    return {
      'sids': _storeId.isEmpty || _storeId == '0' ? <String>[] : <String>[_storeId],
      'spid': _spId,
      'daytype': _timeTabs[_timeIdx].daytype,
      'isorttype': 0,
    };
  }

  void _fetchAllData() {
    // 仅首次加载显示loading，后续切换静默刷新避免抖动
    if (!_hasLoaded) setState(() => _loading = true);
    final params = _buildParams();
    final isPf = _dataBtn == 1;
    // 并行请求：卡片顺序 + 概览 + 付款方式 + 趋势 + 销售排行榜
    // 零售/批发使用不同的概览和趋势接口
    final rankParams = {...params, 'isorttype': _saleRankSort};
    final saleRankApi = _saleRankType == 'SaleType'
        ? (isPf ? HttpApi.homeGetPFSaleType : HttpApi.homeGetSaleType)
        : (isPf ? HttpApi.homeGetPFSaleProd : HttpApi.homeGetSaleProd);
    final homeCardParams = <String, dynamic>{
      'sids': _storeId.isEmpty || _storeId == '0' ? <String>[] : <String>[_storeId],
      'spid': _spId,
    };
    Future.wait([
      request(HttpApi.homeGetHomeCard, homeCardParams),
      request(isPf ? HttpApi.homeGetPFBusinessOverview : HttpApi.homeGetBusinessOverview, params),
      request(isPf ? HttpApi.homeGetPFPaySum : HttpApi.homeGetPaySum, params),
      request(
          isPf ? HttpApi.homeGetPFBusinessStatistics : HttpApi.homeGetBusinessStatistics, params),
      request(saleRankApi, rankParams),
    ]).then((results) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasLoaded = true;
        // 卡片顺序（对齐 Vue: res[0].getHomeCardDetailList || getHomeCardDetailList）
        final cardData = results[0]['data'];
        List<Map<String, dynamic>> details;
        if (cardData is List && cardData.isNotEmpty && cardData[0] is Map<String, dynamic>) {
          _rawHomeCardData = cardData;
          details =
              (cardData[0]['getHomeCardDetailList'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        } else {
          // API 无数据时使用默认配置
          _rawHomeCardData = null;
          details = List<Map<String, dynamic>>.from(_defaultCardList);
        }
        _cardFullList
          ..clear()
          ..addAll(details);
        _cardList = details.where((e) => e['show'] == 1).toList()
          ..sort((a, b) => (a['isort'] as int?)?.compareTo(b['isort'] as int? ?? 0) ?? 0);
        // 经营概览 (Map)
        final overviewData = results[1]['data'];
        if (overviewData is Map<String, dynamic>) {
          _overview = overviewData;
        }
        // 付款方式 (List)
        final payData = results[2]['data'];
        if (payData is List) {
          _payList = payData.whereType<Map<String, dynamic>>().toList();
          _payList.sort((a, b) {
            final pa = double.tryParse(a['proportion']?.toString() ?? '0') ?? 0;
            final pb = double.tryParse(b['proportion']?.toString() ?? '0') ?? 0;
            return pb.compareTo(pa);
          });
        }
        // 趋势 (List)
        final trendData = results[3]['data'];
        if (trendData is List) {
          _trendList = trendData.whereType<Map<String, dynamic>>().toList();
        }
        // 销售排行榜 (List)
        final rankData = results[4]['data'];
        if (rankData is List) {
          _saleRankList = rankData.whereType<Map<String, dynamic>>().toList();
        }
      });
    });
  }

  void _onRefresh() {
    _fetchAllData();
  }

  /// 单独拉取销售排行榜（类型/排序切换时复用）
  void _fetchSaleRank() {
    final params = _buildParams();
    params['isorttype'] = _saleRankSort;
    final isPf = _dataBtn == 1;
    final api = _saleRankType == 'SaleType'
        ? (isPf ? HttpApi.homeGetPFSaleType : HttpApi.homeGetSaleType)
        : (isPf ? HttpApi.homeGetPFSaleProd : HttpApi.homeGetSaleProd);
    request(api, params).then((res) {
      if (!mounted) return;
      final data = res['data'];
      if (data is List) {
        setState(() => _saleRankList = data.whereType<Map<String, dynamic>>().toList());
      }
    });
  }

  // ─────────────────────────────────────────────────────────
  // 卡片置顶 / 关闭 / 保存（对齐 Vue handleChange + handleSave）
  // ─────────────────────────────────────────────────────────

  /// 置顶卡片：移到第 2 位
  void _cardPin(String fieldId) {
    if (_cardFullList.isEmpty) return;
    final idx = _cardFullList.indexWhere((e) => e['fieldid'] == fieldId);
    if (idx < 0) return;
    final item = _cardFullList.removeAt(idx);
    _cardFullList.insert(1, item); // 插到第 2 位（索引 1）
    // 同步更新显示列表
    _rebuildShowList();
    _cardSave();
  }

  /// 关闭卡片：设置 show=0
  void _cardHide(String fieldId) {
    if (_cardFullList.isEmpty) return;
    final idx = _cardFullList.indexWhere((e) => e['fieldid'] == fieldId);
    if (idx < 0) return;
    _cardFullList[idx]['show'] = 0;
    // 同步更新显示列表
    _rebuildShowList();
    _cardSave();
  }

  /// 从 _cardFullList 重建 _cardList（仅 show==1 的卡片）
  void _rebuildShowList() {
    setState(() {
      _cardList = _cardFullList.where((e) => e['show'] == 1).toList()
        ..sort((a, b) => (a['isort'] as int?)?.compareTo(b['isort'] as int? ?? 0) ?? 0);
    });
  }

  /// 保存卡片配置到服务端
  void _cardSave() {
    if (_cardFullList.isEmpty) return;
    final list = List<Map<String, dynamic>>.from(_cardFullList);
    int showCount = 0;
    for (int i = 0; i < list.length; i++) {
      list[i]['isort'] = i + 1;
      list[i]['datatype'] = 4;
      if (list[i]['show'] == 1) showCount++;
    }

    request(HttpApi.homeSaveHomeCard, [
      {
        'clienttype': 'WEBAPP',
        'datatype': 4,
        'getHomeCardDetailList': list,
        'maxshowcount': showCount,
      }
    ]).then((_) {
      _fetchAllData(); // 刷新首页
    }).catchError((_) {
      _fetchAllData();
    });
  }

  /// 打开卡片设置页，返回后自动刷新数据
  Future<void> _openCardSetting() async {
    final needRefresh = await Navigator.of(context).pushNamed(Routes.cardSetting);
    if (needRefresh == true) _fetchAllData();
  }

  /// 获取库存不足提醒
  void _fetchStockTips() {
    request(HttpApi.getIndexTipTotal, {}).then((res) {
      if (!mounted) return;
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        final list = (data['tiplist'] as List?)
                ?.map((e) => e['title']?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .toList() ??
            [];
        setState(() => _stockTips = list);
      }
    }).catchError((_) {});
  }

  /// 检查单据审批提醒
  void _checkApproval() {
    ApprovalReminderHelper.checkAndShow(context);
  }

  // ─────────────────────────────────────────────────────────
  // 格式化数字
  // ─────────────────────────────────────────────────────────
  String _fmt(dynamic val) {
    if (val == null) return '0.00';
    final d = double.tryParse(val.toString());
    if (d == null) return val.toString();
    return d.toStringAsFixed(2);
  }

  String _fmtRate(dynamic val) {
    if (val == null) return '0.00%';
    final d = double.tryParse(val.toString());
    if (d == null) return '0.00%';
    final prefix = d > 0 ? '+' : '';
    return '$prefix${d.toStringAsFixed(2)}%';
  }

  Color _rateColor(dynamic val) {
    final d = double.tryParse(val?.toString() ?? '0') ?? 0;
    if (d > 0) return const Color(0xFFFF4444);
    if (d < 0) return const Color(0xFF00C936);
    return const Color(0xFF9CA3AF);
  }

  String get _dayTypeName {
    const map = {'1': '日', '2': '日', '3': '周', '4': '月', '5': '月'};
    return map[_timeTabs[_timeIdx].daytype] ?? '日';
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // 权限检查中 → 显示加载态
    if (_isCheckingPermission) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 始终渲染正常首页内容，无权限时叠加半透明遮罩
    final homeBody = Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Stack(children: [
        // 蓝色渐变背景（延伸到时间筛选下方）
        Container(
          height: 300,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF49A4FF), Color(0xFF3764FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            _buildHeader(),
            _buildTimeFilter(),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(children: [
                RefreshIndicator(
                  onRefresh: () async => _fetchAllData(),
                  child: ListView(
                    cacheExtent: 800,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      // 营业数据始终第一位（yysj）
                      RepaintBoundary(
                          child: _CoreDataCard(
                        overview: _overview,
                        fmt: _fmt,
                        fmtRate: _fmtRate,
                        rateColor: _rateColor,
                        isWholesale: _dataBtn == 1,
                        myType: _myType,
                        onMyTypeChanged: (v) => setState(() => _myType = v),
                      )),
                      // 库存不足提醒条（对齐 Vue stock-notice）
                      if (_stockTips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        StockNoticeBar(tips: _stockTips),
                      ],
                      // 其余卡片按 _cardList 顺序动态渲染（对齐 Vue v-for cardList）
                      for (final card in _cardList)
                        if (card['fieldid'] != 'yysj' && card['fieldid'] != 'yjxx') ...[
                          const SizedBox(height: 12),
                          _buildCardWidget(card),
                        ],
                      // 数据卡片设置入口（对齐 Vue index.vue 106-111）
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _openCardSetting,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF3FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.settings, size: 16, color: Color(0xFF333333)),
                              SizedBox(width: 8),
                              Text(
                                '数据卡片设置',
                                style: TextStyle(fontSize: 14, color: Color(0xFF333333)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 加载指示（无蒙层，仅居中图标，不遮挡首页内容）
                if (_loading)
                  const Positioned.fill(
                    child: Center(
                      child: SizedBox(
                          width: 36,
                          height: 36,
                          child:
                              CircularProgressIndicator(color: Color(0xFF006EFF), strokeWidth: 3)),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ]),
    );

    // 无权限时在首页内容之上叠加半透明蒙层
    if (!_hasPermission) {
      return Stack(
        children: [
          homeBody,
          _buildNoPermissionOverlay(),
        ],
      );
    }

    return homeBody;
  }

  /// 根据 fieldId 构建对应卡片组件（对齐 Vue v-if/else-if）
  Widget _buildCardWidget(Map<String, dynamic> card) {
    final fid = card['fieldid']?.toString() ?? '';
    Widget child;
    switch (fid) {
      case 'fkfs':
        child = PaymentCard(
          payList: _payList,
          fmt: _fmt,
          onCardPin: () => _cardPin('fkfs'),
          onCardHide: () => _cardHide('fkfs'),
          onCardManage: _openCardSetting,
        );
        break;
      case 'qs':
        child = SizedBox(
          height: 280,
          child: TrendCard(
            trendList: _trendList,
            daytype: _timeTabs[_timeIdx].daytype,
            trendType: _trendType,
            onTrendTypeChanged: (type) => setState(() => _trendType = type),
            onCardPin: () => _cardPin('qs'),
            onCardHide: () => _cardHide('qs'),
            onCardManage: _openCardSetting,
          ),
        );
        break;
      case 'xsb':
        child = SaleRankCard(
          rankList: _saleRankList,
          rankType: _saleRankType,
          rankSort: _saleRankSort,
          fmt: _fmt,
          onRankTypeChanged: (String v) => setState(() {
            _saleRankType = v;
            _fetchSaleRank();
          }),
          onRankSortChanged: (int v) => setState(() {
            _saleRankSort = v;
            _fetchSaleRank();
          }),
          onCardPin: () => _cardPin('xsb'),
          onCardHide: () => _cardHide('xsb'),
          onCardManage: _openCardSetting,
        );
        break;
      default:
        child = const SizedBox.shrink();
    }
    return RepaintBoundary(child: child);
  }

  // ── 顶部 Header ──────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          // 机构名称最大宽度 50%，溢出省略（避免挤占右侧零售/批发 tab）
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.5,
            child: GestureDetector(
              onTap: _selectStore,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                ],
              ),
            ),
          ),
          const Spacer(),
          // 零售/批发 切换
          _buildDataBtn(0, '零售'),
          _buildDataBtn(1, '批发'),
        ],
      ),
    );
  }

  Widget _buildDataBtn(int index, String label) {
    final active = _dataBtn == index;
    return GestureDetector(
      onTap: () {
        if (_dataBtn == index) return;
        setState(() => _dataBtn = index);
        // 操作审计：切换零售/批发
        FileLogWriter.instance.writeOperationLog('首页', '切换数据维度', label);
        _fetchAllData();
      },
      child: Container(
        width: 56,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: active ? 1.0 : 0.5),
            fontSize: 15,
            fontWeight: active ? FontWeight.w600 : FontWeight.w300,
          ),
        ),
      ),
    );
  }

  // ── 时间筛选条 ──────────────────────────────────────────────
  Widget _buildTimeFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: List.generate(_timeTabs.length, (i) {
            final selected = _timeIdx == i;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_timeIdx == i) return;
                  setState(() => _timeIdx = i);
                  // 操作审计：切换时间维度
                  FileLogWriter.instance.writeOperationLog('首页', '切换时间', _timeTabs[i].label);
                  _fetchAllData();
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _timeTabs[i].label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color:
                          selected ? const Color(0xFF006EFF) : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// 无权限半透明蒙层 —— 叠加在首页内容之上（对齐 boss hideHomeBoo 遮罩）
  Widget _buildNoPermissionOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withOpacity(0.5),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 80,
              color: Colors.white70,
            ),
            SizedBox(height: 24),
            Text(
              '当前账号功能被限制',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '请联系管理员!',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  时间 Tab 数据模型
// ═══════════════════════════════════════════════════════════
class _TimeTab {
  const _TimeTab(this.label, this.daytype);
  final String label;
  final String daytype;
}

// ═══════════════════════════════════════════════════════════
//  核心数据卡片（蓝色渐变 — 实销金额 + 会员充值）
// ═══════════════════════════════════════════════════════════
class _CoreDataCard extends StatelessWidget {
  const _CoreDataCard({
    required this.overview,
    required this.fmt,
    required this.fmtRate,
    required this.rateColor,
    required this.isWholesale,
    required this.myType,
    required this.onMyTypeChanged,
  });
  final Map<String, dynamic> overview;
  final String Function(dynamic) fmt;
  final String Function(dynamic) fmtRate;
  final Color Function(dynamic) rateColor;
  final bool isWholesale;
  final String myType;
  final ValueChanged<String> onMyTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // 蓝色渐变卡片
      Container(
        height: 100,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: isWholesale
            ? Center(
                child: _CoreColumn(
                  value: fmt(overview['saleAmount']),
                  label: '销售金额',
                  rate: fmtRate(overview['saleAmountRate']),
                  rateColor: rateColor(overview['saleAmountRate']),
                  showArrow: true,
                  arrowOffsetX: -40,
                ),
              )
            : IntrinsicHeight(
                child: Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onMyTypeChanged('0'),
                      child: _CoreColumn(
                        value: fmt(overview['rramt']),
                        label: '实销金额',
                        rate: fmtRate(overview['rramtrate']),
                        rateColor: rateColor(overview['rramtrate']),
                        showArrow: myType == '0',
                      ),
                    ),
                  ),
                  Container(width: 1, height: 35, color: Colors.white),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onMyTypeChanged('1'),
                      child: _CoreColumn(
                        value: fmt(overview['vipaddamt']),
                        label: '会员充值',
                        rate: fmtRate(overview['vipaddamtrate']),
                        rateColor: rateColor(overview['vipaddamtrate']),
                        showArrow: myType == '1',
                      ),
                    ),
                  ),
                ]),
              ),
      ),
      // 白色二级卡片
      SecondaryDataCard(
        overview: overview,
        dayTypeName: '',
        fmt: fmt,
        fmtRate: fmtRate,
        rateColor: rateColor,
        isWholesale: isWholesale,
        myType: myType,
      ),
    ]);
  }
}

class _CoreColumn extends StatelessWidget {
  const _CoreColumn({
    required this.value,
    required this.label,
    required this.rate,
    required this.rateColor,
    this.showArrow = false,
    this.arrowOffsetX = -4,
  });
  final String value;
  final String label;
  final String rate;
  final Color rateColor;
  final bool showArrow;
  final double arrowOffsetX;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (showArrow)
          Positioned(
            left: 0,
            right: 0,
            bottom: -95,
            child: Center(
              child: Transform.translate(
                offset: Offset(arrowOffsetX, 0),
                child: const Icon(Icons.arrow_drop_up, size: 130, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

/// 趋势卡片占位符，首帧渲染时替代图表，避免卡顿
class _TrendPlaceholder extends StatelessWidget {
  const _TrendPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '营业趋势',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FC),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Color(0xFFD0D0D0),
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
