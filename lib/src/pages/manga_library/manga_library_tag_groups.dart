import 'package:flutter/material.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_tag_chip.dart';
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
      return const SizedBox();
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
                  children: groupTags.map((tag) => MangaLibraryTagChip(tag: tag, onTap: onTapTag)).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
