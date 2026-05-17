import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/gallery_image.dart';

enum MangaLibraryItemType {
  gallery('gallery'),
  archive('archive'),
  importedFolder('importedFolder'),
  pdf('pdf');

  final String code;

  const MangaLibraryItemType(this.code);
}

enum MangaLibrarySortType {
  downloadTimeDesc,
  titleAsc,
  pageCountDesc,
}

enum MangaLibraryDisplayMode {
  cover,
  compact,
  detail,
}

class MangaLibraryItem {
  final MangaLibraryItemType type;
  final int? gid;
  final String? token;
  final String title;
  final String category;
  final int pageCount;
  final String? galleryUrl;
  final String? uploader;
  final List<TagData> tags;
  final String downloadTime;
  final String localPath;
  final GalleryImage cover;
  final bool isOriginal;
  final int? sourceGid;
  final String? sourceToken;
  final String? sourceGalleryUrl;
  final String? sourceTitle;
  final String? tagUpdatedAt;

  const MangaLibraryItem({
    required this.type,
    this.gid,
    this.token,
    required this.title,
    required this.category,
    required this.pageCount,
    this.galleryUrl,
    required this.uploader,
    required this.tags,
    required this.downloadTime,
    required this.localPath,
    required this.cover,
    this.isOriginal = false,
    this.sourceGid,
    this.sourceToken,
    this.sourceGalleryUrl,
    this.sourceTitle,
    this.tagUpdatedAt,
  });

  String get id => stableKey;

  String get stableKey => MangaLibraryItem.buildStableKey(type: type, gid: gid, token: token, localPath: localPath);

  bool get isImported => type == MangaLibraryItemType.importedFolder || type == MangaLibraryItemType.pdf;

  static String buildStableKey({required MangaLibraryItemType type, int? gid, String? token, String? localPath}) {
    if (type == MangaLibraryItemType.importedFolder || type == MangaLibraryItemType.pdf) {
      return '${type.code}:${localPath ?? ''}';
    }

    String normalizedToken = token?.trim() ?? '';
    return normalizedToken.isEmpty ? '${type.code}:$gid' : '${type.code}:$gid:$normalizedToken';
  }
}

class MangaLibraryFocusRequest {
  final MangaLibraryItemType type;
  final int gid;
  final String? token;
  final bool openDetail;

  const MangaLibraryFocusRequest({required this.type, required this.gid, this.token, this.openDetail = false});

  String get stableKey => MangaLibraryItem.buildStableKey(type: type, gid: gid, token: token);
}

class MangaSimilarityGroup {
  final MangaLibraryItem first;
  final MangaLibraryItem second;
  final double score;
  final List<String> reasons;

  const MangaSimilarityGroup({
    required this.first,
    required this.second,
    required this.score,
    required this.reasons,
  });

  String get pairKey {
    List<String> ids = [first.id, second.id]..sort();
    return ids.join('|');
  }
}
