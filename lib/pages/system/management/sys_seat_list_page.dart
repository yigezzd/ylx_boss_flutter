import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/system/management/sys_seat_edit_dialog.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 授权管理（对齐 Vue sysseat/index.vue）
class SysSeatListPage extends StatefulWidget {
  const SysSeatListPage({super.key});

  @override
  State<SysSeatListPage> createState() => _SysSeatListPageState();
}

class _SysSeatListPageState extends State<SysSeatListPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  // 站点授权
  List<Map<String, dynamic>> _siteList = [];
  bool _siteLoading = false;
  bool _siteHasMore = true;
  int _sitePage = 1;
  final _siteSearchCtl = TextEditingController();
  final _siteScrollCtl = ScrollController();
  List<int> _siteSids = [];
  String _siteSidsname = '';
  String _siteStopflag = '';
  int _siteClienttype = 0; // 0=全部
  Map<String, dynamic> _siteSum = {};

  // 用户授权
  List<Map<String, dynamic>> _userList = [];
  bool _userLoading = false;
  bool _userHasMore = true;
  int _userPage = 1;
  final _userSearchCtl = TextEditingController();
  final _userScrollCtl = ScrollController();
  List<int> _userSids = [];
  String _userSidsname = '';
  String _userSeatstatus = '';
  Map<String, dynamic> _userSum = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
        _loadCurrent();
      }
    });
    _siteScrollCtl.addListener(() {
      if (_siteScrollCtl.position.pixels >= _siteScrollCtl.position.maxScrollExtent - 60 &&
          !_siteLoading &&
          _siteHasMore) {
        _sitePage++;
        _loadSiteData(reset: false);
      }
    });
    _userScrollCtl.addListener(() {
      if (_userScrollCtl.position.pixels >= _userScrollCtl.position.maxScrollExtent - 60 &&
          !_userLoading &&
          _userHasMore) {
        _userPage++;
        _loadUserData(reset: false);
      }
    });
    _loadCurrent();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _siteSearchCtl.dispose();
    _userSearchCtl.dispose();
    _siteScrollCtl.dispose();
    _userScrollCtl.dispose();
    super.dispose();
  }

  void _loadCurrent() {
    if (_tabIndex == 0) {
      _loadSiteData();
    } else {
      _loadUserData();
    }
  }

  // ============ 站点授权 ============
  Future<void> _loadSiteData({bool reset = true}) async {
    if (_siteLoading) return;
    setState(() => _siteLoading = true);
    if (reset) {
      _sitePage = 1;
      _siteHasMore = true;
    }
    try {
      final res = await request(HttpApi.machineGetList, {
        'is_page': 1,
        'page': _sitePage,
        'pagesize': 20,
        'cond': _siteSearchCtl.text.trim(),
        'sids': _siteSids,
        'stopflag': _siteStopflag,
        'clienttype':
            _siteClienttype > 0 ? ['PC', 'APPSALE', 'APP', 'SSC'][_siteClienttype - 1] : '',
      });
      final data = res['data'];
      final list = (data is Map ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      _siteSum = (data is Map ? data['sumdata'] : null) as Map<String, dynamic>? ?? {};
      setState(() {
        if (_sitePage == 1) {
          _siteList = rows;
        } else {
          _siteList.addAll(rows);
        }
        _siteHasMore = rows.length >= 20;
      });
    } catch (_) {
      setState(() => _siteHasMore = false);
    } finally {
      setState(() => _siteLoading = false);
    }
  }

  // ============ 用户授权 ============
  Future<void> _loadUserData({bool reset = true}) async {
    if (_userLoading) return;
    setState(() => _userLoading = true);
    if (reset) {
      _userPage = 1;
      _userHasMore = true;
    }
    try {
      final res = await request(HttpApi.sysSeatFindList, {
        'is_page': 1,
        'page': _userPage,
        'pagesize': 20,
        'cond': _userSearchCtl.text.trim(),
        'sids': _userSids,
        'seatstatus': _userSeatstatus,
        'authflag': '',
      });
      final data = res['data'];
      final list = (data is Map ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      _userSum = (data is Map ? data['sumdata'] : null) as Map<String, dynamic>? ?? {};
      setState(() {
        if (_userPage == 1) {
          _userList = rows;
        } else {
          _userList.addAll(rows);
        }
        _userHasMore = rows.length >= 20;
      });
    } catch (_) {
      setState(() => _userHasMore = false);
    } finally {
      setState(() => _userLoading = false);
    }
  }

  // ============ 选择机构 ============
  Future<void> _selectSiteStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      // 回显当前选中的机构（空值时高亮“全部”）
      initialSelectedId:
          _siteSids.isNotEmpty && _siteSids.first > 0 ? _siteSids.first.toString() : '',
    );
    if (result != null && mounted) {
      final id = int.tryParse(result['storeid']?.toString() ?? '') ?? 0;
      setState(() {
        _siteSids = id > 0 ? [id] : [];
        _siteSidsname = result['storename']?.toString() ?? '';
      });
      _loadSiteData();
    }
  }

  Future<void> _selectUserStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      // 回显当前选中的机构（空值时高亮“全部”）
      initialSelectedId:
          _userSids.isNotEmpty && _userSids.first > 0 ? _userSids.first.toString() : '',
    );
    if (result != null && mounted) {
      final id = int.tryParse(result['storeid']?.toString() ?? '') ?? 0;
      setState(() {
        _userSids = id > 0 ? [id] : [];
        _userSidsname = result['storename']?.toString() ?? '';
      });
      _loadUserData();
    }
  }

  // ============ 站点操作 ============
  void _editSite(Map<String, dynamic> item) {
    showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SysSeatEditDialog(item: item),
    ).then((v) {
      if (v == true) _loadSiteData();
    });
  }

  void _deleteSite(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确认删除该站点授权吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              request(HttpApi.machineOperate, {...item, 'operateType': 3}).then((_) {
                Toast.show('删除成功');
                _loadSiteData();
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ============ 用户操作 ============
  void _bindUser(Map<String, dynamic> item) {
    if (!PermissionUtils.checkPermission('014701', showTip: false)) {
      Toast.show('你无权绑定用户授权，请在后台修改权限');
      return;
    }
    // 打开用户选择器（对齐 Vue selectCom）
    _showUserPicker(item).then((user) {
      if (user != null) {
        request(HttpApi.sysSeatBindSeat, {
          ...item,
          'username': user['name'],
          'usercode': user['code'],
          'userid': user['userid'],
        }).then((_) {
          Toast.show('绑定成功');
          _loadUserData();
        });
      }
    });
  }

  Future<Map<String, dynamic>?> _showUserPicker(Map<String, dynamic> seatItem) async {
    final userList = await request(HttpApi.sysUserList, {
      'is_page': 1,
      'page': 1,
      'pagesize': 50,
      'cond': '',
      'sids': <int>[],
      'stopflag': 0,
    });
    final list = ((userList['data'] as Map?)?['list'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (list.isEmpty) {
      if (mounted) Toast.show('暂无可用用户');
      return null;
    }
    if (!mounted) return null;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择员工', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ...list.map((u) => ListTile(
                title: Text('[${u['code'] ?? ''}]${u['name'] ?? ''}'),
                onTap: () => Navigator.pop(context, u),
              )),
        ],
      ),
    );
  }

  void _unbindUser(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('提示'),
        content: Text('确认解绑${item['username'] ?? '该用户'}吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              request(HttpApi.sysSeatUnbindSeat, item).then((_) {
                Toast.show('解绑成功');
                _loadUserData();
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _toggleUserStatus(Map<String, dynamic> item, bool enable) {
    if (!PermissionUtils.checkPermission('014702', showTip: false)) {
      Toast.show('你无权启用用户授权，请在后台修改权限');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('提示'),
        content: Text('确认${enable ? "启用" : "停用"}该用户吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              request(HttpApi.sysSeatUpdateStop, [
                {...item, 'stopflag': enable ? 0 : 1}
              ]).then((_) {
                Toast.show('${enable ? "启用" : "停用"}成功');
                _loadUserData();
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ============ Build ============
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
          _buildTabs(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildSiteTab(), _buildUserTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return ColoredBox(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF006EFF),
        unselectedLabelColor: const Color(0xFF666666),
        indicatorColor: const Color(0xFF006EFF),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        tabs: const [Tab(text: '站点授权'), Tab(text: '用户授权')],
      ),
    );
  }

  Widget _buildSiteTab() {
    return RefreshIndicator(
      onRefresh: () async => _loadSiteData(),
      child: ListView(
        controller: _siteScrollCtl,
        children: [
          Column(children: [
            _buildSearchBar(_siteSearchCtl, '请输入设备号/名称', _loadSiteData),
            _buildFilterRow([
              _buildDropdown(_siteSidsname.isNotEmpty ? _siteSidsname : '全部机构', _selectSiteStore),
              _buildDropdown(
                  _siteStopflag.isNotEmpty ? (_siteStopflag == '0' ? '启用' : '停用') : '全部状态',
                  () => _showSheet(
                      title: '选择状态',
                      options: {'全部状态': '', '启用': '0', '停用': '1'},
                      currentValue: _siteStopflag,
                      onSelect: (v) {
                        _siteStopflag = v;
                        _loadSiteData();
                      })),
              _buildDropdown(
                  _siteClienttype == 0
                      ? '全部类型'
                      : ['PC收银端', '安卓收银端', '移动终端', '自助终端'][_siteClienttype - 1],
                  () => _showSheet(
                      title: '选择类型',
                      options: {'全部类型': '0', 'PC收银端': '1', '安卓收银端': '2', '移动终端': '3', '自助终端': '4'},
                      currentValue: _siteClienttype.toString(),
                      onSelect: (v) {
                        _siteClienttype = int.tryParse(v) ?? 0;
                        _loadSiteData();
                      })),
            ]),
            if (_siteSum.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  Text('已购总量:${_siteSum['storeMaxCount'] ?? 0}  ',
                      style: const TextStyle(fontSize: 13)),
                  Text('已授权:${_siteSum['storeCount'] ?? 0}  ',
                      style: const TextStyle(fontSize: 13)),
                  Text('剩余可用:${_siteSum['storeHaveCount'] ?? 0}',
                      style: const TextStyle(fontSize: 13)),
                ]),
              ),
          ]),
          ..._siteList.map((item) => RepaintBoundary(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('设备机号：${item['code'] ?? '--'}',
                                style: const TextStyle(fontSize: 13))),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: item['stopflag'] == 1
                                    ? const Color(0xFFFFF3E0)
                                    : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(3)),
                            child: Text(item['stopflag'] == 1 ? '停用' : '启用',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: item['stopflag'] == 1
                                        ? const Color(0xFFFF9800)
                                        : const Color(0xFF4CAF50)))),
                      ]),
                      const SizedBox(height: 4),
                      Text('设备名称：${item['name'] ?? '--'}', style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                            child: Text('归属机构：${item['storeName'] ?? '--'}',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF666666)))),
                        Text('设备类型：${item['clienttypeName'] ?? '--'}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
                      ]),
                      const SizedBox(height: 4),
                      Text('版本：${item['vcode'] ?? '--'}  最后登录：${item['lastuser'] ?? '--'}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        GestureDetector(
                            onTap: () => _deleteSite(item),
                            child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFDEDEDE)),
                                    borderRadius: BorderRadius.circular(4)),
                                child: const Text('删除',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF333333))))),
                        const SizedBox(width: 8),
                        GestureDetector(
                            onTap: () => _editSite(item),
                            child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF006EFF),
                                    borderRadius: BorderRadius.circular(4)),
                                child: const Text('编辑',
                                    style: TextStyle(fontSize: 12, color: Colors.white)))),
                      ]),
                    ],
                  ),
                ),
              )),
          if (_siteLoading)
            const Padding(
                padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildUserTab() {
    return RefreshIndicator(
      onRefresh: () async => _loadUserData(),
      child: ListView(
        controller: _userScrollCtl,
        children: [
          Column(children: [
            _buildSearchBar(_userSearchCtl, '输入用户名/工号/席位号', _loadUserData),
            _buildFilterRow([
              _buildDropdown(_userSidsname.isNotEmpty ? _userSidsname : '全部门店', _selectUserStore),
              _buildDropdown(
                  _userSeatstatus.isNotEmpty
                      ? ['空闲', '使用中', '停用', '已过期'][int.tryParse(_userSeatstatus) ?? 0]
                      : '不限',
                  () => _showSheet(
                      title: '选择状态',
                      options: {'不限': '', '空闲': '0', '使用中': '1', '停用': '2', '已过期': '3'},
                      currentValue: _userSeatstatus,
                      onSelect: (v) {
                        _userSeatstatus = v;
                        _loadUserData();
                      })),
            ]),
            if (_userSum.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                    '已购总量:${_userSum['userMaxCount'] ?? 0}  占用:${_userSum['userCount'] ?? 0}  空闲:${_userSum['userHaveCount'] ?? 0}',
                    style: const TextStyle(fontSize: 13)),
              ),
          ]),
          ..._userList.map((item) => RepaintBoundary(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('席位：${item['code'] ?? '--'}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(3)),
                            child: Text('${item['seatstatusname'] ?? '--'}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF1976D2)))),
                      ]),
                      const SizedBox(height: 4),
                      Text('${item['username'] ?? '--'}[${item['usercode'] ?? ''}]',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                            child: Text('归属机构：${item['storename'] ?? '--'}',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF666666)))),
                        Text('角色：${item['rolename'] ?? '--'}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
                      ]),
                      const SizedBox(height: 4),
                      Text('到期：${item['validtime'] ?? '--'}  最后登录：${item['lastlogin'] ?? '--'}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (item['usercode'] != '1001') ...[
                          if (item['userid'] != null)
                            GestureDetector(
                                onTap: () => _unbindUser(item),
                                child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                        border: Border.all(color: const Color(0xFFDEDEDE)),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Text('解绑',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF333333)))))
                          else
                            GestureDetector(
                                onTap: () => _bindUser(item),
                                child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                        border: Border.all(color: const Color(0xFFDEDEDE)),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Text('绑定',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF333333))))),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _toggleUserStatus(item, item['stopflag'] != 0),
                            child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF006EFF),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(item['stopflag'] == 0 ? '停用' : '启用',
                                    style: const TextStyle(fontSize: 12, color: Colors.white))),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
              )),
          if (_userLoading)
            const Padding(
                padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  // ============ 复用组件 ============
  Widget _buildSearchBar(TextEditingController ctl, String hint, VoidCallback onSearch) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: ctl,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 6),
            child: Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
          ),
          prefixIconConstraints: const BoxConstraints(),
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
            borderSide: const BorderSide(color: Color(0xFF006EFF)),
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
                      child: entry.value)))
              .toList()),
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
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                  overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
          ],
        ),
      ),
    );
  }

  void _showSheet(
      {required String title,
      required Map<String, String> options,
      required String currentValue,
      required void Function(String) onSelect}) {
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
                                color: selected ? const Color(0xFF006EFF) : const Color(0xFF333333),
                              ),
                            ),
                          ),
                          if (selected) const Icon(Icons.check, size: 18, color: Color(0xFF006EFF)),
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
