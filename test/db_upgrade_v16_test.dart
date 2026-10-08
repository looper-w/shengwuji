// 数据库 v15→v16 升级回归测试（diary 表新增 sort_order 自定义排序列）。
//
// 用 sqflite_common_ffi 在桌面侧复刻用户升级路径：v15 旧 schema（含
// is_locked，无 sort_order）建库写数据 → 生产 DbHelper 真实打开 → 断言
// sort_order 列就位、首开回填生效（活跃区按 created_at DESC 赋 min-1
// 递减系列，显示顺序与升级前完全一致）、归档行恒 NULL、数据完好。
//
// ⚠️ 独立库文件名：sqflite_common_ffi 的库文件是磁盘上共享的真实文件，
// 多测试文件并行跑时共用 items.db 会互相撞锁（db_upgrade_v14_test 头注释）；
// 各文件走 DbHelper.dbFileName 静态覆盖口领独立库名。文件内只跑一个 test。
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shengwuji_app/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v15 旧库升级 v16：sort_order 列就位 + 首开回填 + 归档行恒 NULL + 数据完好', () async {
    DbHelper.dbFileName = 'items_upgrade_v16_test.db';
    final dbPath = p.join(
      await databaseFactory.getDatabasesPath(),
      DbHelper.dbFileName,
    );
    await databaseFactory.deleteDatabase(dbPath);
    // bump/snapshot 走 SharedPreferences（内部已 try/catch 静默容错），
    // mock 掉避免 MissingPluginException 噪声
    SharedPreferences.setMockInitialValues({});

    // ---- 1. 复刻 v15 旧库：diary 有 is_locked（v15 产物）、无 sort_order ----
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 15,
        onCreate: (db, version) async {
          await db.execute(
            "CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, location TEXT, sync_uuid TEXT)",
          );
          await db.execute(
            "CREATE TABLE diary(id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT, created_at TEXT, audio_path TEXT, duration INTEGER, is_archived INTEGER DEFAULT 0, exported_at TEXT, tag TEXT, sync_uuid TEXT, is_locked INTEGER DEFAULT 0)",
          );
          await db.execute(
            "CREATE TABLE sync_deleted(uuid TEXT PRIMARY KEY, kind TEXT NOT NULL, deleted_at TEXT NOT NULL)",
          );
        },
      ),
    );
    await oldDb.insert('diary', {
      'content': '旧日记-较新',
      'created_at': '2026-09-28T11:00:00.000',
      'is_archived': 0,
      'sync_uuid': 'uuid-v15-new',
    });
    await oldDb.insert('diary', {
      'content': '旧日记-较旧',
      'created_at': '2026-09-28T10:00:00.000',
      'is_archived': 0,
      'sync_uuid': 'uuid-v15-old',
    });
    await oldDb.insert('diary', {
      'content': '旧日记-归档',
      'created_at': '2026-09-28T09:00:00.000',
      'is_archived': 1,
      'sync_uuid': 'uuid-v15-arch',
    });
    await oldDb.close();

    // ---- 2. 生产 DbHelper 真实打开：触发 v15→v16 升级 + 首开回填 ----
    final dbHelper = DbHelper();
    final db = await dbHelper.db;

    // ---- 3. sort_order 列就位：PRAGMA 核实表结构 ----
    final cols = await db.rawQuery('PRAGMA table_info(diary)');
    expect(cols.any((c) => c['name'] == 'sort_order'), isTrue);

    // ---- 4. 首开回填：活跃区顺序与升级前纯时间序完全一致 ----
    final diaries = await dbHelper.getDiaries();
    expect(
      diaries.where((d) => d['is_archived'] == 0).map((d) => d['content']),
      ['旧日记-较新', '旧日记-较旧'],
    );
    // 回填为 min-1 递减系列且最新行最小（ASC 排序小=置顶）：
    // 较旧=-1、较新=-2
    expect(diaries[0]['sort_order'], -2);
    expect(diaries[1]['sort_order'], -1);
    // 归档行恒 NULL、排在活跃区之后，数据完好
    expect(diaries.last['content'], '旧日记-归档');
    expect(diaries.last['sort_order'], isNull);
    expect(diaries.last['is_locked'], 0);
    expect(diaries.last['sync_uuid'], 'uuid-v15-arch');

    // ---- 5. 新插入行走 sort_order 语义：置顶于回填系列之上 ----
    final newId = await dbHelper.insertDiary('升级后新卡');
    final after = await dbHelper.getDiaries();
    expect(after.first['id'], newId);
    expect(after.first['sort_order'], -3); // min(-1,-2)-1，置顶于回填系列之上

    await db.close();
  });
}
