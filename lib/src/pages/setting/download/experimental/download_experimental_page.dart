import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/extension/string_extension.dart';
import 'package:jhentai/src/extension/widget_extension.dart';
import 'package:jhentai/src/service/manga_library_import_service.dart';
import 'package:jhentai/src/setting/download_setting.dart';
import 'package:jhentai/src/utils/permission_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';
import 'package:jhentai/src/widget/eh_wheel_speed_controller.dart';

class DownloadExperimentalPage extends StatefulWidget {
  const DownloadExperimentalPage({Key? key}) : super(key: key);

  @override
  State<DownloadExperimentalPage> createState() => _DownloadExperimentalPageState();
}

class _DownloadExperimentalPageState extends State<DownloadExperimentalPage> {
  final ScrollController _scrollController = ScrollController();
  bool _scanning = false;
  bool _exportingMetadata = false;
  DownloadDirectoryScanResult? _lastResult;
  MangaLibraryMetadataExportResult? _lastExportResult;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text('downloadExperimental'.tr)),
      body: EHWheelSpeedController(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 16, bottom: 48),
          children: [
            _buildDownloadPath(),
            _buildChangePathHint(),
            _buildScanButton(),
            _buildExportMetadataButton(),
            if (_lastResult != null) _buildResult(_lastResult!),
            if (_lastExportResult != null) _buildExportResult(_lastExportResult!),
          ],
        ).withListTileTheme(context),
      ),
    );
  }

  Widget _buildDownloadPath() {
    return Obx(
      () => ListTile(
        leading: const Icon(Icons.folder_open),
        title: Text('downloadPath'.tr),
        subtitle: Text(downloadSetting.downloadPath.value.breakWord),
      ),
    );
  }

  Widget _buildChangePathHint() {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text('changeDownloadPathInDownloadSetting'.tr),
      subtitle: Text('downloadExperimentalHint'.tr),
    );
  }

  Widget _buildExportMetadataButton() {
    return ListTile(
      leading: _exportingMetadata ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_alt),
      title: Text('exportAllLibraryMetadata'.tr),
      subtitle: Text('exportAllLibraryMetadataHint'.tr),
      enabled: !_scanning && !_exportingMetadata,
      onTap: _scanning || _exportingMetadata ? null : _handleExportMetadata,
    );
  }

  Widget _buildScanButton() {
    return ListTile(
      leading: _scanning ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.manage_search),
      title: Text('rescanDownloadDirectory'.tr),
      subtitle: Text('rescanDownloadDirectoryHint'.tr),
      enabled: !_scanning,
      onTap: _scanning ? null : _handleScan,
    );
  }

  Widget _buildResult(DownloadDirectoryScanResult result) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('scanResult'.tr, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ResultRow(label: 'lastScanTime'.tr, value: result.scanTime),
            _ResultRow(label: 'restoredGalleryCount'.tr, value: result.restoredGalleryCount.toString()),
            _ResultRow(label: 'restoredArchiveCount'.tr, value: result.restoredArchiveCount.toString()),
            _ResultRow(label: 'importedFolderCount'.tr, value: result.importedFolderCount.toString()),
            _ResultRow(label: 'importedPdfCount'.tr, value: result.importedPdfCount.toString()),
            _ResultRow(label: 'updatedImportedCount'.tr, value: result.updatedImportedCount.toString()),
            _ResultRow(label: 'skippedCount'.tr, value: result.skippedCount.toString()),
            _ResultRow(label: 'errorCount'.tr, value: result.errorCount.toString()),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('error'.tr, style: Theme.of(context).textTheme.titleSmall),
              ...result.errors.take(5).map((error) => Text(error, maxLines: 3, overflow: TextOverflow.ellipsis)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExportResult(MangaLibraryMetadataExportResult result) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('libraryMetadataExportResult'.tr, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ResultRow(label: 'lastScanTime'.tr, value: result.exportTime),
            _ResultRow(label: 'successCount'.tr, value: result.successCount.toString()),
            _ResultRow(label: 'skippedCount'.tr, value: result.skippedCount.toString()),
            _ResultRow(label: 'conflictCount'.tr, value: result.conflictCount.toString()),
            _ResultRow(label: 'failureCount'.tr, value: result.failureCount.toString()),
            if (result.conflicts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('libraryMetadataConflict'.tr, style: Theme.of(context).textTheme.titleSmall),
              ...result.conflicts.take(5).map((error) => Text(error, maxLines: 3, overflow: TextOverflow.ellipsis)),
            ],
            if (result.failures.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('error'.tr, style: Theme.of(context).textTheme.titleSmall),
              ...result.failures.take(5).map((error) => Text(error, maxLines: 3, overflow: TextOverflow.ellipsis)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleScan() async {
    setState(() => _scanning = true);
    try {
      await requestStoragePermission();
      DownloadDirectoryScanResult result = await mangaLibraryImportService.rescanDownloadDirectory();
      if (mounted) {
        setState(() => _lastResult = result);
      }
      if (result.errorCount > 0 && result.importedFolderCount == 0 && result.importedPdfCount == 0 && result.restoredGalleryCount == 0 && result.restoredArchiveCount == 0) {
        toast('${'operationFailed'.tr}: ${result.errors.take(2).join('\n')}', isShort: false);
      }
    } catch (e) {
      toast('${'operationFailed'.tr}: $e', isShort: false);
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _handleExportMetadata() async {
    setState(() => _exportingMetadata = true);
    try {
      await requestStoragePermission();
      MangaLibraryMetadataExportResult result = await mangaLibraryImportService.exportAllSidecars();
      if (mounted) {
        setState(() => _lastExportResult = result);
      }
      if (result.failureCount > 0) {
        toast('${'libraryMetadataWriteFailed'.tr}: ${result.failures.take(2).join('\n')}', isShort: false);
      } else {
        toast('libraryMetadataWriteSuccess'.tr);
      }
    } catch (e) {
      toast('${'libraryMetadataWriteFailed'.tr}: $e', isShort: false);
    } finally {
      if (mounted) {
        setState(() => _exportingMetadata = false);
      }
    }
  }

}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(label)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
