import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/domain/repositories/rdp/index.dart';
import 'package:portix/src/features/rdp/bloc/index.dart';
import 'package:portix/src/features/rdp/page/rdp_session_page.dart';
import 'package:portix/src/features/rdp/widget/rdp_file_import_dialog.dart';
import 'package:portix/src/features/rdp/widget/rdp_manual_form_dialog.dart';
import 'package:portix/src/features/rdp/widget/rdp_profile_card.dart';

class RdpWorkspaceView extends StatefulWidget {
  const RdpWorkspaceView({super.key});

  @override
  State<RdpWorkspaceView> createState() => _RdpWorkspaceViewState();
}

class _RdpWorkspaceViewState extends State<RdpWorkspaceView> {
  // Guard navigasi agar tidak push dua kali untuk session yang sama
  String? _navigatedSessionId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RdpWorkspaceBloc, RdpWorkspaceState>(
      listenWhen: (previous, current) =>
          previous.lastSessionId != current.lastSessionId &&
          current.lastSessionId != null,
      listener: (context, state) {
        final profile = state.selectedProfile;
        if (profile == null) return;

        final sessionId = state.lastSessionId!;

        // Hindari navigasi ganda ke session yang sama
        if (_navigatedSessionId == sessionId) return;
        _navigatedSessionId = sessionId;

        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (context) =>
                    RdpSessionPage(profile: profile, sessionId: sessionId),
              ),
            )
            .then((_) {
              // Reset saat kembali agar koneksi baru bisa dibuka
              _navigatedSessionId = null;
            });
      },
      builder: (context, state) {
        if (state.status == RdpWorkspaceStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.status == RdpWorkspaceStatus.failure) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                state.message.isNotEmpty
                    ? state.message
                    : 'Failed to load RDP workspace.',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final profiles = state.filteredProfiles;
        final selectedProfile = state.selectedProfile;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'RDP Profiles',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _openNewProfileDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('New Profile'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => _openRdpImportDialog(context),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import .rdp'),
                  ),
                  const SizedBox(width: 10),
                  // Tombol test render frame — untuk debug sizing
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/rdp-frame-test'),
                    icon: const Icon(Icons.bug_report, size: 16),
                    label: const Text('Frame Test'),
                  ),
                ],
              ),
              if (state.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(
                    state.message,
                    style: const TextStyle(color: AppColors.cyan),
                  ),
                ),
              const SizedBox(height: 16),
              Expanded(
                child: profiles.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.desktop_windows_outlined,
                                size: 64,
                                color: AppColors.muted,
                              ),
                              SizedBox(height: 18),
                              Text(
                                'No RDP profiles yet.',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Use the toolbar above to add a new profile or import a .rdp file.',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: GridView.builder(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount:
                                            constraints.maxWidth >= 1400
                                            ? 3
                                            : constraints.maxWidth >= 900
                                            ? 2
                                            : 1,
                                        mainAxisSpacing: 14,
                                        crossAxisSpacing: 14,
                                        childAspectRatio: 1.2,
                                      ),
                                  itemCount: profiles.length,
                                  itemBuilder: (context, index) {
                                    final profile = profiles[index];
                                    return RdpProfileCard(
                                      profile: profile,
                                      selected:
                                          selectedProfile?.id == profile.id,
                                    );
                                  },
                                ),
                              ),
                              if (selectedProfile != null) ...[
                                const SizedBox(height: 14),
                                _RdpDetailsPanel(profile: selectedProfile),
                              ] else ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: const Text(
                                    'Klik profil untuk melihat detail dan opsi koneksi.',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openNewProfileDialog(BuildContext context) async {
    final profile = await RdpManualFormDialog.show(context);
    if (profile == null) return;

    final result = await sl<RdpProfileRepository>().saveProfile(profile);
    result.fold(
      (failure) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (_) {
        context.read<RdpWorkspaceBloc>().add(const RdpProfilesRequested());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RDP profile saved successfully.')),
        );
      },
    );
  }

  Future<void> _openRdpImportDialog(BuildContext context) async {
    final profile = await RdpFileImportDialog.show(context);
    if (profile == null) return;

    final result = await sl<RdpProfileRepository>().saveProfile(profile);
    result.fold(
      (failure) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (_) {
        context.read<RdpWorkspaceBloc>().add(const RdpProfilesRequested());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RDP profile imported successfully.')),
        );
      },
    );
  }
}

class _RdpDetailsPanel extends StatelessWidget {
  const _RdpDetailsPanel({required this.profile});

  final RdpProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selected profile',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          _DetailRow(label: 'Name', value: profile.name),
          _DetailRow(label: 'Host', value: profile.address),
          _DetailRow(label: 'Username', value: profile.username),
          _DetailRow(label: 'Group', value: profile.group),
          _DetailRow(
            label: 'Resolution',
            value: '${profile.desktopWidth}×${profile.desktopHeight}',
          ),
          _DetailRow(label: 'Status', value: profile.status.name),
          if (profile.sourceRdpFilePath != null)
            _DetailRow(
              label: 'Imported from',
              value: profile.sourceRdpFilePath!,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: profile.isConnectable
                    ? () {
                        context.read<RdpWorkspaceBloc>().add(
                          RdpLaunchRequested(profile.id),
                        );
                      }
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Connect'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  context.read<RdpWorkspaceBloc>().add(
                    RdpProfileEditRequested(profile.id),
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete profile?'),
                      content: const Text(
                        'Are you sure you want to delete this profile?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    context.read<RdpWorkspaceBloc>().add(
                      RdpProfileDeleted(profile.id),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                // ✅ PERBAIKAN: Update ke WidgetStateProperty (Flutter 3.22+)
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.all(AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
