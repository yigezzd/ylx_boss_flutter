import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:sp_util/sp_util.dart';

/// 用户信息页面（账号详情）
/// 点击"个人中心"页的账号信息区域跳转至此
class UserInfoPage extends StatefulWidget {
  const UserInfoPage({super.key});

  @override
  State<UserInfoPage> createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {
  Map<String, dynamic> _user = {};
  Map<String, dynamic> _store = {};
  Map<String, dynamic> _sysStoreAccount = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    try {
      final userStr = SpUtil.getString(Constant.user) ?? '';
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      final accountStr = SpUtil.getString(Constant.sysStoreAccount) ?? '';
      if (userStr.isNotEmpty) {
        _user = jsonDecode(userStr) as Map<String, dynamic>;
      }
      if (storeStr.isNotEmpty) {
        _store = jsonDecode(storeStr) as Map<String, dynamic>;
      }
      if (accountStr.isNotEmpty) {
        _sysStoreAccount = jsonDecode(accountStr) as Map<String, dynamic>;
      }
    } catch (_) {}
    setState(() {});
  }

  String _maskPhone(String phone) {
    if (phone.length < 7) {
      return phone;
    }
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  /// 头像 URL
  String get _avatarUrl {
    String avatar = '';
    // 优先 sysStoreAccount
    avatar = _sysStoreAccount['wximg']?.toString() ??
        _sysStoreAccount['logo']?.toString() ??
        '';
    // 兜底 user.sysUserWx
    if (avatar.isEmpty) {
      final wxInfo = _user['sysUserWx'];
      if (wxInfo is Map) {
        avatar = wxInfo['wximg']?.toString() ?? '';
      }
    }
    if (avatar.startsWith('http')) {
      return avatar;
    }
    if (avatar.isNotEmpty) {
      return '${Constant.imageBaseUrl}/$avatar';
    }
    return '';
  }

  /// 所属机构
  String get _orgName {
    final storeName = _store['name']?.toString() ?? '';
    final deptName = _store['deptname']?.toString() ??
        _store['deptName']?.toString() ??
        '';
    if (storeName.isNotEmpty && deptName.isNotEmpty) {
      return '$storeName-$deptName';
    }
    return storeName.isNotEmpty ? storeName : '--';
  }

  /// 登录工号
  String get _jobNumber {
    return _user['code']?.toString() ?? '--';
  }

  /// 员工姓名
  String get _employeeName {
    return _user['name']?.toString() ??
        _user['realname']?.toString() ??
        '--';
  }

  /// 手机号码
  String get _phone {
    final raw = _user['phone']?.toString() ??
        _user['mobile']?.toString() ??
        '';
    return raw.isNotEmpty ? raw : '--';
  }

  /// 退出登录
  void _logout() {
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
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '用户信息'),
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── 用户信息卡片 ──
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Column(
                  children: [
                    // 用户头像
                    _buildAvatarRow(),
                    _buildDivider(),
                    // 所属机构
                    _buildInfoRow('所属机构', _orgName),
                    _buildDivider(),
                    // 登录工号
                    _buildInfoRow('登录工号', _jobNumber),
                    _buildDivider(),
                    // 员工姓名
                    _buildInfoRow('员工姓名', _employeeName),
                    _buildDivider(),
                    // 手机号码
                    _buildInfoRow('手机号码', _phone),
                  ],
                ),
              ),
              const Spacer(),
              // ── 退出登录按钮 ──
              _buildLogoutButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// 头像行
  Widget _buildAvatarRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          const Text(
            '用户头像',
            style: TextStyle(fontSize: 15, color: Color(0xFF666666)),
          ),
          const Spacer(),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: ClipOval(
              child: _avatarUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _avatarUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 112,
                      memCacheHeight: 112,
                      placeholder: (_, __) => _buildAvatarPlaceholder(),
                      errorWidget: (_, __, ___) => _buildAvatarPlaceholder(),
                    )
                  : _buildAvatarPlaceholder(),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildAvatarPlaceholder() {
    return const ColoredBox(
      color: Color(0xFFF0F0F0),
      child: Icon(
        Icons.person,
        size: 28,
        color: Color(0xFFCCCCCC),
      ),
    );
  }

  /// 信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: Color(0xFF666666)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: Color(0xFFF0F0F0)),
    );
  }

  /// 退出登录按钮
  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: GestureDetector(
        onTap: _logout,
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          alignment: Alignment.center,
          child: const Text(
            '退出登录',
            style: TextStyle(
              fontSize: 16,
              color: Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
