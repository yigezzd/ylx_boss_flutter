import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/basis/printing/edit_product_group.dart';
import 'package:flutter_deer/pages/business/basis/printing/receipt_detail.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/widgets/common_select_sheet.dart';
import 'package:flutter_deer/widgets/date_picker_sheet.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 单据列表页（标签打印 → 单据）
/// 业务逻辑参考 Vue boss 项目 subs/basis/printing/receipts/index.vue
class ReceiptsListPage extends StatefulWidget {
  const ReceiptsListPage({super.key});

  @override
  State<ReceiptsListPage> createState() => _ReceiptsListPageState();
}

class _ReceiptsListPageState extends State<ReceiptsListPage> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _textColor = Color(0xFF333333);
  static const Color _subTextColor = Color(0xFF7A7A7A);
  static const Color _bgColor = Color(0xFFF5F6FA);
  static const Color _borderColor = Color(0xFFDEDEDE);

  /// 单据类型选项
  static const List<Map<String, dynamic>> _notypeList = [
    {'label': '采购入库单', 'id': 1},
    {'label': '调价单', 'id': 2},
    {'label': '配送收货单', 'id': 4},
    {'label': '调拨入库单', 'id': 3},
    {'label': '商品分组', 'id': 5},
  ];

  int _notype = 2; // 默认调价单
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _list = [];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // 日期范围
  String _startDate = '';
  String _endDate = '';

  // 快捷时间选择（4=自定义）
  int _activeQuickTimeId = 4;

  // 供应商筛选
  String _supId = '';
  String _supName = '';

  // 制单人筛选
  String _buyerId = '';
  String _buyerName = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = _formatDate(now);
    _startDate = _formatDate(now);
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 60 &&
        !_loading &&
        _hasMore) {
      _page++;
      _loadData();
    }
  }

  String get _notypeLabel =>
      _notypeList.firstWhere((e) => e['id'] == _notype, orElse: () => _notypeList[1])['label']
          as String;

  // ─── 数据加载 ───

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);

    final isGroup = _notype == 5;
    final url = isGroup ? HttpApi.labelProductGroupFindList : HttpApi.getLabelBill;

    final params = <String, dynamic>{
      'is_page': 1,
      'field': 'createtime',
      'type': 'desc',
      'page': _page,
      'pagesize': 20,
      'notype': _notype,
    };
    if (!isGroup) {
      params['starttime'] = '$_startDate 00:00:00';
      params['endtime'] = '$_endDate 23:59:59';
    }
    if (_notype == 5) {
      params['type'] = 'asc';
    }
    // 搜索条件
    final searchText = _searchController.text.trim();
    if (searchText.isNotEmpty) {
      if (isGroup) {
        params['groupname'] = searchText;
      } else {
        params['billno'] = searchText;
      }
    }

    // 供应商筛选
    if (_supId.isNotEmpty) params['supid'] = _supId;
    if (_supName.isNotEmpty) params['supname'] = _supName;
    // 制单人筛选
    if (_buyerId.isNotEmpty) params['buyerid'] = _buyerId;
    if (_buyerName.isNotEmpty) params['buyeridname'] = _buyerName;

    try {
      final res = await request(url, params, _page == 1);
      if (!mounted) return;

      final data = res['data'];
      final newList = (data is Map ? data['list'] : null) as List? ?? [];
      final items = newList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      setState(() {
        if (_page == 1) {
          _list = items;
        } else {
          _list.addAll(items);
        }
        _hasMore = items.length >= 20;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refresh() {
    _page = 1;
    _hasMore = true;
    _loadData();
  }

  void _resetFilters() {
    setState(() {
      _supId = '';
      _supName = '';
      _buyerId = '';
      _buyerName = '';
      final now = DateTime.now();
      _startDate = _formatDate(now);
      _endDate = _formatDate(now);
      _activeQuickTimeId = 4;
      _searchController.clear();
    });
    _refresh();
  }

  // ─── 筛选弹窗 ───

  void _showFilterDrawer() {
    int tmpActiveQuickTimeId = _activeQuickTimeId;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(ctx).size.height * 0.65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题栏
                  Row(
                    children: [
                      const Text('筛选', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── 快速时间选择 ──
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      const _QuickTimeTag('昨天', 0),
                      const _QuickTimeTag('今天', 1),
                      const _QuickTimeTag('本周', 2),
                      const _QuickTimeTag('本月', 3),
                      const _QuickTimeTag('自定义', 4),
                    ].map((tag) {
                      final active = tmpActiveQuickTimeId == tag.id;
                      return GestureDetector(
                        onTap: () {
                          if (tag.id == 4) {
                            setModalState(() => tmpActiveQuickTimeId = 4);
                            return;
                          }
                          final now = DateTime.now();
                          DateTime start = now;
                          DateTime end = now;
                          switch (tag.id) {
                            case 0:
                              start = now.subtract(const Duration(days: 1));
                              end = start;
                              break;
                            case 1:
                              break;
                            case 2:
                              final weekday = now.weekday;
                              start = now.subtract(Duration(days: weekday - 1));
                              end = start.add(const Duration(days: 6));
                              break;
                            case 3:
                              start = DateTime(now.year, now.month);
                              end = DateTime(now.year, now.month + 1, 0);
                              break;
                          }
                          setModalState(() {
                            _startDate = _formatDate(start);
                            _endDate = _formatDate(end);
                            tmpActiveQuickTimeId = tag.id;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: active ? _primaryColor : Colors.white,
                            border: Border.all(color: active ? _primaryColor : _borderColor),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag.label,
                            style:
                                TextStyle(fontSize: 12, color: active ? Colors.white : _textColor),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // 日期范围
                  _buildDateRangeRow(ctx, setModalState, (v) => tmpActiveQuickTimeId = v),
                  const SizedBox(height: 12),

                  const Spacer(),
                  // 底部按钮
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _resetFilters();
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              border: Border.all(color: _primaryColor),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: const Text('重置',
                                style: TextStyle(fontSize: 15, color: _primaryColor)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _activeQuickTimeId = tmpActiveQuickTimeId;
                            });
                            Navigator.pop(ctx);
                            _refresh();
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: const Text('确定',
                                style: TextStyle(fontSize: 15, color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDateRangeRow(
      BuildContext ctx, StateSetter setModalState, void Function(int) onQuickTimeChanged) {
    return Row(
      children: [
        const Text('开始日期', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showCommonDatePicker(
                ctx,
                initial: DateTime.tryParse(_startDate) ?? DateTime.now(),
              );
              if (picked != null) {
                setModalState(() {
                  _startDate = _formatDate(picked);
                  onQuickTimeChanged(4);
                });
              }
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: _borderColor),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: Text(_startDate, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('结束', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showCommonDatePicker(
                ctx,
                initial: DateTime.tryParse(_endDate) ?? DateTime.now(),
              );
              if (picked != null) {
                setModalState(() {
                  _endDate = _formatDate(picked);
                  onQuickTimeChanged(4);
                });
              }
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: _borderColor),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: Text(_endDate, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: const TextStyle(fontSize: 14, color: _subTextColor)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 14), textAlign: TextAlign.right),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }

  /// 选择制单人
  Future<Map<String, dynamic>?> _selectUser(BuildContext context) {
    return CommonSelectSheet.show(
      context,
      title: '选择制单人',
      searchHint: '输入制单人名称/编码',
      fetchData: (searchText, page) {
        return request(HttpApi.sysUserList, {
          'cond': searchText,
          'is_page': 1,
          'page': page,
        }).then((result) {
          final data = result['data'];
          return data is Map<String, dynamic> ? data : null;
        });
      },
      idField: 'userid',
      showAll: true,
      mapResult: (item) {
        final name = item['name']?.toString() ?? '';
        final code = item['code']?.toString() ?? '';
        return {
          'userid': item['userid']?.toString() ?? '',
          'name': code.isNotEmpty ? '[$code]$name' : name,
        };
      },
    );
  }

  // ─── 单据类型选择 ───

  void _showNotypeSelector() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('单据类型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              ..._notypeList.map((opt) {
                final id = opt['id'] as int;
                final label = opt['label'] as String;
                final isSelected = _notype == id;
                return ListTile(
                  title: Text(label,
                      style: TextStyle(
                        color: isSelected ? _primaryColor : _textColor,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      )),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: _primaryColor, size: 22)
                      : null,
                  onTap: () {
                    setState(() => _notype = id);
                    Navigator.pop(ctx);
                    _searchController.clear();
                    _refresh();
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ─── 列表项点击 ───

  void _onItemTap(Map<String, dynamic> item) {
    if (_notype == 5) {
      // 商品分组 → 查看模式，勾选商品后返回选中列表
      Navigator.push<List<Map<String, dynamic>>>(
        context,
        MaterialPageRoute(
          builder: (_) => EditProductGroupPage(
            groupId: item['groupid']?.toString() ?? '',
            isEdit: 2, // 查看模式
          ),
        ),
      ).then((result) {
        if (result != null && result.isNotEmpty && mounted) {
          // 通过事件机制将选中商品传回标签打印主页
          Navigator.pop(context, result);
        }
      });
    } else {
      // 单据 → 详情页
      Navigator.push<List<Map<String, dynamic>>>(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptDetailPage(
            billId: item['billid']?.toString() ?? '',
            notype: _notype,
            billInfo: item,
          ),
        ),
      ).then((result) {
        if (result != null && result.isNotEmpty && mounted) {
          // 通过事件机制将选中商品传回标签打印主页
          Navigator.pop(context, result);
        }
      });
    }
  }

  // ─── 新增/编辑分组 ───

  void _openEditProductGroup([Map<String, dynamic>? item]) {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProductGroupPage(
          groupId: item?['groupid']?.toString() ?? '',
          isEdit: item != null ? 1 : 1, // 编辑模式
        ),
      ),
    ).then((refresh) {
      if (refresh ?? false) _refresh();
    });
  }

  // ─── 页面构建 ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '单据列表'),
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部：类型选择 + 日期筛选
            _buildTopBar(),
            // 搜索栏
            _buildSearchBar(),
            // 列表
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // 单据类型
          Expanded(
            child: GestureDetector(
              onTap: _showNotypeSelector,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: _borderColor),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_notypeLabel,
                          style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 20, color: _subTextColor),
                  ],
                ),
              ),
            ),
          ),
          if (_notype != 5) ...[
            const SizedBox(width: 8),
            // 日期筛选
            Expanded(
              child: GestureDetector(
                onTap: _showFilterDrawer,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: _borderColor),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text('时间',
                            style: TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                      ),
                      Icon(Icons.arrow_drop_down, size: 20, color: _subTextColor),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, _) {
                  return TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _refresh(),
                    decoration: InputDecoration(
                      hintText: _notype == 5 ? '请输入商品组名称' : '请输入单号',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8B8B8B)),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8B8B8B)),
                      // 有输入内容时显示清空按钮
                      suffixIcon: value.text.isNotEmpty
                          ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                _debounce?.cancel();
                                _searchController.clear();
                                _refresh();
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.cancel, size: 16, color: Color(0xFFBFBFBF)),
                              ),
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
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
                    style: const TextStyle(fontSize: 13),
                  );
                },
              ),
            ),
          ),
          // 商品分组模式下的新增按钮
          if (_notype == 5) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _openEditProductGroup(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  border: Border.all(color: _borderColor),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(Icons.add, size: 22, color: _textColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_list.isEmpty && !_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 60, color: Color(0xFFCCCCCC)),
            SizedBox(height: 12),
            Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView.builder(
        controller: _scrollController,
        cacheExtent: 800,
        itemCount: _list.length + (_hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == _list.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          return _ReceiptCard(
            item: _list[i],
            notype: _notype,
            onTap: () => _onItemTap(_list[i]),
            onEdit: _notype == 5 ? () => _openEditProductGroup(_list[i]) : null,
          );
        },
      ),
    );
  }
}

