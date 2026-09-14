import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/main.dart';
import 'package:flutter_deer/net/dio_utils.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/pages/login/page/login_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 防止多个并发请求同时触发跳转登录页
bool _isRedirectingToLogin = false;

/// 记录接口操作日志
///
/// 所有接口调用（[request]）的成功与失败都会经此记录到 crash_log 分类，
/// [data] 为响应数据（由 FileLogWriter 自动截断摘要），
/// [params] 过大时同样由 FileLogWriter 自动截断保护。
void _logApi(String url, dynamic params, String result, {dynamic data}) {
  String path = url;
  try {
    path = Uri.parse(url).path;
  } catch (_) {}
  FileLogWriter.instance.writeErrorLog(
    null,
    path,
    params is String ? params : json.encode(params),
    result,
    data: data,
  );
}

/// ylx-boss 风格的统一请求方法
///
/// 默认 POST，请求体为两层结构：
///   外层：sid / spid / client / token / sign / requestId（公共参数）
///   内层 params：clientflag / userid / ...业务参数
///
/// 返回完整接口响应 Map（包含 retcode / retmsg / data 等字段）。
/// - retcode == 0 时 Future 正常完成 → 执行 .then()
/// - retcode != 0 或网络异常时 Future 以异常完成 → 执行 .catchError()
///   拦截器已统一 Toast 提示 retmsg，调用方 .catchError 中无需再弹错误
///
/// 用法示例：
/// ```dart
/// // data 为 Map → 自动合并 clientflag/userid 后作为 params
/// request(HttpApi.someUrl, {'key': 'value'})
///
/// // data 为非 Map（如字符串）→ 直接作为 params 原始值
/// request(HttpApi.delProduct, productId)
/// ```
Future<Map<String, dynamic>> request(
  String url, [
  dynamic data,
  bool showLoading = false,
  bool showError = true,
  dynamic rawParamsValue,
]) async {
  final String token = SpUtil.getString(Constant.token) ?? '';

  // 从 store 中读取 sid / spid
  String sid = '';
  String spid = '';
  try {
    final String storeStr = SpUtil.getString(Constant.store) ?? '';
    if (storeStr.isNotEmpty) {
      final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
      sid = storeMap['id']?.toString() ?? '';
      spid = storeMap['spid']?.toString() ?? '';
    }
  } catch (_) {}

  // 从 user 中读取 userid
  String? userid;
  try {
    final String userStr = SpUtil.getString(Constant.user) ?? '';
    if (userStr.isNotEmpty) {
      final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
      userid = userMap['userid']?.toString();
    }
  } catch (_) {}

  // 构建 params：
  // - rawParamsValue 优先（兼容旧调用）
  // - data 为非 Map 时，直接作为 params 原始值（如删除接口传 productid 字符串）
  // - data 为 Map 时，合并 clientflag/userid/sid/spid
  final dynamic params;
  if (rawParamsValue != null) {
    params = rawParamsValue;
  } else if (data is Map<String, dynamic>) {
    params = <String, dynamic>{
      'clientflag': 1,
      'sid': sid.isNotEmpty ? sid : '0',
      'spid': spid.isNotEmpty ? spid : '0',
      if (userid != null && userid.isNotEmpty) 'userid': userid,
      ...data,
    };
  } else if (data != null) {
    // 非 Map（如 String / int），直接作为 params
    params = data;
  } else {
    params = <String, dynamic>{
      'clientflag': 1,
      'sid': sid.isNotEmpty ? sid : '0',
      'spid': spid.isNotEmpty ? spid : '0',
      if (userid != null && userid.isNotEmpty) 'userid': userid,
    };
  }

  // 构建外层请求体（公共参数 + params）
  // 仅当 params 为 Map 时注入 client 字段；字符串等原始值直接透传（如 getSupplierInfo 传 id）
  if (params is Map<String, dynamic>) {
    params['client'] = 'WEBAPP';
  }
  final Map<String, dynamic> requestData = <String, dynamic>{
    'sid': sid.isNotEmpty ? sid : '0',
    'spid': spid.isNotEmpty ? spid : '0',
    'client': 'WEBAPP',
    'token': token,
    'sign': '83690002',
    'requestId': DateTime.now().millisecondsSinceEpoch,
    'params': params,
  };

  const String baseUrl = HttpApi.baseUrlYlx;
  final String fullUrl = url.startsWith('http') ? url : '$baseUrl$url';

  try {
    final Response<String> response = await DioUtils.instance.dio.post<String>(
      fullUrl,
      data: requestData,
    );
    final String content = response.data.toString();
    final Map<String, dynamic> jsonMap = json.decode(content) as Map<String, dynamic>;

    if (jsonMap.containsKey('retcode')) {
      final dynamic retcode = jsonMap['retcode'];
      final String retmsg = jsonMap['retmsg']?.toString() ?? '请求失败';
      if (retcode == 0) {
        _logApi(fullUrl, params, '接口成功 retcode=0', data: jsonMap['data']);
        return jsonMap;
      }
      if (retcode == -2 || retcode == -3) {
        // 登录信息失效：清除缓存并跳转登录页
        _logApi(fullUrl, params, '接口失败 retcode=$retcode retmsg=$retmsg');
        _handleLoginExpired(retmsg);
        throw _ApiException(jsonMap);
      }
      if (showError && retmsg.isNotEmpty) {
        Toast.show(retmsg);
      }
      _logApi(fullUrl, params, '接口失败 retcode=$retcode retmsg=$retmsg');
      throw _ApiException(jsonMap);
    }
    // 兼容非 retcode 格式（如拦截器包装的 code/message）
    if (jsonMap['code'] == 0) {
      _logApi(fullUrl, params, '接口成功 code=0', data: jsonMap['data']);
      return jsonMap;
    }
    final String msg = jsonMap['message']?.toString() ?? '请求失败';
    if (showError && msg.isNotEmpty) {
      Toast.show(msg);
    }
    _logApi(fullUrl, params, '接口失败 message=$msg');
    throw _ApiException(jsonMap);
  } on _ApiException {
    // 业务异常直接向上抛出（已 Toast）
    rethrow;
  } catch (e) {
    // 网络异常 / DioException —— 始终提取真实错误信息，不论 showError
    String errorMsg = '网络请求异常';
    if (e is DioException) {
      if (e.response?.data != null) {
        try {
          final dynamic respData = e.response!.data;
          final Map<String, dynamic> errMap = respData is String
              ? json.decode(respData) as Map<String, dynamic>
              : (respData as Map<String, dynamic>);
          final dynamic retcode = errMap['retcode'];
          final String? retmsg = errMap['retmsg']?.toString();
          if (retcode == -2 || retcode == -3) {
            _handleLoginExpired(retmsg ?? '登录信息失效，请重新登录');
          }
          if (retmsg != null && retmsg.isNotEmpty) {
            errorMsg = retmsg;
          }
        } catch (_) {}
      } else {
        // 无响应体时（超时/连接拒绝等），根据异常类型显示友好中文提示
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.sendTimeout:
          case DioExceptionType.receiveTimeout:
            errorMsg = '当前没有网络, 请连接网络!';
            break;
          case DioExceptionType.connectionError:
            errorMsg = '当前没有网络, 请连接网络!';
            break;
          default:
            errorMsg = '网络请求异常';
        }
      }
    }
    if (showError) Toast.show(errorMsg);
    _logApi(fullUrl, params, '接口异常: $errorMsg');
    throw _ApiException(<String, dynamic>{'retcode': -1, 'retmsg': errorMsg});
  }
}

