import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/user/label_print_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/gprinter.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:sp_util/sp_util.dart';

/// 未打印标签页
///
/// 业务逻辑参考小程序 ylx-boss subs/basis/printing/unprinted/index.vue：
/// 查询未打印列表 → 勾选/全选 → 修改份数 / 单条删除 / 批量删除 → 重新打印
class UnprintedListPage extends StatefulWidget {
  const UnprintedListPage({super.key});

  @override
  State<UnprintedListPage> createState() => _UnprintedListPageState();
}

class _UnprintedListPageState extends State<UnprintedListPage> {
  static const Color _primaryColor = Color(0xFF006EFF);
  static const Color _textColor = Color(0xFF333333);
  static const Color _bgColor = Color(0xFFF5F6FA);

  /// 未打印数据列表（每项附 _checked 勾选状态）
  List<Map<String, dynamic>> _dataList = [];

  /// 打印设置（含蓝牙配置 + 打印方式）
  Map<String, dynamic> _printSettings = {};

  /// 旧接口前台打印参数
  Map<String, dynamic> _labelPrintParams = {};

  /// 蓝牙打印进行中（全屏 loading 弹窗控制）
  bool _blePrinting = false;

  @override
  void initState() {
    super.initState();
    _getList();
    _loadPrintSettings();
  }

  // ─── 选中状态 ───

  int get _selectedCount => _dataList.where((e) => e['_checked'] == true).length;

  bool get _isAllSelected => _dataList.isNotEmpty && _dataList.every((e) => e['_checked'] == true);

  /// 半选中状态（部分选中）
  bool get _indeterminate => _selectedCount > 0 && _selectedCount < _dataList.length;

  // ─── 数据加载 ───

  /// 查询未打印列表
  Future<void> _getList() async {
    try {
      final res = await request(HttpApi.getNoPrintList, <String, dynamic>{}, false, false);
      if (res['retcode'] != 0 || !mounted) {
        return;
      }
      final data = res['data'];
      List<dynamic> list = [];
      if (data is List) {
        list = data;
      } else if (data is Map && data['list'] is List) {
        list = data['list'] as List;
      }
      setState(() {
        _dataList = list.map((e) {
          final item = Map<String, dynamic>.from(e as Map);
          item['_checked'] = false;
          return item;
        }).toList();
      });
    } catch (_) {}
  }

  /// 加载打印设置（含蓝牙配置 + 打印方式 + 旧接口前台打印状态）
  void _loadPrintSettings() {
    final clientId = _getClientId();
    request(HttpApi.getPrintSet, {'clientid': clientId}, false, false).then((res) {
      if (res['retcode'] == 0 && mounted) {
        setState(() => _printSettings = Map<String, dynamic>.from(res['data'] as Map? ?? {}));
      }
    }).catchError((_) {});

    request(HttpApi.getLabelPrintParams, {'type': 31}, false, false).then((res) {
      if (res['retcode'] == 0 && mounted) {
        setState(() => _labelPrintParams = Map<String, dynamic>.from(res['data'] as Map? ?? {}));
      }
    }).catchError((_) {});
  }

  /// 获取客户端设备标识
  String _getClientId() {
    final wxopenid = SpUtil.getString('wxopenid') ?? '';
    final storeStr = SpUtil.getString(Constant.store) ?? '';
    String sid = '';
    try {
      if (storeStr.isNotEmpty) {
        final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
        sid = storeMap['id']?.toString() ?? '';
      }
    } catch (_) {}
    if (wxopenid.isNotEmpty && sid.isNotEmpty) {
      return '${wxopenid}_$sid';
    }
    return wxopenid.isNotEmpty
        ? wxopenid
        : sid.isNotEmpty
            ? sid
            : 'default';
  }

  // ─── 勾选 / 份数 / 删除 ───

  /// 全选/取消全选
  void _toggleSelectAll(bool val) {
    setState(() {
      for (final item in _dataList) {
        item['_checked'] = val;
      }
    });
  }

  /// 修改打印份数（对齐小程序 qtyChange）
  void _qtyChanged(int index, int val) {
    setState(() => _dataList[index]['qty'] = val);
    request(HttpApi.updateNoPrintCopies, _dataList[index]).then((res) {
      if (res['retcode'] == 0) {
        Toast.show('份数已修改');
      }
    }).catchError((_) {});
  }

  /// 单条删除
  void _delSingle(int index) {
    _showConfirmDialog('确定删除该条数据吗？', () async {
      final item = _dataList[index];
      try {
        await request(HttpApi.delNoPrintList, [item]);
        if (mounted) {
          setState(() => _dataList.removeAt(index));
          Toast.show('删除成功');
        }
      } catch (_) {}
    });
  }

  /// 批量删除
  void _batchDel() {
    final selected = _dataList.where((e) => e['_checked'] == true).toList();
    if (selected.isEmpty) {
      return;
    }
    _showConfirmDialog('确定删除已选的 ${selected.length} 条数据吗？', () async {
      try {
        await request(HttpApi.delNoPrintList, selected);
        if (mounted) {
          setState(() => _dataList.removeWhere((e) => e['_checked'] == true));
          Toast.show('删除成功');
        }
      } catch (_) {}
    });
  }

