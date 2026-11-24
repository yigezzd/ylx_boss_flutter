import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/system/management/sys_seat_edit_dialog.dart';
import 'package:flutter_deer/pages/system/management/sys_seat_widgets.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/vas_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 授权管理（对齐 boss sysseat/index.vue 三个 Tab）
///
/// 1. 收银站点授权：/machine/getMachineSeatList，行内操作 绑定/解绑收银机
/// 2. 收银机列表：/machine/getMachineList，行内操作 上传日志/启用/删除/编辑
/// 3. 移动管店授权：/sysseat/findList，行内操作 绑定/解绑、启用/停用
class SysSeatListPage extends StatefulWidget {
  const SysSeatListPage({super.key});

  @override
  State<SysSeatListPage> createState() => _SysSeatListPageState();
}

class _SysSeatListPageState extends State<SysSeatListPage> with SingleTickerProviderStateMixin {
  static const int _pageSize = 20;
  static const Color _primary = Color(0xFF006EFF);
  static const Duration _debounceDuration = Duration(milliseconds: 500);

  /// 绑定收银机弹窗列表项字段卡片（对齐 Vue bindMachineFields）
  static const List<Map<String, String>> _bindMachineFields = [
    {'label': '机号', 'key': 'code'},
    {'label': '设备名称', 'key': 'name'},
    {'label': '归属机构', 'key': 'storeName'},
    {'label': '设备类型', 'key': 'clientTypeName'},
  ];

  late final TabController _tabController;
  int _tabIndex = 0;

  // ---- 权限（页面生命周期内不变）----
  bool _canBind = false; // 014701
  bool _canOperate = false; // 014702

  // ---- 收银站点授权 ----
  final TextEditingController _siteSearchCtl = TextEditingController();
  final ScrollController _siteScrollCtl = ScrollController();
  List<Map<String, dynamic>> _siteList = [];
  Map<String, dynamic> _siteSum = {};
  bool _siteLoading = false;
  bool _siteHasMore = true;
  int _sitePage = 1;
  int _siteReqId = 0; // 请求序号：丢弃过期响应，避免旧筛选结果覆盖新结果
  List<int> _siteSids = [];
  String _siteSidsname = '';
  String _siteSeatstatus = '';
  String _siteClienttype = '';
  Timer? _siteDebounce;

  // ---- 收银机列表 ----
  final TextEditingController _machineSearchCtl = TextEditingController();
  final ScrollController _machineScrollCtl = ScrollController();
  List<Map<String, dynamic>> _machineList = [];
  Map<String, dynamic> _machineSum = {};
  bool _machineLoading = false;
  bool _machineHasMore = true;
  int _machinePage = 1;
  int _machineReqId = 0;
  List<int> _machineSids = [];
  String _machineSidsname = '';
  String _machineStopflag = '';
  String _machineClienttype = '';
  Timer? _machineDebounce;

  // ---- 移动管店授权 ----
  final TextEditingController _seatSearchCtl = TextEditingController();
  final ScrollController _seatScrollCtl = ScrollController();
  List<Map<String, dynamic>> _seatList = [];
  Map<String, dynamic> _seatSum = {};
  bool _seatLoading = false;
  bool _seatHasMore = true;
  int _seatPage = 1;
  int _seatReqId = 0;
  List<int>? _seatSids; // 未选机构时为 null（对齐 Vue queryD.sids = null）
  String _seatSidsname = '';
  String _seatStatus = '';
  Timer? _seatDebounce;

  // ---- 试用期 / 席位版本 ----
  bool _storeTrial = false;
  String _storeValidDate = '';
  bool _seatTrial = false;
  bool _seatNotOpen = false;
  String _seatExpireDate = '';

