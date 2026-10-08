import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/theme/app_theme.dart';
import 'package:shengwuji_app/theme/custom_theme.dart' show contrastRatio;

/// 深色主题（AppThemes.dark + themeMode 三档）测试
///
/// 背景：2026-09-28 用户拍板——主 App 只做一套标准深色皮肤（非各浅色主题
/// 的深色变体），MaterialApp.darkTheme 专用；悬浮窗不做深色系。
void main() {
  group('parseThemeMode', () {
    test('null / 缺失 → 跟随系统', () {
      expect(parseThemeMode(null), ThemeMode.system);
    });

    test('合法三值解析', () {
      expect(parseThemeMode('system'), ThemeMode.system);
      expect(parseThemeMode('light'), ThemeMode.light);
      expect(parseThemeMode('dark'), ThemeMode.dark);
    });

    test('坏串兜底跟随系统', () {
      expect(parseThemeMode(''), ThemeMode.system);
      expect(parseThemeMode('darkness'), ThemeMode.system);
      expect(parseThemeMode('Dark'), ThemeMode.system); // 大小写敏感，坏串兜底
    });
  });

  group('AppThemes.dark 注册约束', () {
    test('深色主题不进 all（主题选择器只选浅色皮肤）', () {
      expect(AppThemes.all.contains(AppThemes.dark), isFalse);
      expect(AppThemes.findById('dark_standard'), isNull);
    });

    test('all 中全部为浅色主题', () {
      for (final t in AppThemes.all) {
        expect(t.brightness, Brightness.light, reason: '${t.id} 应为浅色');
      }
    });

    test('深色主题非 Pro、brightness=dark', () {
      expect(AppThemes.dark.isPro, isFalse);
      expect(AppThemes.dark.brightness, Brightness.dark);
    });
  });

  group('深色主题配色 sanity', () {
    final ext = AppThemes.dark.extension;

    test('背景双层符合 Material 深色规范', () {
      expect(ext.scaffoldBackground, const Color(0xFF121212));
      expect(ext.cardBackground, const Color(0xFF1E1E1E));
      expect(ext.surface, const Color(0xFF1E1E1E));
    });

    test('文字为白 alpha 三档（87%/60%/38%）', () {
      expect(ext.textPrimary, const Color(0xDEFFFFFF));
      expect(ext.textSecondary, const Color(0x99FFFFFF));
      expect(ext.textHint, const Color(0x61FFFFFF));
    });

    test('状态栏图标用亮色（isDarkOverlay=true）', () {
      expect(ext.isDarkOverlay, isTrue);
    });

    test('主文字在卡片底对比度 ≥ 12:1', () {
      final ratio = contrastRatio(
        ext.textPrimary,
        ext.cardBackground,
      );
      expect(ratio, greaterThanOrEqualTo(12.0));
    });

    test('次文字在卡片底对比度 ≥ 7:1', () {
      final ratio = contrastRatio(
        ext.textSecondary,
        ext.cardBackground,
      );
      expect(ratio, greaterThanOrEqualTo(7.0));
    });

    test('深色主题 FAB 前景色为暗色且在品牌青上 ≥3:1（2026-09-28 真机反馈）', () {
      // 用户反馈：白图标/白字在深底界面太跳「起码不能亮色的白」
      expect(ext.fabContentColor, isNot(Colors.white));
      final ratio = contrastRatio(
        ext.fabContentColor,
        ext.primary,
      );
      expect(ratio, greaterThanOrEqualTo(3.0));
    });

    test('深色主题黏土阴影无白高光（光晕修复），浅色主题保留白高光', () {
      // 白高光在深底显形为一圈光晕 → 深色只留暗影
      final darkShadow = ext.fabClayShadow;
      for (final shadow in darkShadow) {
        expect(shadow.color, isNot(const Color(0x66FFFFFF)));
        expect(
          shadow.color.computeLuminance(),
          lessThan(0.5),
          reason: '深色主题阴影不应含白色高光',
        );
      }
      final lightShadow = AppThemes.defaultTheme.extension.fabClayShadow;
      expect(lightShadow.length, 2);
      expect(
        lightShadow.first.color.computeLuminance(),
        greaterThan(0.5),
        reason: '浅色主题第一道光应为白色高光',
      );
    });

    test('浅色主题 FAB 前景色恒白（2026-09-23 恒白承诺回归保护）', () {
      for (final t in AppThemes.all) {
        expect(
          t.extension.fabContentColor,
          Colors.white,
          reason: '${t.id}（浅色）语音钮图标应恒白',
        );
      }
    });

    test('强调文字色（primaryDark 亮青）在深底可读 ≥ 4.5:1', () {
      final ratio = contrastRatio(
        ext.primaryDark,
        ext.scaffoldBackground,
      );
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('启动页沿用深海渐变（深浅两态视觉一致）', () {
      expect(ext.splashGradient, isNotNull);
      expect(ext.splashGradient!.length, 3);
      expect(ext.splashGradient!.first, const Color(0xFF0D1B2E));
    });
  });

  group('深色主题 ThemeData 构建', () {
    test('toThemeData 产出的 ColorScheme 为 dark', () {
      final theme = AppThemes.dark.toThemeData();
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('浅色主题 toThemeData 仍为 light（brightness 字段不串档）', () {
      for (final t in AppThemes.all) {
        expect(
          t.toThemeData().colorScheme.brightness,
          Brightness.light,
          reason: '${t.id} 的 ThemeData 应为浅色',
        );
      }
    });
  });
}
