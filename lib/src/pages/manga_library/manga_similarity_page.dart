import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_tag_groups.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/widget/eh_alert_dialog.dart';
import 'package:jhentai/src/widget/eh_image.dart';

class MangaSimilarityPage extends StatelessWidget {
  const MangaSimilarityPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('similarManga'.tr)),
      body: GetBuilder<MangaLibraryService>(
        id: MangaLibraryService.similarityChangedId,
        builder: (_) {
          List<MangaSimilarityGroup> groups = mangaLibraryService.similarityGroups;
          if (groups.isEmpty) {
            return Center(child: Text('noData'.tr));
          }

          return ListView.separated(
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
                onPressed: () => mangaLibraryService.ignoreSimilarityGroup(group),
              ),
            ),
          ],
        ),
      ),
    );
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
        EHImage(galleryImage: item.cover, containerWidth: 72, containerHeight: 102, fit: BoxFit.cover),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('${'pageCount'.tr}: ${item.pageCount}'),
              Text(item.type == MangaLibraryItemType.gallery ? 'gallery'.tr : 'archive'.tr),
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
    bool? result = await showDialog(context: context, builder: (_) => EHDialog(title: 'delete'.tr + '?'));
    if (result == true) {
      await mangaLibraryService.deleteItem(item);
    }
  }
}
