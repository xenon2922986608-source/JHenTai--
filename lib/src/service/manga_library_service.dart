import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/dao/manga_library_user_data_dao.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/gallery_download_service.dart';
import 'package:jhentai/src/service/jh_service.dart';
import 'package:jhentai/src/utils/convert_util.dart';

MangaLibraryService mangaLibraryService = MangaLibraryService();

class MangaLibraryService extends GetxController with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String libraryChangedId = 'mangaLibraryChangedId';

  final Map<String, MangaLibraryUserDataData> _userData = {};
  final List<TagData> selectedTags = [];

  @override
  List<JHLifeCircleBean> get initDependencies => super.initDependencies..addAll([galleryDownloadService, archiveDownloadService]);

  @override
  Future<void> doInitBean() async {
    Get.put(this, permanent: true);
    await _loadUserData();
  }

  @override
  Future<void> doAfterBeanReady() async {}

  Future<void> _loadUserData() async {
    _userData.clear();
    for (MangaLibraryUserDataData data in await MangaLibraryUserDataDao.selectAll()) {
      _userData[_key(data.gid, data.itemType)] = data;
    }
  }

  List<MangaLibraryItem> get items {
    List<MangaLibraryItem> result = [];

    result.addAll(
      galleryDownloadService.gallerys.where((gallery) => DownloadStatus.values[gallery.downloadStatusIndex] == DownloadStatus.downloaded).map((gallery) {
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
          userRating: _userRating(gallery.gid, MangaLibraryItemType.gallery),
          isOriginal: gallery.downloadOriginalImage,
        );
      }),
    );

    result.addAll(
      archiveDownloadService.archives.where((archive) => ArchiveStatus.fromCode(archive.archiveStatusCode) == ArchiveStatus.completed).map((archive) {
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
          userRating: _userRating(archive.gid, MangaLibraryItemType.archive),
          isOriginal: archive.isOriginal,
        );
      }),
    );

    result.sort((a, b) => b.downloadTime.compareTo(a.downloadTime));
    return result;
  }

  List<MangaLibraryItem> get filteredItems {
    if (selectedTags.isEmpty) {
      return items;
    }

    return items.where((item) {
      return selectedTags.every((selectedTag) {
        return item.tags.any((tag) => tag.namespace == selectedTag.namespace && tag.key == selectedTag.key);
      });
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

  bool isTagSelected(TagData tagData) {
    return selectedTags.any((tag) => tag.namespace == tagData.namespace && tag.key == tagData.key);
  }

  Future<void> updateUserRating(MangaLibraryItem item, double? userRating) async {
    if (userRating == null) {
      await MangaLibraryUserDataDao.deleteByKey(item.gid, item.userDataType);
      _userData.remove(_key(item.gid, item.userDataType));
    } else {
      await MangaLibraryUserDataDao.updateUserRating(item.gid, item.userDataType, userRating);
      _userData[_key(item.gid, item.userDataType)] = MangaLibraryUserDataData(
        gid: item.gid,
        itemType: item.userDataType,
        userRating: userRating,
        updatedAt: DateTime.now().toString(),
      );
    }
    update([libraryChangedId, _itemId(item)]);
  }

  Future<void> deleteItem(MangaLibraryItem item) async {
    if (item.type == MangaLibraryItemType.gallery) {
      await galleryDownloadService.deleteGalleryByGid(item.gid);
    } else {
      await archiveDownloadService.deleteArchive(item.gid);
    }

    await MangaLibraryUserDataDao.deleteByKey(item.gid, item.userDataType);
    _userData.remove(_key(item.gid, item.userDataType));
    update([libraryChangedId]);
  }

  String itemUpdateId(MangaLibraryItem item) => _itemId(item);

  double? _userRating(int gid, MangaLibraryItemType type) {
    return _userData[_key(gid, type.code)]?.userRating;
  }

  String _key(int gid, String itemType) => '$itemType:$gid';

  String _itemId(MangaLibraryItem item) => 'mangaLibraryItem::${item.id}';
}
