import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:oktoast/oktoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'package:flutter_deer/util/voice_recognition_util.dart';

/// 语音识别弹窗
///
/// 底部弹出，支持录音 -> 阿里云 NLS 实时识别 -> 文本解析 -> 返回结果
class VoiceRecognitionDialog extends StatefulWidget {
  const VoiceRecognitionDialog({super.key});

  /// 显示语音识别弹窗并返回解析结果
  static Future<List<Map<String, dynamic>>?> show(BuildContext context) {
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceRecognitionDialog(),
    );
  }

  @override
  State<VoiceRecognitionDialog> createState() => _VoiceRecognitionDialogState();
}

class _VoiceRecognitionDialogState extends State<VoiceRecognitionDialog>
    with SingleTickerProviderStateMixin {
  final VoiceRecognitionUtil _recognizer = VoiceRecognitionUtil();
  final AudioRecorder _recorder = AudioRecorder();

  late AnimationController _animController;
  late Animation<double> _pulseAnimation;

  bool _isRecording = false;
  bool _isConnecting = false;
  String _currentText = '';
  String _finalText = '';
  String _errorMsg = '';
  int _selectedFormat = 2; // 默认格式：品名+数量+单位

  StreamSubscription<List<int>>? _recordSub;
  Timer? _silenceTimer; // 静音检测定时器（与 boss 端对齐）

  static const List<String> _formatLabels = [
    '品名+数量+单位+单价',
    '品名+数量+单位+金额',
    '品名+数量+单位（默认）',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _recognizer.onResult = (text) {
      if (mounted) {
        setState(() {
          _currentText = text;
          _errorMsg = '';
        });
        _resetSilenceTimer(); // 每次收到新结果重置静音计时
      }
    };
    _recognizer.onCompleted = (text) {
      if (mounted) {
        setState(() {
          _finalText = text;
          _currentText = text;
          _isConnecting = false;
        });
        _cancelSilenceTimer();
      }
    };
    _recognizer.onError = (error) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isRecording = false;
          _errorMsg = error;
        });
        _cancelSilenceTimer();
        _animController.stop();
        _animController.reset();
      }
    };
  }

  @override
  void dispose() {
    _cancelSilenceTimer();
    _stopRecording();
    _recognizer.dispose();
    _recorder.dispose();
    _animController.dispose();
    _recordSub?.cancel();
    super.dispose();
  }

  /// 重置静音检测定时器（1.5秒无新结果自动停止，与 boss 端 1.2s 对齐）
  void _resetSilenceTimer() {
    _cancelSilenceTimer();
    _silenceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_isRecording && mounted) {
        debugPrint('[Voice] 检测到静音，自动停止识别');
        _stopRecording();
      }
    });
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  // =================== 录音控制 ===================

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    // 请求权限
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      showToast('需要麦克风权限才能使用语音识别');
      return;
    }

    setState(() {
      _isConnecting = true;
      _currentText = '';
      _finalText = '';
    });

    try {
      // 获取 token 并建立 WebSocket 连接
      final token = await VoiceRecognitionUtil.getToken();
      await _recognizer.startRecognition(token);

      // 开始录音 (16000Hz, PCM, 单声道)
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );

      final stream = await _recorder.startStream(config);
      _recordSub = stream.listen((List<int> data) {
        _recognizer.sendAudioData(Uint8List.fromList(data));
      });

      setState(() {
        _isRecording = true;
        _isConnecting = false;
      });
      _animController.repeat(reverse: true);
    } catch (e) {
      setState(() => _isConnecting = false);
      showToast('启动录音失败: $e');
    }
  }

  Future<void> _stopRecording() async {
    _cancelSilenceTimer();
    try {
      await _recordSub?.cancel();
      _recordSub = null;
      await _recorder.stop();
      await _recognizer.stopRecognition();
    } catch (_) {}

    if (mounted) {
      setState(() => _isRecording = false);
      _animController.stop();
      _animController.reset();
    }
  }

  // =================== 确认按钮 ===================

  void _onConfirm() {
    final text = _finalText.isNotEmpty ? _finalText : _currentText;
    if (text.trim().isEmpty) {
      showToast('请先录音或等待识别完成');
      return;
    }

    final result = parseVoiceText(text, _selectedFormat);
    if (result.isEmpty) {
      showToast('未能解析出有效商品信息，请重试');
      return;
    }

    Navigator.pop(context, result);
  }

  // =================== Build ===================

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部标题栏
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // 麦克风区域
          _buildMicArea(),
          // 识别文本区域
          _buildTextDisplay(),
          // 格式选择
          _buildFormatSelector(),
          // 确认按钮
          _buildConfirmButton(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '语音录入',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.close, size: 22, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _buildMicArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          GestureDetector(
            onTap: _isConnecting ? null : _toggleRecording,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isRecording ? _pulseAnimation.value : 1.0,
                  child: child,
                );
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? const Color(0xFF006EFF).withValues(alpha: 0.12)
                      : const Color(0xFFF3F4F6),
                ),
                child: Icon(
                  Icons.mic,
                  size: 40,
                  color: _isRecording
                      ? const Color(0xFF006EFF)
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isConnecting
                ? '正在连接...'
                : _isRecording
                    ? '正在聆听...'
                    : '点击开始录音',
            style: TextStyle(
              fontSize: 14,
              color: _isRecording
                  ? const Color(0xFF006EFF)
                  : const Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextDisplay() {
    final displayText = _currentText.isNotEmpty
        ? _currentText
        : (_finalText.isNotEmpty ? _finalText : '');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 60, maxHeight: 120),
      decoration: BoxDecoration(
        color: _errorMsg.isNotEmpty ? const Color(0xFFFFF7ED) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _errorMsg.isNotEmpty ? const Color(0xFFFDBA74) : const Color(0xFFE5E7EB)),
      ),
      child: _errorMsg.isNotEmpty
          ? SingleChildScrollView(
              child: Text(
                '识别错误: $_errorMsg',
                style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626), height: 1.5),
              ),
            )
          : displayText.isEmpty
              ? const Center(
                  child: Text('识别文本将在此显示', style: TextStyle(fontSize: 13, color: Color(0xFFD1D5DB))),
                )
              : SingleChildScrollView(
                  child: Text(
                    displayText,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF111827), height: 1.5),
                  ),
                ),
    );
  }

  Widget _buildFormatSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('识别格式：', style: TextStyle(fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          ...List.generate(_formatLabels.length, (index) {
            return RadioListTile<int>(
              value: index,
              groupValue: _selectedFormat,
              onChanged: (val) => setState(() => _selectedFormat = val!),
              title: Text(
                _formatLabels[index],
                style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              activeColor: const Color(0xFF006EFF),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF006EFF),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('确认添加', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// =================== 文本解析 ===================

/// 中文数字转阿拉伯数字
String _chineseToArabic(String text) {
  const cnNums = {'零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10, '百': 100, '千': 1000};
  final buffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    if (cnNums.containsKey(char)) {
      // 简单处理：将中文数字字符替换为对应阿拉伯数字
      if (char == '十') {
        buffer.write('10');
      } else if (char == '百') {
        buffer.write('100');
      } else if (char == '千') {
        buffer.write('1000');
      } else if (char == '两') {
        buffer.write('2');
      } else {
        buffer.write(cnNums[char]);
      }
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

/// 解析语音识别文本为商品列表
///
/// [text] 识别文本
/// [format] 格式: 0=品名+数量+单位+单价, 1=品名+数量+单位+金额, 2=品名+数量+单位
/// 返回 List<Map>，每项含 name, quantity, unit, price(可选)
List<Map<String, dynamic>> parseVoiceText(String text, int format) {
  if (text.trim().isEmpty) return [];

  // 先做中文数字转换
  text = _chineseToArabic(text);

  // 按中英文逗号分割
  final segments = text.split(RegExp(r'[,，]'));
  final results = <Map<String, dynamic>>[];

  // 常见单位列表
  const units = r'(?:斤|个|箱|件|袋|瓶|包|盒|kg|g|只|条|支|桶|罐|台|套|双|把|根|张|块|粒|颗|片|杯|壶|盘|碗|杯|份|本|册|卷|捆|扎|束|对|副|组|批|打|车|船|架|艘|辆|匹|头)';

  for (final segment in segments) {
    final s = segment.trim();
    if (s.isEmpty) continue;

    Map<String, dynamic>? item;

    switch (format) {
      case 0: // 品名+数量+单位+单价
        final re = RegExp('(.+?)(\\d+\\.?\\d*)($units).*?每.*?(\\d+\\.?\\d*)元?');
        final match = re.firstMatch(s);
        if (match != null) {
          item = {
            'name': match.group(1)!.trim(),
            'quantity': double.tryParse(match.group(2)!) ?? 1,
            'unit': match.group(3)!.trim(),
            'price': double.tryParse(match.group(4)!) ?? 0,
          };
        }
        break;
      case 1: // 品名+数量+单位+金额
        final re = RegExp('(.+?)(\\d+\\.?\\d*)($units).*?共.*?(\\d+\\.?\\d*)元?');
        final match = re.firstMatch(s);
        if (match != null) {
          final qty = double.tryParse(match.group(2)!) ?? 1;
          final amt = double.tryParse(match.group(4)!) ?? 0;
          item = {
            'name': match.group(1)!.trim(),
            'quantity': qty,
            'unit': match.group(3)!.trim(),
            'price': qty > 0 ? amt / qty : amt,
          };
        }
        break;
      case 2: // 品名+数量+单位（默认）
      default:
        final re = RegExp('(.+?)(\\d+\\.?\\d*)($units)');
        final match = re.firstMatch(s);
        if (match != null) {
          item = {
            'name': match.group(1)!.trim(),
            'quantity': double.tryParse(match.group(2)!) ?? 1,
            'unit': match.group(3)!.trim(),
          };
        }
        break;
    }

    if (item != null && (item['name'] as String).isNotEmpty) {
      results.add(item);
    }
  }

  return results;
}
