import 'dart:convert';

/// 推送消息类型（与后端约定，通过通知附加字段 extras 中的 `type` 下发）
enum PushMessageType {
  /// 系统公告
  notice,

  /// 单据 / 订单状态变更
  bill,

  /// 库存预警 / 证照到期提醒
  stock,

  /// 审批提醒
  approval,

  /// 未知 / 未指定类型
  unknown,
}

/// 统一的通知消息 / 自定义消息模型
///
/// 极光通知消息与自定义消息的字段结构略有差异，这里做归一化，
/// 统一从 `extras` 中读取跳转所需的业务字段。
class PushMessage {
  const PushMessage({
    required this.raw,
    this.id,
    this.title,
    this.content,
    this.extras = const <String, dynamic>{},
  });

  /// 原始消息（来自极光回调的 Map）
  final Map<String, dynamic> raw;

  /// 通知 / 消息 ID
  final String? id;

  /// 标题
  final String? title;

  /// 内容
  final String? content;

  /// 附加字段（跳转参数都在这里，由后端下发）
  final Map<String, dynamic> extras;

  /// 消息类型
  PushMessageType get type => _parseType(extras['type']?.toString());

  /// 目标页面路由（extras 中显式指定时优先使用）
  String? get route => _extrasString('route');

  /// 单据类型 id（映射到对应单据列表页）
  String? get billTypeId => _extrasString('billtypeid');

  /// 跳转内置 WebView 的 URL
  String? get url => _extrasString('url');

  /// 是否携带跳转信息
  bool get hasNavigateInfo => route != null || billTypeId != null || url != null;

  String? _extrasString(String key) {
    final dynamic value = extras[key];
    if (value == null) return null;
    final String text = value.toString();
    return text.isEmpty ? null : text;
  }

  static PushMessageType _parseType(String? value) {
    switch (value) {
      case 'notice':
        return PushMessageType.notice;
      case 'bill':
        return PushMessageType.bill;
      case 'stock':
        return PushMessageType.stock;
      case 'approval':
        return PushMessageType.approval;
      default:
        return PushMessageType.unknown;
    }
  }

  /// 从极光回调的原始 Map 构造（兼容通知消息与自定义消息的字段差异）
  factory PushMessage.fromRaw(Map<String, dynamic> raw) {
    return PushMessage(
      raw: raw,
      id: _firstString(raw, <String>['id', 'messageId', 'msg_id']),
      title: _firstString(raw, <String>['title']),
      content: _firstString(raw, <String>['content', 'message', 'alert']),
      extras: _extractExtras(raw),
    );
  }

  static Map<String, dynamic> _extractExtras(Map<String, dynamic> raw) {
    final Map<String, dynamic> result = <String, dynamic>{};

    final dynamic extras = raw['extras'];
    if (extras is Map) {
      result.addAll(Map<String, dynamic>.from(extras));

      // 极光 Android 通知的业务附加字段套在 cn.jpush.android.EXTRA 里，平铺到顶层
      final dynamic inner = extras['cn.jpush.android.EXTRA'];
      if (inner is Map) {
        result.addAll(Map<String, dynamic>.from(inner));
      } else if (inner is String && inner.isNotEmpty) {
        // 兼容 EXTRA 为 JSON 字符串的情况
        try {
          final dynamic decoded = jsonDecode(inner);
          if (decoded is Map) {
            result.addAll(Map<String, dynamic>.from(decoded as Map));
          }
        } catch (_) {}
      }
    }

    // 兼容 router / route 两种命名（后台可能配成 router）
    if (!result.containsKey('route') && result.containsKey('router')) {
      result['route'] = result['router'];
    }

    return result;
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = map[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }
    return null;
  }

  /// 供日志输出
  Map<String, dynamic> toLogMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'content': content,
      'type': type.name,
      'extras': extras,
    };
  }
}
