import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/res/resources.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/other_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_scroll_view.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sp_util/sp_util.dart';

/// design/1注册登录/index.html
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 定义controller
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _nodeText1 = FocusNode();
  final FocusNode _nodeText2 = FocusNode();
  final FocusNode _nodeText3 = FocusNode();
  final TextEditingController _codeController = TextEditingController();

  bool _clickable = false;
  bool _isLoading = false;
  bool _isShowPwd = false;
  bool _isShowDelete = false;
  bool _agreed = true;
  bool _rememberPwd = true;
  int _loginType = 0; // 0: 手机号登录, 1: 商户号登录
  String _appVersion = '';

  // 是否为开发环境
  bool get _isDev => HttpApi.baseUrlYlx.contains('dev.bypos.net');

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      /// 显示状态栏和导航栏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    });
    // 先添加监听器，确保后续恢复凭证时能触发 _verify
    _nameController.addListener(_verify);
    _passwordController.addListener(_verify);
    _codeController.addListener(_verify);
    // 恢复记住密码相关状态和凭证
    final savedLoginType = SpUtil.getString(Constant.rememberLoginType);
    _loginType = (savedLoginType != null && savedLoginType.isNotEmpty)
        ? int.tryParse(savedLoginType) ?? 0
        : 0;
    _rememberPwd = SpUtil.getBool(Constant.rememberPwdEnabled) ?? false;
    _restoreCredentials();
    _updateDeleteVisibility();

    // 操作审计：进入登录页
    FileLogWriter.instance.writeOperationLog('登录页', '进入页面');
  }

  @override
  void dispose() {
    _nameController.removeListener(_verify);
    _passwordController.removeListener(_verify);
    _codeController.removeListener(_verify);
    _nameController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _nodeText1.dispose();
    _nodeText2.dispose();
    _nodeText3.dispose();
    super.dispose();
  }

  void _updateDeleteVisibility() {
    final bool show = _nameController.text.isNotEmpty;
    if (show != _isShowDelete) {
      setState(() {
        _isShowDelete = show;
      });
    }
  }

  void _verify() {
    _updateDeleteVisibility();
    final String name = _nameController.text;
    final String password = _passwordController.text;
    bool clickable = true;
    if (_loginType == 0) {
      if (name.isEmpty || name.length < 11) {
        clickable = false;
      }
    } else {
      if (name.isEmpty) {
        clickable = false;
      }
      final String code = _codeController.text;
      if (code.isEmpty) {
        clickable = false;
      }
    }
    if (password.isEmpty) {
      clickable = false;
    }

    if (clickable != _clickable) {
      setState(() {
        _clickable = clickable;
      });
    }
  }

  void _login() {
    if (!_agreed) {
      Toast.show('请阅读并勾选服务协议与隐私政策！');
      return;
    }
    // 操作审计：发起登录（不记录密码等敏感信息）
    FileLogWriter.instance.writeOperationLog(
      '登录页',
      '发起登录',
      _loginType == 0 ? '手机号登录' : '商户号登录',
    );
    setState(() => _isLoading = true);
    _getLoginList().then((stores) {
      if (stores.length > 1) {
        // 需要用户选择门店：先结束按钮加载态，
        // 避免弹窗展示期间及用户返回取消后登录按钮一直转圈；
        // 用户选中门店后由 _doLogin 重新进入加载态
        if (mounted) setState(() => _isLoading = false);
        _showStoreSelectionDialog(stores);
      } else if (stores.length == 1) {
        _doLogin(stores[0] as Map<String, dynamic>);
      } else {
        _doLogin(null);
      }
    }).catchError((_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  /// 第一步：获取门店列表
  Future<List<dynamic>> _getLoginList() async {
    final String pwdMd5 = md5.convert(utf8.encode(_passwordController.text)).toString();
    final Map<String, dynamic> params;
    if (_loginType == 0) {
      params = {'phone': _nameController.text, 'pwd': pwdMd5, 'logintype': '1'};
    } else {
      params = {
        'account': _nameController.text,
        'code': _codeController.text,
        'pwd': pwdMd5,
        'logintype': '2'
      };
    }
    final result = await request(HttpApi.getLoginList, params);
    // 兼容两种格式：data 包裹 或 顶层直接为列表
    if (result['data'] is List) {
      return result['data'] as List<dynamic>;
    }
    return [];
  }

  /// 第二步：执行登录
  void _doLogin(Map<String, dynamic>? storeItem) {
    // 从门店选择弹窗选中门店后重新进入加载态；
    // 单门店/无门店直登时保持 _login 中已有的加载态
    if (mounted) setState(() => _isLoading = true);
    final String pwdMd5 = md5.convert(utf8.encode(_passwordController.text)).toString();
    final Map<String, dynamic> params;
    if (_loginType == 0) {
      params = {'phone': _nameController.text, 'pwd': pwdMd5, 'logintype': '1'};
    } else {
      params = {
        'account': _nameController.text,
        'code': _codeController.text,
        'pwd': pwdMd5,
        'logintype': '2'
      };
    }
    if (storeItem != null) {
      params['loginuuid'] = storeItem['loginuuid'] ?? '';
    }
    request(HttpApi.lxlogin, params).then((result) {
      // 兼容两种响应格式（data 包裹 / 扁平结构）
      final raw = result['data'];
      final Map<String, dynamic> data = raw is Map ? Map<String, dynamic>.from(raw) : result;
      SpUtil.putString(Constant.token, data['token']?.toString() ?? '');
      SpUtil.putString(Constant.user, json.encode(data['user'] ?? {}));
      SpUtil.putString(Constant.store, json.encode(data['store'] ?? {}));
      SpUtil.putString(Constant.rolemap, json.encode(data['rolemap'] ?? {}));
      SpUtil.putString(Constant.sysStoreAccount, json.encode(data['sysStoreAccount'] ?? {}));
      SpUtil.putString(Constant.allLoginData, json.encode(data));
      SpUtil.putString(Constant.accessToken, data['token']?.toString() ?? '');
      // loginParamResp 在 data 内部
      final loginParamResp = data['loginParamResp'];
      if (loginParamResp != null && loginParamResp is Map) {
        // 与 boss 项目对齐：将嵌套的子对象属性扁平化到顶层
        // 例: { "moduleA": { "dynamicsCodeFlushTime": 60 } } => { "dynamicsCodeFlushTime": 60 }
        final flat = Map<String, dynamic>.from(loginParamResp);
        final keysToRemove = <String>[];
        final extras = <String, dynamic>{};
        for (final entry in flat.entries) {
          if (entry.value is Map) {
            final sub = Map<String, dynamic>.from(entry.value as Map);
            extras.addAll(sub);
            keysToRemove.add(entry.key);
          }
        }
        for (final key in keysToRemove) {
          flat.remove(key);
        }
        flat.addAll(extras);
        SpUtil.putString(Constant.loginParamResp, json.encode(flat));
      }
      if (mounted) {
        // 操作审计：登录成功（记录账号，不记录密码）
        FileLogWriter.instance.writeOperationLog(
          '登录页',
          '登录成功',
          '账号: ${_nameController.text}',
        );
        // 登录成功后，根据记住密码开关保存或清除凭证
        _saveOrClearCredentials();
        // 登录成功后记录设备基础信息（对齐 smdcapp LoginActivity: JsonWriter.initLogInfo）
        FileLogWriter.instance.logDeviceInfo();
        Toast.show('登录成功');
        NavigatorUtils.push(context, Routes.home, clearStack: true);
      }
    }).catchError((e) {
      debugPrint('登录异常: $e');
    }).whenComplete(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  /// 显示门店选择弹窗
  void _showStoreSelectionDialog(List<dynamic> stores) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          constraints: const BoxConstraints(maxHeight: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14.0,
                    color: Color(0xFF4688FA),
                  ),
                  children: [
                    const TextSpan(text: '当前账号，关联 '),
                    TextSpan(
                      text: '${stores.length} 个门店',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: '，请选择'),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: stores.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFEEEEEE), indent: 54),
                  itemBuilder: (context, index) {
                    final store = stores[index];
                    final account = store['account']?.toString() ?? '';
                    final storeName = store['storename']?.toString() ?? '';
                    final userName = store['username']?.toString() ?? '';
                    final code = store['code']?.toString() ?? '';
                    final usercode = store['usercode']?.toString() ?? '';
                    final primaryText = account.isNotEmpty && storeName.isNotEmpty
                        ? '$account - $storeName'
                        : account.isNotEmpty
                            ? account
                            : storeName;
                    final rolePart = usercode.isNotEmpty ? '$usercode - $userName' : userName;
                    final secondaryText = code.isNotEmpty ? '[ $code ] $rolePart' : rolePart;
                    return InkWell(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _doLogin(store as Map<String, dynamic>);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Row(
                          children: [
                            // 蓝色圆形图标
                            Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4688FA),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.store_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            // 文本区域
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    primaryText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  if (secondaryText.isNotEmpty) ...[
                                    const SizedBox(height: 3.0),
                                    Text(
                                      secondaryText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.0,
                                        color: Color(0xFF999999),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // 右箭头
                            const Icon(
                              Icons.chevron_right,
                              color: Color(0xFFCCCCCC),
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: NetworkImage(
              'http://byyoupic.oss-cn-shenzhen.aliyuncs.com/bycloud/zm/null/pro_436a135b19fdffe73d99700926a89b45.png',
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: MyScrollView(
                  keyboardConfig:
                      Utils.getKeyboardActionsConfig(context, <FocusNode>[_nodeText1, _nodeText2]),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  children: _buildBody,
                ),
              ),
              // 版本号固定在页面底部
              _buildVersionInfo(),
              const SizedBox(height: 16.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    if (!_isDev) {
      return const SizedBox(height: 8.0);
    }
    return Container(
      height: 44.0,
      alignment: Alignment.center,
      child: const Text(
        '开发版',
        style: TextStyle(
          fontSize: 16.0,
          color: Color(0xFFFF4444),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Widget> get _buildBody => <Widget>[
        const SizedBox(height: 28.0),
        // 品牌标题区域 - 水平+垂直居中
        Container(
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '灵犀管店',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32.0,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                  letterSpacing: 2.0,
                ),
              ),
              SizedBox(height: 8.0),
              Text(
                '欢迎使用，您的掌上管家！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18.0,
                  color: Color(0xFF555555),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28.0),
        // 白色登录卡片
        _buildLoginCard(),
        const SizedBox(height: 24.0),
      ];

  /// 白色登录卡片（Tab + 表单 + 记住密码 + 协议 + 登录按鈕）
  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFEAEAEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLoginTypeTabs(),
          const SizedBox(height: 8.0),
          _buildFormCard(),
          const SizedBox(height: 14.0),
          _buildRememberPwd(),
          const SizedBox(height: 10.0),
          _buildAgreement(),
          const SizedBox(height: 20.0),
          _buildLoginButton(),
        ],
      ),
    );
  }

  /// 登录方式切换Tab
  Widget _buildLoginTypeTabs() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _switchTab(0),
            child: _buildTabContent('手机号登录', 0),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _switchTab(1),
            child: _buildTabContent('商户号登录', 1),
          ),
        ),
      ],
    );
  }

  void _switchTab(int index) {
    if (_loginType == index) return;
    // 切换前保存当前模式的凭证（仅在勾选记住密码时）
    if (_rememberPwd) {
      _saveCredentials();
    }
    setState(() {
      _loginType = index;
      // 切换到新模式后恢复对应凭证
      _restoreCredentials();
    });
  }

  Widget _buildTabContent(String text, int index) {
    final bool isActive = _loginType == index;
    return Container(
      height: 64.0,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: isActive ? 18.0 : 16.0,
              color: isActive ? Colours.app_main : const Color(0xFF555555),
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6.0),
          Container(
            width: 32.0,
            height: 3.0,
            decoration: BoxDecoration(
              color: isActive ? Colours.app_main : Colors.transparent,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 输入表单卡片（拆分为独立输入框，白色背景）
  Widget _buildFormCard() {
    return Column(
      children: [
        // 手机号/账号输入框
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: _buildPhoneField(),
        ),
        const SizedBox(height: 12.0),
        // 商户号登录时额外显示账号输入框
        if (_loginType == 1) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: _buildCodeField(),
          ),
          const SizedBox(height: 12.0),
        ],
        // 密码输入框
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: _buildPasswordField(),
        ),
      ],
    );
  }

  /// 手机号/账号输入框
  Widget _buildPhoneField() {
    return Row(
      children: [
        Icon(
          _loginType == 0 ? Icons.phone_android : Icons.store_outlined,
          color: const Color(0xFFBBBBBB),
          size: 22.0,
        ),
        const SizedBox(width: 10.0),
        Expanded(
          child: TextField(
            key: const Key('phone'),
            focusNode: _nodeText1,
            controller: _nameController,
            maxLength: 30,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: _loginType == 0 ? '请输入手机号' : '请输入商户号',
              hintStyle: const TextStyle(
                fontSize: 14.0,
                color: Color(0xFFAAAAAA),
              ),
              counterText: '',
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10.0),
            ),
            style: const TextStyle(
              fontSize: 15.0,
              color: Colours.text,
            ),
          ),
        ),
        if (_isShowDelete)
          GestureDetector(
            onTap: () => _nameController.clear(),
            child: Container(
              width: 20.0,
              height: 20.0,
              decoration: const BoxDecoration(
                color: Colours.text_gray_c,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 14.0,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  /// 商户号账号输入框
  Widget _buildCodeField() {
    return Row(
      children: [
        const Icon(Icons.person_outline, color: Color(0xFFBBBBBB), size: 22.0),
        const SizedBox(width: 10.0),
        Expanded(
          child: TextField(
            key: const Key('code'),
            focusNode: _nodeText3,
            controller: _codeController,
            maxLength: 20,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            //inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9]'))],
            // 允许数字与英文字母（大小写均可）
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]'))],
            decoration: const InputDecoration(
              hintText: '请输入账号',
              hintStyle: TextStyle(
                fontSize: 14.0,
                color: Color(0xFFAAAAAA),
              ),
              counterText: '',
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10.0),
            ),
            style: const TextStyle(
              fontSize: 15.0,
              color: Colours.text,
            ),
          ),
        ),
      ],
    );
  }

  /// 密码输入框
  Widget _buildPasswordField() {
    return Row(
      children: [
        const Icon(Icons.lock_outline, color: Color(0xFFBBBBBB), size: 22.0),
        const SizedBox(width: 10.0),
        Expanded(
          child: TextField(
            key: const Key('password'),
            focusNode: _nodeText2,
            controller: _passwordController,
            obscureText: !_isShowPwd,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (_clickable && !_isLoading) {
                _login();
              }
            },
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp('[\u4e00-\u9fa5]'))],
            decoration: const InputDecoration(
              hintText: '请输入密码',
              hintStyle: TextStyle(
                fontSize: 14.0,
                color: Color(0xFFAAAAAA),
              ),
              counterText: '',
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10.0),
            ),
            style: const TextStyle(
              fontSize: 15.0,
              color: Colours.text,
            ),
          ),
        ),
        GestureDetector(
          key: const Key('password_showPwd'),
          onTap: () {
            setState(() {
              _isShowPwd = !_isShowPwd;
            });
          },
          child: Icon(
            _isShowPwd ? Icons.visibility : Icons.visibility_off,
            color: const Color(0xFFBBBBBB),
            size: 22.0,
          ),
        ),
      ],
    );
  }

  /// 登录按钮
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 50.0,
      child: ElevatedButton(
        key: const Key('login'),
        onPressed: (_clickable && !_isLoading) ? _login : null,
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return Colours.button_disabled;
            }
            return Colours.app_main;
          }),
          foregroundColor: MaterialStateProperty.all(Colors.white),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24.0),
            ),
          ),
          elevation: MaterialStateProperty.all(0),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20.0,
                height: 20.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                '登  录',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4.0,
                ),
              ),
      ),
    );
  }

  /// 记住账号密码
  Widget _buildRememberPwd() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _rememberPwd = !_rememberPwd;
          if (!_rememberPwd) {
            // 取消勾选时，清除已保存的凭证
            _clearCredentials();
          }
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 16.0,
            height: 16.0,
            decoration: BoxDecoration(
              color: _rememberPwd ? Colours.app_main : Colors.transparent,
              borderRadius: BorderRadius.circular(3.0),
              border: Border.all(
                color: _rememberPwd ? Colours.app_main : const Color(0xFFCCCCCC),
                width: 1.5,
              ),
            ),
            child: _rememberPwd ? const Icon(Icons.check, size: 12.0, color: Colors.white) : null,
          ),
          const SizedBox(width: 6.0),
          const Text(
            '记住账号密码',
            style: TextStyle(
              fontSize: Dimens.font_sp12,
              color: Color(0xFF444444),
            ),
          ),
        ],
      ),
    );
  }

  /// 协议勾选区域
  Widget _buildAgreement() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _agreed = !_agreed;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 16.0,
            height: 16.0,
            decoration: BoxDecoration(
              color: _agreed ? Colours.app_main : Colors.transparent,
              borderRadius: BorderRadius.circular(3.0),
              border: Border.all(
                color: _agreed ? Colours.app_main : const Color(0xFFCCCCCC),
                width: 1.5,
              ),
            ),
            child: _agreed ? const Icon(Icons.check, size: 12.0, color: Colors.white) : null,
          ),
          const SizedBox(width: 6.0),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: Dimens.font_sp12,
                  color: Color(0xFF444444),
                ),
                children: [
                  const TextSpan(text: '同意'),
                  TextSpan(
                    text: '《用户服务协议》',
                    style: const TextStyle(
                      color: Colours.app_main,
                      fontSize: Dimens.font_sp12,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        NavigatorUtils.goAssetHtmlPage(
                          context,
                          '用户协议',
                          'assets/data/user_agreement.html',
                        );
                      },
                  ),
                  const TextSpan(text: '和'),
                  TextSpan(
                    text: '《隐私政策》',
                    style: const TextStyle(
                      color: Colours.app_main,
                      fontSize: Dimens.font_sp12,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        NavigatorUtils.goAssetHtmlPage(
                          context,
                          '隐私政策',
                          'assets/data/privacy_policy.html',
                        );
                      },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建时通过 --dart-define=FULL_VERSION 注入的完整版本号（保留前导零）
  static const _kFullVersion = String.fromEnvironment('FULL_VERSION');

  /// 动态加载版本号
  Future<void> _loadAppVersion() async {
    try {
      if (_kFullVersion.isNotEmpty) {
        _appVersion = _kFullVersion;
      } else {
        final info = await PackageInfo.fromPlatform();
        final build = info.buildNumber;
        _appVersion = build.isNotEmpty ? '${info.version}.$build' : info.version;
      }
      setState(() {});
    } catch (_) {}
  }

  // ========== 记住账号密码相关方法 ==========

  /// 保存当前登录模式的凭证（仅在勾选记住密码时）
  void _saveCredentials() {
    if (_loginType == 0) {
      // 手机号登录模式
      SpUtil.putString(Constant.rememberPhone, _nameController.text);
      SpUtil.putString(Constant.rememberPhonePwd, _passwordController.text);
    } else {
      // 商户号登录模式
      SpUtil.putString(Constant.rememberMerchantCode, _nameController.text);
      SpUtil.putString(Constant.rememberMerchantAccount, _codeController.text);
      SpUtil.putString(Constant.rememberMerchantPwd, _passwordController.text);
    }
    // 保存当前登录方式
    SpUtil.putString(Constant.rememberLoginType, _loginType.toString());
  }

  /// 根据当前登录模式恢复已保存的凭证
  void _restoreCredentials() {
    if (_loginType == 0) {
      _nameController.text = SpUtil.getString(Constant.rememberPhone) ?? '';
      _passwordController.text = SpUtil.getString(Constant.rememberPhonePwd) ?? '';
      _codeController.clear();
    } else {
      _nameController.text = SpUtil.getString(Constant.rememberMerchantCode) ?? '';
      _codeController.text = SpUtil.getString(Constant.rememberMerchantAccount) ?? '';
      _passwordController.text = SpUtil.getString(Constant.rememberMerchantPwd) ?? '';
    }
  }

  /// 清除当前登录模式的已保存凭证
  void _clearCredentials() {
    if (_loginType == 0) {
      SpUtil.remove(Constant.rememberPhone);
      SpUtil.remove(Constant.rememberPhonePwd);
    } else {
      SpUtil.remove(Constant.rememberMerchantCode);
      SpUtil.remove(Constant.rememberMerchantAccount);
      SpUtil.remove(Constant.rememberMerchantPwd);
    }
  }

  /// 登录成功后根据记住密码开关保存或清除凭证
  void _saveOrClearCredentials() {
    SpUtil.putBool(Constant.rememberPwdEnabled, _rememberPwd);
    if (_rememberPwd) {
      _saveCredentials();
    } else {
      _clearCredentials();
    }
  }

  /// 底部版本号
  Widget _buildVersionInfo() {
    return Center(
      child: Text(
        _appVersion.isNotEmpty ? '版本：V$_appVersion' : '',
        style: const TextStyle(
          fontSize: Dimens.font_sp14,
          color: Colours.text_gray,
        ),
      ),
    );
  }
}
