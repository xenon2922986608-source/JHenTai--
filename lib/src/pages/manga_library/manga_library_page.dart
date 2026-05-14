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
          IconButton(
            tooltip: 'search'.tr,
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context),
          ),
          GetBuilder<MangaLibraryService>(
            id: MangaLibraryService.libraryChangedId,
            builder: (_) => _buildSortButton(),
          ),
          GetBuilder<MangaLibraryService>(
            id: MangaLibraryService.libraryChangedId,
            builder: (_) => mangaLibraryService.hasActiveFilters
                ? IconButton(
                    tooltip: 'clearAllFilters'.tr,
                    icon: const Icon(Icons.filter_alt_off),
                    onPressed: mangaLibraryService.clearFilters,
                  )
                : const SizedBox(),
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
        _buildLibraryToolbar(items.length),
        if (mangaLibraryService.hasActiveFilters) _buildActiveFilters(),
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

  Widget _buildLibraryToolbar(int filteredCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(label: Text('${'itemCount'.tr}: $filteredCount/${mangaLibraryService.items.length}')),
          _buildTypeFilterButton(),
          _buildCategoryFilterButton(),
        ],
      ),
    );
  }

  Widget _buildTypeFilterButton() {
    return PopupMenuButton<String>(
      tooltip: 'filterByType'.tr,
      onSelected: (value) {
        if (value == 'gallery') {
          mangaLibraryService.setSelectedType(MangaLibraryItemType.gallery);
        } else if (value == 'archive') {
          mangaLibraryService.setSelectedType(MangaLibraryItemType.archive);
        } else {
          mangaLibraryService.setSelectedType(null);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(value: 'all', child: Text('allTypes'.tr)),
        PopupMenuItem<String>(value: 'gallery', child: Text('gallery'.tr)),
        PopupMenuItem<String>(value: 'archive', child: Text('archive'.tr)),
      ],
      child: Chip(
        avatar: const Icon(Icons.collections_bookmark, size: 18),
        label: Text('${'filterByType'.tr}: ${_typeTitle(mangaLibraryService.selectedType)}'),
      ),
    );
  }

  Widget _buildCategoryFilterButton() {
    return PopupMenuButton<String>(
      tooltip: 'filterByCategory'.tr,
      onSelected: (value) => mangaLibraryService.setSelectedCategory(value == '__all__' ? null : value),
      itemBuilder: (_) => [
        PopupMenuItem<String>(value: '__all__', child: Text('allCategories'.tr)),
        ...mangaLibraryService.availableCategories.map((category) => PopupMenuItem<String>(value: category, child: Text(category))),
      ],
      child: Chip(
        avatar: const Icon(Icons.category, size: 18),
        label: Text('${'category'.tr}: ${mangaLibraryService.selectedCategory ?? 'allCategories'.tr}'),
      ),
    );
  }

  Widget _buildSortButton() {
    return PopupMenuButton<MangaLibrarySortType>(
      tooltip: 'sortBy'.tr,
      icon: const Icon(Icons.sort),
      onSelected: mangaLibraryService.setSortType,
      itemBuilder: (_) => MangaLibrarySortType.values
          .map(
            (type) => CheckedPopupMenuItem<MangaLibrarySortType>(
              value: type,
              checked: type == mangaLibraryService.sortType,
              child: Text(_sortTitle(type)),
            ),
          )
          .toList(),
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${'activeFilters'.tr}(${'andLogic'.tr})'),
          if (mangaLibraryService.searchKeyword.trim().isNotEmpty)
            InputChip(
              avatar: const Icon(Icons.search, size: 18),
              label: Text(mangaLibraryService.searchKeyword),
              onDeleted: () => mangaLibraryService.setSearchKeyword(''),
            ),
          if (mangaLibraryService.selectedType != null)
            InputChip(
              label: Text(_typeTitle(mangaLibraryService.selectedType)),
              onDeleted: () => mangaLibraryService.setSelectedType(null),
            ),
          if (mangaLibraryService.selectedCategory != null)
            InputChip(
              label: Text(mangaLibraryService.selectedCategory!),
              onDeleted: () => mangaLibraryService.setSelectedCategory(null),
            ),
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

  Future<void> _showSearchDialog(BuildContext context) async {
    TextEditingController controller = TextEditingController(text: mangaLibraryService.searchKeyword);
    String? keyword = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('search'.tr),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'librarySearchHint'.tr),
          onSubmitted: (value) => Get.back(result: value),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: ''), child: Text('clear'.tr)),
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
          TextButton(onPressed: () => Get.back(result: controller.text), child: Text('OK'.tr)),
        ],
      ),
    );
    controller.dispose();

    if (keyword != null) {
      mangaLibraryService.setSearchKeyword(keyword);
    }
  }

  String _typeTitle(MangaLibraryItemType? type) {
    if (type == null) {
      return 'allTypes'.tr;
    }

    switch (type) {
      case MangaLibraryItemType.gallery:
        return 'gallery'.tr;
      case MangaLibraryItemType.archive:
        return 'archive'.tr;
    }
  }

  String _sortTitle(MangaLibrarySortType type) {
    switch (type) {
      case MangaLibrarySortType.downloadTimeDesc:
        return 'sortDownloadTimeDesc'.tr;
      case MangaLibrarySortType.titleAsc:
        return 'sortTitleAsc'.tr;
      case MangaLibrarySortType.pageCountDesc:
        return 'sortPageCountDesc'.tr;
    }
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
                        EHGalleryCategoryTag(
                          category: item.category,
                          height: 20,
                          textStyle: const TextStyle(height: 1, fontSize: 12, color: Colors.white),
                          onTap: () => mangaLibraryService.setSelectedCategory(item.category),
                        ),
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
