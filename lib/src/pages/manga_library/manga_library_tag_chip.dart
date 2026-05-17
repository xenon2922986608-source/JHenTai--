import 'package:flutter/material.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/gallery_tag.dart';
import 'package:jhentai/src/widget/eh_tag.dart';

class MangaLibraryTagChip extends StatelessWidget {
  final TagData tag;
  final ValueChanged<TagData>? onTap;

  const MangaLibraryTagChip({Key? key, required this.tag, this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return EHTag(
      tag: GalleryTag(tagData: tag),
      onTap: onTap == null ? null : (_) => onTap!(tag),
    );
  }
}
