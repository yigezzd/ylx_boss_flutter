import 'package:flutter/foundation.dart';

class Constant {

  /// App运行在Release环境时，inProduction为true；当App运行在Debug和Profile环境时，inProduction为false
  static const bool inProduction  = kReleaseMode;

  static bool isDriverTest  = false;
  static bool isUnitTest  = false;
  
  static const String data = 'data';
  static const String message = 'message';
  static const String code = 'code';
  
  static const String keyGuide = 'keyGuide';
  static const String phone = 'phone';
  static const String accessToken = 'accessToken';
  static const String refreshToken = 'refreshToken';

  static const String theme = 'AppTheme';

  /// 登录相关存储 key
  static const String token = 'token';
  static const String user = 'user';
  static const String store = 'store';
  static const String rolemap = 'rolemap';
  static const String sysStoreAccount = 'sysStoreAccount';
  static const String allLoginData = 'allLoginData';
  static const String loginParamResp = 'loginParamResp';

  /// 记住密码相关存储 key
  static const String rememberLoginType = 'remember_login_type'; // 上次登录方式 0:手机号 1:商户号
  static const String rememberPhone = 'remember_phone';           // 手机号模式-手机号
  static const String rememberPhonePwd = 'remember_phone_pwd';    // 手机号模式-密码
  static const String rememberMerchantCode = 'remember_merchant_code';     // 商户号模式-商户号
  static const String rememberMerchantAccount = 'remember_merchant_account'; // 商户号模式-账号
  static const String rememberMerchantPwd = 'remember_merchant_pwd';         // 商户号模式-密码
  static const String rememberPwdEnabled = 'remember_pwd_enabled';           // 记住密码开关

  /// 扫码设置相关存储 key
  /// 扫码设备：0=摄像头，1=iScan激光扫码，2=iScan激光扫码+摄像头
  static const String scanDevice = 'scan_device';
  /// 录入数量模式：0=默认累加1，1=弹窗手动输入
  static const String scanQtyMode = 'scan_qty_mode';
  /// 连续扫码开关
  static const String scanContinuous = 'scan_continuous';

  /// 图片 OSS 前缀（商品图片等通用）
  static const String imageBaseUrl = 'https://byyoupic.oss-cn-shenzhen.aliyuncs.com';

}

