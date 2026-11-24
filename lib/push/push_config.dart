/// 极光推送（JPush）配置
///
/// 接入前请先在极光官网 https://www.jiguang.cn 完成：
/// 1. 注册/登录极光开发者账号，创建「应用」；
/// 2. 应用包名填写 `com.boyou.lxboss`（必须与 android/app/build.gradle 的 applicationId 一致）；
/// 3. 将获取到的 AppKey 填入下方 [appKey]；
/// 4. 需要「应用被杀进程后仍可接收推送」时，在极光后台「设置 → 推送设置 → 厂商通道」
///    逐一配置 OPPO / 小米 / 华为 / vivo / 魅族 / 荣耀 的 AppKey、AppId 等。
class PushConfig {
  PushConfig._();

  /// 极光 AppKey（与极光后台「灵犀智店」应用一致）
  static const String appKey = '0052165d4ce3194b134d2e58';

  /// 渠道名，用于推送统计（与 demo 保持一致）
  static const String channel = 'default_developer';

  /// iOS 生产环境开关：true = 生产环境（AppStore 分发），false = 开发环境（沙箱）
  static const bool production = false;

  /// 别名前缀：alias = user_<userid>，用于按用户精准推送
  static const String userAliasPrefix = 'user_';

  /// 标签前缀：tag = store_<sid>，用于按商户（门店）批量推送
  static const String storeTagPrefix = 'store_';
}