  // ─── 重新打印 ───

  /// 重新打印（对齐小程序 rePrint：蓝牙打印 / 旧接口打印 / 打印已关闭）
  Future<void> _rePrint() async {
    final selected = _dataList.where((e) => e['_checked'] == true).toList();
    if (selected.isEmpty) {
      Toast.show('请先选择要打印的数据');
      return;
    }

    final printType = _printSettings['printType'] != null
        ? int.tryParse(_printSettings['printType'].toString()) ?? 1
        : 1;

    // 分支 1：蓝牙打印
    if (printType == 2) {
      final bleStatus = int.tryParse(_printSettings['lableBluetoothStatus']?.toString() ?? '') ?? 0;
      final deviceId = _printSettings['lableDeviceid']?.toString() ?? '';
      bool btOn = true;
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          btOn = await GPrinter.isBluetoothEnabled;
        } catch (_) {}
      }
      if (bleStatus != 1 || deviceId.isEmpty || !btOn) {
        if (!mounted) {
          return;
        }
        _showGoSettingsDialog('未连接打印机', '请先在打印设置中连接蓝牙打印机');
        return;
      }
      if (!mounted) {
        return;
      }
      _showConfirmDialog('确定打印 ${selected.length} 个标签吗？', () {
        _blePrintSelected(deviceId, selected);
      });
      return;
    }

    // 分支 2：旧接口打印
    if (printType == 1) {
      final labelPrintType =
          int.tryParse(_labelPrintParams['labelPrintType']?.toString() ?? '') ?? 0;
      if (labelPrintType != 1) {
        _showGoSettingsDialog('提示', '前台打印未启用，请前往打印设置开启');
        return;
      }
      _showConfirmDialog('确定打印吗？', () async {
        // 旧接口一次请求打印一条，逐条循环调用（对齐小程序）
        try {
          for (final item in selected) {
            await request(HttpApi.labelPrintRePrint, item);
          }
          if (mounted) {
            Toast.show('重新打印成功');
            _getList();
          }
        } catch (_) {}
      });
      return;
    }

    // 分支 3：打印已关闭
    _showGoSettingsDialog('提示', '打印已关闭，请前往打印设置开启');
  }

  /// 蓝牙打印选中数据（对齐 label_print_home 的 BLE 打印流程）
  Future<void> _blePrintSelected(String savedDeviceId, List<Map<String, dynamic>> selected) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      Toast.show('蓝牙打印暂仅支持 Android 设备');
      return;
    }
    if (_blePrinting) {
      return;
    }

    final granted = await GPrinter.requestPermissions();
    if (!granted) {
      Toast.show('蓝牙权限被拒绝，无法打印');
      return;
    }

    bool connected = false;
    try {
      connected = await GPrinter.isConnected;
    } catch (_) {}
    if (!connected && savedDeviceId.isNotEmpty && mounted) {
      _showBleLoading('正在连接打印机...');
      try {
        connected = await GPrinter.connect(savedDeviceId,
            name: _printSettings['lableBluetoothCode']?.toString() ?? '');
      } catch (_) {
        connected = false;
      }
      _hideBleLoading();
    }

    if (!connected) {
      if (!mounted) {
        return;
      }
      _showGoSettingsDialog('提示', '尚未在应用内连接蓝牙打印机，请前往打印设置连接');
      return;
    }

    // 构建打印明细（份数已在 TSC PRINT 指令中设置）
    final printNum = int.tryParse(_printSettings['print_num']?.toString() ?? '') ?? 1;
    final template = int.tryParse(_printSettings['print_template']?.toString() ?? '') ?? 1;
    final items = selected.map((item) {
      final qty = _clampQty(item['qty'] ?? printNum);
      return <String, dynamic>{
        'name': item['name'] ?? item['productname'] ?? '',
        'size': item['size'] ?? '',
        'barcode': item['barcode'] ?? '',
        'mprice1': item['mprice1'] ?? 0,
        'sellprice': item['sellprice'] ?? 0,
        'qty': qty,
        'copies': qty,
      };
    }).toList();

    if (!mounted) {
      return;
    }
    _showBleLoading('打印中...');
    _blePrinting = true;
    try {
      await GPrinter.printLabels(items, template: template);
      Toast.show('打印成功');
      // 打印成功后删除已打印数据（对齐小程序 blePrintLabels）
      request(HttpApi.delNoPrintList, selected, false, false).then((_) {
        if (mounted) {
          setState(() => _dataList.removeWhere((e) => e['_checked'] == true));
        }
      }).catchError((_) {});
    } on PlatformException catch (e) {
      Toast.show(e.message ?? '打印失败');
    } catch (_) {
      Toast.show('打印失败');
    } finally {
      _blePrinting = false;
      _hideBleLoading();
    }
  }

  // ─── 工具方法 ───

  int _clampQty(dynamic val) {
    final qty = int.tryParse(val?.toString() ?? '') ?? 1;
    return qty.clamp(1, 20);
  }

  /// 蓝牙打印全屏 loading 弹窗
  void _showBleLoading(String text) {
    if (!mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(text, style: const TextStyle(fontSize: 13, color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideBleLoading() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  /// 去打印设置引导弹窗
  void _showGoSettingsDialog(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(content, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const LabelPrintPage()),
              );
              // 设置页返回后刷新打印配置，保证用户可直接重试打印
              if (mounted) {
                _loadPrintSettings();
              }
            },
            child: const Text('去设置', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog(String content, VoidCallback onConfirm) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: Text(content, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('确定', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  // ─── 页面构建 ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '未打印标签'),
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _dataList.isEmpty
                  ? _buildEmptyView()
                  : ListView.builder(
                      cacheExtent: 800,
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      itemCount: _dataList.length,
                      itemBuilder: (ctx, i) {
                        final item = _dataList[i];
                        return _UnprintedCard(
                          item: item,
                          onToggle: () {
                            setState(() => item['_checked'] = !(item['_checked'] == true));
                          },
                          onDelete: () => _delSingle(i),
                          onQtyChanged: (val) => _qtyChanged(i, val),
                        );
                      },
                    ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
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

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 全选行
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleSelectAll(!_isAllSelected),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SquareCheckBox(checked: _isAllSelected, indeterminate: _indeterminate),
                const SizedBox(width: 6),
                Text('全选，已选$_selectedCount个',
                    style: const TextStyle(fontSize: 13, color: _textColor)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 操作按钮行
          Row(
            children: [
              // 删除
              Expanded(
                child: GestureDetector(
                  onTap: _batchDel,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: _primaryColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: const Text('删除', style: TextStyle(fontSize: 15, color: _primaryColor)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 重新打印
              Expanded(
                child: GestureDetector(
                  onTap: _rePrint,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _primaryColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '重新打印',
                      style:
                          TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600),
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
}

/// 未打印标签卡片（对齐规则：独立 StatelessWidget + RepaintBoundary）
class _UnprintedCard extends StatelessWidget {
  const _UnprintedCard({
    required this.item,
    required this.onToggle,
    required this.onDelete,
    required this.onQtyChanged,
  });

  final Map<String, dynamic> item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final ValueChanged<int> onQtyChanged;

  @override
  Widget build(BuildContext context) {
    const Color subTextColor = Color(0xFF7A7A7A);
    const Color borderColor = Color(0xFFE2E2E2);

    final name = item['name']?.toString() ?? item['productname']?.toString() ?? '';
    final size = item['size']?.toString() ?? '';
    final unit = item['unit']?.toString() ?? '';
    final barcode = item['barcode']?.toString() ?? '';
    final mprice1 = MathUtils.formatDecimal(2, item['mprice1'] ?? '0');
    final sellprice = MathUtils.formatDecimal(2, item['sellprice'] ?? '0');
    final qty = int.tryParse(item['qty']?.toString() ?? '') ?? 1;
    final checked = item['_checked'] == true;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            // 勾选框：相对整卡内容垂直居中
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _SquareCheckBox(checked: checked),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 商品名称 + 删除按钮
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          size.isNotEmpty ? '$name($size)' : name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFFF5252)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 条码
                  Text(barcode, style: const TextStyle(fontSize: 12, color: subTextColor)),
                  const SizedBox(height: 4),
                  // 会员价 + 零售价（含单位）
                  Row(
                    children: [
                      Expanded(
                        child: Text('会员价：$mprice1',
                            style: const TextStyle(fontSize: 12, color: subTextColor)),
                      ),
                      Text('零售价：$sellprice${unit.isNotEmpty ? '/$unit' : ''}',
                          style: const TextStyle(fontSize: 12, color: subTextColor)),
                    ],
                  ),
                  const Divider(height: 16, thickness: 1, color: borderColor),
                  // 打印份数 + 步进器
                  Row(
                    children: [
                      Text('打印份数：$qty', style: const TextStyle(fontSize: 12, color: subTextColor)),
                      const Spacer(),
                      _QtyStepper(
                        value: qty,
                        min: 1,
                        max: 20,
                        onChanged: onQtyChanged,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 步进器组件（打印份数 1-20）
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBtn(
          icon: Icons.remove,
          enabled: value > min,
          onTap: () => onChanged(value - 1),
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text('$value', style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
        ),
        _buildBtn(
          icon: Icons.add,
          enabled: value < max,
          onTap: () => onChanged(value + 1),
        ),
      ],
    );
  }

  Widget _buildBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? const Color(0xFFDEDEDE) : const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
        ),
      ),
    );
  }
}

/// 方形勾选框（支持半选态，样式对齐公共商品选择组件的复选框）
class _SquareCheckBox extends StatelessWidget {
  const _SquareCheckBox({required this.checked, this.indeterminate = false});

  final bool checked;
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    const Color activeColor = Color(0xFF006EFF);
    final bool active = checked || indeterminate;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: active ? activeColor : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: active ? activeColor : const Color(0xFFCCCCCC),
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : indeterminate
              ? const Icon(Icons.remove, size: 13, color: Colors.white)
              : null,
    );
  }
}
