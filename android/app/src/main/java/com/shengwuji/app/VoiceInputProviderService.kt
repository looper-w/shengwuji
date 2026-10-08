package com.shengwuji.app

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * fcitx5-android 外接语音输入 Provider（AIDL 桥接）。
 *
 * 职责链路：
 *   fcitx IME 录音 --Binder/AIDL--> 本 Service --MethodChannel--> headless FlutterEngine
 *   （voiceProviderMain 入口：VAD 切段 + SenseVoice 转写 + 热词纠错）
 *   --segmentFinal--> 本 Service --AIDL--> fcitx IME 上屏
 *
 * 协议文档见 fcitx5-android 仓库根目录 ASR_VOICE_INPUT_AIDL_INTEGRATION.md。
 * AIDL 接口文件在 src/main/aidl/org/fcitx/fcitx5/android/common/ipc/（包名即
 * Binder descriptor，禁止改动）。
 *
 * 线程模型：所有 Binder 方法跑在 Binder 线程池，涉及 Flutter 引擎 / MethodChannel /
 * 会话状态的操作一律 post 到主线程；RMS 电平计算廉价，直接在 Binder 线程回传。
 * Dart 侧 'ready' 握手前不回 onReady——fcitx 侧有预滚缓冲 + 12s 超时兜底，
 * 模型冷加载期间用户说的话最多保留最近 3 秒，不会崩会话。
 *
 * 内存策略（2026-09-25 与用户对齐）：引擎只在真正有语音会话时拉起；
 * fcitx 每次键盘弹出的 keepalive 预热（bind → isAvailable → 2s 解绑）不触发
 * 加载——那个机制是为"解绑后仍能继续后台加载"的 Provider 设计的，本服务
 * 绑定解除即被销毁，预热只会白烧 CPU/IO。会话结束后引擎再保温 90s
 * （覆盖 fcitx 的连续输入间隔），之后即便 fcitx 还持有绑定也主动销毁
 * FlutterEngine 释放模型内存；下一次长按空格重新冷加载，由预滚兜底。
 */
class VoiceInputProviderService : Service() {

