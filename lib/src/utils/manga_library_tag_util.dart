import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/enum/eh_namespace.dart';

String mangaLibraryTagText(TagData tag) {
  String namespace = tag.translatedNamespace?.isNotEmpty == true ? tag.translatedNamespace! : tag.namespace;
  String key = tag.tagName?.isNotEmpty == true ? tag.tagName! : tag.key;
  return '$namespace:$key';
}

String mangaLibraryTagSearchText(TagData tag) {
  String translatedNamespace = mangaLibraryNamespaceText(tag.namespace, sampleTag: tag);
  String translatedTagName = tag.tagName?.isNotEmpty == true ? tag.tagName! : tag.key;
  return [
    '${tag.namespace}:${tag.key}',
    tag.namespace,
    tag.key,
    translatedNamespace,
    translatedTagName,
    '$translatedNamespace:$translatedTagName',
  ].join(' ');
}


String mangaLibraryNamespaceText(String namespace, {TagData? sampleTag}) {
  if (sampleTag?.translatedNamespace?.isNotEmpty == true) {
    return sampleTag!.translatedNamespace!;
  }

  return EHNamespace.findNameSpaceFromDescOrAbbr(namespace)?.chineseDesc ?? namespace;
}

LinkedHashMap<String, List<TagData>> groupMangaLibraryTagsByNamespace(List<TagData> tags) {
  const namespaceOrder = ['language', 'parody', 'character', 'female', 'male', 'mixed', 'artist', 'group', 'cosplayer', 'other'];
  Map<String, List<TagData>> grouped = tags.groupListsBy((tag) => tag.namespace);
  LinkedHashMap<String, List<TagData>> result = LinkedHashMap();

  for (String namespace in namespaceOrder) {
    List<TagData>? namespaceTags = grouped.remove(namespace);
    if (namespaceTags != null && namespaceTags.isNotEmpty) {
      result[namespace] = namespaceTags;
    }
  }

  List<String> restNamespaces = grouped.keys.toList()..sort();
  for (String namespace in restNamespaces) {
    result[namespace] = grouped[namespace]!;
  }

  return result;
}
