import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';

/// 本地运行日志写入工具
///
/// 功能：
/// 1. 异步批量写入日志文件（使用 StreamController 队列，避免高频 IO）
/// 2. 按日期和分类命名：{appDocDir}/log/{yyyy-MM-dd}_{category}.log
/// 3. 分类日志支持：json_writer（运行日志）/ crash_log（操作+接口日志）
/// 4. 单条日志最大 650KB 截断保护
/// 5. 启动时记录设备基础信息（需登录成功后调用，此时商户/账号已存入 SpUtil）
/// 6. 自动清理过期日志（保留天数按月份：1-2月20天，其他10天）
///
/// 操作日志（[writeOperationLog]）与接口日志（[writeErrorLog]）
/// 写入同一分类文件，按时间顺序形成完整的操作审计轨迹。
class FileLogWriter {
  FileLogWriter._();

  static final FileLogWriter instance = FileLogWriter._();

  /// 日志根目录缓存
  String? _logRootPath;

  /// 单条日志最大长度
  static const int _maxLogLength = 650000;

  /// 日志写入队列
  final StreamController<_LogItem> _logController =
      StreamController<_LogItem>.broadcast();

  /// 批量缓冲
  final List<_LogItem> _batchBuffer = [];

  /// 批量写入阈值（最多10条或500ms）
  static const int _batchSize = 10;
  static const Duration _batchTimeout = Duration(milliseconds: 500);

  Timer? _flushTimer;
  bool _initialized = false;

  /// 日志分类
  static const String categoryJsonWriter = 'json_writer';
  static const String categoryCrashLog = 'crash_log';

  /// 保留天数（1-2月20天，其他10天）
  static int get _keepDays {
    final int month = DateTime.now().month;
    return (month == 1 || month == 2) ? 20 : 10;
  }

  // ─────────────── 初始化 ───────────────

  /// 初始化日志系统（在 main.dart 中调用）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Web 平台无文件系统，跳过文件日志初始化
    if (kIsWeb) return;

    // 获取日志根目录
    final dir = await getApplicationDocumentsDirectory();
    _logRootPath = '${dir.path}/log';

    // 启动批量写入监听
    _logController.stream.listen(_onLogItem);

