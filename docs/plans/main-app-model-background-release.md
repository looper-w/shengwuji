# 计划：主 App 识别引擎「退后台释放」+ 悬浮窗式并行加载

> 目标读者：下一个开发会话。本计划自包含，动手前请先通读"背景事实"，再按"改动清单"执行。
> 项目：声物记（S:\CodeProject\my_first_app，Flutter，包名 com.shengwuji.app）
> 日期：2026-09-25 · 来源：与用户对齐的内存优化方案（对话纪要见文末"决策记录"）

## 目标

主 App 那份 SenseVoice 模型内存不再常驻：App 退后台后延迟释放识别引擎；回到前台后
首次录音用"悬浮窗同款"并行加载把冷加载耗时藏进说话时间，避免出现可感知的等待。

预期效果：对"悬浮窗 + 输入法为主"的用户，稳态任意时刻通常只有一份模型在内存
（悬浮窗已有 120s idle 释放；输入法 Provider 已有 90s idle 释放，本轮均不动）。

## 背景事实（新会话必读）

1. **三副本格局**：主 App、悬浮窗、输入法 Provider 是三个独立 FlutterEngine
   （同进程 com.shengwuji.app，三个 isolate 组），模型各自加载、内存不共享。
2. **悬浮窗参照实现**（照抄对象）：`lib/overlay/overlay_voice_memo.dart`
   - 开录时并行预热（约 345 行附近，注释"懒启动识别 worker（录音期间预热模型，
     与录音并行）"）：`await RecognizerSingleton.preloadModelPath();` 然后
     `unawaited(RecognizerSingleton.instance.initialize())`，**不 await、不阻塞开录**；
   - 转写处兜底（约 558-561 行）：`await RecognizerSingleton.instance.initialize()`
     ——RecognitionService.initialize 内部对并发调用做归并（_spawnCompleter），
     不会 double spawn，这是现成保证，照抄即可；
   - 转写收尾后排定 idle 释放（`_scheduleWorkerIdleRelease`，约 683 行起）：
     Timer 120s（`OverlayConstants.voiceMemoWorkerIdleSeconds`）→
     `RecognizerSingleton.instance.dispose()`；新录音 start 时取消计时。
3. **RecognizerSingleton 释放语义**（`lib/recognizer_singleton.dart`）：
   `dispose()` 会销毁 worker isolate 并重建内部 `_service` 实例，之后可再次
   `initialize()`——悬浮窗已长期依赖此行为，主 App 照用无需改门面。
   ⚠️ dispose 会把 `_currentModelPath` 置 null：**每次重新加载前必须先
   `preloadModelPath()`**（悬浮窗 start() 每次都先调它，主 App 抄的时候别漏）。
4. **主 App 现状**：
   - 启动页不加载模型（`splash_screen.dart` `_finishInit` 注释"启动时不加载模型
     （延迟加载）"），首次录音才加载——但**加载后永不释放**；
   - 各录音入口在录音前 `await initialize()`（阻塞，冷加载 1~1.5s 用户可见），
     锚点：`record_tab.dart:342`（refreshEngine，普通录音）、`record_tab.dart:866`
     （搬家模式入口，有"正在初始化..."状态条）、`diary_tab.dart:1524`（refreshEngine）、
     `list_tab.dart:124`（物品页语音查询）；
   - 日记"再次转写"：`diary_tab.dart` `_retranscribeDiary`（约 2396 行）→
     `_recognizerManager.transcribe`（约 2119 行），**没有 initialize 前置守卫，
     释放后调用会抛 StateError——必须补兜底**；
   - 生命周期观察者现成：`main.dart` `_MainScaffoldState.didChangeAppLifecycleState`
     （约 374 行，已有后台重置快捷方式标志的逻辑，在此扩展）；
   - record_tab 录音 PCM 本就先进 `_audioBuffer`（约 416 行），停止后才转写——
     结构上天然适合"开录不等模型"。

## 改动清单

### 第 1 步：主 App 全局「在途识别」计数器（防误杀）

新建轻量全局计数（建议放 `lib/utils/` 新文件，如 `recognition_activity.dart`，
static int + begin/end 两个方法）：
- record_tab / diary_tab / list_tab 每处 transcribe 前后（含 _retranscribeDiary）
  begin/end 计数；
