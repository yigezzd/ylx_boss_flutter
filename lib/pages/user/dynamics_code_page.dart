import 'dart:async';
import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sp_util/sp_util.dart';

/// 收银授权码页面
/// 业务逻辑参考 boss 项目 subs/user/dynamicscode/index.vue
class DynamicsCodePage extends StatefulWidget {
  const DynamicsCodePage({super.key});

  @override
  State<DynamicsCodePage> createState() => _DynamicsCodePageState();
}

class _DynamicsCodePageState extends State<DynamicsCodePage> {
  String _storeName = '';
  String _code = '';
  bool _codeReady = false;

  /// 倒计时总秒数，取自 loginParamResp.dynamicsCodeFlushTime，默认 120s
  int _flushTime = 120;
  int _countdown = 120;
  Timer? _countdownTimer;

  /// 手动刷新冷却（5s）
  bool _refreshDisabled = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _loadStoreName();
    _loadFlushTime();
    _fetchCode();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _loadStoreName() {
    try {
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final store = jsonDecode(storeStr) as Map<String, dynamic>;
        _storeName = store['name']?.toString() ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _loadFlushTime() {
    try {
      final paramStr = SpUtil.getString(Constant.loginParamResp) ?? '';
      if (paramStr.isNotEmpty) {
        final param = jsonDecode(paramStr) as Map<String, dynamic>;
        final int? t = param['dynamicsCodeFlushTime'] is int
            ? param['dynamicsCodeFlushTime'] as int
            : int.tryParse(param['dynamicsCodeFlushTime']?.toString() ?? '');
        if (t != null && t > 0) {
          _flushTime = t;
          _countdown = t;
        }
      }
    } catch (_) {}
  }

  /// 获取授权码
  Future<void> _fetchCode() async {
    try {
      final result = await request(HttpApi.getAuthCode, {});
      final data = result['data']?.toString() ?? '';
      if (data.isNotEmpty && mounted) {
        setState(() {
          _code = data;
          _codeReady = true;
        });
      }
    } catch (_) {
      // 接口异常由 http_helper 统一 Toast
    }
  }

  /// 开始倒计时（每秒递减，归零后自动刷新）
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          // 归零：重新读取后台设置的刷新时间（与boss项目对齐）
          _loadFlushTime();
          _countdown = _flushTime;
          _fetchCode();
        }
      });
    });
  }

  /// 手动刷新（5s 冷却，与boss项目对齐）
  void _handleManualRefresh() {
    if (_refreshDisabled) return;
    setState(() {
      _loadFlushTime(); // 每次刷新也重新读取后台设置
      _countdown = _flushTime;
      _refreshDisabled = true;
      _cooldown = 5;
    });
    _fetchCode();
    _startCountdown();

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_cooldown > 0) {
          _cooldown--;
        } else {
          _refreshDisabled = false;
          _cooldownTimer?.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '收银授权码'),
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    children: [
                      // ── 顶部商户名（票根样式）──
                      _buildTicketHeader(),
                      // ── 条码 + 二维码 + 有效期 ──
                      Expanded(child: _buildCodeSection()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 票根顶部：商户名 + 虚线分割
  Widget _buildTicketHeader() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 左侧半圆缺口
        Positioned(
          left: -14,
          bottom: -14,
          child: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFF5F6FA),
            ),
          ),
        ),
        // 右侧半圆缺口
        Positioned(
          right: -14,
          bottom: -14,
          child: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFF5F6FA),
            ),
          ),
        ),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 22,
                    color: Color(0xFF006EFF),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _storeName.isNotEmpty ? _storeName : '商户',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 虚线分割
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: CustomPaint(
                size: const Size(double.infinity, 1),
                painter: _DashedLinePainter(
                  color: const Color(0xFFE2E2E2),
                  dashWidth: 6,
                  dashSpace: 4,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ],
    );
  }

  /// 条码 + 二维码 + 有效期
  Widget _buildCodeSection() {
    if (!_codeReady || _code.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // 条码
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: _code,
              width: double.infinity,
              height: 80,
              drawText: true,
              style: const TextStyle(
                fontSize: 12,
                letterSpacing: 1.5,
                color: Color(0xFF333333),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 二维码
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFEEEEEE)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: _code,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.circle,
                color: Color(0xFF006EFF),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Color(0xFF333333),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 有效期按钮
          GestureDetector(
            onTap: _handleManualRefresh,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFA4A4A4)),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh,
                    size: 18,
                    color: _refreshDisabled
                        ? const Color(0xFF999999)
                        : const Color(0xFF505050),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '有效期：${_countdown}s',
                    style: TextStyle(
                      fontSize: 14,
                      color: _refreshDisabled
                          ? const Color(0xFF999999)
                          : const Color(0xFF505050),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// 虚线绘制器
class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  _DashedLinePainter({
    required this.color,
    this.dashWidth = 6,
    this.dashSpace = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
