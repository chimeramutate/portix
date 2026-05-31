import 'package:flutter/material.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import '../../bloc/index.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'profile_card.dart';

class ProfileGallery extends StatelessWidget {
  const ProfileGallery({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final profiles = state.filteredProfiles;
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppPill(label: 'All', color: AppColors.cyan),
                    AppPill(label: 'Production', color: AppColors.muted),
                    AppPill(label: 'Key auth', color: AppColors.muted),
                    AppPill(label: 'Recently used', color: AppColors.muted),
                  ],
                ),
              ),
              AppButton(
                icon: Icons.grid_view_rounded,
                label: 'Gallery',
                primary: false,
                onPressed: () {},
              ),
              const SizedBox(width: 8),
              AppButton(
                icon: Icons.upload_file_rounded,
                label: 'Import',
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final count = _columnCount(constraints.maxWidth);
                return GridView.builder(
                  itemCount: profiles.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    mainAxisExtent: 230,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    return ProfileCard(
                      profile: profile,
                      selected: profile.id == state.selectedProfile?.id,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _columnCount(double width) {
    if (width >= 1400) return 4;
    if (width >= 1000) return 3;
    if (width >= 700) return 2;
    return 1;
  }
}
