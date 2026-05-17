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
  final List<MangaSimilarityGroup> _sessionGroups = [];
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshSessionGroups());
  }

  Future<void> _refreshSessionGroups() async {
    if (_isRefreshing) {
      return;
    }
    setState(() => _isRefreshing = true);
    try {
      await mangaLibraryService.refreshSimilarityGroups(force: true);
      if (mounted) {
        setState(() {
          _sessionGroups
            ..clear()
            ..addAll(mangaLibraryService.similarityGroups);
        });
      }
    } catch (e) {
      toast('${'operationFailed'.tr}: $e', isShort: false);
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _removeGroup(MangaSimilarityGroup group) {
    setState(() => _sessionGroups.removeWhere((candidate) => candidate.pairKey == group.pairKey));
  }

  void _removeGroupsForItem(MangaLibraryItem item) {
    setState(() => _sessionGroups.removeWhere((group) => group.first.stableKey == item.stableKey || group.second.stableKey == item.stableKey));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('similarManga'.tr),
        actions: [
          IconButton(
            tooltip: 'refreshSimilarityResults'.tr,
            icon: _isRefreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshSessionGroups,
          ),
        ],
      ),
      body: _isRefreshing
          ? const Center(child: CircularProgressIndicator())
          : _sessionGroups.isEmpty
              ? _SimilarityEmptyState(onRefresh: _refreshSessionGroups)
              : ListView.separated(
                  key: const PageStorageKey<String>('mangaSimilarityList'),
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) => _SimilarityGroupCard(
                    group: _sessionGroups[index],
                    onIgnore: () => _ignoreGroup(_sessionGroups[index]),
                    onDeletedItem: _removeGroupsForItem,
                  ),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: _sessionGroups.length,
                ),
    );
  }

  Future<void> _ignoreGroup(MangaSimilarityGroup group) async {
    try {
      await mangaLibraryService.ignoreSimilarityGroup(group);
      _removeGroup(group);
    } catch (e) {
      toast('${'operationFailed'.tr}: $e', isShort: false);
    }
  }
}

class _SimilarityEmptyState extends StatelessWidget {
  final VoidCallback onRefresh;

  const _SimilarityEmptyState({required this.onRefresh});

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
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh), label: Text('refreshSimilarityResults'.tr)),
                OutlinedButton(
                  onPressed: () => backRoute(currentRoute: Routes.mangaSimilarity),
                  child: Text('backToMangaLibrary'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarityGroupCard extends StatelessWidget {
  final MangaSimilarityGroup group;
  final VoidCallback onIgnore;
  final ValueChanged<MangaLibraryItem> onDeletedItem;

  const _SimilarityGroupCard({required this.group, required this.onIgnore, required this.onDeletedItem});

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
            _SimilarityItem(item: group.first, onDeleted: onDeletedItem),
            const Divider(),
            _SimilarityItem(item: group.second, onDeleted: onDeletedItem),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.visibility_off),
                label: Text('ignoreThisSimilarity'.tr),
                onPressed: onIgnore,
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
  final ValueChanged<MangaLibraryItem> onDeleted;

  const _SimilarityItem({required this.item, required this.onDeleted});

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
      onDeleted(item);
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
