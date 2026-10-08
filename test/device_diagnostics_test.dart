import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/utils/device_diagnostics.dart';

Map<String, Object?> _fullInfo() => {
  'manufacturer': 'Xiaomi',
  'brand': 'Xiaomi',
  'model': '23113RKC6C',
  'device': 'houji',
  'hardware': 'qcom',
  'abis': ['arm64-v8a', 'armeabi-v7a'],
  'androidRelease': '15',
  'sdkInt': 35,
  'displayId': 'OS2.0.108.0.VNBCNXM',
  'miuiVersion': 'V816',
  'screenWidthPx': 1220,
  'screenHeightPx': 2712,
  'refreshRate': 120.0,
  'densityDpi': 440,
  'density': 2.75,
  'navigationMode': 2,
  'canDrawOverlays': false,
  'micGranted': true,
  'notifGranted': true,
  'enabledAccessibilityServices':
      'com.shengwuji.app/.VolumeKeyAccessibilityService:'
      'com.example.jumper/.JumperService',
};

void main() {
  group('formatDeviceDiagnostics 完整数据', () {
    test('五行齐全且关键字段落位', () {
      final lines = DeviceDiagnosticsLogger.formatDeviceDiagnostics(
        _fullInfo(),
        engine: 'main',
      );
      expect(lines, hasLength(5));
      expect(lines[0], contains('Xiaomi'));
      expect(lines[0], contains('23113RKC6C'));
      expect(lines[0], contains('qcom'));
      expect(lines[1], contains('Android 15'));
      expect(lines[1], contains('SDK 35'));
      expect(lines[1], contains('OS2.0.108.0.VNBCNXM'));
      expect(lines[1], contains('MIUI=V816'));
      expect(lines[2], contains('1220x2712px'));
      expect(lines[2], contains('440dpi'));
      expect(lines[2], contains('x2.75'));
      expect(lines[2], contains('120.0Hz'));
      expect(lines[2], contains('arm64-v8a'));
      expect(lines[3], contains('手势导航(2)'));
      expect(lines[3], contains('悬浮窗权限=false'));
      expect(lines[3], contains('麦克风=true'));
      expect(lines[4], contains('com.shengwuji.app'));
      expect(lines[4], contains('com.example.jumper'));
    });

    test('engine 标签出现在每行', () {
      final lines = DeviceDiagnosticsLogger.formatDeviceDiagnostics(
        _fullInfo(),
        engine: 'overlay',
      );
      for (final line in lines) {
        expect(line, contains('设备诊断/overlay'));
      }
    });
  });

  group('formatDeviceDiagnostics 边界与脏数据兜底', () {
    test('无障碍服务为空显示（无）', () {
      final info = _fullInfo()..['enabledAccessibilityServices'] = '';
      final lines = DeviceDiagnosticsLogger.formatDeviceDiagnostics(
        info,
        engine: 'main',
      );
      expect(lines[4], contains('（无）'));
    });

    test('无障碍服务只留包名且去重', () {
      final info = _fullInfo()
        ..['enabledAccessibilityServices'] =
            'a.b/.S1:a.b/.S2:c.d/.S3';
      final lines = DeviceDiagnosticsLogger.formatDeviceDiagnostics(
        info,
        engine: 'main',
      );
      expect(lines[4], contains('a.b, c.d'));
      expect(lines[4], isNot(contains('.S1')));
    });

    test('MIUI 版本为空串时不带 MIUI 段', () {
      final info = _fullInfo()..['miuiVersion'] = '';
      final lines = DeviceDiagnosticsLogger.formatDeviceDiagnostics(
        info,
        engine: 'main',
      );
      expect(lines[1], isNot(contains('MIUI')));
    });

    test('导航模式各取值', () {
      for (final (mode, label) in [
        (0, '三键(0)'),
        (1, '两键(1)'),
        (2, '手势导航(2)'),
        (-1, '未知(-1)'),
      ]) {
        final info = _fullInfo()..['navigationMode'] = mode;
        final lines = DeviceDiagnosticsLogger.formatDeviceDiagnostics(
          info,
          engine: 'main',
        );
        expect(lines[3], contains('导航=$label'), reason: 'mode=$mode');
      }
    });

    test('字段缺失逐项问号兜底不抛异常', () {
      final lines = DeviceDiagnosticsLogger.formatDeviceDiagnostics(
        <String, Object?>{},
        engine: 'main',
      );
      expect(lines, hasLength(5));
      expect(lines[0], contains('?'));
      // enabledAccessibilityServices 缺失 = 读取失败语义显示 '?'（与「空串 =
      // 确知无启用服务」区分，见「无障碍服务为空」用例）
      expect(lines[4], contains(': ?'));
    });

    test('类型不符（abis 非 List / density 非 num）不抛异常', () {
      final info = _fullInfo()
        ..['abis'] = 'arm64-v8a'
        ..['density'] = 'high'
        ..['refreshRate'] = null;
      final lines = DeviceDiagnosticsLogger.formatDeviceDiagnostics(
        info,
        engine: 'main',
      );
      expect(lines[2], contains('ABI=[?]'));
      expect(lines[2], contains('x?'));
      expect(lines[2], contains('刷新率=?Hz'));
    });
  });
}
