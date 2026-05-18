import 'dart:convert';

import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/service/jh_service.dart';
import 'package:jhentai/src/service/local_config_service.dart';

ReadProgressService readProgressService = ReadProgressService();

class ReadProgressService extends GetxController with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String readProgressUpdateId = 'readProgress';

  @override
  List<JHLifeCircleBean> get initDependencies => super.initDependencies..addAll([localConfigService]);

  /// Cache for read progress: gid -> readIndex
  final Map<String, int> _progressCache = {};
  final Map<String, MangaLibraryPdfReadProgress> _pdfProgressCache = {};

  @override
  Future<void> doInitBean() async {
    Get.put(this, permanent: true);
  }

  @override
  Future<void> doAfterBeanReady() async {}

  /// Get read progress for a gallery with cache
  Future<int> getReadProgress(int gid) async {
    // Return from cache if available
    if (_progressCache.containsKey(gid.toString())) {
      return _progressCache[gid.toString()]!;
    }

    // Read from storage
    final data = await localConfigService.read(
      configKey: ConfigEnum.readIndexRecord,
      subConfigKey: gid.toString(),
    );

    final progress = int.tryParse(data ?? '') ?? 0;
    _progressCache[gid.toString()] = progress;
    return progress;
  }

  Future<MangaLibraryPdfReadProgress?> getPdfReadProgress(String stableKey) async {
    if (_pdfProgressCache.containsKey(stableKey)) {
      return _pdfProgressCache[stableKey];
    }

    final data = await localConfigService.read(
      configKey: ConfigEnum.mangaLibraryPdfReadProgress,
      subConfigKey: stableKey,
    );
    if (data == null || data.trim().isEmpty) {
      return null;
    }

    try {
      MangaLibraryPdfReadProgress progress = MangaLibraryPdfReadProgress.fromJson(jsonDecode(data));
      _pdfProgressCache[stableKey] = progress;
      return progress;
    } catch (_) {
      return null;
    }
  }

  Future<void> updatePdfReadProgress(String stableKey, MangaLibraryPdfReadProgress progress) async {
    _pdfProgressCache[stableKey] = progress;
    await localConfigService.write(
      configKey: ConfigEnum.mangaLibraryPdfReadProgress,
      subConfigKey: stableKey,
      value: jsonEncode(progress.toJson()),
    );
    updateSafely(['$readProgressUpdateId::$stableKey']);
  }

  /// Update read progress and notify listeners
  Future<void> updateReadProgress(String recordKey, int index) async {
    _progressCache[recordKey] = index;
    await localConfigService.write(
      configKey: ConfigEnum.readIndexRecord,
      subConfigKey: recordKey,
      value: index.toString(),
    );
    updateSafely(['$readProgressUpdateId::$recordKey']);
  }
}

class MangaLibraryPdfReadProgress {
  final int currentPage;
  final int pageCount;
  final String updatedAt;

  const MangaLibraryPdfReadProgress({required this.currentPage, required this.pageCount, required this.updatedAt});

  factory MangaLibraryPdfReadProgress.fromJson(Map<String, dynamic> json) {
    return MangaLibraryPdfReadProgress(
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 1,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currentPage': currentPage,
      'pageCount': pageCount,
      'updatedAt': updatedAt,
    };
  }
}
