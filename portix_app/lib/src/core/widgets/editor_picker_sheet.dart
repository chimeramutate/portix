import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/entities/sftp/local_editor.dart';
import '../theme/app_theme.dart';
import 'app_panel.dart';

/// A bottom sheet that lists available editors/apps for opening a file.
/// Shared across SSH remote folder and SFTP features.
class EditorPickerSheet extends StatelessWidget {
  const EditorPickerSheet({
    required this.editors,
    super.key,
    this.title = 'Open with',
  });

  final List<LocalEditor> editors;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.apps_rounded, color: AppColors.cyan, size: 18),
                const SizedBox(width: 10),
                Text(title, style: portixTitle(15)),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: editors.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final editor = editors[index];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    tileColor: AppColors.surfaceCard.withValues(alpha: .5),
                    leading: _buildEditorIcon(editor),
                    title: Text(editor.name, style: portixTitle(12)),
                    onTap: () => Navigator.of(context).pop(editor),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorIcon(LocalEditor editor) {
    final fallbackIcon = Icon(
      editor.icon ?? Icons.open_in_new_rounded,
      color: AppColors.cyan,
      size: 18,
    );

    if (editor.svgAsset == null || editor.svgAsset!.trim().isEmpty) {
      return fallbackIcon;
    }

    return SvgPicture.asset(
      editor.svgAsset!,
      width: 18,
      height: 18,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => fallbackIcon,
      errorBuilder: (_, __, ___) => fallbackIcon,
    );
  }
}
