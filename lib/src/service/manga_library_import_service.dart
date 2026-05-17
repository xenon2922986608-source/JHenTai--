import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/gallery_download_service.dart';
import 'package:jhentai/src/service/jh_service.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/setting/download_setting.dart';
import 'package:jhentai/src/utils/file_util.dart';
import 'package:path/path.dart';

MangaLibraryImportService mangaLibraryImportService = MangaLibraryImportService();

class MangaLibraryImportService extends GetxController with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String importedItemsChangedId = 'mangaLibraryImportedItemsChangedId';
  static const String importedFolderCategory = 'localFolder';
  static const String pdfCategory = 'PDF';

  final List<MangaLibraryImportedItem> importedItems = [];

  @override
  List<JHLifeCircleBean> get initDependencies => super.initDependencies..addAll([galleryDownloadService, archiveDownloadService, localConfigService]);

  @override
  Future<void> doInitBean() async {
    Get.put(this, permanent: true);
    await refreshImportedItems();
  }

  @override
  Future<void> doAfterBeanReady() async {}

  Future<void> refreshImportedItems() async {
    List<LocalConfig> configs = await localConfigService.readWithAllSubKeys(configKey: ConfigEnum.mangaLibraryImportedItem);
    importedItems
      ..clear()
      ..addAll(configs.map((config) => MangaLibraryImportedItem.fromJson(jsonDecode(config.value))).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));
    update([importedItemsChangedId]);
  }

  Future<DownloadDirectoryScanResult> rescanDownloadDirectory() async {
    DownloadDirectoryScanResult result = DownloadDirectoryScanResult(scanPath: downloadSetting.downloadPath.value, scanTime: DateTime.now().toString());

    result.restoredGalleryCount = await galleryDownloadService.restoreTasks();
    result.restoredArchiveCount = await archiveDownloadService.restoreTasks();

    Directory downloadDir = Directory(downloadSetting.downloadPath.value);
    try {
      if (!await downloadDir.exists()) {
        result.errorCount++;
        result.errors.add('${'downloadPath'.tr}: ${downloadSetting.downloadPath.value}');
        return result;
      }

      await for (FileSystemEntity entity in downloadDir.list(followLinks: false)) {
        try {
          if (entity is Directory) {
            await _scanDirectory(entity, result);
            continue;
          }

          if (entity is File && FileUtil.isPdfExtension(entity.path)) {
            await _upsertPdf(entity, result);
            continue;
          }

          result.skippedCount++;
        } catch (e, stack) {
          result.errorCount++;
          result.errors.add('${entity.path}: $e');
          log.error('Scan download directory item failed: ${entity.path}', e, stack);
        }
      }
    } catch (e, stack) {
      result.errorCount++;
      result.errors.add('${downloadSetting.downloadPath.value}: $e');
      log.error('Scan download directory failed: ${downloadSetting.downloadPath.value}', e, stack);
    }

    await refreshImportedItems();
    return result;
  }

  Future<bool> deleteImportedItem(MangaLibraryItem item, {required bool deleteOriginalFile}) async {
    bool originalExisted = false;

    if (deleteOriginalFile) {
      if (item.type == MangaLibraryItemType.importedFolder) {
        Directory directory = Directory(item.localPath);
        originalExisted = await directory.exists();
        if (originalExisted) {
          await directory.delete(recursive: true);
        }
      } else if (item.type == MangaLibraryItemType.pdf) {
        File file = File(item.localPath);
        originalExisted = await file.exists();
        if (originalExisted) {
          await file.delete();
        }
      }
    }

    await localConfigService.delete(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: item.stableKey);
    await refreshImportedItems();
    return originalExisted;
  }

  Future<void> _scanDirectory(Directory directory, DownloadDirectoryScanResult result) async {
    File galleryMetadata = File(join(directory.path, GalleryDownloadService.metadataFileName));
    File archiveMetadata = File(join(directory.path, ArchiveDownloadService.metadataFileName));
    if (await galleryMetadata.exists() || await archiveMetadata.exists()) {
      result.skippedCount++;
      return;
    }

    List<File> images = await directory
        .list(followLinks: false)
        .where((entity) => entity is File && FileUtil.isImageExtension(entity.path))
        .cast<File>()
        .toList();

    if (images.isEmpty) {
      result.skippedCount++;
      return;
    }

    images.sort(FileUtil.naturalCompareFile);
    await _upsertImportedFolder(directory, images, result);
  }

  Future<void> _upsertImportedFolder(Directory directory, List<File> images, DownloadDirectoryScanResult result) async {
    String now = result.scanTime;
    String itemKey = MangaLibraryItem.buildStableKey(type: MangaLibraryItemType.importedFolder, localPath: directory.path);
    MangaLibraryImportedItem? existed = importedItems.firstWhereOrNull((item) => item.itemKey == itemKey);
    bool existedHasTags = existed?.tags.isNotEmpty ?? false;
    MangaLibraryImportedItem item = MangaLibraryImportedItem(
      itemKey: itemKey,
      type: MangaLibraryItemType.importedFolder.code,
      title: basename(directory.path),
      localPath: directory.path,
      coverPath: images.first.path,
      pageCount: existedHasTags ? (existed?.pageCount ?? images.length) : images.length,
      category: existedHasTags ? (existed?.category ?? importedFolderCategory) : importedFolderCategory,
      tags: existed?.tags ?? '',
      createdAt: existed?.createdAt ?? now,
      updatedAt: now,
      lastScanAt: now,
      sourceGid: existed?.sourceGid,
      sourceToken: existed?.sourceToken,
      sourceGalleryUrl: existed?.sourceGalleryUrl,
      sourceTitle: existed?.sourceTitle,
      sourceUploader: existed?.sourceUploader,
      tagUpdatedAt: existed?.tagUpdatedAt,
    );

    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: itemKey, value: jsonEncode(item.toJson()));

    if (existed == null) {
      result.importedFolderCount++;
      importedItems.add(item);
    } else {
      result.updatedImportedCount++;
      importedItems[importedItems.indexWhere((i) => i.itemKey == itemKey)] = item;
    }
  }

  Future<void> _upsertPdf(File file, DownloadDirectoryScanResult result) async {
    String now = result.scanTime;
    String itemKey = MangaLibraryItem.buildStableKey(type: MangaLibraryItemType.pdf, localPath: file.path);
    MangaLibraryImportedItem? existed = importedItems.firstWhereOrNull((item) => item.itemKey == itemKey);
    bool existedHasTags = existed?.tags.isNotEmpty ?? false;
    MangaLibraryImportedItem item = MangaLibraryImportedItem(
      itemKey: itemKey,
      type: MangaLibraryItemType.pdf.code,
      title: basenameWithoutExtension(file.path),
      localPath: file.path,
      coverPath: null,
      pageCount: existedHasTags ? (existed?.pageCount ?? 0) : 0,
      category: existedHasTags ? (existed?.category ?? pdfCategory) : pdfCategory,
      tags: existed?.tags ?? '',
      createdAt: existed?.createdAt ?? now,
      updatedAt: now,
      lastScanAt: now,
      sourceGid: existed?.sourceGid,
      sourceToken: existed?.sourceToken,
      sourceGalleryUrl: existed?.sourceGalleryUrl,
      sourceTitle: existed?.sourceTitle,
      sourceUploader: existed?.sourceUploader,
      tagUpdatedAt: existed?.tagUpdatedAt,
    );

    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: itemKey, value: jsonEncode(item.toJson()));

    if (existed == null) {
      result.importedPdfCount++;
      importedItems.add(item);
    } else {
      result.updatedImportedCount++;
      importedItems[importedItems.indexWhere((i) => i.itemKey == itemKey)] = item;
    }
  }

  Future<void> updateImportedItemTags({
    required MangaLibraryItem item,
    required String tags,
    int? sourceGid,
    String? sourceToken,
    String? sourceGalleryUrl,
    String? sourceTitle,
    String? sourceUploader,
    String? category,
    String? uploader,
    int? pageCount,
  }) async {
    int index = importedItems.indexWhere((importedItem) => importedItem.itemKey == item.stableKey);
    if (index == -1) {
      throw Exception('mangaLibraryItemNotFound'.tr);
    }

    MangaLibraryImportedItem existed = importedItems[index];
    String now = DateTime.now().toString();
    MangaLibraryImportedItem updated = existed.copyWith(
      tags: tags,
      category: category,
      pageCount: pageCount,
      sourceGid: sourceGid,
      sourceToken: sourceToken,
      sourceGalleryUrl: sourceGalleryUrl,
      sourceTitle: sourceTitle,
      sourceUploader: sourceUploader ?? uploader,
      tagUpdatedAt: now,
      updatedAt: now,
    );

    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: updated.itemKey, value: jsonEncode(updated.toJson()));
    importedItems[index] = updated;
    update([importedItemsChangedId]);
  }

}

