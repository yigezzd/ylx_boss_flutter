import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';

class SelectRefbillPage extends StatefulWidget {
  const SelectRefbillPage({
    super.key,
    this.bsid,
    this.storename,
    this.customTypes,
    this.extraListParams,
    this.extraInfoParams,
  });

  /// 当前机构 ID（用于过滤原单列表，与 boss 端 sids 参数对齐）
  final int? bsid;

  /// 当前机构名称
  final String? storename;

  /// 自定义单据类型列表（如要货申请单），覆盖默认类型
  final List<Map<String, dynamic>>? customTypes;

  /// 传给 findList 接口的额外参数
  final Map<String, dynamic>? extraListParams;

  /// 传给 getInfo 接口的额外参数
  final Map<String, dynamic>? extraInfoParams;

  @override
  State<SelectRefbillPage> createState() => _SelectRefbillPageState();
}

class _SelectRefbillPageState extends State<SelectRefbillPage> with SingleTickerProviderStateMixin {
  /// 单据类型：1=采购订货单 2=采购计划单 3=自采申请单 4=直配订单 5=越库订单
  static const List<Map<String, dynamic>> _types = [
    {'value': 1, 'label': '采购订货单', 'path': 'cgorder/findList', 'infoPath': 'cgorder/getInfo'},
    {'value': 2, 'label': '采购计划单', 'path': 'cgplan/findList', 'infoPath': 'cgplan/getInfo'},
    {'value': 3, 'label': '自采申请单', 'path': 'cgzc/findList', 'infoPath': 'cgzc/getInfo'},
    {'value': 4, 'label': '直配订单', 'path': 'cgother/findList', 'infoPath': 'cgother/getInfo'},
    {'value': 5, 'label': '越库订单', 'path': 'cgothercd/findList', 'infoPath': 'cgothercd/getInfo'},
  ];

  int _selectedType = 1;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();

