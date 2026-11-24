import 'dart:convert';
import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/members/vippay/vippay_record_router.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:sp_util/sp_util.dart';

/// 收款记录页面 —— 对齐 boss 项目 subs/member/vippay/record.vue
///
/// - 列设置：display/getModelDisplaySetList（mcode=091401），仅渲染原型白名单 10 列
///   （show==1 过滤 → 白名单裁剪 → isort 升序 → billno 固定首位）；
/// - 业务数据：vipTable/getVipCardDetailList（opertype=8 收款）；
/// - 筛选条件：门店选择、时间快捷选择、搜索框、会员分类、业务员、收银员；
/// - 交互：分页加载、表头排序（billno/addmoney/capitalmoney/givemoney）、放大表格、汇总行。
class VippayRecordPage extends StatefulWidget {
  const VippayRecordPage({super.key});

  @override
  State<VippayRecordPage> createState() => _VippayRecordPageState();
}

class _VippayRecordPageState extends State<VippayRecordPage> {
  static const int _pageSize = 20;

  // ── 列表状态 ──
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _hasLoadedOnce = false;
  List<Map<String, dynamic>> _list = [];

  // ── 列配置 ──
  List<_RecordColumn> _columns = const [];
  bool _columnsInited = false;

  // ── 门店 ──
  List<String> _sids = [];
  String _storeName = '';
  String _activeStoreId = '';

  // ── 时间 ──
  late DateTime _startDate;
  late DateTime _endDate;
  int? _activeQuickTimeId = 1; // 默认今日

  // ── 排序 ──
  String _sortField = 'createtime';
  String _sortType = 'desc';
  int? _sortColumnIndex;
  bool _sortAscending = false;

  // ── 筛选条件 ──
  String _cond = '';
  String _typeid = '';
  String _typename = '';
  String _userid = '';
  String _username = '';
  String _cashid = '';
  String _cashname = '';

  // ── 合计 ──
  Map<String, dynamic> _sumdata = {};
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = now;
    _endDate = now;
    _initStore();
    _initTemplateList();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 列宽依赖屏幕宽度，首帧时构建本地兜底列
    if (!_columnsInited) {
      _columnsInited = true;
      _columns = _buildColumns(_fallbackCols);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 默认门店（对齐 Vue getCookie("store")）
  void _initStore() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        final String id = storeMap['id']?.toString() ?? '';
        _activeStoreId = id;
        _sids = id.isNotEmpty ? [id] : [];
        _storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
  }

  // ==================== 列设置 ====================

  /// 各列最小宽度兜底（对齐 record.vue MIN_WIDTH）
  static const Map<String, double> _minWidth = {
    'storeName': 80,
    'vipno': 86,
    'typeid': 60,
    'vipname': 60,
    'mobile': 86,
    'billno': 140,
    'opertype': 60,
    'payname': 60,
    'salename': 60,
    'addmoney': 70,
    'capitalmoney': 60,
    'givemoney': 60,
    'endcapitalmoney': 70,
    'endgivemoney': 70,
    'endmoney': 70,
    'clienttype': 60,
    'opername': 60,
    'createtime': 96,
    'memo': 100,
  };

  /// 原型展示的列（表格仅渲染以下关键列，最终顺序仍按 isort 排列）
  static const List<String> _prototypeFields = [
    'billno',
    'vipno',
    'typeid',
    'vipname',
    'mobile',
    'addmoney',
    'capitalmoney',
    'givemoney',
    'salename',
    'opername',
  ];

