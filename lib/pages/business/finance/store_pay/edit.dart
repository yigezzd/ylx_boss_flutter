import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/date_range_picker.dart';
import 'package:sp_util/sp_util.dart';

/// 门店结算单编辑页 —— 对齐 boss 项目 storePlierpayEdit.vue
class StorePayEditPage extends StatefulWidget {
  const StorePayEditPage({super.key, this.billid = ''});

  /// 单据ID，为空表示新增
  final String billid;

  @override
  State<StorePayEditPage> createState() => _StorePayEditPageState();
}

class _StorePayEditPageState extends State<StorePayEditPage> {
  // ── 状态 ──
  bool _loading = false;

  /// 获取账单列表的独立加载状态（避免新增模式 _formData 为空时触发全屏白屏）
  bool _billLoading = false;
  bool _saving = false;
  Map<String, dynamic> _formData = {};
  List<Map<String, dynamic>> _detaillist = [];
  List<Map<String, dynamic>> _allBills = [];

  // ── 多级审批 ──
  List<Map<String, dynamic>> _reviewFlowUsers = [];
  List<Map<String, dynamic>> _reviewBillFlows = [];
  String _userCode = '';
  String _userid = '';

  // ── 表单字段 ──
  String _bsid = ''; // 应付门店ID
  String _bstorename = ''; // 应付门店名称
  String _sid = ''; // 应收门店ID
  String _storename = ''; // 应收门店名称
  String _handlerid = '';
  String _handlername = '';
  String _startdate = '';
  String _enddate = '';
  String _bankid = ''; // 收款账户ID
  String _bankname = ''; // 收款账户名称
  String _bankidother = ''; // 付款账户ID
  String _bankidothername = ''; // 付款账户名称
  String _payway = '';
  String _paywayname = '';
  String _advance = '';

  // ── 汇总字段 ──
  String _prepayamt = '0.000';
  String _payamt = '';
  String _freeamt = '';
  String _prepaidamt = '';
  String _billnum = '';
  String _billamt = '';

  // ── Controllers ──
  final TextEditingController _remarkCtl = TextEditingController();
  final TextEditingController _payamtCtl = TextEditingController();
  final TextEditingController _freeamtCtl = TextEditingController();
  final TextEditingController _prepaidamtCtl = TextEditingController();

  // ── FocusNodes（失焦触发计算，对齐 Vue @blur）──
  late final FocusNode _payamtFocus = FocusNode()
    ..addListener(() {
      if (!_payamtFocus.hasFocus && mounted) _settleConfirm('payamt');
    });
  late final FocusNode _freeamtFocus = FocusNode()
    ..addListener(() {
      if (!_freeamtFocus.hasFocus && mounted) _settleConfirm('freeamt');
    });
  late final FocusNode _prepaidamtFocus = FocusNode()
    ..addListener(() {
      if (!_prepaidamtFocus.hasFocus && mounted) _settleConfirm('prepaidamt');
    });

  // ── 枚举 ──
  int get _signflag => int.tryParse(_formData['signflag']?.toString() ?? '') ?? 0;
  bool get _isEdit =>
      widget.billid.isNotEmpty || (_formData['billid']?.toString().isNotEmpty ?? false);
  bool get _isReadonly => _signflag == 1 || _signflag == 2 || _signflag == -1;
  String get _billno => _formData['billno']?.toString() ?? '';

  // ── 多级审批计算属性 ──
  bool get _isAdmin => _userCode == '1001';

  bool get _bolHandleT {
    if (_isAdmin) return true;
    return _reviewFlowUsers.any((item) => item['userid']?.toString() == _userid);
  }

  bool get _bolHandleTT {
    if (_isAdmin) return true;
    if (_reviewFlowUsers.isEmpty) return true;
    final firstIndex = int.tryParse(_reviewFlowUsers[0]['index']?.toString() ?? '0') ?? 0;
    return firstIndex <= 1;
  }

  // ignore: unused_element
  bool get _bolHandleTTT {
    if (_isAdmin) return true;
    if (_reviewFlowUsers.isEmpty) {
      if (_reviewBillFlows.isEmpty) return true;
      return _reviewBillFlows.any((item) => item['userid']?.toString() == _userid);
    }
    return _reviewBillFlows.any((item) => item['userid']?.toString() == _userid);
  }

  bool get _isWithdrawPending => _formData['reviewsignflag']?.toString() == '2';

