import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flustars_flutter3/flustars_flutter3.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/version_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// APP 版本更新弹窗
///
/// 展示新版本信息、更新说明，支持下载进度显示。
class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.newVersion,
    required this.updateDesc,
    required this.downloadUrl,
    this.forceUpdate = false,
    this.updateTime = '',
    this.cname = '',
  });
  
  /// 新版本号，如 "1.4.0"
  final String newVersion;
  
  /// 更新说明，多行文本
  final String updateDesc;
  
  /// APK 下载地址（Android 使用）
  final String downloadUrl;
  
  /// 是否强制更新（true 时不显示"稍后提醒"按钮，禁止关闭弹窗）
  final bool forceUpdate;
  
  /// 更新时间，如 "2026-06-30 10:09:10"
  final String updateTime;
  
  /// 应用名称
  final String cname;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  final CancelToken _cancelToken = CancelToken();
  bool _isDownloading = false;
  double _progress = 0;

  @override
  void dispose() {
    if (!_cancelToken.isCancelled && _progress < 1) {
      _cancelToken.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forceUpdate && !_isDownloading,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 顶部渐变区域 ──
                _buildHeader(),
                // ── 内容区域 ──
                _buildContent(),
                // ── 操作按钮 ──
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 28, bottom: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF006EFF), Color(0xFF0047B3)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.system_update_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '发现新版本',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'v${widget.newVersion}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 应用名称 + 更新时间
          if (widget.cname.isNotEmpty || widget.updateTime.isNotEmpty) ...[
            Row(
              children: [
                if (widget.cname.isNotEmpty) ...[
                  const Icon(
                    Icons.apps,
                    size: 16,
                    color: Color(0xFF006EFF),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.cname,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF333333),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (widget.updateTime.isNotEmpty) ...[
                  if (widget.cname.isNotEmpty) const SizedBox(width: 8),
                  Text(
                    widget.updateTime,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            '更新说明',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE8ECF0)),
            ),
            child: SingleChildScrollView(
              child: Text(
                widget.updateDesc,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                  height: 1.6,
                ),
              ),
            ),
          ),
          if (_isDownloading) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: const Color(0xFFE8ECF0),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF006EFF),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF006EFF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          if (!widget.forceUpdate && !_isDownloading) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(
                      color: const Color(0xFFCCCCCC),
                    ),
                  ),
                  child: const Text(
                    '稍后提醒',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF999999),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: GestureDetector(
              onTap: _isDownloading ? null : _handleUpdate,
              child: Container(
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _isDownloading
                      ? const Color(0xFFCCCCCC)
                      : const Color(0xFF006EFF),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Text(
                  _isDownloading ? '下载中...' : '立即更新',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleUpdate() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      Navigator.of(context).pop();
      VersionUtils.jumpAppStore();
    } else if (kIsWeb) {
      // Web 平台：直接在新标签页打开下载地址，浏览器会自动触发下载
      Navigator.of(context).pop();
      launchUrl(
        Uri.parse(widget.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
    } else {
      setState(() {
        _isDownloading = true;
      });
      _downloadApk();
    }
  }

  /// 下载 APK 并安装
  Future<void> _downloadApk() async {
    try {
      setInitDir(initStorageDir: true);
      await DirectoryUtil.getInstance();
      DirectoryUtil.createStorageDirSync(category: 'Download');
      final String path = DirectoryUtil.getStoragePath(
        fileName: 'ylx_boss',
        category: 'Download',
        format: 'apk',
      ) ?? '';
      final File file = File(path);

      await Dio().download(
        widget.downloadUrl,
        file.path,
        cancelToken: _cancelToken,
        onReceiveProgress: (int count, int total) {
          if (total > 0) {
            setState(() {
              _progress = count / total;
            });
            if (count == total) {
              Navigator.of(context).pop();
              VersionUtils.install(path);
            }
          }
        },
      );
    } catch (e) {
      if (!_cancelToken.isCancelled) {
        Toast.show('下载失败，请稍后重试');
        debugPrint('APK下载异常: $e');
        setState(() {
          _isDownloading = false;
          _progress = 0;
        });
      }
    }
  }
}
