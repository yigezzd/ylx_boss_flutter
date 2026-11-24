# 灵犀管店 推送功能接入说明

本文档说明「灵犀管店」App 的推送功能设计、接入步骤与后端推送约定。

## 一、目标场景

推送能力服务以下业务场景：

| 场景                | 推送方式             | 示例                                            |
| ------------------- | -------------------- | ----------------------------------------------- |
| 系统公告            | 通知（Notification） | 平台规则变更、版本升级提醒                      |
| 订单/单据状态变更   | 通知 + 自定义消息    | 采购/批发/库存/财务单据审核通过、驳回、状态流转 |
| 库存预警 / 证照到期 | 通知                 | 商品临期、库存不足、积压、供应商证照过期        |
| 单据审批提醒        | 通知                 | 有待审批单据时提醒审批人                        |

- **通知**：展示在系统通知栏，点击后跳转 App 内对应页面。
- **自定义消息**：App 内静默接收（不展示通知栏），用于实时刷新列表、红点等。

## 二、技术方案

采用 **极光推送（JPush）**：

- Flutter 插件：`jpush_flutter 3.5.8`（对应原生 `cn.jiguang.sdk:jpush:6.2.1`）。
- **前台/后台接收**：走极光自有长连接通道。
- **应用被杀进程后接收**：走厂商通道（OPPO / 小米 / 华为 / vivo / 魅族 / 荣耀），需在极光后台配置厂商通道。
- **iOS**：走 APNs。

## 三、代码结构

```
lib/push/
├── push_config.dart    # 配置（AppKey、渠道、别名/标签前缀）
├── push_message.dart   # 消息模型与解析（通知/自定义消息归一化）
├── push_service.dart   # 核心服务：初始化、权限、RegistrationID、别名/标签、事件分发
└── push_router.dart    # 通知点击跳转（route/url/billtypeid → 页面）
```

与既有代码的集成点：

| 文件                                       | 改动                                                    |
| ------------------------------------------ | ------------------------------------------------------- |
| `lib/main.dart`                            | App 启动时 `PushService.instance.init()`                |
| `lib/pages/login/page/login_page.dart`     | 登录成功后 `PushService.instance.bindUser()`            |
| `lib/net/http_helper.dart`                 | 退出登录/登录失效时 `PushService.instance.unbindUser()` |
| `android/app/build.gradle`                 | `manifestPlaceholders`（JPUSH_APPKEY 等）               |
| `android/app/src/main/AndroidManifest.xml` | 通知权限 + 关闭 Flutter 深链接                          |
| `android/app/proguard-rules.pro`           | 极光混淆 keep 规则                                      |

## 四、接入步骤（必做）

### 1. 配置 AppKey

在极光官网 <https://www.jiguang.cn> 创建应用，包名填 `com.boyou.lxboss`（与 `android/app/build.gradle` 中的 `applicationId` 一致），拿到 AppKey 后同步修改两处（**保持一致**）：

1. `lib/push/push_config.dart` 中的 `appKey`
2. `android/app/build.gradle` 中 `manifestPlaceholders` 的 `JPUSH_APPKEY`

> 极光及华为等厂商平台登记的 Android 应用包名必须统一为 `com.boyou.lxboss`。项目中的 `com.weilu.deer` 是当前 Android `namespace` 和原生代码包名，不是平台登记时使用的应用包名；无需为此修改 `namespace` 或原生代码包名。

### 2. 配置厂商通道（应用被杀进程后接收推送）

极光后台 → 设置 → 推送设置 → 厂商通道，按需配置 OPPO / 小米 / 华为 / vivo / 魅族 / 荣耀 的 AppKey、AppId、AppSecret。未配置厂商通道时，应用被系统杀死后可能收不到推送。

### 3. iOS（如需）

- Xcode 中 `TARGETS → Runner → Signing & Capabilities → + Push Notifications`。
- 极光后台配置 APNs 证书（或 token 鉴权）。
- 生产环境时把 `PushConfig.production` 改为 `true`。

### 4. 通知权限

- Android 13+ 需要通知权限，代码已声明 `POST_NOTIFICATIONS`，运行时通过 `PushService.instance.requestNotificationPermission()` 申请。
- 建议在首次进入首页后调用一次；用户拒绝后可调用 `openNotificationSettings()` 引导开启。

## 五、后端推送约定

### 别名 / 标签规则

登录成功后 App 会自动注册：

| 标识  | 值              | 用途                   |
| ----- | --------------- | ---------------------- |
| alias | `user_<userid>` | 按用户精准推送         |
| tag   | `store_<sid>`   | 按门店（商户）批量推送 |

后端推送时：

- 推送给单个用户 → 按 alias `user_<userid>`。
- 推送给某门店全部用户 → 按 tag `store_<sid>`。
- 推送给所有用户 → 广播。

### 通知附加字段（extras）约定

通知/自定义消息可携带 `extras`，App 据此处理跳转与业务：

| 字段         | 说明                                                    |
| ------------ | ------------------------------------------------------- |
| `type`       | 消息类型：`notice` / `bill` / `stock` / `approval`      |
| `route`      | 目标页面路由（优先级最高），如 `/purchase/cgorder/list` |
| `url`        | 网页地址，跳转内置 WebView（用于公告）                  |
| `billtypeid` | 单据类型 id，映射到对应单据列表页                      
| `billtypeid` | 单据类型 id，映射到对应单据列表页 |

`billtypeid` 与路由的映射见 `lib/push/push_router.dart`（与首页审批提醒 `ApprovalReminderHelper` 保持一致）。

点击通知的跳转优先级：`route` > `url` > `billtypeid` > 首页。

## 六、业务侧使用示例

```dart
// 订阅自定义消息（如订单状态变更后刷新列表）
PushService.instance.messageStream.listen((PushMessage msg) {
  if (msg.type == PushMessageType.bill) {
    // 刷新列表逻辑
  }
});

// 获取设备 RegistrationID（用于排查/上报）
final String rid = await PushService.instance.getRegistrationId();

// 申请通知权限
await PushService.instance.requestNotificationPermission();
```

## 七、日志与排查

- 调试日志：`Log.d/Log.e/Log.json`（tag `PUSH`，仅 Debug 环境输出）。
- 操作审计：`FileLogWriter.instance.writeOperationLog`（始终记录，可经「上传日志」功能导出）。
- 极光 SDK 自身日志：`PushService.init()` 中 `debug: !Constant.inProduction`，Debug 包会打印 SDK 详细日志。

排查推送问题时需提供：**RegistrationID、Message ID、AppKey、设备型号与系统版本、SDK 日志**。

## 八、常见问题

1. **收不到推送**：先确认 `appKey` 与后台一致、包名一致、通知权限已开、极光后台创建推送后确实点了「立即发送」（推送记录里有记录才代表已发出）。
2. **应用被杀后收不到**：未配置厂商通道，或厂商通道的 AppKey/AppId 配置错误。
3. **点击通知白屏**：已通过关闭 `flutter_deeplinking_enabled` 处理；若仍白屏，检查 `MainActivity` 的深链接配置。
4. **Release 包收不到**：确认混淆 keep 规则已生效（`proguard-rules.pro`）。
