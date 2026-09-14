import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:intl/intl.dart';
import 'package:sp_util/sp_util.dart';

/// 日志压缩上传工具
///
/// 功能：
/// 1. 收集本地日志文件（最近 N 天）
/// 2. 打包压缩为 zip
/// 3. 通过 FTP 上传到远程服务器
/// 4. 上传完成后删除本地 zip
///
/// FTP 服务器信息：
/// - 地址：yundb.bypos.net:15671
/// - 账号：yunpos / yunpos83690002
/// - 远程目录：YunPosDB/ANDROID/LXGD_LX/
class LogUploadUtils {
  LogUploadUtils._();

  // ─────────────── FTP 配置───────────────

  static const String _ftpHost = 'yundb.bypos.net';
  static const int _ftpPort = 15671;
  static const String _ftpUser = 'yunpos';
  static const String _ftpPass = 'yunpos83690002';
  static const String _ftpRemoteDir = 'YunPosDB/ANDROID/LXGD_LX/';

  /// 客户端标识（灵犀管店使用 BOSS_APP）
  static const String _client = 'BOSS_APP';

  /// 保留天数（1-2月20天，其他10天）
  static int get _keepDays {
    final int month = DateTime.now().month;
    return (month == 1 || month == 2) ? 20 : 10;
  }

  // ─────────────── 上传入口 ───────────────