/// 强制下线处理：弹窗提示 → 清除缓存 → 跳转登录页
void _handleForceLogout(String retmsg) {
  if (_isRedirectingToLogin) return;
  _isRedirectingToLogin = true;

  final navigatorState = MyApp.navigatorKey.currentState;
  if (navigatorState == null) {
    // navigator 未就绪，降级为直接跳转
    _clearCachePreservingRemember();
    _navigateToLogin();
    return;
  }

  showDialog<void>(
    context: navigatorState.context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('提示'),
      content: Text(retmsg.isNotEmpty ? retmsg : '您已被强制下线，请重新登录'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            _clearCachePreservingRemember();
            _navigateToLogin();
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 登录失效统一处理：清除缓存 + 跳转登录页
/// 注意：保留"记住账号密码"相关数据，不清除
void _handleLoginExpired(String retmsg) {
  if (_isRedirectingToLogin) return;
  _isRedirectingToLogin = true;

  Toast.show(retmsg.isNotEmpty ? retmsg : '登录信息失效，请重新登录');

  _clearCachePreservingRemember();

  // 延迟重置标志，避免快速连续触发
  Future.delayed(const Duration(seconds: 3), () {
    _isRedirectingToLogin = false;
  });

  _navigateToLogin();
}

/// 清除缓存但保留"记住账号密码"相关数据
void _clearCachePreservingRemember() {
  // 字符串类型的记住密码 key
  final rememberKeys = <String, String>{};
  for (final key in [
    Constant.rememberLoginType,
    Constant.rememberPhone,
    Constant.rememberPhonePwd,
    Constant.rememberMerchantCode,
    Constant.rememberMerchantAccount,
    Constant.rememberMerchantPwd,
  ]) {
    final value = SpUtil.getString(key);
    if (value != null && value.isNotEmpty) {
      rememberKeys[key] = value;
    }
  }

  // 布尔类型的记住密码开关（单独处理，避免类型不匹配）
  final bool? rememberPwdEnabled = SpUtil.getBool(Constant.rememberPwdEnabled);

  SpUtil.clear();

  // 恢复字符串类型数据
  rememberKeys.forEach((key, value) {
    SpUtil.putString(key, value);
  });

  // 恢复布尔类型数据
  if (rememberPwdEnabled != null) {
    SpUtil.putBool(Constant.rememberPwdEnabled, rememberPwdEnabled);
  }
}

/// 主动退出登录：清除缓存（保留记住密码）并跳转登录页
void logoutAndRedirect(BuildContext context) {
  _clearCachePreservingRemember();
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    (route) => false,
  );
}

/// 跳转登录页，若 navigator 尚未就绪则延迟重试
void _navigateToLogin([int retryCount = 0]) {
  final navigatorState = MyApp.navigatorKey.currentState;
  if (navigatorState != null) {
    navigatorState.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  } else if (retryCount < 5) {
    // navigator 未就绪，等待下一帧后重试（最多重试 5 次）
    debugPrint('⚠️ _navigateToLogin: navigator 未就绪，第 ${retryCount + 1} 次重试');
    Future.delayed(const Duration(milliseconds: 500), () {
      _navigateToLogin(retryCount + 1);
    });
  } else {
    debugPrint('❌ _navigateToLogin: 重试 $retryCount 次后仍无法跳转登录页');
    _isRedirectingToLogin = false;
  }
}

/// 内部异常类，携带完整接口响应 Map
/// 通过 [response] 可在 .catchError 中获取完整响应数据
class _ApiException implements Exception {
  _ApiException(this.response);
  final Map<String, dynamic> response;

  @override
  String toString() {
    final retmsg = response['retmsg']?.toString() ?? response['message']?.toString();
    return retmsg ?? '接口请求异常';
  }
}