/// 单据卡片组件
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.item,
    required this.notype,
    required this.onTap,
    this.onEdit,
  });
  final Map<String, dynamic> item;
  final int notype;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    if (notype == 5) return _buildGroupCard();
    return _buildBillCard();
  }

  Widget _buildBillCard() {
    final billno = item['billno']?.toString() ?? '';
    final createname = item['createname']?.toString() ?? '';
    final createtime = item['createtime']?.toString() ?? '';
    final supname = item['supname']?.toString() ?? '';
    final billamt = MathUtils.formatDecimal(3, item['billamt'] ?? '0');

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 单号 + 状态
              Row(
                children: [
                  Expanded(
                    child: Text(billno,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (notype == 1)
                    const Text('已入库', style: TextStyle(fontSize: 13, color: Color(0xFF006EFF))),
                ],
              ),
              const SizedBox(height: 4),
              // 制单人 / 供应商
              Row(
                children: [
                  Expanded(
                    child: Text(
                      notype == 1 ? '供应商：$supname' : '制单人：$createname',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                    ),
                  ),
                  if (notype == 1 || notype == 3)
                    Text('单据金额：$billamt',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ],
              ),
              if (notype == 1 && supname.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('制单人：$createname',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              ],
              const Divider(height: 12, thickness: 1, color: Color(0xFFEEEEEE)),
              Text('制单时间：$createtime',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard() {
    final groupname = item['groupname']?.toString() ?? '';
    final opername = item['opername']?.toString() ?? '';
    final createtime = item['createtime']?.toString() ?? '';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('商品分组名称：$groupname',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                  const SizedBox(height: 4),
                  Text('创建人：$opername',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                  const Divider(height: 12, thickness: 1, color: Color(0xFFEEEEEE)),
                  Text('创建时间：$createtime',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                ],
              ),
            ),
            // 编辑按钮
            if (onEdit != null)
              Positioned(
                right: 28,
                top: 14,
                child: GestureDetector(
                  onTap: onEdit,
                  child: const Icon(Icons.edit, size: 18, color: Color(0xFF7A7A7A)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 快捷时间标签
class _QuickTimeTag {
  const _QuickTimeTag(this.label, this.id);
  final String label;
  final int id;
}
