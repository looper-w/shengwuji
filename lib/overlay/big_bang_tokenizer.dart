import 'dart:developer' as developer;
import 'dart:io';

import 'package:dart_jieba/dart_jieba.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// 大爆炸分词 token：text 为原文片段，selectable=false 的 token（纯标点/
/// 符号/空白）渲染降级、不参与选择，但**保留在序列里**——区间拼接时夹在
/// 选中词之间的空格/标点原文不丢（见 [BigBangTokenizer.joinSelected]）
class BigBangToken {
  final String text;
  final bool selectable;
  const BigBangToken(this.text, {this.selectable = true});
}

/// 大爆炸分词器（悬浮窗"长按正文 → 词块点选/滑选复制"）。
///
/// 词级切分复用修正对体系的 dart_jieba（词典 assets/jieba_dict.dgz，
/// 运行时拷到数据库目录——dart_jieba 用 dart:io 读文件，APK 内 asset 不是
/// 文件系统路径）。⚠️ 加载结果缓存在 **本 isolate 的 static**——悬浮窗
/// overlay engine 是独立 isolate，主 engine 经 ContextCorrector 加载过的
/// 分词器对本 isolate 无效（与 sherpa-onnx FFI 绑定同款铁律），故本类在
/// overlay isolate 里独立懒加载；jieba 加载/切分失败一律回退字符级切分
/// （[charSplit]），大爆炸功能永不缺席
class BigBangTokenizer {
  static JiebaSegmenter? _seg;
  static Future<JiebaSegmenter?>? _loading;

  /// token 含至少一个字母或数字（\p{L} 含 CJK 汉字）才可选；
  /// 纯标点/符号/空白不可选
  static final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static bool isSelectable(String token) => _wordChar.hasMatch(token);

  static bool isWhitespace(String token) => token.trim().isEmpty;

  /// 原始切分序列 → token 列表（空白/标点降级为不可选但保留，供区间拼接
  /// 带出原文）。jieba 保证 token 拼接 == 原文
  static List<BigBangToken> fromRawTokens(List<String> raw) {
    // jieba 按 UTF-16 code unit 切分，emoji 等代理对会被劈成两个孤立代理
    // token——孤立代理不是合法 UTF-16，Text 渲染直接抛
    // "string is not well-formed UTF-16"（真机 logcat 刷屏根因）。先按代理对
    // 完整性把相邻碎片并回去再判可选性；合并不破坏"拼接==原文"不变量
    final repaired = <String>[];
    final buf = StringBuffer();
    for (final t in raw) {
      if (t.isEmpty) continue;
      buf.write(t);
      // 缓冲末尾是孤立高代理（0xD800~0xDBFF）：低代理在下一个碎片里，继续攒
      final last = t.codeUnitAt(t.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) continue;
      repaired.add(buf.toString());
      buf.clear();
    }
    if (buf.isNotEmpty) repaired.add(buf.toString());
    return [
      for (final t in repaired) BigBangToken(t, selectable: isSelectable(t)),
    ];
  }