class MangaLibraryImportedItem {
  final String itemKey;
  final String type;
  final String title;
  final String localPath;
  final String? coverPath;
  final int pageCount;
  final String category;
  final String tags;
  final String createdAt;
  final String updatedAt;
  final String lastScanAt;
  final int? sourceGid;
  final String? sourceToken;
  final String? sourceGalleryUrl;
  final String? sourceTitle;
  final String? sourceUploader;
  final String? tagUpdatedAt;

  const MangaLibraryImportedItem({
    required this.itemKey,
    required this.type,
    required this.title,
    required this.localPath,
    required this.coverPath,
    required this.pageCount,
    required this.category,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.lastScanAt,
    this.sourceGid,
    this.sourceToken,
    this.sourceGalleryUrl,
    this.sourceTitle,
    this.sourceUploader,
    this.tagUpdatedAt,
  });

  factory MangaLibraryImportedItem.fromJson(Map<String, dynamic> json) {
    return MangaLibraryImportedItem(
      itemKey: json['itemKey'],
      type: json['type'],
      title: json['title'],
      localPath: json['localPath'],
      coverPath: json['coverPath'],
      pageCount: json['pageCount'] ?? 0,
      category: json['category'],
      tags: json['tags'] ?? '',
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
      lastScanAt: json['lastScanAt'],
      sourceGid: json['sourceGid'],
      sourceToken: json['sourceToken'],
      sourceGalleryUrl: json['sourceGalleryUrl'],
      sourceTitle: json['sourceTitle'],
      sourceUploader: json['sourceUploader'],
      tagUpdatedAt: json['tagUpdatedAt'],
    );
  }

