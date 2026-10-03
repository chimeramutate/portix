import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

import '../../controller/terminal_search_controller.dart';

/// Find-in-terminal box: Enter / Shift+Enter step through matches, Esc
/// closes.
class TerminalSearchBar extends StatefulWidget {
  const TerminalSearchBar({
    required this.search,
    required this.onClose,
    super.key,
  });

  final TerminalSearchController search;
  final VoidCallback onClose;

  @override
  State<TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<TerminalSearchBar> {
  late final _query = TextEditingController(text: widget.search.query);
  final _focus = FocusNode();

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String _) {
    if (HardwareKeyboard.instance.isShiftPressed) {
      widget.search.previous();
    } else {
      widget.search.next();
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: AppColors.surface,
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListenableBuilder(
            listenable: widget.search,
            builder: (context, _) {
              final search = widget.search;
              final status = search.query.isEmpty
                  ? ''
                  : search.matchCount == 0
                  ? 'No results'
                  : '${search.current + 1}/${search.matchCount}'
                        '${search.matchCount >= maxTerminalMatches ? '+' : ''}';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_rounded, size: 16),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      key: const ValueKey('terminal-search-field'),
                      controller: _query,
                      focusNode: _focus,
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Find in terminal',
                        border: InputBorder.none,
                      ),
                      onChanged: search.search,
                      onSubmitted: _submit,
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      status,
                      textAlign: TextAlign.right,
                      style: portixMuted(12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous (Shift+Enter)',
                    visualDensity: VisualDensity.compact,
                    onPressed: search.matchCount == 0 ? null : search.previous,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Next (Enter)',
                    visualDensity: VisualDensity.compact,
                    onPressed: search.matchCount == 0 ? null : search.next,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close (Esc)',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
