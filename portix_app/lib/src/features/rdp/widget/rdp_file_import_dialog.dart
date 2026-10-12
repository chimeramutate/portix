import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';

/// Picks a .rdp file and parses it into an [RdpProfile].
class RdpFileImportDialog {
  RdpFileImportDialog._();

  /// Null when the user cancels the picker.
  static Future<RdpProfile?> pickAndParse() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['rdp'],
        dialogTitle: 'Select .rdp file',
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        throw Exception('Invalid file path');
      }

      final backendService = sl<RdpBackendService>();
      final parseResult = await backendService.parseRdpFile(filePath);

      return parseResult.fold(
        (failure) => throw Exception(failure.message),
        (profile) => profile,
      );
    } catch (e) {
      rethrow;
    }
  }

  static String getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}
