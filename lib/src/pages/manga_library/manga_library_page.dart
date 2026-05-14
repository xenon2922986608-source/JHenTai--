import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/extension/widget_extension.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/pages/download/download_base_page.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/gallery_download_service.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/widget/eh_alert_dialog.dart';
import 'package:jhentai/src/widget/eh_gallery_category_tag.dart';
import 'package:jhentai/src/widget/eh_image.dart';
import 'package:jhentai/src/widget/eh_wheel_speed_controller.dart';

class MangaLibraryPage extends StatelessWidget {
  MangaLibraryPage({Key? key}) : super(key: key);

  final ScrollController scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: 0,
        title: const DownloadPageSegmentControl(galleryType: DownloadPageGalleryType.library),
        actions: [
          GetBuilder<MangaLibraryService>(
            id: MangaLibraryService.libraryChangedId,
            builder: (_) {
              int count = mangaLibraryService.similarityGroups.length;
              return Badge(
                isLabelVisible: count > 0,
                label: Text(count.toString()),
                child: IconButton(
                  tooltip: 'similarManga'.tr,
                  icon: const Icon(Icons.content_copy),
                  onPressed: () => toRoute(Routes.mangaSimilarity),
                ),
              );
            },
          ),
          GetBuilder<MangaLibraryService>(
            id: MangaLibraryService.libraryChangedId,
            builder: (_) => mangaLibraryService.selectedTags.isEmpty
                ? const SizedBox()
                : IconButton(
                    tooltip: 'clearTagFilter'.tr,
                    icon: const Icon(Icons.filter_alt_off),
                    onPressed: mangaLibraryService.clearSelectedTags,
                  ),
          ),
        ],
      ),
      body: GetBuilder<GalleryDownloadService>(
        id: galleryDownloadService.galleryCountChangedId,
        builder: (_) => GetBuilder<ArchiveDownloadService>(
          id: archiveDownloadService.galleryCountChangedId,
          builder: (_) => GetBuilder<MangaLibraryService>(
            id: MangaLibraryService.libraryChangedId,
            builder: (_) => _buildBody(context),
          ),
        ),
      ),
    ).enableMouseDrag();
  }

  Widget _buildBody(BuildContext context) {
    List<MangaLibraryItem> items = mangaLibraryService.filteredItems;

    return Column(
      children: [
        if (mangaLibraryService.selectedTags.isNotEmpty) _buildSelectedTags(),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text('noData'.tr))
              : EHWheelSpeedController(
                  controller: scrollController,
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 80),
                    itemBuilder: (context, index) => _MangaLibraryCard(item: items[index]),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: items.length,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSelectedTags() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${'selectedTags'.tr}(${'andLogic'.tr})'),
          ...mangaLibraryService.selectedTags.map(
            (tag) => InputChip(
              label: Text(_tagText(tag)),
              onDeleted: () => mangaLibraryService.toggleSelectedTag(tag),
            ),
          ),
        ],
      ),
    );
  }
}

class _MangaLibraryCard extends StatelessWidget {
  final MangaLibraryItem item;

  const _MangaLibraryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => toRoute(Routes.mangaLibraryDetail, arguments: item, preventDuplicates: false),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EHImage(galleryImage: item.cover, containerWidth: 90, containerHeight: 128, fit: BoxFit.cover),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        EHGalleryCategoryTag(category: item.category, height: 20, textStyle: const TextStyle(height: 1, fontSize: 12, color: Colors.white)),
                        Text(item.type == MangaLibraryItemType.gallery ? 'gallery'.tr : 'archive'.tr),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${'pageCount'.tr}: ${item.pageCount}  ${'uploader'.tr}: ${item.uploader ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${'downloadTime'.tr}: ${item.downloadTime}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${'localPath'.tr}: ${item.localPath}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    _TagPreview(tags: item.tags),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.menu_book), onPressed: () => mangaLibraryService.openReader(item)),
                  IconButton(icon: const Icon(Icons.delete), onPressed: () => _confirmDelete(context, item)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, MangaLibraryItem item) async {
    bool? result = await showDialog(context: context, builder: (_) => EHDialog(title: 'delete'.tr + '?'));
    if (result == true) {
      await mangaLibraryService.deleteItem(item);
    }
  }
}

class _TagPreview extends StatelessWidget {
  final List<TagData> tags;

  const _TagPreview({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: tags.take(10).map((tag) {
        return InkWell(
          onTap: () => mangaLibraryService.toggleSelectedTag(tag),
          child: Chip(
            label: Text(_tagText(tag), overflow: TextOverflow.ellipsis),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
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
