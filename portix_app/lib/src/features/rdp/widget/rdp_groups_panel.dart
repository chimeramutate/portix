import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/widgets/side_panel.dart';
import 'package:portix/src/features/rdp/bloc/rdp_workspace_bloc.dart';

/// RDP profile groups for the workspace side panel; a click filters the
/// profile grid.
class RdpGroupsPanel extends StatelessWidget {
  const RdpGroupsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RdpWorkspaceBloc>().state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [
        for (final group in state.groups)
          SidePanelTile(
            icon: group == 'All'
                ? Icons.computer_outlined
                : Icons.folder_outlined,
            label: group == 'All' ? 'All profiles' : group,
            count: group == 'All'
                ? state.profiles.length
                : state.profiles.where((p) => p.group == group).length,
            selected: state.groupFilter == group,
            onTap: () => context.read<RdpWorkspaceBloc>().add(
              RdpGroupFilterChanged(group),
            ),
          ),
      ],
    );
  }
}
