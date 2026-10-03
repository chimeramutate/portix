import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:xterm/xterm.dart';

import 'terminal_themes.dart';

/// Shows every terminal theme as a sample of terminal output. A click
/// applies the theme right away ([onSelected]); the dialog stays open so
/// other themes can be tried, and closes on Esc or a click outside.
Future<void> showTerminalThemePicker(
  BuildContext context, {
  required String? current,
  required ValueChanged<String> onSelected,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (_) =>
        TerminalThemePicker(current: current, onSelected: onSelected),
  );
}

class TerminalThemePicker extends StatefulWidget {
  const TerminalThemePicker({
    required this.current,
    required this.onSelected,
    super.key,
  });

  final String? current;
  final ValueChanged<String> onSelected;

  @override
  State<TerminalThemePicker> createState() => _TerminalThemePickerState();
}

class _TerminalThemePickerState extends State<TerminalThemePicker> {
  late String? _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Terminal theme',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.muted,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: GridView.extent(
                  shrinkWrap: true,
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  children: [
                    for (final name in terminalThemeNames)
                      _ThemeCard(
                        key: ValueKey('terminal-theme-$name'),
                        name: name,
                        selected: name == _selected,
                        onTap: () {
                          setState(() => _selected = name);
                          widget.onSelected(name);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.name,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = terminalThemeByName(name);
    return Material(
      color: theme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.green : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: theme.green,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(child: TerminalThemeSample(theme: theme)),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final color in [
                    theme.red,
                    theme.green,
                    theme.yellow,
                    theme.blue,
                    theme.magenta,
                    theme.cyan,
                    theme.white,
                    theme.brightBlack,
                  ])
                    Expanded(child: Container(height: 6, color: color)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A few lines of shell output in [theme]'s colors.
class TerminalThemeSample extends StatelessWidget {
  const TerminalThemeSample({required this.theme, super.key});

  final TerminalTheme theme;

  @override
  Widget build(BuildContext context) {
    TextSpan span(String text, Color color) => TextSpan(
      text: text,
      style: TextStyle(color: color),
    );
    return Text.rich(
      TextSpan(
        style: TextStyle(
          color: theme.foreground,
          fontFamily: 'monospace',
          fontSize: 10.5,
          height: 1.35,
        ),
        children: [
          span('user@portix', theme.green),
          span(':', theme.foreground),
          span('~/app', theme.blue),
          span('\$ ls\n', theme.foreground),
          span('src/  ', theme.blue),
          span('run.sh  ', theme.green),
          span('notes.md\n', theme.foreground),
          span('✓ build ok ', theme.green),
          span('! 2 warn ', theme.yellow),
          span('✗ 1 err\n', theme.red),
          span('# comment ', theme.brightBlack),
          span('git:(', theme.magenta),
          span('main', theme.cyan),
          span(')\n', theme.magenta),
          span('\$ ', theme.foreground),
          TextSpan(
            text: ' ',
            style: TextStyle(backgroundColor: theme.cursor),
          ),
        ],
      ),
      overflow: TextOverflow.clip,
    );
  }
}
