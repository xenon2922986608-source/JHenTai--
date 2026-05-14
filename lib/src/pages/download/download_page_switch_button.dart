import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages/download/download_base_page.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/utils/route_util.dart';

class DownloadPageSwitchButton extends StatelessWidget {
  final DownloadPageGalleryType targetGalleryType;

  const DownloadPageSwitchButton({Key? key, required this.targetGalleryType}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: targetGalleryType == DownloadPageGalleryType.library ? 'switchToMangaLibrary'.tr : 'switchToDownload'.tr,
      icon: Icon(targetGalleryType == DownloadPageGalleryType.library ? Icons.collections_bookmark : Icons.download),
      onPressed: () {
        // TODO: Scroll to a matching item by gid/token when download and library lists expose stable item positioning APIs.
        downloadPageGalleryTypeNotifier.value = targetGalleryType;
        DownloadPageBodyTypeChangeNotification(galleryType: targetGalleryType).dispatch(context);
        toRoute(Routes.download);
      },
    );
  }
}