- 释放守卫用它：计数 > 0 时**不释放**（转写完成后自然走到下一轮守卫，见第 2 步）。

### 第 2 步：退后台释放（main.dart）

在 `_MainScaffoldState.didChangeAppLifecycleState` 扩展：
- `paused/hidden`：启动一个延迟 Timer（建议 8s，给在途转写留收尾时间）；
- Timer 到点时守卫：App 仍在后台（state 未回 resumed）&& 在途识别计数 == 0 &&
  `RecognizerSingleton.instance.isReady` → 打日志 +
  `RecognizerSingleton.instance.dispose()`；
- 计数 > 0 时顺延：重新排 Timer（简单做法：10s 后再查一轮，兜底上限 3 轮防死循环）；
- `resumed`：取消待释放 Timer（不主动加载，懒加载守卫自然兜）。

### 第 3 步：并行加载（照抄悬浮窗，逐入口改造）

对下列入口，把"先 await initialize 再开录"改为"先开录 +
`preloadModelPath()` + `unawaited(initialize())`"，转写处统一加
`await initialize()` 兜底（归并语义保证安全）：
1. `record_tab.dart` 普通录音（refreshEngine 路径，342 行一带）；
2. `record_tab.dart` 搬家模式（866 行一带；"正在初始化..."状态条保留作兜底，
   正常情况下不再出现）；
3. `diary_tab.dart` 录音（1524 行一带）；
4. `list_tab.dart` 语音查询（124 行；此入口没有"说话时间"可蹭——查询前先等模型？
   简单处理：保留 await（查询本来就有 loading 态），只加"未就绪才 await"守卫即可，
   不强行并行）；
5. `diary_tab.dart` `_retranscribeDiary`：开头补
   `preloadModelPath() + await initialize()`（无录音时间可蹭，必须阻塞等）。

⚠️ 改造后每个入口都要能走通"冷启动（worker 不存在）→ 开录 → 转写"全链路。

### 第 4 步：验证与构建

- `flutter analyze --no-pub` 无新增告警；
- 真机/模拟器验收清单（见下）；
- `flutter build apk --target-platform android-arm64 --split-per-abi` 出包。

## 验收清单

1. 主 App 录一条音 → 退后台 10s → logcat 出现释放日志（实现时打统一前缀，
   建议 `[BackgroundRelease]`）→ `adb shell dumpsys meminfo com.shengwuji.app`
   内存回落（int8 模型 229MB + 运行时开销，应看到两三百 MB 量级的下降）；
2. 退后台 5s 内回前台 → 模型未释放（Timer 被取消）；
3. 退后台时正在转写 → 转写正常完成、不崩，完成后下一轮守卫才释放；
4. 释放后回 App 点录音：**开录立即开始**（无 1.5s 等待），说完照常出字
   （加载被说话时间盖住）；录 1 秒超短句时停止后稍有延迟属预期（兜底 await）；
5. 搬家模式不受影响（常亮不退后台；入口并行化后"正在初始化..."基本不出现）；
6. 悬浮窗速记、输入法语音（长按空格）回归正常——本轮零改动，但构建后必须过一遍；
7. 日记"再次转写"在释放后的状态下可正常工作（先阻塞加载再转写）。

## 明确不做（已与用户对齐）

- ❌ 跨引擎共享同一份模型：三个 isolate 堆不互通，FFI 句柄不能跨引擎传递；
  真共享需把识别+热词+纠错整条管线下沉 native，工程量不成比例；
- ❌ 悬浮窗 120s idle 释放机制、输入法 Provider 90s idle 释放机制：本轮零改动；
- ❌ 输入法侧（S:\CodeProject\fcitx5-android）零改动。

## 决策记录（2026-09-25 与用户对话）

- 用户重度使用悬浮窗 + 输入法，主 App 那份模型常驻是浪费 → 做退后台释放；
- 用户点名"照抄悬浮窗"：并行加载藏冷加载、转写后延迟释放；
- 主 App 唯一会露馅的场景是"回 App 只录 1~2 秒超短句"，接受此代价（有兜底）；
- list_tab 语音查询无说话时间可蹭，保留阻塞加载（有 loading 态），不强改。
