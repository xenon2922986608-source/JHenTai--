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

enum MangaLibraryTagFilterMode {
  all,
  hasTags,
  missingTags,
}

enum MangaLibraryOrganizedFilterMode {
  all,
  organizedOnly,
  unorganizedOnly,
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
  final String? sourceCategory;
  final String? tagUpdatedAt;
  final String? sidecarPath;
  final bool hasSidecarMetadata;
  final bool organized;
  final String? organizedUpdatedAt;

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
    this.sourceCategory,
    this.tagUpdatedAt,
    this.sidecarPath,
    this.hasSidecarMetadata = false,
    this.organized = false,
    this.organizedUpdatedAt,
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


class MangaLibraryItemUserData {
  final String stableKey;
  final bool organized;
  final String organizedUpdatedAt;

  const MangaLibraryItemUserData({required this.stableKey, required this.organized, required this.organizedUpdatedAt});

  factory MangaLibraryItemUserData.fromJson(Map<String, dynamic> json) {
    return MangaLibraryItemUserData(
      stableKey: json['stableKey'] ?? '',
      organized: json['organized'] ?? json['greenLabel'] ?? false,
      organizedUpdatedAt: json['organizedUpdatedAt'] ?? json['greenLabelUpdatedAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stableKey': stableKey,
      'organized': organized,
      'organizedUpdatedAt': organizedUpdatedAt,
    };
  }
}

class MangaLibraryOrganizedState {
  final bool organized;
  final String? organizedUpdatedAt;

  const MangaLibraryOrganizedState({required this.organized, this.organizedUpdatedAt});
}
