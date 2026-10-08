import 'package:shared_preferences/shared_preferences.dart';

/// 大爆炸分词层的「联网搜索」配置：搜索引擎注册表、URL 拼接与 prefs 存取。
///
/// 悬浮窗与主 App 日记页共用：选中词块后按选定引擎拼 URL，经原生 openUrl
/// 通道拉起浏览器（browserPackage 空串 = 系统默认浏览器）。
enum SearchEngine { baidu, bing, google }

/// 搜索引擎注册表：显示名 + URL 模板（查询词经 Uri.encodeComponent 编码后拼接）
const Map<SearchEngine, ({String label, String urlBase})> searchEngines = {
  SearchEngine.baidu: (label: '百度', urlBase: 'https://www.baidu.com/s?wd='),
  SearchEngine.bing: (label: '必应', urlBase: 'https://www.bing.com/search?q='),
  SearchEngine.google: (
    label: 'Google',
    urlBase: 'https://www.google.com/search?q=',
  ),
};

/// prefs key：搜索引擎（enum name）/ 指定浏览器包名 / 浏览器显示名
///（包名与显示名成对存取，设置页选择器落盘，本侧消费包名）
const kSearchEngineKey = 'search_engine';
const kSearchBrowserPackageKey = 'search_browser_package';
const kSearchBrowserNameKey = 'search_browser_name';

/// 拼接搜索 URL：base + 编码后的查询词
String buildSearchUrl(SearchEngine engine, String query) {
  return searchEngines[engine]!.urlBase + Uri.encodeComponent(query);
}

/// 解析落盘的搜索引擎（坏值 / null 兜底 baidu）
SearchEngine parseSearchEngine(String? raw) {
  return SearchEngine.values.asNameMap()[raw] ?? SearchEngine.baidu;
}

/// 读取搜索配置（跨 engine 的 prefs 内存缓存隔离，读前 reload——项目惯例）。
/// browserPackage 缺省空串 = 系统默认浏览器。
Future<({SearchEngine engine, String browserPackage})>
loadSearchConfig() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return (
    engine: parseSearchEngine(prefs.getString(kSearchEngineKey)),
    browserPackage: prefs.getString(kSearchBrowserPackageKey) ?? '',
  );
}
