import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/gallery.dart';
import 'package:jhentai/src/model/gallery_detail.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/pages/manga_library/manga_library_tag_groups.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';
import 'package:jhentai/src/widget/eh_alert_dialog.dart';
import 'package:jhentai/src/widget/eh_gallery_category_tag.dart';
import 'package:jhentai/src/widget/eh_image.dart';
import 'package:jhentai/src/widget/eh_wheel_speed_controller.dart';

class MangaLibraryTagFillPage extends StatefulWidget {
  const MangaLibraryTagFillPage({Key? key}) : super(key: key);

  @override
  State<MangaLibraryTagFillPage> createState() => _MangaLibraryTagFillPageState();
}

class _MangaLibraryTagFillPageState extends State<MangaLibraryTagFillPage> {
  final TextEditingController _keywordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  MangaLibraryItem? _initialItem;
  String _autoKeyword = '';
  List<Gallery> _candidates = [];
  bool _isSearching = false;
  bool _isFetching = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final dynamic arguments = Get.arguments;
    if (arguments is MangaLibraryItem) {
      _initialItem = arguments;
      _autoKeyword = mangaLibraryService.buildTagFillSearchKeyword(arguments);
      _keywordController.text = _autoKeyword;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialItem == null) {
      return Scaffold(
        appBar: AppBar(title: Text('fillTags'.tr)),
        body: Center(child: Text('invalidMangaLibraryItem'.tr)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('fillTags'.tr)),
      body: GetBuilder<MangaLibraryService>(
        id: MangaLibraryService.libraryChangedId,
        builder: (_) {
          MangaLibraryItem? item = mangaLibraryService.findItem(_initialItem!.id);
          if (item == null) {
            return Center(child: Text('mangaLibraryItemNotFound'.tr));
          }

          return EHWheelSpeedController(
            controller: _scrollController,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _LocalMangaInfoCard(item: item, autoKeyword: _autoKeyword),
                const SizedBox(height: 16),
                Text('searchKeyword'.tr, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keywordController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'tagFillKeywordHint'.tr,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isSearching ? null : _search,
                      icon: _isSearching ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                      label: Text('search'.tr),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_errorMessage != null) _ErrorPanel(message: _errorMessage!, onRetry: _search),
                if (_hasSearched && !_isSearching && _errorMessage == null && _candidates.isEmpty) _EmptyPanel(message: 'noTagFillCandidates'.tr),
                if (_candidates.isNotEmpty) ...[
                  Text('tagFillCandidates'.tr, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._candidates.map((candidate) => _CandidateCard(
                        candidate: candidate,
                        isBusy: _isFetching,
                        onViewDetail: () => _viewCandidateDetail(candidate),
                        onUse: () => _confirmAndUseCandidate(item, candidate),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _search() async {
    String keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      toast('invalid'.tr);
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _errorMessage = null;
    });

    try {
      List<Gallery> candidates = await mangaLibraryService.searchTagFillCandidates(keyword);
      if (!mounted) {
        return;
      }
      setState(() {
        _candidates = candidates;
      });
      if (candidates.isEmpty) {
        toast('noTagFillCandidates'.tr, isShort: false);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _candidates = [];
        _errorMessage = '${'tagFillSearchFailed'.tr}: $e';
      });
      toast(_errorMessage!, isShort: false);
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _viewCandidateDetail(Gallery candidate) async {
    setState(() => _isFetching = true);
    try {
      GalleryDetail detail = await mangaLibraryService.fetchTagFillCandidateDetail(candidate);
      if (!mounted) {
        return;
      }
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(detail.japaneseTitle ?? detail.rawTitle),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      EHGalleryCategoryTag(category: detail.category),
                      Chip(label: Text('${'pageCount'.tr}: ${detail.pageCount}')),
                      Chip(label: Text('${'uploader'.tr}: ${detail.uploader ?? '-'}')),
                      Chip(label: Text('${'rating'.tr}: ${detail.rating.toStringAsFixed(2)}')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  MangaLibraryTagGroups(tags: detail.tags.values.flattened.map((tag) => tag.tagData).toList(), dense: true),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: backRoute, child: Text('OK'.tr))],
        ),
      );
    } catch (e) {
      toast('${'tagFillCandidateDetailFailed'.tr}: $e', isShort: false);
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  Future<void> _confirmAndUseCandidate(MangaLibraryItem item, Gallery candidate) async {
    bool? ok = await showDialog(
      context: context,
      builder: (_) => EHDialog(title: 'confirmFillTags'.tr, content: 'confirmFillTagsHint'.trArgs([candidate.title, item.title])),
    );
    if (ok != true) {
      toast('tagFillCancelled'.tr);
      return;
    }

    setState(() => _isFetching = true);
    try {
      await mangaLibraryService.fillMissingTagsFromGallery(item, candidate);
      toast('tagFillSaved'.tr);
      if (mounted) {
        backRoute(currentRoute: Routes.mangaLibraryTagFill);
      }
    } catch (e) {
      toast('${'tagFillSaveFailed'.tr}: $e', isShort: false);
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }
}

class _LocalMangaInfoCard extends StatelessWidget {
  final MangaLibraryItem item;

  final String autoKeyword;

  const _LocalMangaInfoCard({required this.item, required this.autoKeyword});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('localManga'.tr, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _InfoLine(label: 'originalTitle'.tr, value: item.title),
            _InfoLine(label: 'autoSearchKeyword'.tr, value: autoKeyword),
            _InfoLine(label: 'type'.tr, value: _mangaLibraryTypeTitle(item.type)),
            _InfoLine(label: 'localPath'.tr, value: item.localPath),
            _InfoLine(label: 'tags'.tr, value: item.tags.isEmpty ? 'noTags'.tr : item.tags.length.toString()),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final Gallery candidate;
  final bool isBusy;
  final VoidCallback onViewDetail;
  final VoidCallback onUse;

  const _CandidateCard({required this.candidate, required this.isBusy, required this.onViewDetail, required this.onUse});

  @override
  Widget build(BuildContext context) {
    List<TagData> tags = candidate.tags.values.flattened.map((tag) => tag.tagData).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EHImage(galleryImage: candidate.cover, containerWidth: 92, containerHeight: 132, fit: BoxFit.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      EHGalleryCategoryTag(category: candidate.category),
                      Chip(label: Text('${'pageCount'.tr}: ${candidate.pageCount ?? '-'}')),
                      Chip(label: Text('${'uploader'.tr}: ${candidate.uploader ?? '-'}')),
                      Chip(label: Text('${'rating'.tr}: ${candidate.rating.toStringAsFixed(2)}')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MangaLibraryTagGroups(tags: tags, dense: true, maxGroups: 3, maxTagsPerGroup: 4),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(onPressed: isBusy ? null : onViewDetail, icon: const Icon(Icons.info_outline), label: Text('viewCandidateDetail'.tr)),
                      FilledButton.icon(onPressed: isBusy ? null : onUse, icon: const Icon(Icons.new_label_outlined), label: Text('useThisCandidate'.tr)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text('reload'.tr)),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String message;

  const _EmptyPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
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
