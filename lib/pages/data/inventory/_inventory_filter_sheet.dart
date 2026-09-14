import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// 库存分析筛选弹窗数据模型
class InventoryFilterData {
  InventoryFilterData({
    this.cond = '',
    this.days = 0,
    this.brandid = '',
    this.brandname = '',
    List<String>? itemstatus,
    this.mpbilltypeflag = 1,
    this.showzerostockflag = 1,
    this.saleflag = 1,
  }) : itemstatus = itemstatus ?? [];
  String cond;
  int days;
  String brandid;
  String brandname;
  List<String> itemstatus;
  int mpbilltypeflag;
  int showzerostockflag;
  int saleflag;

  InventoryFilterData copy() => InventoryFilterData(
        cond: cond,
        days: days,
        brandid: brandid,
        brandname: brandname,
        itemstatus: List.from(itemstatus),
        mpbilltypeflag: mpbilltypeflag,
        showzerostockflag: showzerostockflag,
        saleflag: saleflag,
      );
}

/// 库存分析共用筛选弹窗
/// 适合 changQue(畅缺)、unsalable(滞销)、zeroStock(零库存)、loadStock(负库存)、enterUnsold(进货未销)
class InventoryFilterSheet extends StatelessWidget {
  const InventoryFilterSheet({
    super.key,
    required this.initial,
    required this.onConfirm,
    this.showDays = true,
    this.daysLabel = '持续天数',
    this.defaultDays = 3,
    this.showBrand = true,
    this.itemStatusSingle = false,
    this.showMpbilltype = false,
    this.toggleLabel = '不显示促销商品',
    this.showSecondToggle = false,
    this.secondToggleLabel = '',
    this.itemStatusOptions = _defaultItemStatusOptions,
    this.onSelectBrand,
    this.sids = const [],
  });

  final InventoryFilterData initial;
  final ValueChanged<InventoryFilterData> onConfirm;
  final bool showDays;
  final String daysLabel;
  final int defaultDays;
  final bool showBrand;
  final bool itemStatusSingle;
  final bool showMpbilltype;
  final String toggleLabel;
  final bool showSecondToggle;
  final String secondToggleLabel;
  final List<Map<String, String>> itemStatusOptions;
  final Future<void> Function(BuildContext ctx, void Function(String id, String name) onSelected)?
      onSelectBrand;
  final List<int> sids;

  static const _defaultItemStatusOptions = [
    {'label': '全部', 'value': ''},
    {'label': '正常', 'value': '1'},
    {'label': '新品', 'value': '2'},
    {'label': '冻结', 'value': '3'},
    {'label': '停购', 'value': '4'},
    {'label': '停用', 'value': '5'},
  ];

  @override
  Widget build(BuildContext context) {
    return _FilterSheetBody(
      initial: initial,
      onConfirm: onConfirm,
      showDays: showDays,
      daysLabel: daysLabel,
      defaultDays: defaultDays,
      showBrand: showBrand,
      itemStatusSingle: itemStatusSingle,
      showMpbilltype: showMpbilltype,
      toggleLabel: toggleLabel,
      showSecondToggle: showSecondToggle,
      secondToggleLabel: secondToggleLabel,
      itemStatusOptions: itemStatusOptions,
      onSelectBrand: onSelectBrand,
      sids: sids,
    );
  }
}

class _FilterSheetBody extends StatefulWidget {
  const _FilterSheetBody({
    required this.initial,
    required this.onConfirm,
    this.showDays = true,
    this.daysLabel = '持续天数',
    this.defaultDays = 3,
    this.showBrand = true,
    this.itemStatusSingle = false,
    this.showMpbilltype = false,
    this.toggleLabel = '不显示促销商品',
    this.showSecondToggle = false,
    this.secondToggleLabel = '',
    this.itemStatusOptions = _defaultItemStatusOptions,
    this.onSelectBrand,
    this.sids = const [],
  });

  final InventoryFilterData initial;
  final ValueChanged<InventoryFilterData> onConfirm;
  final bool showDays;
  final String daysLabel;
  final int defaultDays;
  final bool showBrand;
  final bool itemStatusSingle;
  final bool showMpbilltype;
  final String toggleLabel;
  final bool showSecondToggle;
  final String secondToggleLabel;
  final List<Map<String, String>> itemStatusOptions;
  final Future<void> Function(BuildContext ctx, void Function(String id, String name) onSelected)?
      onSelectBrand;
  final List<int> sids;

