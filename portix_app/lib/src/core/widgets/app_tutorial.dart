import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:tutorial/tutorial.dart';

/// One highlighted widget + its explanation.
typedef TutorialStep = ({GlobalKey key, String title, String body});

/// Shows the coach-mark tutorial [id] once per install (seen ids are kept in
/// `tutorials_seen.txt` in the app support dir). Steps whose widget is not on
/// screen are skipped.
Future<void> showTutorialOnce(
  BuildContext context,
  String id,
  List<TutorialStep> steps,
) async {
  final File file;
  try {
    file = File(
      '${(await getApplicationSupportDirectory()).path}/tutorials_seen.txt',
    );
    if (await file.exists() && (await file.readAsLines()).contains(id)) return;
  } catch (_) {
    return; // No storage (tests, sandbox issue): skip rather than nag forever.
  }
  if (!context.mounted) return;

  final screen = MediaQuery.sizeOf(context);
  final items = <TutorialItem>[];
  for (final (i, step) in steps.indexed) {
    final box = step.key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final below = rect.center.dy < screen.height / 2;
    final last = i == steps.length - 1;
    items.add(
      TutorialItem(
        globalKey: step.key,
        shapeFocus: ShapeFocus.square,
        touchScreen: true,
        left: screen.width * .1,
        top: below ? rect.bottom + 16 : null,
        bottom: below ? null : screen.height - rect.top + 16,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title,
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.body,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 14),
        ],
        widgetNext: Text(
          last ? 'Selesai' : 'Klik untuk lanjut (${i + 1}/${steps.length})',
          style: TextStyle(
            color: AppColors.green,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
  if (items.isEmpty || !context.mounted) return;

  try {
    await file.writeAsString('$id\n', mode: FileMode.append);
  } catch (_) {
    return;
  }
  if (context.mounted) Tutorial.showTutorial(context, items);
}
