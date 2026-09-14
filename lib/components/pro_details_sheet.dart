import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 商品信息展示样式
enum ProDetailsInfoStyle {
  /// 卡片式：名称(粗) + 条码(灰) + 底部双栏信息行（默认原售价/原进价，可用 cardPairs 自定义）
  card,

  /// 标签行式：「商品名称：xxx」「条码：xxx」逐行展示（需配合 infoRows）
  labeledRows,
}

/// 标签行式信息行定义（[pairWithNext] 为 true 时与下一行合并为双栏同行）
class ProDetailsInfoRow {
  const ProDetailsInfoRow(this.label, this.value, {this.pairWithNext = false});
  final String label;
  final String value;
  final bool pairWithNext;
}

/// 商品详情公共弹窗（对齐 Vue proDetails 组件）
///
/// 统一促销计划、门店调价、快速调价、标签打印等模块的
/// 单位/规格选择（bi/product/getProductExtendList）、价格同步、条码更新逻辑。
class ProDetailsSheet extends StatefulWidget {
  const ProDetailsSheet({
    super.key,
    required this.item,
    required this.storeid,
    this.title = '商品详情',
    this.disabled = false,
    this.unitDisabled = false,
    this.sizeDisabled = false,
    this.mergData,
    this.infoStyle = ProDetailsInfoStyle.card,
    this.cardPairs = const [],
    this.infoRows = const [],
    this.showQty = false,
    this.qtyMin = 1,
    this.qtyMax = 20,
    this.qtyField = 'qty',
    this.priceFields,
    this.showFooter = true,
    this.showCancel = true,
    this.onExtendSelected,
    this.syncNameToValue = true,
    this.showShelves = true,
  });

  /// 商品数据（内部副本，确定时返回合并后的结果）
  final Map<String, dynamic> item;

  /// 门店 ID（接口 bsid 参数）
  final String storeid;

  /// 弹窗标题（促销计划/门店调价传商品名称，其他默认「商品详情」）
  final String title;

  /// 整体禁用（审批通过等只读场景）
  final bool disabled;

  /// 单独禁用单位/规格选择（门店调价单位/规格已锁定场景）
  final bool unitDisabled;
  final bool sizeDisabled;

  /// 扩展列表接口的额外参数（如 {'cgpriceflag': 1}）
  final Map<String, dynamic>? mergData;

  /// 商品信息展示样式
  final ProDetailsInfoStyle infoStyle;

  /// 卡片式信息区底部的「标签：值」列表（infoStyle = card 时生效；
  /// 为空时默认展示原售价/原进价，两两一行双栏展示）
  final List<ProDetailsInfoRow> cardPairs;

  /// 标签行式信息行（infoStyle = labeledRows 时生效）
  final List<ProDetailsInfoRow> infoRows;

  /// 是否展示数量步进器
  final bool showQty;
  final int qtyMin;
  final int qtyMax;
  final String qtyField;

  /// 选择单位/规格后需同步的价格字段白名单；null 时使用默认全量字段
  final List<String>? priceFields;

  /// 底部按钮（快速调价等页面内嵌场景可关闭）
  final bool showFooter;
  final bool showCancel;

  /// 单位/规格选择应用后的回调（携带最新商品数据；快速调价用于计算 ptype/sname）
  final void Function(String type, Map<String, dynamic> item)? onExtendSelected;

  /// 打开弹窗时是否将 unitname/sizename 同步给 unit/size 用于回显
  ///（对齐 Vue editFn 回显；商品分组等页面不需要该赋值，传 false）
  final bool syncNameToValue;

  /// 默认信息区是否展示货架号（促销调价单/门店调价单不展示，传 false）
  final bool showShelves;

  /// 默认同步的价格字段（各模块字段并集，仅接口返回的字段会被写入）
  static const List<String> defaultPriceFields = [
    'sellprice',
    'inprice',
    'cgprice',
    'oldprice',
    'minsellprice',
    'mallsellprice',
    'mprice1',
    'mprice2',
    'mprice3',
    'pfprice1',
    'pfprice2',
    'pfprice3',
    'psprice',
  ];

