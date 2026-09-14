import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/home/custom/sup_file_warn_page.dart';
import 'package:flutter_deer/pages/home/widgets/approval_reminder_helper.dart';

/// 库存预警页面（对齐 Vue /subs/comPages/stockWarning）
class StockWarningPage extends StatefulWidget {
  const StockWarningPage({super.key});

  @override
  State<StockWarningPage> createState() => _StockWarningPageState();
}

class _StockWarningPageState extends State<StockWarningPage> {
  List<_TipItem> _tips = [];
  int _approvalCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final res = await request(HttpApi.getIndexTipTotal, <String, dynamic>{});
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        final rawList = (data['tiplist'] as List?) ?? [];
        final tips = <_TipItem>[];
        for (final item in rawList) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          final title = item['title']?.toString() ?? '';
          if (title.isEmpty) {
            continue;
          }
          // 只显示特定类型（对齐 Vue: 商品即将过期/库存不足/库存积压/供应商过期提醒）
          if (!['商品即将过期', '库存不足', '库存积压', '供应商过期提醒'].contains(title)) {
            continue;
          }

          String link = '';
          String menuid = '';
          switch (title) {
            case '商品即将过期':
              link = '../data/inventory/vaildWarn/index';
              menuid = '0214';
              break;
            case '库存不足':
              link = '../data/inventory/inventoryWarn/index?currTab=0';
              menuid = '0213';
              break;
            case '库存积压':
              link = '../data/inventory/inventoryWarn/index?currTab=1';
              menuid = '0213';
              break;
            case '供应商过期提醒':
              link = 'supfilewarn';
              menuid = '';
              break;
          }
          // 供应商过期提醒徽标数来自 supfilescount（对齐 Vue）
          final count = title == '供应商过期提醒'
              ? (int.tryParse(data['supfilescount']?.toString() ?? '0') ?? 0)
              : 0;
          tips.add(_TipItem(title: title, link: link, menuid: menuid, count: count));
        }
        _tips = tips;
      }

      // 获取待审批数量
      _approvalCount = await ApprovalReminderHelper.fetchCount();
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openApproval() async {
    await ApprovalReminderHelper.checkAndShow(context);
  }

  void _navigateTo(String title) {
    // 按标题映射到 Flutter 路由
    switch (title) {
      case '库存不足':
        Navigator.of(context).pushNamed('/inventoryWarn');
        break;
      case '库存积压':
        Navigator.of(context).pushNamed('/inventoryWarn', arguments: {'currTab': '1'});
        break;
      case '商品即将过期':
        Navigator.of(context).pushNamed('/vaildWarn');
        break;
      case '供应商过期提醒':
        // 跳转证照过期提醒列表页（对齐 Vue supFileWarn）
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SupFileWarnPage(),
          ),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('跳转: $title', style: const TextStyle(fontSize: 13)),
              duration: const Duration(seconds: 1)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('消息提醒'),
        backgroundColor: const Color(0xFF006EFF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < _tips.length; i++)
                        _buildItem(
                          context,
                          _tips[i].title,
                          showDot: _tips[i].count <= 0,
                          count: _tips[i].count > 0 ? _tips[i].count : null,
                          onTap: () => _navigateTo(_tips[i].title),
                          isLast: i == _tips.length - 1 && _approvalCount == 0,
                        ),
                      if (_approvalCount > 0)
                        _buildItem(
                          context,
                          '待审批单据',
                          count: _approvalCount,
                          onTap: _openApproval,
                          isLast: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    String title, {
    bool showDot = false,
    int? count,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF5F5F5))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
            ),
            if (showDot)
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      const BoxDecoration(color: Color(0xFFFF4400), shape: BoxShape.circle)),
            if (count != null && count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: const Color(0xFFFF4400), borderRadius: BorderRadius.circular(11)),
                child: Text('$count',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            if (showDot || (count != null && count > 0)) const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF999999)),
          ],
        ),
      ),
    );
  }
}

class _TipItem {
  const _TipItem({required this.title, required this.link, required this.menuid, this.count = 0});
  final String title;
  final String link;
  final String menuid;
  final int count;
}
