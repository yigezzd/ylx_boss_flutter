package com.weilu.deer;

import android.content.pm.ShortcutManager;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;

/**
 * @author weilu
 */
public class MainActivity extends FlutterActivity {

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    flutterEngine.getPlugins().add(new InstallAPKPlugin(this));
    flutterEngine.getPlugins().add(new PdaScannerPlugin());
    flutterEngine.getPlugins().add(new GPrinterPlugin());
  }

  @Override
  protected void onCreate(@Nullable Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    /// 设置状态栏透明，导航栏沉浸。
//    getWindow().addFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
    getWindow().setStatusBarColor(Color.TRANSPARENT);
    // 清除旧版本通过 quick_actions 插件注册的动态快捷方式（如"Demo"），避免覆盖安装后残留
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
      ShortcutManager shortcutManager = getSystemService(ShortcutManager.class);
      if (shortcutManager != null) {
        shortcutManager.removeAllDynamicShortcuts();
      }
    }
  }
}
