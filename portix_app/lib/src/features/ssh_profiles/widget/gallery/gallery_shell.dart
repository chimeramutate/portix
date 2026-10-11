import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/index.dart';
import 'group_sidebar.dart';
import 'profile_gallery.dart';
import 'profile_inspector.dart';

class GalleryShell extends StatefulWidget {
  const GalleryShell({super.key});

  @override
  State<GalleryShell> createState() => _GalleryShellState();
}

class _GalleryShellState extends State<GalleryShell> {
  bool _groupsCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshWorkspaceBloc, SshWorkspaceState>(
      builder: (context, state) {
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showGroups = constraints.maxWidth >= 760;
                  final selected = state.selectedProfile;
                  final showInspector =
                      constraints.maxWidth >= 1120 && selected != null;
                  final inspectorWidth = (constraints.maxWidth * 0.25).clamp(
                    280.0,
                    360.0,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showGroups)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          width: _groupsCollapsed
                              ? groupSidebarCollapsedWidth
                              : groupSidebarWidth,
                          // Lay out at the final width and clip, so the list
                          // doesn't squeeze while the width animates.
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: _groupsCollapsed
                                  ? groupSidebarCollapsedWidth
                                  : groupSidebarWidth,
                              maxWidth: _groupsCollapsed
                                  ? groupSidebarCollapsedWidth
                                  : groupSidebarWidth,
                              child: GroupSidebar(
                                state: state,
                                collapsed: _groupsCollapsed,
                                onToggle: () => setState(
                                  () => _groupsCollapsed = !_groupsCollapsed,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Expanded(child: ProfileGallery(state: state)),
                      if (showInspector)
                        SizedBox(
                          width: inspectorWidth,
                          child: ProfileInspector(profile: selected),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
