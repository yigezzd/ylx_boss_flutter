import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/business/members/basic/add.dart';
import 'package:flutter_deer/pages/business/members/basic/second_list.dart';
import 'package:flutter_deer/util/math_utils.dart';
import 'package:flutter_deer/util/permission_utils.dart';

/// 会员详情页 —— 对齐 boss 项目 subs/member/members/edit.vue
class MemberDetailPage extends StatefulWidget {
  const MemberDetailPage({super.key, required this.vipid, required this.vipno});

  final String vipid;
  final String vipno;

  @override
  State<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends State<MemberDetailPage> {
  Map<String, dynamic> _vipInfo = {};
  List<Map<String, dynamic>> _labelInfoList = [];
  List<Map<String, dynamic>> _textOrDate = [];
  bool _loading = true;

  /// 数据是否有变更（编辑保存后回传给列表页刷新）
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final params = {
      'vipid': widget.vipid,
      'vipno': widget.vipno,
      'sharevipflag': '',
      'notwx': true,
    };
    try {
      final results = await Future.wait([
        request(HttpApi.vipInfoGetVipInfo, params),
        request(HttpApi.vipInfoGetVipInfoOtherData, params, false, false),
        request(HttpApi.vipSetGetVipMoreSetList, <String, dynamic>{}, false, false),
      ]);
      if (!mounted) return;
      setState(() {
        final info = results[0]['data'];
        _vipInfo = info is Map<String, dynamic> ? info : <String, dynamic>{};

        final other = results[1]['data'];
        if (other is Map<String, dynamic>) {
          final labels = other['labelInfoList'] as List? ?? [];
          _labelInfoList = labels.cast<Map<String, dynamic>>();
        }

        final set = results[2]['data'];
        if (set is List) {
          _textOrDate = set
              .cast<Map<String, dynamic>>()
              .where((it) =>
                  _toInt(it['coltype']) == 1 &&
                  _toInt(it['status']) == 1 &&
                  _toInt(it['onlinestatus']) == 1)
              .toList();
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _toInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  String _timeSplice(dynamic time) {
    final s = time?.toString() ?? '';
    if (s.isEmpty) return '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  /// 进入编辑页（对齐 Vue edit()，权限 010703）
  Future<void> _edit() async {
    if (!PermissionUtils.checkPermission('010703')) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: '/业务/会员/会员编辑'),
        builder: (_) => MemberAddPage(
          isAdd: 2,
          data: {
            'vipid': widget.vipid,
            'vipno': widget.vipno,
          },
        ),
      ),
    );
    if ((saved ?? false) && mounted) {
      _changed = true;
      setState(() => _loading = true);
      _loadData();
    }
  }

  /// 副卡详情（对齐 Vue toList）
  Future<void> _toSecondList() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/业务/会员/副卡列表'),
        builder: (_) => MemberSecondListPage(
          vipid: widget.vipid,
          vipno: widget.vipno,
          parentcardid: _vipInfo['parentcardid']?.toString() ?? '',
        ),
      ),
    );
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => Navigator.pop(context, _changed),
        ),
        title: const Text('会员详情',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF006EFF)))
          : ListView(
              cacheExtent: 800,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 8),
                _buildBalanceCard(),
                const SizedBox(height: 8),
                _buildTagCard(),
                const SizedBox(height: 8),
                _buildInfoCard(),
              ],
            ),
    );
  }

  // ──────────── 头部会员卡（对齐 Vue wrapper + bg-img）────────────
  Widget _buildHeaderCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          // 背景图（对齐 Vue 远程 vipbg 图，加载失败时用渐变兜底）
          Positioned.fill(
            child: Image.network(
              'http://byyoupic.oss-cn-shenzhen.aliyuncs.com/bycloud/zm/null/pro_bbaae44a7d8b64459f8f11e7a31bbcfe.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFF6E8), Color(0xFFFFE9C8)],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _vipInfo['vipno']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        _vipInfo['viptypename']?.toString() ?? '',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    // 编辑按钮（对齐 Vue 编辑 + icon-bianji，权限 010703）
                    GestureDetector(
                      onTap: _edit,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('编辑', style: TextStyle(fontSize: 14, color: Color(0xFF8A5D1E))),
                          SizedBox(width: 4),
                          Icon(Icons.edit_outlined, size: 14, color: Color(0xFF8A5D1E)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '会员姓名：${_vipInfo['vipname'] ?? ''}',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '手机号码：${_vipInfo['mobile'] ?? ''}',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                    ),
                    const SizedBox(width: 10),
                    // 副卡详情标签
                    GestureDetector(
                      onTap: _toSecondList,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8A5D1E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            const Text('副卡详情', style: TextStyle(fontSize: 10, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 余额卡片（对齐 Vue boxbg 金色边框卡片）────────────
  Widget _buildBalanceCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEED2B4)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('储卡余额', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
                      const SizedBox(height: 4),
                      Text(
                        MathUtils.formatDecimal(3, _vipInfo['nowmoney']),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本金：${MathUtils.formatDecimal(3, _vipInfo['capitalmoney'])}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '赠金：${MathUtils.formatDecimal(3, _vipInfo['givemoney'])}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEED2B4)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '会员积分：${MathUtils.formatDecimal(4, _vipInfo['nowpoint'])}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF7A7A7A)),
                  ),
                ),
                Expanded(
                  child: Text(
                    '零钱余额：${MathUtils.formatDecimal(3, _vipInfo['pocketmoney'])}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF7A7A7A)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 标签卡片 ────────────
  Widget _buildTagCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('会员标签：', style: TextStyle(fontSize: 14, color: Color(0xFF686868))),
          Expanded(
            child: _labelInfoList.isEmpty
                ? const Text('', style: TextStyle(fontSize: 14))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final item in _labelInfoList)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF9EE),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: const Color(0xFFEED2B4)),
                          ),
                          child: Text(
                            item['name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF8A5D1E)),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ──────────── 信息卡片 ────────────
  Widget _buildInfoCard() {
    final birthday = _timeSplice(_vipInfo['birthday']).isNotEmpty
        ? _timeSplice(_vipInfo['birthday'])
        : _timeSplice(_vipInfo['birthdaylan']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          _buildInfoRow('累计消费额', MathUtils.formatDecimal(3, _vipInfo['allsalemoney'])),
          _buildInfoRow('会员生日', birthday),
          _buildInfoRow('未销日期', _timeSplice(_vipInfo['lastsaledate'])),
          _buildInfoRow('联系地址', _vipInfo['address']?.toString() ?? ''),
          for (final item in _textOrDate)
            _buildInfoRow(
              '${item['title']?.toString() ?? ''}：',
              _vipInfo[item['extracolumn']?.toString()]?.toString() ?? '',
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
            ),
          ),
        ],
      ),
    );
  }
}
