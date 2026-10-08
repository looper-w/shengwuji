import 'package:shengwuji_app/app_logger.dart';

/// 设备诊断日志（2026-09-26，悬浮窗「滑动收起后把手/竖线不出现」终端用户
/// 反馈不可复现，发诊断包收集日志定位用）。
///
/// 采集在原生侧 DeviceDiagnostics.kt（双 engine 共用：主 App 通道与无障碍
/// 服务通道同名 handler），本类负责把返回 map 格式化成日志行并经 [log] 写入
/// AppLogger——诊断包用户从 App 内「导出运行日志」分享回来即可定位。
///
/// 隐私纪律（与原生侧一致）：只含非敏感字段（品牌/型号/屏幕/导航模式/权限
/// 快照/已启用无障碍服务），不采 IMEI/Android ID/应用列表，不联网。
class DeviceDiagnosticsLogger {
  /// 每个 isolate 记一次（主 engine 与 overlay engine 是独立 isolate，静态
  /// 字段互不共享，各自记一次正好覆盖「主 App 未启动、仅悬浮窗 engine 在
  /// 跑」的场景——日志文件两 isolate 共同 append）
  static bool _logged = false;

  /// 格式化诊断 map 为日志行（纯函数，单测规格）。
  /// 字段缺失/类型不符逐项兜底，任何脏数据不抛异常。
  static List<String> formatDeviceDiagnostics(
    Map<dynamic, dynamic> info, {
    required String engine,
  }) {
    String str(String key) => info[key]?.toString() ?? '?';
    final abis = info['abis'] is List
        ? (info['abis'] as List).join(',')
        : '?';
    final density = info['density'] is num
        ? (info['density'] as num).toStringAsFixed(2)
        : '?';
    final refreshRate = info['refreshRate'] is num
        ? (info['refreshRate'] as num).toStringAsFixed(1)
        : '?';
    final miui = str('miuiVersion');
    final navMode = switch (info['navigationMode']) {
      2 => '手势导航(2)',
      1 => '两键(1)',
      0 => '三键(0)',
      final other => '未知($other)',
    };
    final a11yRaw = str('enabledAccessibilityServices');
    final a11yList = a11yRaw.isEmpty
        ? '（无）'
        : a11yRaw
              .split(':')
              // 组件串形态 包名/服务类名，只留包名便于一眼扫冲突方
              .map((c) => c.split('/').first)
              .toSet()
              .join(', ');
    return [
      '📱 [设备诊断/$engine] ${str('manufacturer')} ${str('brand')} '
          '${str('model')} (device=${str('device')}, hw=${str('hardware')})',
      '📱 [设备诊断/$engine] Android ${str('androidRelease')} '
          '(SDK ${str('sdkInt')}), display=${str('displayId')}'
          '${miui.isEmpty ? '' : ', MIUI=$miui'}',
      '📱 [设备诊断/$engine] 屏幕 ${str('screenWidthPx')}x'
          '${str('screenHeightPx')}px @${str('densityDpi')}dpi(x$density), '
          '刷新率=${refreshRate}Hz, ABI=[$abis]',
      '📱 [设备诊断/$engine] 导航=$navMode, '
          '悬浮窗权限=${str('canDrawOverlays')}, 麦克风=${str('micGranted')}, '
          '通知=${str('notifGranted')}',
      '📱 [设备诊断/$engine] 已启用无障碍服务: $a11yList',
    ];
  }

  /// 拉取原生诊断信息并写入日志（每 isolate 只记第一次调用，重复调用 no-op）。
  /// [fetch] 由各 engine 注入自己的通道调用（主 engine 走 com.shengwuji.app/app，
  /// overlay engine 走 AccessibilityOverlay.getDeviceDiagnostics）。
  static Future<void> logOnce({
    required String engine,
    required Future<Map<dynamic, dynamic>?> Function() fetch,
  }) async {
    if (_logged) return;
    _logged = true;
    try {
      final info = await fetch();
      if (info == null) {
        log('⚠️ [设备诊断/$engine] 原生返回空，本次不记录');
        return;
      }
      for (final line in formatDeviceDiagnostics(info, engine: engine)) {
        log(line);
      }
    } catch (e) {
      log('⚠️ [设备诊断/$engine] 读取失败: $e');
    }
  }
}
