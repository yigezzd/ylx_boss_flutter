import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/user/bluetooth_printer_page.dart';
import 'package:flutter_deer/pages/user/label_template_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:sp_util/sp_util.dart';

/// 标签打印设置页面
/// 业务逻辑参考 boss 项目 subs/user/printSet/index.vue（新接口蓝牙打印设置）
class LabelPrintPage extends StatefulWidget {
  const LabelPrintPage({super.key});

  @override
  State<LabelPrintPage> createState() => _LabelPrintPageState();
}

class _LabelPrintPageState extends State<LabelPrintPage> {
  static const Color _primaryColor = Color(0xFF006EFF);

  bool _loading = true;

  /// 新接口打印设置（含蓝牙配置）
  Map<String, dynamic> _query = {};

  static const List<Map<String, dynamic>> _printTypeOptions = [
    {'value': 0, 'label': '关闭打印'},
    {'value': 1, 'label': '前台打印'},
    {'value': 2, 'label': '蓝牙打印'},
  ];

  static const Map<int, String> _templateMap = {
    1: '系统模板1(60×40)',
    2: '系统模板2(50×30)',
    3: '系统模板3(40×30)',
    4: '系统模板4(45×20)',
  };

  int get _printType => _intOf(_query['printType'], 1);
  int get _printNum => _intOf(_query['print_num'], 1);
  int get _printTemplate => _intOf(_query['print_template'], 1);

