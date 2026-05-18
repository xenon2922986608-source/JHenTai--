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
import 'package:jhentai/src/utils/convert_util.dart';
import 'package:jhentai/src/utils/file_util.dart';
import 'package:path/path.dart';

MangaLibraryImportService mangaLibraryImportService = MangaLibraryImportService();

class MangaLibraryImportService extends GetxController with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String importedItemsChangedId = 'mangaLibraryImportedItemsChangedId';
  static const String importedFolderCategory = 'localFolder';
  static const String pdfCategory = 'PDF';
  static const String sidecarFileName = '.jhentai-library.json';
  static const int sidecarSchemaVersion = 1;

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
    MangaLibrarySidecarMetadata? sidecar = await _readSidecarMetadata(
      type: MangaLibraryItemType.importedFolder,
      localPath: directory.path,
      result: result,
    );
    MangaLibraryImportedItem? selectedMetadata = _selectImportedMetadata(existed: existed, sidecar: sidecar);
    bool shouldSyncSidecarFromLocal = existed != null && selectedMetadata == existed && _hasPortableMetadata(existed);
    bool selectedHasTags = selectedMetadata?.tags.isNotEmpty ?? false;
    MangaLibraryImportedItem item = MangaLibraryImportedItem(
      itemKey: itemKey,
      type: MangaLibraryItemType.importedFolder.code,
      title: selectedMetadata?.title ?? basename(directory.path),
      localPath: directory.path,
      coverPath: images.first.path,
      pageCount: selectedHasTags ? (selectedMetadata?.pageCount ?? images.length) : (sidecar?.pageCount ?? images.length),
      category: selectedMetadata?.category ?? sidecar?.category ?? importedFolderCategory,
      tags: selectedMetadata?.tags ?? sidecar?.tags ?? '',
      createdAt: existed?.createdAt ?? now,
      updatedAt: selectedMetadata?.updatedAt ?? sidecar?.updatedAt ?? now,
      lastScanAt: now,
      sourceGid: selectedMetadata?.sourceGid ?? sidecar?.sourceGid,
      sourceToken: selectedMetadata?.sourceToken ?? sidecar?.sourceToken,
      sourceGalleryUrl: selectedMetadata?.sourceGalleryUrl ?? sidecar?.sourceGalleryUrl,
      sourceTitle: selectedMetadata?.sourceTitle ?? sidecar?.sourceTitle,
      sourceCategory: selectedMetadata?.sourceCategory ?? sidecar?.sourceCategory,
      sourceUploader: selectedMetadata?.sourceUploader ?? sidecar?.sourceUploader,
      tagUpdatedAt: selectedMetadata?.tagUpdatedAt ?? sidecar?.tagUpdatedAt,
      sidecarPath: _sidecarPathFor(type: MangaLibraryItemType.importedFolder, localPath: directory.path),
      hasSidecarMetadata: sidecar != null,
      organized: selectedMetadata?.organized ?? sidecar?.organized ?? false,
      organizedUpdatedAt: selectedMetadata?.organizedUpdatedAt ?? sidecar?.organizedUpdatedAt,
    );

    if (shouldSyncSidecarFromLocal && await _tryWriteSidecarAfterScan(item, result)) {
      item = item.copyWith(hasSidecarMetadata: true);
    }
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
    MangaLibrarySidecarMetadata? sidecar = await _readSidecarMetadata(
      type: MangaLibraryItemType.pdf,
      localPath: file.path,
      result: result,
    );
    MangaLibraryImportedItem? selectedMetadata = _selectImportedMetadata(existed: existed, sidecar: sidecar);
    bool shouldSyncSidecarFromLocal = existed != null && selectedMetadata == existed && _hasPortableMetadata(existed);
    bool selectedHasTags = selectedMetadata?.tags.isNotEmpty ?? false;
    MangaLibraryImportedItem item = MangaLibraryImportedItem(
      itemKey: itemKey,
      type: MangaLibraryItemType.pdf.code,
      title: selectedMetadata?.title ?? sidecar?.title ?? basenameWithoutExtension(file.path),
      localPath: file.path,
      coverPath: null,
      pageCount: selectedHasTags ? (selectedMetadata?.pageCount ?? 0) : (sidecar?.pageCount ?? 0),
      category: selectedMetadata?.category ?? sidecar?.category ?? pdfCategory,
      tags: selectedMetadata?.tags ?? sidecar?.tags ?? '',
      createdAt: existed?.createdAt ?? now,
      updatedAt: selectedMetadata?.updatedAt ?? sidecar?.updatedAt ?? now,
      lastScanAt: now,
      sourceGid: selectedMetadata?.sourceGid ?? sidecar?.sourceGid,
      sourceToken: selectedMetadata?.sourceToken ?? sidecar?.sourceToken,
      sourceGalleryUrl: selectedMetadata?.sourceGalleryUrl ?? sidecar?.sourceGalleryUrl,
      sourceTitle: selectedMetadata?.sourceTitle ?? sidecar?.sourceTitle,
      sourceCategory: selectedMetadata?.sourceCategory ?? sidecar?.sourceCategory,
      sourceUploader: selectedMetadata?.sourceUploader ?? sidecar?.sourceUploader,
      tagUpdatedAt: selectedMetadata?.tagUpdatedAt ?? sidecar?.tagUpdatedAt,
      sidecarPath: _sidecarPathFor(type: MangaLibraryItemType.pdf, localPath: file.path),
      hasSidecarMetadata: sidecar != null,
      organized: selectedMetadata?.organized ?? sidecar?.organized ?? false,
      organizedUpdatedAt: selectedMetadata?.organizedUpdatedAt ?? sidecar?.organizedUpdatedAt,
    );

    if (shouldSyncSidecarFromLocal && await _tryWriteSidecarAfterScan(item, result)) {
      item = item.copyWith(hasSidecarMetadata: true);
    }
    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: itemKey, value: jsonEncode(item.toJson()));

    if (existed == null) {
      result.importedPdfCount++;
      importedItems.add(item);
    } else {
      result.updatedImportedCount++;
      importedItems[importedItems.indexWhere((i) => i.itemKey == itemKey)] = item;
    }
  }

  String? sidecarPathForItem(MangaLibraryItem item) {
    if (!item.isImported) {
      return null;
    }
    return _sidecarPathFor(type: item.type, localPath: item.localPath);
  }

  bool sidecarExistsForItem(MangaLibraryItem item) {
    String? sidecarPath = sidecarPathForItem(item);
    return sidecarPath != null && File(sidecarPath).existsSync();
  }

  bool _hasPortableMetadata(MangaLibraryImportedItem item) {
    return item.tags.isNotEmpty ||
        item.sourceGid != null ||
        (item.sourceToken?.trim().isNotEmpty ?? false) ||
        (item.sourceGalleryUrl?.trim().isNotEmpty ?? false) ||
        (item.sourceTitle?.trim().isNotEmpty ?? false) ||
        (item.sourceCategory?.trim().isNotEmpty ?? false) ||
        (item.sourceUploader?.trim().isNotEmpty ?? false) ||
        (item.tagUpdatedAt?.trim().isNotEmpty ?? false) ||
        item.organized ||
        (item.organizedUpdatedAt?.trim().isNotEmpty ?? false);
  }

  int _tagCount(String tags) => tags.trim().isEmpty ? 0 : tags.split(',').where((tag) => tag.trim().isNotEmpty).length;

  int _portableMetadataScore(MangaLibraryImportedItem item) {
    int score = _tagCount(item.tags) * 10;
    if (item.sourceGid != null) {
      score++;
    }
    if (item.sourceToken?.trim().isNotEmpty ?? false) {
      score++;
    }
    if (item.sourceGalleryUrl?.trim().isNotEmpty ?? false) {
      score++;
    }
    if (item.sourceTitle?.trim().isNotEmpty ?? false) {
      score++;
    }
    if (item.sourceCategory?.trim().isNotEmpty ?? false) {
      score++;
    }
    if (item.sourceUploader?.trim().isNotEmpty ?? false) {
      score++;
    }
    if (item.tagUpdatedAt?.trim().isNotEmpty ?? false) {
      score++;
    }
    if (item.organized) {
      score++;
    }
    if (item.organizedUpdatedAt?.trim().isNotEmpty ?? false) {
      score++;
    }
    return score;
  }

  String _sidecarPathFor({required MangaLibraryItemType type, required String localPath}) {
    if (type == MangaLibraryItemType.importedFolder) {
      return join(localPath, sidecarFileName);
    }
    return '$localPath.jhentai-library.json';
  }

  Future<MangaLibrarySidecarMetadata?> _readSidecarMetadata({required MangaLibraryItemType type, required String localPath, DownloadDirectoryScanResult? result}) async {
    String sidecarPath = _sidecarPathFor(type: type, localPath: localPath);
    File sidecarFile = File(sidecarPath);
    if (!await sidecarFile.exists()) {
      return null;
    }

    try {
      Map<String, dynamic> json = jsonDecode(await sidecarFile.readAsString()) as Map<String, dynamic>;
      return MangaLibrarySidecarMetadata.fromJson(json, fallbackType: type, sidecarPath: sidecarPath);
    } catch (e, stack) {
      result?.errorCount++;
      result?.errors.add('${'libraryMetadataReadFailed'.tr}: $sidecarPath: $e');
      log.error('Read manga library sidecar metadata failed: $sidecarPath', e, stack);
      return null;
    }
  }

  MangaLibraryImportedItem? _selectImportedMetadata({required MangaLibraryImportedItem? existed, required MangaLibrarySidecarMetadata? sidecar}) {
    if (sidecar == null) {
      return existed;
    }
    MangaLibraryImportedItem sidecarItem = sidecar.toImportedItem(existing: existed);
    if (existed == null) {
      return sidecarItem;
    }

    int existedTagCount = _tagCount(existed.tags);
    int sidecarTagCount = _tagCount(sidecar.tags);
    if (existedTagCount == 0 && sidecarTagCount > 0) {
      return sidecarItem;
    }
    if (existedTagCount > 0 && sidecarTagCount == 0) {
      return existed;
    }

    DateTime? existedTime = _parseMetadataTime(existed.tagUpdatedAt ?? existed.updatedAt);
    DateTime? sidecarTime = _parseMetadataTime(sidecar.tagUpdatedAt ?? sidecar.updatedAt);
    if (existedTime != null && sidecarTime != null && existedTime != sidecarTime) {
      return sidecarTime.isAfter(existedTime) ? sidecarItem : existed;
    }

    DateTime? existedOrganizedTime = _parseMetadataTime(existed.organizedUpdatedAt);
    DateTime? sidecarOrganizedTime = _parseMetadataTime(sidecar.organizedUpdatedAt);
    if (existedOrganizedTime != null && sidecarOrganizedTime != null && existedOrganizedTime != sidecarOrganizedTime) {
      return sidecarOrganizedTime.isAfter(existedOrganizedTime) ? sidecarItem : existed;
    }
    if (existed.organized && sidecar.organized == null) {
      return existed;
    }

    int existedMetadataScore = _portableMetadataScore(existed);
    int sidecarMetadataScore = _portableMetadataScore(sidecarItem);
    if (sidecarMetadataScore > existedMetadataScore) {
      return sidecarItem;
    }
    return existed;
  }

  DateTime? _parseMetadataTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  Future<void> exportItemSidecar(MangaLibraryItem item) async {
    if (!item.isImported) {
      throw Exception('invalidMangaLibraryItem'.tr);
    }
    int index = importedItems.indexWhere((importedItem) => importedItem.itemKey == item.stableKey);
    if (index == -1) {
      throw Exception('mangaLibraryItemNotFound'.tr);
    }
    MangaLibraryImportedItem updated = importedItems[index].copyWith(
      sidecarPath: _sidecarPathFor(type: item.type, localPath: item.localPath),
      hasSidecarMetadata: true,
    );
    await _writeSidecar(updated);
    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: updated.itemKey, value: jsonEncode(updated.toJson()));
    importedItems[index] = updated;
    update([importedItemsChangedId]);
  }

  Future<MangaLibraryMetadataExportResult> exportAllSidecars() async {
    MangaLibraryMetadataExportResult result = MangaLibraryMetadataExportResult(exportTime: DateTime.now().toString());
    for (int index = 0; index < importedItems.length; index++) {
      MangaLibraryImportedItem item = importedItems[index];
      try {
        if (!_hasPortableMetadata(item)) {
          result.skippedCount++;
          continue;
        }

        MangaLibraryItemType type = item.type == MangaLibraryItemType.pdf.code ? MangaLibraryItemType.pdf : MangaLibraryItemType.importedFolder;
        MangaLibrarySidecarMetadata? sidecar = await _readSidecarMetadata(type: type, localPath: item.localPath, result: null);
        MangaLibraryImportedItem? selected = _selectImportedMetadata(existed: item, sidecar: sidecar);
        if (sidecar != null && selected != item) {
          result.skippedCount++;
          result.conflicts.add('${item.title}: ${'libraryMetadataSidecarNewer'.tr}');
          continue;
        }

        MangaLibraryImportedItem updated = item.copyWith(
          sidecarPath: _sidecarPathFor(type: type, localPath: item.localPath),
          hasSidecarMetadata: true,
        );
        await _writeSidecar(updated);
        await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: updated.itemKey, value: jsonEncode(updated.toJson()));
        importedItems[index] = updated;
        result.successCount++;
      } catch (e, stack) {
        result.failureCount++;
        result.failures.add('${item.title} (${item.localPath}): $e');
        log.error('Export manga library sidecar metadata failed: ${item.localPath}', e, stack);
      }
    }
    update([importedItemsChangedId]);
    return result;
  }

  Future<void> _writeSidecar(MangaLibraryImportedItem item) async {
    MangaLibraryItemType type = item.type == MangaLibraryItemType.pdf.code ? MangaLibraryItemType.pdf : MangaLibraryItemType.importedFolder;
    String sidecarPath = item.sidecarPath ?? _sidecarPathFor(type: type, localPath: item.localPath);
    File sidecarFile = File(sidecarPath);
    await sidecarFile.parent.create(recursive: true);
    Map<String, dynamic> json = MangaLibrarySidecarMetadata.fromImportedItem(item, sidecarPath: sidecarPath).toJson();
    await sidecarFile.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  Future<bool> _tryWriteSidecarAfterScan(MangaLibraryImportedItem item, DownloadDirectoryScanResult result) async {
    try {
      await _writeSidecar(item);
      return true;
    } catch (e, stack) {
      result.errorCount++;
      result.errors.add('${'libraryMetadataWriteFailed'.tr}: ${item.localPath}: $e');
      log.error('Sync manga library sidecar metadata after scan failed: ${item.localPath}', e, stack);
      return false;
    }
  }

  Future<bool> updateImportedItemOrganized({required MangaLibraryItem item, required bool organized, required String organizedUpdatedAt}) async {
    int index = importedItems.indexWhere((importedItem) => importedItem.itemKey == item.stableKey);
    if (index == -1) {
      throw Exception('mangaLibraryItemNotFound'.tr);
    }

    MangaLibraryImportedItem existed = importedItems[index];
    MangaLibraryImportedItem updated = existed.copyWith(
      organized: organized,
      organizedUpdatedAt: organizedUpdatedAt,
      updatedAt: organizedUpdatedAt,
      sidecarPath: existed.sidecarPath ?? _sidecarPathFor(type: item.type, localPath: item.localPath),
      hasSidecarMetadata: existed.hasSidecarMetadata,
    );

    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: updated.itemKey, value: jsonEncode(updated.toJson()));
    importedItems[index] = updated;
    update([importedItemsChangedId]);

    try {
      MangaLibraryImportedItem synced = updated.copyWith(hasSidecarMetadata: true);
      await _writeSidecar(synced);
      await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: synced.itemKey, value: jsonEncode(synced.toJson()));
      importedItems[index] = synced;
      update([importedItemsChangedId]);
      return true;
    } catch (e, stack) {
      log.error('Sync manga library organized metadata failed: ${item.localPath}', e, stack);
      return false;
    }
  }


  Future<void> updateImportedItemPageCount({required MangaLibraryItem item, required int pageCount}) async {
    int index = importedItems.indexWhere((importedItem) => importedItem.itemKey == item.stableKey);
    if (index == -1) {
      throw Exception('mangaLibraryItemNotFound'.tr);
    }

    MangaLibraryImportedItem existed = importedItems[index];
    String now = DateTime.now().toString();
    MangaLibraryImportedItem updated = existed.copyWith(
      pageCount: pageCount,
      updatedAt: now,
      sidecarPath: existed.sidecarPath ?? _sidecarPathFor(type: item.type, localPath: item.localPath),
      hasSidecarMetadata: existed.hasSidecarMetadata,
    );

    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: updated.itemKey, value: jsonEncode(updated.toJson()));
    importedItems[index] = updated;
    update([importedItemsChangedId]);

    if (updated.hasSidecarMetadata) {
      try {
        await _writeSidecar(updated);
      } catch (e, stack) {
        log.error('Sync manga library PDF page count failed: ${item.localPath}', e, stack);
      }
    }
  }

  Future<void> updateImportedItemTags({
    required MangaLibraryItem item,
    required String tags,
    int? sourceGid,
    String? sourceToken,
    String? sourceGalleryUrl,
    String? sourceTitle,
    String? sourceCategory,
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
      sourceCategory: sourceCategory ?? category,
      sourceUploader: sourceUploader ?? uploader,
      tagUpdatedAt: now,
      updatedAt: now,
      sidecarPath: existed.sidecarPath ?? _sidecarPathFor(type: item.type, localPath: item.localPath),
      hasSidecarMetadata: existed.hasSidecarMetadata,
    );

    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: updated.itemKey, value: jsonEncode(updated.toJson()));
    importedItems[index] = updated;
    update([importedItemsChangedId]);

    MangaLibraryImportedItem synced = updated.copyWith(hasSidecarMetadata: true);
    await _writeSidecar(synced);
    await localConfigService.write(configKey: ConfigEnum.mangaLibraryImportedItem, subConfigKey: synced.itemKey, value: jsonEncode(synced.toJson()));
    importedItems[index] = synced;
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
  final String? sourceCategory;
  final String? sourceUploader;
  final String? tagUpdatedAt;
  final String? sidecarPath;
  final bool hasSidecarMetadata;
  final bool organized;
  final String? organizedUpdatedAt;

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
    this.sourceCategory,
    this.sourceUploader,
    this.tagUpdatedAt,
    this.sidecarPath,
    this.hasSidecarMetadata = false,
    this.organized = false,
    this.organizedUpdatedAt,
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
      sourceCategory: json['sourceCategory'],
      sourceUploader: json['sourceUploader'],
      tagUpdatedAt: json['tagUpdatedAt'],
      sidecarPath: json['sidecarPath'],
      hasSidecarMetadata: json['hasSidecarMetadata'] ?? false,
      organized: json['organized'] ?? json['greenLabel'] ?? false,
      organizedUpdatedAt: json['organizedUpdatedAt'] ?? json['greenLabelUpdatedAt'],
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
    String? sourceCategory,
    String? sourceUploader,
    String? tagUpdatedAt,
    String? sidecarPath,
    bool? hasSidecarMetadata,
    bool? organized,
    String? organizedUpdatedAt,
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
      sourceCategory: sourceCategory ?? this.sourceCategory,
      sourceUploader: sourceUploader ?? this.sourceUploader,
      tagUpdatedAt: tagUpdatedAt ?? this.tagUpdatedAt,
      sidecarPath: sidecarPath ?? this.sidecarPath,
      hasSidecarMetadata: hasSidecarMetadata ?? this.hasSidecarMetadata,
      organized: organized ?? this.organized,
      organizedUpdatedAt: organizedUpdatedAt ?? this.organizedUpdatedAt,
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
      'sourceCategory': sourceCategory,
      'sourceUploader': sourceUploader,
      'tagUpdatedAt': tagUpdatedAt,
      'sidecarPath': sidecarPath,
      'hasSidecarMetadata': hasSidecarMetadata,
      'organized': organized,
      'organizedUpdatedAt': organizedUpdatedAt,
    };
  }
}

