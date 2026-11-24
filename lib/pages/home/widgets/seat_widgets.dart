import 'package:flutter/material.dart';

// 席位相关公共 UI（供"业务"/"报表"等 tab 复用，对齐 boss 项目 business.vue / data.vue）：
// - SeatExpireTip：席位到期提醒条（专业版且距到期 15 天内显示）
// - showSeatLockedDialog：功能受限弹窗（基础版非白名单功能点击提示）
// - showSeatRenewDialog：席位续费弹窗（日期红色高亮，"解绑席位"跳转"我的"tab）

/// 席位到期提醒条（对齐 Vue .seat-tip）
class SeatExpireTip extends StatelessWidget {
  const SeatExpireTip({
    super.key,
    required this.seatCode,
    required this.expireDate,
    this.onRenewTap,
  });

  /// 席位号（无值时显示 "--"）
  final String seatCode;

  /// 席位到期日期（YYYY-MM-DD）
  final String expireDate;

  /// "立即续费"点击回调
  final VoidCallback? onRenewTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: const Color(0xFFFFF7E6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '席位$seatCode $expireDate 过期，',
            style: const TextStyle(fontSize: 13, color: Color(0xFFD46B08)),
          ),
          GestureDetector(
            onTap: onRenewTap,
            child: const Text(
              '立即续费',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFFF6A00),
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const Text(
            '。',
            style: TextStyle(fontSize: 13, color: Color(0xFFD46B08)),
          ),
        ],
      ),
    );
  }
}

/// 功能受限弹窗（对齐 Vue "功能受限！"弹窗）
void showSeatLockedDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('功能受限！'),
      content: const Text('您当前所选功能，需开通移动店务席位，\n请联系管理员，为您绑定席位或续费！'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );
}

/// 席位续费弹窗（对齐 Vue 席位续费弹窗）：
/// 提示登录商户后台续费，日期红色高亮，"解绑席位"跳转"我的"tab
void showSeatRenewDialog(
  BuildContext context, {
  required String expireDate,
  VoidCallback? onUnbind,
}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('提示'),
      // 日期红色高亮（对齐 Vue 席位续费弹窗：日期样式 color: red）
      content: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: '当前专业版席位 '),
            TextSpan(
              text: expireDate,
              style: const TextStyle(color: Color(0xFFFF4D4F)),
            ),
            const TextSpan(text: ' 过期，\n请登录商户后台，进行席位管理或续费!'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            // 对齐 Vue onSeatUnbind：跳转"我的"页（uni.switchTab）
            onUnbind?.call();
          },
          child: const Text(
            '解绑席位',
            style: TextStyle(
              color: Color(0xFF3764FF),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    ),
  );
}
