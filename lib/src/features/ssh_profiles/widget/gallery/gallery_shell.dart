import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/index.dart';
import 'group_sidebar.dart';
import 'profile_gallery.dart';
import 'profile_inspector.dart';

class GalleryShell extends StatelessWidget {
  const GalleryShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshWorkspaceBloc, SshWorkspaceState>(
      builder: (context, state) {
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showGroups = constraints.maxWidth >= 900;
                  final selected = state.selectedProfile;
                  final showInspector =
                      constraints.maxWidth >= 1120 && selected != null;
                  return Row(
                    children: [
                      if (showGroups)
                        SizedBox(width: 250, child: GroupSidebar(state: state)),
                      Expanded(child: ProfileGallery(state: state)),
                      if (showInspector)
                        SizedBox(
                          width: 300,
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
