import 'dart:math';

import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/gallery_download_service.dart';
import 'package:jhentai/src/service/jh_service.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import 'package:jhentai/src/utils/convert_util.dart';

MangaLibraryService mangaLibraryService = MangaLibraryService();

class MangaLibraryService extends GetxController with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String libraryChangedId = 'mangaLibraryChangedId';
  static const String similarityChangedId = 'mangaSimilarityChangedId';

  final List<TagData> selectedTags = [];
  final Set<String> ignoredSimilarityPairs = {};

  @override
  List<JHLifeCircleBean> get initDependencies => super.initDependencies..addAll([galleryDownloadService, archiveDownloadService, localConfigService]);

  @override
  Future<void> doInitBean() async {
    Get.put(this, permanent: true);
    await _loadIgnoredSimilarityPairs();
  }

  @override
  Future<void> doAfterBeanReady() async {}

  Future<void> _loadIgnoredSimilarityPairs() async {
    ignoredSimilarityPairs
      ..clear()
      ..addAll((await localConfigService.readWithAllSubKeys(configKey: ConfigEnum.mangaSimilarityIgnoredPair)).map((config) => config.subConfigKey));
  }

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
        tags: tagDataString2TagDataList(gallery.tags),
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
        tags: tagDataString2TagDataList(archive.tags),
        downloadTime: archive.insertTime,
        localPath: archiveDownloadService.computeArchiveUnpackingPath(archive.title, archive.gid),
        cover: GalleryImage(url: archive.coverUrl),
        isOriginal: archive.isOriginal,
      );
    }));

    result.sort((a, b) => b.downloadTime.compareTo(a.downloadTime));
    return result;
  }

  List<MangaLibraryItem> get filteredItems {
    if (selectedTags.isEmpty) {
      return items;
    }

    return items.where((item) {
      return selectedTags.every((selectedTag) => item.tags.any((tag) => tag.namespace == selectedTag.namespace && tag.key == selectedTag.key));
    }).toList();
  }

  void toggleSelectedTag(TagData tagData) {
    int index = selectedTags.indexWhere((tag) => tag.namespace == tagData.namespace && tag.key == tagData.key);
    if (index == -1) {
      selectedTags.add(tagData);
    } else {
      selectedTags.removeAt(index);
    }
    update([libraryChangedId]);
  }

  void clearSelectedTags() {
    selectedTags.clear();
    update([libraryChangedId]);
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
      await galleryDownloadService.deleteGalleryByGid(item.gid);
    } else {
      await archiveDownloadService.deleteArchive(item.gid);
    }
    update([libraryChangedId, similarityChangedId]);
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