  /// 字符级兜底切分（jieba 不可用时）：CJK 逐字独立成词、连续 ASCII
  /// 字母/数字归并为一个 token、标点与空白不可选但保留
  static List<BigBangToken> charSplit(String text) {
    final tokens = <BigBangToken>[];
    final buf = StringBuffer();
    final asciiWord = RegExp(r'[A-Za-z0-9]');
    void flush() {
      if (buf.isNotEmpty) {
        tokens.add(BigBangToken(buf.toString()));
        buf.clear();
      }
    }

    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (!isSelectable(ch)) {
        // 空白/标点：断开 ASCII 归并，自身作不可选 token 保留
        flush();
        tokens.add(BigBangToken(ch, selectable: false));
      } else if (asciiWord.hasMatch(ch)) {
        buf.write(ch);
      } else {
        flush();
        tokens.add(BigBangToken(ch));
      }
    }
    flush();
    return tokens;
  }

  /// 二次爆炸：把词块再炸成单字（中文逐字、英文逐字母）——jieba 切分不合
  /// 心意时的最细粒度兜底（如「app叫声物记」切成【app、叫声、物记】，再炸
  /// 一次逐字挑选）。与 [charSplit] 的契约差异：charSplit 是回退链语义
  /// （连续 ASCII 归并为一个词），本函数逐 rune 切、每 rune 一个 token。
  /// String.runes 按 code point 迭代，emoji 代理对天然不劈开（😀 整体一
  /// 个不可选 token），标点/空白/emoji 不可选但保留在序列——"拼接==原文"
  /// 不变量保持
  static List<BigBangToken> explodeToChars(String text) => [
    for (final rune in text.runes)
      BigBangToken(
        String.fromCharCode(rune),
        selectable: isSelectable(String.fromCharCode(rune)),
      ),
  ];

  /// 选中集合 → 复制文本：选中 index 排序后按"区间连续性"分组——相邻两个
  /// 选中词之间只隔着不可选 token（空格/标点）视为同一区间，拼接时把中间
  /// token 的原文一并带出（英文空格、中文标点不丢）；跨可选词的间断是用户
  /// 跳跃点选：间断区原文不带出，但间断区两端若紧贴空白（英文单词间的
  /// 空格），交界补一个空格——否则两次滑选/点选的英文会粘成 "holdafter"
  /// （真机反馈）；中文跳跃点选边界本无空格，行为不变（直接首尾相接）
  static String joinSelected(List<BigBangToken> tokens, Set<int> selected) {
    if (selected.isEmpty) return '';
    final sorted = selected.toList()..sort();
    final buf = StringBuffer();
    var runStart = sorted.first;
    var prev = sorted.first;
    for (var i = 1; i <= sorted.length; i++) {
      final cur = i < sorted.length ? sorted[i] : -1;
      var sameRun = cur == prev + 1;
      if (!sameRun && cur > prev + 1) {
        sameRun = true;
        for (var j = prev + 1; j < cur; j++) {
          if (tokens[j].selectable) {
            sameRun = false;
            break;
          }
        }
      }
      if (i < sorted.length && sameRun) {
        prev = cur;
        continue;
      }
      for (var j = runStart; j <= prev; j++) {
        buf.write(tokens[j].text);
      }
      if (i < sorted.length) {
        // 跳跃间断交界：间断区首/尾 token 是空白（间断区非空——cur > prev+1；
        // 全区空白会被判为同一区间走不到这里），补一个空格保英文词间空格
        if (isWhitespace(tokens[prev + 1].text) ||
            isWhitespace(tokens[cur - 1].text)) {
          buf.write(' ');
        }
        runStart = cur;
        prev = cur;
      }
    }
    return buf.toString();
  }

  /// 懒加载 jieba（幂等，并发归并到同一 Future）。词典拷贝模式照抄
  /// ContextCorrector._loadSegmenter：任何失败静默返回 null，调用方回退
  static Future<JiebaSegmenter?> _load() {
    return _loading ??= () async {
      try {
        String baseDir;
        try {
          baseDir = await getDatabasesPath();
        } catch (_) {
          // 测试环境无 sqflite 平台通道：落到系统临时目录
          baseDir = Directory.systemTemp.path;
        }
        final dictFile = File('$baseDir/jieba_dict.dgz');
        if (!dictFile.existsSync()) {
          final bytes = await rootBundle.load('assets/jieba_dict.dgz');
          await dictFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        }
        _seg = await JiebaSegmenter.load(dictPath: dictFile.path);
        developer.log('[BigBangTokenizer] jieba 分词器已就绪（大爆炸词级切分）');
      } catch (e) {
        developer.log('[BigBangTokenizer] jieba 初始化失败，大爆炸回退字符级切分: $e');
      }
      return _seg;
    }();
  }

  /// 切分入口：jieba 就绪走词级，未就绪/失败回退字符级
  static Future<List<BigBangToken>> tokenize(String text) async {
    if (text.isEmpty) return const [];
    final seg = _seg ?? await _load();
    if (seg == null) return charSplit(text);
    try {
      return fromRawTokens(seg.cut(text));
    } catch (e) {
      developer.log('[BigBangTokenizer] jieba 切分失败，回退字符级: $e');
      return charSplit(text);
    }
  }
}
