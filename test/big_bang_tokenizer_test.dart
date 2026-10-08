import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/overlay/big_bang_tokenizer.dart';

void main() {
  group('isSelectable / isWhitespace', () {
    test('汉字/字母/数字可选，标点空白不可选', () {
      expect(BigBangTokenizer.isSelectable('苹果'), isTrue);
      expect(BigBangTokenizer.isSelectable('hello'), isTrue);
      expect(BigBangTokenizer.isSelectable('3'), isTrue);
      expect(BigBangTokenizer.isSelectable('，'), isFalse);
      expect(BigBangTokenizer.isSelectable('。'), isFalse);
      expect(BigBangTokenizer.isSelectable(' '), isFalse);
      expect(BigBangTokenizer.isSelectable('…'), isFalse);
    });

    test('空白判定', () {
      expect(BigBangTokenizer.isWhitespace(' '), isTrue);
      expect(BigBangTokenizer.isWhitespace(' \t\n'), isTrue);
      expect(BigBangTokenizer.isWhitespace('，'), isFalse);
      expect(BigBangTokenizer.isWhitespace('a'), isFalse);
    });
  });

  group('fromRawTokens', () {
    test('空 token 过滤，标点降级不可选但保留', () {
      final tokens = BigBangTokenizer.fromRawTokens(['苹果', '', '，', ' ', '牛奶']);
      expect(tokens.length, 4);
      expect(tokens[0].selectable, isTrue);
      expect(tokens[1].text, '，');
      expect(tokens[1].selectable, isFalse);
      expect(tokens[2].selectable, isFalse);
      expect(tokens[3].selectable, isTrue);
    });

    test('emoji 代理对被劈开的相邻碎片合并回完整字符（UTF-16 异常根因）', () {
      // jieba 按 code unit 切分会把 😀 劈成高代理 + 低代理两个 token——
      // 孤立代理渲染直接抛 "string is not well-formed UTF-16"
      final tokens = BigBangTokenizer.fromRawTokens([
        '测试',
        '\uD83D', // 😀 高代理
        '\uDE00', // 😀 低代理
        '一下',
      ]);
      expect(tokens.map((t) => t.text).toList(), ['测试', '😀', '一下']);
      // 拼接 == 原文不变量
      expect(tokens.map((t) => t.text).join(), '测试😀一下');
    });

    test('emoji 与相邻词同碎片时也正确合并', () {
      final tokens = BigBangTokenizer.fromRawTokens([
        '\uD83D', // 😀 高代理
        '\uDE00赞', // 低代理粘在下一个词上
      ]);
      expect(tokens.map((t) => t.text).toList(), ['😀赞']);
      expect(tokens.single.text.runes.length, 2);
    });
  });

  group('charSplit 字符级兜底', () {
    test('CJK 逐字、连续 ASCII 归并、标点空白保留不可选', () {
      final tokens = BigBangTokenizer.charSplit('钥匙A12，测');
      expect(tokens.map((t) => t.text).toList(), ['钥', '匙', 'A12', '，', '测']);
      expect(tokens[0].selectable, isTrue);
      expect(tokens[2].selectable, isTrue);
      expect(tokens[3].selectable, isFalse);
    });

    test('token 拼接 == 原文', () {
      const text = 'hello world，你好 ABC';
      final joined = BigBangTokenizer.charSplit(text).map((t) => t.text).join();
      expect(joined, text);
    });
  });

  group('explodeToChars 二次爆炸', () {
    test('英文逐字母（与 charSplit 的 ASCII 归并契约相反）', () {
      final tokens = BigBangTokenizer.explodeToChars('app');
      expect(tokens.map((t) => t.text).toList(), ['a', 'p', 'p']);
      expect(tokens.every((t) => t.selectable), isTrue);
    });

    test('中文逐字', () {
      final tokens = BigBangTokenizer.explodeToChars('叫声');
      expect(tokens.map((t) => t.text).toList(), ['叫', '声']);
      expect(tokens.every((t) => t.selectable), isTrue);
    });

    test('中英混合逐字', () {
      final tokens = BigBangTokenizer.explodeToChars('app叫声');
      expect(tokens.map((t) => t.text).toList(), ['a', 'p', 'p', '叫', '声']);
    });

    test('标点/空白降级不可选但保留在序列', () {
      final tokens = BigBangTokenizer.explodeToChars('a，b');
      expect(tokens.map((t) => t.text).toList(), ['a', '，', 'b']);
      expect(tokens[1].selectable, isFalse);
    });

    test('emoji 不劈代理对：整体一个不可选 token，拼接 == 原文', () {
      // String.runes 按 code point 迭代，😀 是一个 rune——不会像 jieba
      // 的 UTF-16 code unit 切分那样劈出孤立代理（渲染抛异常的根因）
      final tokens = BigBangTokenizer.explodeToChars('a😀b');
      expect(tokens.map((t) => t.text).toList(), ['a', '😀', 'b']);
      expect(tokens[1].selectable, isFalse);
      expect(tokens.map((t) => t.text).join(), 'a😀b');
    });

    test('空串 → 空列表', () {
      expect(BigBangTokenizer.explodeToChars(''), isEmpty);
    });
  });

  group('joinSelected 区间拼接', () {
    // 词块序列：苹果(0) ，(1) 牛奶(2) ' '(3) bread(4)
    final tokens = BigBangTokenizer.fromRawTokens([
      '苹果',
      '，',
      '牛奶',
      ' ',
      'bread',
    ]);

    test('空选择 → 空串', () {
      expect(BigBangTokenizer.joinSelected(tokens, {}), '');
    });

    test('单选 → 该词原文', () {
      expect(BigBangTokenizer.joinSelected(tokens, {0}), '苹果');
    });

    test('跨标点/空白的连续选择：中间原文带出', () {
      expect(BigBangTokenizer.joinSelected(tokens, {0, 2, 4}), '苹果，牛奶 bread');
    });

    test('跳过可选词 = 跳跃点选：不带中间原文，交界贴空白则补一个空格', () {
      // 间断区 ['，','牛奶',' '] 尾部紧贴空白 → 交界补空格（'苹果bread' 是
      // 修复前行为——英文场景会粘词，真机反馈后改为保留交界空格）
      expect(BigBangTokenizer.joinSelected(tokens, {0, 4}), '苹果 bread');
    });

    test('乱序 index 集合按原文顺序拼接', () {
      expect(BigBangTokenizer.joinSelected(tokens, {4, 0}), '苹果 bread');
    });

    test('两次滑选英文词组：交界保留原空格不粘词', () {
      // 真机反馈场景：第一次滑选 "touch and hold"，第二次追加
      // "after two hours"，修复前得到 "touch and holdafter two hours"
      final english = BigBangTokenizer.charSplit(
        'touch and hold then after two hours',
      );
      // touch(0) and(2) hold(4) | then(6) 跳过 | after(8) two(10) hours(12)
      expect(
        BigBangTokenizer.joinSelected(english, {0, 2, 4, 8, 10, 12}),
        'touch and hold after two hours',
      );
    });

    test('间断区两端无空白：跳跃点选仍直接首尾相接', () {
      final chinese = BigBangTokenizer.fromRawTokens([
        '苹果',
        '，',
        '香蕉',
        '，',
        '牛奶',
      ]);
      expect(BigBangTokenizer.joinSelected(chinese, {0, 4}), '苹果牛奶');
    });
  });
}
