/// 悬浮窗日记列表长按拖动排序的内存重排纯函数。
///
/// ReorderableListView 的 onReorder 只报 (oldIndex, newIndex)，活跃区与
/// 归档区的分界（活跃恒在前，getDiaries 排序保证）由调用方经 [isArchived]
/// 谓词告知。DB 持久化入口：DbHelper.reorderActiveDiaries。
library;

/// 把 [items] 中 [oldIndex] 处的活跃卡移到 [newIndex]（ReorderableListView
/// 语义：newIndex 为移除 oldIndex 之后的插入位）。
///
/// - 归档区卡不可拖：oldIndex 落在归档区（或越界）原样返回；
/// - 落点 clamp 在活跃区内：拖到归档区位置 = 落到活跃区末尾，
///   归档区整体不受影响（「已归档」分隔线钉在归档首卡，跟随归档区不动）；
/// - 位置实际未变时原样返回（调用方按 identical 判 no-op，不 setState/落库）。
List<T> reorderActiveItems<T>({
  required List<T> items,
  required bool Function(T item) isArchived,
  required int oldIndex,
  required int newIndex,
}) {
  final activeCount = items.where((item) => !isArchived(item)).length;
  // 归档区卡不可拖（UI 层不包 DragStartListener 本就到不了这里，防御兜底）
  if (oldIndex < 0 || oldIndex >= activeCount) return items;
  // 落点越过活跃区 → clamp 到活跃区末尾
  if (newIndex > activeCount) newIndex = activeCount;
  if (newIndex < 0) newIndex = 0;
  // ReorderableListView 标准重排换算（newIndex 以移除后位置计）
  if (newIndex > oldIndex) newIndex -= 1;
  if (newIndex == oldIndex) return items;
  final result = List<T>.of(items);
  result.insert(newIndex, result.removeAt(oldIndex));
  return result;
}
