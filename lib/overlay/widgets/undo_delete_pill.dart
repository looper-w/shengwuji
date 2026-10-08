import 'package:flutter/material.dart';
import '../overlay_constants.dart';

/// 滑动删除撤销胶囊：「滑动直接删除」开启后，活跃卡划走删除时贴在面板
/// header 下方的提示条（黑 72% 半透明底 + 白字，与 OverlayPanelHeader /
/// _StopHintPill / ProLockedHintPill 同视觉家族，跨背景对比度已验证）。
///
/// 生命周期由 OverlayHome 的待撤销槽位驱动：删除即出现，
/// OverlayConstants.swipeDeleteUndoWindow 到期/面板收起/窗口移除时随槽位
/// 落定消失（消失即删除落定，不可再撤销）。
class UndoDeletePill extends StatelessWidget {
  /// 点击「撤销」回调（OverlayHome._undoSwipeDelete）
  final VoidCallback onUndo;

  /// 面板字体档位（-2~+2，随设置页「字体大小」缩放，与面板文字同源）
  final int fontSizeStep;

  /// 面板停靠侧（true=屏幕左缘）：胶囊贴停靠缘便于单手点撤销——
  /// 停靠右缘时胶囊贴面板右端（屏幕右缘拇指区），停靠左缘镜像。
  /// 与 OverlayPanelHeader 的 dockLeft 镜像规则同款
  final bool dockLeft;

  const UndoDeletePill({
    super.key,
    required this.onUndo,
    required this.fontSizeStep,
    required this.dockLeft,
  });

  double _fs(double base) => OverlayConstants.fontScaled(base, fontSizeStep);

  @override
  Widget build(BuildContext context) {
    // Align 在面板宽度约束内撑满（widthFactor=null），Row.min 收缩到内容宽，
    // Align 决定贴哪侧——与录音胶囊/工具条 Align.centerRight/centerLeft 同款
    return Align(
      alignment: dockLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        // 与卡片左右 margin 对齐（卡片 margin horizontal 14）
        padding: const EdgeInsets.only(left: 14, right: 14, top: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete_outline,
                size: _fs(14),
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                '已删除',
                style: TextStyle(
                  fontSize: _fs(12),
                  height: 1.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUndo,
                child: Padding(
                  // 撤销按钮加大命中区（胶囊内文字按钮偏小）
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    '撤销',
                    style: TextStyle(
                      fontSize: _fs(12),
                      height: 1.2,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