  /// 本地兜底列（与后台"会员储卡明细"列设置一致）
  static const List<Map<String, dynamic>> _fallbackCols = [
    {
      'prop': 'storeName',
      'dlabel': '机构',
      'align': 'left',
      'fwidth': 180,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 2
    },
    {
      'prop': 'vipno',
      'dlabel': '会员卡号',
      'align': 'left',
      'fwidth': 160,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 3
    },
    {
      'prop': 'typeid',
      'dlabel': '会员分类',
      'align': 'left',
      'fwidth': 110,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 4
    },
    {
      'prop': 'vipname',
      'dlabel': '会员姓名',
      'align': 'left',
      'fwidth': 110,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 5
    },
    {
      'prop': 'mobile',
      'dlabel': '手机号',
      'align': 'left',
      'fwidth': 160,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 6
    },
    {
      'prop': 'billno',
      'dlabel': '单据编号',
      'align': 'left',
      'fwidth': 160,
      'fietype': 1,
      'sortflag': 1,
      'show': 1,
      'isort': 7
    },
    {
      'prop': 'opertype',
      'dlabel': '业务类型',
      'align': 'left',
      'fwidth': 110,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 8
    },
    {
      'prop': 'payname',
      'dlabel': '付款方式',
      'align': 'left',
      'fwidth': 110,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 9
    },
    {
      'prop': 'salename',
      'dlabel': '业务员',
      'align': 'left',
      'fwidth': 110,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 10
    },
    {
      'prop': 'addmoney',
      'dlabel': '交易金额',
      'align': 'right',
      'fwidth': 110,
      'fietype': 4,
      'sortflag': 1,
      'show': 1,
      'isort': 11
    },
    {
      'prop': 'capitalmoney',
      'dlabel': '本金',
      'align': 'right',
      'fwidth': 90,
      'fietype': 4,
      'sortflag': 1,
      'show': 1,
      'isort': 12
    },
    {
      'prop': 'givemoney',
      'dlabel': '赠金',
      'align': 'right',
      'fwidth': 90,
      'fietype': 4,
      'sortflag': 1,
      'show': 1,
      'isort': 13
    },
    {
      'prop': 'endcapitalmoney',
      'dlabel': '实时本金',
      'align': 'right',
      'fwidth': 110,
      'fietype': 4,
      'sortflag': 1,
      'show': 1,
      'isort': 14
    },
    {
      'prop': 'endgivemoney',
      'dlabel': '实时赠金',
      'align': 'right',
      'fwidth': 110,
      'fietype': 4,
      'sortflag': 1,
      'show': 1,
      'isort': 15
    },
    {
      'prop': 'endmoney',
      'dlabel': '实时余额',
      'align': 'right',
      'fwidth': 110,
      'fietype': 4,
      'sortflag': 1,
      'show': 1,
      'isort': 16
    },
    {
      'prop': 'clienttype',
      'dlabel': '充值类型',
      'align': 'left',
      'fwidth': 110,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 17
    },
    {
      'prop': 'opername',
      'dlabel': '收银员',
      'align': 'left',
      'fwidth': 110,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 18
    },
    {
      'prop': 'createtime',
      'dlabel': '操作时间',
      'align': 'left',
      'fwidth': 160,
      'fietype': 1,
      'sortflag': 1,
      'show': 1,
      'isort': 19
    },
    {
      'prop': 'memo',
      'dlabel': '备注',
      'align': 'left',
      'fwidth': 300,
      'fietype': 1,
      'sortflag': 0,
      'show': 1,
      'isort': 20
    },
  ];

  /// 列宽缩放比例（对齐 record.vue：列设置总宽 2570，适配移动端横向滚动）
  double _calcWidth(String prop, double fwidth) {
    final double winW = MediaQuery.of(context).size.width;
    final double colScale = math.min((winW * 2.6) / 2570, 0.62);
    return math.max((fwidth * colScale).roundToDouble(), _minWidth[prop] ?? 56);
  }

