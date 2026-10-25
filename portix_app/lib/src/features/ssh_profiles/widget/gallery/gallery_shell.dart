import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'profile_gallery.dart';
import 'profile_inspector.dart';

/// Profile cards, with the selected profile's inspector on wide windows.
/// The group list lives in the workspace side panel.
class GalleryShell extends StatelessWidget {
  const GalleryShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshWorkspaceBloc, SshWorkspaceState>(
      builder: (context, state) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final selected = state.selectedProfile;
            final showInspector =
                constraints.maxWidth >= 880 && selected != null;
            final inspectorWidth = (constraints.maxWidth * 0.3).clamp(
              280.0,
              360.0,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ProfileGallery(state: state)),
                if (showInspector)
                  SizedBox(
                    width: inspectorWidth,
                    child: ProfileInspector(profile: selected),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
