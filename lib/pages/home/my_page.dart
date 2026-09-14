import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/user/about_page.dart';
import 'package:flutter_deer/pages/user/dynamics_code_page.dart';
import 'package:flutter_deer/pages/user/settings_page.dart';
import 'package:flutter_deer/pages/user/user_info_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/log_upload_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/version_check_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sp_util/sp_util.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  Map<String, dynamic> _user = {};
  Map<String, dynamic> _store = {};
  Map<String, dynamic> _sysStoreAccount = {};
  String _appVersion = '';
  bool _checkingUpdate = false;
  bool _uploadingLog = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadAppVersion();
  }

  void _loadUserInfo() {
    try {
      final userStr = SpUtil.getString(Constant.user) ?? '';
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (userStr.isNotEmpty) {
        _user = jsonDecode(userStr) as Map<String, dynamic>;
      }
      final accountStr = SpUtil.getString(Constant.sysStoreAccount) ?? '';
      if (storeStr.isNotEmpty) {
        _store = jsonDecode(storeStr) as Map<String, dynamic>;
      }
      if (accountStr.isNotEmpty) {
        _sysStoreAccount = jsonDecode(accountStr) as Map<String, dynamic>;
      }
    } catch (_) {}
    setState(() {});
  }

  /// 构建时通过 --dart-define=FULL_VERSION 注入的完整版本号（保留前导零）
  static const _kFullVersion = String.fromEnvironment('FULL_VERSION');

  Future<void> _loadAppVersion() async {
    try {
      if (_kFullVersion.isNotEmpty) {
        _appVersion = _kFullVersion;
      } else {
        final info = await PackageInfo.fromPlatform();
        final build = info.buildNumber;
        _appVersion = build.isNotEmpty ? '${info.version}.$build' : info.version;
      }
      setState(() {});
    } catch (_) {}
  }

  String _maskPhone(String phone) {
    if (phone.length < 7) {
      return phone;
    }
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  /// 检查更新
  Future<void> _checkUpdate() async {
    if (_checkingUpdate) {
      return;
    }
    setState(() => _checkingUpdate = true);

    try {
      await VersionCheckUtils.checkUpdate(context: context);
    } catch (_) {
      // 接口异常时由 http_helper 统一 Toast 提示
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  /// 上传日志（FTP 上传本地运行日志压缩包，对齐 ytt-smdc-flutter 设置页“上传日志”按钮）
  Future<void> _uploadLog() async {
    if (_uploadingLog) {
      return;
    }
    setState(() => _uploadingLog = true);

    try {
      final result = await LogUploadUtils.uploadLog(onProgress: (msg) {
        // 上传过程阶段提示（压缩中 / 连接FTP / 上传中）
        if (mounted) {
          Toast.show(msg);
        }
      });
      if (mounted) {
        if (result == '1') {
          Toast.show('上传日志成功');
        } else {
          Toast.show('上传日志失败: $result');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingLog = false);
      }
    }
  }

  void _logout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前账号？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              logoutAndRedirect(context);
            },
            child: const Text('确认', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String userName = _user['name']?.toString() ?? _user['username']?.toString() ?? '用户';
    final String roleName = _user['roleName']?.toString() ?? _user['role']?.toString() ?? '';
    final String phone = _user['phone']?.toString() ?? _user['mobile']?.toString() ?? '';
    final String orgName = _store['name']?.toString() ?? '';
    final String merchantId = _store['account']?.toString() ?? '';
    final String merchantName = _sysStoreAccount['name']?.toString() ?? '';

    final String displayName = roleName.isNotEmpty ? '$userName-$roleName' : userName;

    return Scaffold(
      // 全页渐变背景
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF006EFF),
              Color(0xFF0052CC),
              Color(0xFFE8EEF8),
            ],
            stops: [0.0, 0.28, 0.35],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── 顶部操作栏 ──
              _buildTopBar(),
              // ── 用户信息区 ──
              _buildUserSection(displayName, phone),
              const SizedBox(height: 8),
              // ── 圆角白色内容区 ──
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: SingleChildScrollView(
                    // 底部留出导航栏高度（SafeArea ≈ 34 + navBar 56 ≈ 90），防止内容被遮挡
                    padding: const EdgeInsets.only(top: 12, bottom: 90),
                    child: Column(
                      children: [
                        _buildInfoCard(
                          orgName,
                          merchantId,
                          merchantName,
                        ),
                        const SizedBox(height: 10),
                        _buildMenuCard(context),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部标题栏
  Widget _buildTopBar() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '个人中心',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// 用户信息区（头像 + 姓名 + 手机号，点击跳转用户信息页）
  Widget _buildUserSection(String displayName, String phone) {
    return GestureDetector(
      onTap: () {
        Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const UserInfoPage()),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Colors.white.withOpacity(0.25),
              child: const Icon(
                Icons.person,
                size: 36,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    phone.isNotEmpty ? _maskPhone(phone) : '暂无手机号',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
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

  /// 账户信息卡片（所属机构 / 商户编号 / 商户名称）
  Widget _buildInfoCard(
    String orgName,
    String merchantId,
    String merchantName,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          _buildInfoRow('所属机构', orgName),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _buildInfoRow('商户编号', merchantId),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _buildInfoRow('商户名称', merchantName),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '--',
              textAlign: TextAlign.start,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 功能菜单卡片（四个功能模块 + 检查更新 + 退出登录）
  Widget _buildMenuCard(BuildContext context) {
    final items = [
      _MenuItem(
        svgFile: 'cashcode.svg',
        title: '收银授权码',
        menuId: '0304',
        onTap: () {
          if (!PermissionUtils.checkPermission('0304')) return;
          Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const DynamicsCodePage()),
          );
        },
      ),
      _MenuItem(
        // icon: Icons.settings,
        // iconColor: const Color(0xFF006EFF),
        svgFile: 'paramsset.svg',
        title: '设置',
        onTap: () {
          Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          );
        },
      ),
      _MenuItem(
        svgFile: 'shangchuanrizhi.svg',
        title: _uploadingLog ? '上传日志中...' : '上传日志',
        onTap: _uploadLog,
        trailing: _uploadingLog
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF006EFF)),
                ),
              )
            : null,
      ),
      _MenuItem(
        svgFile: 'aboutyi.svg',
        title: '关于',
        onTap: () {
          Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const AboutPage()),
          );
        },
      ),
      _MenuItem(
        svgFile: 'version_update.svg',
        title: '检查更新',
        subtitle: _appVersion.isNotEmpty ? 'v$_appVersion' : '',
        onTap: _checkUpdate,
        trailing: _checkingUpdate
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF006EFF)),
                ),
              )
            : null,
      )
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: List.generate(items.length, (i) {
            final item = items[i];
            return Column(
              children: [
                ListTile(
                  leading: item.svgFile != null
                      ? Padding(
                          padding: EdgeInsets.only(left: item.iconLeadingPadding ?? 0),
                          child: BossSvgIcon(svgFile: item.svgFile!, size: item.iconSize ?? 28),
                        )
                      : Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: item.iconColor?.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(item.icon, color: item.iconColor, size: 20),
                        ),
                  title: Row(
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 15,
                          color: item.titleColor ?? const Color(0xFF333333),
                        ),
                      ),
                      if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            item.subtitle!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF999999),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: item.trailing ??
                      const Icon(
                        Icons.chevron_right,
                        color: Color(0xFFCCCCCC),
                        size: 20,
                      ),
                  onTap: item.onTap,
                ),
                if (i < items.length - 1) const Divider(height: 1, indent: 64, endIndent: 16),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    this.icon,
    this.iconColor,
    this.svgFile,
    this.iconSize,
    this.iconLeadingPadding,
    required this.title,
    required this.onTap,
    this.titleColor,
    this.subtitle,
    this.trailing,
    this.menuId = '',
  });

  final IconData? icon;
  final Color? iconColor;
  final String? svgFile;
  final double? iconSize;
  final double? iconLeadingPadding;
  final String title;
  final VoidCallback onTap;
  final Color? titleColor;
  final String? subtitle;
  final Widget? trailing;

  /// 权限菜单 ID（对齐 boss 项目 menuid，为空时无需校验）
  final String menuId;
}
