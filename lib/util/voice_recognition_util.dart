import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 阿里云 NLS 实时语音识别工具类
///
/// 使用 WebSocket 协议与阿里云 NLS 网关通信，
/// 支持流式发送 PCM 音频数据并获取实时/最终识别结果。
class VoiceRecognitionUtil {
  static const String _wsUrl = 'wss://nls-gateway.cn-shanghai.aliyuncs.com/ws/v1';
  static const String _appKey = 'QYd2qTabwi5r6lnM';

  // 阿里云 AccessKey（与 Vue 端一致）
  static const String _accessKeyId = 'LTAI5tGGdy73N1DF9NPnDv1F';
  static const String _accessKeySecret = 'yWMleUU8Rcxos41AImZNwaoochZheZ';
  static const String _nlsMetaUrl = 'https://nls-meta.cn-shanghai.aliyuncs.com';

  // Token 缓存
  static String? _cachedToken;
  static int? _cachedExpireTime; // 毫秒时间戳

  WebSocketChannel? _channel;
  String? _taskId;
  bool _isStarted = false;

  /// 中间识别结果回调
  void Function(String text)? onResult;

  /// 最终识别结果回调
  void Function(String text)? onCompleted;

  /// 错误回调
  void Function(String error)? onError;

  /// 连接已建立回调
  VoidCallback? onConnected;

  /// 连接已关闭回调
  VoidCallback? onDisconnected;

  /// 获取 NLS Token
  ///
  /// 直接调用阿里云 NLS Meta API（与 Vue 端 token.js 逻辑一致），
  /// 使用 HMAC-SHA1 签名鉴权，支持 Token 缓存（过期前自动刷新）。
  static Future<String> getToken() async {
    // 1. 检查缓存是否有效
    if (_cachedToken != null && _cachedExpireTime != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      // 提前 60 秒刷新，避免临界过期
      if (now < _cachedExpireTime! - 60000) {
        debugPrint('NLS Token 缓存命中，剩余 ${((_cachedExpireTime! - now) / 1000).toStringAsFixed(0)}s');
        return _cachedToken!;
      }
      debugPrint('NLS Token 已过期，重新获取');
    }

    try {
      // 2. 构建签名参数（按字母排序）
      final String nonce = _generateUUID();
      final String timestamp = _utcTimestamp();
      final Map<String, String> params = <String, String>{
        'AccessKeyId': _accessKeyId,
        'Action': 'CreateToken',
        'Format': 'JSON',
        'RegionId': 'cn-shanghai',
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureNonce': nonce,
        'SignatureVersion': '1.0',
        'Timestamp': timestamp,
        'Version': '2019-02-28',
      };

      // 3. 构造规范化查询字符串（按 key 字母排序）
      final sortedKeys = params.keys.toList()..sort();
      final normalizedParts = <String>[];
      for (final key in sortedKeys) {
        normalizedParts.add('${Uri.encodeComponent(key)}=${Uri.encodeComponent(params[key]!)}');
      }
      final normalizedQuery = normalizedParts.join('&');

      // 4. 构造待签名字符串: GET&%2F&<encodedQuery>
      final stringToSign = 'GET&${Uri.encodeComponent('/')}&${Uri.encodeComponent(normalizedQuery)}';

      // 5. HMAC-SHA1 签名（key 需要加 &）
      final hmacKey = utf8.encode('$_accessKeySecret&');
      final hmacSha1 = Hmac(sha1, hmacKey);
      final digest = hmacSha1.convert(utf8.encode(stringToSign));
      final signature = base64.encode(digest.bytes);

      // 6. 拼装最终 URL
      final finalQuery = 'Signature=${Uri.encodeComponent(signature)}&$normalizedQuery';
      final requestUrl = '$_nlsMetaUrl/?$finalQuery';

      debugPrint('NLS Token 请求 URL: $requestUrl');

      // 7. 发起 GET 请求
      final dio = Dio();
      final response = await dio.get<Map<String, dynamic>>(
        requestUrl,
        options: Options(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final data = response.data;
      if (data == null) {
        debugPrint('NLS Token 响应为空');
        return '';
      }

      debugPrint('NLS Token 响应: $data');

      // 8. 解析 Token: { Token: { Id: "xxx", ExpireTime: 1234567890 } }
      final tokenObj = data['Token'] as Map<String, dynamic>?;
      if (tokenObj == null) {
        debugPrint('NLS Token 响应中无 Token 字段: $data');
        return '';
      }

      final tokenId = tokenObj['Id']?.toString() ?? '';
      final expireTime = tokenObj['ExpireTime'];

      if (tokenId.isEmpty) {
        debugPrint('NLS Token Id 为空');
        return '';
      }

      // 9. 缓存 Token（ExpireTime 是秒级时间戳，转为毫秒）
      _cachedToken = tokenId;
      if (expireTime is num) {
        _cachedExpireTime = (expireTime * 1000).toInt();
      } else {
        // 兜底：1小时后过期
        _cachedExpireTime = DateTime.now().millisecondsSinceEpoch + 3600000;
      }

      debugPrint('NLS Token 获取成功: ${tokenId.substring(0, 8)}...');
      return tokenId;
    } catch (e) {
      debugPrint('获取 NLS Token 失败: $e');
      return '';
    }
  }

  /// UTC 时间戳格式化为 ISO 字符串（与 Vue 端 utctimestamp 一致）
  static String _utcTimestamp() {
    final now = DateTime.now().toUtc();
    String pad(int n) => n < 10 ? '0$n' : n.toString();
    return '${now.year}-${pad(now.month)}-${pad(now.day)}T${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}Z';
  }

  /// 开始识别
  ///
  /// 建立 WebSocket 连接并发送 StartRecognition 指令。
  /// [token] 为阿里云 NLS 鉴权 token。
  Future<void> startRecognition(String token) async {
    if (_isStarted) return;

    // Token 为空时直接报错，避免无效连接
    if (token.isEmpty) {
      onError?.call('语音识别服务未配置：Token 为空，请联系管理员配置 NLS 服务');
      return;
    }

    _taskId = _generateUUID();
    final messageId = _generateUUID();

    try {
      final uri = Uri.parse('$_wsUrl?token=$token');
      _channel = WebSocketChannel.connect(uri);

      // 等待连接建立（ready future），设置超时保护
      await _channel!.ready.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('WebSocket 连接超时，请检查网络');
        },
      );

      _channel!.stream.listen(
        _onMessage,
        onError: (Object error) {
          onError?.call('WebSocket 错误: $error');
          _cleanup();
        },
        onDone: () {
          onDisconnected?.call();
          _cleanup();
        },
      );

      final startMsg = {
        'header': {
          'message_id': messageId,
          'task_id': _taskId,
          'namespace': 'SpeechRecognizer',
          'name': 'StartRecognition',
          'appkey': _appKey,
        },
        'payload': {
          'format': 'pcm',
          'sample_rate': 16000,
          'enable_intermediate_result': true,
          'enable_punctuation_prediction': true,
          'enable_inverse_text_normalization': true,
          'enable_voice_detection': true,
          'max_end_silence': 2000,
        },
      };

      _channel!.sink.add(jsonEncode(startMsg));
      _isStarted = true;
      onConnected?.call();
    } on TimeoutException catch (e) {
      onError?.call('连接超时: $e');
      _cleanup();
    } catch (e) {
      onError?.call('连接失败: $e');
      _cleanup();
    }
  }