  /// 以底部抽屉方式打开商品详情弹窗，返回确定后的商品数据（取消返回 null）
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> item,
    required String storeid,
    String title = '商品详情',
    bool disabled = false,
    bool unitDisabled = false,
    bool sizeDisabled = false,
    Map<String, dynamic>? mergData,
    ProDetailsInfoStyle infoStyle = ProDetailsInfoStyle.card,
    List<ProDetailsInfoRow> cardPairs = const [],
    List<ProDetailsInfoRow> infoRows = const [],
    bool showQty = false,
    int qtyMin = 1,
    int qtyMax = 20,
    String qtyField = 'qty',
    List<String>? priceFields,
    bool showFooter = true,
    bool showCancel = true,
    void Function(String type, Map<String, dynamic> item)? onExtendSelected,
    bool syncNameToValue = true,
    bool showShelves = true,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProDetailsSheet(
        item: item,
        storeid: storeid,
        title: title,
        disabled: disabled,
        unitDisabled: unitDisabled,
        sizeDisabled: sizeDisabled,
        mergData: mergData,
        infoStyle: infoStyle,
        cardPairs: cardPairs,
        infoRows: infoRows,
        showQty: showQty,
        qtyMin: qtyMin,
        qtyMax: qtyMax,
        qtyField: qtyField,
        priceFields: priceFields,
        showFooter: showFooter,
        showCancel: showCancel,
        onExtendSelected: onExtendSelected,
        syncNameToValue: syncNameToValue,
        showShelves: showShelves,
      ),
    );
  }

  @override
  State<ProDetailsSheet> createState() => _ProDetailsSheetState();
}

class _ProDetailsSheetState extends State<ProDetailsSheet> {
  late Map<String, dynamic> _item;
  late String _currentUnit;
  late String _currentSize;
  late String _unitonlyid;
  late String _sizeonlyid;
  late String _barcode;

  /// 判断值是否为「空」（对齐 Vue proDetails falsy：null / '' / 0 / '0' 均视为空）
  static bool _isEmpty(dynamic v) {
    if (v == null) {
      return true;
    }
    final s = v.toString().trim();
    return s.isEmpty || s == '0';
  }

  /// 单位可选条件（对齐 Vue unitCanSelect：productid 存在 && !sizeonlyid）
  bool get _unitCanSelect {
    if (widget.disabled || widget.unitDisabled) {
      return false;
    }
    final productid = _item['productid']?.toString() ?? _item['prodid']?.toString() ?? '';
    return productid.isNotEmpty && _isEmpty(_sizeonlyid);
  }

  /// 规格可选条件（对齐 Vue sizeCanSelect：specflag==1 && !unitonlyid）
  bool get _sizeCanSelect {
    if (widget.disabled || widget.sizeDisabled) {
      return false;
    }
    final specflag = _item['specflag']?.toString() ?? '';
    return specflag == '1' && _isEmpty(_unitonlyid);
  }

  int get _qty {
    final v = int.tryParse(_item[widget.qtyField]?.toString() ?? '') ?? widget.qtyMin;
    return v.clamp(widget.qtyMin, widget.qtyMax);
  }

  List<String> get _priceFields => widget.priceFields ?? ProDetailsSheet.defaultPriceFields;

  @override
  void initState() {
    super.initState();
    _item = Map<String, dynamic>.from(widget.item);
    // 回显：unitname/sizename 非空时同步给 unit/size（对齐 Vue editFn；
    // 商品分组等页面不需要该赋值，由 syncNameToValue 控制）
    if (widget.syncNameToValue) {
      final uname = _item['unitname']?.toString() ?? '';
      if (uname.isNotEmpty) {
        _item['unit'] = uname;
      }
      final sname = _item['sizename']?.toString() ?? '';
      if (sname.isNotEmpty) {
        _item['size'] = sname;
      }
    }
    _currentUnit = _item['unit']?.toString() ?? '';
    _currentSize = _item['size']?.toString() ?? '';
    _unitonlyid = _item['unitonlyid']?.toString() ?? '';
    _sizeonlyid = _item['sizeonlyid']?.toString() ?? '';
    // 条码回显：取第一个非空值（字段存在但值为空串时 ?? 链会短路，
    // 需逐字段判空；对齐 Vue proItem.barcode || proItem.code）
    _barcode = _pickBarcode(_item);
  }

