import 'package:flutter/material.dart';
import 'package:flutter_deer/models/scan_settings.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 扫码设置页面
/// 包含三个配置项：扫码设备 / 录入数量模式 / 连续扫码开关
class ScanSettingsPage extends StatefulWidget {
  const ScanSettingsPage({super.key});

  @override
  State<ScanSettingsPage> createState() => _ScanSettingsPageState();
}

class _ScanSettingsPageState extends State<ScanSettingsPage> {
  late ScanSettings _settings;

  /// 扫码设备选项
  static const List<Map<String, dynamic>> _deviceOptions = [
    {'value': 0, 'label': '摄像头'},
    {'value': 1, 'label': 'iScan激光扫码'},
    {'value': 2, 'label': 'iScan激光扫码 + 摄像头'},
  ];

  /// 录入数量模式选项
  static const List<Map<String, dynamic>> _qtyModeOptions = [
    {'value': 0, 'label': '默认累加1'},
    {'value': 1, 'label': '弹窗手动输入'},
  ];

  @override
  void initState() {
    super.initState();
    _settings = ScanSettings.fromSp();
  }

  void _saveAndSetState(void Function() fn) {
    setState(fn);
    _settings.save();
  }

  // ── 选择弹窗 ──

  void _showDevicePicker() {
    _showOptionPicker(
      title: '选择扫码设备',
      options: _deviceOptions,
      currentValue: _settings.scanDevice,
      onSelected: (int value) {
        _saveAndSetState(() => _settings.scanDevice = value);
      },
    );
  }

  void _showQtyModePicker() {
    _showOptionPicker(
      title: '选择录入数量模式',
      options: _qtyModeOptions,
      currentValue: _settings.scanQtyMode,
      onSelected: (int value) {
        _saveAndSetState(() {
          _settings.scanQtyMode = value;
          // 弹窗手动输入模式下，连续扫码必须关闭
          if (value == 1) {
            _settings.scanContinuous = false;
          }
        });
      },
    );
  }

  void _showOptionPicker({
    required String title,
    required List<Map<String, dynamic>> options,
    required int currentValue,
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
              // 顶部拖拽指示条
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
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
              // 选项列表
              ...options.map((opt) {
                final int value = opt['value'] as int;
                final String label = opt['label'] as String;
                final bool isSelected = currentValue == value;
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
                    onSelected(value);
                    Navigator.pop(ctx);
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

  // ── UI 构建 ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '扫码设置'),
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
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
                _buildSettingRow(
                  label: '扫码设备',
                  value: _settings.scanDeviceLabel,
                  onTap: _showDevicePicker,
                ),
                _buildSettingRow(
                  label: '扫码录入数量模式',
                  value: _settings.scanQtyModeLabel,
                  onTap: _showQtyModePicker,
                ),
                _buildSwitchRow(
                  label: '连续扫码',
                  value: _settings.scanContinuous,
                  enabled: _settings.scanQtyMode != 1,
                  onChanged: (bool value) {
                    _saveAndSetState(() => _settings.scanContinuous = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 文字行（右侧显示当前值 + 箭头）
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
            const Icon(Icons.chevron_right,
                size: 20, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }

  /// Switch 开关行
  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: enabled ? const Color(0xFF707070) : const Color(0xFFBBBBBB),
            ),
          ),
          const Spacer(),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeColor: const Color(0xFF006EFF),
          ),
        ],
      ),
    );
  }
}
