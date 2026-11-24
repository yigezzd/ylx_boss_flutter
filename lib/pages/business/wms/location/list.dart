import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/location/edit.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 读取接口字段并转为字符串（兼容 dynamic 返回）
String _pick(Map<String, dynamic> map, String key) {
  final Object? value = map[key];
  return value?.toString() ?? '';
}

/// 绑定商品展示名：商品名（单位），区分同名不同包装单位；名称已含单位后缀时不重复拼接（兼容历史数据 productname 未带单位）
String _formatBindName(Map<String, dynamic> item) {
  final String name = _pick(item, 'productname');
  if (name.isEmpty) {
    return '';
  }
  final String unitText = _pick(item, 'unit');
  final String unit = unitText.isNotEmpty ? unitText : _pick(item, 'unitname');
  if (unit.isEmpty) {
    return name;
  }
  if (name.contains('（$unit）') || name.contains('($unit)')) {
    return name;
  }
  return '$name（$unit）';
}

/// WMS 货位管理列表页（对齐小程序 wms/location/index.vue）
class WmsLocationListPage extends StatefulWidget {
  const WmsLocationListPage({super.key});

  @override
  State<WmsLocationListPage> createState() => _WmsLocationListPageState();
}

class _WmsLocationListPageState extends State<WmsLocationListPage> {
  static const int _pageSize = 20;
  static const Color _primaryColor = Color(0xFF006EFF);

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _list = <Map<String, dynamic>>[];

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _searchTextEmpty = true;

  /// 机构（默认当前登录机构）
  String _storeId = '';
  String _storeName = '';

  /// 库区
  String _zoneId = '';
  String _zoneName = '全部库区';

  /// 状态：''=全部、0=启用、1=停用
  String _stopflag = '';

