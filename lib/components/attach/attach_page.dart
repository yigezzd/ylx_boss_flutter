import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 附件管理页面 —— 对齐 boss 项目 comPages/attach.vue
///
/// 支持图片上传、预览、删除，最多 9 张，单张不超过 5MB。
/// 返回时通过 Navigator.pop(context, _fileList) 回传更新后的附件列表。
class AttachPage extends StatefulWidget {
  /// 已有附件列表
  final List<Map<String, dynamic>> fileLists;

  /// 菜单 ID（如 050201=采购订货）
  final String menuid;

  /// 单据 ID（编辑模式才有）
  final String billid;

  /// 单据编号
  final String billno;

  const AttachPage({
    super.key,
    required this.fileLists,
    required this.menuid,
    this.billid = '',
    this.billno = '',
  });

  /// 便捷入口：返回更新后的 fileLists（可能为 null 表示未修改）
  static Future<List<Map<String, dynamic>>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> fileLists,
    required String menuid,
    String billid = '',
    String billno = '',
  }) async {
    return Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => AttachPage(
          fileLists: fileLists,
          menuid: menuid,
          billid: billid,
          billno: billno,
        ),
      ),
    );
  }

  @override
  State<AttachPage> createState() => _AttachPageState();
}

class _AttachPageState extends State<AttachPage> {
  static const int _maxCount = 9;
  static const int _maxSize = 5 * 1024 * 1024; // 5MB

