import 'package:flutter/material.dart';

/// 授权管理列表卡片（对齐 boss sysseat/index.vue 的三个 Tab）
///
/// - [SiteSeatCard] 收银站点授权
/// - [MachineCard] 收银机列表
/// - [ShopSeatCard] 移动管店授权
///
/// 列表项均为独立 StatelessWidget，由页面在外层包 RepaintBoundary 复用。

const Color _primary = Color(0xFF006EFF);
const Color _textMain = Color(0xFF333333);
const Color _border = Color(0xFFE5E7EB);

/// 文本取值：空串回退默认值（对齐 Vue `a || '--'`）
String seatText(dynamic value, [String fallback = '--']) {
  final String text = value?.toString() ?? '';
  return text.isNotEmpty ? text : fallback;
}

/// 两字段回退取值（对齐 Vue `a || b || fallback`）
String seatText2(dynamic first, dynamic second, [String fallback = '--']) {
  final String a = first?.toString() ?? '';
  if (a.isNotEmpty) {
    return a;
  }
  final String b = second?.toString() ?? '';
  return b.isNotEmpty ? b : fallback;
}

/// 站点归属机构文案：[编码]-名称（对齐 Vue seatStoreText）
String seatStoreText(Map<String, dynamic> item) {
  final String code = seatText2(item['storecode'], item['storeCode'], '');
  final String name = seatText2(item['storename'], item['storeName'], '');
  if (code.isNotEmpty && name.isNotEmpty) {
    return '[$code]-$name';
  }
  if (name.isNotEmpty) {
    return name;
  }
  return code.isNotEmpty ? '[$code]' : '--';
}

/// 站点状态颜色：空闲绿 / 使用中蓝 / 停用与已过期红（对齐 Vue seatStatusColor）
Color seatStatusColor(dynamic seatstatus) {
  final String s = seatstatus?.toString() ?? '';
  if (s == '0') {
    return const Color(0xFF00A870);
  }
  if (s == '1') {
    return _primary;
  }
  return const Color(0xFFD54B5A);
}

/// 信息行：左侧一段 + 右侧一段（右侧贴卡片最右），过长自动换行/省略
///
/// 对齐 Vue 的 `justify-content: space-between`（左段靠左、右段靠右）。
/// 注意不能用「左侧 Flexible + 右侧 Expanded + Align」组合：loose 弹性子项
/// 的实际宽度可能小于分配宽度，Row 的剩余空间会留在行尾，右侧文字会停在中间。
class SeatInfoRow extends StatelessWidget {
  const SeatInfoRow({super.key, required this.left, this.right});

  final Widget left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: left),
          if (right != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: right,
              ),
            ),
        ],
      ),
    );
  }
}

/// 行内操作按钮（轻量实现，替代 Material 按钮）
class SeatActionButton extends StatelessWidget {
  const SeatActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color textColor = filled ? Colors.white : (enabled ? _textMain : const Color(0xFF999999));
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? (enabled ? _primary : const Color(0xFFB7C9E8)) : null,
          border: filled
              ? null
              : Border.all(color: enabled ? const Color(0xFFDEDEDE) : const Color(0xFFEDEDED)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: textColor)),
      ),
    );
  }
}

/// 卡片外壳：白底 + 圆角 + 细边框（不使用 BoxShadow）
class _SeatCardShell extends StatelessWidget {
  const _SeatCardShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

Widget _cell(String text, {Color color = _textMain}) {
  return Text(
    text,
    style: TextStyle(fontSize: 13, color: color),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

/// 收银站点授权卡片（对齐 Vue 站点授权列表卡片）
class SiteSeatCard extends StatelessWidget {
  const SiteSeatCard({
    super.key,
    required this.item,
    required this.canBind,
    required this.onBind,
    required this.onUnbind,
  });

  final Map<String, dynamic> item;

  /// 是否可绑定/解绑（权限 014701）
  final bool canBind;
  final VoidCallback onBind;
  final VoidCallback onUnbind;

  @override
  Widget build(BuildContext context) {
    final bool bound = seatText(item['machinecode'], '').isNotEmpty;
    return _SeatCardShell(
      children: [
        // 使用状态紧跟站点编号（不右对齐）
        SeatInfoRow(
          left: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _cell('站点编号：${seatText(item['code'])}')),
              const SizedBox(width: 8),
              Text(
                seatText(item['seatstatusname']),
                style: TextStyle(fontSize: 13, color: seatStatusColor(item['seatstatus'])),
              ),
            ],
          ),
        ),
        SeatInfoRow(left: _cell('归属机构：${seatStoreText(item)}')),
        SeatInfoRow(
          left: _cell('到期日期：${seatText(item['validtime'])}'),
          right: _cell('绑定机号：${seatText(item['machinecode'], '未绑定')}'),
        ),
        SeatInfoRow(
          left: _cell('软件版本：${seatText(item['vcode'])}'),
          right: _cell('设备类型：${seatText2(item['clienttypeName'], item['clienttypename'])}'),
        ),
        SeatInfoRow(left: _cell('最后登录时间：${seatText(item['lasttime'])}')),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (bound)
              SeatActionButton(label: '解绑', enabled: canBind, onTap: onUnbind)
            else
              SeatActionButton(label: '绑定', filled: true, enabled: canBind, onTap: onBind),
          ],
        ),
      ],
    );
  }
}

