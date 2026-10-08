import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/overlay/overlay_constants.dart';
import 'package:shengwuji_app/overlay/widgets/overlay_diary_card.dart';

/// 悬浮窗字体大小五档回归（2026-09-27，用户需求：以现字号为基准 ±2 档）：
/// prefs overlay_font_size_step ∈ [-2,2]（每档 1pt——0.5pt 档差真机不可辨、
/// 2pt 档差最小档跌破可读下限）；只作用日记面板文字（卡片收起/展开/编辑/
/// 删除确认 + 分隔线/空态/错误态），不作用把手（独立大小档位，叠加会双重
/// 缩放）与语音速记胶囊（宽度预算按 15 号字调过）；收起态文字测量缓存 key
/// 含字号——不同档位同文本宽度不同，不进 key 会串档（估算偏窄把短文字顶出
/// 省略号，046fe0b 同类坑）。
void main() {
  group('档位解析与缩放（纯函数）', () {
    test('parseFontSizeStep：null/缺失兜底标准档 0', () {
      expect(OverlayConstants.parseFontSizeStep(null), 0);
      expect(OverlayConstants.fontSizeStepDefault, 0);
    });

    test('parseFontSizeStep：合法五档原样通过', () {
      for (final step in [-2, -1, 0, 1, 2]) {
        expect(OverlayConstants.parseFontSizeStep(step), step);
      }
    });

    test('parseFontSizeStep：越界脏值 clamp 到 [-2,2]（连续刻度语义）', () {
      expect(OverlayConstants.parseFontSizeStep(3), 2);
      expect(OverlayConstants.parseFontSizeStep(99), 2);
      expect(OverlayConstants.parseFontSizeStep(-3), -2);
      expect(OverlayConstants.parseFontSizeStep(-99), -2);
    });

    test('fontScaled：基准 + 档位（每档 1pt），标准档恒等', () {
      expect(OverlayConstants.fontScaled(15, 0), 15.0);
      expect(OverlayConstants.fontScaled(15, 2), 17.0);
      expect(OverlayConstants.fontScaled(15, -2), 13.0);
      expect(OverlayConstants.fontScaled(12, -2), 10.0);
    });

    test('边界不变量：最小档正文 11pt / 时间行 10pt，不跌破可读下限', () {
      // 正文基准 cardFontSize（13）、时间行基准 12，最小档 -2 后仍 ≥10pt
      expect(
        OverlayConstants.fontScaled(OverlayConstants.cardFontSize, -2),
        greaterThanOrEqualTo(11.0),
      );
      expect(
        OverlayConstants.fontScaled(12, -2),
        greaterThanOrEqualTo(10.0),
      );
    });
  });

  group('收起态文字测量缓存按字号分档', () {
    const text = '钥匙放在客厅电视柜';

    test('同文本不同字号测出不同宽度（缓存 key 含字号，不串档）', () {
      final w13 = OverlayDiaryCard.measureCollapsedTextWidthForTest(
        text,
        TextScaler.noScaling,
        null,
        fontSize: 13,
      );
      final w15 = OverlayDiaryCard.measureCollapsedTextWidthForTest(
        text,
        TextScaler.noScaling,
        null,
        fontSize: 15,
      );
      final w17 = OverlayDiaryCard.measureCollapsedTextWidthForTest(
        text,
        TextScaler.noScaling,
        null,
        fontSize: 17,
      );
      expect(w15, greaterThan(w13));
      expect(w17, greaterThan(w15));
    });

    test('同字号重复测量命中缓存，跨字号各自 shaping 一次', () {
      final before = OverlayDiaryCard.collapsedTextMeasureCount;
      // 首次 14pt：miss 一次
      OverlayDiaryCard.measureCollapsedTextWidthForTest(
        text,
        TextScaler.noScaling,
        null,
        fontSize: 14,
      );
      // 重复 14pt：命中缓存不再 layout
      OverlayDiaryCard.measureCollapsedTextWidthForTest(
        text,
        TextScaler.noScaling,
        null,
        fontSize: 14,
      );
      // 换 16pt：字号不同 = 不同 key，miss 一次
      OverlayDiaryCard.measureCollapsedTextWidthForTest(
        text,
        TextScaler.noScaling,
        null,
        fontSize: 16,
      );
      expect(OverlayDiaryCard.collapsedTextMeasureCount - before, 2);
    });
  });
}
