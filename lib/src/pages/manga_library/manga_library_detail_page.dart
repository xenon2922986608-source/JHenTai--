import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/pages/download/download_base_page.dart';
import 'package:jhentai/src/pages/details/details_page_logic.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_tag_groups.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';
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
      appBar: AppBar(
        title: Text('mangaLibraryDetail'.tr),
        actions: [
          if (!arguments.isImported)
            IconButton(
              tooltip: 'switchToThisMangaInDownload'.tr,
              icon: const Icon(Icons.download),
              onPressed: () => _switchToDownload(arguments),
            ),
        ],
      ),
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

  void _switchToDownload(MangaLibraryItem item) {
    if (item.type == MangaLibraryItemType.archive) {
      toast('archiveItemNoVisibleDownloadEntry'.tr, isShort: false);
      return;
    }
    if (item.isImported || item.galleryUrl == null) {
      toast('downloadItemNotFound'.tr);
      return;
    }

    mangaLibraryService.requestFocusInDownload(item);
    downloadPageGalleryTypeNotifier.value = null;
    downloadPageGalleryTypeNotifier.value = DownloadPageGalleryType.download;
    toRoute(Routes.download);
    toRoute(
      Routes.details,
      arguments: DetailsPageArgument(galleryUrl: GalleryUrl.parse(item.galleryUrl!)),
      preventDuplicates: false,
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
              _MangaLibraryDetailCover(item: item),
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
                        EHGalleryCategoryTag(category: item.category, onTap: () => mangaLibraryService.setSelectedCategory(item.category)),
                        Chip(label: Text(_mangaLibraryTypeTitle(item.type))),
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
          MangaLibraryTagGroups(tags: item.tags, onTapTag: mangaLibraryService.toggleSelectedTag),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    bool? result = await showDialog(
      context: context,
      builder: (_) => EHDialog(title: item.isImported ? 'removeImportedItemOnlyHint'.tr : 'delete'.tr + '?'),
    );
    if (result == true) {
      await mangaLibraryService.deleteItem(item);
      backRoute(currentRoute: Routes.mangaLibraryDetail);
    }
  }
}

class _MangaLibraryDetailCover extends StatelessWidget {
  final MangaLibraryItem item;

  const _MangaLibraryDetailCover({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.type == MangaLibraryItemType.pdf || (item.cover.path == null && item.cover.url.isEmpty)) {
      return Container(
        width: 150,
        height: 214,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text('PDF'.tr, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
    }

    return EHImage(galleryImage: item.cover, containerWidth: 150, containerHeight: 214, fit: BoxFit.cover);
  }
}

String _mangaLibraryTypeTitle(MangaLibraryItemType type) {
  switch (type) {
    case MangaLibraryItemType.gallery:
      return 'gallery'.tr;
    case MangaLibraryItemType.archive:
      return 'archive'.tr;
    case MangaLibraryItemType.importedFolder:
      return 'importedFolder'.tr;
    case MangaLibraryItemType.pdf:
      return 'PDF'.tr;
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
