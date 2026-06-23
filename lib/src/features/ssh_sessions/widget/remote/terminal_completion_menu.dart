import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:xterm/xterm.dart';

import '../../controller/index.dart';

class TerminalCompletionMenu extends StatefulWidget {
  const TerminalCompletionMenu({
    super.key,
    required this.terminalViewKey,
    required this.suggestions,
    required this.suggestionSuffix,
    this.onSelectSuggestion,
  });

  final GlobalKey<TerminalViewState> terminalViewKey;
  final List<TerminalSuggestion> suggestions;
  final TerminalSuggestion? suggestionSuffix;
  final void Function(TerminalSuggestion)? onSelectSuggestion;

  @override
  State<TerminalCompletionMenu> createState() => _TerminalCompletionMenuState();
}

class _TerminalCompletionMenuState extends State<TerminalCompletionMenu> {
  static const _rowHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    final cursorRect = widget.terminalViewKey.currentState?.cursorRect;
    if (widget.suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visibleSuggestions = widget.suggestions.take(6).toList();
            final menuHeight = visibleSuggestions.length * _rowHeight;
            final menuWidth = (constraints.maxWidth - 32)
                .clamp(220.0, 560.0)
                .toDouble();
            final maxLeft = (constraints.maxWidth - menuWidth - 16)
                .clamp(16.0, constraints.maxWidth)
                .toDouble();
            final fallbackTop = (constraints.maxHeight - menuHeight - 52)
                .clamp(12.0, constraints.maxHeight)
                .toDouble();
            final left = (cursorRect?.left ?? 16.0)
                .clamp(16.0, maxLeft)
                .toDouble();
            final topBelow = (cursorRect?.bottom ?? fallbackTop) + 12;
            final topAbove = (cursorRect?.top ?? fallbackTop) - menuHeight - 12;
            final top = topBelow + menuHeight <= constraints.maxHeight - 12
                ? topBelow
                : topAbove.clamp(12.0, constraints.maxHeight).toDouble();

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: menuWidth,
                  height: menuHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.terminal.withValues(alpha: .9),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: .7),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final suggestion in visibleSuggestions)
                          InkWell(
                            onTap: () => _selectSuggestion(suggestion),
                            child: _TerminalCompletionRow(
                              suggestion: suggestion,
                              selected:
                                  suggestion.command ==
                                  widget.suggestionSuffix?.command,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _selectSuggestion(TerminalSuggestion suggestion) {
    if (widget.onSelectSuggestion != null) {
      widget.onSelectSuggestion!(suggestion);
    }
  }
}

class _TerminalCompletionRow extends StatelessWidget {
  const _TerminalCompletionRow({
    required this.suggestion,
    required this.selected,
  });

  final TerminalSuggestion suggestion;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = switch (suggestion.source) {
      TerminalSuggestionSource.history => AppColors.green,
      TerminalSuggestionSource.remoteHelp => AppColors.cyan,
    };
    final description = suggestion.description.trim();

    return Container(
      height: _TerminalCompletionMenuState._rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: selected ? AppColors.primaryBlue.withValues(alpha: .28) : null,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: suggestion.display,
                style: TextStyle(
                  color: selected ? AppColors.text : color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (description.isNotEmpty)
                TextSpan(
                  text: ' -- $description',
                  style: TextStyle(
                    color: selected ? AppColors.text : AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: const TextStyle(
            fontSize: 12,
            height: 1,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
