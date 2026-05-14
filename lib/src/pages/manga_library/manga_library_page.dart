import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/extension/widget_extension.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/pages/download/download_base_page.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_tag_groups.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/gallery_download_service.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/utils/manga_library_tag_util.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';
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
            builder: (_) => _buildDisplayModeButton(),
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
    _handlePendingLibraryFocus(items);

    return Column(
      children: [
        _buildLibraryToolbar(items.length),
        if (mangaLibraryService.hasActiveFilters) _buildActiveFilters(),
        Expanded(
          child: items.isEmpty ? Center(child: Text('noMangaLibrarySearchResult'.tr)) : _buildItemList(items),
        ),
      ],
    );
  }

  Widget _buildItemList(List<MangaLibraryItem> items) {
    if (mangaLibraryService.displayMode == MangaLibraryDisplayMode.cover) {
      return GridView.builder(
        controller: scrollController,
        padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 80),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170,
          childAspectRatio: 0.68,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (context, index) => _MangaLibraryCard(item: items[index], displayMode: mangaLibraryService.displayMode),
        itemCount: items.length,
      );
    }

    return EHWheelSpeedController(
      controller: scrollController,
      child: ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 80),
        itemBuilder: (context, index) => _MangaLibraryCard(item: items[index], displayMode: mangaLibraryService.displayMode),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: items.length,
      ),
    );
  }

  void _handlePendingLibraryFocus(List<MangaLibraryItem> items) {
    MangaLibraryFocusRequest? request = mangaLibraryService.consumePendingLibraryFocusRequest();
    if (request == null) {
      return;
    }

    Get.engine.addPostFrameCallback((_) {
      MangaLibraryItem? item = mangaLibraryService.findItemByIdentity(type: request.type, gid: request.gid, token: request.token);
      if (item == null) {
        toast('mangaLibraryItemNotFound'.tr);
        return;
      }

      int index = items.indexWhere((candidate) => candidate.stableKey == item.stableKey);
      if (index >= 0 && scrollController.hasClients) {
        double offset = mangaLibraryService.displayMode == MangaLibraryDisplayMode.cover ? (index ~/ 2) * 250 : index * 156;
        scrollController.animateTo(
          offset.clamp(0, scrollController.position.maxScrollExtent).toDouble(),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }

      mangaLibraryService.highlightLibraryItem(item.stableKey);
      if (request.openDetail) {
        toRoute(Routes.mangaLibraryDetail, arguments: item, preventDuplicates: false);
      }
    });
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

  Widget _buildDisplayModeButton() {
    return PopupMenuButton<MangaLibraryDisplayMode>(
      tooltip: 'displayMode'.tr,
      icon: const Icon(Icons.view_module),
      onSelected: mangaLibraryService.setDisplayMode,
      itemBuilder: (_) => MangaLibraryDisplayMode.values
          .map(
            (mode) => CheckedPopupMenuItem<MangaLibraryDisplayMode>(
              value: mode,
              checked: mode == mangaLibraryService.displayMode,
              child: Text(_displayModeTitle(mode)),
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
              label: Text(mangaLibraryTagText(mangaLibraryService.resolveTagTranslation(tag))),
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


  String _displayModeTitle(MangaLibraryDisplayMode mode) {
    switch (mode) {
      case MangaLibraryDisplayMode.cover:
        return 'mangaLibraryCoverMode'.tr;
      case MangaLibraryDisplayMode.compact:
        return 'mangaLibraryCompactMode'.tr;
      case MangaLibraryDisplayMode.detail:
        return 'mangaLibraryDetailMode'.tr;
    }
  }
}

class _MangaLibraryCard extends StatelessWidget {
  final MangaLibraryItem item;
  final MangaLibraryDisplayMode displayMode;

  const _MangaLibraryCard({required this.item, required this.displayMode});

  @override
  Widget build(BuildContext context) {
    bool isHighlighted = mangaLibraryService.highlightedLibraryItemKey == item.stableKey;
    return Card(
      color: isHighlighted ? Theme.of(context).colorScheme.primaryContainer : null,
      shape: isHighlighted ? RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(12)) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => toRoute(Routes.mangaLibraryDetail, arguments: item, preventDuplicates: false),
        child: displayMode == MangaLibraryDisplayMode.cover ? _buildCoverMode(context) : _buildListMode(context),
      ),
    );
  }

  Widget _buildCoverMode(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        EHImage(galleryImage: item.cover, fit: BoxFit.cover),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            color: Colors.black.withOpacity(0.62),
            child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'read') {
                mangaLibraryService.openReader(item);
              }
              if (value == 'delete') {
                _confirmDelete(context, item);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'read', child: Text('read'.tr)),
              PopupMenuItem(value: 'delete', child: Text('delete'.tr)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListMode(BuildContext context) {
    bool isDetailMode = displayMode == MangaLibraryDisplayMode.detail;
    double coverWidth = isDetailMode ? 150 : 90;
    double coverHeight = isDetailMode ? 214 : 128;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EHImage(galleryImage: item.cover, containerWidth: coverWidth, containerHeight: coverHeight, fit: BoxFit.cover),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: isDetailMode ? 3 : 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
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
                if (isDetailMode) ...[
                  Text('${'downloadTime'.tr}: ${item.downloadTime}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${'localPath'.tr}: ${item.localPath}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${'userRating'.tr}: -', maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 4),
                isDetailMode
                    ? MangaLibraryTagGroups(tags: item.tags, onTapTag: mangaLibraryService.toggleSelectedTag, maxGroups: 5, maxTagsPerGroup: 8, dense: true)
                    : MangaLibraryTagGroups(tags: item.tags, onTapTag: mangaLibraryService.toggleSelectedTag, maxGroups: 3, maxTagsPerGroup: 4, dense: true),
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
    );
  }

  Future<void> _confirmDelete(BuildContext context, MangaLibraryItem item) async {
    bool? result = await showDialog(context: context, builder: (_) => EHDialog(title: 'delete'.tr + '?'));
    if (result == true) {
      await mangaLibraryService.deleteItem(item);
    }
  }
}
