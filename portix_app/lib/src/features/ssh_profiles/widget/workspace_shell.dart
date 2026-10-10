import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';

import '../bloc/index.dart';
import 'workspace_rail.dart';
import 'workspace_top_bar.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({required this.state, required this.child, super.key});

  final SshWorkspaceState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            WorkspaceTopBar(state: state),
            Expanded(
              child: Row(
                children: [
                  WorkspaceRail(activeView: state.activeView),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
