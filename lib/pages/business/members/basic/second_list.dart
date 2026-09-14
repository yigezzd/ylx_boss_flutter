import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';

/// 主卡/副卡列表页 —— 对齐 boss 项目 subs/member/members/secondList.vue
///
/// [parentcardid] == '1' 时标题为“副卡列表”，否则为“主卡列表”。
class MemberSecondListPage extends StatefulWidget {
  const MemberSecondListPage({
    super.key,
    required this.vipid,
    required this.vipno,
    required this.parentcardid,
  });

  final String vipid;
  final String vipno;
  final String parentcardid;

  @override
  State<MemberSecondListPage> createState() => _MemberSecondListPageState();
}

class _MemberSecondListPageState extends State<MemberSecondListPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await request(HttpApi.vipInfoGetVipInfoOtherData, {
        'vipid': widget.vipid,
        'vipno': widget.vipno,
        'sharevipflag': '',
      });
      final data = res['data'];
      if (!mounted) return;
      setState(() {
        final rows = (data is Map<String, dynamic> ? data['vipSecondList'] as List? : null) ?? [];
        _list = rows.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(widget.parentcardid == '1' ? '副卡列表' : '主卡列表',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : _list.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  cacheExtent: 800,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                  itemCount: _list.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RepaintBoundary(child: _SecondCard(item: _list[index])),
                    );
                  },
                ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 60, color: Color(0xFFD1D5DB)),
          SizedBox(height: 12),
          Text('暂无数据', style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// 主/副卡卡片项（独立 Widget，优化低端设备滑动性能）
// ─────────────────────────────────────────────────
class _SecondCard extends StatelessWidget {
  const _SecondCard({required this.item});

  final Map<String, dynamic> item;

  String _timeSplice(dynamic time) {
    final s = time?.toString() ?? '';
    if (s.isEmpty) return '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _validdateify(Map<String, dynamic> item) {
    if (item['validflag']?.toString() == '0') return '长期有效';
    final validdate = item['validdate']?.toString() ?? '';
    return validdate.length >= 10 ? validdate.substring(0, 10) : '长期有效';
  }

  String _cardstatusText(dynamic status) {
    final s = int.tryParse(status?.toString() ?? '') ?? 0;
    switch (s) {
      case 0:
        return '未发行';
      case 1:
        return '正常';
      case 2:
        return '挂失';
      case 3:
        return '注销';
      default:
        return '已过期';
    }
  }

  @override
  Widget build(BuildContext context) {
    const infoStyle = TextStyle(fontSize: 12, color: Color(0xFF7A7A7A));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡号【分类】 + 状态标签
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item['vipno'] ?? ''}【${item['typename'] ?? ''}】',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF999999),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _cardstatusText(item['cardstatus']),
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('会员姓名：${item['vipname'] ?? ''}', style: infoStyle)),
              Expanded(child: Text('手机号码：${item['mobile'] ?? ''}', style: infoStyle)),
            ],
          ),
          const SizedBox(height: 6),
          Text('身份号码：${item['idcardno'] ?? ''}', style: infoStyle),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('绑定日期：${_timeSplice(item['bindtime'])}', style: infoStyle)),
              Expanded(child: Text('有效日期：${_validdateify(item)}', style: infoStyle)),
            ],
          ),
          const SizedBox(height: 6),
          Text('会员地址：${item['address'] ?? ''}', style: infoStyle),
        ],
      ),
    );
  }
}