class MangaLibrarySidecarMetadata {
  final MangaLibraryItemType type;
  final String? title;
  final String? category;
  final int? pageCount;
  final String tags;
  final int? sourceGid;
  final String? sourceToken;
  final String? sourceGalleryUrl;
  final String? sourceTitle;
  final String? sourceCategory;
  final String? sourceUploader;
  final String? tagUpdatedAt;
  final String? updatedAt;
  final String? sidecarPath;
  final bool? organized;
  final String? organizedUpdatedAt;

  const MangaLibrarySidecarMetadata({
    required this.type,
    this.title,
    this.category,
    this.pageCount,
    required this.tags,
    this.sourceGid,
    this.sourceToken,
    this.sourceGalleryUrl,
    this.sourceTitle,
    this.sourceCategory,
    this.sourceUploader,
    this.tagUpdatedAt,
    this.updatedAt,
    this.sidecarPath,
    this.organized,
    this.organizedUpdatedAt,
  });

  factory MangaLibrarySidecarMetadata.fromJson(Map<String, dynamic> json, {required MangaLibraryItemType fallbackType, String? sidecarPath}) {
    Map<String, dynamic> source = (json['source'] is Map) ? Map<String, dynamic>.from(json['source']) : <String, dynamic>{};
    MangaLibraryItemType type = json['libraryType'] == MangaLibraryItemType.pdf.code ? MangaLibraryItemType.pdf : fallbackType;
    return MangaLibrarySidecarMetadata(
      type: type,
      title: json['title'],
      category: json['category'],
      pageCount: (json['pageCount'] as num?)?.toInt(),
      tags: _decodeSidecarTags(json['tags']),
      sourceGid: (source['gid'] as num?)?.toInt() ?? (json['sourceGid'] as num?)?.toInt(),
      sourceToken: source['token'] ?? json['sourceToken'],
      sourceGalleryUrl: source['galleryUrl'] ?? json['sourceGalleryUrl'],
      sourceTitle: source['title'] ?? json['sourceTitle'],
      sourceCategory: source['category'] ?? json['sourceCategory'],
      sourceUploader: source['uploader'] ?? json['sourceUploader'],
      tagUpdatedAt: json['tagUpdatedAt'],
      updatedAt: json['updatedAt'],
      sidecarPath: sidecarPath,
      organized: json['organized'] ?? json['greenLabel'],
      organizedUpdatedAt: json['organizedUpdatedAt'] ?? json['greenLabelUpdatedAt'],
    );
  }

