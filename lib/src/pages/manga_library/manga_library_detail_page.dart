import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/widget/eh_alert_dialog.dart';
import 'package:jhentai/src/widget/eh_gallery_category_tag.dart';
import 'package:jhentai/src/widget/eh_image.dart';
import 'package:jhentai/src/widget/eh_wheel_speed_controller.dart';

class MangaLibraryDetailPage extends StatelessWidget {
  const MangaLibraryDetailPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dynamic arguments = Get.arguments;
    if (arguments is! MangaLibraryItem) {
      return _InvalidMangaLibraryItemPage(message: 'invalidMangaLibraryItem'.tr);
    }

    return Scaffold(
      appBar: AppBar(title: Text('mangaLibraryDetail'.tr)),
      body: GetBuilder<MangaLibraryService>(
        id: MangaLibraryService.libraryChangedId,
        builder: (_) {
          MangaLibraryItem? item = mangaLibraryService.findItem(arguments.id);
          if (item == null) {
            return _InvalidMangaLibraryItemContent(message: 'mangaLibraryItemNotFound'.tr);
          }

          return _MangaLibraryDetailBody(item: item);
        },
      ),
    );
  }
}

class _InvalidMangaLibraryItemPage extends StatelessWidget {
  final String message;

  const _InvalidMangaLibraryItemPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('mangaLibraryDetail'.tr)),
      body: _InvalidMangaLibraryItemContent(message: message),
    );
  }
}

class _InvalidMangaLibraryItemContent extends StatelessWidget {
  final String message;

  const _InvalidMangaLibraryItemContent({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => backRoute(currentRoute: Routes.mangaLibraryDetail),
              child: Text('back'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _MangaLibraryDetailBody extends StatelessWidget {
  final MangaLibraryItem item;

  const _MangaLibraryDetailBody({required this.item});

  @override
  Widget build(BuildContext context) {
    final ScrollController scrollController = ScrollController();
    return EHWheelSpeedController(
      controller: scrollController,
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EHImage(galleryImage: item.cover, containerWidth: 150, containerHeight: 214, fit: BoxFit.cover),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        EHGalleryCategoryTag(category: item.category),
                        Chip(label: Text(item.type == MangaLibraryItemType.gallery ? 'gallery'.tr : 'archive'.tr)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.menu_book),
                          label: Text('read'.tr),
                          onPressed: () => mangaLibraryService.openReader(item),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: Text('delete'.tr),
                          onPressed: () => _confirmDelete(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(label: 'category'.tr, value: item.category),
          _InfoRow(label: 'pageCount'.tr, value: item.pageCount.toString()),
          _InfoRow(label: 'uploader'.tr, value: item.uploader ?? '-'),
          _InfoRow(label: 'downloadTime'.tr, value: item.downloadTime),
          _InfoRow(label: 'localPath'.tr, value: item.localPath),
          _InfoRow(label: 'userRating'.tr, value: '-'),
          const SizedBox(height: 12),
          Text('tags'.tr, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _TagList(tags: item.tags),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    bool? result = await showDialog(context: context, builder: (_) => EHDialog(title: 'delete'.tr + '?'));
    if (result == true) {
      await mangaLibraryService.deleteItem(item);
      backRoute(currentRoute: Routes.mangaLibraryDetail);
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _TagList extends StatelessWidget {
  final List<TagData> tags;

  const _TagList({required this.tags});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return Text('noData'.tr);
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: tags.map((tag) {
        return ActionChip(
          label: Text(_tagText(tag), overflow: TextOverflow.ellipsis),
          onPressed: () => mangaLibraryService.toggleSelectedTag(tag),
        );
      }).toList(),
    );
  }
}

String _tagText(TagData tag) {
  String namespace = tag.translatedNamespace ?? tag.namespace;
  String key = tag.tagName ?? tag.key;
  return '$namespace:$key';
}
