package com.shengwuji.app

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.view.WindowManager

/**
 * 设备诊断信息采集（2026-09-26，悬浮窗「滑动收起后把手/竖线不出现」终端用户
 * 反馈不可复现，发诊断包收集日志定位用——怀疑 ROM/屏幕/导航模式/无障碍冲突）。
 *
 * 双 engine 共用（同 MediaMuteHelper 先例）：主 App（MainActivity 通道
 * com.shengwuji.app/app）与悬浮窗 engine（无障碍 Service 通道
 * com.shengwuji.app/accessibility_overlay）各传自己的 Context。
 *
 * 采集纪律：只采**非敏感、诊断必需**的字段——品牌/型号/处理器平台、Android
 * 与 ROM 版本、屏幕分辨率/密度/刷新率、导航模式、权限快照、已启用无障碍服务
 * 列表（冲突检测：李跳跳/自动点击器等会抢按键事件或画悬浮层，能直接解释
 * 「手势被吞」）。**刻意不采** IMEI/Android ID/序列号/MAC/已安装应用列表。
 * 结果只经 Dart log() 进本地运行日志（用户手动导出分享），不联网。
 */
object DeviceDiagnostics {

    fun collect(context: Context): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()

        // ── 品牌/型号/处理器平台（判断 ROM 特有问题的第一眼信息）──
        map["manufacturer"] = Build.MANUFACTURER
        map["brand"] = Build.BRAND
        map["model"] = Build.MODEL
        map["device"] = Build.DEVICE
        map["hardware"] = Build.HARDWARE
        map["abis"] = Build.SUPPORTED_ABIS.toList()

        // ── 系统/ROM 版本：DISPLAY 常含 MIUI/HyperOS/EMUI 等 ROM 构建串 ──
        map["androidRelease"] = Build.VERSION.RELEASE
        map["sdkInt"] = Build.VERSION.SDK_INT
        map["displayId"] = Build.DISPLAY
        map["miuiVersion"] = readSystemProperty("ro.miui.ui.version.name")

        // ── 屏幕：分辨率/密度/刷新率（刷新率与 vsync 相关——面板滑出动画的
        // dismissed 回调节奏依赖它，悬浮窗纹理重投影问题也可能有刷新率特征）──
        try {
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            if (Build.VERSION.SDK_INT >= 30) {
                val metrics = wm.currentWindowMetrics
                val bounds = metrics.bounds
                map["screenWidthPx"] = bounds.width()
                map["screenHeightPx"] = bounds.height()
            } else {
                @Suppress("DEPRECATION")
                val dm = android.util.DisplayMetrics()
                @Suppress("DEPRECATION")
                wm.defaultDisplay.getRealMetrics(dm)
                map["screenWidthPx"] = dm.widthPixels
                map["screenHeightPx"] = dm.heightPixels
            }
            @Suppress("DEPRECATION")
            map["refreshRate"] = wm.defaultDisplay?.refreshRate
        } catch (_: Exception) {
            // 屏幕信息拿不到不阻塞其余字段
        }
        map["densityDpi"] = context.resources.displayMetrics.densityDpi
        map["density"] = context.resources.displayMetrics.density

        // ── 导航模式（2=手势导航）：贴边竖线/把手就在系统手势区里，强相关 ──
        map["navigationMode"] = try {
            Settings.Secure.getInt(context.contentResolver, "navigation_mode")
        } catch (_: Exception) {
            -1
        }

        // ── 权限快照：悬浮窗权限本链路不需要（TYPE_ACCESSIBILITY_OVERLAY 系统
        // 放行），但记录其状态可排除「用户开了别家悬浮窗权限/别家悬浮窗在场」的
        // 干扰排查方向；麦克风/通知影响录音与前台服务保活 ──
        map["canDrawOverlays"] = Settings.canDrawOverlays(context)
        map["micGranted"] = context.checkSelfPermission(
            android.Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        map["notifGranted"] = if (Build.VERSION.SDK_INT >= 33) {
            context.checkSelfPermission(
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        // ── 已启用的无障碍服务列表（最有价值的冲突检测）：其他无障碍服务会
        // 抢音量键事件（filterKeyEvents）或自行画悬浮层。读 Settings.Secure
        // 无需权限。只保留 包名/服务类名 形态，已是系统脱敏后的组件串 ──
        map["enabledAccessibilityServices"] = try {
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""
        } catch (_: Exception) {
            ""
        }

        return map
    }

    /** 反射读 build.prop（MIUI 版本号等）；读不到返回空串，不抛异常 */
    private fun readSystemProperty(key: String): String {
        return try {
            val clazz = Class.forName("android.os.SystemProperties")
            val method = clazz.getMethod("get", String::class.java)
            (method.invoke(null, key) as? String).orEmpty()
        } catch (_: Exception) {
            ""
        }
    }
}
