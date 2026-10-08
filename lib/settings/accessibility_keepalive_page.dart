import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme_extension.dart';
import 'accessibility_check.dart';
import 'settings_widgets.dart';

/// 「无障碍保活指南」三级页（音量键快捷操作 → 顶部入口进入）
///
/// 背景：音量键手势依赖无障碍服务常驻后台，但国产 ROM（小米/华为/OPPO/vivo
/// 等）的省电策略会自动杀后台并顺手关闭无障碍服务，用户感知为「音量键长按
/// 没反应」。本页给出一套逐项自查清单；页面纯说明无状态，唯一的动作是底部
/// 按钮复用 [openAccessibilitySettings] 直达系统无障碍设置。
class AccessibilityKeepAlivePage extends StatelessWidget {
  const AccessibilityKeepAlivePage({super.key});

  static const _steps = [
    (
      Icons.play_circle_outline,
      '开启「自启动」',
      '系统设置 → 应用管理 → 声物记 → 打开「自启动」。'
          '部分手机叫「自动管理」，需改为「手动管理」后勾选「允许自启动」',
    ),
    (
      Icons.lock_outline,
      '在最近任务里「锁定」本应用',
      '打开多任务（最近任务）界面，找到声物记卡片，下拉卡片或点小锁图标加锁。'
          '加锁后系统一键清理后台不会杀掉它',
    ),
    (
      Icons.battery_saver_outlined,
      '电池策略设为「无限制」',
      '系统设置 → 应用 → 声物记 → 耗电管理（或「电池用量」）→ 选择「无限制」/「不优化」，'
          '并允许后台活动',
    ),
    (
      Icons.open_in_new,
      '允许「后台弹出界面」',
      '小米 MIUI/澎湃等系统需在应用权限管理里单独允许「后台弹出界面」，'
          '音量键手势才能拉起录音或悬浮窗',
    ),
    (
      Icons.lock_clock_outlined,
      '允许「锁屏显示」',
      '锁屏状态下按音量键需要拉起 App 时，在应用管理中允许「锁屏显示」/「在锁屏上显示」',
    ),
    (
      Icons.accessibility_new,
      '重新开启无障碍服务',
      '完成以上设置后，回到无障碍设置把「声物记」关掉再重新打开一次，让它在干净的进程里常驻',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ext = AppThemeExtension.of(context);
    return Scaffold(
      backgroundColor: ext.scaffoldBackground,
      appBar: AppBar(
        title: Text(
          '音量键失灵排查',
          style: TextStyle(color: ext.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: ext.isDarkOverlay
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SettingsCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: ext.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '音量键手势依赖无障碍服务常驻后台。部分手机的省电策略会自动清理后台、'
                    '顺带把无障碍服务关掉，表现为「长按/双击音量键没反应」。'
                    '按下面的清单逐项设置，可以大幅降低被系统关闭的概率',
                    style: TextStyle(
                      color: ext.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SettingsSectionTitle('逐项自查清单'),
          SettingsCard(
            child: Column(
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _buildStep(context, i + 1, _steps[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SettingsSectionTitle('还是不行？'),
          SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '各家手机系统的设置入口和叫法差异很大，上面只是常见名称。',
                  style: TextStyle(
                    color: ext.textSecondary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '建议在浏览器搜索「无障碍服务 保活 + 手机品牌」，'
                  '例如「无障碍服务 小米 保活」，按图文教程逐项对照设置',
                  style: TextStyle(
                    color: ext.textPrimary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: openAccessibilitySettings,
            icon: const Icon(Icons.launch, size: 20),
            label: const Text(
              '前往无障碍设置',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: ext.primary,
              foregroundColor: ext.textOnPrimary,
              elevation: 0,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '设置完成后，回到无障碍设置确认「声物记」处于开启状态',
            style: TextStyle(color: ext.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// 单条自查步骤：序号圆点 + 图标 + 标题 + 说明（纯展示，无跳转——
  /// 各家 ROM 路径差异大，深链跳不准反而误导，用文字描述让用户对照找）
  Widget _buildStep(
    BuildContext context,
    int index,
    (IconData, String, String) step,
  ) {
    final ext = AppThemeExtension.of(context);
    final (icon, title, description) = step;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: ext.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
              color: ext.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: ext.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: ext.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(
                  color: ext.textSecondary,
                  fontSize: 12,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