  /// 发送音频数据
  void sendAudioData(Uint8List data) {
    if (!_isStarted || _channel == null) return;
    try {
      _channel!.sink.add(data);
    } catch (e) {
      onError?.call('发送音频数据失败: $e');
    }
  }

  /// 停止识别
  Future<void> stopRecognition() async {
    if (!_isStarted || _channel == null) return;

    final messageId = _generateUUID();
    final stopMsg = {
      'header': {
        'message_id': messageId,
        'task_id': _taskId,
        'namespace': 'SpeechRecognizer',
        'name': 'StopRecognition',
        'appkey': _appKey,
      },
    };

    try {
      _channel!.sink.add(jsonEncode(stopMsg));
    } catch (e) {
      onError?.call('停止识别失败: $e');
    }

    _isStarted = false;
    // 等待服务端返回最终结果后再关闭
    await Future<void>.delayed(const Duration(seconds: 2));
    await _closeChannel();
  }

  /// 释放资源
  Future<void> dispose() async {
    _isStarted = false;
    await _closeChannel();
    onResult = null;
    onCompleted = null;
    onError = null;
    onConnected = null;
    onDisconnected = null;
  }

  // =================== 私有方法 ===================

  void _onMessage(dynamic message) {
    if (message is String) {
      try {
        final data = jsonDecode(message) as Map<String, dynamic>;
        final header = data['header'] as Map<String, dynamic>?;
        if (header == null) return;

        final name = header['name']?.toString() ?? '';
        final status = header['status'] ?? 0;

        switch (name) {
          case 'RecognitionStarted':
            // 识别已开始
            break;
          case 'RecognitionResultChanged':
            // 中间结果
            final payload = data['payload'] as Map<String, dynamic>?;
            final result = payload?['result']?.toString() ?? '';
            if (result.isNotEmpty) {
              onResult?.call(result);
            }
            break;
          case 'RecognitionCompleted':
            // 最终结果
            final payload = data['payload'] as Map<String, dynamic>?;
            final result = payload?['result']?.toString() ?? '';
            onCompleted?.call(result);
            break;
          case 'TaskFailed':
            final statusText = header['status_text']?.toString() ?? '未知错误';
            onError?.call('识别失败: $statusText (status=$status)');
            break;
        }
      } catch (e) {
        onError?.call('解析消息失败: $e');
      }
    }
  }

  void _cleanup() {
    _isStarted = false;
    _channel = null;
    _taskId = null;
  }

  Future<void> _closeChannel() async {
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _cleanup();
  }

  /// 生成符合 RFC 4122 v4 的随机 UUID（与 boss 端 uuid.js 对齐）
  static String _generateUUID() {
    final Random rng = Random.secure();
    const hexDigits = '0123456789abcdef';
    final List<String> s = List<String>.filled(36, '');
    for (int i = 0; i < 36; i++) {
      s[i] = hexDigits[rng.nextInt(16)];
    }
    s[14] = '4'; // version 4
    s[19] = hexDigits[(int.tryParse(s[19], radix: 16)! & 0x3) | 0x8]; // variant
    s[8] = s[13] = s[18] = s[23] = '-';
    return s.join();
  }
}
