import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/push/push_config.dart';
import 'package:flutter_deer/push/push_message.dart';
import 'package:flutter_deer/push/push_router.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/log_utils.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:sp_util/sp_util.dart';

/// 推送服务：封装极光 JPush 的初始化、权限申请、设备注册、消息接收与分发。
///
/// 注意：极光推送仅支持 Android / iOS，Web 平台下会自动跳过初始化（不报错、正常显示页面）。
///
/// 使用方式：
/// 1. App 启动时调用 [init]（在 `runApp` 之前）；
/// 2. 登录成功后调用 [bindUser]，绑定用户/商户标识并上报设备 id；
/// 3. 退出登录或登录失效时调用 [unbindUser] 解绑，避免串号；
/// 4. 业务侧通过 [messageStream] 订阅自定义消息，通过 [openStream] 订阅通知点击。
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const String _tag = 'PUSH';

  /// 极光消息「下发通道」枚举（SDK platform / rom_type 字段）：
  /// 0=极光，1=小米，2=华为，3=魅族，4=OPPO，5=vivo，6=华硕，7=荣耀，8=FCM
  static const Map<int, String> _channelNames = <int, String>{
    0: '极光通道',
    1: '小米通道',
    2: '华为通道',
    3: '魅族通道',
    4: 'OPPO通道',
    5: 'vivo通道',
    6: '华硕通道',
    7: '荣耀通道',
    8: 'FCM通道',
  };

  /// 极光插件实例（Web 平台下为 null）
  JPushFlutterInterface? _jpush;

  bool _initialized = false;
  String _registrationId = '';

  /// 当前平台是否支持极光推送（仅 Android / iOS）
  bool get _isSupported => !kIsWeb;

  /// 自定义消息流（App 内静默接收，不展示通知栏）
  final StreamController<PushMessage> _messageController =
      StreamController<PushMessage>.broadcast();
  Stream<PushMessage> get messageStream => _messageController.stream;

  /// 通知点击事件流
  final StreamController<PushMessage> _openController = StreamController<PushMessage>.broadcast();
  Stream<PushMessage> get openStream => _openController.stream;

  /// 初始化推送服务。Web 平台会直接跳过。
  void init() {
    if (_initialized) return;
    _initialized = true;

    if (!_isSupported) {
      Log.d('当前平台不支持推送（Web），跳过初始化', tag: _tag);
      return;
    }

    _jpush = JPush.newJPush();
    _registerEventHandler();
    _jpush!.setup(
      appKey: PushConfig.appKey,
      channel: PushConfig.channel,
      debug: !Constant.inProduction,
    );
    Log.d('推送服务初始化完成', tag: _tag);
    FileLogWriter.instance.writeOperationLog('推送', '初始化');

    // 获取 RegistrationID 并打印到控制台：注册未完成（结果为空）时自动重试
    _fetchRegistrationId();

    // 冷启动且已登录：延迟绑定用户标识（等待 SDK 初始化完成）
    Future.delayed(const Duration(seconds: 1), () {
      if (_hasLoginState()) {
        bindUser();
      }
    });
  }

  /// 是否处于已登录状态（据此决定是否需要重新绑定别名/标签）
  bool _hasLoginState() {
    final String token = SpUtil.getString(Constant.token) ?? '';
    return token.isNotEmpty;
  }

  void _registerEventHandler() {
    final JPushFlutterInterface? jpush = _jpush;
    if (jpush == null) return;
    jpush.addEventHandler(
      onReceiveNotification: (Map<String, dynamic> event) async {
        // 收到通知（已展示在系统通知栏）
        _handlePushEvent('收到通知', event, _noop);
      },
      onOpenNotification: (Map<String, dynamic> event) async {
        // 用户点击通知栏通知
        _handlePushEvent('点击通知', event, (PushMessage msg) {
          if (!_openController.isClosed) {
            _openController.add(msg);
          }
          PushRouter.handle(msg);
        });
      },
      onReceiveMessage: (Map<String, dynamic> event) async {
        // 收到自定义消息（App 内静默接收）
        _handlePushEvent('收到自定义消息', event, (PushMessage msg) {
          if (!_messageController.isClosed) {
            _messageController.add(msg);
          }
        });
      },
      onNotifyMessageUnShow: (Map<String, dynamic> event) async {
        // 通知到达但未能展示（如通知权限被关闭、被系统展示策略拦截）
        _handlePushEvent('通知未展示', event, _noop);
      },
      onConnected: (Map<String, dynamic> event) async {
        // 长连接已连接时通知走极光通道（实时、不限量）；
        // 断开后离线通知只能等厂商通道下发（受厂商每日限额）或 App 上线后补发
        final bool connected = event['result'] == true;
        Log.d('推送长连接状态: $connected', tag: _tag);
        FileLogWriter.instance.writeOperationLog(
          '推送',
          '长连接状态',
          connected ? '已连接（走极光通道）' : '已断开（离线走厂商通道或待补发）',
        );
      },
      onCommandResult: (Map<String, dynamic> event) async {
        Log.json(jsonEncode(event), tag: '$_tag-命令结果');
        _persistCommandResult(event);
      },
    );
  }

  /// 统一处理推送回调：解析消息 → 记录日志（含下发通道）→ 执行业务逻辑。
  ///
  /// 无论处理成功还是失败都会输出控制台日志并写入本地日志文件，
  /// 每条记录都能看到「走的什么通道」：
  /// 0 极光（长连接）/ 1 小米 / 2 华为 / 3 魅族 / 4 OPPO / 5 vivo / 6 华硕 / 7 荣耀 / 8 FCM。
  void _handlePushEvent(
    String action,
    Map<String, dynamic> event,
    void Function(PushMessage message) onMessage,
  ) {
    final String channel = _resolveChannel(event);
    try {
      final PushMessage msg = PushMessage.fromRaw(event);
      Log.json(jsonEncode(msg.toLogMap()), tag: '$_tag-$action[$channel]');
      FileLogWriter.instance.writeOperationLog(
        '推送',
        action,
        '通道=$channel 标题=${msg.title ?? ''} 内容=${msg.content ?? ''} id=${msg.id ?? ''}',
      );
      onMessage(msg);
    } catch (e) {
      Log.e('$action处理失败: $e', tag: '$_tag-$action[$channel]');
      FileLogWriter.instance.writeOperationLog(
        '推送',
        '$action失败',
        '通道=$channel 错误=$e 数据=${_safeJsonEncode(event)}',
      );
    }
  }

  /// 解析消息的下发通道（极光长连接 or 各厂商通道）。
  ///
  /// 极光 SDK 在 extras 的 `cn.jpush.android.TYPE_PLATFORM` 字段回传通道枚举值
  /// （本地补丁已让通知消息也透出该字段）；iOS 侧统一下发通道为 APNs。
  static String _resolveChannel(Map<String, dynamic> event) {
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'APNs';
    final dynamic extras = event['extras'];
    if (extras is Map) {
      final dynamic platform = extras['cn.jpush.android.TYPE_PLATFORM'];
      final int? value = platform is num ? platform.toInt() : int.tryParse('$platform');
      if (value != null) {
        return '${_channelNames[value] ?? '未知通道'}($value)';
      }
    }
    return '未知';
  }

  /// 将厂商通道命令回调落盘，用于排查离线推送是否走厂商通道。
  ///
  /// 华为等设备默认屏蔽第三方应用 logcat，控制台日志取不到；
  /// 此处只记录 cmd / errorCode / platform，不写入厂商 token 等敏感信息。
  /// cmd=10000 为厂商 token 注册结果回调（extras.platform：2=华为）。
  void _persistCommandResult(Map<String, dynamic> event) {
    final dynamic cmd = event['cmd'];
    final dynamic errorCode = event['errorCode'];
    final dynamic extras = event['extras'];
    String platform = '';
    if (extras is Map) {
      final dynamic raw = extras['platform'];
      final int? value = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (value != null) {
        platform = ' 通道=${_channelNames[value] ?? '未知通道'}($value)';
      }
    }
    FileLogWriter.instance.writeOperationLog(
      '推送',
      '厂商命令回调',
      'cmd=$cmd errorCode=$errorCode$platform',
    );
    if (cmd == 10000) {
      FileLogWriter.instance.writeOperationLog(
        '推送',
        '厂商通道注册',
        errorCode == 0 ? '成功$platform' : '失败$platform errorCode=$errorCode',
      );
    }
  }

  static void _noop(PushMessage message) {}

  static String _safeJsonEncode(Object? data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  /// 获取 RegistrationID（设备在极光的唯一标识，后台可据此精准推送）
  Future<String> getRegistrationId() async {
    if (_registrationId.isNotEmpty) return _registrationId;
    final JPushFlutterInterface? jpush = _jpush;
    if (jpush == null) return '';
    try {
      _registrationId = await jpush.getRegistrationID();
      if (_registrationId.isEmpty) {
        // 注册未完成或网络异常时 SDK 返回空：打印失败，便于在控制台排查
        Log.e('获取 RegistrationID 失败：结果为空（注册未完成或网络异常）', tag: _tag);
        FileLogWriter.instance.writeOperationLog('推送', '获取RegistrationID失败', '结果为空');
      } else {
        Log.d('收到 RegistrationID: $_registrationId', tag: _tag);
        FileLogWriter.instance.writeOperationLog('推送', '获取RegistrationID', _registrationId);
      }
    } catch (e) {
      Log.e('获取 RegistrationID 失败: $e', tag: _tag);
      FileLogWriter.instance.writeOperationLog('推送', '获取RegistrationID失败', '$e');
    }
    return _registrationId;
  }

  /// 获取并打印 RegistrationID：注册未完成（结果为空）时自动重试，最多 5 次
  Future<void> _fetchRegistrationId() async {
    for (int i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final String rid = await getRegistrationId();
      if (rid.isNotEmpty) {
        return; // 成功：日志已在 getRegistrationId 内打印「收到 RegistrationID」
      }
    }
    Log.e('获取 RegistrationID 失败：重试 5 次结果仍为空（请检查网络与极光后台配置）', tag: _tag);
    FileLogWriter.instance.writeOperationLog('推送', '获取RegistrationID失败', '重试5次结果为空');
  }

  /// 上报设备 RegistrationID 到业务后台（接口暂定，先留入口）。
  ///
  /// 待后端提供接口后，在 [HttpApi.pushBindDevice] 填入接口路径即可生效。
  Future<void> reportRegistrationId() async {
    final String rid = await getRegistrationId();
    if (rid.isEmpty) {
      Log.d('RegistrationID 为空，跳过上报', tag: _tag);
      return;
    }

    const String api = HttpApi.pushBindDevice;
    if (api.isEmpty) {
      Log.d('推送设备绑定接口未配置（暂定），跳过上报，rid=$rid', tag: _tag);
      return;
    }

    final String userid = _getUserId();
    try {
      await request(
        api,
        <String, dynamic>{
          'registrationId': rid,
          'userid': userid,
        },
        false,
        false,
      );
      Log.d('上报 RegistrationID 成功: $rid，userid: $userid', tag: _tag);
      FileLogWriter.instance.writeOperationLog('推送', '上报设备ID', rid);
    } catch (e) {
      Log.e('上报 RegistrationID 失败: $e', tag: _tag);
    }
  }

  /// 通知权限是否已开启
  Future<bool> isNotificationEnabled() async {
    final JPushFlutterInterface? jpush = _jpush;
    if (jpush == null) return false;
    try {
      return await jpush.isNotificationEnabled();
    } catch (e) {
      Log.e('检查通知权限失败: $e', tag: _tag);
      return false;
    }
  }

  /// 申请通知权限。
  /// Android 13+ 需要通知权限才能展示通知；iOS 通过系统弹窗申请。
  /// 建议在合适的时机（如首次进入首页后）调用，避免过早打扰用户。
  Future<void> requestNotificationPermission() async {
    final JPushFlutterInterface? jpush = _jpush;
    if (jpush == null) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        jpush.applyPushAuthority();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        jpush.requestRequiredPermission();
      }
      Log.d('已请求通知权限', tag: _tag);
    } catch (e) {
      Log.e('请求通知权限失败: $e', tag: _tag);
    }
  }

  /// 跳转到系统设置中的通知设置页（用户关闭权限后引导其开启）
  void openNotificationSettings() {
    final JPushFlutterInterface? jpush = _jpush;
    if (jpush == null) return;
    try {
      jpush.openSettingsForNotification();
    } catch (e) {
      Log.e('跳转通知设置失败: $e', tag: _tag);
    }
  }

  /// 登录成功后绑定用户/商户标识：
  /// - alias = user_<userid>：后台可按用户精准推送
  /// - tag   = store_<sid>  ：后台可按门店（商户）批量推送
  /// 绑定完成后上报设备 id 到业务后台。
  Future<void> bindUser() async {
    final JPushFlutterInterface? jpush = _jpush;
    if (jpush == null) return;
    try {
      final String userid = _getUserId();
      final String sid = _getStoreId();

      if (userid.isNotEmpty) {
        final String alias = '${PushConfig.userAliasPrefix}$userid';
        final Map<dynamic, dynamic> result = await jpush.setAlias(alias);
        Log.d('设置 alias=$alias，结果: $result', tag: _tag);
        FileLogWriter.instance.writeOperationLog('推送', '绑定用户', alias);
      }
      if (sid.isNotEmpty) {
        final String tag = '${PushConfig.storeTagPrefix}$sid';
        final Map<dynamic, dynamic> result = await jpush.addTags(<String>[tag]);
        Log.d('添加 tag=$tag，结果: $result', tag: _tag);
        FileLogWriter.instance.writeOperationLog('推送', '绑定门店', tag);
      }
    } catch (e) {
      Log.e('绑定用户推送标识失败: $e', tag: _tag);
      FileLogWriter.instance.writeOperationLog('推送', '绑定用户失败', '$e');
    }

    // 登录后上报设备 id（接口暂定）
    await reportRegistrationId();
  }

  /// 退出登录 / 登录失效时解绑，避免上一账号收到下一账号的推送
  Future<void> unbindUser() async {
    final JPushFlutterInterface? jpush = _jpush;
    if (jpush == null) return;

    // 关键：在第一个 await 之前同步读取 userid / rid / sid / spid，
    // 避免调用方在 await 挂起期间执行 SpUtil.clear() 清空缓存导致取不到
    final String userid = _getUserId();
    final String rid = _registrationId;
    final String sid = _getStoreId();
    final String spid = _getSpid();
    final String token = _getToken();

    try {
      await jpush.deleteAlias();
      await jpush.cleanTags();
      Log.d('已解绑推送别名与标签', tag: _tag);
      FileLogWriter.instance.writeOperationLog('推送', '解绑用户');
    } catch (e) {
      Log.e('解绑用户推送标识失败: $e', tag: _tag);
    }

    // 解绑设备 id（调用 /jpush/unbind 接口）
    await unbindRegistrationId(rid: rid, token: token, userid: userid, sid: sid, spid: spid);
  }

  /// 解绑设备 RegistrationID（退出登录时调用 /jpush/unbind，参数与绑定一致）
  Future<void> unbindRegistrationId({
    required String rid,
    required String token,
    required String userid,
    required String sid,
    required String spid,
  }) async {
    if (rid.isEmpty) {
      Log.d('RegistrationID 为空，跳过解绑', tag: _tag);
      return;
    }

    try {
      await request(
        HttpApi.pushUnbindDevice,
        <String, dynamic>{'registrationId': rid},
        false,
        false,
        null,
        <String, String>{
          'token': token,
          'userid': userid,
          'sid': sid,
          'spid': spid,
        },
      );
      Log.d('解绑 RegistrationID 成功: $rid，userid: $userid', tag: _tag);
      FileLogWriter.instance.writeOperationLog('推送', '解绑设备ID', rid);
    } catch (e) {
      Log.e('解绑 RegistrationID 失败: $e', tag: _tag);
    }
  }

  /// 清空通知栏上的所有通知
  Future<void> clearAllNotifications() async {
    final JPushFlutterInterface? jpush = _jpush;
    if (jpush == null) return;
    try {
      await jpush.clearAllNotifications();
    } catch (e) {
      Log.e('清空通知失败: $e', tag: _tag);
    }
  }

  String _getUserId() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isEmpty) return '';
      final Map<String, dynamic> user = jsonDecode(userStr) as Map<String, dynamic>;
      return user['userid']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _getStoreId() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isEmpty) return '';
      final Map<String, dynamic> store = jsonDecode(storeStr) as Map<String, dynamic>;
      return store['id']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _getSpid() {
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isEmpty) return '';
      final Map<String, dynamic> store = jsonDecode(storeStr) as Map<String, dynamic>;
      return store['spid']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _getToken() {
    return SpUtil.getString(Constant.token) ?? '';
  }
}
