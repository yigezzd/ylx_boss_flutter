import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/components/select/select_store.dart';
import 'package:flutter_deer/components/select/select_warehouse.dart';
import 'package:flutter_deer/components/select/select_product.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_customer.dart';
import 'package:flutter_deer/pages/business/wholesale/select/select_salesperson.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/math_utils.dart';

import 'package:flutter_deer/widgets/load_image.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/widgets/select_field_item.dart';
import 'package:sp_util/sp_util.dart';

enum _PFAction { none, save, sign, delete, print, retsign }

class PfOrderEditPage extends StatefulWidget {
  final Map<String, dynamic>? billData;

  const PfOrderEditPage({super.key, this.billData});

  @override
  State<PfOrderEditPage> createState() => _PfOrderEditPageState();
}

class _PfOrderEditPageState extends State<PfOrderEditPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _custController = TextEditingController();
  final TextEditingController _warehouseController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _salesController = TextEditingController();

  final TextEditingController _scanController = TextEditingController();
  late final FocusNode _scanFocusNode;
  bool _scanFieldFocused = false;
  Timer? _scanDebounceTimer;

  String? _custid;
  int? _storeid;
  String? _counterid;
  String? _salesid;
  String? _salesname;
  String? _storename;
  int? _storetype;

  _PFAction _submitAction = _PFAction.none;
  bool _detailLoading = false;

  bool _isSelectMode = false;
  Set<int> _selectedIndices = {};

  Map<String, dynamic>? _billData;
  String? _newBillid;

  bool get _isEdit =>
      (_newBillid != null && _newBillid!.isNotEmpty) ||
      (widget.billData != null &&
          (widget.billData!['billid']?.toString().isNotEmpty ?? false));
  bool get _isSigned => _billData?['signflag']?.toString() == '1';

  final List<_PFDetailRow> _items = [];

  @override
  void initState() {
    super.initState();
    _scanFocusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          final scanCode = _scanController.text.trim();
          if (scanCode.isNotEmpty) {
            _scanDebounceTimer?.cancel();
            _handleScannedBarcode(scanCode,
                returnFocusNode: _scanFocusNode);
            _scanController.clear();
            _scanFocusNode.requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.hide');
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _scanFocusNode.addListener(() {
      if (_scanFocusNode.hasFocus && !_scanFieldFocused) {
        _scanFieldFocused = true;
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } else if (!_scanFocusNode.hasFocus) {
        _scanFieldFocused = false;
      }
    });
    _scanController.addListener(() {
      _scanDebounceTimer?.cancel();
      final text = _scanController.text.trim();
      if (text.isEmpty) return;
      _scanDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final code = _scanController.text.trim();
        if (code.isEmpty) return;
        _handleScannedBarcode(code, returnFocusNode: _scanFocusNode);
        _scanController.clear();
        _scanFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      });
    });

    if (_isEdit) {
      _loadDetail();
    } else {
      _loadNewModeDefaults();
    }
  }

  void _loadNewModeDefaults() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        _storeid = _parseIntFlexible(storeMap, ['id', 'storeid', 'bsid']);
        _storename = storeMap['name']?.toString();
        _storetype = _parseIntFlexible(storeMap, ['storetype']);
        _storeController.text = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    // 榛樿涓氬姟鍛樹粠user璇诲彇
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        _salesid = userMap['userid']?.toString();
        _salesname = userMap['name']?.toString();
        _salesController.text = userMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    _loadDefaultWarehouse();
  }

  void _loadDefaultWarehouse() {
    if (_storeid == null) return;
    request(HttpApi.counterGetList, {
      'sids': _storeid.toString(),
      'stopflag': 0,
      'cond': '',
      'is_page': 1,
      'page': 1,
    }).then((result) {
      if (!mounted) return;
      final data = result['data'];
      final list =
          (data is Map<String, dynamic> ? data['list'] : null) as List? ?? [];
      if (list.isNotEmpty) {
        final first = list.first as Map<String, dynamic>;
        setState(() {
          _counterid = first['counterid']?.toString();
          _warehouseController.text =
              first['countername']?.toString() ?? '';
        });
      }
    });
  }

  static int? _parseIntFlexible(
      Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final val = map[key];
      if (val == null) continue;
      if (val is int) return val;
      if (val is double) return val.toInt();
      final str = val.toString().trim();
      if (str.isEmpty) continue;
      final parsed = int.tryParse(str);
      if (parsed != null) return parsed;
      final d = double.tryParse(str);
      if (d != null) return d.toInt();
    }
    return null;
  }

  @override
  void dispose() {
    _scanDebounceTimer?.cancel();
    _custController.dispose();
    _warehouseController.dispose();
    _remarkController.dispose();
    _storeController.dispose();
    _salesController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  void _loadDetail([Map<String, dynamic>? overrideParams]) {
    setState(() => _detailLoading = true);
    final Map<String, dynamic> params = overrideParams ??
        Map<String, dynamic>.from(widget.billData!);

    request(HttpApi.pfOrderGetInfo, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _billData = data;
          _custController.text = data['custname']?.toString() ?? '';
          _storeController.text = data['storename']?.toString() ?? '';
          _warehouseController.text =
              data['countername']?.toString() ?? '';
          _salesController.text = data['salesname']?.toString() ?? '';
          _remarkController.text = data['remark']?.toString() ?? '';

          _custid = data['custid']?.toString();
          _storeid =
              _parseIntFlexible(data, ['bsid', 'storeid']);
          _storename = data['storename']?.toString();
          _storetype = _parseIntFlexible(data, ['storetype']);
          _counterid = data['counterid']?.toString();
          _salesid = data['salesid']?.toString();
          _salesname = data['salesname']?.toString();

          final list = data['detaillist'] as List? ?? [];
          for (final row in _items) {
            row.dispose();
          }
          _items.clear();
          for (final v in list) {
            if (v is! Map) continue;
            final c = Map<String, dynamic>.from(v);
            final row = _PFDetailRow();
            row.prodid = c['prodid']?.toString() ??
                c['productid']?.toString() ?? '';
            row.nameController.text =
                c['productname']?.toString() ??
                    c['name']?.toString() ?? '';
            row.qtyController.text = c['qty']?.toString() ?? '0';
            row.priceController.text =
                c['price']?.toString() ?? '0';
            row.presentQtyController.text =
                c['presentqty']?.toString() ?? '0';

            row.amt = double.tryParse(c['amt']?.toString() ?? '');
            row.rawData = c;
            _items.add(row);
          }
        });
      }
    }).whenComplete(() {
      if (mounted) setState(() => _detailLoading = false);
    });
  }

  // 鈺愨晲锟?鎻愪氦/淇濆瓨 鈺愨晲锟?
  void _submit() {
    if (!_isSigned) {
      if (_custid == null || _custid!.isEmpty) {
        Toast.show('璇烽€夋嫨瀹㈡埛');
        return;
      }
      if (_storeid == null) {
        Toast.show('璇烽€夋嫨鏈烘瀯');
        return;
      }
      if (_counterid == null || _counterid!.isEmpty) {
        Toast.show('璇烽€夋嫨浠撳簱');
        return;
      }
    }

    if (!_isEdit) {
      if (!_formKey.currentState!.validate()) return;
    }

    final List<_PFDetailRow> submitItems;
    if (_isEdit) {
      submitItems = List.from(_items);
    } else {
      submitItems = _items
          .where((row) =>
              (row.prodid ?? '').isNotEmpty &&
              row.nameController.text.trim().isNotEmpty)
          .toList();
    }

    if (submitItems.isEmpty) {
      Toast.show('璇烽€夋嫨鍟嗗搧');
      return;
    }

    if (!_isEdit) {
      for (final row in submitItems) {
        final qty = double.tryParse(row.qtyController.text) ?? 0;
        if (qty == 0) {
          Toast.show('请填写数量');
          return;
        }
      }
    }

    setState(() => _submitAction = _PFAction.save);

    final detaillist = _buildSubmitDetailList();
    double totalQty = 0;
    double totalAmt = 0;
    for (final item in detaillist) {
      totalQty = MathUtils.add(
          totalQty,
          double.tryParse(item['qty']?.toString() ?? '0') ?? 0);
      totalAmt = MathUtils.add(
          totalAmt,
          double.tryParse(item['amt']?.toString() ?? '0') ?? 0);
    }

    final Map<String, dynamic> params;
    if (_isEdit) {
      params = Map<String, dynamic>.from(_billData!);
    } else {
      final now = DateTime.now();
      final billdate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      params = {
        'billtype': 0,
        'billdate': billdate,
        'signflag': 0,
        'freeamt': 0,
        'fileLists': [],
      };
    }

    params['billqty'] = totalQty;
    params['billamt'] = MathUtils.roundTo(totalAmt);
    params['detaillist'] = detaillist;
    params['remark'] = _remarkController.text.trim();
    params['custname'] = _custController.text.trim();
    params['custid'] = _custid ?? '';
    params['bsid'] = _storeid ?? '';
    params['storename'] = _storename ?? '';
    params['storetype'] = _storetype ?? '';
    params['counterid'] = _counterid ?? '';
    params['countername'] = _warehouseController.text.trim();
    params['salesid'] = _salesid ?? '';
    params['salesname'] = _salesname ?? '';

    request(HttpApi.pfOrderSave, params).then((result) {
      if (!mounted) return;
      Toast.show(result['retmsg']?.toString() ?? '淇濆瓨鎴愬姛');
      final retData = result['data'];
      if (retData is Map<String, dynamic>) {
        if (_isEdit) {
          _loadDetail(Map<String, dynamic>.from(retData));
        } else {
          final String? newBillid =
              retData['billid']?.toString();
          if (newBillid != null && newBillid.isNotEmpty) {
            setState(() => _newBillid = newBillid);
            _loadDetail(Map<String, dynamic>.from(retData));
          } else {
            Navigator.pop(context, true);
          }
        }
      } else {
        if (!_isEdit) Navigator.pop(context, true);
      }
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFAction.none);
    });
  }

  List<Map<String, dynamic>> _buildSubmitDetailList() {
    return _items.map((row) {
      final qty = double.tryParse(row.qtyController.text) ?? 0;
      final price = double.tryParse(row.priceController.text) ?? 0;
      final presentqty =
          double.tryParse(row.presentQtyController.text) ?? 0;
      final jsqty = MathUtils.add(qty, presentqty);
      final item = row.rawData != null
          ? Map<String, dynamic>.from(row.rawData!)
          : <String, dynamic>{};
      item['productname'] = row.nameController.text.trim();
      item['prodname'] = row.nameController.text.trim();
      item['qty'] = qty;
      item['price'] = price;
      item['amt'] = row.amt ?? MathUtils.mul(qty, price);
      item['jsqty'] = jsqty;
      item['presentqty'] = presentqty;
      item['batchno'] = '';
      item['prodid'] = row.prodid ?? '';
      return item;
    }).toList();
  }

  // 鈺愨晲锟?瀹℃牳 鈺愨晲锟?
  Future<void> _sign() async {
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('鎻愮ず'),
        content: const Text('纭畾瀹℃牳鍗曟嵁鍚楋紵'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('鍙栨秷')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('纭畾')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _PFAction.sign);
    request(HttpApi.pfOrderSign, _billData!).then((result) {
      if (!mounted) return;
      Toast.show('瀹℃牳鎴愬姛');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFAction.none);
    });
  }

  Future<void> _retsign() async {
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('鎻愮ず'),
        content: const Text('纭畾鍙嶅鏍稿崟鎹悧锟?),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('鍙栨秷')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('纭畾')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _PFAction.retsign);
    request(HttpApi.pfOrderRetsign, _billData!).then((result) {
      if (!mounted) return;
      Toast.show('鍙嶅鎴愬姛');
      _loadDetail();
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFAction.none);
    });
  }

  Future<void> _delBill() async {
    if (_billData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('鎻愮ず'),
        content: const Text('纭畾鍒犻櫎鍚楋紵'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('鍙栨秷')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('纭畾')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitAction = _PFAction.delete);
    request(HttpApi.pfOrderDelBill, _billData!).then((result) {
      if (!mounted) return;
      Toast.show('鍒犻櫎鎴愬姛');
      Navigator.pop(context, true);
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFAction.none);
    });
  }

  Future<void> _print() async {
    if (_billData == null) return;
    setState(() => _submitAction = _PFAction.print);
    request('airprint/setWxPrintRw', {
      'menuid': '060102',
      'data': _billData,
    }).then((result) {
      if (!mounted) return;
      Toast.show('鎵撳嵃鎴愬姛');
    }).whenComplete(() {
      if (mounted) setState(() => _submitAction = _PFAction.none);
    });
  }

  // 鈺愨晲锟?閫夋嫨鍟嗗搧锛堟壒鍙戣锟?mergData锟?鈺愨晲锟?
  Future<void> _selectProducts() async {
    if (_storeid == null) {
      Toast.show('璇峰厛閫夋嫨鏈烘瀯');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('璇峰厛閫夋嫨浠撳簱');
      return;
    }
    if (_custid == null || _custid!.isEmpty) {
      Toast.show('璇峰厛閫夋嫨瀹㈡埛鍚嶇О');
      return;
    }

    final mergData = {
      'bsid': _storeid,
      'custid': _custid ?? '',
      'pfpriceflag': 1,
      'itemstatus': '1,2',
      'needbatchflag': 1,
      'counterid': _counterid,
    };

    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectProductPage(
          mergData: mergData,
          multiple: true,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        for (final prod in result) {
          final row = _PFDetailRow();
          row.prodid = prod['prodid']?.toString() ??
              prod['productid']?.toString() ?? '';
          row.nameController.text =
              prod['productname']?.toString() ??
                  prod['name']?.toString() ?? '';
          row.qtyController.text = (prod['qty'] ?? 1).toString();
          row.priceController.text =
              prod['pfprice1']?.toString() ??
                  prod['price']?.toString() ??
                  '0';
          row.presentQtyController.text = (prod['giftqty'] ?? 0).toString();
          row.rawData =
              Map<String, dynamic>.from(prod);
          _defValSet(row.rawData!);
          _items.add(row);
        }
      });
    }
  }

  // 鈺愨晲锟?鎵爜 鈺愨晲锟?
  Future<void> _scanBarcode() async {
    if (_storeid == null) {
      Toast.show('璇峰厛閫夋嫨鏈烘瀯');
      return;
    }
    if (_counterid == null || _counterid!.isEmpty) {
      Toast.show('璇峰厛閫夋嫨浠撳簱');
      return;
    }
    if (_custid == null || _custid!.isEmpty) {
      Toast.show('璇峰厛閫夋嫨瀹㈡埛鍚嶇О');
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => Container(
        height: 200,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('鎵爜褰曞叆',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '杈撳叆鎴栨壂鎻忔潯锟?,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) =>
                  Navigator.pop(context, val),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _handleScannedBarcode(result);
    }
  }

  Future<void> _handleScannedBarcode(String scanCode,
      {FocusNode? returnFocusNode}) async {
    if (_storeid == null) {
      Toast.show('璇峰厛閫夋嫨鏈烘瀯');
      returnFocusNode?.requestFocus();
      return;
    }
    if (_counterid == null) {
      Toast.show('璇峰厛閫夋嫨浠撳簱');
      returnFocusNode?.requestFocus();
      return;
    }
    if (_custid == null) {
      Toast.show('璇峰厛閫夋嫨瀹㈡埛');
      returnFocusNode?.requestFocus();
      return;
    }

    final result = await request(HttpApi.productGetList, {
      'scancode': scanCode,
      'is_page': 1,
      'page': 1,
      'pagesize': 10,
      'storeid': _storeid ?? '',
      'counterid': _counterid ?? '',
      'custid': _custid ?? '',
      'pfpriceflag': 1,
      'needbatchflag': 1,
      'itemstatusin': '1,2',
    });

    if (!mounted) return;
    final data = result['data'];
    final list =
        (data is Map<String, dynamic> ? data['list'] : null)
                as List? ??
            [];
    if (list.isEmpty) {
      Toast.show('鏈壘鍒板晢锟?);
      returnFocusNode?.requestFocus();
      return;
    }

    final prod = list.first as Map<String, dynamic>;

    // === 瀵归綈 lxAss锛歞efValSet 璧嬪€煎晢鍝佸垵濮嬶拷?===
    final qty = num.tryParse((prod['qty'] ?? 1).toString())?.toDouble() ?? 1;
    final giftQty =
        num.tryParse((prod['giftqty'] ?? 0).toString())?.toDouble() ?? 0;
    // 浠锋牸浼樺厛绾э細custdiscountprice > 0 ? custdiscountprice : (custprice ?? price)
    final price = _getScanPrice(prod);

    // === 瀵归綈 lxAss锛氭寜 barcode/productid/size/unit/supid/batchno 鏌ラ噸 ===
    final existingIndex = _findScanProductIndex(prod);

    if (existingIndex >= 0 && mounted) {
      // 閲嶅鍟嗗搧 锟?鎵撳紑璇︽儏寮圭獥缂栬緫宸叉湁琛岋紙瀵归綈 lxAss锟?
      await _showProDetailDrawer(_items[existingIndex], existingIndex);
    } else if (mounted) {
      // 鏂板晢锟?锟?鍏堟墦寮€璇︽儏寮圭獥锛岀‘璁ゅ悗鍐嶅姞鍏ュ垪琛紙瀵归綈 lxAss锟?
      final result2 = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ProDetailSheet(
          productData: Map<String, dynamic>.from(prod),
          initialPrice: price,
          initialQty: qty,
          initialGiftQty: giftQty,
          initialRemark: prod['remark']?.toString() ?? '',
          readOnly: false,
          onSelectUnitSize: (type) => _showExtendOptions(type, prod),
        ),
      );
      if (result2 != null && mounted) {
        setState(() {
          final row = _PFDetailRow();
          row.prodid = prod['prodid']?.toString() ??
              prod['productid']?.toString() ?? '';
          row.nameController.text =
              prod['productname']?.toString() ??
                  prod['name']?.toString() ?? '';
          row.qtyController.text =
              (result2['qty'] as double?)?.toStringAsFixed(1) ??
                  qty.toStringAsFixed(1);
          row.priceController.text =
              double.tryParse(result2['price']?.toString() ?? '')
                      ?.toStringAsFixed(2) ??
                  price.toStringAsFixed(2);
          row.presentQtyController.text =
              (result2['presentqty'] as double?)?.toStringAsFixed(0) ??
                  giftQty.toStringAsFixed(0);
          row.rawData = Map<String, dynamic>.from(prod);
          _defValSet(row.rawData!);
          row.amt = MathUtils.mul(
            double.tryParse(row.qtyController.text) ?? 0,
            double.tryParse(row.priceController.text) ?? 0,
          );
          // unshift 鍒板垪琛ㄩ浣嶏紙瀵归綈 lxAss锟?
          _items.insert(0, row);
        });
      }
    }

    returnFocusNode?.requestFocus();
  }

  /// lxAss 浠锋牸浼樺厛绾э細custdiscountprice > 0 ? custdiscountprice : (custprice ?? price)
  double _getScanPrice(Map<String, dynamic> prod) {
    final custdiscountprice =
        double.tryParse(prod['custdiscountprice']?.toString() ?? '') ?? 0;
    if (custdiscountprice > 0) return custdiscountprice;
    final custprice = double.tryParse(prod['custprice']?.toString() ?? '');
    if (custprice != null) return custprice; // custprice=0 涔熸槸鏈夋晥浠锋牸
    return double.tryParse(prod['price']?.toString() ?? '') ?? 0;
  }

  /// 锟?barcode/productid/size/unit/supid/batchno 鏌ユ壘宸插湪鍒楄〃涓殑鍟嗗搧绱㈠紩锛堝锟?lxAss锟?
  int _findScanProductIndex(Map<String, dynamic> prod) {
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i].rawData ?? {};
      if ((item['barcode']?.toString() ?? '') ==
              (prod['barcode']?.toString() ?? '') &&
          ((item['productid']?.toString() ?? '') ==
                      (prod['productid']?.toString() ?? '') ||
              (item['prodid']?.toString() ?? '') ==
                  (prod['productid']?.toString() ?? '')) &&
          (item['size']?.toString() ?? '') ==
              (prod['size']?.toString() ?? '') &&
          (item['unit']?.toString() ?? '') ==
              (prod['unit']?.toString() ?? '') &&
          (item['supid']?.toString() ?? '') ==
              (prod['supid']?.toString() ?? '') &&
          (item['batchno']?.toString() ?? '') ==
              (prod['batchno']?.toString() ?? '')) {
        return i;
      }
    }
    return -1;
  }

  // 鈺愨晲锟?鎵归噺鎿嶄綔 鈺愨晲锟?
  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) _selectedIndices.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.addAll(List.generate(_items.length, (i) => i));
      }
    });
  }

  /// 璋冩帴鍙ｆ煡璇㈣锟?鍗曚綅閫夐」
  Future<Map<String, dynamic>?> _showExtendOptions(String type, Map<String, dynamic> raw) async {
    final String productid = raw['prodid']?.toString() ??
        raw['productid']?.toString() ?? '';
    if (productid.isEmpty) return null;

    final params = <String, dynamic>{
      'productid': productid,
      'cgpriceflag': 1,
      'bsid': _storeid?.toString() ?? '',
      'custid': _custid ?? '',
      'itemtype': raw['itemtype']?.toString() ?? '',
      'packageflag': raw['packageflag']?.toString() ?? '',
      'specflag': raw['specflag']?.toString() ?? '',
      'pfpriceflag': 1,
      'needbatchflag': 1,
      'itemstatus': '1,2',
      'is_page': 1,
    };
    if (type == 'size') {
      params['counterid'] = _counterid ?? '';
    }

    final result = await request(HttpApi.productGetExtendList, params);
    if (!mounted) return null;
    final data = result['data'];
    final rawList = (data is Map<String, dynamic>
        ? (type == 'size' ? data['sizelist'] : data['packlist'])
        : null) as List? ?? [];
    if (rawList.isEmpty) {
      Toast.show('鏃犲彲锟?{type == 'unit' ? '鍗曚綅' : '瑙勬牸'}');
      return null;
    }

    // 瀛楁鏄犲皠锛歴electCom 锟?getProductExtendList 鐨勭壒娈婂锟?
    // size 锟?name: size/sname, id: sizeonlyid/onlyid
    // unit 锟?name: unit/sunit, id: unitonlyid/onlyid
    final list = rawList.map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      if (type == 'size') {
        m['_name'] = m['size']?.toString() ?? m['sname']?.toString() ?? '';
        m['_id'] = m['sizeonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
      } else {
        m['_name'] = m['unit']?.toString() ?? m['sunit']?.toString() ?? '';
        m['_id'] = m['unitonlyid']?.toString() ?? m['onlyid']?.toString() ?? '';
      }
      return m;
    }).toList();

    // 寮瑰嚭閫夋嫨鍒楄〃
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Text('閫夋嫨${type == 'unit' ? '鍗曚綅' : '瑙勬牸'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final item = list[i];
                  final String name = item['_name']?.toString() ?? '';
                  final String code = item['scode']?.toString() ??
                      item['code']?.toString() ?? '';
                  return GestureDetector(
                    onTap: () {
                      // lxAss selectSizeFn(pfsale) 锟?price = custprice
                      // lxAss selectUnitFn(pfsale) 锟?price = custprice
                      final price = type == 'size'
                          ? (item['custprice']?.toString() ??
                              item['pfprice1']?.toString() ??
                              item['sellprice']?.toString() ??
                              item['price']?.toString() ?? '')
                          : (item['custprice']?.toString() ??
                              item['cgprice']?.toString() ??
                              item['pfprice1']?.toString() ??
                              item['sellprice']?.toString() ??
                              item['price']?.toString() ?? '');
                      final sel = <String, dynamic>{
                        type: item[type]?.toString() ?? item['_name']?.toString() ?? '',
                        '${type}onlyid': item['_id']?.toString() ?? '',
                        'price': price,
                        'sellprice': item['sellprice']?.toString() ?? '',
                        'retailprice': item['sellprice']?.toString() ?? item['retailprice']?.toString() ?? '',
                        'stockqty': item['stockqty']?.toString() ?? item['stock']?.toString() ?? '',
                        'barcode': item['sbarcode']?.toString() ?? item['barcode']?.toString() ?? '',
                        'custprice': item['custprice']?.toString() ?? '',
                        'refprice': item['refprice']?.toString() ?? '',
                        'inprice': item['inprice']?.toString() ?? '',
                        'code': item['scode']?.toString() ?? item['code']?.toString() ?? '',
                      };
                      Navigator.pop(ctx, sel);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: const Color(0xFFF3F4F6))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name.isNotEmpty ? name : '-',
                                    style: const TextStyle(fontSize: 15, color: Color(0xFF111827))),
                                if (code.isNotEmpty)
                                  Text(code,
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    return selected;
  }

  Future<void> _showProDetailDrawer(
      _PFDetailRow row, int index) async {
    final raw = row.rawData ?? {};
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProDetailSheet(
        productData: raw,
        initialPrice: double.tryParse(row.priceController.text) ?? 0,
        initialQty: double.tryParse(row.qtyController.text) ?? 0,
        initialGiftQty: double.tryParse(row.presentQtyController.text) ?? 0,
        initialRemark: raw['remark']?.toString() ?? '',
        readOnly: _readOnly,
        onSelectUnitSize: (type) => _showExtendOptions(type, raw),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final r = _items[index];
        r.priceController.text =
            double.tryParse(result['price']?.toString() ?? '')?.toStringAsFixed(2) ??
                r.priceController.text;
        r.qtyController.text =
            (result['qty'] as double?)?.toString() ??
                result['qty']?.toString() ??
                r.qtyController.text;
        r.presentQtyController.text =
            (result['presentqty'] as double?)?.toStringAsFixed(0) ??
                result['presentqty']?.toString() ??
                r.presentQtyController.text;
        r.amt = MathUtils.mul(
          double.tryParse(r.qtyController.text) ?? 0,
          double.tryParse(r.priceController.text) ?? 0,
        );
        if (r.rawData != null) {
          r.rawData!['price'] = double.tryParse(r.priceController.text) ?? 0;
          r.rawData!['qty'] = double.tryParse(r.qtyController.text) ?? 0;
          r.rawData!['presentqty'] = double.tryParse(r.presentQtyController.text) ?? 0;
          r.rawData!['remark'] = result['remark']?.toString() ?? '';
          r.rawData!['amt'] = r.amt;
          // 鏇存柊鍗曚綅/瑙勬牸
          if (result['unit'] != null) r.rawData!['unit'] = result['unit'];
          if (result['unitonlyid'] != null) r.rawData!['unitonlyid'] = result['unitonlyid'];
          if (result['size'] != null) r.rawData!['size'] = result['size'];
          if (result['sizeonlyid'] != null) r.rawData!['sizeonlyid'] = result['sizeonlyid'];
          if (result['barcode'] != null) r.rawData!['barcode'] = result['barcode'];
          if (result['retailprice'] != null) r.rawData!['retailprice'] = result['retailprice'];
          if (result['stockqty'] != null) r.rawData!['stockqty'] = result['stockqty'];
          _amtJudge(r.rawData!);
        }
      });
    }
  }

  void _toggleIndex(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  bool get _isAllSelected =>
      _items.isNotEmpty && _selectedIndices.length == _items.length;

  void _batchDelete() {
    if (_selectedIndices.isEmpty) return;
    final count = _selectedIndices.length;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('鎻愮ず'),
        content: Text('纭畾鍒犻櫎閫変腑锟?$count 鏉℃槑缁嗭紵'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('鍙栨秷')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('纭畾')),
        ],
      ),
    ).then((confirm) {
      if (confirm != true) return;
      setState(() {
        final sorted = _selectedIndices.toList()
          ..sort((a, b) => b.compareTo(a));
        for (final i in sorted) {
          _items[i].dispose();
          _items.removeAt(i);
        }
        _selectedIndices.clear();
        _isSelectMode = false;
      });
    });
  }

  bool get _readOnly => _isEdit && _isSigned;

  // 鈺愨晲锟?姹囨€昏锟?鈺愨晲锟?
  /// 璁㈣揣鏁伴噺锛堜粎涓绘暟閲忥紝涓嶅惈璧犻€侊紝瀵归綈 lxAss 搴曢儴鍚堣锟?
  String get _totalOrderQty {
    double sum = 0;
    for (final row in _items) {
      sum += (double.tryParse(row.qtyController.text) ?? 0);
    }
    return sum.toStringAsFixed(1);
  }

  String get _totalAmt {
    double sum = 0;
    for (final row in _items) {
      if (row.amt != null) {
        sum = MathUtils.add(sum, row.amt!);
      } else {
        final qty = double.tryParse(row.qtyController.text) ?? 0;
        final price =
            double.tryParse(row.priceController.text) ?? 0;
        sum = MathUtils.add(sum, MathUtils.mul(qty, price));
      }
    }
    return MathUtils.roundTo(sum).toStringAsFixed(2);
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
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit
              ? (_isSigned ? '鎵瑰彂璁㈣揣璇︽儏' : '淇敼鎵瑰彂璁㈣揣')
              : '鏂板鎵瑰彂璁㈣揣',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: _detailLoading
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF006EFF)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final body = Column(
      children: [
        Expanded(
          child: CustomScrollView(
            cacheExtent: 800,
            slivers: [
              if (_isEdit)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: _buildBillStatusWidget(),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: _buildCard(
                    title: '鍗曟嵁淇℃伅',
                    child: _readOnly
                        ? _buildBillInfoReadonly()
                        : _buildBillInfoEditable(),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PFStickyHeaderDelegate(state: this),
              ),
              if (_items.isNotEmpty)
                SliverList.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) =>
                      RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8),
                      child: _PFDetailItem(
                        row: _items[index],
                        index: index,
                        isSelectMode: _isSelectMode,
                        isSelected:
                            _selectedIndices.contains(index),
                        readOnly: _readOnly,
                        onTap: () => _showProDetailDrawer(
                            _items[index], index),
                        onToggle: () =>
                            _toggleIndex(index),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: 8)),
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
    return _isEdit ? body : Form(key: _formKey, child: body);
  }

  Widget _buildBillStatusWidget() {
    final data = _billData ?? {};
    final String billno = data['billno']?.toString() ?? '-';
    final String createtime =
        data['createtime']?.toString() ?? '-';
    final String salesname =
        data['salesname']?.toString() ?? '';
    final String signtime = data['signtime']?.toString() ?? '';
    final String signusername =
        data['signusername']?.toString() ??
            data['signname']?.toString() ?? '';
    return _buildCard(
      title: '鍗曞彿锟?billno',
      titleRight: Text(
        _isSigned ? '宸插锟? : '寰呭锟?,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _isSigned
              ? const Color(0xFF00A870)
              : const Color(0xFFD54B5A),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('鍒跺崟淇℃伅锟?createtime',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A7A7A))),
                const SizedBox(width: 16),
                Text(salesname,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A7A7A))),
              ],
            ),
            if (_isSigned &&
                (signtime.isNotEmpty ||
                    signusername.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                      '瀹℃牳淇℃伅锟?{signtime.isNotEmpty ? signtime : '-'}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7A7A7A))),
                  const SizedBox(width: 16),
                  Text(
                      signusername.isNotEmpty
                          ? signusername
                          : '-',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7A7A7A))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBillInfoReadonly() {
    return Column(
      children: [
        _buildReadonlyField(
            label: '鏈烘瀯', value: _storeController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(
            label: '浠撳簱', value: _warehouseController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(
            label: '瀹㈡埛', value: _custController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(
            label: '涓氬姟锟?, value: _salesController.text),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildReadonlyField(
            label: '澶囨敞', value: _remarkController.text),
      ],
    );
  }

  Widget _buildBillInfoEditable() {
    return Column(
      children: [
        SelectFieldItem(
          label: '鏈烘瀯',
          required: false,
          value: _storeController.text,
          hint: '璇烽€夋嫨',
          onTap: () async {
            final result = await SelectStorePage.show(context,
                initialSelectedId: _storeid?.toString());
            if (result != null && mounted) {
              setState(() {
                _storeid = int.tryParse(
                    result['storeid']?.toString() ?? '');
                _storename =
                    result['storename']?.toString();
                _storetype = int.tryParse(
                    result['storetype']?.toString() ?? '');
                _storeController.text =
                    result['storename']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '浠撳簱',
          required: false,
          value: _warehouseController.text,
          hint: '璇烽€夋嫨',
          onTap: () async {
            final result = await SelectWarehousePage.show(
                context,
                bsid: _storeid,
                initialSelectedId: _counterid);
            if (result != null && mounted) {
              setState(() {
                _counterid =
                    result['counterid']?.toString();
                _warehouseController.text =
                    result['countername']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '瀹㈡埛',
          required: false,
          value: _custController.text,
          hint: '璇烽€夋嫨',
          onTap: () async {
            final result = await SelectCustomerPage.show(
                context,
                initialSelectedId: _custid);
            if (result != null && mounted) {
              setState(() {
                _custid =
                    result['custid']?.toString();
                _custController.text =
                    result['custname']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        SelectFieldItem(
          label: '涓氬姟锟?,
          required: false,
          value: _salesController.text,
          hint: '璇烽€夋嫨',
          onTap: () async {
            final result =
                await SelectSalespersonPage.show(context,
                    initialSelectedId: _salesid);
            if (result != null && mounted) {
              setState(() {
                _salesid =
                    result['salesid']?.toString();
                _salesname =
                    result['salesname']?.toString();
                _salesController.text =
                    result['salesname']?.toString() ?? '';
              });
            }
          },
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        _buildField(
          controller: _remarkController,
          label: '澶囨敞',
          hint: '璇疯緭鍏ュ娉ㄤ俊锟?,
          maxLines: 1,
          verticalPadding: 10,
        ),
      ],
    );
  }

  Widget _buildStickyHeader() {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        color: const Color(0xFFF5F5F5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isSigned) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _buildScanInput(),
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFEEEEEE),
                      width: 0.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF006EFF),
                              borderRadius:
                                  BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('鍟嗗搧鏄庣粏',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight:
                                        FontWeight.w600,
                                    color:
                                        Color(0xFF111827))),
                          ),
                          if (!_isSigned) ...[
                            GestureDetector(
                              onTap: _toggleSelectMode,
                              child: Row(
                                mainAxisSize:
                                    MainAxisSize.min,
                                children: [
                                  Icon(
                                      _isSelectMode
                                          ? Icons.close
                                          : Icons
                                              .delete_outline,
                                      size: 17,
                                      color: _isSelectMode
                                          ? const Color(
                                              0xFF6B7280)
                                          : const Color(
                                              0xFFFF4D4F)),
                                  const SizedBox(width: 2),
                                  Text(
                                      _isSelectMode
                                          ? '鍙栨秷'
                                          : '鍒犻櫎',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _isSelectMode
                                              ? const Color(
                                                  0xFF6B7280)
                                              : const Color(
                                                  0xFFFF4D4F),
                                          fontWeight:
                                              FontWeight
                                                  .w500)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _scanBarcode,
                              child: const Row(
                                mainAxisSize:
                                    MainAxisSize.min,
                                children: [
                                  BossSvgIcon(
                                      svgFile: 'scan.svg',
                                      size: 12),
                                  SizedBox(width: 2),
                                  Text('鎵弿',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(
                                              0xFF006EFF),
                                          fontWeight:
                                              FontWeight
                                                  .w500)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _selectProducts,
                              child: const Row(
                                mainAxisSize:
                                    MainAxisSize.min,
                                children: [
                                  Icon(
                                      Icons
                                          .add_circle_outline,
                                      size: 16,
                                      color: Color(
                                          0xFF006EFF)),
                                  SizedBox(width: 2),
                                  Text('鏂板',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(
                                              0xFF006EFF),
                                          fontWeight:
                                              FontWeight
                                                  .w500)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Divider(
                        height: 1,
                        color: Color(0xFFE5E7EB)),
                    Container(
                      color: const Color(0xFFF9FAFB),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: const Row(
                        children: [
                          Expanded(
                              flex: 5,
                              child: Text('鍟嗗搧淇℃伅',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Color(0xFF6B7280),
                                      fontWeight:
                                          FontWeight.w500))),
                          Expanded(
                              flex: 2,
                              child: Text('浠锋牸',
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Color(0xFF6B7280),
                                      fontWeight:
                                          FontWeight.w500))),
                          Expanded(
                              flex: 2,
                              child: Text('璧狅拷?,
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Color(0xFF6B7280),
                                      fontWeight:
                                          FontWeight.w500))),
                          Expanded(
                              flex: 3,
                              child: Text('鏁伴噺',
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Color(0xFF6B7280),
                                      fontWeight:
                                          FontWeight.w500))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_items.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LoadAssetImage('state/zwsp',
                          width: 80, height: 80),
                      const SizedBox(height: 12),
                      const Text('鏆傛棤鍟嗗搧鏄庣粏',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const BossSvgIcon(
              svgFile: 'scan.svg',
              size: 20,
              color: Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _scanController,
                focusNode: _scanFocusNode,
                keyboardType: TextInputType.none,
                decoration: const InputDecoration(
                  hintText: '鎵弿鍟嗗搧鏉＄爜',
                  hintStyle: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9CA3AF)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _scanController.clear(),
            child: const Icon(Icons.close,
                size: 18, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    Widget? titleRight,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF006EFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (titleRight != null) titleRight,
              ],
            ),
          ),
          const Divider(
              height: 1, color: Color(0xFFE5E7EB)),
          child,
        ],
      ),
    );
  }

  Widget _buildReadonlyField({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF374151))),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF111827)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String hint = '',
    int maxLines = 1,
    double verticalPadding = 10,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 14, vertical: verticalPadding),
      child: Row(
        crossAxisAlignment: maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF374151))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF111827)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFD1D5DB)),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.only(bottom: 2),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_isSelectMode) {
      return _buildBatchDeleteBar();
    }
    if (_readOnly) {
      return Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
              top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    '璁㈣揣鏁伴噺锟?_totalOrderQty锛屽叡${_items.length}椤癸紝鎬婚噾棰濓細楼$_totalAmt',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    label: '鍙嶅锟?,
                    onTap: () {
                      if (!PermissionUtils.checkPermission(
                          '012206', showTip: true)) return;
                      _retsign();
                    },
                    primary: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    label: '鎵撳嵃',
                    onTap: () {
                      if (!PermissionUtils.checkPermission(
                          '012207', showTip: true)) return;
                      _print();
                    },
                    primary: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (!_isEdit) {
      return Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
              top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    '璁㈣揣鏁伴噺锟?_totalOrderQty锛屽叡${_items.length}椤癸紝鎬婚噾棰濓細楼$_totalAmt',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    label: '淇濆瓨',
                    onTap: _submit,
                    loading: _submitAction == _PFAction.save,
                    primary: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 寰呭鏍哥紪杈戞ā锟?
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  '璁㈣揣鏁伴噺锟?_totalOrderQty锛屽叡${_items.length}椤癸紝鎬婚噾棰濓細楼$_totalAmt',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  label: '淇濆瓨',
                  onTap: () {
                    if (!PermissionUtils.checkPermission(
                        '012203', showTip: true)) return;
                    _submit();
                  },
                  loading: _submitAction == _PFAction.save,
                  primary: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  label: '瀹℃牳',
                  onTap: () {
                    if (!PermissionUtils.checkPermission(
                        '012205', showTip: true)) return;
                    _sign();
                  },
                  loading: _submitAction == _PFAction.sign,
                  primary: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatchDeleteBar() {
    final selectedCount = _selectedIndices.length;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleSelectAll,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _isAllSelected,
                    activeColor: const Color(0xFF006EFF),
                    onChanged: (_) => _toggleSelectAll(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('鍏拷?, style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              ],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: selectedCount > 0 ? _batchDelete : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: selectedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFFD1D5DB),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD1D5DB),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('鍒犻櫎閫変腑($selectedCount)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onTap,
    bool loading = false,
    bool primary = true,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: loading
              ? const Color(0xFFB0C4DE)
              : primary
                  ? const Color(0xFF006EFF)
                  : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: primary
              ? null
              : Border.all(
                  color: const Color(0xFFDEDEDE)),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white))
            : Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: primary
                      ? Colors.white
                      : const Color(0xFF333333),
                ),
              ),
      ),
    );
  }
}

/// 鎵瑰彂璁㈣揣鏄庣粏琛屾暟锟?
class _PFDetailRow {
  _PFDetailRow() {
    initFocusListeners();
  }

  final TextEditingController nameController =
      TextEditingController();
  final TextEditingController qtyController =
      TextEditingController(text: '1');
  final TextEditingController priceController =
      TextEditingController();
  final TextEditingController presentQtyController =
      TextEditingController(text: '0');
  final FocusNode priceFocusNode = FocusNode();
  final FocusNode presentQtyFocusNode = FocusNode();
  final FocusNode qtyFocusNode = FocusNode();
  String? prodid;
  double? amt;
  Map<String, dynamic>? rawData;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    presentQtyController.dispose();
    priceFocusNode.dispose();
    presentQtyFocusNode.dispose();
    qtyFocusNode.dispose();
  }

  static void _addOnFocusSelectAll(
      FocusNode node, TextEditingController controller) {
    node.addListener(() {
      if (node.hasFocus && controller.text.isNotEmpty) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      }
    });
  }

  void initFocusListeners() {
    _addOnFocusSelectAll(priceFocusNode, priceController);
    _addOnFocusSelectAll(
        presentQtyFocusNode, presentQtyController);
    _addOnFocusSelectAll(qtyFocusNode, qtyController);
  }
}

/// 鏄庣粏锟?Widget
class _PFDetailItem extends StatefulWidget {
  final _PFDetailRow row;
  final int index;
  final bool isSelectMode;
  final bool isSelected;
  final bool readOnly;
  final VoidCallback onToggle;
  final VoidCallback? onTap;

  const _PFDetailItem({
    required this.row,
    required this.index,
    this.isSelectMode = false,
    this.isSelected = false,
    this.readOnly = false,
    required this.onToggle,
    this.onTap,
  });

  @override
  State<_PFDetailItem> createState() => _PFDetailItemState();
}

class _PFDetailItemState extends State<_PFDetailItem> {
  TextEditingController get _priceCtrl =>
      widget.row.priceController;
  TextEditingController get _giftCtrl =>
      widget.row.presentQtyController;
  TextEditingController get _qtyCtrl =>
      widget.row.qtyController;

  final FocusNode _priceFocus = FocusNode();
  final FocusNode _giftFocus = FocusNode();
  final FocusNode _qtyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _PFDetailRow._addOnFocusSelectAll(
        _priceFocus, _priceCtrl);
    _PFDetailRow._addOnFocusSelectAll(_giftFocus, _giftCtrl);
    _PFDetailRow._addOnFocusSelectAll(_qtyFocus, _qtyCtrl);
  }

  @override
  void dispose() {
    _priceFocus.dispose();
    _giftFocus.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  void _notifyChange() {
    final newPrice =
        double.tryParse(_priceCtrl.text) ?? 0;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final giftQty = double.tryParse(_giftCtrl.text) ?? 0;
    final raw = widget.row.rawData;
    if (raw != null) {
      raw['price'] = newPrice;
      raw['qty'] = qty;
      raw['presentqty'] = giftQty;
      _amtJudge(raw);
    }
    widget.row.amt = MathUtils.mul(qty, newPrice);
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.row.rawData;
    final String barcode = raw?['barcode']?.toString() ??
        raw?['selfbarcode']?.toString() ?? '';
    final String retailPrice =
        (double.tryParse(raw?['sellprice']?.toString() ??
                    raw?['retailprice']?.toString() ??
                    '0') ??
                0)
            .toStringAsFixed(2);

    return Container(
      decoration: BoxDecoration(
        color: widget.index.isOdd
            ? const Color(0xFFFAFAFA)
            : Colors.white,
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isSelectMode) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: widget.isSelected,
                      activeColor:
                          const Color(0xFF006EFF),
                      onChanged: (_) =>
                          widget.onToggle(),
                      materialTapTargetSize:
                          MaterialTapTargetSize
                              .shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 5,
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        () {
                          final productName = raw?['productname']?.toString() ??
                              raw?['name']?.toString() ?? '';
                          final size = raw?['size']?.toString() ?? '';
                          final unit = raw?['unit']?.toString() ?? '';
                          final buf = StringBuffer(productName);
                          if (size.isNotEmpty) buf.write('/$size');
                          if (unit.isNotEmpty) buf.write('$unit');
                          return buf.toString();
                        }(),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (barcode.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(barcode,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280))),
                      ],
                      const SizedBox(height: 2),
                      Text('闆跺敭浠凤細$retailPrice',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 34,
                            child: TextField(
                              controller: _priceCtrl,
                              focusNode: _priceFocus,
                              readOnly: widget.readOnly,
                              enabled:
                                  !widget.readOnly,
                              keyboardType: const TextInputType
                                  .numberWithOptions(
                                  decimal: true),
                              textAlign:
                                  TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(
                                      0xFF111827)),
                              decoration:
                                  const InputDecoration(
                                isDense: true,
                                contentPadding:
                                    EdgeInsets
                                        .symmetric(
                                        horizontal:
                                            4,
                                        vertical:
                                            8),
                                border:
                                    OutlineInputBorder(
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                                enabledBorder:
                                    OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color(
                                                0xFFE5E7EB)),
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                                focusedBorder:
                                    OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color(
                                                0xFF006EFF)),
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                              ),
                              onChanged: (_) =>
                                  _notifyChange(),
                              onSubmitted: (_) =>
                                  _notifyChange(),
                              onEditingComplete:
                                  _notifyChange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 34,
                            child: TextField(
                              controller: _giftCtrl,
                              focusNode: _giftFocus,
                              readOnly:
                                  widget.readOnly,
                              enabled:
                                  !widget.readOnly,
                              keyboardType:
                                  const TextInputType
                                      .numberWithOptions(),
                              textAlign:
                                  TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(
                                      0xFF111827)),
                              decoration:
                                  const InputDecoration(
                                isDense: true,
                                contentPadding:
                                    EdgeInsets
                                        .symmetric(
                                        horizontal:
                                            4,
                                        vertical:
                                            8),
                                border:
                                    OutlineInputBorder(
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                                enabledBorder:
                                    OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color(
                                                0xFFE5E7EB)),
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                                focusedBorder:
                                    OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color(
                                                0xFF006EFF)),
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                              ),
                              onChanged: (_) =>
                                  _notifyChange(),
                              onSubmitted: (_) =>
                                  _notifyChange(),
                              onEditingComplete:
                                  _notifyChange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 3,
                          child: SizedBox(
                            height: 34,
                            child: TextField(
                              controller: _qtyCtrl,
                              focusNode: _qtyFocus,
                              readOnly:
                                  widget.readOnly,
                              enabled:
                                  !widget.readOnly,
                              keyboardType: const TextInputType
                                  .numberWithOptions(
                                  decimal: true),
                              textAlign:
                                  TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(
                                      0xFF111827)),
                              decoration:
                                  const InputDecoration(
                                isDense: true,
                                contentPadding:
                                    EdgeInsets
                                        .symmetric(
                                        horizontal:
                                            4,
                                        vertical:
                                            8),
                                border:
                                    OutlineInputBorder(
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                                enabledBorder:
                                    OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color(
                                                0xFFE5E7EB)),
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                                focusedBorder:
                                    OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color(
                                                0xFF006EFF)),
                                        borderRadius: BorderRadius
                                            .all(
                                            Radius
                                                .circular(
                                                4))),
                              ),
                              onChanged: (_) =>
                                  _notifyChange(),
                              onSubmitted: (_) =>
                                  _notifyChange(),
                              onEditingComplete:
                                  _notifyChange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        widget.row.qtyController,
                        widget.row.priceController
                      ]),
                      builder: (_, __) {
                        final q = double.tryParse(widget
                                .row
                                .qtyController
                                .text) ??
                            0;
                        final p = double.tryParse(widget
                                .row
                                .priceController
                                .text) ??
                            0;
                        final a = (q * p)
                                .toStringAsFixed(2);
                        return Padding(
                          padding:
                              const EdgeInsets.only(top: 4),
                          child: Text('閲戦锟?a',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color:
                                      Color(0xFF6B7280))),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 绮樻€ц〃澶翠唬锟?
class _PFStickyHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  final _PfOrderEditPageState state;

  _PFStickyHeaderDelegate({required this.state});

  @override
  double get minExtent => _PFMinExtent;

  @override
  double get maxExtent => state._isSigned
      ? _PFMinExtent
      : _PFMaxExtent;

  static const double _PFScanHeight = 62.0;
  static const double _PFTitleHeight = 40.0;
  static const double _PFColumnHeight = 36.0;
  static const double _PFMinExtent =
      _PFTitleHeight + _PFColumnHeight;
  static const double _PFMaxExtent =
      _PFScanHeight + _PFMinExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset,
      bool overlapsContent) {
    return state._buildStickyHeader();
  }

  @override
  bool shouldRebuild(
          covariant SliverPersistentHeaderDelegate
              oldDelegate) =>
      true;
}

// =================== 鍟嗗搧璇︽儏鎶藉眽 ===================
class _ProDetailSheet extends StatefulWidget {
  final Map<String, dynamic> productData;
  final double initialPrice;
  final double initialQty;
  final double initialGiftQty;
  final String initialRemark;
  final bool readOnly;
  final Future<Map<String, dynamic>?> Function(String type)? onSelectUnitSize;

  const _ProDetailSheet({
    required this.productData,
    required this.initialPrice,
    required this.initialQty,
    required this.initialGiftQty,
    required this.initialRemark,
    this.readOnly = false,
    this.onSelectUnitSize,
  });

  @override
  State<_ProDetailSheet> createState() => _ProDetailSheetState();
}

class _ProDetailSheetState extends State<_ProDetailSheet> {
  late final Map<String, dynamic> _localData;
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _giftCtrl;
  late TextEditingController _remarkCtrl;

  @override
  void initState() {
    super.initState();
    // 娣辨嫹璐濓紝闃叉淇敼鏃舵薄鏌撳師濮嬫暟锟?
    _localData = Map<String, dynamic>.from(widget.productData);
    _priceCtrl = TextEditingController(text: widget.initialPrice.toStringAsFixed(2));
    final qty = widget.initialQty;
    _qtyCtrl = TextEditingController(
      text: qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2),
    );
    _giftCtrl = TextEditingController(text: widget.initialGiftQty.toStringAsFixed(0));
    _remarkCtrl = TextEditingController(text: widget.initialRemark);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _giftCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _localData;
    final String name = data['productname']?.toString() ?? data['name']?.toString() ?? '';
    final String barcode = data['barcode']?.toString() ?? '';
    final double spVal = double.tryParse(
      data['saleprice']?.toString() ?? data['retailprice']?.toString()
          ?? data['sellprice']?.toString() ?? '0',
    ) ?? 0;
    final String saleprice = spVal.toStringAsFixed(2);
    final String shelves = data['shelves']?.toString() ?? '';
    final String unit = data['unit']?.toString() ?? '';
    final String size = data['size']?.toString() ?? '';

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Text(
                    '鍟嗗搧璇︽儏',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 88,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unit.isNotEmpty ? '$name/$unit' : name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          if (barcode.isNotEmpty) ...[const SizedBox(height: 4), Text(barcode, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('闆跺敭浠凤細$saleprice', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              if (shelves.isNotEmpty) ...[const SizedBox(width: 16), Text('璐ф灦鍙凤細$shelves', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 鍗曚綅閫夋嫨
                    _buildSelectField(label: '鍗曚綅', value: unit, onTap: widget.readOnly ? null : (data['packageflag']?.toString() != '1' || data['specflag']?.toString() == '1') ? () => _onSelect('unit') : null),
                    _buildDivider(),
                    // 瑙勬牸閫夋嫨
                    _buildSelectField(label: '瑙勬牸', value: size, onTap: widget.readOnly ? null : (data['specflag']?.toString() == '1' && (data['unitonlyid'] == null || data['unitonlyid']?.toString().isEmpty == true)) ? () => _onSelect('size') : null),
                    _buildDivider(),
                    // 鏁伴噺
                    _buildFormField(label: '鏁伴噺', controller: _qtyCtrl, isDecimal: true, readOnly: widget.readOnly, onChanged: (_) => setState(() {})),
                    _buildDivider(),
                    // 璧犻€佹暟锟?
                    _buildFormField(label: '璧犻€佹暟锟?, controller: _giftCtrl, readOnly: widget.readOnly, onChanged: (_) => setState(() {})),
                    _buildDivider(),
                    // 浠锋牸
                    _buildFormField(label: '浠锋牸', controller: _priceCtrl, isDecimal: true, readOnly: widget.readOnly, onChanged: (_) => setState(() {})),
                    _buildDivider(),
                    // 閲戦锛堝彧璇伙級
                    _buildAmountField(),
                    _buildDivider(),
                    // 澶囨敞
                    _buildFormField(label: '澶囨敞', controller: _remarkCtrl, readOnly: widget.readOnly, keyboardType: TextInputType.text, maxLines: 2),
                  ],
                ),
              ),
            ),
            if (!widget.readOnly)
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('鍙栨秷', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, {
                          'price': double.tryParse(_priceCtrl.text) ?? 0.0,
                          'qty': double.tryParse(_qtyCtrl.text) ?? 0.0,
                          'presentqty': double.tryParse(_giftCtrl.text) ?? 0.0,
                          'remark': _remarkCtrl.text.trim(),
                          'unit': _localData['unit']?.toString() ?? '',
                          'unitonlyid': _localData['unitonlyid']?.toString() ?? '',
                          'size': _localData['size']?.toString() ?? '',
                          'sizeonlyid': _localData['sizeonlyid']?.toString() ?? '',
                          'barcode': _localData['barcode']?.toString() ?? '',
                          'retailprice': _localData['retailprice']?.toString() ?? '',
                          'stockqty': _localData['stockqty']?.toString() ?? _localData['stock']?.toString() ?? '',
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006EFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('纭畾',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 閫夋嫨瑙勬牸鎴栧崟锟?
  Future<void> _onSelect(String type) async {
    final result = await widget.onSelectUnitSize?.call(type);
    if (result == null || !mounted) return;
    // 鏇存柊 rawData 骞跺埛锟?UI
    final data = _localData;
    if (type == 'unit') {
      data['unit'] = result['unit'] ?? '';
      data['unitonlyid'] = result['unitonlyid'] ?? '';
      final priceStr = result['price']?.toString() ?? '';
      final price = num.tryParse(priceStr);
      if (price != null) {
        data['price'] = price;
        _priceCtrl.text = price.toStringAsFixed(2);
      }
      if (result['sellprice'] != null) data['sellprice'] = result['sellprice'];
      if (result['retailprice'] != null) data['retailprice'] = result['retailprice'];
      if (result['stockqty'] != null) data['stockqty'] = result['stockqty'];
      if (result['barcode'] != null) data['barcode'] = result['barcode'];
    } else if (type == 'size') {
      data['size'] = result['size'] ?? '';
      data['sizeonlyid'] = result['sizeonlyid'] ?? '';
      final priceStr = result['price']?.toString() ?? '';
      final price = num.tryParse(priceStr);
      if (price != null) {
        data['price'] = price;
        _priceCtrl.text = price.toStringAsFixed(2);
      }
      if (result['sellprice'] != null) data['sellprice'] = result['sellprice'];
      if (result['retailprice'] != null) data['retailprice'] = result['retailprice'];
      if (result['stockqty'] != null) data['stockqty'] = result['stockqty'];
      if (result['barcode'] != null) data['barcode'] = result['barcode'];
    }
    setState(() {});
  }

  /// 鍙€夋嫨瀛楁锛堝崟锟?瑙勬牸锟?
  Widget _buildSelectField({required String label, required String value, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : '璇烽€夋嫨',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: value.isNotEmpty ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 16,
                color: const Color(0xFF9CA3AF),
              ),
          ],
        ),
      ),
    );
  }

  /// 閲戦鍙瀛楁
  Widget _buildAmountField() {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final amount = MathUtils.mul(qty, price);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 80,
            child: Text('閲戦',
                style: TextStyle(
                    fontSize: 14, color: Color(0xFF374151))),
          ),
          Expanded(
            child: Text(
              '${amount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    bool isDecimal = false,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.number,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              readOnly: readOnly,
              enabled: !readOnly,
              onChanged: onChanged,
              keyboardType:
                  isDecimal ? const TextInputType.numberWithOptions(decimal: true) : keyboardType,
              inputFormatters:
                  isDecimal ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))] : null,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFD1D5DB)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildDivider() => const Divider(height: 1, color: Color(0xFFF3F4F6));
}

// 鈺愨晲鈺?pfOrder 閲戦璁＄畻 鈥?瀵归綈 pfOrder/edit.vue 鐨?writeData / amtJudge / defValSet 鈺愨晲鈺?

/// amtJudge锛堝榻?pfOrder edit.vue锛?
void _amtJudge(Map<String, dynamic> raw) {
  final qty = double.tryParse(raw['qty']?.toString() ?? '') ?? 0;
  final price = double.tryParse(raw['price']?.toString() ?? '') ?? 0;
  final presentQty =
      double.tryParse(raw['presentqty']?.toString() ?? '') ?? 0;
  final sellprice =
      double.tryParse(raw['sellprice']?.toString() ?? '') ?? 0;
  final inprice = double.tryParse(raw['inprice']?.toString() ?? '') ?? 0;
  final costprice =
      double.tryParse(raw['costprice']?.toString() ?? '') ?? 0;
  final outtaxrate =
      double.tryParse(raw['outtaxrate']?.toString() ?? '') ?? 0;

  // amt = qty * price
  raw['amt'] = MathUtils.roundTo(MathUtils.mul(qty, price), 3);
  // notaxamt = amt / (1 + outtaxrate)
  raw['notaxamt'] = MathUtils.roundTo(
      MathUtils.divide(double.tryParse(raw['amt']?.toString() ?? '0') ?? 0,
          1 + outtaxrate),
      3);
  // sellamt = sellprice * (qty + presentqty)
  raw['sellamt'] =
      MathUtils.roundTo(MathUtils.mul(sellprice, qty + presentQty), 3);
  // inpriceamt = inprice * (qty + presentqty)
  raw['inpriceamt'] =
      MathUtils.roundTo(MathUtils.mul(inprice, qty + presentQty), 3);
  // costpriceamt = costprice * (qty + presentqty)
  final costpriceAmt = MathUtils.mul(costprice, qty + presentQty);
  // grossrateamt = amt - costpriceamt
  raw['grossrateamt'] = MathUtils.roundTo(
      MathUtils.subtract(
          double.tryParse(raw['amt']?.toString() ?? '0') ?? 0, costpriceAmt),
      3);
  // camt = amt - inpriceamt
  raw['camt'] = MathUtils.roundTo(
      MathUtils.subtract(
          double.tryParse(raw['amt']?.toString() ?? '0') ?? 0,
          double.tryParse(raw['inpriceamt']?.toString() ?? '0') ?? 0),
      3);
  // notaxamt锛堝啀娆¤绠楋紝淇濈暀 Vue 閲嶅璋冪敤鐨勮涓猴級
  raw['notaxamt'] = MathUtils.roundTo(
      MathUtils.divide(double.tryParse(raw['amt']?.toString() ?? '0') ?? 0,
          1 + outtaxrate),
      3);
  // grossrate = price > 0 ? (price - costprice) / price * 100 : 0
  if (price == 0) {
    raw['grossrate'] = 0;
  } else {
    raw['grossrate'] = MathUtils.roundTo(
        MathUtils.mul(MathUtils.divide(price - costprice, price), 100), 3);
  }
}

/// writeData锛堝榻?pfOrder edit.vue锛屽惈 zjsqty/ssqty锛?
void _writeData(String key, Map<String, dynamic> row) {
  final packagenum =
      double.tryParse(row['packagenum']?.toString() ?? '') ?? 1;
  if (key == 'jsqty') {
    row['jsqty'] =
        double.tryParse(row['jsqty']?.toString() ?? '') ?? 0;
    row['qty'] = MathUtils.roundTo(
        MathUtils.mul(
            double.tryParse(row['jsqty']?.toString() ?? '0') ?? 0,
            packagenum),
        1);
    final qty = double.tryParse(row['qty']?.toString() ?? '0') ?? 0;
    row['zjsqty'] = (qty / packagenum).floorToDouble();
    row['ssqty'] = MathUtils.roundTo(
        MathUtils.subtract(
            qty, MathUtils.mul(row['zjsqty'] as double, packagenum)),
        1);
  } else if (key == 'presentqty') {
    row['presentqty'] =
        double.tryParse(row['presentqty']?.toString() ?? '') ?? 0;
  } else if (key == 'qty') {
    row['qty'] = double.tryParse(row['qty']?.toString() ?? '') ?? 0;
    final qty = double.tryParse(row['qty']?.toString() ?? '0') ?? 0;
    row['jsqty'] = MathUtils.roundTo(MathUtils.divide(qty, packagenum), 1);
    row['zjsqty'] = (qty / packagenum).floorToDouble();
    row['ssqty'] = MathUtils.roundTo(
        MathUtils.subtract(
            qty, MathUtils.mul(row['zjsqty'] as double, packagenum)),
        1);
  } else if (key == 'zjsqty') {
    row['zjsqty'] =
        double.tryParse(row['zjsqty']?.toString() ?? '') ?? 0;
    final zjsqty = double.tryParse(row['zjsqty']?.toString() ?? '0') ?? 0;
    final ssqty = double.tryParse(row['ssqty']?.toString() ?? '0') ?? 0;
    row['qty'] = MathUtils.roundTo(
        MathUtils.add(MathUtils.mul(zjsqty, packagenum), ssqty), 1);
  } else if (key == 'ssqty') {
    row['ssqty'] =
        double.tryParse(row['ssqty']?.toString() ?? '') ?? 0;
    if (packagenum <= (double.tryParse(row['ssqty']?.toString() ?? '0') ?? 0)) {
      row['ssqty'] = packagenum - 1;
    }
    final zjsqty = double.tryParse(row['zjsqty']?.toString() ?? '0') ?? 0;
    final ssqty = double.tryParse(row['ssqty']?.toString() ?? '0') ?? 0;
    row['qty'] = MathUtils.roundTo(
        MathUtils.add(MathUtils.mul(zjsqty, packagenum), ssqty), 1);
  } else if (key == 'rate') {
    row['rate'] = double.tryParse(row['rate']?.toString() ?? '') ?? 0;
    final rate = double.tryParse(row['rate']?.toString() ?? '0') ?? 0;
    final refprice =
        double.tryParse(row['refprice']?.toString() ?? '0') ?? 0;
    row['price'] = MathUtils.roundTo(
        MathUtils.mul(MathUtils.divide(rate, 100), refprice), 2);
  } else if (key == 'refprice') {
    row['refprice'] =
        double.tryParse(row['refprice']?.toString() ?? '') ?? 0;
    final refprice =
        double.tryParse(row['refprice']?.toString() ?? '0') ?? 0;
    final rate = double.tryParse(row['rate']?.toString() ?? '0') ?? 0;
    row['price'] = MathUtils.roundTo(
        MathUtils.divide(MathUtils.mul(refprice, rate), 100) as double, 2);
    final qty = double.tryParse(row['qty']?.toString() ?? '0') ?? 0;
    row['ckjamt'] =
        MathUtils.roundTo(MathUtils.mul(refprice, qty), 3);
  } else if (key == 'price') {
    row['price'] = double.tryParse(row['price']?.toString() ?? '') ?? 0;
    final price = double.tryParse(row['price']?.toString() ?? '0') ?? 0;
    final refprice =
        double.tryParse(row['refprice']?.toString() ?? '0') ?? 0;
    row['rate'] = MathUtils.roundTo(
        MathUtils.mul(refprice > 0 ? MathUtils.divide(price, refprice) : 0, 100),
        1);
  } else if (key == 'amt') {
    row['amt'] = double.tryParse(row['amt']?.toString() ?? '') ?? 0;
    final amt = double.tryParse(row['amt']?.toString() ?? '0') ?? 0;
    final qty = double.tryParse(row['qty']?.toString() ?? '0') ?? 0;
    final refprice =
        double.tryParse(row['refprice']?.toString() ?? '0') ?? 0;
    final outtaxrate =
        double.tryParse(row['outtaxrate']?.toString() ?? '') ?? 0;
    row['price'] = MathUtils.roundTo(
        qty == 0
            ? (double.tryParse(row['price']?.toString() ?? '0') ?? 0)
            : MathUtils.divide(amt, qty),
        2);
    row['rate'] = MathUtils.roundTo(
        MathUtils.mul(refprice > 0 ? MathUtils.divide(
            double.tryParse(row['price']?.toString() ?? '0') ?? 0, refprice) : 0, 100),
        1);
    row['notaxamt'] = MathUtils.roundTo(
        MathUtils.divide(amt, 1 + outtaxrate), 3);
  }
  _amtJudge(row);
}

/// defValSet锛堝榻?pfOrder edit.vue 鈥?涓嶅惈 presentqty/rate锛?
void _defValSet(Map<String, dynamic> raw, {bool flag = true}) {
  if (flag) {
    raw['qty'] = double.tryParse(raw['qty']?.toString() ?? '') ?? 0;
  }
  raw['outtaxrate'] =
      double.tryParse(raw['outtaxrate']?.toString() ?? '') ?? 0;
  final qty = double.tryParse(raw['qty']?.toString() ?? '0') ?? 0;
  final packagenum =
      double.tryParse(raw['packagenum']?.toString() ?? '') ?? 1;
  raw['jsqty'] = MathUtils.roundTo(MathUtils.divide(qty, packagenum), 1);
  // price: custdiscountprice > custprice > price
  final custdiscountprice =
      double.tryParse(raw['custdiscountprice']?.toString() ?? '');
  final custprice = double.tryParse(raw['custprice']?.toString() ?? '');
  final oldPrice = double.tryParse(raw['price']?.toString() ?? '') ?? 0;
  raw['price'] = (custdiscountprice != null && custdiscountprice > 0)
      ? MathUtils.roundTo(custdiscountprice)
      : MathUtils.roundTo(custprice ?? oldPrice);
  // refprice = refprice ?? custprice
  if (raw['refprice'] == null) {
    raw['refprice'] = custprice ?? 0;
  }
  raw['refprice'] = MathUtils.roundTo(
      double.tryParse(raw['refprice']?.toString() ?? '') ?? 0);
  raw['costprice'] = MathUtils.roundTo(
      double.tryParse(raw['costprice']?.toString() ?? '') ?? 0);
  raw['saleprice'] = MathUtils.roundTo(
      double.tryParse(raw['sellprice']?.toString() ?? '') ?? 0);
  raw['intaxrate'] =
      double.tryParse(raw['intaxrate']?.toString() ?? '') ?? 0;
  raw['stockqty'] =
      double.tryParse(raw['stockqty']?.toString() ?? '') ?? 0;
  _writeData('price', raw);
  _amtJudge(raw);
}

