/// 审批提醒跳转列表页时携带的初始审核状态（Tab 索引）。
///
/// 仅由审批提醒入口（ApprovalReminderHelper）在跳转前通过
/// [setPendingStatusIndex] 置为"待审核"(1)；目标单据列表页在 initState
/// 调用 [consumePendingStatusIndex] 读取并立即清零。
///
/// 因此从业务页等正常入口进入列表页时该值始终为默认的 0（"全部"），
/// 只有点击首页/库存预警页的单据审批提醒跳转时才会停留在"待审核"。
class ReviewNavState {
  ReviewNavState._();

  /// "待审核"对应的状态 Tab 索引（各单据列表页约定：0=全部 1=待审核 2=已审核 3=已驳回）
  static const int statusIndexPendingReview = 1;

  static int _pendingStatusIndex = 0;

  /// 审批提醒跳转前设置目标列表页应停留的审核状态 Tab 索引
  static void setPendingStatusIndex(int index) => _pendingStatusIndex = index;

  /// 目标列表页 initState 读取待应用的初始 Tab 索引，读取后立即清零，
  /// 保证仅对本次跳转生效，不影响后续正常进入其它列表页。
  ///
  /// 无"待审核"Tab 的页面（如盘点计划）也应调用本方法以清零标志，避免泄漏。
  static int consumePendingStatusIndex() {
    final int v = _pendingStatusIndex;
    _pendingStatusIndex = 0;
    return v;
  }
}
