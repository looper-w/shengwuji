import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/utils/note_lock_auth.dart';

/// 笔记加锁前置检查（isDeviceSecure）与引导跳转（openSecuritySettings）的
/// 通道封装语义：原生返回什么透传什么；通道异常按「未设置锁屏密码」/
/// 「未拉起」失败关闭（安全侧兜底）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.shengwuji.app/app');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('isDeviceSecure 透传原生 true', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isDeviceSecure');
      return true;
    });
    expect(await NoteLockAuth.isDeviceSecure(), isTrue);
  });

  test('isDeviceSecure 透传原生 false（未设锁屏密码 → 禁止加锁）', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await NoteLockAuth.isDeviceSecure(), isFalse);
  });

  test('isDeviceSecure 通道异常按未设置兜底（失败关闭）', () async {
    // 不注册 handler → MissingPluginException
    expect(await NoteLockAuth.isDeviceSecure(), isFalse);
  });

  test('openSecuritySettings 透传原生结果', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openSecuritySettings');
      return true;
    });
    expect(await NoteLockAuth.openSecuritySettings(), isTrue);
  });

  test('openSecuritySettings 通道异常返回 false', () async {
    expect(await NoteLockAuth.openSecuritySettings(), isFalse);
  });
}
