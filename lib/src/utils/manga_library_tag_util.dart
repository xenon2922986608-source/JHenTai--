import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/enum/eh_namespace.dart';


const Map<String, String> mangaLibraryChineseNamespaceAliases = {
  '语言': 'language',
  '語言': 'language',
  '女性': 'female',
  '男性': 'male',
  '角色': 'character',
  '原作': 'parody',
  '作者': 'artist',
  '团体': 'group',
  '團體': 'group',
  '社团': 'group',
  '社團': 'group',
  '其他': 'other',
  '混杂': 'misc',
  '混雜': 'misc',
  '杂项': 'misc',
  '雜項': 'misc',
};

const List<({String input, String output})> mangaLibraryTagFillSearchQuerySamples = [
  (
    input: '979293 [五識細工 (愛子八千代)] セクシャルディーヴィエントモード (グランブルーファンタジー) [中国 ]',
    output: '[五識細工 (愛子八千代)] セクシャルディーヴィエントモード (グランブルーファンタジー)',
  ),
  (
    input: '3745937-(C107) [フラットプラーク(かぐーら)] 交接条件下、影と生存 (アークナイツ) [中国翻訳]',
    output: '(C107) [フラットプラーク(かぐーら)] 交接条件下、影と生存 (アークナイツ)',
  ),
  (input: '3745937 - [作者] 标题 [Chinese]', output: '[作者] 标题'),
  (input: '3745937_[作者] 标题 [Digital]', output: '[作者] 标题'),
  (input: '3745937【作者】标题 [AI Generated]', output: '作者 标题'),
];

String buildEhSearchQueryFromLibraryTitle(String title) {
  return title
      .replaceFirst(RegExp(r'^\s*\d+\s*(?:[-_]\s*)?(?=[\s\[\(（【])'), '')
      .replaceAll(
        RegExp(
          r'[\[【]\s*(?:中国|中國|中国語|中國語|中国翻訳|中國翻譯|中文|無修正|无修正|chinese|digital|uncensored|ai generated|english|japanese|korean|translated|translation)\s*[\]】]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'[\(（]\s*(?:中国|中國|中国語|中國語|中国翻訳|中國翻譯|中文|無修正|无修正|chinese|digital|uncensored|ai generated|english|japanese|korean|translated|translation)\s*[\)）]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'漢化|汉化|中文|無修正|无修正|中国語|中國語|中国翻訳|中國翻譯|翻訳|翻译|DL版|電子版', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\[[^\]]*(?:汉化组|漢化組|翻译组|翻訳組|组|組)[^\]]*\]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\([^\)]*(?:汉化组|漢化組|翻译组|翻訳組|组|組)[^\)]*\)', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'[【】「」『』]'), ' ')
      .replaceAll(RegExp(r'\[\s*\]|\(\s*\)|（\s*）'), ' ')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String normalizeMangaLibraryTagNamespace(String namespace) {
  String value = namespace.trim();
  if (value.isEmpty) {
    return value;
  }
  String? mapped = mangaLibraryChineseNamespaceAliases[value];
  if (mapped != null) {
    return mapped;
  }
  return EHNamespace.findNameSpaceFromDescOrAbbr(value)?.desc ?? value.toLowerCase();
}

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
  const namespaceOrder = ['language', 'parody', 'character', 'female', 'male', 'mixed', 'artist', 'group', 'cosplayer', 'misc', 'other'];
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