  String get _currentPrinterName {
    final code = _query['lableBluetoothCode']?.toString() ?? '';
    final deviceId = _query['lableDeviceid']?.toString() ?? '';
    return code.isNotEmpty ? code : (deviceId.isNotEmpty ? deviceId : '未设置');
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ─── 加载设置 ───

  /// 并行拉取新接口设置和旧接口互斥状态（对齐小程序 getPrintSet）
  Future<void> _loadSettings() async {
    final clientId = _getClientId();
    Map<String, dynamic> printRes = {};
    int oldType = 0;
    try {
      final results = await Future.wait<dynamic>([
        request(HttpApi.getPrintSet, {'clientid': clientId}, false, false),
        request(HttpApi.getLabelPrintParams, {'type': 31}, false, false),
      ]);
      final newRes = results[0] as Map;
      if (newRes['retcode'] == 0 && newRes['data'] is Map) {
        printRes = Map<String, dynamic>.from(newRes['data'] as Map);
      }
      final oldRes = results[1] as Map;
      if (oldRes['retcode'] == 0 && oldRes['data'] is Map) {
        oldType = _intOf((oldRes['data'] as Map)['labelPrintType'], 0);
      }
    } catch (_) {}
    if (!mounted) {
      return;
    }

    // 首次未保存时接口可能返回空对象，保留默认值
    final savedType = printRes['printType'] != null ? _intOf(printRes['printType'], 1) : 1;
    // 旧接口前台打印开启时，强制前台打印（互斥规则）
    final finalType = oldType != 0 ? 1 : savedType;

    setState(() {
      _query = {
        ...printRes,
        'clientid': clientId,
        'printType': finalType,
        'print_flag': _intOf(printRes['print_flag'], 0),
        'print_num': _intOf(printRes['print_num'], 1),
        'print_template': _intOf(printRes['print_template'], 1),
        'lable_page': _intOf(printRes['lable_page'], 1),
        'lableBluetoothStatus': _intOf(printRes['lableBluetoothStatus'], 0),
        'lableBluetoothCode': printRes['lableBluetoothCode'] ?? '',
        'lableDeviceid': printRes['lableDeviceid'] ?? '',
        'lableServiceid': printRes['lableServiceid'] ?? printRes['lableServiceId'] ?? '',
        'lableCharacteristicid':
            printRes['lableCharacteristicid'] ?? printRes['lableCharacteristicId'] ?? '',
      };
      _loading = false;
    });
  }

  // ─── 保存设置 ───

  /// 保存新接口打印设置（对齐小程序 savePrintSet）
  Future<void> _savePrintSet() async {
    if (_query.isEmpty) {
      return;
    }
    try {
      await request(HttpApi.savePrintSet, _query, false, false);
    } catch (_) {}
  }

  /// 保存旧接口前台打印状态（与新接口 printType 保持同步）
  Future<void> _saveOldLabelPrintType(int type) async {
    try {
      await request(
        HttpApi.saveLabelPrintParams,
        {'type': 31, 'labelPrintType': type},
        false,
        false,
      );
    } catch (_) {}
  }

  // ─── 交互 ───

  /// 切换打印方式：新旧接口联动保存
  void _onPrintTypeChange(int value) {
    setState(() {
      _query['printType'] = value;
    });
    _savePrintSet();
    // 前台打印依赖旧接口开关，蓝牙/关闭时同步关闭旧接口
    _saveOldLabelPrintType(value == 1 ? 1 : 0);
  }

  /// 选择蓝牙打印机：跳转打印机设置页（对齐小程序 跳转 bluetooth 页面），返回后刷新配置
  Future<void> _selectPrinter() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const BluetoothPrinterPage()),
    );
    if (mounted) {
      _loadSettings();
    }
  }

  void _onPrintNumChange(int value) {
    if (value < 1 || value > 10) {
      return;
    }
    setState(() => _query['print_num'] = value);
    _savePrintSet();
  }

  void _showPrintTypePicker() {
    _showPickerSheet(
      title: '选择打印方式',
      options: _printTypeOptions,
      selectedValue: _printType,
      onSelected: (value) {
        Navigator.pop(context);
        _onPrintTypeChange(value);
      },
    );
  }

  Future<void> _showTemplatePicker() async {
    final value = await Navigator.push<int>(
      context,
      MaterialPageRoute<int>(
        builder: (_) => LabelTemplatePage(initialTemplate: _printTemplate),
      ),
    );
    if (value != null && value != _printTemplate) {
      setState(() => _query['print_template'] = value);
      _savePrintSet();
    }
  }

  void _showPickerSheet({
    required String title,
    required List<Map<String, dynamic>> options,
    required int selectedValue,
    required ValueChanged<int> onSelected,
  }) {
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              ...options.map((opt) {
                final int value = opt['value'] as int;
                final String label = opt['label'] as String;
                final bool isSelected = selectedValue == value;
                return ListTile(
                  title: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? _primaryColor : const Color(0xFF333333),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: _primaryColor, size: 22)
                      : null,
                  onTap: () => onSelected(value),
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ─── 工具方法 ───

  int _intOf(dynamic value, int def) {
    if (value == null) {
      return def;
    }
    return int.tryParse(value.toString()) ?? def;
  }

  /// 获取客户端设备标识（与标签打印主页保持一致）
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

  // ─── 页面构建 ───

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        await _savePrintSet();
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: const MyAppBar(centerTitle: '标签打印设置'),
        backgroundColor: const Color(0xFFF5F6FA),
        body: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 打印方式
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSettingRow(
                              label: '打印方式',
                              value: _printTypeOptions.firstWhere(
                                (o) => o['value'] == _printType,
                                orElse: () => _printTypeOptions[1],
                              )['label'] as String,
                              onTap: _showPrintTypePicker,
                            ),
                            // 蓝牙模式专属设置
                            if (_printType == 2) ...[
                              _buildSettingRow(
                                label: '打印机设置',
                                value: _currentPrinterName,
                                onTap: _selectPrinter,
                              ),
                              _buildSettingRow(
                                label: '打印份数',
                                trailing: _buildNumStepper(),
                              ),
                              _buildSettingRow(
                                label: '打印预包装模版',
                                value: _templateMap[_printTemplate] ?? '默认模板',
                                onTap: _showTemplatePicker,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_printType == 2)
                        const Padding(
                          padding: EdgeInsets.only(top: 12, left: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '注：请保持蓝牙打印机开机并在附近，打印份数为商品未设置数量时的默认份数',
                              style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String label,
    String? value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 15, color: Color(0xFF707070)),
            ),
            const SizedBox(width: 12),
            if (trailing != null)
              // 步进器等控件靠右对齐（对齐小程序 flex-row-center-between）
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              )
            else ...[
              // value 占满剩余空间并右对齐，紧贴右边缘
              Expanded(
                child: Text(
                  value ?? '',
                  style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCCCCCC)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 打印份数步进器（1-10）
  Widget _buildNumStepper() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStepBtn(Icons.remove, _printNum > 1, () => _onPrintNumChange(_printNum - 1)),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text('$_printNum', style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
        ),
        _buildStepBtn(Icons.add, _printNum < 10, () => _onPrintNumChange(_printNum + 1)),
      ],
    );
  }

  Widget _buildStepBtn(IconData icon, bool enabled, VoidCallback onTap) {
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
