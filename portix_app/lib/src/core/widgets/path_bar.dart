import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_panel.dart';

/// A directory entry offered by [PathBar]'s Tab autocomplete.
typedef PathEntry = ({String name, bool isDirectory});

/// Editable path field with on-demand Tab/arrow autocomplete of the typed
/// directory. Used by the SFTP panes and the SSH remote folder view.
class PathBar extends StatefulWidget {
  const PathBar({
    required this.path,
    super.key,
    required this.onSubmit,
    this.onListPath,
  });

  final String path;
  final ValueChanged<String> onSubmit;

  /// Non-navigating directory lister used for Tab autocomplete. Returns the
  /// children of the given directory path. When null, autocomplete is off.
  final Future<List<PathEntry>> Function(String)? onListPath;

  @override
  State<PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<PathBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.path,
  );
  late final FocusNode _focusNode = FocusNode();

  // Tab autocomplete state. Only populated on demand (Tab / ArrowDown), never
  // while typing, so Tab focus traversal elsewhere in the app is untouched.
  final List<PathEntry> _candidates = [];
  bool _open = false;
  bool _loading = false;
  int _highlight = 0;
  final ScrollController _scrollController = ScrollController();

  /// Caches raw children of a directory so repeated completions in the same
  /// directory don't re-hit the SSH backend on every Tab press.
  final Map<String, List<PathEntry>> _dirCache = {};

  /// (parent, prefix) of the most recent listing so Tab can detect changes.
  String _lastParent = '';
  String _lastPrefix = '';

  bool _tearingDown = false;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _onKey;
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _close();
    });
  }

  @override
  void didUpdateWidget(covariant PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path && _controller.text == oldWidget.path) {
      _controller.text = widget.path;
    }
  }

  @override
  void dispose() {
    // Mark as torn down BEFORE releasing resources: _focusNode.dispose() can
    // synchronously fire the focus listener, which must not call setState on
    // an element that is being unmounted.
    _tearingDown = true;
    _scrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted || _tearingDown) return;
    setState(() {
      _open = false;
      _candidates.clear();
    });
  }

  (String, String) _splitDirAndPrefix(String input) {
    final slash = input.lastIndexOf('/');
    if (slash < 0) return ('', input);
    return (input.substring(0, slash + 1), input.substring(slash + 1));
  }

  Future<void> _fetch() async {
    final lister = widget.onListPath;
    if (lister == null) return;
    final (parent, prefix) = _splitDirAndPrefix(_controller.text);
    if (parent.isEmpty) return;
    if (!mounted) return;
    _lastParent = parent;
    _lastPrefix = prefix;
    setState(() => _loading = true);
    try {
      final List<PathEntry> entries;
      final cached = _dirCache[parent];
      if (cached != null) {
        entries = cached;
      } else {
        final fetched = await lister(parent);
        if (!mounted) return;
        _dirCache[parent] = fetched;
        entries = fetched;
      }
      final pl = prefix.toLowerCase();
      final filtered =
          entries
              .where((e) => e.name != '.' && e.name != '..')
              .where((e) => e.name.toLowerCase().startsWith(pl))
              .toList()
            ..sort(
              (a, b) => switch (a.isDirectory == b.isDirectory) {
                true => a.name.compareTo(b.name),
                _ => a.isDirectory ? -1 : 1,
              },
            );
      if (!mounted) return;
      setState(() {
        _candidates
          ..clear()
          ..addAll(filtered);
        _highlight = 0;
        _open = _candidates.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _candidates.clear();
        _highlight = 0;
        _open = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _complete(PathEntry entry) {
    final (parent, _) = _splitDirAndPrefix(_controller.text);
    final newText = parent + entry.name + (entry.isDirectory ? '/' : '');
    _controller
      ..text = newText
      ..selection = TextSelection.collapsed(offset: newText.length);
    _close();
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final logical = event.logicalKey;

    if (logical == LogicalKeyboardKey.escape) {
      if (_open) {
        _close();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!_open &&
        (logical == LogicalKeyboardKey.arrowDown ||
            logical == LogicalKeyboardKey.arrowUp)) {
      if (!_loading) _fetch();
      return KeyEventResult.handled;
    }

    if (_open && logical == LogicalKeyboardKey.tab) {
      final (p, pf) = _splitDirAndPrefix(_controller.text);
      if (p.isNotEmpty && (p != _lastParent || pf != _lastPrefix)) {
        if (!_loading) _fetch();
        return KeyEventResult.handled;
      }
      if (_candidates.isNotEmpty) {
        if (_highlight < _candidates.length - 1) {
          setState(() => _highlight++);
          _scrollToHighlight();
        } else {
          // Past the last row: release Tab so focus can leave the field.
          _close();
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      }
      _close();
      return KeyEventResult.ignored;
    }

    if (_open &&
        (logical == LogicalKeyboardKey.arrowDown ||
            logical == LogicalKeyboardKey.arrowUp)) {
      final (p, pf) = _splitDirAndPrefix(_controller.text);
      if (p.isNotEmpty && (p != _lastParent || pf != _lastPrefix)) {
        if (!_loading) _fetch();
        return KeyEventResult.handled;
      }
      if (_candidates.isNotEmpty) {
        if (logical == LogicalKeyboardKey.arrowDown &&
            _highlight < _candidates.length - 1) {
          setState(() => _highlight++);
          _scrollToHighlight();
        } else if (logical == LogicalKeyboardKey.arrowUp && _highlight > 0) {
          setState(() => _highlight--);
          _scrollToHighlight();
        }
      }
      return KeyEventResult.handled;
    }

    if (_open &&
        _candidates.isNotEmpty &&
        (logical == LogicalKeyboardKey.enter ||
            logical == LogicalKeyboardKey.numpadEnter)) {
      _complete(_candidates[_highlight]);
      return KeyEventResult.handled;
    }

    // Tab when closed opens the list only when there is text to complete; an
    // empty field falls through to normal focus traversal.
    if (!_open &&
        logical == LogicalKeyboardKey.tab &&
        _controller.text.trim().isNotEmpty) {
      if (!_loading) _fetch();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToHighlight() {
    const rowHeight = 32.0;
    final extent = rowHeight * (_highlight + 1);
    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0) {
      if (_scrollController.offset > extent ||
          extent >
              _scrollController.offset +
                  _scrollController.position.viewportDimension) {
        _scrollController.animateTo(
          (extent - rowHeight / 2).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, color: AppColors.muted, size: 16),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onSubmitted: (value) {
                    if (_open && _candidates.isNotEmpty) {
                      _complete(_candidates[_highlight]);
                    } else {
                      widget.onSubmit(value);
                    }
                  },
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (widget.onListPath != null) ...[
                const SizedBox(width: 4),
                Text(
                  'Tab',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                tooltip: _open ? 'Close suggestions' : 'Open path',
                onPressed: _open
                    ? () => _close()
                    : () => widget.onSubmit(_controller.text),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                icon: Icon(
                  _open ? Icons.close_rounded : Icons.keyboard_return_rounded,
                  color: AppColors.muted,
                  size: 17,
                ),
              ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 160,
              child: _loading
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _candidates.length,
                      itemBuilder: (context, index) {
                        final entry = _candidates[index];
                        final isHighlight = index == _highlight;
                        return GestureDetector(
                          onTap: () => _complete(entry),
                          child: Container(
                            height: 32,
                            color: isHighlight
                                ? AppColors.surfaceCard
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  entry.isDirectory
                                      ? Icons.folder_outlined
                                      : Icons.insert_drive_file_outlined,
                                  color: entry.isDirectory
                                      ? AppColors.amber
                                      : AppColors.muted,
                                  size: 15,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    entry.name,
                                    style: TextStyle(
                                      color: isHighlight
                                          ? AppColors.text
                                          : AppColors.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