  @override
  void initState() {
    super.initState();
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _userid = userMap['userid']?.toString() ?? '';
        _userCode = userMap['code']?.toString() ?? '';
      }
    } catch (_) {}
    if (_isEdit) _loadData();
  }

  @override
  void dispose() {
    _remarkCtl.dispose();
    _payamtCtl.dispose();
    _freeamtCtl.dispose();
    _prepaidamtCtl.dispose();
    _payamtFocus.dispose();
    _freeamtFocus.dispose();
    _prepaidamtFocus.dispose();
    super.dispose();
  }

  // =================== 数据加载 ===================

  Future<void> _loadData() async {
    if (_loading) return;
    final billid =
        widget.billid.isNotEmpty ? widget.billid : (_formData['billid']?.toString() ?? '');
    if (billid.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await request(HttpApi.financeStorePayGetInfo, {'billid': billid});
      final data = res['data'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() {
          _formData = Map<String, dynamic>.from(data);
          final flowList = data['detaillist'] as List? ?? [];
          _detaillist = flowList
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          // 同步表单字段
          _bsid = _str(data['bsid']);
          _bstorename = _str(data['bstorename']);
          _sid = _str(data['sid']);
          _storename = _str(data['storename']);
          _handlerid = _str(data['handlerid']);
          _handlername = _str(data['handlername']);
          _bankid = _str(data['bankid']);
          _bankname = _str(data['bankname']);
          _bankidother = _str(data['bankidother']);
          _bankidothername = _str(data['bankidothername']);
          _payway = _str(data['payway']);
          _paywayname = _str(data['paywayname']);
          _advance = _str(data['advance']);
          _remarkCtl.text = _str(data['remark']);
          _payamtCtl.text = _str(data['payamt']);
          _freeamtCtl.text = _str(data['freeamt']);
          _prepaidamtCtl.text = _str(data['prepaidamt']);
          _payamt = _str(data['payamt']);
          _freeamt = _str(data['freeamt']);
          _prepaidamt = _str(data['prepaidamt']);
          _startdate = _str(data['startdate']).split(' ').first;
          _enddate = _str(data['enddate']).split(' ').first;
          // 初始化每条明细
          for (int i = 0; i < _detaillist.length; i++) {
            _initBillInfo(_detaillist[i], i);
          }
          // 汇总
          final sumData = _sumFields(_detaillist, [
            'billamt',
            'paidamt',
            'freetotalamt',
            'prepaidtotalamt',
            'nowamt',
            'payamt',
            'freeamt',
            'prepaidamt',
            'debtamt',
            'prepayamt'
          ]);
          _prepayamt = sumData['prepayamt']?.toString() ?? '0.000';
          _billnum = sumData['billnum']?.toString() ?? '';
          _billamt = sumData['billamt']?.toString() ?? '';
          // 汇总后覆盖付款金额/本次免付/预付结算（对齐 Vue: query = {...query, ...sumdata}）
          _payamt = sumData['payamt']?.toString() ?? '';
          _freeamt = sumData['freeamt']?.toString() ?? '';
          _prepaidamt = sumData['prepaidamt']?.toString() ?? '';
          _payamtCtl.text = _payamt;
          _freeamtCtl.text = _freeamt;
          _prepaidamtCtl.text = _prepaidamt;
          _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
          _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
        });
      }
    } catch (_) {
      if (mounted) Toast.show('加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =================== 选择器 ===================

  /// 应付门店（storetypes=[1,2], stopflag=0, 排除应收门店）
  Future<void> _selectStoreOut() async {
    final excludeId = _sid;
    final result = await CommonSelectSheet.show(
      context,
      title: '选择应付门店',
      searchHint: '输入门店名称/编码',
      fetchData: (search, page) {
        final params = <String, dynamic>{
          'storetypes': [1, 2],
          'stopflag': 0,
          'cond': search,
          'is_page': 1,
          'page': page,
          'pagesize': 20,
          if (excludeId.isNotEmpty) 'nostoreid': excludeId,
        };
        return request(HttpApi.storeGetList, params).then((r) {
          final data = r['data'];
          return data is Map<String, dynamic> ? data : null;
        });
      },
      mapResult: (item) => {
        'storeid': item['id']?.toString() ?? '',
        'storename': item['name']?.toString() ?? '',
      },
      initialSelectedId: _bsid,
    );
    if (result != null && mounted) {
      setState(() {
        _bsid = result['storeid']?.toString() ?? '';
        _bstorename = result['storename']?.toString() ?? '';
      });
      if (_bsid.isNotEmpty && _sid.isNotEmpty) _fetchStoreBill();
    }
  }

  /// 应收门店（storetypes=[0,3], psselecttype=2, sids=[bsid], nosidsflag=1, 排除应付门店）
  Future<void> _selectStoreIn() async {
    final currentBsid = _bsid;
    if (currentBsid.isEmpty) {
      Toast.show('请先选择应付门店');
      return;
    }
    final excludeId = _bsid;
    final result = await CommonSelectSheet.show(
      context,
      title: '选择应收门店',
      searchHint: '输入门店名称/编码',
      fetchData: (search, page) {
        final params = <String, dynamic>{
          'storetypes': [0, 3],
          'sids': [currentBsid],
          'psselecttype': 2,
          'nosidsflag': 1,
          'cond': search,
          'is_page': 1,
          'page': page,
          'pagesize': 20,
          if (excludeId.isNotEmpty) 'nostoreid': excludeId,
        };
        return request(HttpApi.storeGetList, params).then((r) {
          final data = r['data'];
          return data is Map<String, dynamic> ? data : null;
        });
      },
      mapResult: (item) => {
        'storeid': item['id']?.toString() ?? '',
        'storename': item['name']?.toString() ?? '',
      },
      initialSelectedId: _sid,
    );
    if (result != null && mounted) {
      setState(() {
        _sid = result['storeid']?.toString() ?? '';
        _storename = result['storename']?.toString() ?? '';
      });
      if (_bsid.isNotEmpty && _sid.isNotEmpty) _fetchStoreBill();
    }
  }

  Future<void> _selectBills() async {
    final isNew = !_isEdit;
    if (isNew) {
      if (_bsid.isEmpty) {
        Toast.show('请先选择应付门店');
        return;
      }
      if (_sid.isEmpty) {
        Toast.show('请先选择应收门店');
        return;
      }
    }
    final result = await showModalBottomSheet<
        (List<Map<String, dynamic>>, List<Map<String, dynamic>>, String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => !isNew
          ? _buildBillViewSheet(ctx)
          : SafeArea(
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.85,
                decoration: const BoxDecoration(
                    color: Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                child: _StoreSelectBillSheet(
                  bills: _allBills,
                  selectedIds: _detaillist.map((e) => e['sbillid']?.toString() ?? '').toSet(),
                  advance: _advance,
                  bsid: _bsid,
                  sid: _sid,
                  initialLoading: _billLoading,
                  initialStart: _startdate,
                  initialEnd: _enddate,
                ),
              ),
            ),
    );
    if (result != null && mounted) {
      setState(() {
        // 弹窗返回：选中单据、最新全量数据、弹窗内日期范围（与编辑页日期范围互相关联）
        _detaillist = result.$1;
        _allBills = result.$2;
        _startdate = result.$3;
        _enddate = result.$4;
        final sumData = _sumFields(_detaillist, [
          'billamt',
          'paidamt',
          'freetotalamt',
          'prepaidtotalamt',
          'nowamt',
          'payamt',
          'freeamt',
          'prepaidamt',
          'debtamt',
          'prepayamt'
        ]);
        _prepayamt = sumData['prepayamt']?.toString() ?? '0.000';
        _billnum = sumData['billnum']?.toString() ?? '';
        _billamt = sumData['billamt']?.toString() ?? '';
        // 新增模式：对齐 Vue onSelectBill 后 sumFields 覆盖，不自动分配（blur 时才结算）
        if (!_isEdit) {
          _payamt = _prepayamt;
          _payamtCtl.text = _prepayamt;
          _freeamt = MathUtils.formatDecimal(3, 0);
          _freeamtCtl.text = _freeamt;
          _prepaidamt = sumData['prepaidamt']?.toString() ?? '0.000';
          _prepaidamtCtl.text = _prepaidamt;
        }
      });
    }
  }

  Future<void> _selectDateRange() async {
    // 日期范围：范围日历弹窗（点两次选开始/结束，一次确认）
    final range = await showDateRangeCalendarPicker(
      context,
      initialStart: _startdate.isNotEmpty ? DateTime.tryParse(_startdate) : null,
      initialEnd: _enddate.isNotEmpty ? DateTime.tryParse(_enddate) : null,
    );
    if (range == null || !mounted) return;
    setState(() {
      _startdate = _fmtDate(range.$1);
      _enddate = _fmtDate(range.$2);
    });
    if (_bsid.isNotEmpty && _sid.isNotEmpty) _fetchStoreBill();
  }

  Future<void> _selectHandler() async {
    final result = await CommonSelectSheet.show(
      context,
      title: '选择经手人',
      searchHint: '输入经手人名称/编码',
      fetchData: (search, page) => request(HttpApi.sysUserList, {
        'cond': search,
        'is_page': 1,
        'page': page,
        'pagesize': 20,
      }).then((r) {
        final data = r['data'];
        return data is Map<String, dynamic> ? data : null;
      }),
      idField: 'userid',
      showAll: true,
      initialSelectedId: _handlerid,
    );
    if (result != null && mounted) {
      setState(() {
        _handlerid = result['userid']?.toString() ?? '';
        _handlername = result['name']?.toString() ?? '';
      });
    }
  }

  /// 收款账户
  Future<void> _selectBank() async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      context,
      title: '选择收款账户',
      searchHint: '输入账户名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.pluginsGet, {
            'plugins': ['bank'],
          });
          final data = r['data'];
          if (data is Map<String, dynamic> && data['bank'] is Map<String, dynamic>) {
            final bk = data['bank'] as Map<String, dynamic>;
            cache = ((bk['list'] as List?) ?? []).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'bankid',
      showAll: true,
      initialSelectedId: _bankid,
    );
    if (result != null && mounted) {
      setState(() {
        _bankid = result['bankid']?.toString() ?? '';
        _bankname = result['name']?.toString() ?? '';
      });
    }
  }

  /// 付款账户
  Future<void> _selectBankOther() async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      context,
      title: '选择付款账户',
      searchHint: '输入账户名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.pluginsGet, {
            'plugins': ['bank'],
          });
          final data = r['data'];
          if (data is Map<String, dynamic> && data['bank'] is Map<String, dynamic>) {
            final bk = data['bank'] as Map<String, dynamic>;
            cache = ((bk['list'] as List?) ?? []).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'bankid',
      showAll: true,
      initialSelectedId: _bankidother,
    );
    if (result != null && mounted) {
      setState(() {
        _bankidother = result['bankid']?.toString() ?? '';
        _bankidothername = result['name']?.toString() ?? '';
      });
    }
  }

  Future<void> _selectPayway() async {
    List<Map<String, dynamic>>? cache;
    final result = await CommonSelectSheet.show(
      context,
      title: '选择付款方式',
      searchHint: '输入付款方式名称',
      fetchData: (search, page) async {
        if (cache == null) {
          final r = await request(HttpApi.pluginsGet, {
            'buseflag': 1,
            'paywayParams': {'name': ''},
            'plugins': ['payway'],
          });
          final data = r['data'];
          if (data is Map<String, dynamic> && data['payway'] is Map<String, dynamic>) {
            final pw = data['payway'] as Map<String, dynamic>;
            cache = ((pw['list'] as List?) ?? []).cast<Map<String, dynamic>>();
          } else {
            cache = [];
          }
        }
        final filtered = search.isEmpty
            ? cache!
            : cache!.where((e) => (e['name'] ?? '').toString().contains(search)).toList();
        return <String, dynamic>{'list': filtered, 'has_more': false};
      },
      idField: 'payid',
      showAll: true,
      initialSelectedId: _payway,
    );
    if (result != null && mounted) {
      setState(() {
        _payway = result['payid']?.toString() ?? '';
        _paywayname = result['name']?.toString() ?? '';
      });
    }
  }

  // =================== 获取门店账单 ===================

  Future<void> _fetchStoreBill() async {
    _allBills = [];
    setState(() => _billLoading = true);
    try {
      final res = await request(
          HttpApi.financeStorePayGetStoreBill,
          {
            'is_page': 0,
            'bsid': _bsid,
            'sid': _sid,
            'starttime': _startdate.isNotEmpty ? '$_startdate 00:00:00' : '',
            'endtime': _enddate.isNotEmpty ? '$_enddate 23:59:59' : '',
          },
          false,
          false);
      final data = res['data'];
      if (data is List && mounted) {
        final bills = data
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final money = bills.isNotEmpty ? (bills[0]['advance'] ?? 0) : 0;
        _comBillList(bills, money);
        _allBills = bills;
        setState(() {
          _advance = money?.toString() ?? '';
          _detaillist = bills;
          final sumData = _sumFields(_detaillist, [
            'billamt',
            'paidamt',
            'freetotalamt',
            'prepaidtotalamt',
            'nowamt',
            'payamt',
            'freeamt',
            'prepaidamt',
            'debtamt',
            'prepayamt'
          ]);
          _prepayamt = sumData['prepayamt']?.toString() ?? '0.000';
          _billnum = sumData['billnum']?.toString() ?? '';
          _billamt = sumData['billamt']?.toString() ?? '';
          // 新增模式：对齐 Vue getStoreBill 后 sumFields 覆盖（付款金额=本次应付合计、
          // 预付结算=预付款分配总额），不自动分配到明细（Vue 仅在输入框 blur 时 settleConfirm）
          if (!_isEdit) {
            _payamt = _prepayamt;
            _payamtCtl.text = _prepayamt;
            _freeamt = MathUtils.formatDecimal(3, 0);
            _freeamtCtl.text = _freeamt;
            _prepaidamt = sumData['prepaidamt']?.toString() ?? '0.000';
            _prepaidamtCtl.text = _prepaidamt;
          }
        });
      } else if (mounted) {
        Toast.show('该门店没有账单，请重新选择');
        setState(() {
          _detaillist = [];
          _allBills = [];
          _billnum = '';
          _billamt = '';
        });
      }
    } catch (e) {
      if (mounted) {
        // 提示接口返回的 retmsg（_ApiException.toString 即 retmsg 文案）
        Toast.show(e.toString());
        setState(() {
          _detaillist = [];
          _allBills = [];
          _billnum = '';
          _billamt = '';
        });
      }
    } finally {
      if (mounted) setState(() => _billLoading = false);
    }
  }

  // =================== 结算计算逻辑（对齐 Vue calculatePayment） ===================

  void _settleConfirm(String type) {
    final value = type == 'payamt'
        ? _payamtCtl.text
        : type == 'freeamt'
            ? _freeamtCtl.text
            : _prepaidamtCtl.text;
    final result = _calculatePayment(
        double.tryParse(value) ?? 0,
        {
          'nowamt': double.tryParse(_prepayamt) ?? 0,
          'freeamt': double.tryParse(_freeamt) ?? 0,
          'prepaidamt': double.tryParse(_prepaidamt) ?? 0,
          'payamt': double.tryParse(_payamt) ?? 0,
        },
        type);
    setState(() {
      _freeamt = MathUtils.formatDecimal(3, result['freeamt']);
      _prepaidamt = MathUtils.formatDecimal(3, result['prepaidamt']);
      _payamt = MathUtils.formatDecimal(3, result['payamt']);
      _freeamtCtl.text = _freeamt;
      _prepaidamtCtl.text = _prepaidamt;
      _payamtCtl.text = _payamt;
    });
    // 分配到每条明细
    double payamt = double.tryParse(_payamt) ?? 0;
    double freeamt = double.tryParse(_freeamt) ?? 0;
    double prepaidamt = double.tryParse(_prepaidamt) ?? 0;
    for (final item in _detaillist) {
      item['payamt'] = 0;
      item['freeamt'] = 0;
      item['prepaidamt'] = 0;
      final nowamt = double.tryParse(item['nowamt']?.toString() ?? '') ?? 0;
      if (payamt >= nowamt) {
        item['payamt'] = nowamt;
        payamt -= nowamt;
      } else {
        item['payamt'] = payamt;
        payamt = 0;
        final shengyu = nowamt - (double.tryParse(item['payamt']?.toString() ?? '') ?? 0);
        if (freeamt >= shengyu) {
          item['freeamt'] = shengyu;
          freeamt -= shengyu;
        } else {
          item['freeamt'] = freeamt;
          freeamt = 0;
          final shengyu2 = nowamt -
              ((double.tryParse(item['payamt']?.toString() ?? '') ?? 0) +
                  (double.tryParse(item['freeamt']?.toString() ?? '') ?? 0));
          if (prepaidamt >= shengyu2) {
            item['prepaidamt'] = shengyu2;
            prepaidamt -= shengyu2;
          } else {
            item['prepaidamt'] = prepaidamt;
            prepaidamt = 0;
          }
        }
      }
      final totalPay = (double.tryParse(item['freeamt']?.toString() ?? '') ?? 0) +
          (double.tryParse(item['prepaidamt']?.toString() ?? '') ?? 0) +
          (double.tryParse(item['payamt']?.toString() ?? '') ?? 0);
      item['debtamt'] = MathUtils.formatDecimal(3, nowamt - totalPay);
      item['freeamt'] = MathUtils.formatDecimal(3, item['freeamt']);
      item['prepaidamt'] = MathUtils.formatDecimal(3, item['prepaidamt']);
      item['payamt'] = MathUtils.formatDecimal(3, item['payamt']);
      final billAmt = double.tryParse(item['billamt']?.toString() ?? '') ?? 0;
      final paidamt = double.tryParse(item['paidamt']?.toString() ?? '') ?? 0;
      final freetotalamt = double.tryParse(item['freetotalamt']?.toString() ?? '') ?? 0;
      final prepaidtotalamt = double.tryParse(item['prepaidtotalamt']?.toString() ?? '') ?? 0;
      item['prepayamt'] =
          MathUtils.formatDecimal(3, billAmt - paidamt - freetotalamt - prepaidtotalamt);
    }
    setState(() {});
  }

  Map<String, double> _sumFields(List<Map<String, dynamic>> arr, List<String> fields) {
    if (arr.isEmpty) {
      return {for (final f in fields) f: 0, 'billnum': 0};
    }
    final result = <String, double>{'billnum': arr.length.toDouble()};
    for (final field in fields) {
      result[field] = 0;
    }
    for (final item in arr) {
      for (final field in fields) {
        result[field] =
            (result[field] ?? 0) + (double.tryParse(item[field]?.toString() ?? '') ?? 0);
      }
    }
    for (final field in fields) {
      result[field] = double.tryParse(MathUtils.formatDecimal(3, result[field] ?? 0)) ?? 0;
    }
    return result;
  }

  static Map<String, double> _calculatePayment(double nowPayAmt, Map<String, dynamic> data,
      [String type = 'payamt']) {
    final double nowamt = double.tryParse(data['nowamt']?.toString() ?? '') ?? 0;
    double freeamt = double.tryParse(data['freeamt']?.toString() ?? '') ?? 0;
    double prepaidamt = double.tryParse(data['prepaidamt']?.toString() ?? '') ?? 0;
    double payamt = double.tryParse(data['payamt']?.toString() ?? '') ?? 0;

    final isRefundMode = nowamt < 0;
    if (isRefundMode && nowPayAmt > 0) nowPayAmt = 0;

    if (type == 'payamt')
      payamt = nowPayAmt;
    else if (type == 'freeamt')
      freeamt = nowPayAmt;
    else if (type == 'prepaidamt') prepaidamt = nowPayAmt;

    double totalPay = payamt + freeamt + prepaidamt;
    final isOver = nowamt >= 0 ? totalPay > nowamt : totalPay < nowamt;

    if (isOver) {
      double overAmount = totalPay - nowamt;
      double adjustField(double field, String key) {
        if (type != key && field != 0 && overAmount != 0) {
          final reduce = min(field.abs(), overAmount.abs()) * field.sign;
          field -= reduce;
          overAmount -= reduce;
        }
        return field;
      }

      if (type != 'payamt') payamt = adjustField(payamt, 'payamt');
      if (type != 'prepaidamt') prepaidamt = adjustField(prepaidamt, 'prepaidamt');
      if (type != 'freeamt') freeamt = adjustField(freeamt, 'freeamt');
      if (type == 'payamt')
        payamt = nowamt - freeamt - prepaidamt;
      else if (type == 'freeamt')
        freeamt = nowamt - payamt - prepaidamt;
      else if (type == 'prepaidamt') prepaidamt = nowamt - payamt - freeamt;
    } else {
      final maxAllowed = nowamt -
          (type == 'payamt' ? 0 : payamt) -
          (type == 'freeamt' ? 0 : freeamt) -
          (type == 'prepaidamt' ? 0 : prepaidamt);
      final currentMain = {'payamt': payamt, 'freeamt': freeamt, 'prepaidamt': prepaidamt}[type]!;
      final exceeds = nowamt >= 0 ? currentMain > maxAllowed : currentMain < maxAllowed;
      if (exceeds) {
        if (type == 'payamt')
          payamt = maxAllowed;
        else if (type == 'freeamt')
          freeamt = maxAllowed;
        else if (type == 'prepaidamt') prepaidamt = maxAllowed;
      }
    }

    totalPay = payamt + freeamt + prepaidamt;
    final debtamt = nowamt - totalPay;
    return {'freeamt': freeamt, 'prepaidamt': prepaidamt, 'payamt': payamt, 'debtamt': debtamt};
  }

  void _comBillList(List<Map<String, dynamic>> arr, dynamic money) {
    double advance = double.tryParse(money?.toString() ?? '') ?? 0;
    for (final item in arr) {
      item['paidamt'] = item['payamt'];
      item['freetotalamt'] = item['freeamt'];
      item['prepaidtotalamt'] = item['prepaidamt'];
      item['sbillid'] = item['sbillid'] ?? item['billid'];
      item['sbillno'] = item['sbillno'] ?? item['billno'];
      item['sbilldate'] = item['sbilldate'] ?? item['billdate'];
      item['freeamt'] = MathUtils.formatDecimal(3, 0);
      item['prepaidamt'] = MathUtils.formatDecimal(3, 0);
      final billAmt = double.tryParse(item['billamt']?.toString() ?? '') ?? 0;
      final paidamt = double.tryParse(item['paidamt']?.toString() ?? '') ?? 0;
      final freetotalamt = double.tryParse(item['freetotalamt']?.toString() ?? '') ?? 0;
      final prepaidtotalamt = double.tryParse(item['prepaidtotalamt']?.toString() ?? '') ?? 0;
      final nowamt = billAmt - paidamt - freetotalamt - prepaidtotalamt;
      item['nowamt'] = nowamt;
      item['remark'] = '';
      if (advance > 0 && advance > nowamt) {
        item['prepaidamt'] = MathUtils.formatDecimal(3, nowamt);
        advance -= double.tryParse(item['prepaidamt']?.toString() ?? '') ?? 0;
      } else if (advance > 0 && advance < nowamt) {
        item['prepaidamt'] = MathUtils.formatDecimal(3, advance);
        advance = 0;
      }
      // 本次应付金额 = 单据金额 - 已付金额 - 免付金额 - 预付款金额（对齐 Vue settleConfirm）
      item['prepayamt'] =
          MathUtils.formatDecimal(3, billAmt - paidamt - freetotalamt - prepaidtotalamt);
      item['debtamt'] = MathUtils.formatDecimal(
          3, nowamt - (double.tryParse(item['prepaidamt']?.toString() ?? '') ?? 0));
      item['freeamt'] = MathUtils.formatDecimal(3, 0);
      item['payamt'] = MathUtils.formatDecimal(3, nowamt);
    }
  }

  void _initBillInfo(Map<String, dynamic> obj, int index) {
    obj['billamt'] = MathUtils.formatDecimal(3, obj['billamt'] ?? 0);
    obj['paidamt'] = MathUtils.formatDecimal(3, obj['paidamt'] ?? 0);
    obj['freetotalamt'] = MathUtils.formatDecimal(3, obj['freetotalamt'] ?? 0);
    obj['prepaidtotalamt'] = MathUtils.formatDecimal(3, obj['prepaidtotalamt'] ?? 0);
    final billAmt = double.tryParse(obj['billamt']?.toString() ?? '') ?? 0;
    final paidamt = double.tryParse(obj['paidamt']?.toString() ?? '') ?? 0;
    final freetotalamt = double.tryParse(obj['freetotalamt']?.toString() ?? '') ?? 0;
    final prepaidtotalamt = double.tryParse(obj['prepaidtotalamt']?.toString() ?? '') ?? 0;
    obj['nowamt'] = MathUtils.formatDecimal(3, billAmt - paidamt - freetotalamt - prepaidtotalamt);
    obj['payamt'] = MathUtils.formatDecimal(3, obj['payamt'] ?? 0);
    obj['freeamt'] = MathUtils.formatDecimal(3, obj['freeamt'] ?? 0);
    obj['prepaidamt'] = MathUtils.formatDecimal(3, obj['prepaidamt'] ?? 0);
    obj['prepayamt'] =
        MathUtils.formatDecimal(3, billAmt - paidamt - freetotalamt - prepaidtotalamt);
    obj['debtamt'] = MathUtils.formatDecimal(
        3,
        (double.tryParse(obj['prepayamt']?.toString() ?? '') ?? 0) -
            (double.tryParse(obj['payamt']?.toString() ?? '') ?? 0));
    obj['sbillid'] = obj['sbillid'] ?? obj['billid'];
    obj['sbillno'] = obj['sbillno'] ?? obj['billno'];
    obj['sbilldate'] = obj['sbilldate'] ?? obj['billdate'];
    obj['isort'] = index + 1;
  }

  // =================== 保存 / 审核 / 作废 / 删除 / 撤回 ===================

  Future<void> _handleSave([int sign = 0]) async {
    if (_isEdit) {
      if (!PermissionUtils.checkPermission('014603', showTip: false)) {
        Toast.show('你无权编辑门店结算，请在后台修改权限');
        return;
      }
    } else {
      if (!PermissionUtils.checkPermission('014602', showTip: false)) {
        Toast.show('你无权新增门店结算，请在后台修改权限');
        return;
      }
    }
    if (_saving) return;
    if (_detaillist.isEmpty) {
      Toast.show('请选择单据');
      return;
    }
    if (_bsid.isEmpty) {
      Toast.show('请选择应付门店');
      return;
    }
    if (_sid.isEmpty) {
      Toast.show('请选择应收门店');
      return;
    }
    if (_payway.isEmpty) {
      Toast.show('请选择付款方式');
      return;
    }
    if (_bankname.isEmpty) {
      Toast.show('请选择收款账户');
      return;
    }
    if (_bankidothername.isEmpty) {
      Toast.show('请选择付款账户');
      return;
    }

    setState(() => _saving = true);
    try {
      final params = <String, dynamic>{
        'bsid': _bsid,
        'bstorename': _bstorename,
        'sid': _sid,
        'storename': _storename,
        'handlerid': _handlerid,
        'handlername': _handlername,
        'remark': _remarkCtl.text.trim(),
        'bankid': _bankid,
        'bankname': _bankname,
        'bankidother': _bankidother,
        'bankidothername': _bankidothername,
        'payway': _payway,
        'paywayname': _paywayname,
        'startdate': _startdate.isNotEmpty ? '$_startdate 00:00:00' : '',
        'enddate': _enddate.isNotEmpty ? '$_enddate 23:59:59' : '',
        'payamt': _payamtCtl.text.trim(),
        'freeamt': _freeamtCtl.text.trim(),
        'prepaidamt': _prepaidamtCtl.text.trim(),
        'detaillist': _detaillist,
        'billnum': _billnum,
        'billamt': _billamt,
      };
      final currentBillid =
          widget.billid.isNotEmpty ? widget.billid : (_formData['billid']?.toString() ?? '');
      if (currentBillid.isNotEmpty) params['billid'] = currentBillid;
      if (_formData.containsKey('reviewsignflag')) {
        params['reviewsignflag'] = _formData['reviewsignflag'];
      }
      if (_formData.containsKey('reviewremark')) {
        params['reviewremark'] = _formData['reviewremark'];
      }

      final isNew = currentBillid.isEmpty;
      final api = isNew ? HttpApi.financeStorePayAdd : HttpApi.financeStorePayUpdate;
      final res = await request(api, params);
      final data = res['data'];
      if (mounted) {
        Toast.show(res['retmsg']?.toString() ?? '保存成功');
        final bool isWithdraw = sign == 1 && _isWithdrawPending;
        if (data is Map<String, dynamic>) {
          _formData = Map<String, dynamic>.from(data);
          _startdate = _str(data['startdate']).split(' ').first;
          _enddate = _str(data['enddate']).split(' ').first;
          setState(() {
            _reviewFlowUsers = _parseReviewList(data['reviewFlowUsers']);
            _reviewBillFlows = _parseReviewList(data['reviewBillFlows']);
          });
          await _loadData();
        }
        if (sign == 1) {
          _handleSignAfterSave(data is Map<String, dynamic> ? data : null, isWithdraw: isWithdraw);
        }
      }
    } catch (_) {
      if (mounted) Toast.show('保存失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleSignAfterSave(Map<String, dynamic>? savedData, {bool isWithdraw = false}) {
    if (_reviewFlowUsers.isNotEmpty && !_bolHandleT) {
      Toast.show('您不属于当前审批节点的审核人！');
      return;
    }
    if (isWithdraw) {
      _doSign(isWithdraw: true);
      return;
    }
    if (_reviewFlowUsers.isNotEmpty) {
      _showApprovalDialog().then((approvalResult) {
        if (approvalResult != null && mounted) {
          _formData['reviewsignflag'] = approvalResult['reviewsignflag'];
          _formData['reviewremark'] = approvalResult['reviewremark'];
          _doSign();
        }
      });
    } else {
      _doSign();
    }
  }

  Future<void> _handleSign() async {
    if (!PermissionUtils.checkPermission('014605', showTip: false)) {
      Toast.show('你无权审核门店结算，请在后台修改权限');
      return;
    }
    if (_formData.isEmpty) return;
    if (_reviewFlowUsers.isNotEmpty) {
      final approvalResult = await _showApprovalDialog();
      if (approvalResult == null || !mounted) return;
      _formData['reviewsignflag'] = approvalResult['reviewsignflag'];
      _formData['reviewremark'] = approvalResult['reviewremark'];
      _doSign();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定审核单据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;
    _doSign();
  }

  void _doSign({bool isWithdraw = false}) {
    if (_formData.isEmpty) return;
    final params = Map<String, dynamic>.from(_formData);
    // 门店结算审核：signflag 固定传 1（对齐 Vue signApi: query.value.signflag = 1）
    params['signflag'] = 1;
    params['reviewremark'] = _formData['reviewremark']?.toString() ?? '';
    if (isWithdraw) {
      params['reviewsignflag'] = 2;
    } else {
      final reviewsignflag = int.tryParse(params['reviewsignflag']?.toString() ?? '') ?? -1;
      if (reviewsignflag != 0) {
        params['reviewsignflag'] = 1;
      }
    }
    setState(() => _saving = true);
    request(HttpApi.financeStorePaySign, params).then((_) {
      if (mounted) {
        Toast.show('审核成功');
        _loadData();
      }
    }).catchError((_) {
      if (mounted) Toast.show('审核失败');
    }).whenComplete(() {
      if (mounted) setState(() => _saving = false);
    });
  }

  Future<Map<String, dynamic>?> _showApprovalDialog({int defaultFlag = 1}) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ApprovalDialog(defaultFlag: defaultFlag),
    );
  }

  void _showApprovalLogDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: _ApprovalLogSheet(
            reviewBillFlows: _reviewBillFlows,
            scrollController: scrollCtrl,
          ),
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> _parseReviewList(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Future<void> _handleZf() async {
    if (!PermissionUtils.checkPermission('014606', showTip: false)) {
      Toast.show('你无权作废门店结算，请在后台修改权限');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定作废单据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await request(HttpApi.financeStorePayZf, _formData);
      if (mounted) {
        Toast.show('作废成功');
        setState(() => _formData['signflag'] = -1);
      }
    } catch (_) {
      if (mounted) Toast.show('作废失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleDelete() async {
    if (!PermissionUtils.checkPermission('014604', showTip: false)) {
      Toast.show('你无权删除门店结算，请在后台修改权限');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定删除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      final currentBillid =
          widget.billid.isNotEmpty ? widget.billid : (_formData['billid']?.toString() ?? '');
      await request(HttpApi.financeStorePayDelete, {'billid': currentBillid});
      if (mounted) {
        Toast.show('删除成功');
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) Toast.show('删除失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleRetsign() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('撤回单据后，所有审批步骤需重新处理！是否撤回该门店结算单？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirm != true) return;
    _formData['reviewsignflag'] = 2;
    await _handleSave(1);
  }

  void _handlePrint() {
    request(HttpApi.cgorderPrint, {'menuid': '102302', 'data': _formData}).then((_) {
      if (mounted) Toast.show('打印任务已发送');
    });
  }

  // =================== UI Build ===================

  /// 居中加载图标卡片（透明遮罩，内容保持可见，避免加载时白屏）
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _formData.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    String statusText;
    Color statusColor;
    if (_signflag == 1) {
      statusText = '已审核';
      statusColor = const Color(0xFF00A870);
    } else if (_signflag == 2) {
      statusText = '已驳回';
      statusColor = const Color(0xFFFF9900);
    } else if (_signflag == -1) {
      statusText = '已作废';
      statusColor = const Color(0xFFAAAAAA);
    } else {
      statusText = _isEdit ? '待审核' : '新增';
      statusColor = const Color(0xFFD54B5A);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(_isEdit ? '门店结算单详情' : '新增门店结算单',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
            onPressed: () => Navigator.pop(context, true)),
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_isEdit) _buildInfoHeader(statusText, statusColor),
            if (_isEdit && (_reviewFlowUsers.isNotEmpty || _reviewBillFlows.isNotEmpty)) ...[
              const SizedBox(height: 8),
              _buildApprovalNodeCard()
            ],
            const SizedBox(height: 16),
            _buildSectionTitle('单据信息'),
            const SizedBox(height: 8),
            _buildFormCard([
              _buildSelectRow('应付门店', _bstorename,
                  onTap: !_isReadonly && !_isEdit ? _selectStoreOut : null, required: true),
              _buildSelectRow('应收门店', _storename,
                  onTap: !_isReadonly && !_isEdit ? _selectStoreIn : null, required: true),
              _buildSelectRow('选择单据', _detaillist.isNotEmpty ? '单据数量：$_billnum，总金额：$_billamt' : '',
                  onTap: _selectBills, required: true),
              _buildSelectRow('日期范围',
                  _startdate.isNotEmpty && _enddate.isNotEmpty ? '$_startdate — $_enddate' : '',
                  onTap: !_isReadonly && !_isEdit ? _selectDateRange : null),
              _buildSelectRow('经手人', _handlername, onTap: !_isReadonly ? _selectHandler : null),
              _buildTextInputRow('备注', _remarkCtl, enabled: !_isReadonly),
            ]),
            const SizedBox(height: 16),
            _buildSectionTitle('结算信息'),
            const SizedBox(height: 8),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEEEEE))),
                child: Column(children: [
                  const Text('本次应付款', style: TextStyle(fontSize: 16, color: Color(0xFF7A7A7A))),
                  const SizedBox(height: 6),
                  Text(_prepayamt,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                ])),
            const SizedBox(height: 8),
            Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEEEEE))),
                child: Column(children: [
                  _buildSettleInputRow('付款金额', _payamtCtl,
                      focusNode: _payamtFocus, enabled: !_isReadonly),
                  _buildSettleInputRow('本次免付', _freeamtCtl,
                      focusNode: _freeamtFocus, enabled: !_isReadonly),
                  _buildSettleReadRow('预付余额', _advance.isEmpty ? '0' : _advance),
                  _buildSettleInputRow('预付结算', _prepaidamtCtl,
                      focusNode: _prepaidamtFocus, enabled: !_isReadonly),
                  _buildSelectRow('付款方式', _paywayname,
                      onTap: !_isReadonly ? _selectPayway : null, required: true),
                  _buildSelectRow('收款账户', _bankname,
                      onTap: !_isReadonly ? _selectBank : null, required: true),
                  _buildSelectRow('付款账户', _bankidothername,
                      onTap: !_isReadonly ? _selectBankOther : null, required: true),
                ])),
            const SizedBox(height: 80),
          ]),
        ),
        // 居中加载图标卡片（透明遮罩，内容保持可见，避免加载时白屏）
        if (_loading || _billLoading) _loadingCard,
      ]),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildInfoHeader(String statusText, Color statusColor) {
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(_billno,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(statusText,
                    style:
                        TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500)))
          ]),
          const SizedBox(height: 8),
          _buildInfoRow(
              '制单信息', '${_formData['createtime'] ?? ''}  ${_formData['createname'] ?? ''}'),
          if (_signflag == 1)
            _buildInfoRow('审核信息', '${_formData['signtime'] ?? ''}  ${_formData['signname'] ?? ''}'),
        ]));
  }

  static Widget _buildInfoRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text('$label：', style: const TextStyle(fontSize: 13, color: Color(0xFF7A7A7A))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))))
      ]));
  static Widget _buildSectionTitle(String title) => Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
                color: const Color(0xFF006EFF), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)))
      ]);
  static Widget _buildFormCard(List<Widget> children) => Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEEEEEE))),
      child: Column(children: children));

  Widget _buildSelectRow(String label, String value,
      {VoidCallback? onTap, String placeholder = '请选择', bool required = false}) {
    final enabled = onTap != null;
    final displayValue = value.isNotEmpty ? value : (enabled ? placeholder : '');
    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration:
                const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
            child: Row(children: [
              SizedBox(
                  width: 80,
                  child: Row(children: [
                    if (required)
                      const Text('*', style: TextStyle(fontSize: 14, color: Color(0xFFFF4D4F))),
                    Expanded(
                        child: Text(label,
                            style: const TextStyle(fontSize: 15, color: Color(0xFF374151)))),
                  ])),
              Expanded(
                  child: Text(displayValue,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 14,
                          color: enabled && value.isEmpty
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF374151)))),
              if (enabled) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBEBDBE))
              ],
            ])));
  }

  static Widget _buildTextInputRow(String label, TextEditingController controller,
          {bool enabled = true}) =>
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration:
              const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
          child: Row(children: [
            SizedBox(
                width: 80,
                child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF374151)))),
            Expanded(
                child: TextField(
                    controller: controller,
                    enabled: enabled,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF374151)),
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8))))
          ]));
  Widget _buildSettleInputRow(String label, TextEditingController controller,
          {bool enabled = true, FocusNode? focusNode}) =>
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration:
              const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
          child: Row(children: [
            SizedBox(
                width: 80,
                child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF374151)))),
            Expanded(
                child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true, signed: true),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF374151)),
                    decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        hintText: enabled ? '请输入' : '',
                        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)))))
          ]));
  static Widget _buildSettleReadRow(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Row(children: [
        SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF374151)))),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15, color: Color(0xFF374151)))),
      ]));

  Widget _buildBottomBar() {
    if (!_isEdit)
      return _wrapBottomBar(
          [_primaryBtn('保存', _saving ? null : () => _handleSave(), loading: _saving)]);
    if (_signflag == -1) return _wrapBottomBar([_primaryBtn('打印', _handlePrint)]);
    if (_signflag == 1)
      return _wrapBottomBar([
        if (_formData['supsignflag']?.toString() != '1') _primaryBtn('作废', _handleZf),
        _primaryBtn('打印', _handlePrint)
      ]);
    if (_signflag == 2)
      return _wrapBottomBar([
        _outlinedBtn('删除', _handleDelete),
        _primaryBtn('打印', _handlePrint),
        _outlinedBtn('撤回', _handleRetsign)
      ]);
    return _buildPendingButtons();
  }

  Widget _wrapBottomBar(List<Widget> children) => SafeArea(
      child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: const BoxDecoration(
              color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
          child: Row(children: children)));
  Widget _primaryBtn(String label, VoidCallback? onPressed, {bool loading = false}) => Expanded(
      child: GestureDetector(
          onTap: loading ? null : onPressed,
          child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                  color: loading ? const Color(0xFF99C4FF) : const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : Text(label,
                      style: const TextStyle(
                          fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)))));
  Widget _outlinedBtn(String label, VoidCallback? onPressed) => Expanded(
      child: GestureDetector(
          onTap: onPressed,
          child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF374151))))));

  Widget _buildPendingButtons() {
    final buttons = <Widget>[];
    if (!_isWithdrawPending && _bolHandleTT) {
      buttons.add(PopupMenuButton<String>(
          onSelected: (val) {
            if (val == 'delete') _handleDelete();
            if (val == 'print') _handlePrint();
          },
          offset: const Offset(0, -100),
          itemBuilder: (_) => [
                const PopupMenuItem(value: 'delete', child: Text('删除')),
                const PopupMenuItem(value: 'print', child: Text('打印'))
              ],
          child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('更多', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                Icon(Icons.arrow_drop_up, size: 18, color: Color(0xFF6B7280))
              ]))));
    }
    final showSA =
        !_isWithdrawPending && (_bolHandleTT || (_reviewFlowUsers.isNotEmpty && _bolHandleT));
    if (showSA) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(Expanded(
          child: GestureDetector(
              onTap: _saving ? null : () => _handleSave(),
              child: Container(
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                      color: _saving ? const Color(0xFF99C4FF) : const Color(0xFF006EFF),
                      borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Text('保存',
                          style: TextStyle(
                              fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500))))));
      buttons.add(const SizedBox(width: 8));
      buttons.add(Expanded(
          child: GestureDetector(
              onTap: _saving ? null : _handleSign,
              child: Container(
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFF006EFF), borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: const Text('审核',
                      style: TextStyle(
                          fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500))))));
    }
    return _wrapBottomBar(buttons);
  }

  // =================== 选择单据弹窗 ===================

  static Widget _buildSheetHeader(BuildContext ctx) {
    return SizedBox(
        height: 50,
        child: Row(children: [
          const SizedBox(width: 48),
          const Expanded(
              child: Text('选择单据',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          SizedBox(
              width: 48,
              child: Center(
                  child: GestureDetector(
                      onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, size: 22)))),
        ]));
  }

  Widget _buildBillViewSheet(BuildContext ctx) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(children: [
          _buildSheetHeader(ctx),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFF9FAFB),
              child: Row(children: [
                Text('共 ${_detaillist.length} 条',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                const Spacer(),
                Text('预付余额：${MathUtils.formatDecimal(3, _advance)}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              ])),
          Expanded(
              child: ListView.builder(
                  cacheExtent: 800,
                  itemCount: _detaillist.length,
                  itemBuilder: (_, i) {
                    final bill = _detaillist[i];
                    return RepaintBoundary(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(bill['sbillno']?.toString() ?? '',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Text(
                                '日期：${(bill['sbilldate']?.toString() ?? '').substring(0, min(10, (bill['sbilldate']?.toString() ?? '').length))}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                            const SizedBox(width: 16),
                            Text('应付：${MathUtils.formatDecimal(3, bill['billamt'] ?? 0)}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                            const SizedBox(width: 16),
                            Text('本次应付：${MathUtils.formatDecimal(3, bill['nowamt'] ?? 0)}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF006EFF))),
                          ]),
                        ]),
                      ),
                    );
                  })),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
                color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                    color: const Color(0xFF006EFF), borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: const Text('关闭',
                    style:
                        TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  static String _str(dynamic v) => v?.toString() ?? '';
  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _buildApprovalNodeCard() {
    String currentInfo = '';
    if (_reviewFlowUsers.isNotEmpty) {
      final n = _reviewFlowUsers[0];
      currentInfo = '当前在第${n['index'] ?? '1'}节点【${n['stepname'] ?? ''}】';
      if ((n['username']?.toString() ?? '').isNotEmpty) currentInfo += '，审批人:${n['username']}';
    } else if (_reviewBillFlows.isNotEmpty) {
      final n = _reviewBillFlows[0];
      currentInfo = '节点【${n['stepname'] ?? n['stepno'] ?? ''}】';
      if ((n['username']?.toString() ?? '').isNotEmpty) currentInfo += '，审批人:${n['username']}';
    }
    final totalNodes = _reviewFlowUsers.isNotEmpty
        ? int.tryParse(_reviewFlowUsers[0]['allindex']?.toString() ?? '0') ?? 0
        : 0;
    return Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB))),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('审核日志',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
            if (totalNodes > 0)
              Text('共$totalNodes个审批节点',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888)))
          ]),
          const SizedBox(height: 10),
          if (currentInfo.isNotEmpty)
            Row(children: [
              Expanded(
                  child: Text(currentInfo,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
              GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))))
            ])
          else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('等待审核中...', style: TextStyle(fontSize: 13, color: Color(0xFFBFBFBF))),
              GestureDetector(
                  onTap: _showApprovalLogDialog,
                  child: const Text('查看', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))))
            ])
        ]));
  }
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({this.defaultFlag = 1});
  final int defaultFlag;
  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late int _flag = widget.defaultFlag;
  final _rc = TextEditingController();
  @override
  void dispose() {
    _rc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('单据审批', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              Row(children: [
                const Text('*审批意见：', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
                const SizedBox(width: 16),
                GestureDetector(
                    onTap: () => setState(() => _flag = 1),
                    child: Row(children: [
                      _rd(1),
                      const SizedBox(width: 6),
                      const Text('通过', style: TextStyle(fontSize: 14))
                    ])),
                const SizedBox(width: 24),
                GestureDetector(
                    onTap: () => setState(() => _flag = 0),
                    child: Row(children: [
                      _rd(0),
                      const SizedBox(width: 6),
                      const Text('驳回', style: TextStyle(fontSize: 14))
                    ])),
              ]),
              const SizedBox(height: 20),
              Text(_flag == 1 ? '备注信息：' : '*驳回原因：',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
              const SizedBox(height: 8),
              TextField(
                  controller: _rc,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: InputDecoration(
                      hintText: _flag == 1 ? '请输入备注信息' : '请输入驳回原因',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBFBFBF)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.all(12))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('取消'))),
                const SizedBox(width: 16),
                Expanded(
                    child: ElevatedButton(
                        onPressed: () {
                          if (_flag == 0 && _rc.text.trim().isEmpty) {
                            Toast.show('驳回原因不能为空！');
                            return;
                          }
                          Navigator.pop(
                              context, {'reviewsignflag': _flag, 'reviewremark': _rc.text.trim()});
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006EFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('确认'))),
              ]),
            ]),
      ),
    );
  }

  Widget _rd(int v) {
    final s = _flag == v;
    return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: s ? const Color(0xFF006EFF) : const Color(0xFFCCCCCC), width: 2),
            color: s ? const Color(0xFF006EFF) : Colors.white),
        child: s
            ? Center(
                child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)))
            : null);
  }
}

