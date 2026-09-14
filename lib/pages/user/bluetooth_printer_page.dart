import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/gprinter.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:sp_util/sp_util.dart';

/// 蓝牙打印机设置页
/// 业务逻辑参考 boss 项目 subs/user/printSet/bluetooth.vue：
/// 蓝牙开关 → 连接状态 → 已连接打印机（断开）→ 附近设备扫描选择 → 测试打印
class BluetoothPrinterPage extends StatefulWidget {
  const BluetoothPrinterPage({super.key});

  @override
  State<BluetoothPrinterPage> createState() => _BluetoothPrinterPageState();
}

class _BluetoothPrinterPageState extends State<BluetoothPrinterPage> {
  static const Color _primaryColor = Color(0xFF006EFF);

  bool _loading = true;

  /// 服务端打印设置（保存时整体回写）
  Map<String, dynamic> _query = {};

  /// 蓝牙开关（对应 lableBluetoothStatus）
  bool get _enabled => int.tryParse(_query['lableBluetoothStatus']?.toString() ?? '') == 1;

  String get _savedName => _query['lableBluetoothCode']?.toString() ?? '';
  String get _savedMac => _query['lableDeviceid']?.toString() ?? '';

  /// SDK 实际连接状态
  bool _connected = false;

  List<GPrinterDevice> _devices = [];
  bool _scanning = false;

  /// 正在连接的 MAC（连接中禁止重复点击）
  String? _connectingMac;

  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // ─── 初始化 ───

  Future<void> _init() async {
    final granted = await GPrinter.requestPermissions();
    await _loadSettings();
    if (!mounted) {
      return;
    }
    if (!granted) {
      Toast.show('蓝牙权限被拒绝，请在系统设置中开启');
      return;
    }
    // 查询 SDK 实际连接状态（保存的地址不代表真实连接，与小程序 initData 保持一致）
    bool connected = false;
    try {
      connected = await GPrinter.isConnected;
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() => _connected = connected);
    // 蓝牙已启用：有保存设备尝试自动重连（对齐小程序 autoReconnect），否则扫描
    if (_enabled && !connected) {
      final btOn = await _isBtOn();
      if (!mounted) {
        return;
      }
      if (!btOn) {
        // 系统蓝牙未开启：提示并引导一键开启，开启后自动继续
        _handleBtDisabled(_afterBtEnabled);
        return;
      }
      if (_savedMac.isNotEmpty) {
        _tryReconnect();
      } else {
        _scan();
      }
    }
  }

