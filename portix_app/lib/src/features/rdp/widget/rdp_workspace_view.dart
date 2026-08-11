import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/domain/repositories/rdp/index.dart';
import 'package:portix/src/features/rdp/bloc/index.dart';
import 'package:portix/src/features/rdp/page/rdp_session_page.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';
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

  // ── New Profile: manual create + save to database ─────────────────────────
  Future<void> _openNewProfileDialog(BuildContext context) async {
    final profile = await RdpManualFormDialog.show(context);
    if (profile == null) return;

    final result = await sl<RdpProfileRepository>().saveProfile(profile);
    result.fold(
      (failure) {
        _showError(failure.message);
      },
      (_) {
        context.read<RdpWorkspaceBloc>().add(const RdpProfilesRequested());
        _showSuccess('RDP profile saved successfully.');
      },
    );
  }

  // ── Import .rdp: pick + parse + connect (no save) ──────────────────────────
  Future<void> _openRdpImportDialog(BuildContext context) async {
    try {
      // 1. Pick and parse .rdp file
      final profile = await RdpFileImportDialog.pickAndParse();
      if (profile == null) return; // User cancelled

      if (!mounted) return;

      // 2. Connect directly (both Cyberark PSM and manual RDP)
      await _connectRdpSession(context, profile);
    } catch (e) {
      _showError('Failed to import .rdp: $e');
    }
  }

  // ── Connect RDP session ────────────────────────────────────────────────────
  Future<void> _connectRdpSession(
    BuildContext context,
    RdpProfile profile,
  ) async {
    try {
      // 1. Show connection options dialog
      final connectionOptions = await _showRdpConnectionDialog(
        context,
        profile,
        isCyberark: profile.isCyberArkPsm,
      );

      if (connectionOptions == null) return;

      // 2. Get password
      String password = '';
      if (profile.isCyberArkPsm) {
        // Cyberark: NO password prompt (PSM gateway handle auth)
        // TODO: Implement proper Cyberark vault retrieval
        // password = await sl<CyberarkService>().retrievePassword(profile);
        password = '';
      } else {
        // Manual RDP: prompt for password
        password = await _promptPassword(context, profile.username);
        if (password.isEmpty) return; // User cancelled
      }

      if (!mounted) return;

      // 3. Connect
      final sessionId = await _connectToRdp(
        profile: profile,
        password: password,
        localSharePath: connectionOptions['localFolder'] as String?,
        enableFileSharing: connectionOptions['enableSharing'] as bool? ?? false,
      );

      if (mounted) {
        _showSuccess('Connected to ${profile.host}');

        // 4. Navigate to RDP session
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
              _navigatedSessionId = null;
              _scheduleSessionCleanup(profile.id);
            });
      }
    } catch (e) {
      if (mounted) _showError('Connection failed: $e');
    }
  }

  // ── Dialog: Connection options ─────────────────────────────────────────────
  Future<Map<String, Object?>?> _showRdpConnectionDialog(
    BuildContext context,
    RdpProfile profile, {
    required bool isCyberark,
  }) async {
    bool enableSharing = false;

    return showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                isCyberark ? 'CyberArk PSM Connection' : 'RDP Connection',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Host: ${profile.host}:${profile.port}'),
                  Text('User: ${profile.username}'),
                  if (profile.domain != null) Text('Domain: ${profile.domain}'),
                  const SizedBox(height: 16),
                  if (profile.redirectDrives)
                    CheckboxListTile(
                      value: enableSharing,
                      onChanged: (value) {
                        setState(() => enableSharing = value ?? false);
                      },
                      title: const Text('Enable file sharing'),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop({'localFolder': null, 'enableSharing': enableSharing}),
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Prompt password for manual RDP ─────────────────────────────────────────
  Future<String> _promptPassword(BuildContext context, String username) async {
    final controller = TextEditingController();

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Password'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password for $username',
              hintText: 'Enter your password',
            ),
            autofocus: true,
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );

    return password ?? '';
  }

  // ── Connect to RDP via backend service ─────────────────────────────────────
  Future<String> _connectToRdp({
    required RdpProfile profile,
    required String password,
    String? localSharePath,
    bool enableFileSharing = false,
  }) async {
    final backendService = sl<RdpBackendService>();
    final profileToUse = profile.copyWith(
      password: password.isNotEmpty ? password : null,
    );

    final result = await backendService.connect(profileToUse);

    return result.fold<String>(
      (failure) => throw StateError(failure.message),
      (connectionResult) => connectionResult.sessionId,
    );
  }

  // ── Show success message ───────────────────────────────────────────────────
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Show error message ─────────────────────────────────────────────────────
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Schedule cleanup after session ends ─────────────────────────────────────
  void _scheduleSessionCleanup(String profileId) {
    // Cleanup handled by backend session lifecycle
    // This is a placeholder for future cleanup logic
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RDP Details Panel
// ══════════════════════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════════════════════
// Detail Row Widget
// ══════════════════════════════════════════════════════════════════════════════

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