    companion object {
        private const val TAG = "ShengwujiVoiceProvider"
        private const val CHANNEL = "shengwuji/voice_provider"
        private const val ENTRYPOINT = "voiceProviderMain"

        // 与 fcitx VoiceInputIpc.ConfigKeys / ErrorCodes 对齐的本地副本
        private const val KEY_SAMPLE_RATE = "sampleRate"
        private const val KEY_BITS_PER_SAMPLE = "bitsPerSample"
        private const val KEY_CHANNELS = "channels"
        private const val KEY_SILENCE_MS = "silenceMs"
        private const val KEY_LANGUAGE = "language"
        private const val ERR_UNKNOWN = 0
        private const val ERR_MODEL_LOAD_FAILED = 2

        private const val PREF_SAMPLE_RATE = 16000
        private const val PREF_BITS_PER_SAMPLE = 16
        private const val PREF_CHANNELS = 1
        // Silero VAD minSilenceDuration = 0.6s，与 Dart 侧配置一致
        private const val PREF_SILENCE_MS = 600L

        // 会话结束后引擎保温时长：覆盖"说完一句停顿几秒再说"的连续输入间隔，
        // 又不至长期占内存（fcitx 侧保温绑定是 5 分钟，这里主动提前释放）
        private const val IDLE_ENGINE_RELEASE_MS = 90_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var engine: FlutterEngine? = null
    private var dartChannel: MethodChannel? = null

    /** Binder 侧会话回调（startSession 传入） */
    @Volatile private var callback: android.os.IInterface? = null

    // ---- 会话状态（除 sessionOpen 供 Binder 线程读外，仅主线程读写）----
    @Volatile private var sessionOpen = false
    private var engineReady = false // Dart 已报告模型加载完成
    private var readySent = false // 本会话已回 onReady
    private var sessionEndedSent = false // 本会话已回 onSessionEnded
    private var sessionSampleRate = PREF_SAMPLE_RATE
    private var sessionSilenceMs = PREF_SILENCE_MS
    private var sessionLanguage: String? = null

    /** 空闲释放代次：新会话开启时自增，使已排队的释放回调过期失效 */
    private var idleReleaseGeneration = 0

    private val binder = object : org.fcitx.fcitx5.android.common.ipc.IVoiceInputProvider.Stub() {

        override fun isAvailable(): Boolean {
            // 只报可用性，不预热引擎：fcitx 每次键盘弹出都会 bind + isAvailable
            // + 约 2s 后解绑，绑定解除服务即被销毁，预热加载必然中途夭折，
            // 只剩空转。真正的引擎拉起推迟到 startSession（预滚缓冲兜住冷加载）。
            return true
        }

        override fun getPreferredConfig(): Bundle = Bundle().apply {
            putInt(KEY_SAMPLE_RATE, PREF_SAMPLE_RATE)
            putInt(KEY_BITS_PER_SAMPLE, PREF_BITS_PER_SAMPLE)
            putInt(KEY_CHANNELS, PREF_CHANNELS)
            putLong(KEY_SILENCE_MS, PREF_SILENCE_MS)
        }

        override fun configure(params: Bundle?) {
            if (params == null) return
            params.classLoader = VoiceInputProviderService::class.java.classLoader
            val rate = params.getInt(KEY_SAMPLE_RATE, PREF_SAMPLE_RATE)
            val silence = params.getLong(KEY_SILENCE_MS, PREF_SILENCE_MS)
            val language = params.getString(KEY_LANGUAGE)
            mainHandler.post {
                if (rate > 0) sessionSampleRate = rate
                if (silence > 0) sessionSilenceMs = silence
                sessionLanguage = language
                println("🎙️ [$TAG] configure rate=$rate silence=$silence lang=$language")
            }
        }

        override fun startSession(cb: org.fcitx.fcitx5.android.common.ipc.IVoiceInputCallback?) {
            mainHandler.post {
                callback = cb
                sessionOpen = true
                readySent = false
                sessionEndedSent = false
                cancelIdleEngineRelease()
                println("🎙️ [$TAG] startSession")
                ensureEngine()
                maybeAnnounceReady()
            }
        }

        override fun feedAudio(pcm: ByteArray?, offset: Int, len: Int, ptsMs: Long) {
            if (pcm == null || len <= 0 || offset < 0 || offset + len > pcm.size) return
            val cb = callback as? org.fcitx.fcitx5.android.common.ipc.IVoiceInputCallback
            if (cb != null && sessionOpen) {
                try {
                    cb.onVolumeLevel(rmsOf(pcm, offset, len))
                } catch (_: Throwable) {
                }
            }
            val chunk = pcm.copyOfRange(offset, offset + len)
            mainHandler.post {
                if (!sessionOpen) return@post
                dartChannel?.invokeMethod("feed", chunk)
            }
        }

        override fun endStream() {
            println("🎙️ [$TAG] endStream")
            mainHandler.post {
                if (!sessionOpen) return@post
                // Dart 收尾后会回 'sessionEnded'，由 onDartSessionEnded 统一回传
                runCatching { dartChannel?.invokeMethod("endStream", null) }
                    .onFailure {
                        println("⚠️ [$TAG] endStream 通知 Dart 失败: ${it.message}")
                        sendSessionEnded()
                    }
            }
        }

        override fun cancelSession() {
            println("🎙️ [$TAG] cancelSession")
            mainHandler.post { teardownSession(notifyDart = true) }
        }

        override fun stopSession() {
            println("🎙️ [$TAG] stopSession")
            mainHandler.post { teardownSession(notifyDart = true) }
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        println("🎙️ [$TAG] service created")
    }

    override fun onDestroy() {
        println("🎙️ [$TAG] service destroyed")
        mainHandler.removeCallbacksAndMessages(null)
        sessionOpen = false
        callback = null
        dartChannel?.setMethodCallHandler(null)
        dartChannel = null
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    // ================================================================
    // Flutter 引擎管理
    // ================================================================

    /**
     * 拉起 headless FlutterEngine（主线程调用，startSession 时）。引擎创建后跨
     * 会话复用：会话结束保温 [IDLE_ENGINE_RELEASE_MS] 后主动销毁释放模型内存
     * （即便 fcitx 还持有 5 分钟保温绑定），Service 存活期间下一次会话重新冷起；
     * unbind → onDestroy 时也在这里兜底销毁。
     */
    private fun ensureEngine() {
        if (engine != null) return
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, emptyArray())
            val newEngine = FlutterEngine(applicationContext)
            val channel = MethodChannel(newEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler { call, result -> onDartCall(call, result) }
            dartChannel = channel
            val entryPoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                ENTRYPOINT,
            )
            newEngine.dartExecutor.executeDartEntrypoint(entryPoint)
            engine = newEngine
            engineReady = false
            println("✅ [$TAG] provider engine started, entry=$ENTRYPOINT")
        } catch (e: Throwable) {
            println("❌ [$TAG] provider engine 启动失败: ${e.message}")
            engine = null
            dartChannel = null
            engineReady = false
            val cb = callback as? org.fcitx.fcitx5.android.common.ipc.IVoiceInputCallback
            try {
                cb?.onError(ERR_UNKNOWN, "provider engine failed: ${e.message}")
            } catch (_: Throwable) {
            }
            teardownSession(notifyDart = false)
        }
    }

    /** Dart → Kotlin 消息（主线程） */
    private fun onDartCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                engineReady = true
                println("✅ [$TAG] dart ready (model loaded)")
                maybeAnnounceReady()
                result.success(null)
            }
            "segmentFinal" -> {
                val text = call.arguments as? String
                if (!text.isNullOrBlank() && sessionOpen) {
                    val cb = callback as? org.fcitx.fcitx5.android.common.ipc.IVoiceInputCallback
                    try {
                        cb?.onSegmentFinal(text)
                    } catch (e: Throwable) {
                        println("⚠️ [$TAG] onSegmentFinal 回传失败: ${e.message}")
                    }
                }
                result.success(null)
            }
            "sessionEnded" -> {
                println("🎙️ [$TAG] dart session ended")
                sendSessionEnded()
                result.success(null)
            }
            "error" -> {
                val code = (call.arguments as? Map<*, *>)?.get("code") as? Int ?: ERR_UNKNOWN
                val message =
                    (call.arguments as? Map<*, *>)?.get("message") as? String ?: "unknown error"
                println("❌ [$TAG] dart error code=$code msg=$message")
                if (sessionOpen) {
                    val cb = callback as? org.fcitx.fcitx5.android.common.ipc.IVoiceInputCallback
                    try {
                        cb?.onError(code, message)
                    } catch (_: Throwable) {
                    }
                }
                teardownSession(notifyDart = false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ================================================================
    // 会话状态机
    // ================================================================

    /** 引擎就绪 + 会话已开启 ⇒ 通知 Dart 会话参数，再回 onReady（幂等） */
    private fun maybeAnnounceReady() {
        if (!sessionOpen || !engineReady || readySent) return
        readySent = true
        val params = mapOf(
            "sampleRate" to sessionSampleRate,
            "silenceMs" to sessionSilenceMs,
            "language" to sessionLanguage,
        )
        runCatching { dartChannel?.invokeMethod("startSession", params) }
            .onFailure { println("⚠️ [$TAG] startSession 通知 Dart 失败: ${it.message}") }
        val cb = callback as? org.fcitx.fcitx5.android.common.ipc.IVoiceInputCallback
        try {
            cb?.onReady()
            println("✅ [$TAG] onReady sent")
        } catch (e: Throwable) {
            println("⚠️ [$TAG] onReady 回传失败: ${e.message}")
        }
    }

    /** cancel/stop/异常路径：停会话，确保至多一次 onSessionEnded */
    private fun teardownSession(notifyDart: Boolean) {
        val hadSession = sessionOpen
        sessionOpen = false
        if (notifyDart && hadSession) {
            runCatching { dartChannel?.invokeMethod("cancel", null) }
        }
        sendSessionEnded()
        callback = null
    }

    private fun sendSessionEnded() {
        if (!sessionEndedSent) {
            sessionEndedSent = true
            val cb = callback as? org.fcitx.fcitx5.android.common.ipc.IVoiceInputCallback
            try {
                cb?.onSessionEnded()
            } catch (_: Throwable) {
            }
            scheduleIdleEngineRelease()
        }
    }

    // ================================================================
    // 空闲引擎释放
    // ================================================================

    /** 会话彻底结束后排队引擎释放；新会话（startSession）会让本排队失效 */
    private fun scheduleIdleEngineRelease() {
        val generation = ++idleReleaseGeneration
        mainHandler.postDelayed({
            if (generation != idleReleaseGeneration) return@postDelayed
            if (sessionOpen) return@postDelayed
            releaseEngine("idle ${IDLE_ENGINE_RELEASE_MS / 1000}s")
        }, IDLE_ENGINE_RELEASE_MS)
    }

    private fun cancelIdleEngineRelease() {
        idleReleaseGeneration++
    }

    /** 销毁 FlutterEngine（连同 worker isolate 与已加载模型），Service 本身继续存活 */
    private fun releaseEngine(reason: String) {
        val current = engine ?: return
        println("🧹 [$TAG] 释放 provider engine ($reason)")
        dartChannel?.setMethodCallHandler(null)
        dartChannel = null
        current.destroy()
        engine = null
        engineReady = false
    }

    private fun rmsOf(buf: ByteArray, offset: Int, len: Int): Int {
        if (len < 2) return 0
        val count = len / 2
        var sumSq = 0.0
        var i = offset
        val end = offset + len - 1
        while (i < end) {
            val lo = buf[i].toInt() and 0xff
            val hi = buf[i + 1].toInt()
            val s = (hi shl 8) or lo
            sumSq += (s * s).toDouble()
            i += 2
        }
        return kotlin.math.sqrt(sumSq / count).toInt().coerceIn(0, 32767)
    }
}
