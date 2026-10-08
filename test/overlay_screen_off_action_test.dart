import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/overlay/overlay_constants.dart';

/// 息屏分流回归（2026-09-28 真机反馈「永久档把手息屏解锁后消失」）：旧语义
/// 息屏无条件推进驻留终态（竖线开→竖线/关→彻底移除），「永久」档不豁免，
/// 与永久=把手常驻的承诺冲突。新语义：永久档把手驻留穿越 AOD（窗口仅由
/// Kotlin GONE/VISIBLE 随息屏/亮屏切换），限时档维持「进 AOD 必须收」。
void main() {
  group('screenOffActionFor 息屏去向分流', () {
    test('永久档（autoHideNeverSeconds）无论竖线开关都把手驻留', () {
      expect(
        OverlayConstants.screenOffActionFor(
          OverlayConstants.autoHideNeverSeconds,
          edgeLineEnabled: true,
        ),
        ScreenOffAction.keepHandle,
      );
      expect(
        OverlayConstants.screenOffActionFor(
          OverlayConstants.autoHideNeverSeconds,
          edgeLineEnabled: false,
        ),
        ScreenOffAction.keepHandle,
      );
    });

    test('限时档 + 竖线开关开 → 缩成贴边竖线', () {
      for (final seconds in [5, 10, 30]) {
        expect(
          OverlayConstants.screenOffActionFor(seconds, edgeLineEnabled: true),
          ScreenOffAction.enterEdgeLine,
          reason: 'seconds=$seconds',
        );
      }
    });

    test('限时档 + 竖线开关关 → 彻底移除窗口', () {
      for (final seconds in [5, 10, 30]) {
        expect(
          OverlayConstants.screenOffActionFor(seconds, edgeLineEnabled: false),
          ScreenOffAction.closeOverlay,
          reason: 'seconds=$seconds',
        );
      }
    });

    test('默认档（autoHideDefaultSeconds）按限时档处理', () {
      expect(
        OverlayConstants.screenOffActionFor(
          OverlayConstants.autoHideDefaultSeconds,
          edgeLineEnabled: true,
        ),
        ScreenOffAction.enterEdgeLine,
      );
      expect(
        OverlayConstants.screenOffActionFor(
          OverlayConstants.autoHideDefaultSeconds,
          edgeLineEnabled: false,
        ),
        ScreenOffAction.closeOverlay,
      );
    });
  });
}
