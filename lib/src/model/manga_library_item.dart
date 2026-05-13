import 'package:jhentai/src/database/database.dart';

import 'gallery_image.dart';

enum MangaLibraryItemType {
  gallery('gallery'),
  archive('archive');

  final String code;

  const MangaLibraryItemType(this.code);

  static MangaLibraryItemType fromCode(String code) {
    return MangaLibraryItemType.values.firstWhere((type) => type.code == code);
  }
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
  final double? userRating;
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
    required this.userRating,
    this.isOriginal = false,
  });

  String get userDataType => type.code;

  String get id => '${type.code}:$gid';

  MangaLibraryItem copyWith({double? userRating}) {
    return MangaLibraryItem(
      type: type,
      gid: gid,
      token: token,
      title: title,
      category: category,
      pageCount: pageCount,
      galleryUrl: galleryUrl,
      uploader: uploader,
      tags: tags,
      downloadTime: downloadTime,
      localPath: localPath,
      cover: cover,
      userRating: userRating ?? this.userRating,
      isOriginal: isOriginal,
    );
  }
}
