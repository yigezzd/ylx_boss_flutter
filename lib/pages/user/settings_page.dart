import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/user/business_print_page.dart';
import 'package:flutter_deer/pages/user/label_print_page.dart';
import 'package:flutter_deer/pages/user/scan_settings_page.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/widgets/boss_svg_icon.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 设置页面
/// 入口：个人中心「设置」菜单项
/// 包含：标签打印设置 / 业务打印设置 / 扫码设置
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget _buildItem(
    BuildContext context, {
    required String svgFile,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: BossSvgIcon(svgFile: svgFile, size: 28),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: Color(0xFFCCCCCC),
        size: 20,
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: const MyAppBar(centerTitle: '设置'),
      body: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildItem(
                context,
                svgFile: 'LabelPrint.svg',
                title: '标签打印设置',
                onTap: () {
                  if (!PermissionUtils.checkPermission('0302')) return;
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const LabelPrintPage()),
                  );
                },
              ),
              const Divider(height: 1, indent: 64, endIndent: 16),
              _buildItem(
                context,
                svgFile: 'printset.svg',
                title: '业务打印设置',
                onTap: () {
                  if (!PermissionUtils.checkPermission('0303')) return;
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const BusinessPrintPage()),
                  );
                },
              ),
              const Divider(height: 1, indent: 64, endIndent: 16),
              _buildItem(
                context,
                svgFile: 'saomashezhi.svg',
                title: '扫码设置',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanSettingsPage()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
