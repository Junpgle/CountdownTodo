import 'package:flutter/material.dart';

import '../models.dart';
import '../utils/app_dialogs.dart';

/// Result returned by [showTodoGroupPickerSheet] when the user confirms a choice.
///
/// Distinguishes dismissing the sheet (`null` return from the sheet route) from
/// explicitly choosing the uncategorized option (`TodoGroupPickerResult(groupId: null)`).
class TodoGroupPickerResult {
  const TodoGroupPickerResult({this.groupId});

  final String? groupId;
}

/// Opens a scrollable, searchable picker for selecting a [TodoGroup].
///
/// Uses a centered dialog with a multi-column grid on wide screens (`width >= 600`)
/// and a modal bottom sheet on compact screens.
/// Returns `null` if the user dismisses the picker without choosing.
Future<TodoGroupPickerResult?> showTodoGroupPickerSheet({
  required BuildContext context,
  required List<TodoGroup> groups,
  String? selectedGroupId,
  String title = '选择归属文件夹',
  String uncategorizedLabel = '未分类',
}) {
  final activeGroups = groups
      .where((g) => !g.isDeleted)
      .toList(growable: false);
  final isWideScreen = MediaQuery.sizeOf(context).width >= 600;

  if (isWideScreen) {
    return showAppDialog<TodoGroupPickerResult>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: TodoGroupPickerSheet(
            groups: activeGroups,
            selectedGroupId: selectedGroupId,
            title: title,
            uncategorizedLabel: uncategorizedLabel,
            isDialog: true,
          ),
        ),
      ),
    );
  }

  return showAppModalBottomSheet<TodoGroupPickerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => TodoGroupPickerSheet(
      groups: activeGroups,
      selectedGroupId: selectedGroupId,
      title: title,
      uncategorizedLabel: uncategorizedLabel,
    ),
  );
}

/// Scrollable, searchable content for selecting a [TodoGroup].
class TodoGroupPickerSheet extends StatefulWidget {
  const TodoGroupPickerSheet({
    super.key,
    required this.groups,
    this.selectedGroupId,
    this.title = '选择归属文件夹',
    this.uncategorizedLabel = '未分类',
    this.isDialog = false,
  });

  final List<TodoGroup> groups;
  final String? selectedGroupId;
  final String title;
  final String uncategorizedLabel;
  final bool isDialog;

  @override
  State<TodoGroupPickerSheet> createState() => _TodoGroupPickerSheetState();
}

class _TodoGroupPickerSheetState extends State<TodoGroupPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_PickerEntry> _buildEntries() {
    final q = _query.trim().toLowerCase();
    final entries = <_PickerEntry>[];

    if (q.isEmpty || widget.uncategorizedLabel.toLowerCase().contains(q)) {
      entries.add(
        _PickerEntry(
          groupId: null,
          title: widget.uncategorizedLabel,
          isUncategorized: true,
        ),
      );
    }

    for (final group in widget.groups) {
      if (group.isDeleted) continue;
      if (q.isNotEmpty) {
        final nameMatch = group.name.toLowerCase().contains(q);
        final teamMatch = group.teamName?.toLowerCase().contains(q) ?? false;
        if (!nameMatch && !teamMatch) continue;
      }
      entries.add(
        _PickerEntry(
          groupId: group.id,
          title: group.name,
          subtitle: group.teamName,
          isUncategorized: false,
        ),
      );
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final activeCount = widget.groups.where((g) => !g.isDeleted).length;
    final showSearch = activeCount >= 5;
    final entries = _buildEntries();

    final availableHeight =
        media.size.height - media.viewInsets.bottom - media.padding.top;
    final maxContainerHeight =
        (availableHeight * (widget.isDialog ? 0.78 : 0.72)).clamp(260.0, 580.0);

    return Padding(
      padding: EdgeInsets.only(
        bottom: widget.isDialog ? 0 : media.viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: maxContainerHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.isDialog) ...[
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                widget.isDialog ? 16 : 14,
                12,
                8,
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, size: 20, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.7,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '共 $activeCount 个',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: '搜索文件夹...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            tooltip: '清空',
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            Divider(
              height: 1,
              thickness: 0.6,
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 36,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '没有找到匹配的文件夹',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      child: const Text('清空搜索'),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useGrid =
                        widget.isDialog || constraints.maxWidth >= 460;
                    if (!useGrid) {
                      return ListView.separated(
                        shrinkWrap: entries.length <= 10,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final isSelected =
                              entry.groupId == widget.selectedGroupId;
                          return _FolderPickerTile(
                            entry: entry,
                            isSelected: isSelected,
                            isGridCard: false,
                            onTap: () => Navigator.of(context).pop(
                              TodoGroupPickerResult(groupId: entry.groupId),
                            ),
                          );
                        },
                      );
                    }

                    final crossAxisCount = constraints.maxWidth >= 680 ? 3 : 2;
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final tileHeight = (60.0 * textScale).clamp(60.0, 86.0);

                    return GridView.builder(
                      shrinkWrap: entries.length <= 16,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 8,
                        mainAxisExtent: tileHeight,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final isSelected =
                            entry.groupId == widget.selectedGroupId;
                        return _FolderPickerTile(
                          entry: entry,
                          isSelected: isSelected,
                          isGridCard: true,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(TodoGroupPickerResult(groupId: entry.groupId)),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickerEntry {
  const _PickerEntry({
    required this.groupId,
    required this.title,
    this.subtitle,
    required this.isUncategorized,
  });

  final String? groupId;
  final String title;
  final String? subtitle;
  final bool isUncategorized;
}

class _FolderPickerTile extends StatelessWidget {
  const _FolderPickerTile({
    required this.entry,
    required this.isSelected,
    required this.isGridCard,
    required this.onTap,
  });

  final _PickerEntry entry;
  final bool isSelected;
  final bool isGridCard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconData = entry.isUncategorized
        ? Icons.inbox_outlined
        : (isSelected ? Icons.folder_rounded : Icons.folder_outlined);

    final backgroundColor = isSelected
        ? colors.primaryContainer.withValues(alpha: 0.6)
        : (isGridCard
              ? colors.surfaceContainerHighest.withValues(alpha: 0.35)
              : Colors.transparent);

    final borderColor = isSelected
        ? colors.primary.withValues(alpha: 0.45)
        : (isGridCard
              ? colors.outlineVariant.withValues(alpha: 0.4)
              : Colors.transparent);

    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.primary.withValues(alpha: 0.16)
                      : colors.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconData,
                  size: 18,
                  color: isSelected ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    if (entry.subtitle != null &&
                        entry.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.groups_outlined,
                            size: 12,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              entry.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: colors.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
