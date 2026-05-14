import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/extension/widget_extension.dart';
import 'package:jhentai/src/pages/download/grid/local/local_gallery_grid_page.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_page.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import 'package:jhentai/src/service/storage_service.dart';
import 'package:simple_animations/animation_controller_extension/animation_controller_extension.dart';
import 'package:simple_animations/animation_mixin/animation_mixin.dart';
import '../../config/ui_config.dart';
import 'grid/archive/archive_grid_download_page.dart';
import 'grid/gallery/gallery_grid_download_page.dart';
import 'list/archive/archive_list_download_page.dart';
import 'list/gallery/gallery_list_download_page.dart';
import 'list/local/local_gallery_list_page.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({Key? key}) : super(key: key);

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

final ValueNotifier<DownloadPageGalleryType?> downloadPageGalleryTypeNotifier = ValueNotifier<DownloadPageGalleryType?>(null);

class _DownloadPageState extends State<DownloadPage> {
  DownloadPageGalleryType galleryType = DownloadPageGalleryType.download;
  DownloadPageBodyType bodyType = GetPlatform.isMobile ? DownloadPageBodyType.list : DownloadPageBodyType.grid;
  Completer<void> bodyTypeCompleter = Completer<void>();

  @override
  void initState() {
    super.initState();

    downloadPageGalleryTypeNotifier.addListener(_handleRequestedGalleryType);

    localConfigService.read(configKey: ConfigEnum.downloadPageBodyType).then((bodyTypeString) {
      if (bodyTypeString != null) {
        int index = int.tryParse(bodyTypeString) ?? bodyType.index;
        bodyType = index >= 0 && index < DownloadPageBodyType.values.length ? DownloadPageBodyType.values[index] : bodyType;
      }
    }).whenComplete(() {
      bodyTypeCompleter.complete();
    });
  }

  @override
  void dispose() {
    downloadPageGalleryTypeNotifier.removeListener(_handleRequestedGalleryType);
    super.dispose();
  }

  void _handleRequestedGalleryType() {
    DownloadPageGalleryType? requestedGalleryType = downloadPageGalleryTypeNotifier.value;
    if (requestedGalleryType == null) {
      return;
    }

    setState(() {
      galleryType = _normalizeVisibleGalleryType(requestedGalleryType);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: NotificationListener<DownloadPageBodyTypeChangeNotification>(
        onNotification: (DownloadPageBodyTypeChangeNotification notification) {
          setState(() {
            galleryType = _normalizeVisibleGalleryType(notification.galleryType ?? galleryType);
            bodyType = notification.bodyType ?? bodyType;
          });
          if (notification.galleryType != null) {
            downloadPageGalleryTypeNotifier.value = galleryType;
          }
          localConfigService.write(configKey: ConfigEnum.downloadPageBodyType, value: (notification.bodyType ?? bodyType).index.toString());
          return true;
        },
        child: FutureBuilder(
          future: bodyTypeCompleter.future,
          builder: (_, __) => !bodyTypeCompleter.isCompleted
              ? const Center()
              : galleryType == DownloadPageGalleryType.download
                  ? bodyType == DownloadPageBodyType.list
                      ? GalleryListDownloadPage(key: const PageStorageKey('GalleryListDownloadBody'))
                      : GalleryGridDownloadPage(key: const PageStorageKey('GalleryGridDownloadBody'))
                  : galleryType == DownloadPageGalleryType.archive
                      ? bodyType == DownloadPageBodyType.list
                          ? ArchiveListDownloadPage(key: const PageStorageKey('ArchiveListDownloadBody'))
                          : ArchiveGridDownloadPage(key: const PageStorageKey('ArchiveGridDownloadBody'))
                      : galleryType == DownloadPageGalleryType.local
                          ? bodyType == DownloadPageBodyType.list
                              ? LocalGalleryListPage(key: const PageStorageKey('LocalGalleryListBody'))
                              : LocalGalleryGridPage(key: const PageStorageKey('LocalGalleryGridBody'))
                          : MangaLibraryPage(key: const PageStorageKey('MangaLibraryBody')),
        ),
      ),
    ).enableMouseDrag();
  }
}

enum DownloadPageGalleryType { download, archive, local, library }

enum DownloadPageBodyType { list, grid }

class DownloadPageBodyTypeChangeNotification extends Notification {
  DownloadPageGalleryType? galleryType;
  DownloadPageBodyType? bodyType;

  DownloadPageBodyTypeChangeNotification({this.galleryType, this.bodyType});
}

class DownloadPageSegmentControl extends StatelessWidget {
  final DownloadPageGalleryType galleryType;

  const DownloadPageSegmentControl({Key? key, required this.galleryType}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<DownloadPageGalleryType>(
      groupValue: _normalizeVisibleGalleryType(galleryType),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
      children: {
        DownloadPageGalleryType.download: SizedBox(
          width: UIConfig.downloadPageSegmentedControlWidth,
          child: Center(
            child: Text(
              'download'.tr,
              style: const TextStyle(fontSize: UIConfig.downloadPageSegmentedTextSize, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DownloadPageGalleryType.library: Text(
          'mangaLibrary'.tr,
          style: const TextStyle(fontSize: UIConfig.downloadPageSegmentedTextSize, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        DownloadPageGalleryType.library: Text(
          'mangaLibrary'.tr,
          style: const TextStyle(fontSize: UIConfig.downloadPageSegmentedTextSize, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      },
      onValueChanged: (value) => DownloadPageBodyTypeChangeNotification(galleryType: value!).dispatch(context),
    );
  }
}

DownloadPageGalleryType _normalizeVisibleGalleryType(DownloadPageGalleryType galleryType) {
  return galleryType == DownloadPageGalleryType.library ? DownloadPageGalleryType.library : DownloadPageGalleryType.download;
}

class GroupOpenIndicator extends StatefulWidget {
  final bool isOpen;

  const GroupOpenIndicator({Key? key, required this.isOpen}) : super(key: key);

  @override
  State<GroupOpenIndicator> createState() => _GroupOpenIndicatorState();
}

class _GroupOpenIndicatorState extends State<GroupOpenIndicator> with AnimationMixin {
  bool isOpen = false;
  late Animation<double> animation = Tween<double>(begin: 0.0, end: -0.25).animate(controller);

  @override
  void initState() {
    super.initState();

    isOpen = widget.isOpen;
    if (isOpen) {
      controller.forward(from: 1);
    }
  }

  @override
  void didUpdateWidget(covariant GroupOpenIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isOpen == widget.isOpen) {
      return;
    }

    isOpen = widget.isOpen;
    if (isOpen) {
      controller.play(duration: const Duration(milliseconds: 150));
    } else {
      controller.playReverse(duration: const Duration(milliseconds: 150));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: animation,
      child: const Icon(Icons.keyboard_arrow_left),
    );
  }
}
