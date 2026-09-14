import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/dio_utils.dart';
import 'package:flutter_deer/net/intercept.dart';
import 'package:flutter_deer/pages/home/home_page.dart';
import 'package:flutter_deer/pages/login/page/login_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/not_found_page.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/setting/provider/theme_provider.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/handle_error_utils.dart';
import 'package:flutter_deer/util/log_utils.dart';
import 'package:flutter_deer/util/theme_utils.dart';
import 'package:flutter_deer/util/version_check_utils.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:oktoast/oktoast.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:url_strategy/url_strategy.dart';

Future<void> main() async {
//  debugProfileBuildsEnabled = true;
//  debugPaintLayerBordersEnabled = true;
//  debugProfilePaintsEnabled = true;
//  debugRepaintRainbowEnabled = true;
  if (Constant.inProduction) {
    /// Release环境时不打印debugPrint内容
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  /// 异常处理
  handleError(() async {
    /// 确保初始化完成
    WidgetsFlutterBinding.ensureInitialized();

    /// 去除URL中的“#”(hash)，仅针对Web。默认为setHashUrlStrategy
    /// 注意本地部署和远程部署时`web/index.html`中的base标签，https://github.com/flutter/flutter/issues/69760
    setPathUrlStrategy();

    /// sp初始化
    await SpUtil.getInstance();

    /// 日志系统初始化（记录接口操作日志，供“上传日志”功能使用）
    await FileLogWriter.instance.init();

    /// 操作审计：App 启动（后续登录/进入首页的轨迹均从此刻开始）
    FileLogWriter.instance.writeOperationLog('App', '启动');

    /// 1.22 预览功能: 在输入频率与显示刷新率不匹配情况下提供平滑的滚动效果
    // GestureBinding.instance?.resamplingEnabled = true;
    runApp(MyApp());
  });

  /// 显示状态栏和导航栏（启动页如需全屏可单独处理）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);

  /// 状态栏图标/文字设为深色，避免白色背景上看不到
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  // TODO(weilu): 启动体验不佳。状态栏、导航栏在冷启动开始的一瞬间为黑色，且无法通过隐藏、修改颜色等方式进行处理。。。
  // 相关问题跟踪：https://github.com/flutter/flutter/issues/73351
}

class MyApp extends StatelessWidget {
  MyApp({super.key, this.home, this.theme}) {
    Log.init();
    initDio();
    Routes.initRoutes();
    VersionCheckUtils.setNavigatorKey(navigatorKey);
  }

  final Widget? home;
  final ThemeData? theme;
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey();

  void initDio() {
    final List<Interceptor> interceptors = <Interceptor>[];

    /// 统一添加身份验证请求头
    interceptors.add(AuthInterceptor());

    /// 刷新Token
    interceptors.add(TokenInterceptor());

    /// 打印Log(生产模式去除)
    if (!Constant.inProduction) {
      interceptors.add(LoggingInterceptor());
    }

    /// 适配数据(根据自己的数据结构，可自行选择添加)
    interceptors.add(AdapterInterceptor());
    configDio(
      baseUrl: 'https://api.github.com/',
      interceptors: interceptors,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget app = MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, ThemeProvider provider, __) {
          return _buildMaterialApp(provider);
        },
      ),
    );

    /// Toast 配置
    return OKToast(
        backgroundColor: Colors.black54,
        textPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        radius: 20.0,
        child: app);
  }

  /// 检查登录状态：token 和商户信息都存在才视为已登录
  static bool _checkLoginState() {
    final token = SpUtil.getString(Constant.token) ?? '';
    if (token.isEmpty) return false;

    // 检查商户信息（store）是否存在且有效
    try {
      final storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isEmpty) return false;
      final storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
      // store 对象需要有有效的 id
      final storeId = storeMap['id'];
      if (storeId == null || storeId == 0 || storeId == '0') return false;
    } catch (_) {
      return false;
    }

    return true;
  }

  Widget _buildMaterialApp(ThemeProvider provider) {
    return MaterialApp(
      title: '灵犀管店',
      // showPerformanceOverlay: true, //显示性能标签
      debugShowCheckedModeBanner: false, // 去除右上角debug的标签
      // checkerboardRasterCacheImages: true,
      // showSemanticsDebugger: true, // 显示语义视图
      // checkerboardOffscreenLayers: true, // 检查离屏渲染

      theme: theme ?? provider.getTheme(),
      darkTheme: provider.getTheme(isDarkMode: true),
      themeMode: provider.getThemeMode(),
      home: home ?? (_checkLoginState() ? const HomePage() : const LoginPage()),
      onGenerateRoute: Routes.router.generator,
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
      ],
      navigatorKey: navigatorKey,
      navigatorObservers: [LogRouteObserver.instance],
      builder: (BuildContext context, Widget? child) {
        /// 保证文字大小不受手机系统设置影响 https://www.kikt.top/posts/flutter/layout/dynamic-text/
        /// AnnotatedRegion 保证每帧都应用深色状态栏图标（无 AppBar 的页面也生效）
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: ThemeUtils.dark,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
            child: child!,
          ),
        );
      },

      /// 因为使用了fluro，这里设置主要针对Web
      onUnknownRoute: (_) {
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const NotFoundPage(),
        );
      },
      restorationScopeId: 'app',
    );
  }
}
