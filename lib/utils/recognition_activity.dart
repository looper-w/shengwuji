/// 全局「在途识别」计数器（主 App 退后台释放识别引擎的防误杀守卫）。
///
/// 背景：主 App 模型加载后不再常驻（退后台 8s 延迟释放，见 main.dart
/// didChangeAppLifecycleState）。转写是异步长操作（VAD 切段时可达数十秒），
/// 释放 Timer 到点时若恰有转写在途，dispose 会把 worker isolate 连同正在
/// decode 的任务一起销毁——轻则本次转写抛 StateError，重则占位日记永远空文本。
///
/// 用法：每个 transcribe 调用方在识别流程开始前 [begin]、结束后 [end]，
/// 必须配对且 end 放 try/finally（transcribe 抛错也要回退计数，否则计数
/// 泄漏会导致引擎永不释放）。diary_tab 的 VAD 长录音按「整场识别流程」
/// 计数（_processRecognition / _retranscribeDiary 整场一对），而非逐段
/// 计数——逐段计数在段间隙会归零，恰好撞上释放轮询会丢掉后续段。
class RecognitionActivity {
  RecognitionActivity._();

  static int _count = 0;

  /// 识别流程开始（转写前的守卫窗口也覆盖在内）
  static void begin() => _count++;

  /// 识别流程结束。防负：异常路径双 end 不至于把计数打负导致守卫失效
  static void end() {
    if (_count > 0) _count--;
  }

  /// 是否有识别在途（>0 时退后台释放守卫应顺延而非释放）
  static bool get inFlight => _count > 0;
}