class _ApprovalLogSheet extends StatelessWidget {
  const _ApprovalLogSheet({required this.reviewBillFlows, required this.scrollController});
  final List<Map<String, dynamic>> reviewBillFlows;
  final ScrollController scrollController;
  String _fa(dynamic v) {
    if (v == 1 || v?.toString() == '1') return '【通过】';
    if (v == 0 || v?.toString() == '0') return '【驳回】';
    if (v == 2 || v?.toString() == '2') return '【撤回】';
    return '';
  }

  Color _ac(dynamic v) {
    if (v == 1) return const Color(0xFF00A870);
    if (v == 0) return const Color(0xFFEF4444);
    if (v == 2) return const Color(0xFFFF9900);
    return const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Expanded(
                  child: Center(
                      child: Text('审批日志',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 20, color: Color(0xFF999999))))
            ])),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Expanded(
            child: reviewBillFlows.isEmpty
                ? const Center(
                    child: Text('暂无审批记录', style: TextStyle(fontSize: 13, color: Color(0xFF999999))))
                : ListView.builder(
                    controller: scrollController,
                    itemCount: reviewBillFlows.length,
                    itemBuilder: (ctx, i) {
                      final item = reviewBillFlows[i];
                      return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                              color: i.isEven ? Colors.white : const Color(0xFFFAFAFA),
                              border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF5F5F5),
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Center(
                                      child: Text('${i + 1}',
                                          style: const TextStyle(
                                              fontSize: 11, color: Color(0xFF666666))))),
                              const SizedBox(width: 10),
                              Text(item['username']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF333333))),
                              const SizedBox(width: 8),
                              Text(_fa(item['reviewsignflag']),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _ac(item['reviewsignflag'])))
                            ]),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(
                                  child: Text('节点：${item['stepname'] ?? ''}',
                                      style:
                                          const TextStyle(fontSize: 12, color: Color(0xFF999999)))),
                              Text(
                                  item['signtime']?.toString() ??
                                      item['createtime']?.toString() ??
                                      '',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)))
                            ]),
                            if ((item['reviewremark']?.toString() ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('备注：${item['reviewremark']}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF666666)))
                            ]
                          ]));
                    }))
      ]);
}

