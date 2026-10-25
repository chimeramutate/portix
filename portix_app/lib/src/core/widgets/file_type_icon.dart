import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:portix/src/domain/entities/sftp/file_type_registry.dart';

/// The VS Code style icon for a file or folder [name], in its own colors.
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({
    required this.name,
    required this.folder,
    this.size = 18,
    super.key,
  });

  final String name;
  final bool folder;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      FileTypeRegistry.iconAssetFor(name, folder: folder),
      width: size,
      height: size,
    );
  }
}