  /// 查询系统蓝牙是否开启（非 Android 平台默认视为开启）
  Future<bool> _isBtOn() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      return await GPrinter.isBluetoothEnabled;
    } catch (_) {
      return true;
    }
  }

  /// 系统蓝牙开启后的后续流程：自动重连已保存设备或扫描
  void _afterBtEnabled() {
    if (_savedMac.isNotEmpty) {
      _tryReconnect();
    } else {
      _scan();
    }
  }

  /// 系统蓝牙未开启：弹窗提示并引导开启，开启成功后执行 [onEnabled]
  Future<void> _handleBtDisabled([VoidCallback? onEnabled]) async {
    if (!mounted) {
      return;
    }
    final toEnable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: const Text('系统蓝牙未开启，是否现在开启？', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开启', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
    if (toEnable != true || !mounted) {
      return;
    }
    try {
      await GPrinter.enableBluetooth();
    } catch (_) {}
    // 等待系统开启生效后再复查
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) {
      return;
    }
    if (await _isBtOn()) {
      onEnabled?.call();
    } else {
      Toast.show('蓝牙未开启，请开启系统蓝牙后重试');
    }
  }

  /// 加载服务端已保存的蓝牙配置（对齐小程序 loadSavedConfig）
  Future<void> _loadSettings() async {
    final clientId = _getClientId();
    try {
      final res = await request(HttpApi.getPrintSet, {'clientid': clientId}, false, false);
      if (!mounted) {
        return;
      }
      Map<String, dynamic> data = {};
      if (res['retcode'] == 0 && res['data'] is Map) {
        data = Map<String, dynamic>.from(res['data'] as Map);
      }
      setState(() {
        _query = {
          ...data,
          'clientid': clientId,
          'printType': data['printType'] ?? 2,
          'print_flag': _intOf(data['print_flag'], 0),
          'print_num': _intOf(data['print_num'], 1),
          'print_template': _intOf(data['print_template'], 1),
          'lable_page': _intOf(data['lable_page'], 1),
          'lableBluetoothStatus': _intOf(data['lableBluetoothStatus'], 0),
          'lableBluetoothCode': data['lableBluetoothCode'] ?? '',
          'lableDeviceid': data['lableDeviceid'] ?? '',
          'lableServiceid': data['lableServiceid'] ?? data['lableServiceId'] ?? '',
          'lableCharacteristicid':
              data['lableCharacteristicid'] ?? data['lableCharacteristicId'] ?? '',
        };
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ─── 保存 ───

  /// 保存蓝牙配置到服务端（对齐小程序 bluetoothResult 回写）
  Future<void> _saveSettings({int? status, String? name, String? mac}) async {
    if (_query.isEmpty) {
      return;
    }
    final payload = Map<String, dynamic>.from(_query);
    if (status != null) {
      payload['lableBluetoothStatus'] = status;
    }
    if (name != null) {
      payload['lableBluetoothCode'] = name;
    }
    if (mac != null) {
      payload['lableDeviceid'] = mac;
      payload['lableServiceid'] = '';
      payload['lableCharacteristicid'] = '';
    }
    try {
      await request(HttpApi.savePrintSet, payload, false, false);
      if (mounted) {
        setState(() => _query = payload);
      }
    } catch (_) {}
  }

  // ─── 交互 ───

  /// 蓝牙开关切换（对齐小程序 onBluetoothToggle）
  Future<void> _onToggle(bool value) async {
    setState(() => _query['lableBluetoothStatus'] = value ? 1 : 0);
    if (value) {
      final granted = await GPrinter.requestPermissions();
      if (!granted) {
        Toast.show('蓝牙权限被拒绝，请在系统设置中开启');
        if (mounted) {
          setState(() => _query['lableBluetoothStatus'] = 0);
        }
        return;
      }
      if (!mounted) {
        return;
      }
      // 检测系统蓝牙：未开启时提示并引导一键开启（对齐小程序 errCode 10001 提示）
      if (!await _isBtOn()) {
        if (!mounted) {
          return;
        }
        setState(() => _query['lableBluetoothStatus'] = 0);
        _handleBtDisabled(() {
          if (!mounted) {
            return;
          }
          setState(() => _query['lableBluetoothStatus'] = 1);
          _afterBtEnabled();
        });
        return;
      }
      if (!_connected && _savedMac.isNotEmpty) {
        _tryReconnect();
      } else if (!_connected) {
        _scan();
      }
    } else {
      // 关闭：断开连接并同步服务端状态（保留已保存的设备地址，下次可自动重连）
      try {
        await GPrinter.disconnect();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _connected = false;
          _devices = [];
        });
      }
      _saveSettings(status: 0);
    }
  }

  /// 自动重连上次保存的设备（对齐小程序 autoReconnect）
  Future<void> _tryReconnect() async {
    if (_connectingMac != null) {
      return;
    }
    setState(() => _connectingMac = _savedMac);
    bool ok = false;
    try {
      ok = await GPrinter.connect(_savedMac);
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _connectingMac = null;
      _connected = ok;
    });
    if (ok) {
      _saveSettings(status: 1);
    }
  }

  /// 扫描附近打印机（对齐小程序 startSearch）
  Future<void> _scan() async {
    if (_scanning) {
      return;
    }
    setState(() {
      _scanning = true;
      _devices = [];
    });
    try {
      final devices = await GPrinter.scanPrinters(timeout: 8000);
      if (mounted) {
        setState(() => _devices = devices);
      }
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.code == 'BT_DISABLED') {
        // 系统蓝牙未开启：引导开启后自动重新扫描
        _handleBtDisabled(_scan);
      } else {
        Toast.show(e.message ?? '扫描失败');
      }
    } catch (_) {
      if (mounted) {
        Toast.show('扫描失败');
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  /// 点击设备连接（对齐小程序 onDeviceClick → connectDevice）
  Future<void> _connect(GPrinterDevice device) async {
    if (_connectingMac != null) {
      return;
    }
    setState(() => _connectingMac = device.mac);
    try {
      final ok = await GPrinter.connect(device.mac);
      if (!mounted) {
        return;
      }
      setState(() {
        _connectingMac = null;
        _connected = ok;
      });
      if (ok) {
        Toast.show('连接成功');
        _saveSettings(status: 1, name: device.name, mac: device.mac);
      } else {
        Toast.show('连接失败，请确认打印机已开启');
      }
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _connectingMac = null);
      Toast.show(e.message ?? '连接失败');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _connectingMac = null);
      Toast.show('连接失败');
    }
  }

  /// 断开当前连接（对齐小程序 disconnectDevice，保留已保存的设备地址）
  Future<void> _disconnect() async {
    try {
      await GPrinter.disconnect();
    } catch (_) {}
    if (mounted) {
      setState(() => _connected = false);
    }
  }

  /// 测试打印（对齐小程序 testPrint）
  Future<void> _testPrint() async {
    if (!_connected) {
      Toast.show('请先连接设备');
      return;
    }
    if (_printing) {
      return;
    }
    setState(() => _printing = true);
    _showLoading('打印中...');
    try {
      await GPrinter.printTestLabel();
      _hideLoading();
      Toast.show('打印成功');
    } on PlatformException catch (e) {
      _hideLoading();
      Toast.show(e.message ?? '打印失败');
    } catch (_) {
      _hideLoading();
      Toast.show('打印失败');
    } finally {
      if (mounted) {
        setState(() => _printing = false);
      }
    }
  }

  // ─── loading 弹窗 ───

  void _showLoading(String text) {
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

  void _hideLoading() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // ─── 工具方法 ───

  int _intOf(dynamic value, int def) {
    if (value == null) {
      return def;
    }
    return int.tryParse(value.toString()) ?? def;
  }

  /// 获取客户端设备标识（与标签打印设置页保持一致）
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
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '蓝牙打印机'),
      backgroundColor: const Color(0xFFF5F6FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildSwitchCard(),
                          if (_enabled) _buildStatusCard(),
                          if (_connected) _buildConnectedCard(),
                          if (_enabled) _buildDeviceCard(),
                        ],
                      ),
                    ),
                  ),
                  _buildBottomBtn(),
                ],
              ),
            ),
    );
  }

  /// 蓝牙开关卡片
  Widget _buildSwitchCard() {
    return _card(
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Text('蓝牙开关', style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
            const Spacer(),
            Switch(
              value: _enabled,
              activeColor: _primaryColor,
              onChanged: _onToggle,
            ),
          ],
        ),
      ),
    );
  }

  /// 连接状态卡片
  Widget _buildStatusCard() {
    final connecting = _connectingMac != null;
    final Color color;
    final Color bg;
    final String label;
    if (_connected) {
      color = const Color(0xFF67C23A);
      bg = const Color(0xFFF0F9EB);
      label = '已连接';
    } else if (connecting) {
      color = const Color(0xFFE6A23C);
      bg = const Color(0xFFFDF6EC);
      label = '连接中...';
    } else {
      color = const Color(0xFF999999);
      bg = const Color(0xFFF5F5F5);
      label = '未连接';
    }
    return _card(
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Text('连接状态', style: TextStyle(fontSize: 15, color: Color(0xFF333333))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(label, style: TextStyle(fontSize: 13, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  /// 已连接打印机卡片（含断开按钮）
  Widget _buildConnectedCard() {
    final name = _savedName.isNotEmpty ? _savedName : _savedMac;
    return _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('已连接打印机', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
          ),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Flexible(
                  child: Text(name,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _disconnect,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFF56C6C)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child:
                        const Text('断开', style: TextStyle(fontSize: 13, color: Color(0xFFF56C6C))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 附近的蓝牙设备卡片
  Widget _buildDeviceCard() {
    return _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
            ),
            child: Row(
              children: [
                const Text('附近的蓝牙设备', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
                const Spacer(),
                GestureDetector(
                  onTap: _scanning ? null : _scan,
                  child: Text(
                    _scanning ? '搜索中...' : '重新扫描',
                    style: TextStyle(
                      fontSize: 14,
                      color: _scanning ? const Color(0xFFCCCCCC) : _primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_scanning && _devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(height: 12),
                  Text('正在搜索打印机...', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
                ],
              ),
            )
          else if (_devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('暂无设备，请点击重新扫描', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              cacheExtent: 800,
              itemCount: _devices.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (ctx, i) => _buildDeviceItem(_devices[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(GPrinterDevice device) {
    final connecting = _connectingMac == device.mac;
    final isSelected = _savedMac == device.mac;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: connecting ? null : () => _connect(device),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.print, size: 20, color: Color(0xFF666666)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(device.mac, style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                ],
              ),
            ),
            if (connecting)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isSelected && _connected)
              const Icon(Icons.check_circle, color: _primaryColor, size: 20)
            else
              const Icon(Icons.radio_button_unchecked, size: 20, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }

  /// 底部测试打印按钮
  Widget _buildBottomBtn() {
    final enabled = _connected && !_printing;
    final String label;
    if (_printing) {
      label = '打印中...';
    } else if (_connectingMac != null) {
      label = '连接中...';
    } else if (!_connected) {
      label = '请先连接设备';
    } else {
      label = '测试打印';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      color: const Color(0xFFF5F6FA),
      child: GestureDetector(
        onTap: enabled ? _testPrint : null,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? _primaryColor : const Color(0xFFCCCCCC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: child,
    );
  }
}
