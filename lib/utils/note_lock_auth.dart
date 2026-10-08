import 'package:flutter/services.dart';

/// 笔记解锁认证的发起封装（主 App 侧）。
///
/// 认证由原生 NoteUnlockCoordinator 统一承接（锁屏中 requestDismissKeyguard
/// 弹系统解锁界面 / 未锁屏弹 androidx.biometric 对话框），invokeMethod 只等
/// 「是否成功拉起」；认证结果异步经 MainActivity → flutterChannel 的
/// noteUnlockResult 事件回发，由 main.dart 转发给 DiaryTabState.onNoteUnlockResult。
/// 悬浮窗侧同款发起走 AccessibilityOverlay.requestUnlockAuth（通道不同）。
class NoteLockAuth {
  NoteLockAuth._();

  /// 主 App 发起系统认证（MainActivity 通道）。返回 false = 已有认证在进行
  /// （Kotlin 层 coordinator 防重），可安全重复调用
  static Future<bool> requestFromApp() async {
    try {
      return await MethodChannel(
        'com.shengwuji.app/app',
      ).invokeMethod('requestUnlockAuth') == true;
    } catch (e) {
      print('❌ [NoteLockAuth] 发起认证失败: $e');
      return false;
    }
  }

  /// 设备是否已设置锁屏凭据（PIN/图案/密码）。笔记**加锁**前置检查——
  /// 未设置时不允许锁定：锁定后没有任何认证手段能看回内容，锁定形同虚设
  /// 反而误导用户以为已保护。通道异常按「未设置」兜底（安全侧失败关闭）
  static Future<bool> isDeviceSecure() async {
    try {
      return await MethodChannel(
        'com.shengwuji.app/app',
      ).invokeMethod('isDeviceSecure') == true;
    } catch (e) {
      print('❌ [NoteLockAuth] 查询锁屏凭据失败: $e');
      return false;
    }
  }

  /// 拉起系统「安全」设置页（加锁引导对话框「去设置」按钮，引导用户先设
  /// 锁屏密码再回来锁定）。返回 true = 已拉起
  static Future<bool> openSecuritySettings() async {
    try {
      return await MethodChannel(
        'com.shengwuji.app/app',
      ).invokeMethod('openSecuritySettings') == true;
    } catch (e) {
      print('❌ [NoteLockAuth] 拉起安全设置页失败: $e');
      return false;
    }
  }
}
