import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_tag_groups.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';
import 'package:jhentai/src/widget/eh_image.dart';

class MangaSimilarityPage extends StatefulWidget {
  const MangaSimilarityPage({Key? key}) : super(key: key);

  @override
  State<MangaSimilarityPage> createState() => _MangaSimilarityPageState();
}

class _MangaSimilarityPageState extends State<MangaSimilarityPage> {
  @override
  void initState() {
    super.initState();
    mangaLibraryService.refreshSimilarityGroups();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('similarManga'.tr)),
      body: GetBuilder<MangaLibraryService>(
        id: MangaLibraryService.similarityChangedId,
        builder: (_) {
          List<MangaSimilarityGroup> groups = mangaLibraryService.similarityGroups;
          if (mangaLibraryService.isRefreshingSimilarityGroups) {
            return const Center(child: CircularProgressIndicator());
          }
          if (groups.isEmpty) {
            return const _SimilarityEmptyState();
          }

          return ListView.separated(
            key: const PageStorageKey<String>('mangaSimilarityList'),
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) => _SimilarityGroupCard(group: groups[index]),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: groups.length,
          );
        },
      ),
    );
  }
}

class _SimilarityEmptyState extends StatelessWidget {
  const _SimilarityEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text('mangaSimilarityAllDone'.tr, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => backRoute(currentRoute: Routes.mangaSimilarity),
              child: Text('backToMangaLibrary'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarityGroupCard extends StatelessWidget {
  final MangaSimilarityGroup group;

  const _SimilarityGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'similarityScore'.tr}: ${group.score.toStringAsFixed(0)}'),
            Text('${'similarityReasons'.tr}: ${group.reasons.join(' / ')}'),
            const SizedBox(height: 8),
            _SimilarityItem(item: group.first),
            const Divider(),
            _SimilarityItem(item: group.second),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.visibility_off),
                label: Text('ignoreThisSimilarity'.tr),
                onPressed: _ignoreGroup,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ignoreGroup() async {
    try {
      await mangaLibraryService.ignoreSimilarityGroup(group);
    } catch (e) {
      toast('${'operationFailed'.tr}: $e', isShort: false);
    }
  }
}

class _SimilarityItem extends StatelessWidget {
  final MangaLibraryItem item;

  const _SimilarityItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SimilarityCover(item: item),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('${'pageCount'.tr}: ${item.pageCount}'),
              Text(_mangaLibraryTypeTitle(item.type)),
              MangaLibraryTagGroups(tags: item.tags, onTapTag: mangaLibraryService.toggleSelectedTag, maxGroups: 3, maxTagsPerGroup: 3, dense: true),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: () => mangaLibraryService.openReader(item), child: Text('read'.tr)),
                  TextButton(onPressed: () => _confirmDelete(context, item), child: Text('delete'.tr)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, MangaLibraryItem item) async {
    bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('delete'.tr + '?'),
        content: Text(_deleteConfirmContent(item)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text('cancel'.tr)),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text('OK'.tr)),
        ],
      ),
    );
    if (result != true) {
      return;
    }

    try {
      await mangaLibraryService.deleteItem(item);
      await mangaLibraryService.refreshSimilarityGroups(force: true);
    } catch (e) {
      toast('${'operationFailed'.tr}: $e', isShort: false);
    }
  }

  String _deleteConfirmContent(MangaLibraryItem item) {
    if (item.type == MangaLibraryItemType.importedFolder) {
      return 'deleteImportedFolderOriginalHint'.tr;
    }
    if (item.type == MangaLibraryItemType.pdf) {
      return 'deletePdfOriginalHint'.tr;
    }
    return 'deleteDownloadedMangaHint'.tr;
  }
}

class _SimilarityCover extends StatelessWidget {
  final MangaLibraryItem item;

  const _SimilarityCover({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.type == MangaLibraryItemType.pdf || (item.cover.path == null && item.cover.url.isEmpty)) {
      return Container(
        width: 72,
        height: 102,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: Icon(Icons.picture_as_pdf, color: Theme.of(context).colorScheme.primary),
      );
    }

    return EHImage(galleryImage: item.cover, containerWidth: 72, containerHeight: 102, fit: BoxFit.cover);
  }
}

String _mangaLibraryTypeTitle(MangaLibraryItemType type) {
  switch (type) {
    case MangaLibraryItemType.gallery:
      return 'gallery'.tr;
    case MangaLibraryItemType.archive:
      return 'archive'.tr;
    case MangaLibraryItemType.importedFolder:
      return 'importedFolder'.tr;
    case MangaLibraryItemType.pdf:
      return 'PDF'.tr;
  }
}