// =================== 门店选择单据弹窗（对齐 Vue storePlierpay/selectBill.vue）==================
class _StoreSelectBillSheet extends StatefulWidget {
  const _StoreSelectBillSheet({
    required this.bills,
    required this.selectedIds,
    required this.advance,
    required this.bsid,
    required this.sid,
    this.initialLoading = false,
    this.initialStart = '',
    this.initialEnd = '',
  });

  /// 全量单据列表
  final List<Map<String, dynamic>> bills;

  /// 初始已选单据 ID
  final Set<String> selectedIds;

  /// 预付余额
  final dynamic advance;
  final String bsid;
  final String sid;

  /// 打开弹窗时外层账单请求仍在进行中，弹窗内部自行重新拉取
  final bool initialLoading;

  /// 初始日期范围（与编辑页日期范围互相关联）
  final String initialStart;
  final String initialEnd;

  @override
  State<_StoreSelectBillSheet> createState() => _StoreSelectBillSheetState();
}

class _StoreSelectBillSheetState extends State<_StoreSelectBillSheet> {
  /// 类型选项（对齐 Vue storePlierpay typeList：1配送收货单/2配退发货单）
  static const List<Map<String, String>> _typeList = [
    {'label': '全部单据类型', 'id': ''},
    {'label': '配送收货单', 'id': '1'},
    {'label': '配退发货单', 'id': '2'},
  ];

