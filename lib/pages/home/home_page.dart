import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/home/business_page.dart';
import 'package:flutter_deer/pages/home/main_home_page.dart';
import 'package:flutter_deer/pages/home/my_page.dart';
import 'package:flutter_deer/pages/home/report_page.dart';
import 'package:flutter_deer/pages/login/page/login_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/version_check_utils.dart';
import 'package:flutter_deer/widgets/double_tap_back_exit_app.dart';
import 'package:sp_util/sp_util.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 当前底部导航索引（对应 [_visibleTabs]）
  int _currentIndex = 0;
  late final PageController _pageController;

  late final List<Widget> _pages = [
    const MainHomePage(),
    const BusinessPage(),
    const ReportPage(),
    const MyPage(),
  ];

  /// 当前可见的底部导航项
  static const List<_TabItem> _visibleTabs = [
    _TabItem(icon: Icons.home, label: '首页'),
    _TabItem(icon: Icons.apps, label: '业务'),
    _TabItem(icon: Icons.insert_chart_outlined_outlined, label: '报表'),
    _TabItem(icon: Icons.person, label: '我的'),
  ];

  /// 可见 tab 索引到 [_pages] 索引的映射
  static const List<int> _tabToPageIndex = [0, 1, 2, 3];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _tabToPageIndex[_currentIndex]);
    // 防御性检查：如果缓存中缺少 token 或商户信息，立即跳转登录页
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_hasValidLoginState()) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute<void>(builder: (_) => const LoginPage()),
          (route) => false,
        );
        return;
      }
      // 初始化设备信息并执行版本检查（启动时用户可能已登录，也可能未登录）
      await Device.initDeviceInfo();
      if (mounted) {
        VersionCheckUtils.checkUpdate(context: context, silent: true);
        // 启动时预取权限数据（登录响应已携带初始 rolemap，此处确保缓存最新）
        PermissionUtils.fetchRoleInfoRetMap();
      }
    });
  }

  /// 检查缓存中是否有有效的 token 和商户信息
  bool _hasValidLoginState() {
    final token = SpUtil.getString(Constant.token) ?? '';
    if (token.isEmpty) return false;

    try {
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isEmpty) return false;
      final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
      final storeId = storeMap['id'];
      if (storeId == null || storeId == 0 || storeId == '0') return false;
    } catch (_) {
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int tabIndex) {
    setState(() {
      _currentIndex = tabIndex;
      _pageController.jumpToPage(_tabToPageIndex[tabIndex]);
    });
    // 任意 tab 切换均触发权限刷新（对齐 boss 项目 onShow → fetchRoleInfoRetMap）
    // PermissionUtils 内置 10s 节流 + 并发不重入，频繁切换不会重复请求
    PermissionUtils.fetchRoleInfoRetMap();
  }

  @override
  Widget build(BuildContext context) {
    return DoubleTapBackExitApp(
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        extendBody: true, // 防止鸿蒙设备上 PageView 内 Scaffold 顶部出现空白
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: _pages,
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  /// 自定义底部导航栏，确保图标在所有状态下都能正确渲染
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_visibleTabs.length, (i) {
              final tab = _visibleTabs[i];
              final selected = i == _currentIndex;
              final color = selected ? const Color(0xFF006EFF) : const Color(0xFF6B7280);
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onTabTapped(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(tab.icon, size: 24, color: color),
                      const SizedBox(height: 2),
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 兼容旧路由引用
typedef Home = HomePage;
