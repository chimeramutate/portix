import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';

import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'workspace_rail.dart';
import 'workspace_top_bar.dart';

/// Windows narrower than this hide the side panel, leaving room for content.
const sidePanelMinWindowWidth = 760.0;

/// Top bar over rail, the active view's side [panel], and the content.
/// Clicking the active rail item collapses or expands the panel.
class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    required this.state,
    required this.child,
    this.panel,
    super.key,
  });

  final SshWorkspaceState state;
  final Widget child;
  final Widget? panel;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  bool _panelCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            WorkspaceTopBar(state: widget.state),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WorkspaceRail(
                      activeView: widget.state.activeView,
                      onReselect: panel == null
                          ? null
                          : () => setState(
                              () => _panelCollapsed = !_panelCollapsed,
                            ),
                    ),
                    if (panel != null &&
                        !_panelCollapsed &&
                        constraints.maxWidth >= sidePanelMinWindowWidth)
                      panel,
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
