import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/gallery_image.dart';

enum MangaLibraryItemType {
  gallery('gallery'),
  archive('archive');

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
  final int gid;
  final String token;
  final String title;
  final String category;
  final int pageCount;
  final String galleryUrl;
  final String? uploader;
  final List<TagData> tags;
  final String downloadTime;
  final String localPath;
  final GalleryImage cover;
  final bool isOriginal;

  const MangaLibraryItem({
    required this.type,
    required this.gid,
    required this.token,
    required this.title,
    required this.category,
    required this.pageCount,
    required this.galleryUrl,
    required this.uploader,
    required this.tags,
    required this.downloadTime,
    required this.localPath,
    required this.cover,
    this.isOriginal = false,
  });

  String get id => '${type.code}:$gid';
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
