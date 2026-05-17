import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/dao/archive_dao.dart';
import 'package:jhentai/src/database/dao/gallery_dao.dart';
import 'package:jhentai/src/database/dao/tag_dao.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/model/gallery.dart';
import 'package:jhentai/src/model/gallery_detail.dart';
import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/model/gallery_page.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/model/search_config.dart';
import 'package:jhentai/src/network/eh_request.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/model/read_page_info.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/gallery_download_service.dart';
import 'package:jhentai/src/service/jh_service.dart';
import 'package:jhentai/src/service/manga_library_import_service.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import 'package:jhentai/src/service/read_progress_service.dart';
import 'package:jhentai/src/service/path_service.dart';
import 'package:jhentai/src/service/super_resolution_service.dart';
import 'package:jhentai/src/utils/convert_util.dart';
import 'package:jhentai/src/utils/manga_library_tag_util.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/file_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';
import 'package:jhentai/src/utils/eh_spider_parser.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:path/path.dart' as path;

MangaLibraryService mangaLibraryService = MangaLibraryService();

class MangaLibraryService extends GetxController with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String libraryChangedId = 'mangaLibraryChangedId';
  static const String similarityChangedId = 'mangaSimilarityChangedId';

  final List<TagData> selectedTags = [];
  final Set<String> ignoredSimilarityPairs = {};
  final Set<String> selectedItemKeys = {};
  final Map<String, MangaLibraryItemUserData> _userData = {};
  MangaLibraryBatchTagFillProgress? batchTagFillProgress;
  bool _cancelBatchTagFill = false;
  final Map<int, GalleryDetail> _batchPreferredDetails = {};

  String searchKeyword = '';
  MangaLibraryItemType? selectedType;
  String? selectedCategory;
  MangaLibraryTagFilterMode tagFilterMode = MangaLibraryTagFilterMode.all;
  MangaLibraryOrganizedFilterMode organizedFilterMode = MangaLibraryOrganizedFilterMode.all;
  MangaLibrarySortType sortType = MangaLibrarySortType.downloadTimeDesc;
  MangaLibraryDisplayMode displayMode = MangaLibraryDisplayMode.compact;
  final Map<String, TagData> _tagTranslationMap = {};
  List<MangaLibraryItem> _cachedItems = [];
  List<MangaLibraryItem> _cachedFilteredItems = [];
  List<MangaSimilarityGroup> _cachedSimilarityGroups = [];
  String _itemsCacheSignature = '';
  String _filteredItemsCacheSignature = '';
  bool _similarityGroupsDirty = true;
  bool isRefreshingSimilarityGroups = false;
  bool selectionMode = false;

  MangaLibraryFocusRequest? _pendingLibraryFocusRequest;
  MangaLibraryFocusRequest? _pendingDownloadFocusRequest;
  String? highlightedLibraryItemKey;
  String? highlightedDownloadItemKey;

  @override
  List<JHLifeCircleBean> get initDependencies => super.initDependencies..addAll([galleryDownloadService, archiveDownloadService, mangaLibraryImportService, localConfigService]);

  @override
  Future<void> doInitBean() async {
    Get.put(this, permanent: true);
    await _loadIgnoredSimilarityPairs();
    await _loadUserData();
    await _loadDisplayMode();
  }

  @override
  Future<void> doAfterBeanReady() async {
    await loadTagTranslations();
  }

  Future<void> _loadIgnoredSimilarityPairs() async {
    ignoredSimilarityPairs
      ..clear()
      ..addAll((await localConfigService.readWithAllSubKeys(configKey: ConfigEnum.mangaSimilarityIgnoredPair)).map((config) => config.subConfigKey));
  }

  Future<void> _loadUserData() async {
    _userData.clear();
    List<LocalConfig> configs = await localConfigService.readWithAllSubKeys(configKey: ConfigEnum.mangaLibraryItemUserData);
    for (LocalConfig config in configs) {
      try {
        MangaLibraryItemUserData data = MangaLibraryItemUserData.fromJson(jsonDecode(config.value));
        _userData[data.stableKey] = data;
      } catch (e, stack) {
        log.error('Read manga library user data failed: ${config.subConfigKey}', e, stack);
      }
    }
  }

  Future<void> _loadDisplayMode() async {
    String? value = await localConfigService.read(configKey: ConfigEnum.mangaLibraryDisplayMode);
    int index = int.tryParse(value ?? '') ?? MangaLibraryDisplayMode.compact.index;
    displayMode = MangaLibraryDisplayMode.values.elementAtOrNull(index) ?? MangaLibraryDisplayMode.compact;
  }

  Future<void> loadTagTranslations() async {
    List<TagData> tags = await TagDao.selectAllTags();
    _tagTranslationMap
      ..clear()
      ..addEntries(tags.map((tag) => MapEntry(_tagKey(tag.namespace, tag.key), tag)));
    refreshLibraryItems(notify: false);
    update([libraryChangedId, similarityChangedId]);
  }

  TagData resolveTagTranslation(TagData tag) {
    return _tagTranslationMap[_tagKey(tag.namespace, tag.key)] ?? tag;
  }

  String _tagKey(String namespace, String key) => '$namespace:$key';

  List<MangaLibraryItem> get items {
    _ensureItemsCacheFresh();
    return _cachedItems;
  }

  void refreshLibraryItems({bool notify = true}) {
    _itemsCacheSignature = '';
    _ensureItemsCacheFresh(force: true);
    _invalidateFilteredItems();
    _invalidateSimilarityGroups();
    if (notify) {
      update([libraryChangedId, similarityChangedId]);
    }
  }

  void _ensureItemsCacheFresh({bool force = false}) {
    String signature = _buildItemsCacheSignature();
    if (!force && signature == _itemsCacheSignature) {
      return;
    }

    _cachedItems = _buildLibraryItems();
    _itemsCacheSignature = signature;
    _invalidateFilteredItems();
    _invalidateSimilarityGroups();
  }

  String _buildItemsCacheSignature() {
    return [
      galleryDownloadService.gallerys.length,
      archiveDownloadService.archives.length,
      mangaLibraryImportService.importedItems.length,
      galleryDownloadService.gallerys.map((gallery) => '${gallery.gid}:${gallery.downloadStatusIndex}:${gallery.insertTime}:${gallery.tags}').join('|'),
      archiveDownloadService.archives.map((archive) => '${archive.gid}:${archive.archiveStatusCode}:${archive.insertTime}:${archive.tags}').join('|'),
      mangaLibraryImportService.importedItems.map((item) => '${item.itemKey}:${item.updatedAt}:${item.tags}:${item.pageCount}:${item.sourceGalleryUrl ?? ''}:${item.sourceCategory ?? ''}:${item.sourceUploader ?? ''}:${item.hasSidecarMetadata}:${item.sidecarPath ?? ''}:${item.organized}:${item.organizedUpdatedAt ?? ''}').join('|'),
      _userData.values.map((data) => '${data.stableKey}:${data.organized}:${data.organizedUpdatedAt}').join('|'),
    ].join('||');
  }

  List<MangaLibraryItem> _buildLibraryItems() {
    List<MangaLibraryItem> result = [];

    result.addAll(galleryDownloadService.gallerys.where((gallery) => DownloadStatus.values[gallery.downloadStatusIndex] == DownloadStatus.downloaded).map((gallery) {
      GalleryImage cover = galleryDownloadService.galleryDownloadInfos[gallery.gid]?.images.firstWhereOrNull((image) => image != null) ?? GalleryImage(url: '');
      return MangaLibraryItem(
        type: MangaLibraryItemType.gallery,
        gid: gallery.gid,
        token: gallery.token,
        title: gallery.title,
        category: gallery.category,
        pageCount: gallery.pageCount,
        galleryUrl: gallery.galleryUrl,
        uploader: gallery.uploader,
        tags: _translateTags(tagDataString2TagDataList(gallery.tags)),
        downloadTime: gallery.insertTime,
        localPath: galleryDownloadService.computeGalleryDownloadAbsolutePath(gallery.title, gallery.gid),
        cover: cover,
        isOriginal: gallery.downloadOriginalImage,
        organized: _userData[MangaLibraryItem.buildStableKey(type: MangaLibraryItemType.gallery, gid: gallery.gid, token: gallery.token)]?.organized ?? false,
        organizedUpdatedAt: _userData[MangaLibraryItem.buildStableKey(type: MangaLibraryItemType.gallery, gid: gallery.gid, token: gallery.token)]?.organizedUpdatedAt,
      );
    }));

    result.addAll(archiveDownloadService.archives.where((archive) => ArchiveStatus.fromCode(archive.archiveStatusCode) == ArchiveStatus.completed).map((archive) {
      return MangaLibraryItem(
        type: MangaLibraryItemType.archive,
        gid: archive.gid,
        token: archive.token,
        title: archive.title,
        category: archive.category,
        pageCount: archive.pageCount,
        galleryUrl: archive.galleryUrl,
        uploader: archive.uploader,
        tags: _translateTags(tagDataString2TagDataList(archive.tags)),
        downloadTime: archive.insertTime,
        localPath: archiveDownloadService.computeArchiveUnpackingPath(archive.title, archive.gid),
        cover: GalleryImage(url: archive.coverUrl),
        isOriginal: archive.isOriginal,
        organized: _userData[MangaLibraryItem.buildStableKey(type: MangaLibraryItemType.archive, gid: archive.gid, token: archive.token)]?.organized ?? false,
        organizedUpdatedAt: _userData[MangaLibraryItem.buildStableKey(type: MangaLibraryItemType.archive, gid: archive.gid, token: archive.token)]?.organizedUpdatedAt,
      );
    }));

    result.addAll(mangaLibraryImportService.importedItems.map((importedItem) {
      MangaLibraryItemType type = importedItem.type == MangaLibraryItemType.pdf.code ? MangaLibraryItemType.pdf : MangaLibraryItemType.importedFolder;
      MangaLibraryItemUserData? userData = _userData[importedItem.itemKey];
      MangaLibraryOrganizedState organizedState = _resolveOrganizedState(userData, importedItem);
      return MangaLibraryItem(
        type: type,
        title: importedItem.title,
        category: importedItem.category,
        pageCount: importedItem.pageCount,
        gid: importedItem.sourceGid,
        token: importedItem.sourceToken,
        galleryUrl: importedItem.sourceGalleryUrl,
        uploader: importedItem.sourceUploader,
        tags: _translateTags(tagDataString2TagDataList(importedItem.tags)),
        downloadTime: importedItem.createdAt,
        localPath: importedItem.localPath,
        cover: GalleryImage(url: '', path: importedItem.coverPath, downloadStatus: DownloadStatus.downloaded),
        sourceGid: importedItem.sourceGid,
        sourceToken: importedItem.sourceToken,
        sourceGalleryUrl: importedItem.sourceGalleryUrl,
        sourceTitle: importedItem.sourceTitle,
        sourceCategory: importedItem.sourceCategory,
        tagUpdatedAt: importedItem.tagUpdatedAt,
        sidecarPath: importedItem.sidecarPath,
        hasSidecarMetadata: importedItem.hasSidecarMetadata,
        organized: organizedState.organized,
        organizedUpdatedAt: organizedState.organizedUpdatedAt,
      );
    }));

    result.sort((a, b) => b.downloadTime.compareTo(a.downloadTime));
    return result;
  }

  List<TagData> _translateTags(List<TagData> tags) {
    return tags.map(resolveTagTranslation).toList();
  }

  List<MangaLibraryItem> get filteredItems {
    _ensureItemsCacheFresh();
    String signature = _buildFilteredItemsCacheSignature();
    if (signature == _filteredItemsCacheSignature) {
      return _cachedFilteredItems;
    }

    String keyword = _normalizeSearchText(searchKeyword);
    List<MangaLibraryItem> result = _cachedItems.where((item) {
      if (selectedType != null && item.type != selectedType) {
        return false;
      }

      if (selectedCategory != null && item.category != selectedCategory) {
        return false;
      }

      if (tagFilterMode == MangaLibraryTagFilterMode.hasTags && item.tags.isEmpty) {
        return false;
      }

      if (tagFilterMode == MangaLibraryTagFilterMode.missingTags && item.tags.isNotEmpty) {
        return false;
      }

      if (organizedFilterMode == MangaLibraryOrganizedFilterMode.organizedOnly && !item.organized) {
        return false;
      }

      if (organizedFilterMode == MangaLibraryOrganizedFilterMode.unorganizedOnly && item.organized) {
        return false;
      }

      if (selectedTags.isNotEmpty && !selectedTags.every((selectedTag) => item.tags.any((tag) => tag.namespace == selectedTag.namespace && tag.key == selectedTag.key))) {
        return false;
      }

      if (keyword.isNotEmpty && !_itemMatchesKeyword(item, keyword)) {
        return false;
      }

      return true;
    }).toList();

    _sortItems(result);
    _cachedFilteredItems = result;
    _filteredItemsCacheSignature = signature;
    return _cachedFilteredItems;
  }

  void _invalidateFilteredItems() {
    _filteredItemsCacheSignature = '';
    _cachedFilteredItems = [];
  }

  String _buildFilteredItemsCacheSignature() {
    return [
      _itemsCacheSignature,
      searchKeyword.trim(),
      selectedType?.code ?? '',
      selectedCategory ?? '',
      tagFilterMode.index,
      organizedFilterMode.index,
      sortType.index,
      selectedTags.map((tag) => _tagKey(tag.namespace, tag.key)).join('|'),
    ].join('||');
  }

  List<String> get availableCategories {
    return items.map((item) => item.category).toSet().toList()..sort();
  }

  bool get hasActiveFilters => searchKeyword.trim().isNotEmpty || selectedType != null || selectedCategory != null || selectedTags.isNotEmpty || tagFilterMode != MangaLibraryTagFilterMode.all || organizedFilterMode != MangaLibraryOrganizedFilterMode.all;

  MangaLibraryItem? findItem(String itemId) {
    return items.firstWhereOrNull((item) => item.id == itemId);
  }

  MangaLibraryItem? findItemByIdentity({required MangaLibraryItemType type, required int gid, String? token}) {
    String key = MangaLibraryItem.buildStableKey(type: type, gid: gid, token: token);
    MangaLibraryItem? exact = items.firstWhereOrNull((item) => item.stableKey == key);
    if (exact != null) {
      return exact;
    }

    if (token == null || token.trim().isEmpty) {
      return items.firstWhereOrNull((item) => item.type == type && item.gid == gid);
    }

    return null;
  }


  bool isItemSelected(MangaLibraryItem item) => selectedItemKeys.contains(item.stableKey);

  void enterSelectionMode({MangaLibraryItem? initialItem}) {
    selectionMode = true;
    if (initialItem != null) {
      selectedItemKeys.add(initialItem.stableKey);
    }
    update([libraryChangedId]);
  }

  void exitSelectionMode() {
    selectionMode = false;
    selectedItemKeys.clear();
    update([libraryChangedId]);
  }

  void toggleItemSelection(MangaLibraryItem item) {
    if (selectedItemKeys.contains(item.stableKey)) {
      selectedItemKeys.remove(item.stableKey);
    } else {
      selectedItemKeys.add(item.stableKey);
    }
    update([libraryChangedId]);
  }

  void selectAllFilteredItems() {
    selectedItemKeys.addAll(filteredItems.map((item) => item.stableKey));
    selectionMode = true;
    update([libraryChangedId]);
  }

  void clearItemSelection() {
    selectedItemKeys.clear();
    update([libraryChangedId]);
  }

  List<MangaLibraryItem> get selectedItems {
    _ensureItemsCacheFresh();
    return _cachedItems.where((item) => selectedItemKeys.contains(item.stableKey)).toList();
  }

  void requestFocusInLibrary({required MangaLibraryItemType type, required int gid, String? token, bool openDetail = true}) {
    _pendingLibraryFocusRequest = MangaLibraryFocusRequest(type: type, gid: gid, token: token, openDetail: openDetail);
    clearFilters();
  }

  MangaLibraryFocusRequest? consumePendingLibraryFocusRequest() {
    MangaLibraryFocusRequest? request = _pendingLibraryFocusRequest;
    _pendingLibraryFocusRequest = null;
    return request;
  }

  void requestFocusInDownload(MangaLibraryItem item) {
    if (item.gid == null) {
      return;
    }
    _pendingDownloadFocusRequest = MangaLibraryFocusRequest(type: item.type, gid: item.gid!, token: item.token);
    update([libraryChangedId]);
  }

  MangaLibraryFocusRequest? consumePendingDownloadFocusRequest() {
    MangaLibraryFocusRequest? request = _pendingDownloadFocusRequest;
    _pendingDownloadFocusRequest = null;
    return request;
  }

  void highlightLibraryItem(String stableKey) {
    highlightedLibraryItemKey = stableKey;
    update([libraryChangedId]);
    Future.delayed(const Duration(seconds: 2), () {
      if (highlightedLibraryItemKey == stableKey) {
        highlightedLibraryItemKey = null;
        update([libraryChangedId]);
      }
    });
  }

  void highlightDownloadItem(String stableKey) {
    highlightedDownloadItemKey = stableKey;
    update([libraryChangedId]);
    Future.delayed(const Duration(seconds: 2), () {
      if (highlightedDownloadItemKey == stableKey) {
        highlightedDownloadItemKey = null;
        update([libraryChangedId]);
      }
    });
  }

  void setSearchKeyword(String keyword) {
    searchKeyword = keyword.trim();
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  void setSelectedType(MangaLibraryItemType? type) {
    selectedType = type;
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  void setSelectedCategory(String? category) {
    selectedCategory = category;
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  bool isTagSelected(TagData tagData) {
    return selectedTags.any((tag) => tag.namespace == tagData.namespace && tag.key == tagData.key);
  }

  void cycleTagFilterMode() {
    tagFilterMode = MangaLibraryTagFilterMode.values[(tagFilterMode.index + 1) % MangaLibraryTagFilterMode.values.length];
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  void clearTagFilterMode() {
    if (tagFilterMode == MangaLibraryTagFilterMode.all) {
      return;
    }
    tagFilterMode = MangaLibraryTagFilterMode.all;
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  void cycleOrganizedFilterMode() {
    organizedFilterMode = MangaLibraryOrganizedFilterMode.values[(organizedFilterMode.index + 1) % MangaLibraryOrganizedFilterMode.values.length];
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  void clearOrganizedFilterMode() {
    if (organizedFilterMode == MangaLibraryOrganizedFilterMode.all) {
      return;
    }
    organizedFilterMode = MangaLibraryOrganizedFilterMode.all;
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  void setSortType(MangaLibrarySortType type) {
    sortType = type;
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  Future<void> setDisplayMode(MangaLibraryDisplayMode mode) async {
    displayMode = mode;
    update([libraryChangedId]);
    await localConfigService.write(configKey: ConfigEnum.mangaLibraryDisplayMode, value: mode.index.toString());
  }

  void toggleSelectedTag(TagData tagData) {
    int index = selectedTags.indexWhere((tag) => tag.namespace == tagData.namespace && tag.key == tagData.key);
    if (index == -1) {
      selectedTags.add(TagData(namespace: tagData.namespace, key: tagData.key));
    } else {
      selectedTags.removeAt(index);
    }
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  void clearSelectedTags() {
    selectedTags.clear();
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  void clearFilters() {
    searchKeyword = '';
    selectedType = null;
    selectedCategory = null;
    tagFilterMode = MangaLibraryTagFilterMode.all;
    organizedFilterMode = MangaLibraryOrganizedFilterMode.all;
    selectedTags.clear();
    _invalidateFilteredItems();
    update([libraryChangedId]);
  }

  bool _itemMatchesKeyword(MangaLibraryItem item, String keyword) {
    if (_normalizeSearchText(item.title).contains(keyword) ||
        (item.gid?.toString() ?? '').contains(keyword) ||
        _normalizeSearchText(item.token ?? '').contains(keyword) ||
        _normalizeSearchText(item.localPath).contains(keyword) ||
        _normalizeSearchText(item.uploader ?? '').contains(keyword)) {
      return true;
    }

    if (_normalizeSearchText(item.category).contains(keyword)) {
      return true;
    }

    return item.tags.any((tag) => _normalizeSearchText(mangaLibraryTagSearchText(tag)).contains(keyword));
  }

  String _normalizeSearchText(String text) {
    String normalized = text.replaceAllMapped(RegExp(r'[！-～]'), (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) - 0xFEE0));
    return normalized.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _sortItems(List<MangaLibraryItem> targetItems) {
    switch (sortType) {
      case MangaLibrarySortType.downloadTimeDesc:
        targetItems.sort((a, b) => b.downloadTime.compareTo(a.downloadTime));
        break;
      case MangaLibrarySortType.titleAsc:
        targetItems.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case MangaLibrarySortType.pageCountDesc:
        targetItems.sort((a, b) => b.pageCount.compareTo(a.pageCount));
        break;
    }
  }

  List<MangaSimilarityGroup> get similarityGroups => _cachedSimilarityGroups;

  int get similarityGroupCount => _cachedSimilarityGroups.length;

  void _invalidateSimilarityGroups() {
    _similarityGroupsDirty = true;
    _cachedSimilarityGroups = [];
  }

  Future<List<MangaSimilarityGroup>> refreshSimilarityGroups({bool force = false}) async {
    _ensureItemsCacheFresh();
    if (!force && !_similarityGroupsDirty) {
      return _cachedSimilarityGroups;
    }

    isRefreshingSimilarityGroups = true;
    update([similarityChangedId]);
    await Future<void>.delayed(Duration.zero);

    List<MangaLibraryItem> currentItems = List.of(_cachedItems);
    List<MangaSimilarityGroup> result = [];

    for (int i = 0; i < currentItems.length; i++) {
      if (i % 40 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      for (int j = i + 1; j < currentItems.length; j++) {
        MangaSimilarityGroup? group = _compare(currentItems[i], currentItems[j]);
        if (group != null && !ignoredSimilarityPairs.contains(group.pairKey)) {
          result.add(group);
        }
      }
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    _cachedSimilarityGroups = result;
    _similarityGroupsDirty = false;
    isRefreshingSimilarityGroups = false;
    update([similarityChangedId, libraryChangedId]);
    return _cachedSimilarityGroups;
  }

  Future<void> ignoreSimilarityGroup(MangaSimilarityGroup group) async {
    ignoredSimilarityPairs.add(group.pairKey);
    await localConfigService.write(configKey: ConfigEnum.mangaSimilarityIgnoredPair, subConfigKey: group.pairKey, value: DateTime.now().toString());
    _cachedSimilarityGroups.removeWhere((candidate) => candidate.pairKey == group.pairKey);
    update([similarityChangedId]);
  }

  Future<MangaLibraryDeleteResult> deleteItem(MangaLibraryItem item) async {
    MangaLibraryDeleteResult result = MangaLibraryDeleteResult();
    await _deleteItemInternal(item, result);
    selectedItemKeys.remove(item.stableKey);
    refreshLibraryItems();
    return result;
  }

  Future<MangaLibraryBatchDeleteResult> deleteItems(List<MangaLibraryItem> targetItems) async {
    MangaLibraryBatchDeleteResult result = MangaLibraryBatchDeleteResult(totalCount: targetItems.length);
    for (MangaLibraryItem item in targetItems) {
      try {
        await _deleteItemInternal(item, result);
        result.successCount++;
      } catch (e, stack) {
        result.failureCount++;
        result.failures.add('${item.title} (${item.localPath}): $e');
        log.error('Delete manga library item failed: ${item.localPath}', e, stack);
      }
      await Future<void>.delayed(Duration.zero);
    }
    selectedItemKeys.removeAll(targetItems.map((item) => item.stableKey));
    selectionMode = false;
    refreshLibraryItems();
    return result;
  }

  Future<void> _deleteItemInternal(MangaLibraryItem item, MangaLibraryDeleteResult result) async {
    result.addType(item.type);
    _userData.remove(item.stableKey);
    await localConfigService.delete(configKey: ConfigEnum.mangaLibraryItemUserData, subConfigKey: item.stableKey);
    if (item.type == MangaLibraryItemType.gallery) {
      await galleryDownloadService.deleteGalleryByGid(item.gid!);
    } else if (item.type == MangaLibraryItemType.archive) {
      await archiveDownloadService.deleteArchive(item.gid!);
    } else {
      bool originalExisted = await mangaLibraryImportService.deleteImportedItem(item, deleteOriginalFile: true);
      if (!originalExisted) {
        result.missingOriginalPaths.add(item.localPath);
      }
    }
  }


  String buildTagFillSearchKeyword(MangaLibraryItem item) {
    String source = item.title.trim().isNotEmpty ? item.title : path.basenameWithoutExtension(item.localPath);
    return buildEhSearchQueryFromLibraryTitle(source);
  }



  String tagDataListToString(List<TagData> tags) {
    return tags.map((tag) => '${tag.namespace}:${tag.key}').join(',');
  }

  TagData parseManualTagInput(String input, {List<TagData> existingTags = const []}) {
    String value = input.trim();
    int colonIndex = value.indexOf(RegExp(r'[:：]'));
    if (colonIndex <= 0 || colonIndex >= value.length - 1) {
      throw Exception('manualTagInvalidFormat'.tr);
    }

    String namespace = normalizeMangaLibraryTagNamespace(value.substring(0, colonIndex));
    String key = value.substring(colonIndex + 1).trim();
    if (namespace.isEmpty || key.isEmpty) {
      throw Exception('manualTagInvalidFormat'.tr);
    }

    TagData tag = _resolveManualTag(namespace, key);
    if (existingTags.any((existed) => existed.namespace == tag.namespace && existed.key == tag.key)) {
      throw Exception('manualTagDuplicate'.tr);
    }
    return tag;
  }

  TagData _resolveManualTag(String namespace, String key) {
    String normalizedKey = key.trim();
    TagData? exact = _tagTranslationMap[_tagKey(namespace, normalizedKey)] ?? _tagTranslationMap[_tagKey(namespace, normalizedKey.toLowerCase())];
    if (exact != null) {
      return exact;
    }

    String lowerKey = normalizedKey.toLowerCase();
    for (TagData tag in _tagTranslationMap.values) {
      if (tag.namespace != namespace) {
        continue;
      }
      if (tag.key.toLowerCase() == lowerKey || tag.tagName?.toLowerCase() == lowerKey || tag.fullTagName?.toLowerCase() == lowerKey) {
        return tag;
      }
    }

    for (MangaLibraryItem item in items) {
      for (TagData tag in item.tags) {
        if (tag.namespace != namespace) {
          continue;
        }
        if (tag.key.toLowerCase() == lowerKey || tag.tagName?.toLowerCase() == lowerKey || tag.fullTagName?.toLowerCase() == lowerKey) {
          return TagData(namespace: tag.namespace, key: tag.key, translatedNamespace: tag.translatedNamespace, tagName: tag.tagName, fullTagName: tag.fullTagName);
        }
      }
    }

    return TagData(namespace: namespace, key: normalizedKey);
  }

  List<TagData> buildManualTagSuggestions(String input, {int limit = 20}) {
    String value = input.trim();
    String? namespace;
    String keyword = value;
    int colonIndex = value.indexOf(RegExp(r'[:：]'));
    if (colonIndex >= 0) {
      namespace = normalizeMangaLibraryTagNamespace(value.substring(0, colonIndex));
      keyword = value.substring(colonIndex + 1).trim();
    }

    String lowerKeyword = keyword.toLowerCase();
    Map<String, TagData> candidates = {};
    void addCandidate(TagData tag) {
      if (namespace != null && namespace!.isNotEmpty && tag.namespace != namespace) {
        return;
      }
      if (lowerKeyword.isNotEmpty &&
          !tag.key.toLowerCase().contains(lowerKeyword) &&
          !(tag.tagName?.toLowerCase().contains(lowerKeyword) ?? false) &&
          !(tag.fullTagName?.toLowerCase().contains(lowerKeyword) ?? false)) {
        return;
      }
      candidates.putIfAbsent(_tagKey(tag.namespace, tag.key), () => tag);
    }

    for (MangaLibraryItem item in items) {
      for (TagData tag in item.tags) {
        addCandidate(tag);
        if (candidates.length >= limit) {
          return candidates.values.take(limit).toList();
        }
      }
    }
    for (TagData tag in _tagTranslationMap.values) {
      addCandidate(tag);
      if (candidates.length >= limit) {
        break;
      }
    }
    return candidates.values.take(limit).toList();
  }


  List<MangaLibraryItem> get batchTagFillTargets => items.where((item) => item.tags.isEmpty && item.title.trim().isNotEmpty).toList();

  void cancelBatchTagFill() {
    _cancelBatchTagFill = true;
    batchTagFillProgress?.status = MangaLibraryBatchTagFillStatus.cancelling;
    update([libraryChangedId]);
  }

  Future<MangaLibraryBatchTagFillProgress> startBatchFillMissingTags() async {
    if (batchTagFillProgress?.isRunning == true) {
      return batchTagFillProgress!;
    }

    List<MangaLibraryItem> targets = batchTagFillTargets;
    batchTagFillProgress = MangaLibraryBatchTagFillProgress(totalCount: targets.length);
    _cancelBatchTagFill = false;
    _batchPreferredDetails.clear();
    update([libraryChangedId]);

    if (targets.isEmpty) {
      batchTagFillProgress!.status = MangaLibraryBatchTagFillStatus.completed;
      update([libraryChangedId]);
      return batchTagFillProgress!;
    }

    for (int index = 0; index < targets.length; index++) {
      if (_cancelBatchTagFill) {
        batchTagFillProgress!.status = MangaLibraryBatchTagFillStatus.cancelled;
        batchTagFillProgress!.records.add(MangaLibraryBatchTagFillRecord(title: targets[index].title, searchQuery: '', status: 'cancelled', reason: 'cancelled'.tr));
        break;
      }

      MangaLibraryItem item = targets[index];
      String cleanedTitle = cleanMangaLibraryTitleForTagFill(item.title);
      String searchQuery = buildEhSearchQueryFromLibraryTitle(item.title);
      batchTagFillProgress!
        ..currentIndex = index + 1
        ..currentTitle = item.title
        ..currentCleanedTitle = cleanedTitle
        ..currentSearchQuery = searchQuery
        ..status = MangaLibraryBatchTagFillStatus.searching;
      log.info('Manga library batch tag fill search: original=${item.title}, cleaned=$cleanedTitle, query=$searchQuery');
      update([libraryChangedId]);

      try {
        List<Gallery> candidates = await searchTagFillCandidates(searchQuery);
        List<Gallery> exactMatches = candidates.where((candidate) => isExactMangaLibraryTitleMatch(item.title, candidate.title)).toList();
        if (exactMatches.isEmpty) {
          batchTagFillProgress!
            ..noExactMatchCount++
            ..skippedCount++
            ..records.add(MangaLibraryBatchTagFillRecord(title: item.title, searchQuery: searchQuery, status: 'skipped_no_exact_match', reason: 'batchTagFillNoExactMatch'.tr));
          continue;
        }
        String successStatus = 'success_exact_single';
        Gallery selectedCandidate = exactMatches.single;
        if (exactMatches.length > 1) {
          _ChinesePreferredCandidateResult preferred = await _selectChinesePreferredExactMatch(item: item, exactMatches: exactMatches, searchQuery: searchQuery);
          if (preferred.status != 'success_exact_chinese_preferred' || preferred.candidate == null) {
            batchTagFillProgress!
              ..multipleExactMatchCount++
              ..skippedCount++
              ..records.add(MangaLibraryBatchTagFillRecord(title: item.title, searchQuery: searchQuery, status: preferred.status, reason: preferred.reason));
            continue;
          }
          selectedCandidate = preferred.candidate!;
          successStatus = preferred.status;
        }

        GalleryDetail? preferredDetail = _batchPreferredDetails.remove(selectedCandidate.gid);
        batchTagFillProgress!.status = MangaLibraryBatchTagFillStatus.fetchingDetail;
        update([libraryChangedId]);
        GalleryDetail detail;
        try {
          detail = preferredDetail ?? await fetchTagFillCandidateDetail(selectedCandidate);
        } catch (e) {
          batchTagFillProgress!
            ..failedDetailCount++
            ..failureCount++
            ..records.add(MangaLibraryBatchTagFillRecord(title: item.title, searchQuery: searchQuery, status: 'failed_details', reason: e.toString()));
          continue;
        }

        String detailTitle = detail.japaneseTitle ?? detail.rawTitle;
        bool detailTitleMatches = isExactMangaLibraryTitleMatch(item.title, detail.rawTitle) || (detail.japaneseTitle != null && isExactMangaLibraryTitleMatch(item.title, detail.japaneseTitle!));
        if (!detailTitleMatches) {
          batchTagFillProgress!
            ..noExactMatchCount++
            ..skippedCount++
            ..records.add(MangaLibraryBatchTagFillRecord(title: item.title, searchQuery: searchQuery, status: 'skipped_no_exact_match', reason: 'batchTagFillDetailTitleMismatch'.tr));
          continue;
        }
        if (tagMap2TagString(detail.tags).isEmpty) {
          batchTagFillProgress!
            ..failedDetailCount++
            ..failureCount++
            ..records.add(MangaLibraryBatchTagFillRecord(title: item.title, searchQuery: searchQuery, status: 'failed_details', reason: 'candidateHasNoTags'.tr));
          continue;
        }

        batchTagFillProgress!.status = MangaLibraryBatchTagFillStatus.writingTags;
        update([libraryChangedId]);
        try {
          await fillMissingTagsFromDetail(item, detail);
          batchTagFillProgress!
            ..successCount++
            ..records.add(MangaLibraryBatchTagFillRecord(title: item.title, searchQuery: searchQuery, status: successStatus, reason: detailTitle));
        } catch (e) {
          batchTagFillProgress!
            ..failedWriteCount++
            ..failureCount++
            ..records.add(MangaLibraryBatchTagFillRecord(title: item.title, searchQuery: searchQuery, status: 'failed_write', reason: e.toString()));
        }
      } catch (e) {
        batchTagFillProgress!
          ..failedSearchCount++
          ..failureCount++
          ..records.add(MangaLibraryBatchTagFillRecord(title: item.title, searchQuery: searchQuery, status: 'failed_search', reason: e.toString()));
      } finally {
        update([libraryChangedId]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    if (_cancelBatchTagFill) {
      batchTagFillProgress!.status = MangaLibraryBatchTagFillStatus.cancelled;
    } else if (batchTagFillProgress!.status != MangaLibraryBatchTagFillStatus.cancelled) {
      batchTagFillProgress!.status = MangaLibraryBatchTagFillStatus.completed;
    }
    refreshLibraryItems();
    update([libraryChangedId]);
    return batchTagFillProgress!;
  }


  Future<_ChinesePreferredCandidateResult> _selectChinesePreferredExactMatch({required MangaLibraryItem item, required List<Gallery> exactMatches, required String searchQuery}) async {
    int unknownCount = 0;
    List<Gallery> chineseCandidates = [];
    _batchPreferredDetails.clear();

    for (Gallery candidate in exactMatches) {
      if (!isExactMangaLibraryTitleMatch(item.title, candidate.title)) {
        continue;
      }

      bool? hasChineseLanguage = _candidateHasChineseLanguageFromSearchResult(candidate);
      if (hasChineseLanguage == null) {
        batchTagFillProgress!.status = MangaLibraryBatchTagFillStatus.fetchingDetail;
        update([libraryChangedId]);
        try {
          GalleryDetail detail = await fetchTagFillCandidateDetail(candidate);
          bool detailTitleMatches = isExactMangaLibraryTitleMatch(item.title, detail.rawTitle) || (detail.japaneseTitle != null && isExactMangaLibraryTitleMatch(item.title, detail.japaneseTitle!));
          if (!detailTitleMatches) {
            unknownCount++;
            continue;
          }
          _batchPreferredDetails[candidate.gid] = detail;
          hasChineseLanguage = mangaLibraryTagsContainChineseLanguage(detail.tags.values.flattened.map((tag) => tag.tagData));
        } catch (e, stack) {
          unknownCount++;
          log.error('Batch tag fill candidate language detection failed: ${candidate.galleryUrl.url}', e, stack);
          continue;
        }
      }

      if (hasChineseLanguage) {
        chineseCandidates.add(candidate);
      }
    }

    if (chineseCandidates.length > 1) {
      _batchPreferredDetails.clear();
      return _ChinesePreferredCandidateResult(status: 'skipped_multiple_chinese', reason: 'batchTagFillMultipleChinese'.tr);
    }
    if (unknownCount > 0) {
      _batchPreferredDetails.clear();
      return _ChinesePreferredCandidateResult(status: 'skipped_multiple_unknown_language', reason: 'batchTagFillUnknownLanguage'.tr);
    }
    if (chineseCandidates.length == 1) {
      return _ChinesePreferredCandidateResult(candidate: chineseCandidates.single, status: 'success_exact_chinese_preferred', reason: 'batchTagFillChinesePreferred'.tr);
    }
    _batchPreferredDetails.clear();
    return _ChinesePreferredCandidateResult(status: 'skipped_multiple_no_chinese', reason: 'batchTagFillNoChinese'.tr);
  }

  bool? _candidateHasChineseLanguageFromSearchResult(Gallery candidate) {
    if (candidate.tags.isNotEmpty) {
      Iterable<TagData> tags = candidate.tags.values.flattened.map((tag) => tag.tagData);
      bool hasLanguageTag = tags.any((tag) => normalizeMangaLibraryTagNamespace(tag.namespace) == 'language' || normalizeMangaLibraryTagNamespace(tag.translatedNamespace ?? '') == 'language');
      return hasLanguageTag ? mangaLibraryTagsContainChineseLanguage(tags) : null;
    }
    String? language = candidate.language?.trim();
    if (language != null && language.isNotEmpty) {
      return isMangaLibraryChineseLanguageTag(namespace: 'language', key: language);
    }
    return null;
  }

  Future<void> toggleOrganized(MangaLibraryItem item) async {
    String now = DateTime.now().toString();
    bool organized = !item.organized;
    MangaLibraryItemUserData data = MangaLibraryItemUserData(stableKey: item.stableKey, organized: organized, organizedUpdatedAt: now);
    _userData[item.stableKey] = data;
    await localConfigService.write(configKey: ConfigEnum.mangaLibraryItemUserData, subConfigKey: item.stableKey, value: jsonEncode(data.toJson()));

    bool sidecarSynced = true;
    if (item.isImported) {
      sidecarSynced = await mangaLibraryImportService.updateImportedItemOrganized(item: item, organized: organized, organizedUpdatedAt: now);
    }

    refreshLibraryItems();
    if (!sidecarSynced) {
      toast('libraryMetadataWriteFailed'.tr, isShort: false);
    }
  }

  MangaLibraryOrganizedState _resolveOrganizedState(MangaLibraryItemUserData? userData, MangaLibraryImportedItem importedItem) {
    if (userData == null) {
      return MangaLibraryOrganizedState(organized: importedItem.organized, organizedUpdatedAt: importedItem.organizedUpdatedAt);
    }

    DateTime? userTime = DateTime.tryParse(userData.organizedUpdatedAt);
    DateTime? importedTime = DateTime.tryParse(importedItem.organizedUpdatedAt ?? '');
    if (userTime != null && importedTime != null && importedTime.isAfter(userTime)) {
      return MangaLibraryOrganizedState(organized: importedItem.organized, organizedUpdatedAt: importedItem.organizedUpdatedAt);
    }
    return MangaLibraryOrganizedState(organized: userData.organized, organizedUpdatedAt: userData.organizedUpdatedAt);
  }

  Future<void> updateItemTagsManually(MangaLibraryItem item, List<TagData> tags) async {
    String tagString = tagDataListToString(tags);
    if (item.isImported) {
      await mangaLibraryImportService.updateImportedItemTags(item: item, tags: tagString);
    } else if (item.type == MangaLibraryItemType.gallery) {
      await GalleryDao.updateGalleryTags(item.gid!, tagString);
      int index = galleryDownloadService.gallerys.indexWhere((gallery) => gallery.gid == item.gid);
      if (index != -1) {
        galleryDownloadService.gallerys[index] = galleryDownloadService.gallerys[index].copyWith(tags: tagString);
      }
    } else if (item.type == MangaLibraryItemType.archive) {
      await ArchiveDao.updateArchiveTags(item.gid!, tagString);
      int index = archiveDownloadService.archives.indexWhere((archive) => archive.gid == item.gid);
      if (index != -1) {
        archiveDownloadService.archives[index] = archiveDownloadService.archives[index].copyWith(tags: tagString);
      }
    }
    refreshLibraryItems();
  }

  Future<List<Gallery>> searchTagFillCandidates(String keyword) async {
    String normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) {
      throw Exception('invalid'.tr);
    }

    GalleryPageInfo pageInfo = await ehRequest.requestGalleryPage<GalleryPageInfo>(
      searchConfig: SearchConfig(keyword: normalizedKeyword),
      parser: EHSpiderParser.galleryPage2GalleryPageInfo,
    );
    return pageInfo.gallerys;
  }

  Future<GalleryDetail> fetchTagFillCandidateDetail(Gallery gallery) async {
    ({GalleryDetail galleryDetails, String apikey}) detailPageInfo = await ehRequest.requestDetailPage<({GalleryDetail galleryDetails, String apikey})>(
      galleryUrl: gallery.galleryUrl.url,
      useCacheIfAvailable: false,
      parser: EHSpiderParser.detailPage2GalleryAndDetailAndApikey,
    );
    return detailPageInfo.galleryDetails;
  }

  Future<void> fillMissingTagsFromGallery(MangaLibraryItem item, Gallery gallery) async {
    GalleryDetail detail = await fetchTagFillCandidateDetail(gallery);
    await fillMissingTagsFromDetail(item, detail);
  }

  Future<void> fillMissingTagsFromDetail(MangaLibraryItem item, GalleryDetail detail) async {
    String tags = tagMap2TagString(detail.tags);
    if (tags.isEmpty) {
      throw Exception('candidateHasNoTags'.tr);
    }

    if (item.isImported) {
      await mangaLibraryImportService.updateImportedItemTags(
        item: item,
        tags: tags,
        sourceGid: detail.galleryUrl.gid,
        sourceToken: detail.galleryUrl.token,
        sourceGalleryUrl: detail.galleryUrl.url,
        sourceTitle: detail.japaneseTitle ?? detail.rawTitle,
        sourceCategory: detail.category,
        sourceUploader: detail.uploader,
        category: detail.category,
        uploader: detail.uploader,
        pageCount: detail.pageCount,
      );
    } else if (item.type == MangaLibraryItemType.gallery) {
      await GalleryDao.updateGalleryTags(item.gid!, tags);
      int index = galleryDownloadService.gallerys.indexWhere((gallery) => gallery.gid == item.gid);
      if (index != -1) {
        galleryDownloadService.gallerys[index] = galleryDownloadService.gallerys[index].copyWith(tags: tags);
      }
    } else if (item.type == MangaLibraryItemType.archive) {
      await ArchiveDao.updateArchiveTags(item.gid!, tags);
      int index = archiveDownloadService.archives.indexWhere((archive) => archive.gid == item.gid);
      if (index != -1) {
        archiveDownloadService.archives[index] = archiveDownloadService.archives[index].copyWith(tags: tags);
      }
    }

    refreshLibraryItems();
  }

  Future<void> fillMissingTagsDirectly(MangaLibraryItem item) async {
    String? galleryUrl = item.galleryUrl;
    if ((galleryUrl == null || galleryUrl.trim().isEmpty) && item.gid != null && (item.token?.trim().isNotEmpty ?? false)) {
      galleryUrl = GalleryUrl(isEH: true, gid: item.gid!, token: item.token!).url;
    }
    if (galleryUrl == null || galleryUrl.trim().isEmpty) {
      throw Exception('mangaLibraryNoSourceGallery'.tr);
    }

    ({GalleryDetail galleryDetails, String apikey}) detailPageInfo = await ehRequest.requestDetailPage<({GalleryDetail galleryDetails, String apikey})>(
      galleryUrl: galleryUrl,
      useCacheIfAvailable: false,
      parser: EHSpiderParser.detailPage2GalleryAndDetailAndApikey,
    );
    await fillMissingTagsFromDetail(item, detailPageInfo.galleryDetails);
  }


  Future<void> exportImportedItemSidecar(MangaLibraryItem item) async {
    await mangaLibraryImportService.exportItemSidecar(item);
    refreshLibraryItems();
  }

  Future<void> openReader(MangaLibraryItem item) async {
    if (item.type == MangaLibraryItemType.pdf) {
      toast('pdfReaderNotSupported'.tr, isShort: false);
      return;
    }

    if (item.type == MangaLibraryItemType.importedFolder) {
      List<GalleryImage> images = await _getImportedFolderImages(item.localPath);
      if (images.isEmpty) {
        toast('noData'.tr);
        return;
      }

      toRoute(
        Routes.read,
        arguments: ReadPageInfo(
          mode: ReadMode.local,
          galleryTitle: item.title,
          initialIndex: 0,
          pageCount: images.length,
          readProgressRecordStorageKey: item.localPath,
          images: images,
          useSuperResolution: false,
        ),
      );
      return;
    }

    int readIndexRecord = await readProgressService.getReadProgress(item.gid!);

    if (item.type == MangaLibraryItemType.gallery) {
      toRoute(
        Routes.read,
        arguments: ReadPageInfo(
          mode: ReadMode.downloaded,
          gid: item.gid,
          token: item.token,
          galleryTitle: item.title,
          galleryUrl: item.galleryUrl,
          initialIndex: readIndexRecord,
          readProgressRecordStorageKey: item.gid.toString(),
          pageCount: item.pageCount,
          useSuperResolution: superResolutionService.get(item.gid!, SuperResolutionType.gallery) != null,
        ),
      );
      return;
    }

    final images = await archiveDownloadService.getUnpackedImages(item.gid!);
    toRoute(
      Routes.read,
      arguments: ReadPageInfo(
        mode: ReadMode.archive,
        gid: item.gid,
        galleryTitle: item.title,
        galleryUrl: item.galleryUrl,
        initialIndex: readIndexRecord,
        pageCount: images.length,
        isOriginal: item.isOriginal,
        readProgressRecordStorageKey: item.gid.toString(),
        images: images,
        useSuperResolution: superResolutionService.get(item.gid!, SuperResolutionType.archive) != null,
      ),
    );
  }

  Future<List<GalleryImage>> _getImportedFolderImages(String folderPath) async {
    Directory directory = Directory(folderPath);
    if (!await directory.exists()) {
      return [];
    }

    List<File> imageFiles = await directory
        .list(followLinks: false)
        .where((entity) => entity is File && FileUtil.isImageExtension(entity.path))
        .cast<File>()
        .toList();
    imageFiles.sort(FileUtil.naturalCompareFile);

    return imageFiles
        .map((file) => GalleryImage(
              url: '',
              path: path.isWithin(pathService.getVisibleDir().path, file.path) ? path.relative(file.path, from: pathService.getVisibleDir().path) : file.path,
              downloadStatus: DownloadStatus.downloaded,
            ))
        .toList();
  }

  MangaSimilarityGroup? _compare(MangaLibraryItem first, MangaLibraryItem second) {
    List<String> reasons = [];
    double score = 0;

    double titleSimilarity = _titleSimilarity(first.title, second.title);
    if (titleSimilarity >= 0.72) {
      score += titleSimilarity * 45;
      reasons.add('titleSimilar'.tr);
    }

    double tagOverlap = _tagOverlap(first.tags, second.tags);
    if (tagOverlap >= 0.45) {
      score += tagOverlap * 30;
      reasons.add('tagOverlap'.tr);
    }

    double importantTagOverlap = _tagOverlap(_importantTags(first.tags), _importantTags(second.tags));
    if (importantTagOverlap >= 0.34) {
      score += importantTagOverlap * 20;
      reasons.add('importantTagOverlap'.tr);
    }

    if (first.category == second.category) {
      score += 8;
      reasons.add('sameCategory'.tr);
    }

    if ((first.pageCount - second.pageCount).abs() <= max(3, (max(first.pageCount, second.pageCount) * 0.08).round())) {
      score += 12;
      reasons.add('pageCountClose'.tr);
    }

    if (score >= 65 && reasons.isNotEmpty) {
      return MangaSimilarityGroup(first: first, second: second, score: min(score, 100), reasons: reasons);
    }

    return null;
  }

  double _titleSimilarity(String a, String b) {
    Set<String> aTokens = _normalizeTitle(a).split(' ').where((token) => token.isNotEmpty).toSet();
    Set<String> bTokens = _normalizeTitle(b).split(' ').where((token) => token.isNotEmpty).toSet();
    if (aTokens.isEmpty || bTokens.isEmpty) {
      return 0;
    }

    return aTokens.intersection(bTokens).length / aTokens.union(bTokens).length;
  }

  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^\)]*\)|【[^】]*】|（[^）]*）'), ' ')
        .replaceAll(RegExp(r'\b(digital|uncensored|ai generated|chinese|english|japanese|korean|translated|translation)\b'), ' ')
        .replaceAll(RegExp(r'漢化|汉化|中文|無修正|无修正|翻訳|翻译'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _tagOverlap(List<TagData> first, List<TagData> second) {
    Set<String> a = first.map((tag) => '${tag.namespace}:${tag.key}').toSet();
    Set<String> b = second.map((tag) => '${tag.namespace}:${tag.key}').toSet();
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }

    return a.intersection(b).length / a.union(b).length;
  }

  List<TagData> _importantTags(List<TagData> tags) {
    const Set<String> namespaces = {'artist', 'group', 'parody', 'character'};
    return tags.where((tag) => namespaces.contains(tag.namespace)).toList();
  }
}




class _ChinesePreferredCandidateResult {
  final Gallery? candidate;
  final String status;
  final String reason;

  const _ChinesePreferredCandidateResult({this.candidate, required this.status, required this.reason});
}

class MangaLibraryBatchTagFillProgress {
  final int totalCount;
  MangaLibraryBatchTagFillStatus status = MangaLibraryBatchTagFillStatus.preparing;
  int currentIndex = 0;
  String currentTitle = '';
  String currentCleanedTitle = '';
  String currentSearchQuery = '';
  int successCount = 0;
  int skippedCount = 0;
  int multipleExactMatchCount = 0;
  int noExactMatchCount = 0;
  int failureCount = 0;
  int failedSearchCount = 0;
  int failedDetailCount = 0;
  int failedWriteCount = 0;
  final List<MangaLibraryBatchTagFillRecord> records = [];

  MangaLibraryBatchTagFillProgress({required this.totalCount});

  bool get isRunning => status == MangaLibraryBatchTagFillStatus.preparing || status == MangaLibraryBatchTagFillStatus.searching || status == MangaLibraryBatchTagFillStatus.fetchingDetail || status == MangaLibraryBatchTagFillStatus.writingTags || status == MangaLibraryBatchTagFillStatus.cancelling;

  double? get progress => totalCount == 0 ? null : currentIndex / totalCount;
}

enum MangaLibraryBatchTagFillStatus {
  preparing,
  searching,
  fetchingDetail,
  writingTags,
  cancelling,
  cancelled,
  completed,
}

class MangaLibraryBatchTagFillRecord {
  final String title;
  final String searchQuery;
  final String status;
  final String reason;

  const MangaLibraryBatchTagFillRecord({required this.title, required this.searchQuery, required this.status, required this.reason});
}

class MangaLibraryDeleteResult {
  int galleryCount = 0;
  int archiveCount = 0;
  int importedFolderCount = 0;
  int pdfCount = 0;
  final List<String> missingOriginalPaths = [];

  void addType(MangaLibraryItemType type) {
    switch (type) {
      case MangaLibraryItemType.gallery:
        galleryCount++;
        break;
      case MangaLibraryItemType.archive:
        archiveCount++;
        break;
      case MangaLibraryItemType.importedFolder:
        importedFolderCount++;
        break;
      case MangaLibraryItemType.pdf:
        pdfCount++;
        break;
    }
  }
}

class MangaLibraryBatchDeleteResult extends MangaLibraryDeleteResult {
  final int totalCount;
  int successCount = 0;
  int failureCount = 0;
  final List<String> failures = [];

  MangaLibraryBatchDeleteResult({required this.totalCount});
}
