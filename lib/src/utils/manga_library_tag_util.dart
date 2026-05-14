import 'package:jhentai/src/database/database.dart';

String mangaLibraryTagText(TagData tag) {
  String namespace = tag.translatedNamespace?.isNotEmpty == true ? tag.translatedNamespace! : tag.namespace;
  String key = tag.tagName?.isNotEmpty == true ? tag.tagName! : tag.key;
  return '$namespace:$key';
}

String mangaLibraryTagSearchText(TagData tag) {
  return [
    '${tag.namespace}:${tag.key}',
    tag.namespace,
    tag.key,
    if (tag.translatedNamespace?.isNotEmpty == true) tag.translatedNamespace!,
    if (tag.tagName?.isNotEmpty == true) tag.tagName!,
    if (tag.translatedNamespace?.isNotEmpty == true && tag.tagName?.isNotEmpty == true) '${tag.translatedNamespace}:${tag.tagName}',
  ].join(' ');
}