  factory MangaLibrarySidecarMetadata.fromImportedItem(MangaLibraryImportedItem item, {String? sidecarPath}) {
    MangaLibraryItemType type = item.type == MangaLibraryItemType.pdf.code ? MangaLibraryItemType.pdf : MangaLibraryItemType.importedFolder;
    return MangaLibrarySidecarMetadata(
      type: type,
      title: item.title,
      category: item.category,
      pageCount: item.pageCount,
      tags: item.tags,
      sourceGid: item.sourceGid,
      sourceToken: item.sourceToken,
      sourceGalleryUrl: item.sourceGalleryUrl,
      sourceTitle: item.sourceTitle,
      sourceCategory: item.sourceCategory,
      sourceUploader: item.sourceUploader,
      tagUpdatedAt: item.tagUpdatedAt,
      updatedAt: item.updatedAt,
      sidecarPath: sidecarPath ?? item.sidecarPath,
      organized: item.organized,
      organizedUpdatedAt: item.organizedUpdatedAt,
    );
  }

  MangaLibraryImportedItem toImportedItem({MangaLibraryImportedItem? existing}) {
    String now = DateTime.now().toString();
    return MangaLibraryImportedItem(
      itemKey: existing?.itemKey ?? '',
      type: type.code,
      title: title ?? existing?.title ?? '',
      localPath: existing?.localPath ?? '',
      coverPath: existing?.coverPath,
      pageCount: pageCount ?? existing?.pageCount ?? 0,
      category: category ?? existing?.category ?? (type == MangaLibraryItemType.pdf ? MangaLibraryImportService.pdfCategory : MangaLibraryImportService.importedFolderCategory),
      tags: tags.isNotEmpty ? tags : (existing?.tags ?? ''),
      createdAt: existing?.createdAt ?? updatedAt ?? now,
      updatedAt: updatedAt ?? existing?.updatedAt ?? now,
      lastScanAt: existing?.lastScanAt ?? now,
      sourceGid: sourceGid ?? existing?.sourceGid,
      sourceToken: sourceToken ?? existing?.sourceToken,
      sourceGalleryUrl: sourceGalleryUrl ?? existing?.sourceGalleryUrl,
      sourceTitle: sourceTitle ?? existing?.sourceTitle,
      sourceCategory: sourceCategory ?? existing?.sourceCategory,
      sourceUploader: sourceUploader ?? existing?.sourceUploader,
      tagUpdatedAt: tagUpdatedAt ?? existing?.tagUpdatedAt,
      sidecarPath: sidecarPath ?? existing?.sidecarPath,
      hasSidecarMetadata: true,
      organized: organized ?? existing?.organized ?? false,
      organizedUpdatedAt: organizedUpdatedAt ?? existing?.organizedUpdatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': MangaLibraryImportService.sidecarSchemaVersion,
      'app': 'JHenTai',
      'libraryType': type.code,
      'title': title,
      'category': category,
      'pageCount': pageCount,
      'tags': _encodeSidecarTags(tags),
      'source': {
        'gid': sourceGid,
        'token': sourceToken,
        'galleryUrl': sourceGalleryUrl,
        'title': sourceTitle,
        'category': sourceCategory,
        'uploader': sourceUploader,
      },
      'tagUpdatedAt': tagUpdatedAt,
      'updatedAt': updatedAt ?? DateTime.now().toString(),
      'organized': organized ?? false,
      'organizedUpdatedAt': organizedUpdatedAt,
      'lastKnownPath': sidecarPath,
    };
  }