  // 日期筛选（对齐小程序 selectTime：列表页年/月/日可自由调整查询范围）
  // 默认选中“自定义”并自动填充近 30 天（对齐小程序自定义态展示，范围更宽避免初始数据为空）
  DateTime? _startDate;
  DateTime? _endDate;
  int _quickTimeIndex = 4; // 0=昨天 1=今日 2=本周 3=本月 4=自定义（对齐 selectTime.vue timeTabs，默认自定义）

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  final ScrollController _scrollController = ScrollController();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _selectedType = _activeTypes.first['value'] as int;
    // 默认“自定义”+ 近 30 天：初始展示默认范围内数据，用户可自由调整
    final now = DateTime.now();
    _endDate = now;
    _startDate = now.subtract(const Duration(days: 30));
    _tabController = TabController(length: _activeTypes.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Tab 切换联动单据类型（仅少类型 TabBar 模式生效）
  void _onTabChanged() {
    final type = _activeTypes[_tabController.index]['value'] as int;
    if (type != _selectedType) {
      _onTypeChanged(type);
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

  List<Map<String, dynamic>> get _activeTypes => widget.customTypes ?? _types;

  String get _currentPath {
    final match = _activeTypes.firstWhere((t) => t['value'] == _selectedType);
    return match['path'] as String;
  }

  String get _currentInfoPath {
    final match = _activeTypes.firstWhere((t) => t['value'] == _selectedType);
    return match['infoPath'] as String;
  }

  /// 当前单据类型是否携带 refdhflag 参数（默认携带；
  // 退货申请单 cgzc/findList 无此过滤项，类型配置 sendRefdhflag:false 关闭，对齐小程序 cgthsq/search 不传该参数）
  bool get _sendRefdhflag {
    final match = _activeTypes.firstWhere((t) => t['value'] == _selectedType);
    return match['sendRefdhflag'] != false;
  }

  /// 当前单据类型自定义的列表参数（如 billtype），覆盖默认参数
  Map<String, dynamic> get _currentListParams {
    final match = _activeTypes.firstWhere((t) => t['value'] == _selectedType);
    final params = match['listParams'];
    return params is Map<String, dynamic> ? params : const {};
  }

  /// 当前单据类型自定义的明细参数
  Map<String, dynamic> get _currentInfoParams {
    final match = _activeTypes.firstWhere((t) => t['value'] == _selectedType);
    final params = match['infoParams'];
    return params is Map<String, dynamic> ? params : const {};
  }

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    return request(_currentPath, <String, dynamic>{
      'is_page': '1',
      'page': '$_page',
      'billno': _searchText,
      'signflag': '1',
      if (_sendRefdhflag) 'refdhflag': 1,
      // 对齐小程序 search.vue isSelect 模式：starttime/endtime 拼接时分秒；
      // 未选择日期时不传，列表显示所有可用单据
      if (_startDate != null) 'starttime': '${_fmtDate(_startDate!)} 00:00:00',
      if (_endDate != null) 'endtime': '${_fmtDate(_endDate!)} 23:59:59',
      if (widget.bsid != null) 'sids': [widget.bsid],
      if (widget.storename != null) 'storename': widget.storename,
      ..._currentListParams,
      ...?widget.extraListParams,
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list = (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.isNotEmpty;
      });
    }).catchError((_) {
      setState(() => _hasMore = false);
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  /// 选中某条原单后，调用对应单据类型的 getInfo 接口获取完整明细，成功后 pop 返回
  void _onSelectBill(Map<String, dynamic> item) {
    final String? billno = item['billno']?.toString();
    if (billno == null || billno.isEmpty) return;

    setState(() => _loading = true);
    // 与 boss 项目保持一致：将列表行整个对象传给 getInfo
    final infoParams = Map<String, dynamic>.from(item);
    infoParams.addAll(_currentInfoParams);
    if (widget.extraInfoParams != null) {
      infoParams.addAll(widget.extraInfoParams!);
    }
    request(_currentInfoPath, infoParams).then((result) {
      if (!mounted) return;
      final data =
          result['data'] is Map<String, dynamic> ? result['data'] as Map<String, dynamic> : result;
      Navigator.pop(context, {
        'refbillno': billno,
        'refbilltype': _selectedType,
        'refbillid': item['billid']?.toString(),
        'info': data,
      });
    }).catchError((_) {
      if (!mounted) return;
      Toast.show('获取单据明细失败，请重试');
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  void _onTypeChanged(int type) {
    if (type == _selectedType) return;
    setState(() {
      _selectedType = type;
      _page = 1;
      _hasMore = true;
      _list = [];
    });
    _loadData();
  }

  /// 少类型模式：铺满宽度的 TabBar（对齐 cgother/list.dart、customer_pay/list.dart 风格）
  Widget _buildTypeTabBar() {
    return ColoredBox(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF006EFF),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelColor: const Color(0xFF6B7280),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        indicatorColor: const Color(0xFF006EFF),
        indicatorSize: TabBarIndicatorSize.label,
        tabs: _activeTypes.map((t) => Tab(text: t['label'] as String)).toList(),
      ),
    );
  }

  /// 多类型模式：横向滚动 chips（保持 instore 等页面现有显示效果）
  Widget _buildTypeChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _activeTypes.map((t) {
            final int value = t['value'] as int;
            final String label = t['label'] as String;
            final bool selected = value == _selectedType;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected,
                selectedColor: const Color(0xFF006EFF).withOpacity(0.15),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? const Color(0xFF006EFF) : const Color(0xFF6B7280),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: selected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB),
                  ),
                ),
                backgroundColor: Colors.white,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                onSelected: (_) => _onTypeChanged(value),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _onSearch() {
    setState(() {
      _searchText = _searchController.text.trim();
      _page = 1;
      _hasMore = true;
      _list = [];
    });
    _loadData();
  }

  static String _fmtDate(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  /// 选择开始/结束日期后重新查询（手动选日期切回自定义，对齐列表页 tmpActiveQuickTimeId=4 约定）
  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // 开始日期晚于结束日期时同步结束日期，保证区间有效
        final end = _endDate;
        if (end == null || picked.isAfter(end)) _endDate = picked;
      } else {
        _endDate = picked;
        final start = _startDate;
        if (start == null || picked.isBefore(start)) _startDate = picked;
      }
      _quickTimeIndex = 4;
      _page = 1;
      _hasMore = true;
      _list = [];
    });
    _loadData();
  }

  /// 快捷时间选项（对齐 selectTime.vue selectTimeFn 的日期区间计算）
  void _applyQuickTime(int index) {
    if (index == _quickTimeIndex) return;
    final now = DateTime.now();
    DateTime? start = _startDate;
    DateTime? end = _endDate;
    switch (index) {
      case 0:
        // 昨天
        final y = now.subtract(const Duration(days: 1));
        start = y;
        end = y;
        break;
      case 1:
        // 今天
        start = now;
        end = now;
        break;
      case 2:
        // 本周（周一~周日）
        final dow = now.weekday; // 1=周一..7=周日
        start = now.subtract(Duration(days: dow - 1));
        end = now.add(Duration(days: dow == 7 ? 0 : 7 - dow));
        break;
      case 3:
        // 本月（首尾日）
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      default:
        // 自定义保持当前日期
        break;
    }
    setState(() {
      _quickTimeIndex = index;
      _startDate = start;
      _endDate = end;
      _page = 1;
      _hasMore = true;
      _list = [];
    });
    _loadData();
  }

  /// 日期筛选区（对齐小程序 selectTime：快捷选项栏 + 自定义日期范围行）
  Widget _buildDateFilter() {
    const tabs = ['昨天', '今日', '本周', '本月', '自定义'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        children: [
          Row(
            children: List.generate(tabs.length, (i) {
              final active = _quickTimeIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _applyQuickTime(i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF006EFF) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickDate(true),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Color(0xFF6B7280)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_startDate != null ? _fmtDate(_startDate!) : '开始日期',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: _startDate != null
                                      ? const Color(0xFF333333)
                                      : const Color(0xFF9CA3AF)),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('至', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickDate(false),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEDEDE)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Color(0xFF6B7280)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_endDate != null ? _fmtDate(_endDate!) : '结束日期',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: _endDate != null
                                      ? const Color(0xFF333333)
                                      : const Color(0xFF9CA3AF)),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '选择原单号',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          // 单据类型选择（单一类型时隐藏）：
          // 少类型（≤3，如 cgth 的 2 类）用铺满宽度的 TabBar，对齐 cgother/list.dart 风格；
          // 多类型（如 instore 默认 5 类）保持原有横向滚动 chips，避免等分压缩拥挤
          if (_activeTypes.length > 1)
            _activeTypes.length <= 3 ? _buildTypeTabBar() : _buildTypeChips(),
          // 日期筛选（对齐小程序 selectTime，用户可自由调整查询范围）
          _buildDateFilter(),
          // 搜索框
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: '输入单号搜索',
                        hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (_) => _onSearch(),
                    ),
                  ),
                  GestureDetector(
                    onTap: _onSearch,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.search, size: 18, color: Color(0xFF006EFF)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 列表
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF006EFF),
              onRefresh: _onRefresh,
              child: _list.isEmpty && !_loading
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                              SizedBox(height: 12),
                              Text(
                                '暂无数据',
                                style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      cacheExtent: 800,
                      itemCount: _list.length + (_loading ? 1 : (_hasMore ? 0 : 1)),
                      itemBuilder: (context, index) {
                        if (index == _list.length) {
                          return _loading
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF006EFF),
                                      ),
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
                        return _RefbillCard(
                          item: _list[index],
                          onTap: () => _onSelectBill(_list[index]),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefbillCard extends StatelessWidget {
  const _RefbillCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String billno = item['billno']?.toString() ?? '-';
    final String createtime = item['createtime']?.toString() ?? '-';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 16, color: Color(0xFF006EFF)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      billno,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 1,
                color: const Color(0xFFEBEBEB),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 4),
                  Text(
                    '制单时间：$createtime',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
