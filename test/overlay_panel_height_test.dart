import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/overlay/overlay_constants.dart';

/// 悬浮窗「面板高度」可见条数档位回归（2026-10-06，用户需求：大屏手机单手
/// 拿时面板顶部的新建/展开按钮够不着）：prefs overlay_panel_max_cards ∈
/// [6,10]（连续刻度 clamp 语义同 fontSizeStep），默认 10 = 历史行为。
/// 核心设计：面板是顶部锚定布局，只缩列表限高只会让底边上移、顶部按钮
/// 原地不动；必须配上顶部下压偏移（每少 1 条下压一张卡高）才兑现
/// 「整列底边位置不变、顶部按钮组下移进拇指区」。
/// 同日修正差一条：ListView padding 只计入滚动范围不裁剪视口，限高把底部
/// padding 48 也算进去会让第 N+1 张卡完整露出（真机 10 档见 11 张）——
/// 限高只加顶部 padding 8，视口卡片可见区恰好 N 张。
void main() {
  group('档位解析（纯函数）', () {
    test('parsePanelMaxCards：null/缺失兜底默认档 10', () {
      expect(OverlayConstants.parsePanelMaxCards(null), 10);
      expect(OverlayConstants.panelMaxCardsDefault, 10);
      // 默认档 = maxVisibleDiaryCards（历史固定行为的唯一真值）
      expect(
        OverlayConstants.panelMaxCardsDefault,
        OverlayConstants.maxVisibleDiaryCards,
      );
    });

    test('parsePanelMaxCards：合法档位原样通过', () {
      for (final cards in [6, 7, 8, 9, 10]) {
        expect(OverlayConstants.parsePanelMaxCards(cards), cards);
      }
    });

    test('parsePanelMaxCards：越界脏值 clamp 到 [6,10]（连续刻度语义）', () {
      expect(OverlayConstants.parsePanelMaxCards(5), 6);
      expect(OverlayConstants.parsePanelMaxCards(0), 6);
      expect(OverlayConstants.parsePanelMaxCards(-3), 6);
      expect(OverlayConstants.parsePanelMaxCards(11), 10);
      expect(OverlayConstants.parsePanelMaxCards(99), 10);
    });
  });

  group('限高与下压偏移（纯函数）', () {
    test('默认档限高 == panelListMaxHeight（历史行为不变量）', () {
      expect(
        OverlayConstants.panelListMaxHeightFor(
          OverlayConstants.panelMaxCardsDefault,
        ),
        OverlayConstants.panelListMaxHeight,
      );
    });

    test('限高随条数严格递减，档差 = 一张卡高（卡片高+间距）', () {
      final perCard =
          OverlayConstants.cardHeight + OverlayConstants.cardSpacing;
      for (var cards = 6; cards < 10; cards++) {
        expect(
          OverlayConstants.panelListMaxHeightFor(cards + 1) -
              OverlayConstants.panelListMaxHeightFor(cards),
          perCard,
        );
      }
    });

    test('默认档下压偏移为 0，每少 1 条下压一张卡高', () {
      final perCard =
          OverlayConstants.cardHeight + OverlayConstants.cardSpacing;
      expect(OverlayConstants.panelTopOffsetFor(10), 0.0);
      expect(OverlayConstants.panelTopOffsetFor(9), perCard);
      expect(OverlayConstants.panelTopOffsetFor(6), 4 * perCard);
    });

    test('设计不变量：任意档位「下压偏移 + 限高」为定值（满列表底边不动）', () {
      final expected =
          OverlayConstants.panelTopOffsetFor(10) +
          OverlayConstants.panelListMaxHeightFor(10);
      for (final cards in [6, 7, 8, 9, 10]) {
        expect(
          OverlayConstants.panelTopOffsetFor(cards) +
              OverlayConstants.panelListMaxHeightFor(cards),
          expected,
        );
      }
    });

    test('最低档 6 条仍保有可滚动的列表区（限高 > 3 张卡高）', () {
      final perCard =
          OverlayConstants.cardHeight + OverlayConstants.cardSpacing;
      expect(
        OverlayConstants.panelListMaxHeightFor(
          OverlayConstants.panelMaxCardsMin,
        ),
        greaterThan(3 * perCard),
      );
    });

    test('视口卡片可见区恰好 N 张（限高只加顶部 padding 8，不含底部 48）', () {
      // ListView/SliverPadding 的 padding 只计入滚动范围不裁剪视口——滚动到
      // 顶时视口内卡片可见区 = 限高 − top padding（8），底部 padding 48 要到
      // 滚到底才出现。若把 48 也算进限高，可见区多出 48 > 卡高 46，第 N+1 张
      // 卡完整露出（真机实测 10 档见 11 张 / 6 档见 7 张的差一条）
      final perCard =
          OverlayConstants.cardHeight + OverlayConstants.cardSpacing;
      for (final cards in [6, 7, 8, 9, 10]) {
        // 可见区 = N×(卡高+间距)：第 N 张（含其底部间距）恰好贴视口底缘，
        // 第 N+1 张 0 像素可见
        expect(
          OverlayConstants.panelListMaxHeightFor(cards) - 8,
          cards * perCard,
        );
      }
    });
  });

  group('主 App 大爆炸层顶边（按悬浮窗 8 条档位取值，用户拍板）', () {
    test('参照条数档 = 8，顶边 = 状态栏避让 + 8 条档下压偏移', () {
      expect(OverlayConstants.bigBangMainAppRefCards, 8);
      expect(
        OverlayConstants.bigBangMainAppTopInset,
        OverlayConstants.panelHeaderTopPadding +
            OverlayConstants.panelTopOffsetFor(8),
      );
      // 数值钉死：40 + (10−8)×(46+10) = 152——与悬浮窗 8 条档位的大爆炸层
      // 顶边同值，改任一同源常量此处会红提示对账
      expect(OverlayConstants.bigBangMainAppTopInset, 152.0);
    });
  });
}
