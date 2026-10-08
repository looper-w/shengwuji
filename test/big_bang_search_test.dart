import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shengwuji_app/utils/big_bang_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildSearchUrl', () {
    test('三家引擎 URL 模板拼接', () {
      expect(
        buildSearchUrl(SearchEngine.baidu, 'test'),
        'https://www.baidu.com/s?wd=test',
      );
      expect(
        buildSearchUrl(SearchEngine.bing, 'test'),
        'https://www.bing.com/search?q=test',
      );
      expect(
        buildSearchUrl(SearchEngine.google, 'test'),
        'https://www.google.com/search?q=test',
      );
    });

    test('中文查询词 UTF-8 百分号编码', () {
      expect(
        buildSearchUrl(SearchEngine.baidu, '苹果'),
        'https://www.baidu.com/s?wd=%E8%8B%B9%E6%9E%9C',
      );
    });

    test('空格编码为 %20', () {
      expect(
        buildSearchUrl(SearchEngine.bing, 'hello world'),
        'https://www.bing.com/search?q=hello%20world',
      );
    });

    test('emoji 编码', () {
      expect(
        buildSearchUrl(SearchEngine.baidu, '😀'),
        'https://www.baidu.com/s?wd=%F0%9F%98%80',
      );
    });

    test('& 等特殊字符编码（防截断查询词）', () {
      expect(
        buildSearchUrl(SearchEngine.google, 'a&b=c'),
        'https://www.google.com/search?q=a%26b%3Dc',
      );
    });
  });

  group('parseSearchEngine', () {
    test('null 与坏值兜底 baidu', () {
      expect(parseSearchEngine(null), SearchEngine.baidu);
      expect(parseSearchEngine(''), SearchEngine.baidu);
      expect(parseSearchEngine('sogou'), SearchEngine.baidu);
    });

    test('合法值按 enum name 解析', () {
      expect(parseSearchEngine('baidu'), SearchEngine.baidu);
      expect(parseSearchEngine('bing'), SearchEngine.bing);
      expect(parseSearchEngine('google'), SearchEngine.google);
    });
  });

  group('loadSearchConfig', () {
    test('缺省值：baidu + 空包名（系统默认浏览器）', () async {
      SharedPreferences.setMockInitialValues({});
      final cfg = await loadSearchConfig();
      expect(cfg.engine, SearchEngine.baidu);
      expect(cfg.browserPackage, '');
    });

    test('自定义值原样读出', () async {
      SharedPreferences.setMockInitialValues({
        kSearchEngineKey: 'google',
        kSearchBrowserPackageKey: 'com.android.chrome',
      });
      final cfg = await loadSearchConfig();
      expect(cfg.engine, SearchEngine.google);
      expect(cfg.browserPackage, 'com.android.chrome');
    });

    test('落盘坏值兜底 baidu', () async {
      SharedPreferences.setMockInitialValues({kSearchEngineKey: 'bogus'});
      final cfg = await loadSearchConfig();
      expect(cfg.engine, SearchEngine.baidu);
    });
  });
}
