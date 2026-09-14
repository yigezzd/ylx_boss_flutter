import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/user/bill_template_page.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:flutter_deer/widgets/qr_code_scanner_page.dart';

/// 业务打印设置页面
/// 业务逻辑参考 boss 项目 subs/user/businessPrintSet/index.vue
class BusinessPrintPage extends StatefulWidget {
  const BusinessPrintPage({super.key});

  @override
  State<BusinessPrintPage> createState() => _BusinessPrintPageState();
}

class _BusinessPrintPageState extends State<BusinessPrintPage> {
  /// 打印方式：0 关闭打印，1 打印服务工具打印
  int _printType = 0;
  String _airno = '';
  bool _loading = true;
  bool _saving = false;

  final TextEditingController _airnoController = TextEditingController();

  static const List<Map<String, dynamic>> _printOptions = [
    {'value': 0, 'label': '关闭打印'},
    {'value': 1, 'label': '打印服务工具打印'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPrintSet();
  }

  @override
  void dispose() {
    _airnoController.dispose();
    super.dispose();
  }

  Future<void> _loadPrintSet() async {
    try {
      final result = await request(
        HttpApi.getWxPrintSet,
        {},
        true, // showLoading
      );
      final data = result['data'];
      if (data != null && data is Map) {
        final int type = (data['printtype'] is int)
            ? data['printtype'] as int
            : int.tryParse(data['printtype']?.toString() ?? '') ?? 0;
        final String airno = data['airno']?.toString() ?? '';
        setState(() {
          _printType = type;
          _airno = airno;
          _airnoController.text = airno;
        });
      }
    } catch (_) {
      // 接口异常由 http_helper 统一 Toast
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePrintSet({bool showToast = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await request(
        HttpApi.saveWxPrintSet,
        {
          'printtype': _printType,
          'airno': _airno,
        },
      );
      if (showToast) {
        Toast.show('保存成功');
      }
    } catch (_) {
      // 接口异常由 http_helper 统一 Toast
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showPrintTypePicker() {
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
                child: Text(
                  '选择打印方式',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              ..._printOptions.map((opt) {
                final int value = opt['value'] as int;
                final String label = opt['label'] as String;
                final bool isSelected = _printType == value;
                return ListTile(
                  title: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF006EFF)
                          : const Color(0xFF333333),
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle,
                          color: Color(0xFF006EFF), size: 22)
                      : null,
                  onTap: () {
                    setState(() {
                      _printType = value;
                      if (value == 0) {
                        _airno = '';
                        _airnoController.clear();
                      }
                    });
                    Navigator.pop(ctx);
                    _savePrintSet();
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

  /// 扫描设备ID
  Future<void> _scanDeviceId() async {
    final String? code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (code != null && code.isNotEmpty && mounted) {
      setState(() {
        _airno = code;
        _airnoController.text = code;
      });
    }
  }

  /// 确认绑定设备
  Future<void> _confirmBind() async {
    final text = _airnoController.text.trim();
    if (text.isEmpty) {
      Toast.show('请输入或扫描设备ID');
      return;
    }
    setState(() => _airno = text);
    await _savePrintSet(showToast: true);
  }

  /// 跳转打印模板选择页
  void _goTemplatePage() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BillTemplatePage(airno: _airno),
      ),
    );
  }

  String get _currentLabel {
    final opt = _printOptions.firstWhere(
      (o) => o['value'] == _printType,
      orElse: () => _printOptions.first,
    );
    return opt['label'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '业务打印设置'),
      backgroundColor: const Color(0xFFF5F6FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 打印方式
                      _buildSettingRow(
                        label: '打印方式',
                        value: _currentLabel,
                        onTap: _showPrintTypePicker,
                      ),
                      // 打印机绑定（仅 printtype == 1 时显示）
                      if (_printType == 1) ...[
                        _buildDeviceBindRow(),
                        _buildTemplateRow(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSettingRow({
    required String label,
    required String value,
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
            const Spacer(),
            Text(
              value,
              style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }

  /// 打印机绑定行
  Widget _buildDeviceBindRow() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          const Text(
            '打印机绑定',
            style: TextStyle(fontSize: 15, color: Color(0xFF707070)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _airnoController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '扫码或输入设备ID',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFCCCCCC),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      const BorderSide(color: Color(0xFF006EFF), width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                suffixIcon: GestureDetector(
                  onTap: _scanDeviceId,
                  child: const Icon(
                    Icons.qr_code_scanner,
                    size: 20,
                    color: Color(0xFF666666),
                  ),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _saving ? null : _confirmBind,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF006EFF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        '确认',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 打印模板行
  Widget _buildTemplateRow() {
    return GestureDetector(
      onTap: _goTemplatePage,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Text(
              '打印模板',
              style: TextStyle(fontSize: 15, color: Color(0xFF707070)),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }
}