  /// 构建列配置（对齐 record.vue buildColumns 规则链）
  List<_RecordColumn> _buildColumns(List<dynamic> source) {
    final rows = source
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        // 仅显示 show == 1 的列
        .where((e) => _toNum(e['show']) == 1)
        // 仅保留原型展示的列（自动排除"序"、机构、备注等非原型列）
        .where((e) => _prototypeFields.contains((e['prop'] ?? e['field'] ?? '').toString()))
        .toList()
      // 按 isort 升序排列（原型顺序）
      ..sort((a, b) => _toNum(a['isort']).compareTo(_toNum(b['isort'])));

    final cols = rows.map((e) {
      final String prop = (e['prop'] ?? e['field'] ?? '').toString();
      final String label = (e['dlabel'] ?? e['fieldname'] ?? prop).toString();
      final double fwidth = _toNum(e['fwidth'] ?? e['width'], fallback: 110).toDouble();
      final int fietype = _toNum(e['fietype']).toInt();
      return _RecordColumn(
        name: prop,
        label: label,
        align: (e['align'] ?? 'left').toString() == 'right' ? 'right' : 'left',
        width: _calcWidth(prop, fwidth),
        fietype: fietype >= 2 ? fietype : null,
        sortable: _toNum(e['sortflag']) == 1,
      );
    }).toList();

    // 单号列调整到第一位（fixed 列需位于数组头部才能生效）
    final int billnoIndex = cols.indexWhere((c) => c.name == 'billno');
    if (billnoIndex > 0) {
      final _RecordColumn billnoCol = cols.removeAt(billnoIndex);
      cols.insert(0, billnoCol);
    }
    return cols;
  }

  /// 拉取接口列设置（接口返回有效列时替换，否则保留本地兜底列）
  void _initTemplateList() {
    request(HttpApi.displayGetModelDisplaySetList, {'mcode': '091401'}).then((result) {
      final dynamic data = result['data'];
      final List<dynamic> rows;
      if (data is List) {
        rows = data;
      } else if (data is Map && data['list'] is List) {
        rows = data['list'] as List;
      } else {
        rows = const [];
      }
      final cols = _buildColumns(rows);
      if (cols.isNotEmpty && mounted) {
        setState(() {
          _columns = cols;
          // 接口列替换后同步排序列索引（越界时重置，避免 DataTable2 断言异常）
          if (_sortColumnIndex != null && _sortColumnIndex! >= cols.length) {
            _sortColumnIndex = null;
          }
        });
      }
    }).catchError((_) {
      // 接口异常时保留本地兜底列
    });
  }

