import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/model/read_page_info.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/service/read_progress_service.dart';
import 'package:jhentai/src/service/super_resolution_service.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/widget/eh_alert_dialog.dart';

class MangaLibraryLogic extends GetxController {
  Future<void> openDetail(MangaLibraryItem item) async {
    toRoute(Routes.mangaLibraryDetail, arguments: item);
  }

  Future<void> openReader(MangaLibraryItem item) async {
    if (item.type == MangaLibraryItemType.gallery) {
      int readIndexRecord = await readProgressService.getReadProgress(item.gid);
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
          useSuperResolution: superResolutionService.get(item.gid, SuperResolutionType.gallery) != null,
        ),
      );
      return;
    }

    if (archiveDownloadService.archiveDownloadInfos[item.gid]?.archiveStatus != ArchiveStatus.completed) {
      return;
    }

    String? string = await localConfigService.read(configKey: ConfigEnum.readIndexRecord, subConfigKey: item.gid.toString());
    int readIndexRecord = string == null ? 0 : (int.tryParse(string) ?? 0);
    final images = await archiveDownloadService.getUnpackedImages(item.gid);

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
        useSuperResolution: superResolutionService.get(item.gid, SuperResolutionType.archive) != null,
      ),
    );
  }

  Future<void> confirmDelete(BuildContext context, MangaLibraryItem item, {bool popAfterDelete = false}) async {
    bool? result = await showDialog(
      context: context,
      builder: (_) => EHDialog(title: 'delete'.tr + '?'),
    );
    if (result == true) {
      await mangaLibraryService.deleteItem(item);
      if (popAfterDelete) {
        backRoute();
      }
    }
  }
}