  late List<Map<String, dynamic>> _fileList;
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _fileList = List<Map<String, dynamic>>.from(
      widget.fileLists.map((e) => Map<String, dynamic>.from(e)),
    );
  }

  int get _remainCount => _maxCount - _fileList.length;

  // =================== 图片选择 & 上传 ===================
  Future<void> _chooseImage() async {
    if (_remainCount <= 0) {
      Toast.show('最多上传$_maxCount张图片');
      return;
    }
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null || !mounted) return;

    final bytes = await image.readAsBytes();
    if (bytes.length > _maxSize) {
      Toast.show('图片超过5MB限制');
      return;
    }

    setState(() => _uploading = true);
    final base64Str = 'data:image/png;base64,${base64Encode(bytes)}';
    final params = {
      'fileurlBase64': base64Str,
      'menuid': widget.menuid,
      'billid': widget.billid,
      'billno': widget.billno,
      'filename': image.name,
    };

    request(HttpApi.fillupByAttachFile, params).then((result) {
      if (!mounted) return;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        final DateTime now = DateTime.now();
        setState(() {
          _fileList.add({
            'filename': _val(data, 'filename', image.name),
            'fileurl': _val(data, 'fileurl', data['url']?.toString() ?? ''),
            'filesize': data['filesize'] ?? bytes.length,
            'createtime': _val(data, 'createtime', _formatDateTime(now)),
            'validtime': _val(data, 'validtime', _formatDate(now.add(const Duration(days: 90)))),
            'menuid': _val(data, 'menuid', widget.menuid),
            'billid': _val(data, 'billid', widget.billid),
            'billno': _val(data, 'billno', widget.billno),
            'id': data['id'],
            'fileid': data['fileid'],
            'saveflag': 1,
            'status': 1,
          });
        });
        Toast.show('上传成功');
      }
    }).catchError((_) {
      if (mounted) Toast.show('上传失败');
    }).whenComplete(() {
      if (mounted) setState(() => _uploading = false);
    });
  }

  // =================== 删除附件 ===================
  Future<void> _removeFile(int index) async {
    final row = _fileList[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定删除该附件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final id = row['id'];
    final fileid = row['fileid'];
    if (id != null || fileid != null) {
      // 已保存到服务端的附件，调用删除接口
      request(HttpApi.delFileList, {
        'isArray': true,
        'param': [
          {...row, 'menuid': widget.menuid},
        ],
      }).then((_) {
        if (!mounted) return;
        setState(() => _fileList.removeAt(index));
        Toast.show('删除成功');
      }).catchError((_) {
        if (mounted) Toast.show('删除失败');
      });
    } else {
      // 未保存的本地附件，直接移除
      setState(() => _fileList.removeAt(index));
    }
  }

  // =================== 同步附件列表到后端 ===================
  /// 取字段值，空字符串回退到 fallback（对齐 lxAss `res.xxx || 默认值`）
  static String _val(Map<String, dynamic> data, String key, String fallback) {
    final v = data[key]?.toString() ?? '';
    return v.isNotEmpty ? v : fallback;
  }

  /// 明细统一补充 saveflag/status = 1（对齐 lxAss syncBillFile）
  List<Map<String, dynamic>> _withSaveFlag() {
    return _fileList
        .map((item) => {...item, 'saveflag': 1, 'status': 1})
        .toList();
  }

  /// YYYY-MM-DD
  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// YYYY-MM-DD HH:mm:ss
  static String _formatDateTime(DateTime dt) {
    return '${_formatDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  void _syncBillFile() {
    if (widget.billid.isEmpty) return;
    request(HttpApi.updateBillFile, {
      'fileLists': _withSaveFlag(),
      'menuid': widget.menuid,
      'billid': widget.billid,
      'billno': widget.billno,
    }).catchError((_) => <String, dynamic>{});
  }

  // =================== 判断是否为图片 ===================
  static bool _isImageFile(Map<String, dynamic> item) {
    final name =
        (item['filename']?.toString() ?? item['fileurl']?.toString() ?? '')
            .split('?')
            .first
            .toLowerCase();
    return RegExp(r'\.(jpe?g|png|gif|bmp|webp)$', caseSensitive: false)
        .hasMatch(name);
  }

  static String _getFullUrl(String fileurl) {
    if (fileurl.isEmpty) return '';
    if (fileurl.startsWith('http')) return fileurl;
    return '${Constant.imageBaseUrl}/$fileurl';
  }

  // =================== 图片预览 ===================
  void _previewImage(int index) {
    final imageUrls = <String>[];
    int currentIndex = 0;
    int imgIdx = 0;
    for (int i = 0; i < _fileList.length; i++) {
      if (_isImageFile(_fileList[i])) {
        imageUrls.add(_getFullUrl(_fileList[i]['fileurl']?.toString() ?? ''));
        if (i == index) currentIndex = imgIdx;
        imgIdx++;
      }
    }
    if (imageUrls.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _ImagePreviewPage(
          urls: imageUrls,
          initialIndex: currentIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Color(0xFF374151)),
          onPressed: () {
            _syncBillFile();
            Navigator.pop(context, _withSaveFlag());
          },
        ),
        title: const Text('附件',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827))),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- 附件网格 ----
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (int i = 0; i < _fileList.length; i++)
                    _buildAttachItem(i),
                  if (_fileList.length < _maxCount) _buildAddButton(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ---- 说明 ----
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('说明',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333))),
                  const SizedBox(height: 8),
                  _infoText('1. 仅支持上传图片，格式：jpg、jpeg、png'),
                  _infoText('2. 单张图片大小不超过5MB'),
                  _infoText('3. 最多上传$_maxCount张图片'),
                  _infoText('4. 附件有效期：默认90天，过期后自动清除'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
    );
  }

  Widget _buildAttachItem(int index) {
    final item = _fileList[index];
    final isImage = _isImageFile(item);
    final fileurl = item['fileurl']?.toString() ?? '';
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 内容区域
          GestureDetector(
            onTap: () => isImage ? _previewImage(index) : _onFileTap(item),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E5E5)),
              ),
              child: isImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _getFullUrl(fileurl),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        cacheHeight: 200,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image,
                              size: 32, color: Color(0xFFCCCCCC)),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.insert_drive_file,
                            size: 36, color: Color(0xFF999999)),
                        const SizedBox(height: 4),
                        Text(
                          _getFileName(item),
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF666666)),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),
          ),
          // 删除按钮
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: () => _removeFile(index),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cancel,
                    size: 20, color: Color(0xFF333333)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _uploading ? null : _chooseImage,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          border: Border.all(
              color: const Color(0xFFCCCCCC),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside),
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFFFAFAFA),
        ),
        child: _uploading
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF006EFF)),
                ),
              )
            : Stack(
                children: [
                  const Center(
                    child: Icon(Icons.add, size: 36, color: Color(0xFF999999)),
                  ),
                  if (_remainCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAAD14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '$_remainCount',
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  static String _getFileName(Map<String, dynamic> item) {
    final raw = item['filename']?.toString() ?? '';
    if (raw.isNotEmpty) {
      if (raw.length > 12) {
        return '${raw.substring(0, 5)}...${raw.substring(raw.length - 5)}';
      }
      return raw;
    }
    final url = item['fileurl']?.toString() ?? '';
    final urlName = url.isNotEmpty ? url.split('/').last : '未知文件';
    if (urlName.length > 12) {
      return '${urlName.substring(0, 5)}...${urlName.substring(urlName.length - 5)}';
    }
    return urlName;
  }

  void _onFileTap(Map<String, dynamic> item) {
    final name = _getFileName(item);
    Toast.show('文件：$name\n暂不支持打开此类型文件');
  }
}

// =================== 图片预览页面 ===================
class _ImagePreviewPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _ImagePreviewPage({
    required this.urls,
    this.initialIndex = 0,
  });

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          '${_currentIndex + 1} / ${widget.urls.length}',
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image,
                    size: 64, color: Colors.white54),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
