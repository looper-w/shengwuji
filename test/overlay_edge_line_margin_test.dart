import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/overlay/overlay_constants.dart';

/// 竖线距屏幕边缘内移间距档位回归（2026-09-29，用户反馈：贴带黑边的钢化膜
/// 后完全贴边的竖线可能被膜边遮住看不见）——三档 0（贴边，历史行为）/ 4 /
/// 8（最里；首版 0/8/16 的 16 档用户实测内移过多，整体下调）。纯 Dart 视觉
/// 内移：窗口 20×64 与透明触摸缓冲区不动，竖线在窗口内向屏内侧偏移；⚠️ 窗口
/// 内硬上限 16 = 窗口宽 20 − 线宽 4，不靠加宽窗口换更大间距（窗口宽 >24 会撞
/// Kotlin EDGE_LINE_WIDTH_THRESHOLD_DP=24 的线态判定）
void main() {
  group('档位解析（纯函数）', () {
    test('parseEdgeLineMargin：合法档原样，null/坏值兜底贴边 0', () {
      expect(OverlayConstants.parseEdgeLineMargin(null), 0);
      expect(OverlayConstants.parseEdgeLineMargin(0), 0);
      expect(OverlayConstants.parseEdgeLineMargin(4), 4);
      expect(OverlayConstants.parseEdgeLineMargin(8), 8);
      // 非法档兜底：集合外任意 int（含首版旧档位 16）一律回落贴边（历史行为）
      expect(OverlayConstants.parseEdgeLineMargin(2), 0);
      expect(OverlayConstants.parseEdgeLineMargin(16), 0);
      expect(OverlayConstants.parseEdgeLineMargin(-4), 0);
    });

    test('edgeLinePadding：内边距落在停靠侧（右缘=right，左缘=left 镜像）', () {
      final right = OverlayConstants.edgeLinePadding(
        sideLeft: false,
        marginDp: 4,
      );
      expect(right, const EdgeInsets.only(right: 4));
      final left = OverlayConstants.edgeLinePadding(
        sideLeft: true,
        marginDp: 8,
      );
      expect(left, const EdgeInsets.only(left: 8));
      // 贴边档 = 零内边距（历史行为不变）
      expect(
        OverlayConstants.edgeLinePadding(sideLeft: false, marginDp: 0),
        EdgeInsets.zero,
      );
    });

    test('不变量：最大档位 + 线宽 ≤ 窗口宽（竖线恒在窗口内，不越界裁剪）', () {
      final maxMargin = OverlayConstants.edgeLineMarginChoices.last;
      expect(
        maxMargin + OverlayConstants.edgeLineWidth,
        lessThanOrEqualTo(OverlayConstants.edgeLineWindowWidth),
      );
      // 窗口宽不随档位加宽（撞 Kotlin 线态宽度阈值 24 的防线）
      expect(OverlayConstants.edgeLineWindowWidth, lessThanOrEqualTo(24));
    });
  });
}
