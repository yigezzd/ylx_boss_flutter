import 'package:flutter_deer/res/constant.dart';
import 'package:sp_util/sp_util.dart';

/// 扫码设置数据模型
///
/// 三个配置项：
/// - [scanDevice] 扫码设备：0=摄像头，1=iScan激光扫码，2=iScan激光扫码+摄像头
/// - [scanQtyMode] 录入数量模式：0=默认累加1，1=弹窗手动输入
/// - [scanContinuous] 连续扫码开关：true=开启（默认），false=关闭
class ScanSettings {
  /// 扫码设备
  /// 0 = 仅摄像头（显示扫描按钮，隐藏红外输入框）
  /// 1 = 仅 iScan 激光扫码（隐藏扫描按钮，显示红外输入框）
  /// 2 = iScan 激光扫码 + 摄像头（两者都显示）
  int scanDevice;

  /// 录入数量模式
  /// 0 = 默认累加1（扫描后直接累加数量）
  /// 1 = 弹窗手动输入（扫描后打开商品详情抽屉，手动确认数量）
  int scanQtyMode;

  /// 连续扫码开关
  /// true = 开启（扫码后焦点回到扫描框，连续扫码模式）
  /// false = 关闭（扫码后焦点转移到数量输入框）
  bool scanContinuous;

  ScanSettings({
    this.scanDevice = 1,
    this.scanQtyMode = 0,
    this.scanContinuous = true,
  });

  /// 从本地存储读取设置
  factory ScanSettings.fromSp() {
    return ScanSettings(
      scanDevice: SpUtil.getInt(Constant.scanDevice, defValue: 1) ?? 1,
      scanQtyMode: SpUtil.getInt(Constant.scanQtyMode, defValue: 0) ?? 0,
      scanContinuous: SpUtil.getBool(Constant.scanContinuous, defValue: true) ?? true,
    );
  }

  /// 保存设置到本地存储
  void save() {
    SpUtil.putInt(Constant.scanDevice, scanDevice);
    SpUtil.putInt(Constant.scanQtyMode, scanQtyMode);
    SpUtil.putBool(Constant.scanContinuous, scanContinuous);
  }

  // ── 便捷 getter ──

  /// 是否显示摄像头扫描按钮
  bool get showCameraButton => scanDevice == 0 || scanDevice == 2;

  /// 是否显示红外扫描输入框
  bool get showInfraredInput => scanDevice == 1 || scanDevice == 2;

  /// 扫码设备显示文本
  String get scanDeviceLabel {
    switch (scanDevice) {
      case 0: return '摄像头';
      case 1: return 'iScan激光扫码';
      case 2: return 'iScan激光扫码 + 摄像头';
      default: return 'iScan激光扫码';
    }
  }

  /// 录入数量模式显示文本
  String get scanQtyModeLabel {
    switch (scanQtyMode) {
      case 0: return '默认累加1';
      case 1: return '弹窗手动输入';
      default: return '默认累加1';
    }
  }

  /// 复制并修改
  ScanSettings copyWith({
    int? scanDevice,
    int? scanQtyMode,
    bool? scanContinuous,
  }) {
    return ScanSettings(
      scanDevice: scanDevice ?? this.scanDevice,
      scanQtyMode: scanQtyMode ?? this.scanQtyMode,
      scanContinuous: scanContinuous ?? this.scanContinuous,
    );
  }
}
