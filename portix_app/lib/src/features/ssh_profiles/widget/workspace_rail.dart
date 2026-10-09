import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/theme/app_theme.dart';

import '../bloc/index.dart';

const workspaceRailWidth = 48.0;

/// Icon-only activity bar in the style of VS Code: names live in tooltips,
/// the active view gets a 2px marker on the left edge.
class WorkspaceRail extends StatelessWidget {
  const WorkspaceRail({required this.activeView, super.key});

  final WorkspaceView activeView;

  @override
  Widget build(BuildContext context) {
    Widget item(WorkspaceView view, IconData icon, String label) => _RailItem(
      selected: view == activeView,
      icon: icon,
      label: label,
      onTap: () =>
          context.read<SshWorkspaceBloc>().add(NavigationChanged(view)),
    );

    return Container(
      width: workspaceRailWidth,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          item(
            WorkspaceView.gallery,
            Icons.format_list_bulleted_rounded,
            'SSH profiles',
          ),
          item(WorkspaceView.rdp, Icons.computer_outlined, 'RDP'),
          item(WorkspaceView.sftp, Icons.cable_rounded, 'SFTP'),
          const Spacer(),
          item(WorkspaceView.settings, Icons.settings_outlined, 'Settings'),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    return Semantics(
      selected: widget.selected,
      child: Tooltip(
        message: widget.label,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: SizedBox(
            width: workspaceRailWidth,
            height: 48,
            child: Stack(
              children: [
                if (widget.selected)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: AppColors.cyan),
                  ),
                Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: _focused
                          ? Border.all(color: AppColors.cyan, width: 2)
                          : null,
                    ),
                    child: Icon(
                      widget.icon,
                      size: 22,
                      color: active ? AppColors.text : AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
