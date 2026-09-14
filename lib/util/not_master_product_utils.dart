import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 非供货资格商品校验弹窗结果（对齐小程序 handleNotMasterProduct）
enum NotMasterProductResult {
  /// 取消/关闭弹窗，不保存
  cancel,

  /// 删除不匹配商品后保存
  removeThenSave,

  /// 保留全部商品继续保存
  keepAll,
}

/// 读取登录参数 cgNotMasterProductFlag（2=警告模式 / 3=阻止模式，其余不校验）
int getCgNotMasterProductFlag() {
  final cfgStr = SpUtil.getString(Constant.loginParamResp) ?? '';
  if (cfgStr.isEmpty) return 0;
  try {
    final cfg = jsonDecode(cfgStr) as Map<String, dynamic>;
    return int.tryParse(cfg['cgNotMasterProductFlag']?.toString() ?? '0') ?? 0;
  } catch (_) {
    return 0;
  }
}

/// 非供货资格商品校验弹窗（对齐小程序 handleNotMasterProduct / 后台 not-master-product 组件）
///
/// flag=3: 阻止模式，仅提示，不可继续；
/// flag=2: 警告模式，点击"继续"后可选择
/// "删除不匹配商品后保存" / "保留全部商品继续保存"（对齐小程序 showActionSheet）。
Future<NotMasterProductResult> showNotMasterProductDialog(
  BuildContext context, {
  required int flag,
  required List<String> names,
}) async {
  final nameStr = names.length > 3 ? '${names.sublist(0, 3).join('、')}...' : names.join('、');

  if (flag == 3) {
    // 阻止模式：仅提示，不可继续
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('无法录入非供货资格的商品'),
        content: Text('以下商品与供应商不匹配，无法保存：\n$nameStr'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
    return NotMasterProductResult.cancel;
  }

  // 警告模式（flag=2）：先确认是否继续录入
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('存在非供货资格的商品'),
      content: Text('本单存在非供货资格的商品（${names.length}个），请确认是否继续录入：\n$nameStr'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续')),
      ],
    ),
  );
  if (confirmed != true) return NotMasterProductResult.cancel;

  // 对齐小程序 showActionSheet：["删除不匹配商品后保存", "保留全部商品继续保存"]
  final idx = await showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('删除不匹配商品后保存', textAlign: TextAlign.center),
            onTap: () => Navigator.pop(ctx, 0),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('保留全部商品继续保存', textAlign: TextAlign.center),
            onTap: () => Navigator.pop(ctx, 1),
          ),
        ],
      ),
    ),
  );
  if (idx == 0) return NotMasterProductResult.removeThenSave;
  if (idx == 1) return NotMasterProductResult.keepAll;
  return NotMasterProductResult.cancel;
}
