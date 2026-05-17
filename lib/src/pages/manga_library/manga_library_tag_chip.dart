import 'package:flutter/material.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/utils/manga_library_tag_util.dart';

class MangaLibraryTagChip extends StatelessWidget {
  final TagData tag;
  final ValueChanged<TagData>? onTap;
  final bool selected;

  const MangaLibraryTagChip({Key? key, required this.tag, this.onTap, this.selected = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    Color backgroundColor = selected ? colorScheme.primaryContainer : colorScheme.surfaceVariant;
    Color foregroundColor = selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant;
    BorderSide borderSide = selected ? BorderSide(color: colorScheme.primary, width: 1.4) : BorderSide(color: colorScheme.outlineVariant, width: 0.8);

    Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.fromBorderSide(borderSide),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            Icon(Icons.check, size: 12, color: foregroundColor),
            const SizedBox(width: 3),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              mangaLibraryTagText(tag),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1, color: foregroundColor, fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: () => onTap!(tag), child: child),
    );
  }
}
