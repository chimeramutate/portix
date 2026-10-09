import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Draws a 2px accent outline while a descendant has keyboard focus.
/// Ink focus highlights are too faint on dark cards to count as visible focus.
class FocusRing extends StatefulWidget {
  const FocusRing({required this.child, this.radius = 8, super.key});

  final Widget child;
  final double radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final keyboard =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: _focused && keyboard
              ? Border.all(color: AppColors.cyan, width: 2)
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