/// 收银机列表卡片（对齐 Vue 收银机列表卡片）
class MachineCard extends StatelessWidget {
  const MachineCard({
    super.key,
    required this.item,
    required this.canOperate,
    required this.canManage,
    required this.onUploadLog,
    required this.onEnable,
    required this.onDelete,
    required this.onEdit,
  });

  final Map<String, dynamic> item;

  /// 上传日志 / 启用（权限 014702）
  final bool canOperate;

  /// 删除 / 编辑（权限 014701）
  final bool canManage;
  final VoidCallback onUploadLog;
  final VoidCallback onEnable;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final bool stopped = item['stopflag']?.toString() == '1';
    return _SeatCardShell(
      children: [
        SeatInfoRow(
          left: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _cell('设备机号：${seatText(item['code'])}')),
              const SizedBox(width: 8),
              Text(
                stopped ? '(停用)' : '(启用)',
                style: const TextStyle(fontSize: 13, color: _primary),
              ),
            ],
          ),
          right: _cell('设备名称：${seatText(item['name'])}'),
        ),
        SeatInfoRow(left: _cell('归属机构：${seatText(item['storeName'])}')),
        SeatInfoRow(
          left: _cell('软件版本：${seatText(item['vcode'])}'),
          right: _cell('最后登录用户：${seatText(item['lastuser'])}'),
        ),
        SeatInfoRow(
          left: _cell('最后登录时间：${seatText(item['lasttime'])}'),
          right: _cell('设备类型：${seatText(item['clienttypeName'])}'),
        ),
        SeatInfoRow(left: _cell('绑定站点：${seatText2(item['seatcode'], item['seatCode'], '未绑定')}')),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SeatActionButton(label: '上传日志', enabled: canOperate, onTap: onUploadLog),
            const SizedBox(width: 8),
            // 对齐 Vue：行内不提供“停用”，仅停用中的收银机显示“启用”
            if (stopped)
              SeatActionButton(label: '启用', filled: true, enabled: canOperate, onTap: onEnable),
            if (stopped) const SizedBox(width: 8),
            SeatActionButton(label: '删除', enabled: canManage, onTap: onDelete),
            const SizedBox(width: 8),
            SeatActionButton(label: '编辑', filled: true, enabled: canManage, onTap: onEdit),
          ],
        ),
      ],
    );
  }
}

/// 移动管店授权卡片（对齐 Vue 移动管店授权列表卡片）
class ShopSeatCard extends StatelessWidget {
  const ShopSeatCard({
    super.key,
    required this.item,
    required this.canBind,
    required this.canOperate,
    required this.onBind,
    required this.onUnbind,
    required this.onEnable,
    required this.onDisable,
  });

  final Map<String, dynamic> item;

  /// 绑定 / 解绑（权限 014701）
  final bool canBind;

  /// 启用 / 停用（权限 014702）
  final bool canOperate;
  final VoidCallback onBind;
  final VoidCallback onUnbind;
  final VoidCallback onEnable;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final String userCode = item['usercode']?.toString() ?? '';
    final bool isAdmin = userCode == '1001';
    final bool bound = (item['userid']?.toString() ?? '').isNotEmpty;
    // 对齐 Vue：stopflag == 0 时显示“停用”，其余（含空值）显示“启用”
    final bool stopped = item['stopflag']?.toString() != '0';
    final String userName = seatText(item['username'], '');
    return _SeatCardShell(
      children: [
        SeatInfoRow(
          left: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _cell('席位：${seatText(item['code'])}')),
              const SizedBox(width: 8),
              Text(
                seatText(item['seatstatusname'], ''),
                style: const TextStyle(fontSize: 13, color: _primary),
              ),
            ],
          ),
          right: Text(
            userName.isEmpty ? '--' : '$userName[$userCode]',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textMain),
          ),
        ),
        SeatInfoRow(
          left: _cell('归属机构：${seatText(item['storename'])}'),
          right: _cell('角色：${seatText(item['rolename'])}'),
        ),
        SeatInfoRow(
          left: _cell('席位到期时间：${seatText(item['validtime'])}'),
          right: _cell('最后登录时间：${seatText(item['lastlogin'])}'),
        ),
        if (!isAdmin) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (bound)
                SeatActionButton(label: '解绑', enabled: canBind, onTap: onUnbind)
              else
                SeatActionButton(label: '绑定', enabled: canBind, onTap: onBind),
              const SizedBox(width: 8),
              if (stopped)
                SeatActionButton(label: '启用', filled: true, enabled: canOperate, onTap: onEnable)
              else
                SeatActionButton(label: '停用', filled: true, enabled: canOperate, onTap: onDisable),
            ],
          ),
        ],
      ],
    );
  }
}

/// 空数据占位（static 复用，避免每次 build 重建闭包）
class SeatEmptyPlaceholder extends StatelessWidget {
  const SeatEmptyPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      ),
    );
  }
}
