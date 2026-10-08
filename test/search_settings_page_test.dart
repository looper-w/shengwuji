import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shengwuji_app/settings/search_settings_page.dart';
import 'package:shengwuji_app/theme/app_theme.dart';
import 'package:shengwuji_app/utils/big_bang_search.dart';

/// 「大爆炸搜索」二级页回归。锁组件层契约：
/// 三引擎 ChoiceChip 渲染与默认选中百度、点选写 prefs search_engine、
/// 「系统默认」浏览器行渲染、mock 通道返回浏览器列表后渲染且点选写
/// search_browser_package / search_browser_name。
/// 坑位照 web_server_settings_card_test：prefs 必须 mock、
/// AppThemeExtension 必须挂应用主题、平台通道用 defaultBinaryMessenger mock。
void main() {
  const channel = MethodChannel('com.shengwuji.app/app');

  final mockBrowsers = [
    {'appName': 'Chrome', 'packageName': 'com.android.chrome'},
    {'appName': 'Via', 'packageName': 'mark.via'},
  ];

  setUp(() {
    // 页面 initState 读 prefs 摘要；widget 测试必须 mock，
    // 否则 SharedPreferences.getInstance() 挂起
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getInstalledBrowsers':
          return mockBrowsers;
        case 'getAppIcon':
          return null; // 图标加载失败走占位，避免 Image.memory 解码假字节
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.defaultTheme.toThemeData(),
        home: const SearchSettingsPage(),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  ChoiceChip chipOf(WidgetTester tester, String label) =>
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

  testWidgets('三个搜索引擎 chip 渲染，默认选中百度', (tester) async {
    await pumpPage(tester);

    expect(find.widgetWithText(ChoiceChip, '百度'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '必应'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Google'), findsOneWidget);
    expect(chipOf(tester, '百度').selected, isTrue);
    expect(chipOf(tester, '必应').selected, isFalse);
    expect(chipOf(tester, 'Google').selected, isFalse);
  });

  testWidgets('点必应写 prefs search_engine=bing 且选中态切换', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('必应'));
    await tester.pump();
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kSearchEngineKey), 'bing');
    expect(chipOf(tester, '必应').selected, isTrue);
    expect(chipOf(tester, '百度').selected, isFalse);
  });

  testWidgets('「系统默认」浏览器行渲染且默认选中', (tester) async {
    await pumpPage(tester);

    expect(find.text('系统默认'), findsOneWidget);
    // 默认 search_browser_package 为空串 → 系统默认行打勾
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('mock 两个浏览器时列表渲染，点选写 prefs 两个 key', (tester) async {
    await pumpPage(tester);

    expect(find.text('Chrome'), findsOneWidget);
    expect(find.text('Via'), findsOneWidget);

    await tester.tap(find.text('Via'));
    await tester.pump();
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kSearchBrowserPackageKey), 'mark.via');
    expect(prefs.getString(kSearchBrowserNameKey), 'Via');
    // 选中勾从系统默认行挪到 Via 行（仍只有一枚）
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
