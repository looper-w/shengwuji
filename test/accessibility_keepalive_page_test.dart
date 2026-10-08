import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/settings/accessibility_keepalive_page.dart';
import 'package:shengwuji_app/theme/app_theme.dart';

/// 「无障碍保活指南」三级页回归（2026-09 新增）。锁组件层契约：
/// 六项自查步骤全渲染、自查清单/搜索教程两分区标题、底部直达无障碍设置按钮。
/// 页面纯说明无状态，openAccessibilitySettings 的通道失败在
/// accessibility_check.dart 内部自吞（catch + log），无需 mock。
void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    // ListView 懒构建，默认 800×600 视口渲染不到下半屏——拉高视口让全部
    // 条目一次性进树（测试结束自动复位）
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // AppThemeExtension.of 经 Theme.extension 解析，必须挂应用主题
        // （同 web_server_settings_card_test 的做法）
        theme: AppThemes.defaultTheme.toThemeData(),
        home: const AccessibilityKeepAlivePage(),
      ),
    );
    await tester.pump();
  }

  testWidgets('渲染六项自查步骤与两个分区标题', (tester) async {
    await pumpPage(tester);

    expect(find.text('逐项自查清单'), findsOneWidget);
    expect(find.text('还是不行？'), findsOneWidget);

    // 六步标题（内容即文档，改动步骤文案需同步本测试）
    for (final title in [
      '开启「自启动」',
      '在最近任务里「锁定」本应用',
      '电池策略设为「无限制」',
      '允许「后台弹出界面」',
      '允许「锁屏显示」',
      '重新开启无障碍服务',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺少步骤：$title');
    }

    // 搜索教程兜底建议
    expect(find.textContaining('无障碍服务 保活'), findsOneWidget);
  });

  testWidgets('底部直达无障碍设置按钮存在且可点', (tester) async {
    await pumpPage(tester);

    final button = find.widgetWithText(ElevatedButton, '前往无障碍设置');
    expect(button, findsOneWidget);
    // 点击不炸即可（通道失败内部自吞）
    await tester.tap(button);
    await tester.pump();
  });
}
