import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/overlay/overlay_constants.dart';

/// 硬不变量高度判定回归（2026-09-27 真机反馈「把手/点竖线回把手后变空白」）：
/// Kotlin dpToPx 截断取整让把手窗口实测高比设计值 88 小（density 2.8125 机器
/// 88dp → 247px → 87.8dp），旧判定 maxHeight < handleHeight 把把手窗误判为
/// 胶囊高度档渲染空白。修复：阈值取两设计高度（88/84）中点，判定走
/// isCapsuleHeightWindow 纯函数。
void main() {
  group('isCapsuleHeightWindow 胶囊高度档判定', () {
    test('阈值 = 把手高与胶囊窗高的中点 86', () {
      expect(OverlayConstants.handleWindowHeightThreshold, 86.0);
    });

    test('语音胶囊窗口实测值（含取整误差）判为胶囊高度档', () {
      // 设计值与 density 2.8125 实测值（84dp → 236px → 83.9）
      expect(OverlayConstants.isCapsuleHeightWindow(84.0), isTrue);
      expect(OverlayConstants.isCapsuleHeightWindow(83.9), isTrue);
      // mdpi（density 1.0）极端：84dp 最多截 1px → 83.0
      expect(OverlayConstants.isCapsuleHeightWindow(83.0), isTrue);
    });

    test('把手窗口实测值（含取整误差）不误判为胶囊高度档', () {
      expect(OverlayConstants.isCapsuleHeightWindow(88.0), isFalse);
      // 本次事故机器实测：88dp @density2.8125 → 247px → 87.8
      expect(OverlayConstants.isCapsuleHeightWindow(87.8), isFalse);
      // mdpi 极端：88dp 最多截 1px → 87.0
      expect(OverlayConstants.isCapsuleHeightWindow(87.0), isFalse);
    });

    test('贴边竖线窗口（64 高）落在胶囊高度档内（分支另由 isEdgeLine 例外放行）',
        () {
      expect(OverlayConstants.isCapsuleHeightWindow(64.0), isTrue);
    });
  });
}