  static const _defaultItemStatusOptions = [
    {'label': '全部', 'value': ''},
    {'label': '正常', 'value': '1'},
    {'label': '新品', 'value': '2'},
    {'label': '冻结', 'value': '3'},
    {'label': '停购', 'value': '4'},
    {'label': '停用', 'value': '5'},
  ];

  @override
  State<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<_FilterSheetBody> {
  late InventoryFilterData _data;
  final _condController = TextEditingController();
  final _daysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _data = widget.initial.copy();
    _condController.text = _data.cond;
    if (_data.days == 0 && widget.showDays) {
      _data.days = widget.defaultDays;
      _daysController.text = widget.defaultDays.toString();
    } else {
      _daysController.text = _data.days != 0 ? _data.days.toString() : '';
    }
  }

  @override
  void dispose() {
    _condController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  void _toggleItemStatus(String value) {
    setState(() {
      if (widget.itemStatusSingle) {
        // 单选：点击"全部"清空，点击其他状态仅保留该状态
        _data.itemstatus = value.isEmpty ? [] : [value];
      } else if (value.isEmpty) {
        _data.itemstatus = [];
      } else if (_data.itemstatus.contains(value)) {
        _data.itemstatus.remove(value);
      } else {
        _data.itemstatus = [..._data.itemstatus, value];
      }
    });
  }

  Future<void> _scanBarcode() async {
    if (Device.isMobile) {
      final code = await Navigator.of(context, rootNavigator: true).push<Object>(
        MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
      );
      if (code != null && mounted) {
        _condController.text = code.toString();
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
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
                  child: Text('筛选',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // 内容区
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 搜索输入（对齐扫码查价搜索框）
                  _buildSearchInput(),
                  // 持续/临期天数 (可选)
                  if (widget.showDays) ...[
                    const SizedBox(height: 16),
                    _buildInputRow(widget.daysLabel, _daysController, '输入天数', isNumber: true),
                  ],
                  const SizedBox(height: 22),
                  // 品牌选择 (可选)
                  if (widget.showBrand) ...[
                    _buildFilterLabel('品牌'),
                    const SizedBox(height: 8),
                    _buildSelectorRow(
                      label: _data.brandname.isNotEmpty ? _data.brandname : '全部品牌',
                      onTap: () {
                        if (widget.onSelectBrand != null) {
                          widget.onSelectBrand!(context, (id, name) {
                            setState(() {
                              _data.brandid = id;
                              _data.brandname = name;
                            });
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 22),
                  ],
                  // 商品状态
                  _buildFilterLabel('商品状态'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.itemStatusOptions.map((opt) {
                      final val = opt['value']!;
                      final label = opt['label']!;
                      final isAll = val.isEmpty;
                      final selected =
                          isAll ? _data.itemstatus.isEmpty : _data.itemstatus.contains(val);
                      return GestureDetector(
                        onTap: () => _toggleItemStatus(val),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF006EFF) : Colors.white,
                            border: Border.all(
                              color: selected ? const Color(0xFF006EFF) : const Color(0xFFDEDEDE),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: selected ? Colors.white : const Color(0xFF333333))),
                        ),
                      );
                    }).toList(),
                  ),
                  // 促销商品开关 (仅畅缺)
                  if (widget.showMpbilltype) ...[
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(widget.toggleLabel,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
                          Switch(
                            value: _data.mpbilltypeflag == 1,
                            activeColor: const Color(0xFF006EFF),
                            onChanged: (v) {
                              setState(() => _data.mpbilltypeflag = v ? 1 : 0);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  // 第二开关 (进货未销等)
                  if (widget.showSecondToggle) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(widget.secondToggleLabel,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
                          Switch(
                            value: _data.saleflag == 1,
                            activeColor: const Color(0xFF006EFF),
                            onChanged: (v) {
                              setState(() => _data.saleflag = v ? 1 : 0);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 底部按钮
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _data = InventoryFilterData(
                          days: widget.showDays ? widget.defaultDays : 0,
                        );
                        _condController.clear();
                        _daysController.text = widget.showDays ? widget.defaultDays.toString() : '';
                      });
                    },
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFD1D5DB)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('重置',
                          style: TextStyle(fontSize: 15, color: Color(0xFF666666))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _data.cond = _condController.text.trim();
                      if (widget.showDays) {
                        _data.days = int.tryParse(_daysController.text.trim()) ?? 0;
                      }
                      widget.onConfirm(_data);
                      Navigator.pop(context);
                    },
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF006EFF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('确定', style: TextStyle(fontSize: 15, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchInput() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
        const SizedBox(width: 6),
        Flexible(
          child: TextField(
            controller: _condController,
            style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
            decoration: const InputDecoration(
              hintText: '输入条码/品名/自编码',
              hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _condController,
          builder: (_, value, __) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () {
                _condController.clear();
                setState(() {});
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.cancel, size: 16, color: Color(0xFFBDBDBD)),
              ),
            );
          },
        ),
        // 扫描图标
        GestureDetector(
          onTap: _scanBarcode,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: BossSvgIcon(svgFile: 'scan.svg', size: 20),
          ),
        ),
      ]),
    );
  }

  Widget _buildInputRow(String label, TextEditingController controller, String hint,
      {bool isNumber = false}) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
        ),
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: TextField(
              controller: controller,
              keyboardType: isNumber
                  ? const TextInputType.numberWithOptions(signed: true)
                  : TextInputType.text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterLabel(String text) {
    return Text(text,
        style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)));
  }

  Widget _buildSelectorRow({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}

/// 通用选择器弹窗（供应商/品牌等）
class SelectorSheet extends StatelessWidget {
  const SelectorSheet({
    super.key,
    required this.title,
    required this.apiPath,
    required this.nameKey,
    required this.idKey,
    this.codeKey,
    this.params,
    required this.onSelected,
  });

  final String title;
  final String apiPath;
  final String nameKey;
  final String idKey;
  final String? codeKey;
  final Map<String, dynamic>? params;
  final void Function(String id, String name) onSelected;

  @override
  Widget build(BuildContext context) {
    return _SelectorSheetBody(
      title: title,
      apiPath: apiPath,
      nameKey: nameKey,
      idKey: idKey,
      codeKey: codeKey,
      params: params,
      onSelected: onSelected,
    );
  }
}

class _SelectorSheetBody extends StatefulWidget {
  const _SelectorSheetBody({
    required this.title,
    required this.apiPath,
    required this.nameKey,
    required this.idKey,
    this.codeKey,
    this.params,
    required this.onSelected,
  });
  final String title, apiPath, nameKey, idKey;
  final String? codeKey;
  final Map<String, dynamic>? params;
  final void Function(String id, String name) onSelected;

  @override
  State<_SelectorSheetBody> createState() => _SelectorSheetBodyState();
}

class _SelectorSheetBodyState extends State<_SelectorSheetBody> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String _keyword = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{
        'is_page': 0,
        'stopflag': '0,3',
        if (_keyword.isNotEmpty) 'cond': _keyword,
        if (widget.params != null) ...widget.params!,
        if (widget.apiPath == HttpApi.supplierList) 'supselltypes': '1,3,4',
        if (widget.apiPath == HttpApi.supplierList) 'supnature': '1,2,3',
      };
      final result = await request(widget.apiPath, params);
      final data = result['data'];
      if (data is List) {
        setState(() => _list = data.cast<Map<String, dynamic>>());
      } else if (data is Map && data['list'] is List) {
        setState(() => _list = (data['list'] as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      setState(() => _list = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(children: [
        SizedBox(
            height: 50,
            child: Row(children: [
              const SizedBox(width: 48),
              Expanded(
                  child: Text(widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)))),
              SizedBox(
                  width: 48,
                  child: Center(
                      child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280))))),
            ])),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '输入关键词搜索',
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
              ),
              onChanged: (v) {
                _keyword = v.trim();
                _loadData();
              },
            )),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _list.isEmpty
                    ? const Center(
                        child:
                            Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))))
                    : ListView.builder(
                        cacheExtent: 800,
                        itemCount: _list.length,
                        itemBuilder: (_, i) {
                          final item = _list[i];
                          final name = item[widget.nameKey]?.toString() ?? '';
                          final id = item[widget.idKey]?.toString() ?? '';
                          final code =
                              widget.codeKey != null ? item[widget.codeKey]?.toString() : null;
                          return RepaintBoundary(
                              child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              widget.onSelected(id, name);
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
                              child: Text(code != null && code.isNotEmpty ? '[$code]$name' : name,
                                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
                            ),
                          ));
                        })),
      ]),
    );
  }
}