  @override
  void initState() {
    super.initState();
    _canBind = PermissionUtils.checkPermission('014701', showTip: false);
    _canOperate = PermissionUtils.checkPermission('014702', showTip: false);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        return;
      }
      final int index = _tabController.index;
      // 点击/滑动切 Tab 时动画结束会多次回调，仅在索引真正变化时刷新
      if (index == _tabIndex) {
        return;
      }
      setState(() => _tabIndex = index);
      _loadCurrentTab();
    });
    _bindScrollPagination();
    _readVersionFlags();
    // 对齐 Vue onShow：刷新增值服务后重算席位试用/未开通状态
    VasUtils.fetchVasList().then((_) {
      if (!mounted) {
        return;
      }
      setState(_readVersionFlags);
    });
    _loadCurrentTab();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _siteDebounce?.cancel();
    _machineDebounce?.cancel();
    _seatDebounce?.cancel();
    _siteSearchCtl.dispose();
    _machineSearchCtl.dispose();
    _seatSearchCtl.dispose();
    _siteScrollCtl.dispose();
    _machineScrollCtl.dispose();
    _seatScrollCtl.dispose();
    super.dispose();
  }

  void _bindScrollPagination() {
    _siteScrollCtl.addListener(() {
      if (_siteScrollCtl.position.pixels >= _siteScrollCtl.position.maxScrollExtent - 60 &&
          !_siteLoading &&
          _siteHasMore) {
        _sitePage++;
        _loadSite(reset: false);
      }
    });
    _machineScrollCtl.addListener(() {
      if (_machineScrollCtl.position.pixels >= _machineScrollCtl.position.maxScrollExtent - 60 &&
          !_machineLoading &&
          _machineHasMore) {
        _machinePage++;
        _loadMachine(reset: false);
      }
    });
    _seatScrollCtl.addListener(() {
      if (_seatScrollCtl.position.pixels >= _seatScrollCtl.position.maxScrollExtent - 60 &&
          !_seatLoading &&
          _seatHasMore) {
        _seatPage++;
        _loadSeat(reset: false);
      }
    });
  }

  void _loadCurrentTab() {
    if (_tabIndex == 0) {
      _loadSite();
    } else if (_tabIndex == 1) {
      _loadMachine();
    } else {
      _loadSeat();
    }
  }

  /// 读取登录机构/席位的试用信息（对齐 Vue siteTrialFlag / seatTrialFlag / seatNotOpenFlag）
  void _readVersionFlags() {
    _storeTrial = false;
    _storeValidDate = '';
    try {
      final String allStr = SpUtil.getString(Constant.allLoginData) ?? '';
      if (allStr.isNotEmpty) {
        final dynamic decoded = json.decode(allStr);
        if (decoded is Map && decoded['store'] is Map) {
          final Map<String, dynamic> store = Map<String, dynamic>.from(decoded['store'] as Map);
          final num? vertype = num.tryParse(store['vertype']?.toString() ?? '');
          _storeTrial = vertype == 0;
          final String vt = store['validtime']?.toString() ?? '';
          _storeValidDate = vt.contains(' ') ? vt.split(' ').first : vt;
        }
      }
    } catch (_) {}

    final Map<String, dynamic> seat = VasUtils.getSeatInfo();
    final num? seatType = num.tryParse(seat['vertype']?.toString() ?? '');
    _seatNotOpen = seatType == -1;
    final DateTime? expireAt = VasUtils.parseExpireTime(seat['expiretime']);
    _seatExpireDate = seat['expiretime'] == null ? '' : VasUtils.formatExpireDate(seat);
    if (seatType == 0 && expireAt != null) {
      // 对齐 Vue：DayJs(expire).startOf('day').isAfter(DayJs())
      final DateTime expireDay = DateTime(expireAt.year, expireAt.month, expireAt.day);
      _seatTrial = expireDay.isAfter(DateTime.now());
    } else {
      _seatTrial = false;
    }
  }

  // ==================== 数据加载 ====================

  Future<void> _loadSite({bool reset = true}) async {
    // 分页不允许并发；刷新/搜索（reset）允许打断在途请求
    if (!reset && _siteLoading) {
      return;
    }
    if (reset) {
      _sitePage = 1;
      _siteHasMore = true;
    }
    final int reqId = ++_siteReqId;
    setState(() => _siteLoading = true);
    try {
      final res = await request(HttpApi.machineGetMachineSeatList, {
        'cond': _siteSearchCtl.text.trim(),
        'valiflag': '1',
        'clienttype': _siteClienttype,
        'seatstatus': _siteSeatstatus,
        'pagesize': _pageSize,
        'page': _sitePage,
        'sids': _siteSids,
        'storeid': '',
        'sidsname': _siteSidsname,
        'stopflag': '',
      });
      if (!mounted || reqId != _siteReqId) {
        return;
      }
      final data = res['data'];
      final rows = _parseRows(data);
      setState(() {
        _siteSum = _parseSum(data);
        if (_sitePage == 1) {
          _siteList = rows;
        } else {
          _siteList.addAll(rows);
        }
        _siteHasMore = rows.length >= _pageSize;
      });
    } catch (_) {
      if (mounted && reqId == _siteReqId) {
        setState(() => _siteHasMore = false);
      }
    } finally {
      if (mounted && reqId == _siteReqId) {
        setState(() => _siteLoading = false);
      }
    }
  }

  Future<void> _loadMachine({bool reset = true}) async {
    if (!reset && _machineLoading) {
      return;
    }
    if (reset) {
      _machinePage = 1;
      _machineHasMore = true;
    }
    final int reqId = ++_machineReqId;
    setState(() => _machineLoading = true);
    try {
      final res = await request(HttpApi.machineGetList, {
        'cond': _machineSearchCtl.text.trim(),
        'valiflag': '1',
        'clienttype': _machineClienttype,
        'pagesize': _pageSize,
        'page': _machinePage,
        'sids': _machineSids,
        'storeid': '',
        'sidsname': _machineSidsname,
        'stopflag': _machineStopflag,
      });
      if (!mounted || reqId != _machineReqId) {
        return;
      }
      final data = res['data'];
      final rows = _parseRows(data);
      setState(() {
        _machineSum = _parseSum(data);
        if (_machinePage == 1) {
          _machineList = rows;
        } else {
          _machineList.addAll(rows);
        }
        _machineHasMore = rows.length >= _pageSize;
      });
    } catch (_) {
      if (mounted && reqId == _machineReqId) {
        setState(() => _machineHasMore = false);
      }
    } finally {
      if (mounted && reqId == _machineReqId) {
        setState(() => _machineLoading = false);
      }
    }
  }

  Future<void> _loadSeat({bool reset = true}) async {
    if (!reset && _seatLoading) {
      return;
    }
    if (reset) {
      _seatPage = 1;
      _seatHasMore = true;
    }
    final int reqId = ++_seatReqId;
    setState(() => _seatLoading = true);
    try {
      final res = await request(HttpApi.sysSeatFindList, {
        'cond': _seatSearchCtl.text.trim(),
        'clienttype': '',
        'pagesize': _pageSize,
        'page': _seatPage,
        'sids': _seatSids,
        'sidsname': _seatSidsname,
        'is_page': 1,
        'authflag': '',
      });
      if (!mounted || reqId != _seatReqId) {
        return;
      }
      final data = res['data'];
      final rows = _parseRows(data);
      setState(() {
        _seatSum = _parseSum(data);
        if (_seatPage == 1) {
          _seatList = rows;
        } else {
          _seatList.addAll(rows);
        }
        _seatHasMore = rows.length >= _pageSize;
      });
    } catch (_) {
      if (mounted && reqId == _seatReqId) {
        setState(() => _seatHasMore = false);
      }
    } finally {
      if (mounted && reqId == _seatReqId) {
        setState(() => _seatLoading = false);
      }
    }
  }

  static List<Map<String, dynamic>> _parseRows(dynamic data) {
    if (data is! Map) {
      return <Map<String, dynamic>>[];
    }
    final List<dynamic>? list = data['list'] as List<dynamic>?;
    if (list == null) {
      return <Map<String, dynamic>>[];
    }
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Map<String, dynamic> _parseSum(dynamic data) {
    if (data is! Map) {
      return <String, dynamic>{};
    }
    final dynamic sum = data['sumdata'];
    return sum is Map ? Map<String, dynamic>.from(sum) : <String, dynamic>{};
  }

  // ==================== 机构选择 ====================

  Future<void> _selectSiteStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId:
          _siteSids.isNotEmpty && _siteSids.first > 0 ? _siteSids.first.toString() : '',
    );
    if (result == null || !mounted) {
      return;
    }
    final int id = int.tryParse(result['storeid']?.toString() ?? '') ?? 0;
    setState(() {
      _siteSids = id > 0 ? [id] : [];
      _siteSidsname = id > 0 ? (result['storename']?.toString() ?? '') : '';
    });
    _loadSite();
  }

  Future<void> _selectMachineStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId:
          _machineSids.isNotEmpty && _machineSids.first > 0 ? _machineSids.first.toString() : '',
    );
    if (result == null || !mounted) {
      return;
    }
    final int id = int.tryParse(result['storeid']?.toString() ?? '') ?? 0;
    setState(() {
      _machineSids = id > 0 ? [id] : [];
      _machineSidsname = id > 0 ? (result['storename']?.toString() ?? '') : '';
    });
    _loadMachine();
  }

  Future<void> _selectSeatStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: (_seatSids != null && _seatSids!.isNotEmpty && _seatSids!.first > 0)
          ? _seatSids!.first.toString()
          : '',
    );
    if (result == null || !mounted) {
      return;
    }
    final int id = int.tryParse(result['storeid']?.toString() ?? '') ?? 0;
    setState(() {
      _seatSids = id > 0 ? [id] : null;
      _seatSidsname = id > 0 ? (result['storename']?.toString() ?? '') : '';
    });
    _loadSeat();
  }

  // ==================== 站点授权操作 ====================

  Future<void> _bindSite(Map<String, dynamic> row) async {
    final machine = await CommonSelectSheet.show(
      context,
      title: '选择收银机',
      searchHint: '收银机号/设备名称',
      nameField: 'code',
      idField: 'code',
      itemFields: _bindMachineFields,
      fetchData: (searchText, page) => request(HttpApi.machineGetList, {
        // 对齐 Vue selectCom：is_page + 登录机构 sid/spid（request 已自动注入） + mergData(seatnullflag/valiflag)
        'is_page': 1,
        'cond': searchText,
        'page': page,
        'pagesize': _pageSize,
        'seatnullflag': 1,
        'valiflag': 1,
      }).then((res) {
        final data = res['data'];
        return data is Map ? Map<String, dynamic>.from(data) : null;
      }),
    );
    if (machine == null || !mounted) {
      return;
    }
    try {
      await request(HttpApi.machineBindMachineSeat, {
        ...row,
        'machinecode': machine['code'],
      });
      if (!mounted) {
        return;
      }
      Toast.show('绑定成功');
      _loadSite();
    } catch (_) {
      // 失败提示由 http_helper 统一处理
    }
  }

  Future<void> _unbindSite(Map<String, dynamic> row) async {
    final bool confirmed = await _confirm('确认解绑该站点的收银机吗？');
    if (!confirmed) {
      return;
    }
    try {
      await request(HttpApi.machineUnbindMachineSeat, row);
      if (!mounted) {
        return;
      }
      Toast.show('解绑成功');
      _loadSite();
    } catch (_) {}
  }

  // ==================== 收银机操作 ====================

  static const Map<int, String> _machineActionNames = {
    1: '启用',
    2: '停用',
    3: '删除',
    4: '上传日志',
  };

  Future<void> _machineOperate(Map<String, dynamic> row, int type) async {
    final String action = _machineActionNames[type] ?? '操作';
    final String content = type == 4 ? '确认上传该收银机的日志吗？' : '确认$action该收银机吗？';
    final bool confirmed = await _confirm(content);
    if (!confirmed) {
      return;
    }
    final dynamic rawId = row['id'] ?? row['machineid'] ?? row['mid'];
    final List<dynamic> ids =
        rawId != null && rawId.toString().isNotEmpty ? <dynamic>[rawId] : <dynamic>[];
    try {
      await request(HttpApi.machineOperate, {'operateType': type, 'ids': ids});
      if (!mounted) {
        return;
      }
      Toast.show('$action成功');
      _loadMachine();
    } catch (_) {}
  }

  Future<void> _editMachine(Map<String, dynamic> item) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SysSeatEditDialog(item: item),
    );
    if ((saved ?? false) && mounted) {
      Toast.show('保存成功');
      if (_tabIndex == 0) {
        _loadSite();
      } else {
        _loadMachine();
      }
    }
  }

  // ==================== 移动管店授权操作 ====================

  Future<void> _bindSeatUser(Map<String, dynamic> row) async {
    final user = await CommonSelectSheet.show(
      context,
      title: '选择员工',
      searchHint: '输入员工名称/编码',
      idField: 'userid',
      fetchData: (searchText, page) => request(HttpApi.sysUserList, {
        // 对齐 Vue selectCom：is_page + 登录机构 sid/spid（request 已自动注入） + cond
        'is_page': 1,
        'cond': searchText,
        'page': page,
        'pagesize': _pageSize,
      }).then((res) {
        final data = res['data'];
        return data is Map ? Map<String, dynamic>.from(data) : null;
      }),
    );
    if (user == null || !mounted) {
      return;
    }
    try {
      await request(HttpApi.sysSeatBindSeat, {
        ...row,
        'username': user['name'],
        'usercode': user['code'],
        'userid': user['userid'],
      });
      if (!mounted) {
        return;
      }
      Toast.show('绑定成功');
      _loadSeat();
    } catch (_) {}
  }

  Future<void> _unbindSeatUser(Map<String, dynamic> row) async {
    final String userName = row['username']?.toString() ?? '';
    final String content = userName.isEmpty ? '确认解绑该用户吗？' : '确认解绑$userName吗？';
    final bool confirmed = await _confirm(content);
    if (!confirmed) {
      return;
    }
    try {
      await request(HttpApi.sysSeatUnbindSeat, row);
      if (!mounted) {
        return;
      }
      // 对齐 Vue：先提示，延后 800ms 再刷新，避免刷新链路把提示顶掉
      Toast.show('解绑成功');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _loadSeat();
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleSeatStatus(Map<String, dynamic> row, bool enable) async {
    final String action = enable ? '启用' : '停用';
    // 对齐 Vue：已过期的席位（seatstatus == 3）不支持启用/停用
    if (row['seatstatus']?.toString() == '3') {
      Toast.show('已过期的席位，不支持$action操作');
      return;
    }
    final bool confirmed = await _confirm('确认$action选中项吗？');
    if (!confirmed) {
      return;
    }
    try {
      await request(HttpApi.sysSeatUpdateStop, [
        {...row, 'stopflag': enable ? 0 : 1}
      ]);
      if (!mounted) {
        return;
      }
      Toast.show('$action成功');
      _loadSeat();
    } catch (_) {}
  }

  // ==================== 通用 ====================

  Future<bool> _confirm(String content) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    return ok ?? false;
  }

  void _onSiteSearchInput() {
    _siteDebounce?.cancel();
    _siteDebounce = Timer(_debounceDuration, () {
      if (mounted) {
        _loadSite();
      }
    });
  }

  void _onMachineSearchInput() {
    _machineDebounce?.cancel();
    _machineDebounce = Timer(_debounceDuration, () {
      if (mounted) {
        _loadMachine();
      }
    });
  }

  void _onSeatSearchInput() {
    _seatDebounce?.cancel();
    _seatDebounce = Timer(_debounceDuration, () {
      if (mounted) {
        _loadSeat();
      }
    });
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('授权管理', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0.5,
      ),
      body: Column(
        children: [
          ColoredBox(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: _primary,
              unselectedLabelColor: const Color(0xFF666666),
              indicatorColor: _primary,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const [
                Tab(text: '收银站点授权'),
                Tab(text: '收银机列表'),
                Tab(text: '移动管店授权'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildSiteTab(), _buildMachineTab(), _buildSeatTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 收银站点授权 ----------
  Widget _buildSiteTab() {
    return RefreshIndicator(
      onRefresh: () => _loadSite(),
      child: ListView.builder(
        controller: _siteScrollCtl,
        cacheExtent: 800,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _siteList.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSiteHeader();
          }
          final int dataIndex = index - 1;
          if (dataIndex >= _siteList.length) {
            return _buildFooter(
                loading: _siteLoading, hasMore: _siteHasMore, isEmpty: _siteList.isEmpty);
          }
          final item = _siteList[dataIndex];
          return RepaintBoundary(
            child: SiteSeatCard(
              item: item,
              canBind: _canBind,
              onBind: () => _bindSite(item),
              onUnbind: () => _unbindSite(item),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSiteHeader() {
    return Column(
      children: [
        _buildSearchBar(_siteSearchCtl, '请输入设备号/名称', () => _loadSite(),
            onChanged: _onSiteSearchInput),
        _buildFilterRow([
          _buildDropdown(_siteSidsname.isNotEmpty ? _siteSidsname : '全部机构', _selectSiteStore),
          _buildDropdown(
              _siteStatusLabel(),
              () => _showSheet(
                  title: '选择状态',
                  options: const {'全部状态': '', '空闲': '0', '使用中': '1', '停用': '2', '已过期': '3'},
                  currentValue: _siteSeatstatus,
                  onSelect: (v) {
                    _siteSeatstatus = v;
                    _loadSite();
                  })),
          _buildDropdown(
              _clientTypeLabel(_siteClienttype),
              () => _showSheet(
                  title: '选择类型',
                  options: const {
                    '全部类型': '',
                    'PC收银端': 'PC',
                    '安卓收银端': 'APPSALE',
                    '移动终端': 'APP',
                    '自助终端': 'SSC',
                  },
                  currentValue: _siteClienttype,
                  onSelect: (v) {
                    _siteClienttype = v;
                    _loadSite();
                  })),
        ]),
        _buildStoreSumBar(_siteSum, '收银站点'),
      ],
    );
  }

  String _siteStatusLabel() {
    switch (_siteSeatstatus) {
      case '0':
        return '空闲';
      case '1':
        return '使用中';
      case '2':
        return '停用';
      case '3':
        return '已过期';
      default:
        return '全部状态';
    }
  }

  static String _clientTypeLabel(String value) {
    switch (value) {
      case 'PC':
        return 'PC收银端';
      case 'APPSALE':
        return '安卓收银端';
      case 'APP':
        return '移动终端';
      case 'SSC':
        return '自助终端';
      default:
        return '全部类型';
    }
  }

  // ---------- 收银机列表 ----------
  Widget _buildMachineTab() {
    return RefreshIndicator(
      onRefresh: () => _loadMachine(),
      child: ListView.builder(
        controller: _machineScrollCtl,
        cacheExtent: 800,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _machineList.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildMachineHeader();
          }
          final int dataIndex = index - 1;
          if (dataIndex >= _machineList.length) {
            return _buildFooter(
                loading: _machineLoading, hasMore: _machineHasMore, isEmpty: _machineList.isEmpty);
          }
          final item = _machineList[dataIndex];
          return RepaintBoundary(
            child: MachineCard(
              item: item,
              canOperate: _canOperate,
              canManage: _canBind,
              onUploadLog: () => _machineOperate(item, 4),
              onEnable: () => _machineOperate(item, 1),
              onDelete: () => _machineOperate(item, 3),
              onEdit: () => _editMachine(item),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMachineHeader() {
    return Column(
      children: [
        _buildSearchBar(_machineSearchCtl, '请输入设备号/名称', () => _loadMachine(),
            onChanged: _onMachineSearchInput),
        _buildFilterRow([
          _buildDropdown(
              _machineSidsname.isNotEmpty ? _machineSidsname : '全部机构', _selectMachineStore),
          _buildDropdown(
              _machineStopflag == '0' ? '启用' : (_machineStopflag == '1' ? '停用' : '全部状态'),
              () => _showSheet(
                  title: '选择状态',
                  options: const {'全部状态': '', '启用': '0', '停用': '1'},
                  currentValue: _machineStopflag,
                  onSelect: (v) {
                    _machineStopflag = v;
                    _loadMachine();
                  })),
          _buildDropdown(
              _clientTypeLabel(_machineClienttype),
              () => _showSheet(
                  title: '选择类型',
                  options: const {
                    '全部类型': '',
                    'PC收银端': 'PC',
                    '安卓收银端': 'APPSALE',
                    '移动终端': 'APP',
                    '自助终端': 'SSC',
                  },
                  currentValue: _machineClienttype,
                  onSelect: (v) {
                    _machineClienttype = v;
                    _loadMachine();
                  })),
        ]),
        _buildStoreSumBar(_machineSum, '收银站点'),
      ],
    );
  }

  // ---------- 移动管店授权 ----------
  Widget _buildSeatTab() {
    return RefreshIndicator(
      onRefresh: () => _loadSeat(),
      child: ListView.builder(
        controller: _seatScrollCtl,
        cacheExtent: 800,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _seatList.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSeatHeader();
          }
          final int dataIndex = index - 1;
          if (dataIndex >= _seatList.length) {
            return _buildFooter(
                loading: _seatLoading, hasMore: _seatHasMore, isEmpty: _seatList.isEmpty);
          }
          final item = _seatList[dataIndex];
          return RepaintBoundary(
            child: ShopSeatCard(
              item: item,
              canBind: _canBind,
              canOperate: _canOperate,
              onBind: () => _bindSeatUser(item),
              onUnbind: () => _unbindSeatUser(item),
              onEnable: () => _toggleSeatStatus(item, true),
              onDisable: () => _toggleSeatStatus(item, false),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSeatHeader() {
    return Column(
      children: [
        _buildSearchBar(_seatSearchCtl, '请输入用户名/工号/席位号', () => _loadSeat(),
            onChanged: _onSeatSearchInput),
        _buildFilterRow([
          _buildDropdown(_seatSidsname.isNotEmpty ? _seatSidsname : '全部门店', _selectSeatStore),
          _buildDropdown(
              _seatStatusLabel(),
              () => _showSheet(
                  title: '选择状态',
                  options: const {'不限': '', '空闲': '0', '使用中': '1', '停用': '2', '已过期': '3'},
                  currentValue: _seatStatus,
                  onSelect: (v) {
                    _seatStatus = v;
                    _loadSeat();
                  })),
        ]),
        _buildSeatSumBar(),
      ],
    );
  }

  String _seatStatusLabel() {
    switch (_seatStatus) {
      case '0':
        return '空闲';
      case '1':
        return '使用中';
      case '2':
        return '停用';
      case '3':
        return '已过期';
      default:
        return '不限';
    }
  }

  // ---------- 汇总栏 ----------
  Widget _buildStoreSumBar(Map<String, dynamic> sum, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: _storeTrial
          ? Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: _primary)),
                Text(' 试用$_storeValidDate 到期，',
                    style: const TextStyle(fontSize: 13, color: Color(0xFFFF0000))),
                const Flexible(
                  child:
                      Text('试用期内，站点不设限制', style: TextStyle(fontSize: 13, color: Color(0xFF333333))),
                ),
              ],
            )
          : Text(
              '当前机构已购总量:${sum['storeMaxCount'] ?? 0}  已授权:${sum['storeCount'] ?? 0}  剩余可用:${sum['storeHaveCount'] ?? 0}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
            ),
    );
  }

  Widget _buildSeatSumBar() {
    if (_seatTrial) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          children: [
            const Text('管店席位',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primary)),
            Text(' 试用$_seatExpireDate 到期，',
                style: const TextStyle(fontSize: 13, color: Color(0xFFFF0000))),
            const Flexible(
              child: Text('试用期内，席位不设限制', style: TextStyle(fontSize: 13, color: Color(0xFF333333))),
            ),
          ],
        ),
      );
    }
    if (_seatNotOpen) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          children: [
            Text('管店席位',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primary)),
            SizedBox(width: 8),
            Flexible(
              child: Text('暂未开通灵犀管店-专业版', style: TextStyle(fontSize: 13, color: Color(0xFFFF0000))),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Text(
        '当前机构已购总量:${_seatSum['userMaxCount'] ?? 0}  占用:${_seatSum['userCount'] ?? 0}  空闲:${_seatSum['userHaveCount'] ?? 0}',
        style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
      ),
    );
  }

  // ---------- 列表 Footer ----------
  Widget _buildFooter({required bool loading, required bool hasMore, required bool isEmpty}) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (isEmpty) {
      return const SeatEmptyPlaceholder();
    }
    if (!hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('没有更多数据', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ),
      );
    }
    return const SizedBox(height: 20);
  }

  // ---------- 通用组件 ----------
  Widget _buildSearchBar(
    TextEditingController ctl,
    String hint,
    VoidCallback onSearch, {
    VoidCallback? onChanged,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: ctl,
        style: const TextStyle(fontSize: 14),
        onChanged: onChanged == null ? null : (_) => onChanged(),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 6),
            child: Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
          ),
          prefixIconConstraints: const BoxConstraints(),
          // 对齐 Vue showClear：有内容时才显示清除按钮
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: ctl,
            builder: (_, value, __) {
              if (value.text.isEmpty) {
                return const SizedBox.shrink();
              }
              return GestureDetector(
                onTap: () {
                  ctl.clear();
                  onSearch();
                },
                child: const Icon(Icons.clear, size: 18, color: Color(0xFF9CA3AF)),
              );
            },
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: _primary),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        onSubmitted: (_) => onSearch(),
      ),
    );
  }

  Widget _buildFilterRow(List<Widget> children) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: children
            .asMap()
            .entries
            .map((entry) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: entry.key < children.length - 1 ? 8 : 0),
                    child: entry.value,
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildDropdown(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
          ],
        ),
      ),
    );
  }

  void _showSheet({
    required String title,
    required Map<String, String> options,
    required String currentValue,
    required void Function(String) onSelect,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      const SizedBox(width: 48),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                ...options.entries.map((e) {
                  final selected = e.value == currentValue;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelect(e.value);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key,
                              style: TextStyle(
                                fontSize: 14,
                                color: selected ? _primary : const Color(0xFF333333),
                              ),
                            ),
                          ),
                          if (selected) const Icon(Icons.check, size: 18, color: _primary),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