  /// 排序选项（对齐 Vue checktypeList）
  static const List<Map<String, dynamic>> _sortList = [
    {'label': '单据日期升序', 'id': 1},
    {'label': '单据日期降序', 'id': 2},
    {'label': '单据金额升序', 'id': 3},
    {'label': '单据金额降序', 'id': 4},
  ];

  late List<Map<String, dynamic>> _all;
  List<Map<String, dynamic>> _filtered = [];

  /// 弹窗内动态选中集合（跨筛选/重新加载保持）
  late Set<String> _selectedIds;
  String _typeFilter = '';
  int _sortType = 2;
  String _keyword = '';
  String _starttime = '';
  String _endtime = '';
  bool _loading = false;
  final TextEditingController _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.selectedIds);
    // 初始日期范围与编辑页同步
    _starttime = widget.initialStart;
    _endtime = widget.initialEnd;
    _all = widget.bills
        .map((e) => Map<String, dynamic>.from(e)
          ..['_selected'] = _selectedIds.contains(e['sbillid']?.toString() ?? ''))
        .toList();
    // 编辑页已请求完数据时弹窗不重新请求接口：对传入数据同样做 writeData 重算，
    // 保证欠款金额与弹窗内请求结果一致（对齐 Vue 弹窗 getList 每次都重算）
    for (final b in _all) {
      _recalcBill(b);
    }
    _applyFilter();
    // 外层 getStoreBill 请求仍在进行中：弹窗内自行重新拉取并显示 loading
    if (widget.initialLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  int get _selectedCount => _selectedIds.length;

  String get _typeName {
    for (final t in _typeList) {
      if (t['id'] == _typeFilter) return t['label'] ?? '';
    }
    return '全部类型';
  }

  String get _sortName {
    for (final s in _sortList) {
      if (s['id'] == _sortType) return s['label']?.toString() ?? '';
    }
    return '单据日期降序';
  }

  String get _timeName => _starttime.isEmpty ? '时间' : '$_starttime~$_endtime';

  /// 本地过滤 + 排序（对齐 Vue filterListFn）
  void _applyFilter() {
    final kw = _keyword.trim();
    final list = _all.where((e) {
      if (_typeFilter.isNotEmpty && e['billtype']?.toString() != _typeFilter) return false;
      if (kw.isNotEmpty &&
          !(e['sbillno']?.toString() ?? '').contains(kw) &&
          !(e['billno']?.toString() ?? '').contains(kw)) {
        return false;
      }
      return true;
    }).toList();
    double dbl(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
    list.sort((a, b) {
      switch (_sortType) {
        case 2:
          return (b['createtime']?.toString() ?? '').compareTo(a['createtime']?.toString() ?? '');
        case 3:
          return dbl(a['billamt']).compareTo(dbl(b['billamt']));
        case 4:
          return dbl(b['billamt']).compareTo(dbl(a['billamt']));
        default:
          return (a['createtime']?.toString() ?? '').compareTo(b['createtime']?.toString() ?? '');
      }
    });
    setState(() => _filtered = list);
  }

  void _toggle(Map<String, dynamic> bill) {
    final id = bill['sbillid']?.toString() ?? '';
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        bill['_selected'] = false;
      } else {
        _selectedIds.add(id);
        bill['_selected'] = true;
      }
    });
  }

  /// 全选/取消全选（作用于当前筛选列表，对齐 Vue allCheckbox）
  void _toggleAll() {
    setState(() {
      final allSelected = _filtered.isNotEmpty && _filtered.every((e) => e['_selected'] == true);
      for (final b in _filtered) {
        final id = b['sbillid']?.toString() ?? '';
        b['_selected'] = !allSelected;
        if (!allSelected) {
          _selectedIds.add(id);
        } else {
          _selectedIds.remove(id);
        }
      }
    });
  }

  void _showTypePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              height: 50,
              child: Row(children: [
                const SizedBox(width: 48),
                const Expanded(
                    child: Text('选择类型',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
                SizedBox(
                    width: 48,
                    child: Center(
                        child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280))))),
              ])),
          const Divider(height: 1),
          for (final t in _typeList)
            ListTile(
              title: Text(t['label'] ?? '',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t['id'] == _typeFilter
                          ? const Color(0xFF006EFF)
                          : const Color(0xFF333333))),
              trailing: _buildRadio(t['id'] == _typeFilter),
              onTap: () {
                Navigator.pop(ctx);
                _typeFilter = t['id'] ?? '';
                _applyFilter();
              },
            ),
        ])),
      ),
    );
  }

  void _showSortPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              height: 50,
              child: Row(children: [
                const SizedBox(width: 48),
                const Expanded(
                    child: Text('选择排序',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
                SizedBox(
                    width: 48,
                    child: Center(
                        child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280))))),
              ])),
          const Divider(height: 1),
          for (final s in _sortList)
            ListTile(
              title: Text(s['label']?.toString() ?? '',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: s['id'] == _sortType
                          ? const Color(0xFF006EFF)
                          : const Color(0xFF333333))),
              trailing: _buildRadio(s['id'] == _sortType),
              onTap: () {
                Navigator.pop(ctx);
                _sortType = s['id'] as int;
                _applyFilter();
              },
            ),
        ])),
      ),
    );
  }

  /// 圆形单选指示器（参考优惠券分析-选择礼券类型弹窗）
  Widget _buildRadio(bool isSelected) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: isSelected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB), width: 2),
      ),
      child: isSelected
          ? Center(
              child: Container(
                  width: 10,
                  height: 10,
                  decoration:
                      const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF006EFF))))
          : null,
    );
  }

  /// 时间范围选择：范围日历弹窗（点两次选开始/结束，一次确认）
  Future<void> _pickDateRange() async {
    final range = await showDateRangeCalendarPicker(
      context,
      initialStart: _starttime.isNotEmpty ? DateTime.tryParse(_starttime) : null,
      initialEnd: _endtime.isNotEmpty ? DateTime.tryParse(_endtime) : null,
    );
    if (range == null || !mounted) return;
    _starttime =
        '${range.$1.year}-${range.$1.month.toString().padLeft(2, '0')}-${range.$1.day.toString().padLeft(2, '0')}';
    _endtime =
        '${range.$2.year}-${range.$2.month.toString().padLeft(2, '0')}-${range.$2.day.toString().padLeft(2, '0')}';
    await _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final res = await request(
          HttpApi.financeStorePayGetStoreBill,
          {
            'is_page': 0,
            'bsid': widget.bsid,
            'sid': widget.sid,
            'starttime': _starttime.isEmpty ? '' : '$_starttime 00:00:00',
            'endtime': _endtime.isEmpty ? '' : '$_endtime 23:59:59',
          },
          false,
          false);
      final data = res['data'];
      if (data is List) {
        final bills = data
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final money = bills.isNotEmpty ? (bills[0]['advance'] ?? 0) : 0;
        _mapBills(bills, money);
        // 重新请求接口后：清掉已选单据，全选新数据（对齐 Vue 日期筛选后的全选逻辑）
        _selectedIds.clear();
        for (final b in bills) {
          _selectedIds.add(b['sbillid']?.toString() ?? '');
          b['_selected'] = true;
        }
        _all = bills;
        _applyFilter();
      } else {
        Toast.show('没有符合条件的单据');
        _selectedIds.clear();
        _all = [];
        _applyFilter();
      }
    } catch (e) {
      // 提示接口返回的 retmsg
      Toast.show(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 单据字段映射（对齐 Vue getList 与页面 _comBillList）
  static void _mapBills(List<Map<String, dynamic>> arr, dynamic money) {
    double advance = double.tryParse(money?.toString() ?? '') ?? 0;
    for (final item in arr) {
      item['paidamt'] = item['payamt'];
      item['freetotalamt'] = item['freeamt'];
      item['prepaidtotalamt'] = item['prepaidamt'];
      item['sbillid'] = item['sbillid'] ?? item['billid'];
      item['sbillno'] = item['sbillno'] ?? item['billno'];
      item['sbilldate'] = item['sbilldate'] ?? item['billdate'];
      item['freeamt'] = MathUtils.formatDecimal(3, 0);
      item['prepaidamt'] = MathUtils.formatDecimal(3, 0);
      final billamt = double.tryParse(item['billamt']?.toString() ?? '') ?? 0;
      final paidamt = double.tryParse(item['paidamt']?.toString() ?? '') ?? 0;
      final freetotalamt = double.tryParse(item['freetotalamt']?.toString() ?? '') ?? 0;
      final prepaidtotalamt = double.tryParse(item['prepaidtotalamt']?.toString() ?? '') ?? 0;
      final nowamt = billamt - paidamt - freetotalamt - prepaidtotalamt;
      item['nowamt'] = nowamt;
      if (advance > 0 && advance > nowamt) {
        item['prepaidamt'] = MathUtils.formatDecimal(3, nowamt);
        advance -= double.tryParse(item['prepaidamt']?.toString() ?? '') ?? 0;
      } else if (advance > 0 && advance < nowamt) {
        item['prepaidamt'] = MathUtils.formatDecimal(3, advance);
        advance = 0;
      }
      // 本次应付金额 = 单据金额 - 已付金额 - 免付金额 - 预付款金额
      item['prepayamt'] =
          MathUtils.formatDecimal(3, billamt - paidamt - freetotalamt - prepaidtotalamt);
      // 对齐 Vue 弹窗 selectBill getList：获取账单后立即 writeData 重算
      _recalcBill(item);
    }
  }

  /// 对齐 Vue 弹窗 selectBill getList 的 writeData 重算：
  /// 付款金额=本次应付全额 → 欠款金额 = 0（advance 分配的预付结算被回退）
  static void _recalcBill(Map<String, dynamic> item) {
    final nowamt = double.tryParse(item['nowamt']?.toString() ?? '') ?? 0;
    final result = _StorePayEditPageState._calculatePayment(nowamt, {
      'nowamt': nowamt,
      'freeamt': 0,
      'prepaidamt': double.tryParse(item['prepaidamt']?.toString() ?? '') ?? 0,
      'payamt': 0,
    });
    item['freeamt'] = MathUtils.formatDecimal(3, result['freeamt']);
    item['prepaidamt'] = MathUtils.formatDecimal(3, result['prepaidamt']);
    item['payamt'] = MathUtils.formatDecimal(3, result['payamt']);
    item['debtamt'] = MathUtils.formatDecimal(3, result['debtamt']);
  }

  /// 单据类型名称（对齐 Vue storePlierpay billNameFn）
  static String _billTypeName(dynamic billtype) {
    switch (billtype?.toString()) {
      case '1':
        return '配送收货单';
      case '2':
        return '配退发货单';
      case '3':
        return '采购入库';
      case '4':
        return '采购退货';
      default:
        return '未知单据';
    }
  }

  void _confirm() {
    final selectedBills = _all.where((b) => b['_selected'] == true).toList();
    for (final b in _all) {
      b.remove('_selected');
    }
    // 返回：选中单据、最新全量数据、弹窗内日期范围（回传编辑页实现日期互相关联）
    Navigator.pop(context, (selectedBills, _all, _starttime, _endtime));
  }

  /// 筛选按钮（对齐 Vue store-btn 样式）
  Widget _buildFilterBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)))),
          const Icon(Icons.arrow_drop_down, size: 28, color: Color(0xFF666666)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _filtered.isNotEmpty && _filtered.every((e) => e['_selected'] == true);
    return Column(children: [
      // ── 标题栏 ──
      SizedBox(
          height: 50,
          child: Row(children: [
            const SizedBox(width: 48),
            const Expanded(
                child: Text('选择单据',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            SizedBox(
                width: 48,
                child: Center(
                    child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, size: 22)))),
          ])),
      const Divider(height: 1, color: Color(0xFFE5E7EB)),
      // ── 筛选区：类型 / 排序 / 时间 + 单号搜索 ──
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(children: [
          Row(children: [
            Expanded(child: _buildFilterBtn(_typeName, _showTypePicker)),
            const SizedBox(width: 8),
            Expanded(child: _buildFilterBtn(_sortName, _showSortPicker)),
            const SizedBox(width: 8),
            Expanded(child: _buildFilterBtn(_timeName, _pickDateRange)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtl,
            onChanged: (v) {
              _keyword = v;
              _applyFilter();
            },
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: '请输入单号',
              hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: Color(0xFFDEDEDE))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: Color(0xFFDEDEDE))),
            ),
          ),
        ]),
      ),
      // ── 汇总栏 ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFFF9FAFB),
        child: Row(children: [
          Text('共 ${_filtered.length} 条',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const Spacer(),
          Text('预付余额：${MathUtils.formatDecimal(3, widget.advance)}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ]),
      ),
      // ── 单据卡片列表 ──
      Expanded(
          child: _loading
              ? const Center(
                  child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF006EFF))))
              : _filtered.isEmpty
                  ? const Center(
                      child:
                          Text('暂无可用单据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))))
                  : ListView.builder(
                      cacheExtent: 800,
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _buildBillCard(_filtered[i]),
                    )),
      // ── 底部栏：全选 + 返回 + 确认 ──
      Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: const BoxDecoration(
            color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
        child: Row(children: [
          Expanded(
              child: GestureDetector(
            onTap: _toggleAll,
            child: Row(children: [
              Icon(
                  allSelected
                      ? Icons.check_box
                      : (_selectedCount > 0
                          ? Icons.indeterminate_check_box
                          : Icons.check_box_outline_blank),
                  size: 22,
                  color: allSelected || _selectedCount > 0
                      ? const Color(0xFF006EFF)
                      : const Color(0xFFD1D5DB)),
              const SizedBox(width: 6),
              Text('全选，已选$_selectedCount个',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
            ]),
          )),
          _buildBottomBtn('返回', outlined: true, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 10),
          _buildBottomBtn('确认', onTap: _confirm),
        ]),
      ),
    ]);
  }

  /// 底部按钮（返回 outlined / 确认实心）
  Widget _buildBottomBtn(String label, {bool outlined = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        height: 40,
        decoration: BoxDecoration(
          color: outlined ? Colors.white : const Color(0xFF006EFF),
          borderRadius: BorderRadius.circular(8),
          border: outlined ? Border.all(color: const Color(0xFF006EFF)) : null,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: outlined ? const Color(0xFF006EFF) : Colors.white)),
      ),
    );
  }

  /// 单据卡片（对齐 Vue 列表卡片：单号+类型 / 金额两行）
  Widget _buildBillCard(Map<String, dynamic> bill) {
    final selected = bill['_selected'] == true;
    final typeName = _billTypeName(bill['billtype']);
    final createtime = bill['createtime']?.toString() ?? bill['sbilldate']?.toString() ?? '';
    return RepaintBoundary(
        child: GestureDetector(
      onTap: () => _toggle(bill),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFEEEEEE))),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(right: 34),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text(bill['sbillno']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF006EFF)))),
                if (typeName.isNotEmpty)
                  Flexible(
                      child: Text('($typeName)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text('单据金额：${MathUtils.formatDecimal(3, bill['billamt'] ?? 0)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                Text('已付金额：${MathUtils.formatDecimal(3, bill['paidamt'] ?? 0)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                    child: Text('欠款金额：${MathUtils.formatDecimal(3, bill['debtamt'] ?? 0)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
                Text('制单日期：${createtime.length > 10 ? createtime.substring(0, 10) : createtime}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ]),
            ]),
          ),
          // 复选框固定右上角
          Positioned(
              top: 0,
              right: 0,
              child: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 22, color: selected ? const Color(0xFF006EFF) : const Color(0xFFD1D5DB))),
        ]),
      ),
    ));
  }
}