  static List<Map<String, dynamic>> _encodeSidecarTags(String tags) {
    return tagDataString2TagDataList(tags).map((tag) {
      return {
        'namespace': tag.namespace,
        'key': tag.key,
        'translatedNamespace': tag.translatedNamespace,
        'tagName': tag.tagName,
        'fullTagName': tag.fullTagName,
      };
    }).toList();
  }

  static String _decodeSidecarTags(dynamic tags) {
    if (tags is String) {
      return tags;
    }
    if (tags is! List) {
      return '';
    }

    return tags.map((tag) {
      if (tag is String) {
        return tag;
      }
      if (tag is Map) {
        String namespace = '${tag['namespace'] ?? ''}'.trim();
        String key = '${tag['key'] ?? tag['tagName'] ?? ''}'.trim();
        if (namespace.isEmpty || key.isEmpty) {
          return '';
        }
        return '$namespace:$key';
      }
      return '';
    }).where((tag) => tag.isNotEmpty).join(',');
  }
}

class MangaLibraryMetadataExportResult {
  final String exportTime;
  int successCount = 0;
  int skippedCount = 0;
  int failureCount = 0;
  final List<String> conflicts = [];
  final List<String> failures = [];

  int get conflictCount => conflicts.length;

  MangaLibraryMetadataExportResult({required this.exportTime});
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