    // 清理过期日志
    deleteOldLogs();
  }

  /// 记录设备基础信息
  ///
  /// 需在登录成功后调用（此时商户号/门店/账号已存入 SpUtil）。
  void logDeviceInfo() {
    if (!_initialized || kIsWeb) return;
    _writeDeviceInfo();
  }

  // ─────────────── 公共写入方法 ───────────────

  /// 写入运行日志
  void writeToFile(dynamic data, {String tag = '描述'}) {
    if (data == null) return;
    String content;
    if (data is String) {
      content = data;
    } else {
      try {
        content = json.encode(data);
      } catch (e) {
        content = 'Serialization Error: $e';
      }
    }
    _enqueue(content, tag, categoryJsonWriter);
  }

  /// 写入用户操作日志
  ///
  /// 记录用户在页面上的关键操作（进入页面、查询、筛选、点击按钮等），
  /// 与接口日志写入同一文件，按时间顺序形成完整的操作审计轨迹。
  ///
  /// [page] 页面名称，如"采购入库列表"；[action] 操作描述，如"进入页面"；
  /// [detail] 可选附加信息，如"第1页"、"单号: CR10012608030001"。
  /// 输出为单行简洁格式：{page} > {action} | {detail}。
  void writeOperationLog(String page, String action, [String? detail]) {
    if (page.isEmpty && action.isEmpty) return;
    final sb = StringBuffer('$page > $action');
    if (detail != null && detail.isNotEmpty) {
      sb.write(' | $detail');
    }
    _enqueue(sb.toString(), '操作', categoryCrashLog);
  }

  /// 写入接口/错误日志
  ///
  /// 所有接口调用的成功与失败都会经此记录，
  /// 包含接口地址 [url]、请求参数 [params]、结果描述 [errorTips] 以及
  /// 可选的响应数据 [data]（内部自动截断，避免日志文件过大）。
  /// 与操作日志写入同一分类文件，按时间顺序形成完整操作轨迹。
  void writeErrorLog(
    dynamic error,
    String url,
    String params,
    String errorTips, {
    dynamic data,
  }) {
    final sb = StringBuffer();
    // 第一行：状态摘要（与 [time] [tag] 前缀拼接后一目了然）
    sb.writeln(errorTips);
    sb.writeln('============================================================');
    if (error != null) {
      sb.writeln(' [异常] $error');
      sb.writeln('------------------------------------------------------------');
    }
    sb.writeln(' URL:    $url');
    sb.writeln(' Params: ${_formatJsonBlock(params)}');
    if (data != null) {
      sb.writeln(' Data:   ${_summarizeData(data)}');
    }
    sb.writeln('============================================================');
    _enqueue(sb.toString(), '接口', categoryCrashLog);
  }

  // ─────────────── 内部实现 ───────────────

  void _enqueue(String data, String tag, String category) {
    if (!_initialized || kIsWeb) return;

    // 长度截断保护
    String processedData = data;
    if (data.length > _maxLogLength) {
      processedData =
          '${data.substring(0, _maxLogLength)}\n...[Truncated, Original total: ${data.length} chars]';
    }

    final time = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());

    _logController.add(_LogItem(
      tag: tag,
      data: processedData,
      time: time,
      category: category,
    ));
  }

  void _onLogItem(_LogItem item) {
    _batchBuffer.add(item);

    // 达到批量阈值立即刷盘
    if (_batchBuffer.length >= _batchSize) {
      _flushTimer?.cancel();
      _flushBatch();
      return;
    }

    // 定时强制刷盘
    _flushTimer?.cancel();
    _flushTimer = Timer(_batchTimeout, _flushBatch);
  }

  void _flushBatch() {
    if (_batchBuffer.isEmpty) return;
    final items = List<_LogItem>.from(_batchBuffer);
    _batchBuffer.clear();

    // 异步写入文件
    _writeBatchToFile(items);
  }

  Future<void> _writeBatchToFile(List<_LogItem> items) async {
    try {
      if (_logRootPath == null) return;

      // 按分类分组写入
      final Map<String, List<_LogItem>> grouped = {};
      for (final item in items) {
        grouped.putIfAbsent(item.category, () => []).add(item);
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      for (final entry in grouped.entries) {
        final category = entry.key;
        final categoryItems = entry.value;

        // 扁平化目录结构：log/{date}_{category}.log
        final filePath = '$_logRootPath/${dateStr}_$category.log';
        final file = File(filePath);
        // 确保父目录存在
        final dir = Directory(_logRootPath!);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        final sb = StringBuffer();
        for (final item in categoryItems) {
          // 格式：[{time}] [{tag}] {data}
          sb.write('[');
          sb.write(item.time);
          sb.write('] [');
          sb.write(item.tag);
          sb.write('] ');
          sb.write(item.data);
          sb.write('\n');
        }

        await file.writeAsString(sb.toString(),
            mode: FileMode.append, flush: true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FileLogWriter write error: $e');
      }
    }
  }

  /// 记录设备基础信息
  void _writeDeviceInfo() {
    // 从 store 中读取商户号/门店编码/门店名称
    String merchantId = '';
    String storeId = '';
    String storeName = '';
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        final Map<String, dynamic> storeMap =
            jsonDecode(storeStr) as Map<String, dynamic>;
        merchantId = storeMap['account']?.toString() ?? '';
        storeId = storeMap['id']?.toString() ?? '';
        storeName = storeMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    // 从 user 中读取登录账号
    String userName = '';
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        userName = userMap['name']?.toString() ?? '';
      }
    } catch (_) {}

    final sb = StringBuffer('\n');
    sb.writeln('---------初始化信息---------');
    sb.writeln('商户号: $merchantId');
    sb.writeln('门店编码: $storeId');
    sb.writeln('门店名称: $storeName');
    sb.writeln('登录账号: $userName');
    sb.writeln(
        '平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    writeToFile(sb.toString(), tag: '设备信息');
  }

  // ─────────────── 日志清理 ───────────────

  /// 删除过期日志文件
  ///
  /// 扫描日志目录下的所有 .log 和 .zip 文件，
  /// 根据文件名前缀日期判断是否过期并删除。
  void deleteOldLogs() {
    if (_logRootPath == null) return;
    try {
      final logDir = Directory(_logRootPath!);
      if (!logDir.existsSync()) return;

      final now = DateTime.now();
      final keepDays = _keepDays;
      final dateFormat = DateFormat('yyyy-MM-dd');

      final entities = logDir.listSync();
      for (final entity in entities) {
        if (entity is! File) continue;
        // 删除残留的 zip 文件
        if (entity.path.endsWith('.zip')) {
          try {
            entity.deleteSync();
          } catch (_) {}
          continue;
        }
        // 文件名格式：yyyy-MM-dd_category.log
        final fileName = entity.path.split(Platform.pathSeparator).last;
        final datePart = fileName.length >= 10 ? fileName.substring(0, 10) : '';
        try {
          final fileDate = dateFormat.parse(datePart);
          if (fileDate.isBefore(now.subtract(Duration(days: keepDays - 1)))) {
            entity.deleteSync();
          }
        } catch (_) {
          // 文件名前缀不是合法日期，跳过
        }
      }
    } catch (_) {}
  }

  /// 获取日志根目录路径（供上传模块使用）
  String? get logRootPath => _logRootPath;

  // ─────────────── 工具方法 ───────────────

  /// 响应数据摘要（避免日志文件过大，截断为前 300 字符）
  String _summarizeData(dynamic data) {
    if (data == null) return '';
    String content;
    try {
      content = json.encode(data);
    } catch (_) {
      return '';
    }
    const int maxLen = 300;
    if (content.length > maxLen) {
      return '${content.substring(0, maxLen)}...[Truncated]';
    }
    return content;
  }

  /// 格式化 JSON 字符串为缩进后的多行文本块
  ///
  /// 如果 [jsonStr] 是合法 JSON，返回带换行和缩进的格式化文本；
  /// 否则原样返回。
  String _formatJsonBlock(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr);
      final formatted = const JsonEncoder.withIndent('  ').convert(decoded);
      // 缩进所有行（第一行前加空格对齐 label）
      final lines = formatted.split('\n');
      return lines.join('\n  ');
    } catch (_) {
      return jsonStr;
    }
  }
}

