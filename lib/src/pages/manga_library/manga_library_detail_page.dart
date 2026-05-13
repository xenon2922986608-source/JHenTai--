import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/extension/widget_extension.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_logic.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/widget/eh_gallery_category_tag.dart';
import 'package:jhentai/src/widget/eh_image.dart';

class MangaLibraryDetailPage extends StatelessWidget {
  MangaLibraryDetailPage({Key? key}) : super(key: key);

  final MangaLibraryLogic logic = Get.put(MangaLibraryLogic());

  MangaLibraryItem get item => Get.arguments as MangaLibraryItem;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('mangaLibraryOfflineDetail'.tr),
        actions: [
          IconButton(icon: const Icon(Icons.menu_book), tooltip: 'read'.tr, onPressed: () => logic.openReader(item)),
          IconButton(icon: const Icon(Icons.delete), tooltip: 'delete'.tr, onPressed: () => logic.confirmDelete(context, item, popAfterDelete: true)),
        ],
      ),
      body: GetBuilder<MangaLibraryService>(
        id: mangaLibraryService.itemUpdateId(item),
        builder: (_) {
          MangaLibraryItem current = mangaLibraryService.items.firstWhereOrNull((e) => e.id == item.id) ?? item;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EHImage(galleryImage: current.cover, containerWidth: 120, containerHeight: 170, fit: BoxFit.cover),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(current.title, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        EHGalleryCategoryTag(category: current.category, height: 24),
                        const SizedBox(height: 8),
                        _buildInfoRow('pageCount'.tr, current.pageCount.toString()),
                        _buildInfoRow('uploader'.tr, current.uploader ?? '-'),
                        _buildInfoRow('downloadTime'.tr, current.downloadTime),
                        _buildInfoRow('localPath'.tr, current.localPath),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _UserRatingBar(item: current),
              const SizedBox(height: 16),
              Text('tags'.tr, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _TagWrap(tags: current.tags),
            ],
          );
        },
      ),
    ).enableMouseDrag();
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $value'),
    );
  }
}

class _TagWrap extends StatelessWidget {
  final List<TagData> tags;

  const _TagWrap({required this.tags});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return Text('noData'.tr);
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags.map((tag) {
        return GetBuilder<MangaLibraryService>(
          id: MangaLibraryService.libraryChangedId,
          builder: (_) => FilterChip(
            label: Text(_tagText(tag)),
            selected: mangaLibraryService.isTagSelected(tag),
            onSelected: (_) => mangaLibraryService.toggleSelectedTag(tag),
          ),
        );
      }).toList(),
    );
  }

  String _tagText(TagData tag) {
    String namespace = tag.translatedNamespace ?? tag.namespace;
    String key = tag.tagName ?? tag.key;
    return '$namespace:$key';
  }
}

class _UserRatingBar extends StatelessWidget {
  final MangaLibraryItem item;

  const _UserRatingBar({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('userRating'.tr, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            for (int i = 1; i <= 5; i++)
              IconButton(
                tooltip: i.toString(),
                icon: Icon((item.userRating ?? 0) >= i ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () => mangaLibraryService.updateUserRating(item, i.toDouble()),
              ),
            TextButton(onPressed: () => mangaLibraryService.updateUserRating(item, null), child: Text('reset'.tr)),
          ],
        ),
      ],
    );
  }
}
