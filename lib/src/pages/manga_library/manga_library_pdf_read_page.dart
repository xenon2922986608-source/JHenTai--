import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/model/manga_library_item.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/service/manga_library_service.dart';
import 'package:jhentai/src/service/read_progress_service.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';
import 'package:pdfx/pdfx.dart';

class MangaLibraryPdfReadPageArgs {
  final MangaLibraryItem item;

  const MangaLibraryPdfReadPageArgs({required this.item});
}

class MangaLibraryPdfReadPage extends StatefulWidget {
  const MangaLibraryPdfReadPage({Key? key}) : super(key: key);

  @override
  State<MangaLibraryPdfReadPage> createState() => _MangaLibraryPdfReadPageState();
}

class _MangaLibraryPdfReadPageState extends State<MangaLibraryPdfReadPage> {
  PdfControllerPinch? _controller;
  MangaLibraryItem? _item;
  bool _isOpening = true;
  String? _errorMessage;
  int _currentPage = 1;
  int _pageCount = 0;
  bool _restoredProgress = false;

  @override
  void initState() {
    super.initState();
    _openPdf();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openPdf() async {
    try {
      Object? arguments = Get.arguments;
      MangaLibraryPdfReadPageArgs? args = arguments is MangaLibraryPdfReadPageArgs ? arguments : null;
      MangaLibraryItem? item = args?.item ?? (arguments is MangaLibraryItem ? arguments : null);
      if (item == null || item.type != MangaLibraryItemType.pdf) {
        _setError('invalidMangaLibraryItem'.tr);
        return;
      }
      _item = item;
      _pageCount = max(0, item.pageCount);

      File file = File(item.localPath);
      bool exists = false;
      try {
        exists = await file.exists();
      } catch (e, stack) {
        log.error('Check PDF file failed: ${item.localPath}', e, stack);
        _setError('${'pdfReadPermissionDenied'.tr}\n${item.localPath}');
        return;
      }
      if (!exists) {
        _setError('${'pdfFileNotFound'.tr}\n${item.localPath}');
        return;
      }

      MangaLibraryPdfReadProgress? progress;
      try {
        progress = await readProgressService.getPdfReadProgress(item.stableKey);
      } catch (e, stack) {
        log.error('Restore manga library PDF read progress failed: ${item.stableKey}', e, stack);
        toast('restorePdfReadProgressFailed'.tr, isShort: false);
      }

      int initialPage = progress?.currentPage ?? 1;
      if (_pageCount > 0) {
        initialPage = initialPage.clamp(1, _pageCount).toInt();
      } else {
        initialPage = max(1, initialPage);
      }
      _currentPage = initialPage;
      _restoredProgress = progress != null;

      _controller = PdfControllerPinch(
        document: PdfDocument.openFile(item.localPath),
        initialPage: initialPage,
        viewportFraction: 1,
      );
      if (mounted) {
        setState(() {
          _isOpening = false;
          _errorMessage = null;
        });
      }
    } catch (e, stack) {
      log.error('Open manga library PDF failed', e, stack);
      _setError('${'pdfOpenFailed'.tr}\n$e');
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isOpening = false;
      _errorMessage = message;
    });
  }

  Future<void> _handleDocumentLoaded(PdfDocument document) async {
    int count = document.pagesCount;
    if (count <= 0) {
      _setError('pdfPageCountInvalid'.tr);
      return;
    }

    int fixedPage = _currentPage.clamp(1, count).toInt();
    if (mounted) {
      setState(() {
        _pageCount = count;
        _currentPage = fixedPage;
      });
    }

    if (fixedPage != _controller?.page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _controller?.jumpToPage(fixedPage);
        } catch (_) {}
      });
    }

    MangaLibraryItem? item = _item;
    if (item != null) {
      unawaited(_saveProgress(fixedPage, count));
      if (item.pageCount != count) {
        try {
          await mangaLibraryService.updatePdfPageCount(item, count);
        } catch (e, stack) {
          log.error('Update manga library PDF page count failed: ${item.localPath}', e, stack);
        }
      }
    }
  }

  void _handleDocumentError(Object error) {
    log.error('Load manga library PDF document failed: ${_item?.localPath}', error);
    _setError('${'pdfReadFailed'.tr}\n$error');
  }

  void _handlePageChanged(int page) {
    if (!mounted) {
      return;
    }
    setState(() => _currentPage = page);
    unawaited(_saveProgress(page, _pageCount));
  }

  Future<void> _saveProgress(int page, int pageCount) async {
    MangaLibraryItem? item = _item;
    if (item == null || page <= 0) {
      return;
    }

    int safePageCount = max(pageCount, page);
    int safePage = page.clamp(1, safePageCount).toInt();
    try {
      await readProgressService.updatePdfReadProgress(
        item.stableKey,
        MangaLibraryPdfReadProgress(
          currentPage: safePage,
          pageCount: safePageCount,
          updatedAt: DateTime.now().toString(),
        ),
      );
    } catch (e, stack) {
      log.error('Save manga library PDF read progress failed: ${item.stableKey}', e, stack);
      if (mounted) {
        toast('savePdfReadProgressFailed'.tr, isShort: false);
      }
    }
  }

  Future<void> _goPrev() async {
    if (_currentPage <= 1) {
      return;
    }
    try {
      await _controller?.previousPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } catch (e, stack) {
      log.error('Go to previous PDF page failed', e, stack);
    }
  }

  Future<void> _goNext() async {
    if (_pageCount > 0 && _currentPage >= _pageCount) {
      return;
    }
    try {
      await _controller?.nextPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } catch (e, stack) {
      log.error('Go to next PDF page failed', e, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_item?.title ?? 'pdfRead'.tr, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: backRoute),
      ),
      body: _buildBody(context),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isOpening) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('openingPdf'.tr, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _openPdf, icon: const Icon(Icons.refresh), label: Text('retry'.tr)),
            ],
          ),
        ),
      );
    }

    PdfControllerPinch? controller = _controller;
    if (controller == null) {
      return const SizedBox();
    }

    return Stack(
      children: [
        PdfViewPinch(
          controller: controller,
          scrollDirection: Axis.vertical,
          padding: 12,
          minScale: 1,
          maxScale: 8,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          onDocumentLoaded: _handleDocumentLoaded,
          onDocumentError: _handleDocumentError,
          onPageChanged: _handlePageChanged,
        ),
        if (_restoredProgress)
          Positioned(
            top: 12,
            right: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.62), borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('restorePdfReadProgress'.tr, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    if (_errorMessage != null || _isOpening) {
      return const SizedBox(height: 0);
    }

    return SafeArea(
      top: false,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              color: Colors.white,
              onPressed: _currentPage <= 1 ? null : _goPrev,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'prevPage'.tr,
            ),
            Expanded(
              child: Text(
                '${'currentPage'.tr}: $_currentPage / ${'totalPages'.tr}: ${_pageCount == 0 ? '-' : _pageCount}',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              color: Colors.white,
              onPressed: _pageCount > 0 && _currentPage >= _pageCount ? null : _goNext,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'nextPage'.tr,
            ),
          ],
        ),
      ),
    );
  }
}