/// 全局路由观察者：自动记录页面进入（操作审计）
///
/// 在 MaterialApp.navigatorObservers 中注册后，
/// 所有通过 Navigator.push 进入的页面（含业务模块页面）都会自动记录
/// "页面导航 > 进入页面" 操作日志，与接口日志一起形成完整操作轨迹。
///
/// 路由名优先取 [RouteSettings.name]（fluro 路由路径或业务模块名），
/// 无 name 时以路由类型名兜底。
class LogRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  LogRouteObserver._();

  static final LogRouteObserver instance = LogRouteObserver._();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute<dynamic>) {
      FileLogWriter.instance.writeOperationLog('页面导航', '进入页面', _routeName(route));
    }
  }

  static String _routeName(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    return route.runtimeType.toString();
  }
}

/// 页面操作日志混入（操作审计）
///
/// 为业务页面提供统一的操作审计日志能力，接入方式：
/// ```dart
/// class _XxxPageState extends State<XxxPage> with LogPageMixin<XxxPage> {
///   @override
///   String get logPageName => '采购订货列表';
/// }
/// ```
/// 然后在进入页面、查询、筛选、新增、保存等操作点调用对应方法即可。
mixin LogPageMixin<T extends StatefulWidget> on State<T> {
  /// 页面名称（如"采购订货列表"），子类必须提供
  String get logPageName;

  /// 记录进入页面（initState 中调用）
  void logEnter() => FileLogWriter.instance.writeOperationLog(logPageName, '进入页面');

  /// 记录查询列表（_loadData 中调用，记录页码便于追踪翻页）
  void logQuery([int page = 1]) =>
      FileLogWriter.instance.writeOperationLog(logPageName, '查询列表', '第$page页');

  /// 记录搜索（关键字查询）
  void logSearch([String? keyword]) =>
      FileLogWriter.instance.writeOperationLog(logPageName, '搜索', keyword);

  /// 记录打开筛选
  void logOpenFilter() => FileLogWriter.instance.writeOperationLog(logPageName, '打开筛选');

  /// 记录应用筛选（传入非默认条件，多个条件用空格分隔；空列表记录为重置筛选）
  void logApplyFilter(List<String> conditions) {
    FileLogWriter.instance.writeOperationLog(
      logPageName,
      conditions.isEmpty ? '重置筛选' : '应用筛选',
      conditions.isEmpty ? null : conditions.join(' '),
    );
  }

  /// 记录点击新增
  void logAdd() => FileLogWriter.instance.writeOperationLog(logPageName, '点击新增');

  /// 记录查看详情（[detail] 为单号/编码/名称等标识，可为空）
  void logView([String? detail]) =>
      FileLogWriter.instance.writeOperationLog(logPageName, '查看详情', detail);

  /// 记录保存/提交（[action] 可传"保存""审核"等，默认"保存"）
  void logSave([String? action]) =>
      FileLogWriter.instance.writeOperationLog(logPageName, action ?? '保存');
}

/// 日志条目
class _LogItem {
  final String tag;
  final String data;
  final String time;
  final String category;

  _LogItem({
    required this.tag,
    required this.data,
    required this.time,
    required this.category,
  });
}
