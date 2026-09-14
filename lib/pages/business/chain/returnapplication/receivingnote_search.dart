import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/chain/receivingnote/edit.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 配送收货单查询/选择页（对齐 Vue chain/receivingnote/search.vue）
/// isSelect=true 时作为配退申请的"选择配送收货单"页面：
/// 标题"选择配送收货单"、时间默认今天、signflag=1、点击回传整张单据
class ReceivingnoteSearchPage extends StatefulWidget {
  const ReceivingnoteSearchPage({super.key, this.isSelect = false, this.mergData});

  final bool isSelect;

  /// 原单选择透传参数（对齐 Vue receivingnote/search.vue：opt.mergData Object.assign 进 params）
  final Map<String, dynamic>? mergData;

  @override
  State<ReceivingnoteSearchPage> createState() => _ReceivingnoteSearchPageState();
}

class _ReceivingnoteSearchPageState extends State<ReceivingnoteSearchPage>
    with LogPageMixin<ReceivingnoteSearchPage> {
  @override
  String get logPageName => widget.isSelect ? '选择配送收货单' : '配送收货单';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  // 时间筛选（对齐 Vue selectTime：isSelect 默认今天）
  static const _quickLabels = ['今天', '近7天', '近30天'];
  late DateTime _startDate;
  late DateTime _endDate;
  int _activeQuickTimeId = 0;

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final now = DateTime.now();
    if (widget.isSelect) {
      // 对齐 Vue onLoad：isSelect 时 starttime=endtime=今天，signflag=1
      _startDate = now;
      _endDate = now;
      _activeQuickTimeId = 0;
    } else {
      _startDate = now.subtract(const Duration(days: 30));
      _endDate = now;
      _activeQuickTimeId = 2;
    }
    _loadData();
    logEnter();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  /// 对齐 Vue retParam：重置页码并加载
  void _reload() {
    setState(() {
      _page = 1;
      _list = [];
      _hasMore = true;
    });
    _loadData();
  }

  void _onQuickTimeTap(int i) {
    final now = DateTime.now();
    DateTime start = now;
    final DateTime end = now;
    switch (i) {
      case 1:
        start = now.subtract(const Duration(days: 6));
        break;
      case 2:
        start = now.subtract(const Duration(days: 29));
        break;
      default:
        break;
    }
    setState(() {
      _activeQuickTimeId = i;
      _startDate = start;
      _endDate = end;
    });
    _reload();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: _startDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        locale: const Locale('zh', 'CN'));
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked;
        _activeQuickTimeId = -1;
      });
      _reload();
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: _endDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        locale: const Locale('zh', 'CN'));
    if (picked != null && mounted) {
      setState(() {
        _endDate = picked;
        _activeQuickTimeId = -1;
      });
      _reload();
    }
  }

  /// 对齐 Vue getList：psstockin/findList（isSelect 时拼 starttime/endtime 当天区间）
  void _loadData() {
    if (_loading || !_hasMore) return;
    _loading = true;
    final Map<String, dynamic> params = {
      'is_page': 1,
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'pagesize': 20,
      'billno': _searchController.text.trim(),
      'signflag': widget.isSelect ? '1' : '',
      'datetype': '1',
    };
    if (widget.isSelect) {
      params['starttime'] = '${_fmtDate(_startDate)} 00:00:00';
      params['endtime'] = '${_fmtDate(_endDate)} 23:59:59';
    }
    // 对齐 Vue onLoad：opt.mergData 并入请求参数（outsid/insid 等机构过滤）
    if (widget.mergData != null) params.addAll(widget.mergData!);
    request(HttpApi.psstockinFindList, params).then((result) {
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
        _hasMore = rows.length >= 20;
      });
    }).catchError((_) {
      if (mounted) setState(() => _hasMore = false);
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

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
        title: Text(
          widget.isSelect ? '选择配送收货单' : '配送收货单',
          style:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
      ),
      body: Column(children: [
        _buildSearchBar(),
        if (widget.isSelect) _buildQuickTimeRow(),
        Expanded(
            child: _list.isEmpty && !_loading
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
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
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    cacheExtent: 800,
                    itemCount: _list.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _list.length) {
                        return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                                child: Text('加载中...',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF999999)))));
                      }
                      final item = _list[index];
                      return RepaintBoundary(
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: _BillCard(
                                  item: item,
                                  onTap: () {
                                    if (widget.isSelect) {
                                      Navigator.pop(context, item);
                                    } else {
                                      // 对齐 Vue selectItemFn：非选择模式需 013208 查看权限
                                      if (!PermissionUtils.checkPermission('013208',
                                          showTip: false)) {
                                        Toast.show('你无权查看配送收货单，请在后台修改权限');
                                        return;
                                      }
                                      Navigator.push(
                                          context,
                                          MaterialPageRoute<ReceivingnoteEditPage>(
                                              builder: (_) =>
                                                  ReceivingnoteEditPage(billData: item)));
                                    }
                                  })));
                    },
                  )),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: TextField(
        controller: _searchController,
        onSubmitted: (_) => _reload(),
        onChanged: (_) => _onSearchChanged(),
        decoration: InputDecoration(
          hintText: '请输入单号',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _onSearchChanged();
                  },
                  child: Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF6B7280),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.close, size: 10, color: Colors.white),
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 24),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFFDEDEDE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFF006EFF)),
          ),
        ),
      ),
    );
  }

  /// 时间快捷选择行（对齐 Vue selectTime，仅选择模式显示）
  Widget _buildQuickTimeRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(children: [
        Expanded(
          child: Container(
            height: 32,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5)),
            child: Row(
              children: List.generate(_quickLabels.length, (i) {
                final selected = _activeQuickTimeId == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onQuickTimeTap(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: selected ? const Color(0xFF006EFF) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        _quickLabels[i],
                        style: TextStyle(
                            fontSize: 13, color: selected ? Colors.white : const Color(0xFF333333)),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _pickStartDate,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5)),
            child: Text(_fmtDate(_startDate),
                style: const TextStyle(fontSize: 12, color: Color(0xFF333333))),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('至', style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
        ),
        GestureDetector(
          onTap: _pickEndDate,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5)),
            child: Text(_fmtDate(_endDate),
                style: const TextStyle(fontSize: 12, color: Color(0xFF333333))),
          ),
        ),
      ]),
    );
  }
}

/// 配送收货单卡片（对齐 Vue search.vue 列表卡片：单号+状态/收货门店+配送中心/单据金额+制单人/制单时间）
class _BillCard extends StatelessWidget {
  const _BillCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  String _statusLabel() {
    final signflag = item['signflag']?.toString() ?? '';
    if (signflag == '1') return '已审核';
    if (signflag == '2') return '已驳回';
    if (signflag == '-1') return '已作废';
    return '待审核';
  }

  Color _statusColor() {
    final signflag = item['signflag']?.toString() ?? '';
    if (signflag == '1') return const Color(0xFF00A870);
    if (signflag == '2') return const Color(0xFFFF9900);
    if (signflag == '-1') return const Color(0xFFAAAAAA);
    return const Color(0xFFD54B5A);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(item['billno']?.toString() ?? '',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
            Text(_statusLabel(),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _statusColor()))
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: Text('收货门店：${item['instorename']?.toString() ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            Expanded(
                child: Text('配送中心：${item['outstorename']?.toString() ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
                child: Text('单据金额：${item['billamt']?.toString() ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
            Text('制单人：${item['createname']?.toString() ?? ''}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))
          ]),
          const SizedBox(height: 4),
          Text('制单时间：${item['createtime']?.toString() ?? ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
        ]),
      ),
    );
  }
}