  static num _toNum(dynamic v, {num fallback = 0}) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? fallback;
  }

  // ==================== 数据加载 ====================

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);

    return request(HttpApi.vipTableGetVipCardDetailList, {
      'is_page': 1,
      'field': _sortField,
      'type': _sortType,
      'cond': _cond,
      'page': _page,
      'pagesize': _pageSize,
      'opertype': '8', // 操作类型：收款
      'sids': _sids.isEmpty ? null : _sids,
      'sidsname': _storeName,
      'starttime': '${_fmtDate(_startDate)} 00:00:00',
      'endtime': '${_fmtDate(_endDate)} 23:59:59',
      'typeid': _typeid,
      'typename': _typename,
      'userid': _userid,
      'username': _username,
      'cashid': _cashid,
      'cashname': _cashname,
    }).then((result) {
      final dynamic data = result['data'];
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final list = (map['list'] as List?) ?? [];
      final rows = list.cast<Map<String, dynamic>>();
      setState(() {
        if (_page == 1) {
          _list = rows;
        } else {
          _list.addAll(rows);
        }
        _hasMore = rows.length >= _pageSize;
        _hasLoadedOnce = true;
        final dynamic sumdata = map['sumdata'];
        _sumdata = sumdata is Map ? sumdata.cast<String, dynamic>() : <String, dynamic>{};
        _totalCount = int.tryParse(map['total']?.toString() ?? '') ?? 0;
      });
    }).catchError((_) {
      setState(() => _hasMore = false);
    }).whenComplete(() {
      setState(() => _loading = false);
    });
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  /// 条件变更后重新加载（对齐 record.vue retParam）
  void _reload() {
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification &&
        notification.metrics.axis == Axis.vertical &&
        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
    return false;
  }

  // ==================== 门店 / 时间 ====================

  Future<void> _selectStore() async {
    final result = await SelectStorePage.show(
      context,
      showAll: true,
      initialSelectedId: _activeStoreId,
    );
    if (result != null && mounted) {
      final String storeId = result['storeid']?.toString() ?? '';
      setState(() {
        _activeStoreId = storeId;
        _sids = storeId.isNotEmpty ? [storeId] : [];
        _storeName = result['storename']?.toString() ?? '';
      });
      _reload();
    }
  }

  Widget _buildTimeSelector() {
    final labels = ['昨天', '今日', '本周', '本月', '自定义'];
    final activeId = _activeQuickTimeId ?? 1;
    const primary = Color(0xFF006EFF);
    const onSurface = Color(0xFF333333);
    const borderColor = Color(0xFFD1D5DB);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        children: [
          // ── 分段控制器：昨天 今日 本周 本月 自定义 ──
          Container(
            height: 37,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: List.generate(labels.length, (i) {
                final selected = activeId == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onQuickTimeSelect(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? Colors.white : onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          // ── 日期导航行 ──
          _buildDateNavigation(),
        ],
      ),
    );
  }

  void _onQuickTimeSelect(int id) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (id) {
      case 0: // 昨天
        start = now.subtract(const Duration(days: 1));
        end = start;
        break;
      case 1: // 今天
        start = now;
        end = now;
        break;
      case 2: // 本周
        final weekday = now.weekday;
        start = now.subtract(Duration(days: weekday - 1));
        end = start.add(const Duration(days: 6));
        break;
      case 3: // 本月
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      default: // 自定义
        start = _startDate;
        end = _endDate;
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
      _activeQuickTimeId = id;
    });
    _reload();
  }

  Widget _buildDateNavigation() {
    final isRange = _activeQuickTimeId == 2 || _activeQuickTimeId == 4;
    final isMonth = _activeQuickTimeId == 3;
    final showArrows = _activeQuickTimeId != 4;

    return Row(
      children: [
        // 左箭头
        if (showArrows)
          GestureDetector(
            onTap: () => _timeShift(-1),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF666666)),
            ),
          ),
        if (showArrows) const SizedBox(width: 8),
        // 日期区域
        Expanded(
          child: Row(
            children: [
              if (isRange) ...[
                Expanded(child: _buildDatePart(_startDate, isStart: true)),
                _buildDateToSeparator(),
                Expanded(child: _buildDatePart(_endDate, isEnd: true)),
              ] else
                Expanded(
                  child: _buildDatePart(_startDate, isMonth: isMonth),
                ),
            ],
          ),
        ),
        if (showArrows) const SizedBox(width: 8),
        // 右箭头
        if (showArrows)
          GestureDetector(
            onTap: () => _timeShift(1),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D5DB)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF666666)),
            ),
          ),
      ],
    );
  }

  Widget _buildDatePart(DateTime date,
      {bool isStart = false, bool isEnd = false, bool isMonth = false}) {
    final String label =
        isMonth ? '${date.year}-${date.month.toString().padLeft(2, '0')}' : _fmtDate(date);

    Future<void> onTap() async {
      if (isMonth) {
        // 本月模式：只选年月
        final picked = await showCommonMonthPicker(context, initial: date);
        if (picked != null && mounted) {
          setState(() {
            _startDate = DateTime(picked.year, picked.month);
            _endDate = DateTime(picked.year, picked.month + 1, 0);
          });
          _reload();
        }
        return;
      }
      final picked = await showCommonDatePicker(context, initial: date);
      if (picked != null && mounted) {
        setState(() {
          if (isEnd) {
            _endDate = picked;
          } else if (isStart) {
            _startDate = picked;
          } else {
            // 单日模式：起止时间同步
            _startDate = picked;
            _endDate = picked;
          }
        });
        _reload();
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        margin: EdgeInsets.only(
          left: isStart ? 0 : 4,
          right: isEnd ? 0 : 4,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
      ),
    );
  }

  Widget _buildDateToSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Text('至',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
    );
  }

  void _timeShift(int direction) {
    final id = _activeQuickTimeId ?? 1;
    DateTime start = _startDate;
    DateTime end = _endDate;
    switch (id) {
      case 0: // 昨天 → ±1 day
      case 1: // 今天 → ±1 day
        start = start.add(Duration(days: direction));
        end = start;
        break;
      case 2: // 本周 → ±7 days
        start = start.add(Duration(days: 7 * direction));
        end = end.add(Duration(days: 7 * direction));
        break;
      case 3: // 本月 → ±1 month
        start = DateTime(_startDate.year, _startDate.month + direction);
        end = DateTime(start.year, start.month + 1, 0);
        break;
    }
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    _reload();
  }

  // ==================== 筛选抽屉 ====================

  void _openFilterSheet() {
    // ── 草稿筛选状态（取消丢弃、确定应用，对齐 record.vue filterDraft）──
    String tmpCond = _cond;
    String tmpTypeid = _typeid;
    String tmpTypename = _typename;
    String tmpUserid = _userid;
    String tmpUsername = _username;
    String tmpCashid = _cashid;
    String tmpCashname = _cashname;

    final condCtrl = TextEditingController(text: _cond);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // 标题栏
                  SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        const SizedBox(width: 48),
                        const Expanded(
                          child: Text(
                            '筛选',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
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
                  // 内容
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── 搜索框 ──
                          TextField(
                            controller: condCtrl,
                            onChanged: (v) => tmpCond = v,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '输入单号/会员卡号/会员姓名/会员手机号',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(left: 10, right: 6),
                                child: Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                              ),
                              prefixIconConstraints: const BoxConstraints(),
                              suffixIcon: tmpCond.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () {
                                        condCtrl.clear();
                                        setSheetState(() => tmpCond = '');
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 10),
                                        child:
                                            Icon(Icons.clear, size: 18, color: Color(0xFF9CA3AF)),
                                      ),
                                    )
                                  : null,
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
                            ),
                          ),
                          const SizedBox(height: 8),
                          // ── 会员分类 ──
                          _buildFilterRow(
                            label: '会员分类',
                            value: tmpTypename,
                            onTap: () => _pickVipType(
                              currentId: tmpTypeid,
                              onPicked: (id, name) => setSheetState(() {
                                tmpTypeid = id;
                                tmpTypename = name;
                              }),
                            ),
                          ),
                          // ── 业务员 ──
                          _buildFilterRow(
                            label: '业务员',
                            value: tmpUsername,
                            onTap: () => _pickStaff(
                              title: '选择业务员',
                              searchHint: '输入业务员名称/编码',
                              currentId: tmpUserid,
                              onPicked: (id, name) => setSheetState(() {
                                tmpUserid = id;
                                tmpUsername = name;
                              }),
                            ),
                          ),
                          // ── 收银员 ──
                          _buildFilterRow(
                            label: '收银员',
                            value: tmpCashname,
                            onTap: () => _pickStaff(
                              title: '选择收银员',
                              searchHint: '输入收银员名称/编码',
                              currentId: tmpCashid,
                              onPicked: (id, name) => setSheetState(() {
                                tmpCashid = id;
                                tmpCashname = name;
                              }),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // ── 底部按钮：取消 / 确定 ──
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(ctx),
                                  child: Container(
                                    height: 42,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFFD1D5DB)),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('取消',
                                        style: TextStyle(fontSize: 15, color: Color(0xFF374151))),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _cond = tmpCond;
                                      _typeid = tmpTypeid;
                                      _typename = tmpTypename;
                                      _userid = tmpUserid;
                                      _username = tmpUsername;
                                      _cashid = tmpCashid;
                                      _cashname = tmpCashname;
                                    });
                                    Navigator.pop(ctx);
                                    _reload();
                                  },
                                  child: Container(
                                    height: 42,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF006EFF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('确定',
                                        style: TextStyle(fontSize: 15, color: Colors.white)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE6E6E6))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : '全部',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: value.isNotEmpty ? const Color(0xFF333333) : const Color(0xFF9CA3AF),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  /// 会员分类选择（对齐 selectCom.vue：vipType/getVipTypeList + sids）
  Future<void> _pickVipType({
    required String currentId,
    required void Function(String id, String name) onPicked,
  }) async {
    final result = await CommonSelectSheet.show(
      context,
      title: '选择会员分类',
      searchHint: '输入会员分类名称/编码',
      fetchData: (search, page) async {
        final r = await request(HttpApi.vipTypeGetVipTypeList, {
          'is_page': 1,
          'page': page,
          'pagesize': 50,
          'sids': _sids.isEmpty ? null : _sids,
          if (search.isNotEmpty) 'cond': search,
        });
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      },
      idField: 'typeid',
      showAll: true,
      initialSelectedId: currentId.isNotEmpty ? currentId : null,
      mapResult: (item) {
        final code = item['code']?.toString() ?? '';
        final name = item['name']?.toString() ?? '';
        return {
          'typeid': item['typeid']?.toString() ?? '',
          'name': code.isNotEmpty ? '[$code]$name' : name,
        };
      },
    );
    if (result != null) {
      onPicked(result['typeid']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }

  /// 业务员/收银员选择（对齐 selectCom.vue：sysuser/findList）
  Future<void> _pickStaff({
    required String title,
    required String searchHint,
    required String currentId,
    required void Function(String id, String name) onPicked,
  }) async {
    final result = await CommonSelectSheet.show(
      context,
      title: title,
      searchHint: searchHint,
      fetchData: (search, page) async {
        final r = await request(HttpApi.sysUserList, {
          'is_page': 1,
          'page': page,
          'pagesize': 50,
          'cond': search,
        });
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      },
      idField: 'userid',
      showAll: true,
      initialSelectedId: currentId.isNotEmpty ? currentId : null,
      mapResult: (item) {
        final code = item['code']?.toString() ?? '';
        final name = item['name']?.toString() ?? '';
        return {
          'userid': item['userid']?.toString() ?? '',
          'name': code.isNotEmpty ? '[$code]$name' : name,
        };
      },
    );
    if (result != null) {
      onPicked(result['userid']?.toString() ?? '', result['name']?.toString() ?? '');
    }
  }

  // ==================== 排序 / 放大 ====================

  void _onSort(int columnIndex, bool ascending, _RecordColumn col) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _sortField = col.name;
      _sortType = ascending ? 'asc' : 'desc';
    });
    _reload();
  }

  /// 打开放大表格（对齐 record.vue amplifyFn）
  void _openAmplify() {
    NavigatorUtils.push(
      context,
      VippayRecordRouter.vippayRecordAmplify,
      arguments: <String, dynamic>{
        'field': _sortField,
        'type': _sortType,
        'cond': _cond,
        'opertype': '8',
        'sids': _sids,
        'sidsname': _storeName,
        'starttime': _fmtDate(_startDate),
        'endtime': _fmtDate(_endDate),
        'typeid': _typeid,
        'typename': _typename,
        'userid': _userid,
        'username': _username,
        'cashid': _cashid,
        'cashname': _cashname,
      },
    );
  }

  // ==================== build ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: true,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '收款记录',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                children: [
                  // ── 门店选择下拉（占满宽度）──
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStore,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDEDEDE)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _storeName.isNotEmpty ? _storeName : '演示门店',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF666666)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // ── 筛选按钮 ──
                  GestureDetector(
                    onTap: _openFilterSheet,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDEDEDE)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const BossSvgIcon(
                        svgFile: 'fliter.svg',
                        size: 22,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildTimeSelector(),
          if (_list.isEmpty && !_loading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                    SizedBox(height: 12),
                    Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
            )
          else if (_list.isEmpty && _hasLoadedOnce)
            // 已加载过、无数据且刷新中：保留空态 + 居中图标卡片，避免表格骨架闪屏
            const Expanded(
              child: Stack(children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFD1D5DB)),
                      SizedBox(height: 12),
                      Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
                _loadingCard,
              ]),
            )
          else ...[
            _buildSummaryBar(),
            Expanded(
              child: Stack(children: [
                _buildTableArea(),
                if (_loading && _hasLoadedOnce && _page == 1) _loadingCard,
              ]),
            ),
          ],
        ],
      ),
    );
  }

  /// 居中加载图标卡片（无全屏遮罩，避免加载中页面泛白）
  static const Widget _loadingCard = Positioned.fill(
    child: Center(
      child: SizedBox(
        width: 72,
        height: 72,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border.fromBorderSide(BorderSide(color: Color(0xFFE1E9F3))),
          ),
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF)),
            ),
          ),
        ),
      ),
    ),
  );

  // ==================== 统计栏 ====================

  String get _totalAmountText {
    final dynamic v = _sumdata['addmoney'] ?? _sumdata['amt'] ?? 0;
    return MathUtils.formatDecimal(3, v);
  }

  Widget _buildSummaryBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
          children: [
            const TextSpan(text: '单据数量：'),
            TextSpan(
              text: '$_totalCount',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333)),
            ),
            const TextSpan(text: '   总金额：'),
            TextSpan(
              text: _totalAmountText,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333)),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 表格 ====================

  /// 表格区域：DataTable2 — 固定单号列 + 横向滚动 + 表头排序
  Widget _buildTableArea() {
    const headerStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF374151),
    );
    final double totalWidth = _columns.fold(0.0, (sum, c) => sum + c.width);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: RefreshIndicator(
        color: const Color(0xFF006EFF),
        onRefresh: _onRefresh,
        child: DataTable2(
          fixedLeftColumns: 1,
          minWidth: math.max(totalWidth, 1.0),
          horizontalMargin: 0,
          columnSpacing: 0,
          dataRowHeight: 52,
          headingRowHeight: 44,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F0FE)),
          border: const TableBorder(
            horizontalInside: BorderSide(color: Color(0xFFE1E9F3)),
            verticalInside: BorderSide(color: Color(0xFFE1E9F3)),
          ),
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          columns: [
            for (var i = 0; i < _columns.length; i++) _buildColumn(i, _columns[i], headerStyle),
          ],
          rows: [
            for (var i = 0; i < _list.length; i++) _buildDataRow(_list[i], i),
            // 加载行：仅加载更多或首次加载时显示（刷新时由居中图标卡片提示）
            if (_loading && (_page > 1 || !_hasLoadedOnce))
              DataRow(cells: [
                const DataCell(SizedBox(
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
                    ),
                  ),
                )),
                for (var i = 1; i < _columns.length; i++) DataCell.empty,
              ]),
          ],
        ),
      ),
    );
  }

  DataColumn2 _buildColumn(int index, _RecordColumn col, TextStyle headerStyle) {
    return DataColumn2(
      fixedWidth: col.width,
      label: Align(
        alignment: col.align == 'right' ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            col.label,
            style: headerStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      onSort:
          col.sortable ? (columnIndex, ascending) => _onSort(columnIndex, ascending, col) : null,
    );
  }

  DataRow2 _buildDataRow(Map<String, dynamic> row, int index) {
    final bool isOdd = index.isOdd;
    return DataRow2(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF9F9F9) : Colors.white,
        border: const Border(
          right: BorderSide(color: Color(0xFFE1E9F3)),
        ),
      ),
      cells: [
        for (final col in _columns) _buildCell(col, row),
      ],
    );
  }

  DataCell _buildCell(_RecordColumn col, Map<String, dynamic> row) {
    // 单号列：蓝色文本 + 放大图标（对齐 record.vue billno 列 icon 放大入口）
    if (col.name == 'billno') {
      final String billno = row['billno']?.toString() ?? '';
      return DataCell(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  billno.isEmpty ? '--' : billno,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF006EFF)),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openAmplify,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: Icon(Icons.zoom_out_map, size: 15, color: Color(0xFF848484)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DataCell(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: col.align == 'right' ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            _cellText(col, row),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
          ),
        ),
      ),
    );
  }

  /// 单元格文本（fietype >= 2 的数值列走 formatDecimal 格式化，对齐 zb-table）
  static String _cellText(_RecordColumn col, Map<String, dynamic> row) {
    final dynamic raw = row[col.name];
    if (col.fietype != null) {
      return MathUtils.formatDecimal(col.fietype!, raw ?? 0);
    }
    final String text = raw?.toString() ?? '';
    return text.isEmpty ? '--' : text;
  }
}

/// 列表列配置（对齐 record.vue buildColumns 输出结构）
class _RecordColumn {
  const _RecordColumn({
    required this.name,
    required this.label,
    required this.align,
    required this.width,
    this.fietype,
    this.sortable = false,
  });

  final String name;
  final String label;

  /// 对齐方式：left / right
  final String align;
  final double width;

  /// 数值格式化类型（>=2 时触发 formatDecimal）
  final int? fietype;
  final bool sortable;
}