  /// 按优先级取第一个非空条码（sbarcode > productbarcode > barcode > code）
  static String _pickBarcode(Map<String, dynamic> item) {
    for (final key in ['sbarcode', 'productbarcode', 'barcode', 'code']) {
      final v = item[key]?.toString() ?? '';
      if (v.isNotEmpty) {
        return v;
      }
    }
    return '';
  }

  // ─── 单位/规格选择 ────────────────────────────────────────

  /// 调用接口查询单位/规格选项（对齐 Vue selectCom getProductExtendList 逻辑）
  Future<void> _showExtendOptions(String type) async {
    final String productid = _item['productid']?.toString() ?? _item['prodid']?.toString() ?? '';
    if (productid.isEmpty) {
      Toast.show('商品信息异常');
      return;
    }

    final params = <String, dynamic>{
      'productid': productid,
      'bsid': widget.storeid,
      'itemtype': _item['itemtype']?.toString() ?? '',
      'packageflag': _item['packageflag']?.toString() ?? '',
      'specflag': _item['specflag']?.toString() ?? '',
      'is_page': 1,
      if (widget.mergData != null) ...widget.mergData!,
    };
    // 促销计划等模块传入了 counterid 时带上（门店调价不传保持原行为）
    if (type == 'size' && (widget.mergData?.containsKey('counterid') ?? false)) {
      params['counterid'] = _item['counterid']?.toString() ?? '';
    }

    try {
      final result = await request(HttpApi.productGetExtendList, params);
      if (!mounted) {
        return;
      }
      final responseData = result['data'];
      final rawList = (responseData is Map<String, dynamic>
              ? (type == 'size' ? responseData['sizelist'] : responseData['packlist'])
              : null) as List? ??
          [];
      if (rawList.isEmpty) {
        Toast.show('暂无可选${type == 'unit' ? '单位' : '规格'}');
        return;
      }

      final list = rawList.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (type == 'size') {
          m['_name'] = m['size']?.toString() ?? m['sname']?.toString() ?? '';
          m['_id'] = m['sizeonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
        } else {
          m['_name'] = m['unit']?.toString() ?? m['sunit']?.toString() ?? '';
          m['_id'] = m['unitonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
        }
        return m;
      }).toList();

      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(children: [
                  Text('选择${type == 'unit' ? '单位' : '规格'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                  ),
                ]),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  cacheExtent: 800,
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final opt = list[i];
                    return ListTile(
                      title: Text(opt['_name']?.toString() ?? ''),
                      onTap: () => Navigator.pop(ctx, opt),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (selected != null && mounted) {
        setState(() => _applyExtendResult(type, selected));
        widget.onExtendSelected?.call(type, _item);
      }
    } catch (_) {
      if (mounted) {
        Toast.show('获取${type == 'unit' ? '单位' : '规格'}失败');
      }
    }
  }

  /// 应用单位/规格选择结果（对齐 Vue selectUnitFn / selectSizeFn）
  void _applyExtendResult(String type, Map<String, dynamic> result) {
    if (type == 'unit') {
      final u = result['unit']?.toString() ?? result['_name']?.toString() ?? '';
      if (u.isNotEmpty) {
        _currentUnit = u;
        _item['unit'] = u;
      }
      // 对齐 Vue selectUnitFn：unitonlyid 无条件设置（小单位为空 → 规格可重新选）
      final uid = result['unitonlyid']?.toString() ?? result['_id']?.toString() ?? '';
      _unitonlyid = uid;
      _item['unitonlyid'] = uid;
      _item['defunit'] = u;
      _item['defunitid'] = uid;
      // 对齐 Vue：选了包装单位后 packagenum 置 1
      dynamic packagenum = result['packagenum'];
      if (!_isEmpty(uid)) {
        packagenum = 1;
      }
      if (packagenum != null) {
        _item['packagenum'] = packagenum;
      }
      // pfprice / mprice 汇总（+e.pfprice || +e.pfprice1 || 0 语义）
      final pfprice = result['pfprice']?.toString();
      if (_isEmpty(pfprice) && result['pfprice1'] != null) {
        _item['pfprice'] = result['pfprice1'];
      } else if (pfprice != null) {
        _item['pfprice'] = pfprice;
      }
      final mprice = result['mprice']?.toString();
      if (_isEmpty(mprice) && result['mprice1'] != null) {
        _item['mprice'] = result['mprice1'];
      } else if (mprice != null) {
        _item['mprice'] = mprice;
      }
      // 单位名称同步
      final unitName = result['sunit']?.toString() ?? u;
      if (unitName.isNotEmpty) {
        _item['unitname'] = unitName;
      }
    } else {
      final s = result['size']?.toString() ?? result['_name']?.toString() ?? '';
      if (s.isNotEmpty) {
        _currentSize = s;
        _item['size'] = s;
      }
      // 对齐 Vue selectSizeFn：sizeonlyid 无条件设置（默认规格为空 → 单位可重新选）
      final sid = result['sizeonlyid']?.toString() ?? result['_id']?.toString() ?? '';
      _sizeonlyid = sid;
      _item['sizeonlyid'] = sid;
      _item['defsize'] = s;
      _item['defsizeid'] = sid;
      // 规格名称同步
      final sizeName = result['sname']?.toString() ?? s;
      if (sizeName.isNotEmpty) {
        _item['sizename'] = sizeName;
      }
    }
    // 价格字段白名单同步（仅接口返回的字段会被写入）
    for (final key in _priceFields) {
      final v = result[key];
      if (v != null) {
        _item[key] = v;
      }
    }
    // 条码更新（对齐 Vue：sbarcode || barcode，取第一个非空）
    String nb = '';
    for (final key in ['sbarcode', 'barcode']) {
      final v = result[key]?.toString() ?? '';
      if (v.isNotEmpty) {
        nb = v;
        break;
      }
    }
    if (nb.isNotEmpty) {
      _barcode = nb;
      _item['barcode'] = nb;
      _item['productbarcode'] = nb;
    }
  }

  /// 确定：返回合并后的商品数据
  void _confirm() {
    final result = Map<String, dynamic>.from(_item);
    print('result: $result');
    result['unit'] = _currentUnit;
    result['size'] = _currentSize;
    result['unitonlyid'] = _unitonlyid;
    result['sizeonlyid'] = _sizeonlyid;
    result['productbarcode'] = _barcode;
    result['barcode'] = _barcode;
    if (widget.showQty) {
      result[widget.qtyField] = _qty;
    }
    Navigator.pop(context, result);
  }

  // ─── UI ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部
          SizedBox(
            height: 50,
            child: Row(children: [
              const SizedBox(width: 48),
              Expanded(
                child: Text(widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis),
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
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // 商品信息区
          if (widget.infoStyle == ProDetailsInfoStyle.card)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE5E7EB)),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildInfoRowWidgets(),
              ),
            ),
          // 单位/规格选择
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              _buildSelectField(
                '单位',
                _currentUnit.isNotEmpty ? _currentUnit : (_unitCanSelect ? '请选择' : '-'),
                onTap: _unitCanSelect ? () => _showExtendOptions('unit') : null,
              ),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildSelectField(
                '规格',
                _currentSize.isNotEmpty ? _currentSize : (_sizeCanSelect ? '请选择' : '-'),
                onTap: _sizeCanSelect ? () => _showExtendOptions('size') : null,
              ),
              // 数量步进器
              if (widget.showQty) ...[
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                _buildQtyField(),
              ],
            ]),
          ),
          // 底部按钮
          if (widget.showFooter)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: widget.showCancel
                  ? Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6B7280),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('取消', style: TextStyle(fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _buildConfirmButton()),
                    ])
                  : _buildConfirmButton(),
            ),
        ],
      ),
    );
  }

  /// 卡片式商品信息（名称 + 条码 + 底部双栏信息行，默认原售价/原进价）
  Widget _buildInfoCard() {
    final String name = _item['productname']?.toString() ?? _item['name']?.toString() ?? '';
    // 底部信息行：未配置 cardPairs 时默认展示原售价/原进价
    List<ProDetailsInfoRow> pairs = widget.cardPairs;
    if (pairs.isEmpty) {
      final String sellprice =
          _item['sellprice']?.toString() ?? _item['saleprice']?.toString() ?? '';
      pairs = [ProDetailsInfoRow('零售价', sellprice)];
      // 货架号由 showShelves 控制（促销调价单/门店调价单不展示）
      if (widget.showShelves) {
        final String shelves = _item['shelves']?.toString() ?? '';
        pairs.add(ProDetailsInfoRow('货架号', shelves));
      }
    }
    // 两两一行双栏展示
    final rows = <Widget>[];
    for (var i = 0; i < pairs.length; i += 2) {
      final row = <Widget>[
        Expanded(child: _buildInfoInline(pairs[i].label, pairs[i].value)),
      ];
      if (i + 1 < pairs.length) {
        row.add(const SizedBox(width: 16));
        row.add(Expanded(child: _buildInfoInline(pairs[i + 1].label, pairs[i + 1].value)));
      } else {
        row.add(const Expanded(child: SizedBox()));
      }
      rows.add(Row(children: row));
      if (i + 2 < pairs.length) {
        rows.add(const SizedBox(height: 4));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        const SizedBox(height: 4),
        Text(_barcode.isNotEmpty ? _barcode : '-',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _buildInfoInline(String label, String value) {
    return Row(children: [
      Text('$label：', style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
      Text(value.isNotEmpty ? value : '-',
          style: const TextStyle(fontSize: 12, color: Color(0xFF333333))),
    ]);
  }

  /// 标签行式商品信息（infoStyle = labeledRows 时逐行展示 infoRows）
  List<Widget> _buildInfoRowWidgets() {
    const style = TextStyle(fontSize: 14, color: Color(0xFF111827));
    final widgets = <Widget>[];
    for (var i = 0; i < widget.infoRows.length; i++) {
      final row = widget.infoRows[i];
      if (row.pairWithNext && i + 1 < widget.infoRows.length) {
        final next = widget.infoRows[i + 1];
        widgets.add(Row(children: [
          Text('${row.label}：${row.value}', style: style),
          const SizedBox(width: 24),
          Expanded(child: Text('${next.label}：${next.value}', style: style)),
        ]));
        i++;
      } else {
        widgets.add(Text('${row.label}：${row.value}', style: style));
      }
      if (i < widget.infoRows.length - 1) {
        widgets.add(const SizedBox(height: 8));
      }
    }
    widgets.add(const SizedBox(height: 8));
    widgets.add(const Divider(height: 1, color: Color(0xFFE5E7EB)));
    return widgets;
  }

  /// 单位/规格选择行
  Widget _buildSelectField(String label, String value, {VoidCallback? onTap}) {
    final canTap = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: value.isNotEmpty && value != '-' && value != '请选择'
                      ? const Color(0xFF111827)
                      : const Color(0xFFD1D5DB),
                )),
          ),
          if (canTap) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
          ],
        ]),
      ),
    );
  }

  /// 数量步进器
  Widget _buildQtyField() {
    final qty = _qty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        const SizedBox(
          width: 80,
          child: Text('数量',
              style:
                  TextStyle(fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
        ),
        const Spacer(),
        _buildQtyButton(Icons.remove, qty > widget.qtyMin,
            () => setState(() => _item[widget.qtyField] = qty - 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('$qty', style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
        ),
        _buildQtyButton(
            Icons.add, qty < widget.qtyMax, () => setState(() => _item[widget.qtyField] = qty + 1)),
      ]),
    );
  }

  Widget _buildQtyButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDEDEDE)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon,
            size: 16, color: enabled ? const Color(0xFF333333) : const Color(0xFFCCCCCC)),
      ),
    );
  }

  /// 确定按钮
  Widget _buildConfirmButton() {
    return SizedBox(
      width: widget.showCancel ? null : double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: _confirm,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF006EFF),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('确定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
