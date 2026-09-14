import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/wms/launch/common.dart';
import 'package:flutter_deer/pages/business/wms/launch/detail.dart';
import 'package:flutter_deer/pages/business/wms/launch/edit.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';
import 'package:sp_util/sp_util.dart';

/// WMS 上架搜索页（对齐 Vue wms/launch/search.vue）
class WmsLaunchSearchPage extends StatefulWidget {
  const WmsLaunchSearchPage({super.key, required this.mode});

  /// '0'=按单据 '1'=按商品
  final String mode;

  @override
  State<WmsLaunchSearchPage> createState() => _WmsLaunchSearchPageState();
}

class _WmsLaunchSearchPageState extends State<WmsLaunchSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  int _requestSeq = 0;

  final List<Map<String, dynamic>> _list = [];

  String _storeId = '';
  String _storeName = '';

  static const int _pageSize = 20;

  bool get _isBillMode => widget.mode == '0';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadLocalInfo();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _loadLocalInfo() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeId = storeMap['id']?.toString() ?? '';
        _storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  /// 输入防抖搜索（对齐 Vue debounce 350ms）
  void _onChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _retParam();
    });
  }

  void _retParam() {
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  Future<void> _loadData() {
    if (_loading) return Future.value();
    setState(() => _loading = true);
    final int seq = ++_requestSeq;
    final bool isFirstPage = _page == 1;
    final String apiUrl = _isBillMode ? HttpApi.wmsLaunchList : HttpApi.wmsLaunchProList;

    final params = <String, dynamic>{
      'is_page': 1,
      'field': _isBillMode ? 'createtime' : 'billno',
      'type': 'desc',
      'page': _page,
      'pagesize': _pageSize,
      'sids': [_storeId],
      'sidsname': _storeName,
    };
    // 对齐 Vue：按单据传 billno，按商品传 cond
    if (_isBillMode) {
      params['billno'] = _controller.text.trim();
    } else {
      params['cond'] = _controller.text.trim();
    }

    return request(apiUrl, params).then((result) {
      if (seq != _requestSeq || !mounted) return;
      final data = result['data'];
      final raw = (data is Map<String, dynamic> ? data['list'] : data) as List? ?? [];
      final rows = raw.whereType<Map<String, dynamic>>().toList();
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
      if (seq != _requestSeq || !mounted) return;
      setState(() => _hasMore = false);
    }).whenComplete(() {
      if (seq == _requestSeq && mounted) {
        setState(() => _loading = false);
      }
    });
  }

  /// 按单据点击 → detail；按商品点击 → edit（对齐 Vue selectItemFn）
  Future<void> _selectItem(Map<String, dynamic> item) async {
    if (!PermissionUtils.checkPermission('011901')) return;
    if (_isBillMode) {
      await Navigator.push(
        context,
        MaterialPageRoute<dynamic>(
          builder: (_) => WmsLaunchDetailPage(billInfo: Map<String, dynamic>.from(item)),
        ),
      );
      return;
    }
    item['qty'] = item['billqty'];
    await Navigator.push(
      context,
      MaterialPageRoute<dynamic>(
        builder: (_) => WmsLaunchEditPage(
          activeTab: '1',
          data: {
            'activeTab': '1',
            'billid': item['billid'],
            'billflag': item['billflag'],
            'billno': item['billno'],
            'locationcode': item['locationcode'] ?? '',
            'locationid': item['locationid'] ?? '',
            'palletcode': item['palletcode'] ?? '',
            'sumlunchqty': item['billqty'] ?? 0,
            'bsid': item['bsid'] ?? '',
            'counterid': item['counterid'] ?? '',
            'detaillist': [item],
            'mergeDetails': [item],
          },
        ),
      ),
    );
  }

  /// 按商品模式下的扫码搜索（对齐 Vue scanFn）
  Future<void> _scan() async {
    final code = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute<dynamic>(builder: (_) => const QrCodeScannerPage()),
    );
    if (!mounted) return;
    final scancode = code?.toString().trim() ?? '';
    if (scancode.isEmpty) {
      Toast.show('请扫描正确条码');
      return;
    }
    _controller.text = scancode;
    _retParam();
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
        title: SizedBox(
          height: 36,
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => _onChanged(),
            onSubmitted: (_) => _retParam(),
            decoration: InputDecoration(
              hintText: _isBillMode ? '请输入单号' : '输入条码/品名/自编码',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
              prefixIconConstraints: const BoxConstraints(minWidth: 32),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _controller.clear();
                        _onChanged();
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
                    ),
                  if (!_isBillMode)
                    GestureDetector(
                      onTap: _scan,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF006EFF)),
                      ),
                    ),
                ],
              ),
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
        ),
      ),
      body: _list.isEmpty && !_loading
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
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
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
                final item = _list[index];
                return RepaintBoundary(
                  child: _isBillMode
                      ? LaunchBillCard(item: item, onTap: () => _selectItem(item))
                      : LaunchProCard(item: item, onTap: () => _selectItem(item)),
                );
              },
            ),
    );
  }
}
