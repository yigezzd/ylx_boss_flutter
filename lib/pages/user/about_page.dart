import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';
import 'package:sp_util/sp_util.dart';

/// 关于页面（服务商信息）
/// 业务逻辑参考 boss 项目 subs/user/about/index.vue
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _storeName = '';
  String _storeAvatar = '';
  Map<String, dynamic> _dls = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
    _loadDls();
  }

  void _loadStoreInfo() {
    try {
      final accountStr = SpUtil.getString(Constant.sysStoreAccount) ?? '';
      if (accountStr.isNotEmpty) {
        final account = jsonDecode(accountStr) as Map<String, dynamic>;
        _storeName = account['name']?.toString() ?? '';
        _storeAvatar = account['wximg']?.toString() ??
            account['logo']?.toString() ??
            '';
      }
      // 如果 sysStoreAccount 没有头像，尝试从 user 获取
      if (_storeAvatar.isEmpty) {
        final userStr = SpUtil.getString(Constant.user) ?? '';
        if (userStr.isNotEmpty) {
          final user = jsonDecode(userStr) as Map<String, dynamic>;
          final wxInfo = user['sysUserWx'];
          if (wxInfo is Map) {
            _storeAvatar = wxInfo['wximg']?.toString() ?? '';
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadDls() async {
    try {
      final result = await request(HttpApi.getDls, {});
      final data = result['data'];
      if (data is Map) {
        setState(() {
          _dls = Map<String, dynamic>.from(data);
        });
      }
    } catch (_) {
      // 接口异常由 http_helper 统一 Toast
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _avatarUrl {
    if (_storeAvatar.startsWith('http')) return _storeAvatar;
    if (_storeAvatar.isNotEmpty) {
      return '${Constant.imageBaseUrl}/$_storeAvatar';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(centerTitle: '关于'),
      backgroundColor: const Color(0xFFF5F6FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── 顶部商户头像 + 名称 ──
                      _buildHeader(),
                      // ── 服务商信息 ──
                      _buildInfoRow(
                        '服务商',
                        _dls['agentname']?.toString() ?? '--',
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        '联系人',
                        _dls['agentusername']?.toString() ?? '--',
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        '电话',
                        _dls['agenttel']?.toString() ?? '--',
                        isPhone: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          // 头像
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFEEEEEE), width: 2),
            ),
            child: ClipOval(
              child: _avatarUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _avatarUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFFF0F0F0),
                        child: const Icon(Icons.store,
                            size: 32, color: Color(0xFFCCCCCC)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFFF0F0F0),
                        child: const Icon(Icons.store,
                            size: 32, color: Color(0xFFCCCCCC)),
                      ),
                    )
                  : Container(
                      color: const Color(0xFFF0F0F0),
                      child: const Icon(Icons.store,
                          size: 32, color: Color(0xFFCCCCCC)),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _storeName.isNotEmpty ? _storeName : '商户',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isPhone = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 15, color: Color(0xFF707070)),
          ),
          const Spacer(),
          if (isPhone && value != '--')
            GestureDetector(
              onTap: () {
                // 可扩展：拨打电话
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.phone_outlined,
                    size: 16,
                    color: Color(0xFF006EFF),
                  ),
                ],
              ),
            )
          else
            Text(
              value,
              style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Divider(height: 1, color: Color(0xFFF0F0F0)),
    );
  }
}
