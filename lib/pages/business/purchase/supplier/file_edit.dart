import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/permission_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sp_util/sp_util.dart';

/// 供应商证照编辑页 —— 对齐 lxAss 项目 supRecord/supFileEdit.vue
///
/// [row] 为空表示新增证照（新增默认有效期 90 天后、status=1 正常）
/// 保存/删除后通过 Navigator.pop 返回结果 Map：
/// `{'action': 'save' | 'delete', 'row': <完整行数据>}`，由父页面更新列表
class SupplierFileEditPage extends StatefulWidget {
  const SupplierFileEditPage({
    super.key,
    this.row,
    this.supid = '',
    this.spid = '',
    this.sid = '',
  });

  /// 待编辑的证照行数据；为空表示新增
  final Map<String, dynamic>? row;

  /// 供应商ID（新增证照时回填 supid 字段）
  final String supid;

  /// 门店ID（store.spid，对齐 lxAss 新增默认值）
  final String spid;

  /// 公司ID（store.id，对齐 lxAss 新增默认值）
  final String sid;

  @override
  State<SupplierFileEditPage> createState() => _SupplierFileEditPageState();
}

class _SupplierFileEditPageState extends State<SupplierFileEditPage>
    with LogPageMixin<SupplierFileEditPage> {
  @override
  String get logPageName => '供应商证照编辑';

  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();

  /// 表单原始数据（对齐 lxAss form 结构，保存时整体回传）
  late Map<String, dynamic> _form;
  bool _uploading = false;

  String _loginOperid = '';
  String _loginOpername = '';

  bool get _isNew => widget.row == null;

  @override
  void initState() {
    super.initState();
    // 当前登录用户（上传证照图片后回填上传人）
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userStr) as Map<String, dynamic>;
        _loginOperid = userMap['userid']?.toString() ?? '';
        _loginOpername = userMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    if (_isNew) {
      // 新增默认值（对齐 lxAss：有效期默认90天后、status=1 正常）
      _form = {
        'id': '',
        'tempkey': 'temp_${DateTime.now().millisecondsSinceEpoch}',
        'spid': widget.spid,
        'sid': widget.sid,
        'supid': widget.supid,
        'documentcode': '',
        'documentname': '',
        'validtime': _fmtDate(DateTime.now().add(const Duration(days: 90))),
        'remark': '',
        'status': 1,
        'fileid': '',
        'filename': '',
        'fileurl': '',
        'filesize': 0,
        'createtime': '',
        'operid': '',
        'opername': '',
      };
    } else {
      _form = Map<String, dynamic>.from(widget.row!);
    }
    _nameCtrl.text = _form['documentname']?.toString() ?? '';
    _codeCtrl.text = _form['documentcode']?.toString() ?? '';
    _remarkCtrl.text = _form['remark']?.toString() ?? '';
    logEnter();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  /// 有效期（YYYY-MM-DD，编辑时后端可能返回完整时间戳，仅取年月日）
  String get _validtime => _fmtValidtime(_form['validtime']);

  /// 格式化日期为 YYYY-MM-DD
  static String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// 兼容日期字符串/完整时间戳，统一输出 YYYY-MM-DD（无法解析时原样返回）
  static String _fmtValidtime(dynamic val) {
    if (val == null) {
      return '';
    }
    final raw = val.toString().trim();
    if (raw.isEmpty) {
      return '';
    }
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      return _fmtDate(dt);
    }
    return raw;
  }

  /// 选择有效期（对齐 lxAss tm-time-picker 仅年月日）
  Future<void> _selectValidtime() async {
    final initial = DateTime.tryParse(_validtime) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _form['validtime'] = _fmtDate(picked);
      });
    }
  }

  /// 选择并上传证照图片（fileUpload 接口，对齐 lxAss chooseImage：最大5M）
  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null || !mounted) {
      return;
    }
    final bytes = await image.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      Toast.show('文件支持最大5M');
      return;
    }
    setState(() => _uploading = true);
    final base64Str = 'data:image/png;base64,${base64Encode(bytes)}';
    request(HttpApi.fileUpload, {'imageBase64': base64Str}).then((result) {
      if (!mounted) {
        return;
      }
      final data = result['data'];
      final imgurl = (data is Map<String, dynamic>)
          ? (data['imgurl']?.toString() ?? '')
          : (data?.toString() ?? '');
      if (imgurl.isEmpty) {
        return;
      }
      setState(() {
        _form['fileurl'] = imgurl;
        _form['filename'] = image.name;
        _form['filesize'] = bytes.length;
        // 上传成功即回填上传时间与上传人（对齐 lxAss chooseImage）
        _form['createtime'] = _fmtDateTime(DateTime.now());
        _form['operid'] = _loginOperid;
        _form['opername'] = _loginOpername;
      });
      Toast.show('上传成功');
    }).catchError((_) {
      if (mounted) {
        Toast.show('上传失败');
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() => _uploading = false);
      }
    });
  }

  static String _fmtDateTime(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
  }

  /// 图片地址兼容处理：完整 URL 直接使用，相对路径拼阿里云前缀（对齐 lxAss getFullUrl/attach_page）
  static String _fullUrl(String fileurl) {
    if (fileurl.isEmpty) {
      return '';
    }
    if (fileurl.startsWith('http')) {
      return fileurl;
    }
    return '${Constant.imageBaseUrl}/$fileurl';
  }

  /// 将输入框内容同步回表单
  Map<String, dynamic> _syncForm() {
    _form['documentname'] = _nameCtrl.text.trim();
    _form['documentcode'] = _codeCtrl.text.trim();
    _form['remark'] = _remarkCtrl.text.trim();
    return _form;
  }

  /// 保存：证照名称必填，其余与 lxAss 一致原样回传
  void _save() {
    if (!PermissionUtils.checkPermission('011104', showTip: false)) {
      Toast.show('你无权编辑供应商，请在后台修改权限');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      Toast.show('请输入证照名称');
      return;
    }
    logSave('保存证照');
    Navigator.pop(context, {'action': 'save', 'row': _syncForm()});
  }

  /// 删除：仅移除父页面列表中的行，最终随供应商保存提交（对齐 lxAss del）
  void _del() {
    if (!PermissionUtils.checkPermission('011103', showTip: false)) {
      Toast.show('你无权删除供应商，请在后台修改权限');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('提示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: const Text('确定删除该证照吗？', style: TextStyle(fontSize: 14, color: Color(0xFF333333))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, {'action': 'delete', 'row': _syncForm()});
              },
              child: const Text('确定', style: TextStyle(color: Color(0xFFD54B5A))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '证照编辑',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Column(
            children: [
              _buildImageRow(),
              _buildInputRow('证照名称', _nameCtrl, required: true),
              _buildInputRow('证照编号', _codeCtrl),
              _buildValidtimeRow(),
              _buildInputRow('备注', _remarkCtrl, maxLines: 3),
              _buildReadonlyRow('上传时间', _form['createtime']?.toString() ?? ''),
              _buildReadonlyRow('上传人', _form['opername']?.toString() ?? ''),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildButton(
                label: '删除',
                isDanger: true,
                onPressed: _del,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildButton(
                label: '保存',
                isPrimary: true,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 证照图片行：点击选择并上传（对齐 lxAss 证照图片 + 右侧箭头）
  Widget _buildImageRow() {
    // 仅展示时拼接完整 URL，_form 中保留后端原始 fileurl（相对路径）
    final fileurl = _fullUrl(_form['fileurl']?.toString() ?? '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 140,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('证照图片', style: TextStyle(fontSize: 13, color: Color(0xFF333333))),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _uploading ? null : _pickAndUpload,
              child: Row(
                children: [
                  _buildImageBox(fileurl),
                  const Spacer(),
                  if (_uploading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF006EFF)),
                    )
                  else
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBox(String fileurl) {
    return Container(
      width: 70,
      height: 70,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: fileurl.isNotEmpty
          ? Image.network(
              fileurl,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildPlaceholder(),
            )
          : _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFF5F5F5),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 32, color: Color(0xFFC0C0C0)),
    );
  }

  /// 有效期选择行
  Widget _buildValidtimeRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _selectValidtime,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 140,
              child: Text('有效期', style: TextStyle(fontSize: 13, color: Color(0xFF333333))),
            ),
            Expanded(
              child: Text(
                _validtime.isEmpty ? '请选择' : _validtime,
                style: TextStyle(
                  fontSize: 14,
                  color: _validtime.isEmpty ? const Color(0xFFC0C0C0) : const Color(0xFF111827),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
  }

  /// 文本输入行（证照名称/证照编号/备注）
  Widget _buildInputRow(
    String label,
    TextEditingController controller, {
    bool required = false,
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  if (required)
                    const Text('* ', style: TextStyle(fontSize: 13, color: Color(0xFFD54B5A))),
                  Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
                ],
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: const InputDecoration(
                hintText: '请输入',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFC0C0C0)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                isDense: true,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  /// 只读行（上传时间/上传人，新增未上传时留空）
  Widget _buildReadonlyRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: value.isEmpty ? const Color(0xFFC0C0C0) : const Color(0xFF999999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
    bool isDanger = false,
  }) {
    final Color bgColor;
    final Color textColor;
    final Color borderColor;
    if (isDanger) {
      bgColor = Colors.white;
      textColor = const Color(0xFFD54B5A);
      borderColor = const Color(0xFFD54B5A);
    } else if (isPrimary) {
      bgColor = const Color(0xFF006EFF);
      textColor = Colors.white;
      borderColor = const Color(0xFF006EFF);
    } else {
      bgColor = Colors.white;
      textColor = const Color(0xFF006EFF);
      borderColor = const Color(0xFF006EFF);
    }

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontSize: 15, color: textColor)),
      ),
    );
  }
}
