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
import 'package:jhentai/src/service/manga_library_import_service.dart';
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
        actions: GetPlatform.isMobile
            ? [
                GetBuilder<MangaLibraryService>(
                  id: MangaLibraryService.libraryChangedId,
                  builder: (_) => _buildMobileActionsMenu(context),
                ),
              ]
            : [
                GetBuilder<MangaLibraryService>(
                  id: MangaLibraryService.libraryChangedId,
                  builder: (_) => IconButton(
                    tooltip: 'batchFillMissingTags'.tr,
                    icon: mangaLibraryService.batchTagFillProgress?.isRunning == true
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_fix_high),
                    onPressed: () => _showBatchTagFillDialog(context),
                  ),
                ),
                GetBuilder<MangaLibraryService>(
                  id: MangaLibraryService.libraryChangedId,
                  builder: (_) {
                    int count = mangaLibraryService.similarityGroupCount;
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
                  builder: (_) => mangaLibraryService.selectionMode
                      ? IconButton(
                          tooltip: 'cancel'.tr,
                          icon: const Icon(Icons.close),
                          onPressed: mangaLibraryService.exitSelectionMode,
                        )
                      : IconButton(
                          tooltip: 'select'.tr,
                          icon: const Icon(Icons.checklist),
                          onPressed: () => mangaLibraryService.enterSelectionMode(),
                        ),
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
          builder: (_) => GetBuilder<MangaLibraryImportService>(
            id: MangaLibraryImportService.importedItemsChangedId,
            builder: (_) => GetBuilder<MangaLibraryService>(
              id: MangaLibraryService.libraryChangedId,
              builder: (_) => _buildBody(context),
            ),
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
        if (mangaLibraryService.selectionMode) _buildSelectionToolbar(context, items),
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
          _buildTagFilterChip(),
          _buildOrganizedFilterChip(),
        ],
      ),
    );
  }

  Widget _buildMobileActionsMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'mangaLibrary'.tr,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'batchFillTags') {
          _showBatchTagFillDialog(context);
          return;
        }
        if (value == 'similar') {
          toRoute(Routes.mangaSimilarity);
          return;
        }
        if (value == 'select') {
          mangaLibraryService.selectionMode ? mangaLibraryService.exitSelectionMode() : mangaLibraryService.enterSelectionMode();
          return;
        }
        if (value == 'search') {
          _showSearchDialog(context);
          return;
        }
        if (value == 'clearFilters') {
          mangaLibraryService.clearFilters();
          return;
        }
        if (value.startsWith('sort:')) {
          int index = int.parse(value.substring('sort:'.length));
          mangaLibraryService.setSortType(MangaLibrarySortType.values[index]);
          return;
        }
        if (value.startsWith('display:')) {
          int index = int.parse(value.substring('display:'.length));
          mangaLibraryService.setDisplayMode(MangaLibraryDisplayMode.values[index]);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'batchFillTags',
          enabled: true,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_fix_high),
            title: Text('batchFillMissingTags'.tr),
          ),
        ),
        PopupMenuItem<String>(
          value: 'similar',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.content_copy),
            title: Text('${'similarManga'.tr}${mangaLibraryService.similarityGroupCount > 0 ? ' (${mangaLibraryService.similarityGroupCount})' : ''}'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'select',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(mangaLibraryService.selectionMode ? Icons.close : Icons.checklist),
            title: Text(mangaLibraryService.selectionMode ? 'cancel'.tr : 'select'.tr),
          ),
        ),
        PopupMenuItem<String>(
          value: 'search',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.search),
            title: Text('search'.tr),
          ),
        ),
        if (mangaLibraryService.hasActiveFilters)
          PopupMenuItem<String>(
            value: 'clearFilters',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.filter_alt_off),
              title: Text('clearAllFilters'.tr),
            ),
          ),
        const PopupMenuDivider(),
        ...MangaLibrarySortType.values.map(
          (type) => CheckedPopupMenuItem<String>(
            value: 'sort:${type.index}',
            checked: type == mangaLibraryService.sortType,
            child: Text('${'sortBy'.tr}: ${_sortTitle(type)}'),
          ),
        ),
        const PopupMenuDivider(),
        ...MangaLibraryDisplayMode.values.map(
          (mode) => CheckedPopupMenuItem<String>(
            value: 'display:${mode.index}',
            checked: mode == mangaLibraryService.displayMode,
            child: Text('${'displayMode'.tr}: ${_displayModeTitle(mode)}'),
          ),
        ),
      ],
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
        } else if (value == 'importedFolder') {
          mangaLibraryService.setSelectedType(MangaLibraryItemType.importedFolder);
        } else if (value == 'pdf') {
          mangaLibraryService.setSelectedType(MangaLibraryItemType.pdf);
        } else {
          mangaLibraryService.setSelectedType(null);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(value: 'all', child: Text('allTypes'.tr)),
        PopupMenuItem<String>(value: 'gallery', child: Text('gallery'.tr)),
        PopupMenuItem<String>(value: 'archive', child: Text('archive'.tr)),
        PopupMenuItem<String>(value: 'importedFolder', child: Text('importedFolder'.tr)),
        PopupMenuItem<String>(value: 'pdf', child: Text('PDF'.tr)),
      ],
      child: Chip(
        avatar: const Icon(Icons.collections_bookmark, size: 18),
        label: Text('${'filterByType'.tr}: ${_typeTitle(mangaLibraryService.selectedType)}'),
      ),
    );
  }

  Widget _buildTagFilterChip() {
    bool selected = mangaLibraryService.tagFilterMode != MangaLibraryTagFilterMode.all;
    return FilterChip(
      avatar: Icon(selected ? Icons.check_circle : Icons.label_outline, size: 18),
      label: Text('${'tagFilter'.tr}: ${_tagFilterTitle(mangaLibraryService.tagFilterMode)}'),
      selected: selected,
      onSelected: (_) => mangaLibraryService.cycleTagFilterMode(),
    );
  }

  Widget _buildOrganizedFilterChip() {
    bool selected = mangaLibraryService.organizedFilterMode != MangaLibraryOrganizedFilterMode.all;
    return FilterChip(
      avatar: Icon(selected ? Icons.task_alt : Icons.radio_button_unchecked, size: 18),
      label: Text('${'greenLabel'.tr}: ${_organizedFilterTitle(mangaLibraryService.organizedFilterMode)}'),
      selected: selected,
      selectedColor: Colors.green.withOpacity(0.22),
      checkmarkColor: Colors.green.shade700,
      onSelected: (_) => mangaLibraryService.cycleOrganizedFilterMode(),
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

  Widget _buildSelectionToolbar(BuildContext context, List<MangaLibraryItem> filteredItems) {
    int selectedCount = mangaLibraryService.selectedItemKeys.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(avatar: const Icon(Icons.check_circle, size: 18), label: Text('${'selectedItems'.tr}: $selectedCount')),
          OutlinedButton.icon(
            icon: const Icon(Icons.select_all),
            label: Text('selectAllFiltered'.tr),
            onPressed: filteredItems.isEmpty ? null : mangaLibraryService.selectAllFilteredItems,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.clear_all),
            label: Text('clearSelection'.tr),
            onPressed: selectedCount == 0 ? null : mangaLibraryService.clearItemSelection,
          ),
          FilledButton.icon(
            icon: const Icon(Icons.delete_forever),
            label: Text('deleteSelected'.tr),
            onPressed: selectedCount == 0 ? null : () => _confirmBatchDelete(context),
          ),
        ],
      ),
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
          if (mangaLibraryService.tagFilterMode != MangaLibraryTagFilterMode.all)
            InputChip(
              avatar: const Icon(Icons.label_off, size: 18),
              label: Text('${'tagFilter'.tr}: ${_tagFilterTitle(mangaLibraryService.tagFilterMode)}'),
              onDeleted: mangaLibraryService.clearTagFilterMode,
            ),
          if (mangaLibraryService.organizedFilterMode != MangaLibraryOrganizedFilterMode.all)
            InputChip(
              avatar: const Icon(Icons.task_alt, size: 18, color: Colors.green),
              label: Text('${'greenLabel'.tr}: ${_organizedFilterTitle(mangaLibraryService.organizedFilterMode)}'),
              onDeleted: mangaLibraryService.clearOrganizedFilterMode,
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

  Future<void> _confirmBatchDelete(BuildContext context) async {
    List<MangaLibraryItem> items = mangaLibraryService.selectedItems;
    if (items.isEmpty) {
      return;
    }

    MangaLibraryDeleteResult summary = MangaLibraryDeleteResult();
    for (MangaLibraryItem item in items) {
      summary.addType(item.type);
    }

    bool? result = await showDialog(
      context: context,
      builder: (_) => EHDialog(title: 'deleteSelected'.tr + '?', content: _batchDeleteConfirmContent(summary)),
    );
    if (result != true) {
      return;
    }

    MangaLibraryBatchDeleteResult deleteResult = await mangaLibraryService.deleteItems(items);
    String message = '${'batchDeleteFinished'.tr}: ${'success'.tr} ${deleteResult.successCount}, ${'failed'.tr} ${deleteResult.failureCount}';
    if (deleteResult.missingOriginalPaths.isNotEmpty) {
      message += '\n${'originalFileNotFoundDeletedRecord'.tr}: ${deleteResult.missingOriginalPaths.length}';
    }
    if (deleteResult.failures.isNotEmpty) {
      message += '\n${deleteResult.failures.take(3).join('\n')}';
    }
    toast(message, isShort: false);
  }

  String _deleteConfirmContent(MangaLibraryItem item) {
    if (item.type == MangaLibraryItemType.importedFolder) {
      return 'deleteImportedFolderOriginalHint'.tr;
    }
    if (item.type == MangaLibraryItemType.pdf) {
      return 'deletePdfOriginalHint'.tr;
    }
    return 'deleteDownloadedMangaHint'.tr;
  }

  String _batchDeleteConfirmContent(MangaLibraryDeleteResult summary) {
    return [
      'batchDeleteConfirmHint'.tr,
      '${'gallery'.tr}: ${summary.galleryCount}',
      '${'archive'.tr}: ${summary.archiveCount}',
      '${'importedFolder'.tr}: ${summary.importedFolderCount}',
      '${'PDF'.tr}: ${summary.pdfCount}',
      'deleteBatchOriginalFilesHint'.tr,
    ].join('\n');
  }


  Future<void> _showBatchTagFillDialog(BuildContext context) async {
    if (mangaLibraryService.batchTagFillProgress?.isRunning != true) {
      mangaLibraryService.prepareBatchTagFill();
    }
    await showDialog(context: context, barrierDismissible: false, builder: (_) => const _BatchTagFillDialog());
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
      case MangaLibraryItemType.importedFolder:
        return 'importedFolder'.tr;
      case MangaLibraryItemType.pdf:
        return 'PDF'.tr;
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


  String _tagFilterTitle(MangaLibraryTagFilterMode mode) {
    switch (mode) {
      case MangaLibraryTagFilterMode.all:
        return 'all'.tr;
      case MangaLibraryTagFilterMode.hasTags:
        return 'hasTags'.tr;
      case MangaLibraryTagFilterMode.missingTags:
        return 'missingTags'.tr;
    }
  }

  String _organizedFilterTitle(MangaLibraryOrganizedFilterMode mode) {
    switch (mode) {
      case MangaLibraryOrganizedFilterMode.all:
        return 'all'.tr;
      case MangaLibraryOrganizedFilterMode.organizedOnly:
        return 'organizedOnly'.tr;
      case MangaLibraryOrganizedFilterMode.unorganizedOnly:
        return 'unorganizedOnly'.tr;
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


class _BatchTagFillDialog extends StatefulWidget {
  const _BatchTagFillDialog();

  @override
  State<_BatchTagFillDialog> createState() => _BatchTagFillDialogState();
}

class _BatchTagFillDialogState extends State<_BatchTagFillDialog> {
  MangaLibraryTagFillStrictness _strictness = MangaLibraryTagFillStrictness.balanced;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MangaLibraryService>(
      id: MangaLibraryService.libraryChangedId,
      builder: (_) {
        MangaLibraryBatchTagFillProgress? progress = mangaLibraryService.batchTagFillProgress;
        if (progress == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return WillPopScope(
          onWillPop: () async {
            if (progress.isRunning) {
              mangaLibraryService.cancelBatchTagFill();
              return false;
            }
            return true;
          },
          child: AlertDialog(
          title: Text('batchFillTags'.tr),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<MangaLibraryTagFillStrictness>(
                    value: _strictness,
                    decoration: InputDecoration(labelText: 'batchTagFillStrictness'.tr),
                    items: MangaLibraryTagFillStrictness.values
                        .map((strictness) => DropdownMenuItem(value: strictness, child: Text(_strictnessTitle(strictness))))
                        .toList(),
                    onChanged: progress.hasStarted ? null : (value) => setState(() => _strictness = value ?? MangaLibraryTagFillStrictness.balanced),
                  ),
                  const SizedBox(height: 8),
                  Text('${'batchTagFillStatus'.tr}: ${_batchStatusTitle(progress.status)}'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress.progress),
                  const SizedBox(height: 8),
                  Text('${'progress'.tr}: ${progress.currentIndex}/${progress.totalCount}'),
                  if (progress.currentTitle.isNotEmpty) Text('${'currentItem'.tr}: ${progress.currentTitle}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (progress.currentCleanedTitle.isNotEmpty) Text('${'cleanedTitle'.tr}: ${progress.currentCleanedTitle}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (progress.currentSearchQuery.isNotEmpty) Text('${'searchKeyword'.tr}: ${progress.currentSearchQuery}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (progress.currentCandidateTitle.isNotEmpty) Text('${'candidateTitle'.tr}: ${progress.currentCandidateTitle}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (progress.currentMatchLevel.isNotEmpty) Text('score=${progress.currentCandidateScore} level=${progress.currentMatchLevel} reasons=${progress.currentReasons.join(', ')}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (progress.totalCount == 0 && !progress.isRunning) Padding(padding: const EdgeInsets.only(top: 8), child: Text('batchTagFillNoTargets'.tr)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(label: Text('${'success'.tr}: ${progress.successCount}')),
                      Chip(label: Text('${'skippedCount'.tr}: ${progress.skippedCount}')),
                      Chip(label: Text('${'batchTagFillMultipleExact'.tr}: ${progress.multipleExactMatchCount}')),
                      Chip(label: Text('${'batchTagFillNoExact'.tr}: ${progress.noExactMatchCount}')),
                      Chip(label: Text('${'failureCount'.tr}: ${progress.failureCount}')),
                    ],
                  ),
                  if (progress.records.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('batchTagFillResultDetails'.tr, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    ...progress.records.take(20).map(
                          (record) => Text(
                            '${record.status}: ${record.title} (${record.searchQuery}) candidate=${record.candidateTitle} score=${record.score} level=${record.matchLevel} reasons=${record.reasons.isEmpty ? record.reason : record.reasons.join(', ')}',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (progress.isRunning)
              TextButton(onPressed: mangaLibraryService.cancelBatchTagFill, child: Text('cancel'.tr))
            else if (!progress.hasStarted) ...[
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('cancel'.tr)),
              TextButton(
                onPressed: progress.totalCount == 0 ? null : () => mangaLibraryService.startBatchFillMissingTags(strictness: _strictness),
                child: Text('start'.tr),
              ),
            ] else ...[
              TextButton(onPressed: () => mangaLibraryService.prepareBatchTagFill(), child: Text('retry'.tr)),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('close'.tr)),
            ],
          ],
          ),
        );
      },
    );
  }

  String _strictnessTitle(MangaLibraryTagFillStrictness strictness) {
    switch (strictness) {
      case MangaLibraryTagFillStrictness.strict:
        return 'batchTagFillStrictnessStrict'.tr;
      case MangaLibraryTagFillStrictness.balanced:
        return 'batchTagFillStrictnessBalanced'.tr;
      case MangaLibraryTagFillStrictness.loose:
        return 'batchTagFillStrictnessLoose'.tr;
    }
  }

  String _batchStatusTitle(MangaLibraryBatchTagFillStatus status) {
    switch (status) {
      case MangaLibraryBatchTagFillStatus.ready:
        return 'batchTagFillReady'.tr;
      case MangaLibraryBatchTagFillStatus.preparing:
        return 'batchTagFillPreparing'.tr;
      case MangaLibraryBatchTagFillStatus.searching:
        return 'batchTagFillSearching'.tr;
      case MangaLibraryBatchTagFillStatus.fetchingDetail:
        return 'batchTagFillFetchingDetail'.tr;
      case MangaLibraryBatchTagFillStatus.writingTags:
        return 'batchTagFillWritingTags'.tr;
      case MangaLibraryBatchTagFillStatus.cancelling:
        return 'batchTagFillCancelling'.tr;
      case MangaLibraryBatchTagFillStatus.cancelled:
        return 'batchTagFillCancelled'.tr;
      case MangaLibraryBatchTagFillStatus.completed:
        return 'batchTagFillCompleted'.tr;
      case MangaLibraryBatchTagFillStatus.failed:
        return 'batchTagFillFailed'.tr;
    }
  }
}

class _MangaLibraryOrganizedBadge extends StatelessWidget {
  const _MangaLibraryOrganizedBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'organized'.tr,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.green.shade600,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
        ),
        child: const Icon(Icons.task_alt, color: Colors.white, size: 18),
      ),
    );
  }
}

class _MangaLibraryOrganizedChip extends StatelessWidget {
  const _MangaLibraryOrganizedChip();

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.task_alt, size: 16, color: Colors.white),
      label: Text('organized'.tr, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: Colors.green.shade600,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
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
        onTap: () {
          if (mangaLibraryService.selectionMode) {
            mangaLibraryService.toggleItemSelection(item);
            return;
          }
          toRoute(Routes.mangaLibraryDetail, arguments: item, preventDuplicates: false);
        },
        onLongPress: () => mangaLibraryService.enterSelectionMode(initialItem: item),
        child: Stack(
          children: [
            displayMode == MangaLibraryDisplayMode.cover ? _buildCoverMode(context) : _buildListMode(context),
            if (item.organized)
              const Positioned(
                top: 6,
                right: 42,
                child: _MangaLibraryOrganizedBadge(),
              ),
            if (mangaLibraryService.selectionMode)
              Positioned(
                top: 4,
                left: 4,
                child: Checkbox(
                  value: mangaLibraryService.isItemSelected(item),
                  onChanged: (_) => mangaLibraryService.toggleItemSelection(item),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverMode(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _MangaLibraryCover(item: item, fit: BoxFit.cover),
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
          if (mangaLibraryService.selectionMode) const SizedBox(width: 32),
          _MangaLibraryCover(item: item, width: coverWidth, height: coverHeight, fit: BoxFit.cover),
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
                    Text(_mangaLibraryTypeTitle(item.type)),
                    if (item.organized) const _MangaLibraryOrganizedChip(),
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
    bool? result = await showDialog(
      context: context,
      builder: (_) => EHDialog(title: 'delete'.tr + '?', content: _deleteConfirmContent(item)),
    );
    if (result == true) {
      try {
        MangaLibraryDeleteResult deleteResult = await mangaLibraryService.deleteItem(item);
        if (deleteResult.missingOriginalPaths.isNotEmpty) {
          toast('originalFileNotFoundDeletedRecord'.tr, isShort: false);
        } else {
          toast('success'.tr);
        }
      } catch (e) {
        toast('${'operationFailed'.tr}: $e', isShort: false);
      }
    }
  }

  String _deleteConfirmContent(MangaLibraryItem item) {
    if (item.type == MangaLibraryItemType.importedFolder) {
      return 'deleteImportedFolderOriginalHint'.tr;
    }
    if (item.type == MangaLibraryItemType.pdf) {
      return 'deletePdfOriginalHint'.tr;
    }
    return 'deleteDownloadedMangaHint'.tr;
  }
}

class _MangaLibraryCover extends StatelessWidget {
  final MangaLibraryItem item;
  final double? width;
  final double? height;
  final BoxFit fit;

  const _MangaLibraryCover({required this.item, this.width, this.height, required this.fit});

  @override
  Widget build(BuildContext context) {
    if (item.type == MangaLibraryItemType.pdf || (item.cover.path == null && item.cover.url.isEmpty)) {
      return Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf, size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6),
              Text('PDF'.tr, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      );
    }

    return EHImage(galleryImage: item.cover, containerWidth: width, containerHeight: height, fit: fit);
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
