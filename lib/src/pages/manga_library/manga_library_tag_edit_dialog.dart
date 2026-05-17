import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/utils/manga_library_tag_util.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';

class MangaLibraryTagEditDialog extends StatefulWidget {
  final MangaLibraryItem item;

  const MangaLibraryTagEditDialog({Key? key, required this.item}) : super(key: key);

  @override
  State<MangaLibraryTagEditDialog> createState() => _MangaLibraryTagEditDialogState();
}

class _MangaLibraryTagEditDialogState extends State<MangaLibraryTagEditDialog> {
  final TextEditingController _controller = TextEditingController();
  late List<TagData> _tags;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tags = widget.item.tags.map((tag) => TagData(namespace: tag.namespace, key: tag.key, translatedNamespace: tag.translatedNamespace, tagName: tag.tagName, fullTagName: tag.fullTagName)).toList();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<TagData> suggestions = mangaLibraryService.buildManualTagSuggestions(_controller.text).where((tag) => !_containsTag(tag)).toList();
    return AlertDialog(
      title: Text('manualEditTags'.tr),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('manualTagInputHint'.tr),
              const SizedBox(height: 12),
              if (_tags.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('manualTagEmptyHint'.tr, style: Theme.of(context).textTheme.bodyMedium),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _tags
                      .map(
                        (tag) => InputChip(
                          label: Text(mangaLibraryTagText(mangaLibraryService.resolveTagTranslation(tag))),
                          onPressed: () => _editTag(tag),
                          onDeleted: () => setState(() => _tags.removeWhere((e) => e.namespace == tag.namespace && e.key == tag.key)),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: 'manualTagInputExample'.tr,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addInputTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: _addInputTag, icon: const Icon(Icons.add), label: Text('addTag'.tr)),
                ],
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('tagSuggestions'.tr, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: suggestions
                      .map(
                        (tag) => ActionChip(
                          label: Text(mangaLibraryTagText(mangaLibraryService.resolveTagTranslation(tag))),
                          onPressed: () => _addTag(tag),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : backRoute, child: Text('cancel'.tr)),
        TextButton(onPressed: _isSaving ? null : _save, child: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text('manualTagSave'.tr)),
      ],
    );
  }

  void _addInputTag() {
    try {
      _addTag(mangaLibraryService.parseManualTagInput(_controller.text, existingTags: _tags));
      _controller.clear();
    } catch (e) {
      toast(e.toString(), isShort: false);
    }
  }

  void _addTag(TagData tag) {
    if (_containsTag(tag)) {
      toast('manualTagDuplicate'.tr);
      return;
    }
    setState(() => _tags.add(tag));
  }

  void _editTag(TagData tag) {
    setState(() {
      _tags.removeWhere((e) => e.namespace == tag.namespace && e.key == tag.key);
      _controller.text = '${tag.namespace}:${tag.key}';
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  bool _containsTag(TagData tag) {
    return _tags.any((existed) => existed.namespace == tag.namespace && existed.key == tag.key);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await mangaLibraryService.updateItemTagsManually(widget.item, _tags);
      toast('tagFillSaved'.tr);
      backRoute(result: true);
    } catch (e) {
      toast('${'tagFillSaveFailed'.tr}: $e', isShort: false);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
