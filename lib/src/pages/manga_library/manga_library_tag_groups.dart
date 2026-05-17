import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_tag_chip.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/utils/manga_library_tag_util.dart';

class MangaLibraryTagGroups extends StatelessWidget {
  final List<TagData> tags;
  final ValueChanged<TagData>? onTapTag;
  final int? maxGroups;
  final int? maxTagsPerGroup;
  final bool dense;

  const MangaLibraryTagGroups({
    Key? key,
    required this.tags,
    this.onTapTag,
    this.maxGroups,
    this.maxTagsPerGroup,
    this.dense = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final groups = groupMangaLibraryTagsByNamespace(tags).entries.take(maxGroups ?? tags.length).toList();
    if (groups.isEmpty) {
      return _NoTagsHint(dense: dense);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.map((entry) {
        final groupTags = entry.value.take(maxTagsPerGroup ?? entry.value.length).toList();
        return Padding(
          padding: EdgeInsets.only(bottom: dense ? 4 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: dense ? 58 : 82,
                child: Text(
                  mangaLibraryNamespaceText(entry.key, sampleTag: groupTags.first),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: dense ? 4 : 6,
                  runSpacing: dense ? 3 : 5,
                  children: groupTags.map((tag) => MangaLibraryTagChip(tag: tag, onTap: onTapTag, selected: mangaLibraryService.isTagSelected(tag))).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}


class _NoTagsHint extends StatelessWidget {
  final bool dense;

  const _NoTagsHint({required this.dense});

  @override
  Widget build(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: mangaLibraryService.filterMissingTags ? colorScheme.primaryContainer : colorScheme.surfaceVariant.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: mangaLibraryService.filterMissingTags ? colorScheme.primary : colorScheme.outlineVariant, width: mangaLibraryService.filterMissingTags ? 1.4 : 1),
      ),
      child: Text(
        mangaLibraryService.filterMissingTags ? '✓ ${'noTags'.tr}' : 'noTags'.tr,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: mangaLibraryService.filterMissingTags ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant, fontWeight: mangaLibraryService.filterMissingTags ? FontWeight.w600 : FontWeight.normal),
      ),
    );
  }
}
