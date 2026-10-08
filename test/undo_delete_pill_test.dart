// 滑动删除撤销胶囊（UndoDeletePill）渲染契约测试。
//
// 契约：黑 72% 半透明底胶囊（OverlayPanelHeader / _StopHintPill 同视觉家族）、
// 「已删除」文案 + 可点「撤销」按钮（点击触发 onUndo）、字号随面板字体档位缩放。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/overlay/overlay_constants.dart';
import 'package:shengwuji_app/overlay/widgets/undo_delete_pill.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('渲染「已删除」+「撤销」，点击撤销触发回调', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        UndoDeletePill(
          onUndo: () => tapped = true,
          fontSizeStep: 0,
          dockLeft: false,
        ),
      ),
    );

    expect(find.text('已删除'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.text('撤销'));
    expect(tapped, isTrue);
  });

  testWidgets('字号随面板字体档位缩放', (tester) async {
    await tester.pumpWidget(
      _wrap(UndoDeletePill(onUndo: () {}, fontSizeStep: 2, dockLeft: false)),
    );
    final text = tester.widget<Text>(find.text('已删除'));
    expect(
      text.style!.fontSize,
      OverlayConstants.fontScaled(12, 2),
    );
  });

  testWidgets('胶囊贴停靠缘：停靠右缘→centerRight，停靠左缘→centerLeft', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(UndoDeletePill(onUndo: () {}, fontSizeStep: 0, dockLeft: false)),
    );
    var align = tester.widget<Align>(
      find.ancestor(of: find.text('已删除'), matching: find.byType(Align)),
    );
    expect(align.alignment, Alignment.centerRight);

    await tester.pumpWidget(
      _wrap(UndoDeletePill(onUndo: () {}, fontSizeStep: 0, dockLeft: true)),
    );
    align = tester.widget<Align>(
      find.ancestor(of: find.text('已删除'), matching: find.byType(Align)),
    );
    expect(align.alignment, Alignment.centerLeft);
  });
}
