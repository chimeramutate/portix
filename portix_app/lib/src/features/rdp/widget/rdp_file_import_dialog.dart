import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';

/// Utility class untuk pick dan parse .rdp file
///
/// Usage:
/// ```dart
/// final profile = await RdpFileImportDialog.pickAndParse();
/// if (profile != null) {
///   // Use profile
/// }
/// ```
class RdpFileImportDialog {
  RdpFileImportDialog._();

  /// Pick .rdp file dan parse langsung
  /// Return [RdpProfile] jika berhasil, null jika cancelled
  static Future<RdpProfile?> pickAndParse() async {
    try {
      // 1. Open file picker
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['rdp'],
        dialogTitle: 'Select .rdp file',
      );

      if (result == null || result.files.isEmpty) {
        return null; // User cancelled
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        throw Exception('Invalid file path');
      }

      // 2. Parse .rdp file
      final backendService = sl<RdpBackendService>();
      final parseResult = await backendService.parseRdpFile(filePath);

      // 3. Return profile or throw error
      return parseResult.fold(
        (failure) => throw Exception(failure.message),
        (profile) => profile,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Get file name dari path
  static String getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}
