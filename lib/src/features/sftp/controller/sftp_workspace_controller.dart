import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:portix/src/data/services/sftp/index.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';

class SftpWorkspaceController extends ChangeNotifier {
  SftpWorkspaceController({
    LocalFileBrowser? localFileBrowser,
    LocalEditorService? localEditorService,
  }) : _localFileBrowser = localFileBrowser ?? LocalFileBrowser(),
       _localEditorService = localEditorService ?? LocalEditorService() {
    _localPath = _localFileBrowser.defaultPath();
    unawaited(loadLocalDirectory(_localPath));
  }

  final LocalFileBrowser _localFileBrowser;
  final LocalEditorService _localEditorService;

  final List<SftpTransferJob> _transferJobs = [];
  late String _localPath;
  List<SftpFileEntry> _localRows = const [];
  String? _localError;
  bool _loadingLocal = false;

  List<SftpTransferJob> get transferJobs => List.unmodifiable(_transferJobs);
  String get localPath => _localPath;
  List<SftpFileEntry> get localRows => _localRows;
  List<SftpFileEntry> get remoteRows => _remoteRows;
  String? get localError => _localError;
  bool get loadingLocal => _loadingLocal;
  int get localItemCount => _localRows.where((row) => row.name != '..').length;

  Future<void> loadLocalDirectory(String path) async {
    _loadingLocal = true;
    _localError = null;
    notifyListeners();

    try {
      final result = await _localFileBrowser.readDirectory(path);
      _localPath = result.path;
      _localRows = result.entries;
    } catch (error) {
      _localError = '$error';
      _localRows = const [];
    } finally {
      _loadingLocal = false;
      notifyListeners();
    }
  }

  void queueTransfer(SftpFileTransfer transfer, bool targetRemote) {
    if (transfer.fromRemote == targetRemote) return;
    _transferJobs.insert(
      0,
      SftpTransferJob(
        name: transfer.file.name,
        direction: targetRemote ? 'Local -> Remote' : 'Remote -> Local',
        value: transfer.file.folder ? .18 : .46,
        queued: _transferJobs.isNotEmpty,
      ),
    );
    notifyListeners();
  }

  void clearTransfers() {
    _transferJobs.clear();
    notifyListeners();
  }

  Future<List<LocalEditor>> detectLocalEditors() {
    return _localEditorService.detectEditors();
  }

  Future<String> editablePathFor(SftpFileEntry file, bool isRemote) {
    if (!isRemote) return Future.value(file.path ?? file.name);
    return _localEditorService.prepareRemoteFileForLocalEdit(file);
  }

  Future<void> openEditor(LocalEditor editor, String path) {
    return _localEditorService.open(editor, path);
  }
}

const _remoteRows = [
  SftpFileEntry(
    name: 'current',
    type: 'symlink',
    size: '23 B',
    modified: '22 May 08:12',
  ),
  SftpFileEntry(
    name: 'release-2026.05.21',
    type: 'dir',
    size: '1.3 GB',
    modified: '22 May 06:41',
    folder: true,
  ),
  SftpFileEntry(
    name: 'release-2026.05.18',
    type: 'dir',
    size: '1.3 GB',
    modified: '18 May 02:09',
    folder: true,
  ),
  SftpFileEntry(
    name: 'shared',
    type: 'dir',
    size: '92 MB',
    modified: '22 May 08:07',
    folder: true,
  ),
  SftpFileEntry(
    name: 'uploads',
    type: 'dir',
    size: '418 MB',
    modified: '21 May 21:20',
    folder: true,
  ),
  SftpFileEntry(
    name: 'rollback.sh',
    type: 'file',
    size: '2 KB',
    modified: '20 May 23:41',
  ),
  SftpFileEntry(
    name: 'env.backup',
    type: 'file',
    size: '1 KB',
    modified: '20 May 18:22',
  ),
];
