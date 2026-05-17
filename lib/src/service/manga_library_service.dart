import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/dao/tag_dao.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/model/gallery_image.dart';
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
import 'package:path/path.dart' as path;

MangaLibraryService mangaLibraryService = MangaLibraryService();

class MangaLibraryService extends GetxController with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String libraryChangedId = 'mangaLibraryChangedId';
  static const String similarityChangedId = 'mangaSimilarityChangedId';

  final List<TagData> selectedTags = [];
  final Set<String> ignoredSimilarityPairs = {};

  String searchKeyword = '';
  MangaLibraryItemType? selectedType;
  String? selectedCategory;
  bool filterMissingTags = false;
  MangaLibrarySortType sortType = MangaLibrarySortType.downloadTimeDesc;
  MangaLibraryDisplayMode displayMode = MangaLibraryDisplayMode.compact;
  final Map<String, TagData> _tagTranslationMap = {};

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
    update([libraryChangedId, similarityChangedId]);
  }

  TagData resolveTagTranslation(TagData tag) {
    return _tagTranslationMap[_tagKey(tag.namespace, tag.key)] ?? tag;
  }

  String _tagKey(String namespace, String key) => '$namespace:$key';

  List<MangaLibraryItem> get items {
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
      );
    }));

    result.addAll(mangaLibraryImportService.importedItems.map((importedItem) {
      MangaLibraryItemType type = importedItem.type == MangaLibraryItemType.pdf.code ? MangaLibraryItemType.pdf : MangaLibraryItemType.importedFolder;
      return MangaLibraryItem(
        type: type,
        title: importedItem.title,
        category: importedItem.category,
        pageCount: importedItem.pageCount,
        uploader: null,
        tags: _translateTags(tagDataString2TagDataList(importedItem.tags)),
        downloadTime: importedItem.createdAt,
        localPath: importedItem.localPath,
        cover: GalleryImage(url: '', path: importedItem.coverPath, downloadStatus: DownloadStatus.downloaded),
      );
    }));

    result.sort((a, b) => b.downloadTime.compareTo(a.downloadTime));
    return result;
  }

  List<TagData> _translateTags(List<TagData> tags) {
    return tags.map(resolveTagTranslation).toList();
  }

  List<MangaLibraryItem> get filteredItems {
    List<MangaLibraryItem> result = items.where((item) {
      if (selectedType != null && item.type != selectedType) {
        return false;
      }

      if (selectedCategory != null && item.category != selectedCategory) {
        return false;
      }

      if (filterMissingTags && item.tags.isNotEmpty) {
        return false;
      }

      if (!filterMissingTags &&
          selectedTags.isNotEmpty &&
          !selectedTags.every((selectedTag) => item.tags.any((tag) => tag.namespace == selectedTag.namespace && tag.key == selectedTag.key))) {
        return false;
      }

      String keyword = _normalizeSearchText(searchKeyword);
      if (keyword.isNotEmpty && !_itemMatchesKeyword(item, keyword)) {
        return false;
      }

      return true;
    }).toList();

    _sortItems(result);
    return result;
  }

  List<String> get availableCategories {
    return items.map((item) => item.category).toSet().toList()..sort();
  }

  bool get hasActiveFilters => searchKeyword.trim().isNotEmpty || selectedType != null || selectedCategory != null || selectedTags.isNotEmpty || filterMissingTags;

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
    update([libraryChangedId]);
  }

  void setSelectedType(MangaLibraryItemType? type) {
    selectedType = type;
    update([libraryChangedId]);
  }

  void setSelectedCategory(String? category) {
    selectedCategory = category;
    update([libraryChangedId]);
  }

  bool isTagSelected(TagData tagData) {
    return selectedTags.any((tag) => tag.namespace == tagData.namespace && tag.key == tagData.key);
  }

  void toggleMissingTagsFilter() {
    filterMissingTags = !filterMissingTags;
    if (filterMissingTags) {
      selectedTags.clear();
    }
    update([libraryChangedId]);
  }

  void clearMissingTagsFilter() {
    if (!filterMissingTags) {
      return;
    }
    filterMissingTags = false;
    update([libraryChangedId]);
  }

  void setSortType(MangaLibrarySortType type) {
    sortType = type;
    update([libraryChangedId]);
  }

  Future<void> setDisplayMode(MangaLibraryDisplayMode mode) async {
    displayMode = mode;
    update([libraryChangedId]);
    await localConfigService.write(configKey: ConfigEnum.mangaLibraryDisplayMode, value: mode.index.toString());
  }

  void toggleSelectedTag(TagData tagData) {
    filterMissingTags = false;
    int index = selectedTags.indexWhere((tag) => tag.namespace == tagData.namespace && tag.key == tagData.key);
    if (index == -1) {
      selectedTags.add(TagData(namespace: tagData.namespace, key: tagData.key));
    } else {
      selectedTags.removeAt(index);
    }
    update([libraryChangedId]);
  }

  void clearSelectedTags() {
    selectedTags.clear();
    update([libraryChangedId]);
  }

  void clearFilters() {
    searchKeyword = '';
    selectedType = null;
    selectedCategory = null;
    filterMissingTags = false;
    selectedTags.clear();
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

  List<MangaSimilarityGroup> get similarityGroups {
    List<MangaLibraryItem> currentItems = items;
    List<MangaSimilarityGroup> result = [];

    for (int i = 0; i < currentItems.length; i++) {
      for (int j = i + 1; j < currentItems.length; j++) {
        MangaSimilarityGroup? group = _compare(currentItems[i], currentItems[j]);
        if (group != null && !ignoredSimilarityPairs.contains(group.pairKey)) {
          result.add(group);
        }
      }
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  Future<void> ignoreSimilarityGroup(MangaSimilarityGroup group) async {
    ignoredSimilarityPairs.add(group.pairKey);
    await localConfigService.write(configKey: ConfigEnum.mangaSimilarityIgnoredPair, subConfigKey: group.pairKey, value: DateTime.now().toString());
    update([similarityChangedId, libraryChangedId]);
  }

  Future<void> deleteItem(MangaLibraryItem item) async {
    if (item.type == MangaLibraryItemType.gallery) {
      await galleryDownloadService.deleteGalleryByGid(item.gid!);
    } else if (item.type == MangaLibraryItemType.archive) {
      await archiveDownloadService.deleteArchive(item.gid!);
    } else {
      await mangaLibraryImportService.deleteImportedItem(item);
    }
    update([libraryChangedId, similarityChangedId]);
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