  /// 上传日志
  ///
  /// 返回 "1" 表示成功，其他为失败原因。
  /// [onProgress] 用于回调上传各阶段进度（如压缩中 / 连接FTP / 上传中）。
  static Future<String> uploadLog({void Function(String msg)? onProgress}) async {
    try {
      final logRootPath = FileLogWriter.instance.logRootPath;
      if (logRootPath == null) return '日志目录未初始化';

      final date = DateFormat('yyyy_MMdd_HHmmss').format(DateTime.now());
      // 从 store 中读取商户号/门店编码（对齐 smdcapp SpUtils）
      String acc = '';
      String storeCode = '';
      try {
        final String storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          final Map<String, dynamic> storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
          acc = storeMap['account']?.toString() ?? '';
          storeCode = storeMap['id']?.toString() ?? '';
        }
      } catch (_) {}

      // 压缩包文件名（{date}_{CLIENT}_{acc}_{storeCode}_logs.zip）
      final zipFileName = '${date}_${_client}_${acc}_${storeCode}_logs.zip';
      final zipFilePath = '$logRootPath/$zipFileName';

      // 1. 收集待压缩的日志文件（最近 N 天）
      final filesToZip = <FileSystemEntity>[];
      final logDir = Directory(logRootPath);
      if (!logDir.existsSync()) return '日志目录不存在';

      final now = DateTime.now();
      final dateFormat = DateFormat('yyyy-MM-dd');
      final targetDates = <String>{};
      for (int i = 0; i < _keepDays; i++) {
        targetDates.add(dateFormat.format(now.subtract(Duration(days: i))));
      }

      final entities = logDir.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.log')) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          // 文件名格式：yyyy-MM-dd_category.log，取前10位日期部分
          final datePart = fileName.length >= 10 ? fileName.substring(0, 10) : '';
          if (targetDates.contains(datePart)) {
            filesToZip.add(entity);
          }
        }
      }

      if (filesToZip.isEmpty) return '没有日志';

      // 2. 压缩为 zip
      onProgress?.call('正在压缩日志...');
      FileLogWriter.instance.writeToFile('开始压缩日志，文件数: ${filesToZip.length}', tag: '日志上传');
      await _zipFiles(filesToZip, zipFilePath);
      FileLogWriter.instance.writeToFile('压缩完成: $zipFilePath', tag: '日志上传');

      // 3. FTP 上传
      onProgress?.call('正在连接FTP服务器...');
      final result = await _ftpUpload(logRootPath, zipFileName);
      FileLogWriter.instance.writeToFile('FTP上传结果: $result', tag: '日志上传');

      // 4. 删除本地 zip（对齐 smdcapp delFile）
      try {
        final zipFile = File(zipFilePath);
        if (zipFile.existsSync()) {
          zipFile.deleteSync();
        }
      } catch (_) {}

      return result;
    } catch (e) {
      FileLogWriter.instance.writeToFile('日志上传异常: $e', tag: '日志上传');
      return '上传异常: $e';
    }
  }

  // ─────────────── Zip 压缩 ───────────────

  /// 将多个日志文件压缩为一个 zip 文件
  static Future<void> _zipFiles(List<FileSystemEntity> files, String zipPath) async {
    final archive = Archive();

    for (final entity in files) {
      if (entity is File) {
        final bytes = entity.readAsBytesSync();
        final fileName = entity.path.split(Platform.pathSeparator).last;
        // 在 zip 中统一放在 log/ 目录下，保持简洁
        archive.addFile(ArchiveFile('log/$fileName', bytes.length, bytes));
      }
    }

    // 编码为 zip 字节
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) return;
    final file = File(zipPath);
    await file.writeAsBytes(zipData, flush: true);
  }

  // ─────────────── FTP 上传（dart:io Socket 实现）───────────────

  /// FTP 上传文件
  ///
  /// 使用 FTP 被动模式（PASV），二进制传输
  /// 返回 "1" 成功，其他为错误信息
  static Future<String> _ftpUpload(String filePath, String fileName) async {
    Socket? cmdSocket;
    Socket? dataSocket;
    StreamIterator<Uint8List>? cmdReader;
    try {
      // 1. 连接 FTP 服务器（手动解析 DNS 并优先 IPv4，规避部分模拟器 IPv6 路由不通的问题）
      final addresses = await InternetAddress.lookup(_ftpHost);
      final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4).toList();
      final targetAddr = ipv4.isNotEmpty ? ipv4.first : addresses.first;
      FileLogWriter.instance.writeToFile(
          'FTP解析 $_ftpHost → [${addresses.map((a) => a.address).join(', ')}]，选用 ${targetAddr.address}',
          tag: '日志上传');
      cmdSocket = await Socket.connect(targetAddr, _ftpPort, timeout: const Duration(seconds: 15));
      FileLogWriter.instance.writeToFile(
          'FTP控制连接已建立: ${cmdSocket.remoteAddress.address}:${cmdSocket.remotePort}',
          tag: '日志上传');
      // 控制连接使用单一订阅迭代器读取，避免对 Socket（单订阅流）重复 listen 报错
      cmdReader = StreamIterator<Uint8List>(cmdSocket);

      String response = await _readFtpResponse(cmdReader);
      if (!response.startsWith('220')) return 'FTP连接失败: $response';

      // 2. 登录
      cmdSocket.write('USER $_ftpUser\r\n');
      await cmdSocket.flush();
      response = await _readFtpResponse(cmdReader);
      if (!response.startsWith('331')) return 'FTP用户名错误: $response';

      cmdSocket.write('PASS $_ftpPass\r\n');
      await cmdSocket.flush();
      response = await _readFtpResponse(cmdReader);
      if (!response.startsWith('230')) return 'FTP密码错误: $response';

      // 3. 设置二进制模式
      cmdSocket.write('TYPE I\r\n');
      await cmdSocket.flush();
      response = await _readFtpResponse(cmdReader);
      if (!response.startsWith('200')) {
        return 'FTP设置二进制模式失败: $response';
      }

      // 4. 切换远程目录
      cmdSocket.write('CWD $_ftpRemoteDir\r\n');
      await cmdSocket.flush();
      response = await _readFtpResponse(cmdReader);
      if (!response.startsWith('250')) return 'FTP切换目录失败: $response';

      // 5. 进入被动模式（PASV）
      cmdSocket.write('PASV\r\n');
      await cmdSocket.flush();
      response = await _readFtpResponse(cmdReader);
      if (!response.startsWith('227')) return 'FTP PASV失败: $response';

      // 解析 PASV 响应中的 IP 和端口
      final pasvMatch = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)').firstMatch(response);
      if (pasvMatch == null) return 'FTP PASV解析失败: $response';

      final dataHostRaw =
          '${pasvMatch.group(1)}.${pasvMatch.group(2)}.${pasvMatch.group(3)}.${pasvMatch.group(4)}';
      final dataPort = int.parse(pasvMatch.group(5)!) * 256 + int.parse(pasvMatch.group(6)!);
      // 对齐 Apache Commons Net FTPClient 的 passive NAT workaround（NatServerResolver）：
      // 服务器在 NAT 后时 PASV 会返回内网地址（如 172.18.x.x / 192.168.x.x / 10.x.x.x），
      // 外网客户端无法直连，此时回退使用控制连接的公网地址（commons-net 默认行为）。
      final dataHost =
          _isPrivateAddress(dataHostRaw) ? cmdSocket.remoteAddress.address : dataHostRaw;
      FileLogWriter.instance.writeToFile(
          'PASV返回 $dataHostRaw:$dataPort，私有地址=${_isPrivateAddress(dataHostRaw)}，数据连接目标 $dataHost:$dataPort',
          tag: '日志上传');

      // 6. 连接数据通道
      dataSocket = await Socket.connect(dataHost, dataPort, timeout: const Duration(seconds: 15));

      // 7. 发送 STOR 命令
      cmdSocket.write('STOR $fileName\r\n');
      await cmdSocket.flush();
      response = await _readFtpResponse(cmdReader);
      if (!response.startsWith('150') && !response.startsWith('125')) {
        return 'FTP STOR失败: $response';
      }

      // 8. 传输文件数据
      final file = File('$filePath/$fileName');
      final fileBytes = await file.readAsBytes();
      dataSocket.add(fileBytes);
      await dataSocket.flush();
      await dataSocket.close();

      // 9. 等待传输完成确认
      response = await _readFtpResponse(cmdReader);
      if (!response.startsWith('226')) return 'FTP传输未完成: $response';

      // 10. 退出
      cmdSocket.write('QUIT\r\n');
      await cmdSocket.flush();

      return '1'; // 上传成功
    } catch (e) {
      return 'FTP异常: $e';
    } finally {
      try {
        await cmdReader?.cancel();
      } catch (_) {}
      try {
        dataSocket?.destroy();
        cmdSocket?.destroy();
      } catch (_) {}
    }
  }

  /// 读取一条 FTP 响应（支持多行响应，基于单一订阅迭代器）
  ///
  /// FTP 响应格式：单行 "NNN text\r\n"；多行 "NNN-...\r\n...NNN text\r\n"。
  /// 以 "NNN "（3位数字+空格）开头的行标志整条响应结束。
  /// 10 秒内无数据则返回已累积内容（可能为空，由调用方判定失败）。
  static Future<String> _readFtpResponse(StreamIterator<Uint8List> reader) async {
    final buffer = StringBuffer();
    while (true) {
      final bool hasMore;
      try {
        hasMore = await reader.moveNext().timeout(const Duration(seconds: 10));
      } on TimeoutException {
        break; // 10 秒内无数据
      }
      if (!hasMore) break; // 流已结束
      buffer.write(String.fromCharCodes(reader.current));
      if (_isCompleteFtpResponse(buffer.toString())) {
        break;
      }
    }
    return buffer.toString().trim();
  }

  /// 判断 IP 是否为私有/内网地址（对齐 commons-net NatServerResolver 的
  /// isSiteLocalAddress / isLoopbackAddress / isLinkLocalAddress / isAnyLocalAddress 判断）
  static bool _isPrivateAddress(String ip) {
    if (ip == '0.0.0.0') return true;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    // 10.0.0.0/8
    if (a == 10) return true;
    // 172.16.0.0/12（172.16.x.x ~ 172.31.x.x）
    if (a == 172 && b >= 16 && b <= 31) return true;
    // 192.168.0.0/16
    if (a == 192 && b == 168) return true;
    // 127.0.0.0/8 loopback
    if (a == 127) return true;
    // 169.254.0.0/16 link-local
    if (a == 169 && b == 254) return true;
    return false;
  }

  /// 判断缓冲区中是否已包含一条完整的 FTP 响应
  static bool _isCompleteFtpResponse(String str) {
    if (!str.contains('\r\n')) return false;
    final lines = str.split('\r\n');
    for (final line in lines) {
      if (line.length >= 4 && line[3] == ' ') {
        return true;
      }
    }
    return false;
  }
}