  String get _statusName =>
      const <String, String>{'': '全部状态', '0': '启用', '1': '停用'}[_stopflag] ?? '全部状态';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchTextChanged);
    _loadLoginStore();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadLoginStore() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(storeStr);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      _storeId = _pick(decoded, 'id');
      _storeName = _pick(decoded, 'name');
    } catch (_) {}
  }

  void _onSearchTextChanged() {
    final bool empty = _searchController.text.isEmpty;
    if (empty != _searchTextEmpty) {
      setState(() => _searchTextEmpty = empty);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  Future<void> _loadData() {
    if (_loading) {
      return Future<void>.value();
    }
    setState(() => _loading = true);
    final bool isFirstPage = _page == 1;

    final Map<String, dynamic> params = <String, dynamic>{
      'is_page': 1,
      'field': '',
      'type': '',
      'page': _page,
      'pagesize': _pageSize,
      // 货位号/货位号名称搜索：与 PC 端 rackGood 入参一致，字段名为 locationcond
      'locationcond': _searchController.text.trim(),
      'storeid': _storeId,
      'stockzoneid': _zoneId,
      'stopflag': _stopflag,
    };

    // 货位管理列表取货位商品列表（行=货位字段+商品字段），与 PC 端 rackGood 一致
    return request(HttpApi.locationProductGetList, params).then((Map<String, dynamic> result) {
      if (!mounted) {
        return;
      }
      final Object? data = result['data'];
      final Object? rawList = data is Map<String, dynamic> ? data['list'] : data;
      final List<Map<String, dynamic>> rows = rawList is List
          ? rawList.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      setState(() {
        if (isFirstPage) {
          _list
            ..clear()
            ..addAll(rows);
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= _pageSize;
      });
    }).catchError((_) {
      if (mounted) {
        setState(() => _hasMore = false);
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() => _loading = false);
      }
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _retParam() {
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  // ────────────────────────── 筛选 ──────────────────────────

  Future<void> _openStoreSelect() async {
    final Map<String, dynamic>? result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _storeId.isNotEmpty ? _storeId : null,
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _storeId = _pick(result, 'storeid');
      _storeName = _storeId.isEmpty ? '' : _pick(result, 'storename');
      // 机构变化后库区需要重新过滤
      _zoneId = '';
      _zoneName = '全部库区';
    });
    _retParam();
  }

  Future<void> _openZoneSelect() async {
    final Map<String, dynamic>? result = await CommonSelectSheet.show(
      context,
      title: '选择库区',
      searchHint: '输入库区名称',
      showAll: true,
      idField: 'stockzoneid',
      initialSelectedId: _zoneId.isNotEmpty ? _zoneId : null,
      fetchData: (String searchText, int page) =>
          request(HttpApi.storageZoneGetList, <String, dynamic>{
        'is_page': 1,
        'page': page,
        'pagesize': _pageSize,
        'cond': searchText,
        'sids': _storeId,
        // 库区接口按 name 模糊搜索（对齐小程序 selectCom 的 condKey="name"）
        'name': searchText,
      }).then((Map<String, dynamic> res) {
        final Object? data = res['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      mapResult: (Map<String, dynamic> item) => <String, dynamic>{
        'stockzoneid': _pick(item, 'stockzoneid'),
        'name': _pick(item, 'name'),
      },
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _zoneId = _pick(result, 'stockzoneid');
      _zoneName = _zoneId.isEmpty ? '全部库区' : _pick(result, 'name');
    });
    _retParam();
  }

  void _openStatusSelect() {
    final List<Map<String, String>> options = <Map<String, String>>[
      <String, String>{'label': '全部状态', 'value': ''},
      <String, String>{'label': '启用', 'value': '0'},
      <String, String>{'label': '停用', 'value': '1'},
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  '选择状态',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ...options.map((Map<String, String> option) {
                final bool selected = _stopflag == option['value'];
                return GestureDetector(
                  onTap: () {
                    setState(() => _stopflag = option['value'] ?? '');
                    Navigator.pop(ctx);
                    _retParam();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFF0F7FF) : Colors.white,
                      border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            option['label'] ?? '',
                            style: TextStyle(
                              fontSize: 14,
                              color: selected ? _primaryColor : const Color(0xFF333333),
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (selected) const Icon(Icons.check, size: 18, color: _primaryColor),
                      ],
                    ),
                  ),
                );
              }),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  // ────────────────────────── 跳转 ──────────────────────────

  Future<void> _goEdit(Map<String, dynamic> item) async {
    // product/getList 行为货位商品记录：货位主键取 locationid（行 id 为绑定记录 id，不代表货位），缺失时用 id 兜底
    final String lid = _pick(item, 'locationid');
    final String locationid = lid.isNotEmpty ? lid : _pick(item, 'id');
    if (locationid.isEmpty) {
      return;
    }
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => WmsLocationEditPage(id: locationid, locationid: locationid),
      ),
    );
    // 对齐小程序 onShow：返回后刷新列表
    if (mounted) {
      _retParam();
    }
  }

  Future<void> _goAdd() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => WmsLocationEditPage(
          storeId: _storeId,
          storeName: _storeName,
        ),
      ),
    );
    if (mounted) {
      _retParam();
    }
  }

  // ────────────────────────── 页面构建 ──────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '货位管理',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _buildStoreChip(),
                      const SizedBox(width: 8),
                      Expanded(child: _buildSearchField()),
                      const SizedBox(width: 8),
                      _buildAddButton(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      _buildQuickChip(
                        label: _zoneName,
                        active: _zoneId.isNotEmpty,
                        onTap: _openZoneSelect,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickChip(
                        label: _statusName,
                        active: _stopflag.isNotEmpty,
                        onTap: _openStatusSelect,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _primaryColor,
        onRefresh: _onRefresh,
        child: _list.isEmpty && !_loading
            ? ListView(
                children: const <Widget>[
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: <Widget>[
                        Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                        SizedBox(height: 12),
                        Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                cacheExtent: 800,
                itemCount: _list.length + (_loading ? 1 : (_hasMore ? 0 : 1)),
                itemBuilder: (BuildContext context, int index) {
                  if (index == _list.length) {
                    return _loading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
                              ),
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                '没有更多数据',
                                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                              ),
                            ),
                          );
                  }
                  final Map<String, dynamic> item = _list[index];
                  return RepaintBoundary(
                    child: _LocationCard(item: item, onTap: () => _goEdit(item)),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildStoreChip() {
    return GestureDetector(
      onTap: _openStoreSelect,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        constraints: const BoxConstraints(maxWidth: 116),
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                _storeName.isNotEmpty ? _storeName : '全部机构',
                style: TextStyle(
                  fontSize: 12,
                  color: _storeName.isNotEmpty ? const Color(0xFF111827) : const Color(0xFF7A7A7A),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF999999)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _retParam(),
        style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
        decoration: InputDecoration(
          hintText: '货位号',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          suffixIcon: _searchTextEmpty
              ? null
              : GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _retParam();
                  },
                  child: const Icon(Icons.clear, size: 16, color: Color(0xFF9CA3AF)),
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 30),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF7F7F7),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _goAdd,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.add, size: 22, color: _primaryColor),
      ),
    );
  }

  Widget _buildQuickChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEAF2FF) : const Color(0xFFF5F6F8),
          border: Border.all(color: active ? const Color(0xFF9EC5FF) : const Color(0xFFF5F6F8)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? _primaryColor : const Color(0xFF7A7A7A),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: active ? _primaryColor : const Color(0xFF7A7A7A),
            ),
          ],
        ),
      ),
    );
  }
}

/// 货位列表卡片（独立 Widget，便于列表复用）
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String code = _pick(item, 'locationcode');
    final String name = _pick(item, 'locationname');
    final bool stopped = _pick(item, 'stopflag') == '1';
    final String storename = _pick(item, 'storename');
    final String countername = _pick(item, 'countername');
    final String zonename = _pick(item, 'zonename');
    // 只有拣货位库区（zonetype=1）才能绑定商品，非拣货位库区不展示该字段
    final String zonetype = _pick(item, 'zonetype');
    final String productname = _formatBindName(item);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  code.isEmpty ? '-' : code,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (stopped)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFFD8A8)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '停用',
                      style: TextStyle(fontSize: 10, color: Color(0xFFFF7D00)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '机构：$storename',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '仓库：$countername',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '库区名称：$zonename',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (zonetype == '1')
                  Text(
                    '绑定商品：$productname',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
