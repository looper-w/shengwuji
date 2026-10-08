import 'package:flutter_test/flutter_test.dart';
import 'package:shengwuji_app/overlay/overlay_diary_reorder.dart';

/// 悬浮窗活跃区卡片长按拖动排序的内存重排纯函数测试
///（lib/overlay/overlay_diary_reorder.dart）。
///
/// 数据模型：活跃区恒在前、归档区恒在尾（getDiaries 排序
/// is_archived ASC 保证），用 int 列表 + 「>=100 视为归档」谓词模拟。
void main() {
  bool isArchived(int item) => item >= 100;

  group('reorderActiveItems 活跃区内重排', () {
    test('前移：第 3 张拖到第 1 位', () {
      final result = reorderActiveItems<int>(
        items: [1, 2, 3, 100, 101],
        isArchived: isArchived,
        oldIndex: 2,
        newIndex: 0,
      );
      expect(result, [3, 1, 2, 100, 101]);
    });

    test('后移：第 1 张拖到第 3 位（newIndex 标准换算 -1）', () {
      final result = reorderActiveItems<int>(
        items: [1, 2, 3, 100, 101],
        isArchived: isArchived,
        oldIndex: 0,
        newIndex: 3,
      );
      expect(result, [2, 3, 1, 100, 101]);
    });

    test('相邻交换：第 1 张拖到第 2 位', () {
      final result = reorderActiveItems<int>(
        items: [1, 2, 3, 100],
        isArchived: isArchived,
        oldIndex: 0,
        newIndex: 2,
      );
      expect(result, [2, 1, 3, 100]);
    });
  });

  group('reorderActiveItems 落点 clamp 与归档区保护', () {
    test('拖到列表最底部 → clamp 落到活跃区末尾，归档区原样不动', () {
      final result = reorderActiveItems<int>(
        items: [1, 2, 3, 100, 101],
        isArchived: isArchived,
        oldIndex: 0,
        newIndex: 5, // 列表末尾（越过活跃区）
      );
      expect(result, [2, 3, 1, 100, 101]);
    });

    test('落点恰为活跃区末尾（newIndex == 活跃条数）', () {
      final result = reorderActiveItems<int>(
        items: [1, 2, 3, 100],
        isArchived: isArchived,
        oldIndex: 0,
        newIndex: 3,
      );
      expect(result, [2, 3, 1, 100]);
    });

    test('归档区卡被拖（oldIndex 落在归档区）→ 原样返回（防御兜底）', () {
      final items = [1, 2, 100, 101];
      final result = reorderActiveItems<int>(
        items: items,
        isArchived: isArchived,
        oldIndex: 2,
        newIndex: 0,
      );
      expect(identical(result, items), isTrue);
    });

    test('位置实际未变 → 原样返回（调用方 identical 判 no-op）', () {
      final items = [1, 2, 3, 100];
      final result = reorderActiveItems<int>(
        items: items,
        isArchived: isArchived,
        oldIndex: 1,
        newIndex: 1,
      );
      expect(identical(result, items), isTrue);
    });

    test('原位向后挪一位语义（oldIndex+1 == newIndex）→ 原样返回', () {
      final items = [1, 2, 3, 100];
      final result = reorderActiveItems<int>(
        items: items,
        isArchived: isArchived,
        oldIndex: 0,
        newIndex: 1, // 换算后仍是 0
      );
      expect(identical(result, items), isTrue);
    });

    test('全活跃无归档区：拖到最后 clamp 到末尾', () {
      final result = reorderActiveItems<int>(
        items: [1, 2, 3],
        isArchived: isArchived,
        oldIndex: 0,
        newIndex: 3,
      );
      expect(result, [2, 3, 1]);
    });

    test('重排返回新列表，输入列表不被修改', () {
      final items = [1, 2, 3, 100];
      final snapshot = List.of(items);
      reorderActiveItems<int>(
        items: items,
        isArchived: isArchived,
        oldIndex: 0,
        newIndex: 2,
      );
      expect(items, snapshot);
    });
  });
}