  MangaLibraryImportedItem copyWith({
    String? itemKey,
    String? type,
    String? title,
    String? localPath,
    String? coverPath,
    int? pageCount,
    String? category,
    String? tags,
    String? createdAt,
    String? updatedAt,
    String? lastScanAt,
    int? sourceGid,
    String? sourceToken,
    String? sourceGalleryUrl,
    String? sourceTitle,
    String? sourceUploader,
    String? tagUpdatedAt,
  }) {
    return MangaLibraryImportedItem(
      itemKey: itemKey ?? this.itemKey,
      type: type ?? this.type,
      title: title ?? this.title,
      localPath: localPath ?? this.localPath,
      coverPath: coverPath ?? this.coverPath,
      pageCount: pageCount ?? this.pageCount,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      sourceGid: sourceGid ?? this.sourceGid,
      sourceToken: sourceToken ?? this.sourceToken,
      sourceGalleryUrl: sourceGalleryUrl ?? this.sourceGalleryUrl,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      sourceUploader: sourceUploader ?? this.sourceUploader,
      tagUpdatedAt: tagUpdatedAt ?? this.tagUpdatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemKey': itemKey,
      'type': type,
      'title': title,
      'localPath': localPath,
      'coverPath': coverPath,
      'pageCount': pageCount,
      'category': category,
      'tags': tags,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'lastScanAt': lastScanAt,
      'sourceGid': sourceGid,
      'sourceToken': sourceToken,
      'sourceGalleryUrl': sourceGalleryUrl,
      'sourceTitle': sourceTitle,
      'sourceUploader': sourceUploader,
      'tagUpdatedAt': tagUpdatedAt,
    };
  }
}

class DownloadDirectoryScanResult {
  final String scanPath;
  final String scanTime;
  int restoredGalleryCount = 0;
  int restoredArchiveCount = 0;
  int importedFolderCount = 0;
  int importedPdfCount = 0;
  int updatedImportedCount = 0;
  int skippedCount = 0;
  int errorCount = 0;
  final List<String> errors = [];

  DownloadDirectoryScanResult({required this.scanPath, required this.scanTime});
}
