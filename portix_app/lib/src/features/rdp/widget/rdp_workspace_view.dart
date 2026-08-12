import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/domain/repositories/rdp/index.dart';
import 'package:portix/src/features/rdp/bloc/index.dart';
import 'package:portix/src/features/rdp/page/rdp_session_page.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';
import 'package:portix/src/features/rdp/service/rdp_window_service.dart';
import 'package:portix/src/features/rdp/widget/rdp_file_import_dialog.dart';
import 'package:portix/src/features/rdp/widget/rdp_manual_form_dialog.dart';
import 'package:portix/src/features/rdp/widget/rdp_profile_card.dart';

class RdpWorkspaceView extends StatefulWidget {
  const RdpWorkspaceView({super.key});

  @override
  State<RdpWorkspaceView> createState() => _RdpWorkspaceViewState();
}

class _RdpWorkspaceViewState extends State<RdpWorkspaceView> {
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

        if (_navigatedSessionId == sessionId) return;
        _navigatedSessionId = sessionId;

        _openSessionSurface(
          context,
          profile: profile,
          sessionId: sessionId,
        ).whenComplete(() {
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
              padding: const EdgeInsets.all(24),
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

        // ============================================================
        // EDIT / FORM VIEW
        // ============================================================

        if (state.activeView == RdpView.form && state.editingProfile != null) {
          return _RdpEditView(
            profile: state.editingProfile!,
            onCancel: () {
              context.read<RdpWorkspaceBloc>().add(
                const RdpProfileSelectionCleared(),
              );

              context.read<RdpWorkspaceBloc>().add(
                const RdpNavigationChanged(RdpView.gallery),
              );
            },
          );
        }

        // ============================================================
        // GALLERY VIEW
        // ============================================================

        final profiles = state.filteredProfiles;
        final selectedProfile = state.selectedProfile;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ========================================================
              // HEADER
              // ========================================================
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
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/rdp-frame-test');
                    },
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

              // ========================================================
              // PROFILE GRID
              // ========================================================
              Expanded(
                child: profiles.isEmpty
                    ? _EmptyProfiles()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount = constraints.maxWidth >= 1400
                              ? 3
                              : constraints.maxWidth >= 900
                              ? 2
                              : 1;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: GridView.builder(
                                  padding: EdgeInsets.zero,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,

                                        // IMPORTANT:
                                        // Jangan gunakan childAspectRatio tinggi.
                                        // Profile card sekarang fixed-height.
                                        mainAxisExtent: 68,

                                        mainAxisSpacing: 6,
                                        crossAxisSpacing: 6,
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

                              const SizedBox(height: 14),

                              if (selectedProfile != null)
                                _RdpDetailsPanel(profile: selectedProfile)
                              else
                                _NoSelectionPanel(),
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

  // ================================================================
  // NEW PROFILE
  // ================================================================

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

  // ================================================================
  // IMPORT .RDP
  // ================================================================

  Future<void> _openRdpImportDialog(BuildContext context) async {
    try {
      final profile = await RdpFileImportDialog.pickAndParse();

      if (profile == null) return;

      if (!mounted) return;

      await _connectRdpSession(context, profile);
    } catch (e) {
      _showError('Failed to import .rdp: $e');
    }
  }

  // ================================================================
  // CONNECT
  // ================================================================

  Future<void> _connectRdpSession(
    BuildContext context,
    RdpProfile profile,
  ) async {
    try {
      final connectionOptions = await _showRdpConnectionDialog(
        context,
        profile,
        isCyberark: profile.isCyberArkPsm,
      );

      if (connectionOptions == null) return;

      String password = '';

      if (profile.isCyberArkPsm) {
        password = '';
      } else {
        password = await _promptPassword(context, profile.username);

        if (password.isEmpty) return;
      }

      if (!mounted) return;

      final sessionId = await _connectToRdp(
        profile: profile,
        password: password,
        localSharePath: connectionOptions['localFolder'] as String?,
        enableFileSharing: connectionOptions['enableSharing'] as bool? ?? false,
      );

      if (!mounted) return;

      _showSuccess('Connected to ${profile.host}');

      if (_navigatedSessionId == sessionId) return;

      _navigatedSessionId = sessionId;

      await _openSessionSurface(
        context,
        profile: profile,
        sessionId: sessionId,
      );
      _navigatedSessionId = null;
      _scheduleSessionCleanup(profile.id);
    } catch (e) {
      if (mounted) {
        _showError('Connection failed: $e');
      }
    }
  }

  // ================================================================
  // CONNECTION OPTIONS
  // ================================================================

  Future<Map<String, Object?>?> _showRdpConnectionDialog(
    BuildContext context,
    RdpProfile profile, {
    required bool isCyberark,
  }) async {
    bool enableSharing = profile.redirectDrives;
    final localFolderController = TextEditingController(
      text: profile.effectiveLocalSharePath,
    );

    final result = await showDialog<Map<String, Object?>>(
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
                        setState(() {
                          enableSharing = value ?? false;
                          if (enableSharing &&
                              localFolderController.text.trim().isEmpty) {
                            localFolderController.text =
                                RdpProfile.defaultLocalSharePath;
                          }
                        });
                      },
                      title: const Text('Enable file sharing'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  if (profile.redirectDrives && enableSharing) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: localFolderController,
                      decoration: InputDecoration(
                        labelText: 'Local shared folder',
                        prefixIcon: const Icon(Icons.folder_shared_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Choose folder',
                          onPressed: () async {
                            final selected = await FilePicker.getDirectoryPath(
                              dialogTitle: 'Select local folder to share',
                            );
                            if (selected == null) return;
                            setState(() {
                              localFolderController.text = selected;
                            });
                          },
                          icon: const Icon(Icons.folder_open_outlined),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(null);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop({
                      'localFolder': localFolderController.text.trim(),
                      'enableSharing': enableSharing,
                    });
                  },
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );
    localFolderController.dispose();
    return result;
  }

  // ================================================================
  // PASSWORD
  // ================================================================

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
            onSubmitted: (_) {
              Navigator.of(dialogContext).pop(controller.text);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    return password ?? '';
  }

  // ================================================================
  // BACKEND CONNECT
  // ================================================================

  Future<String> _connectToRdp({
    required RdpProfile profile,
    required String password,
    String? localSharePath,
    bool enableFileSharing = false,
  }) async {
    final backendService = sl<RdpBackendService>();

    final profileToUse = profile.copyWith(
      password: password.isNotEmpty ? password : null,
      redirectDrives: enableFileSharing,
      localSharePath: enableFileSharing
          ? (localSharePath?.trim().isNotEmpty == true
                ? localSharePath!.trim()
                : profile.effectiveLocalSharePath)
          : null,
      clearLocalSharePath: !enableFileSharing,
    );

    final result = await backendService.connect(profileToUse);

    return result.fold<String>(
      (failure) {
        throw StateError(failure.message);
      },
      (connectionResult) {
        return connectionResult.sessionId;
      },
    );
  }

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

  Future<void> _openSessionSurface(
    BuildContext context, {
    required RdpProfile profile,
    required String sessionId,
  }) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await RdpWindowService.openSession(
          profile: profile,
          sessionId: sessionId,
        );
        return;
      } catch (error) {
        debugPrint('Failed to open RDP session window: $error');
      }
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            RdpSessionPage(profile: profile, sessionId: sessionId),
      ),
    );
  }

  void _scheduleSessionCleanup(String profileId) {
    // Backend menangani lifecycle session.
  }
}

// ====================================================================
// EDIT PROFILE VIEW
// ====================================================================

class _RdpEditView extends StatefulWidget {
  const _RdpEditView({required this.profile, required this.onCancel});

  final RdpProfile profile;
  final VoidCallback onCancel;

  @override
  State<_RdpEditView> createState() => _RdpEditViewState();
}

class _RdpEditViewState extends State<_RdpEditView> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _domainController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _shellController;
  late final TextEditingController _passwordController;
  late final TextEditingController _localSharePathController;

  late bool _fullScreen;
  late bool _redirectDrives;
  late bool _redirectClipboard;
  late bool _enableCredSsp;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final p = widget.profile;

    _nameController = TextEditingController(text: p.name);

    _hostController = TextEditingController(text: p.host);

    _portController = TextEditingController(text: p.port.toString());

    _usernameController = TextEditingController(text: p.username);

    _domainController = TextEditingController(text: p.domain ?? '');

    _widthController = TextEditingController(text: p.desktopWidth.toString());

    _heightController = TextEditingController(text: p.desktopHeight.toString());

    _shellController = TextEditingController(text: p.alternateShell);

    _passwordController = TextEditingController(text: p.password ?? '');

    _localSharePathController = TextEditingController(
      text: p.localSharePath?.isNotEmpty == true
          ? p.localSharePath
          : RdpProfile.defaultLocalSharePath,
    );

    _fullScreen = p.fullScreen;
    _redirectDrives = p.redirectDrives;
    _redirectClipboard = p.redirectClipboard;
    _enableCredSsp = p.enableCredSsp;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _domainController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _shellController.dispose();
    _passwordController.dispose();
    _localSharePathController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==========================================================
          // HEADER
          // ==========================================================
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: widget.onCancel,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              const Text(
                'Edit RDP Profile',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _saving ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save Changes'),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ==========================================================
          // FORM
          // ==========================================================
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connection',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        const SizedBox(height: 14),

                        _twoColumns(
                          _field(
                            controller: _nameController,
                            label: 'Profile Name',
                            icon: Icons.label_outline,
                          ),
                          _field(
                            controller: _hostController,
                            label: 'Host / IP',
                            icon: Icons.dns_outlined,
                          ),
                        ),

                        const SizedBox(height: 12),

                        _twoColumns(
                          _field(
                            controller: _portController,
                            label: 'Port',
                            icon: Icons.settings_ethernet,
                            keyboardType: TextInputType.number,
                          ),
                          _field(
                            controller: _usernameController,
                            label: 'Username',
                            icon: Icons.person_outline,
                          ),
                        ),

                        const SizedBox(height: 12),

                        _twoColumns(
                          _field(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline,
                            obscureText: true,
                          ),
                          _field(
                            controller: _domainController,
                            label: 'Domain',
                            icon: Icons.domain_outlined,
                          ),
                        ),

                        const SizedBox(height: 24),

                        const Text(
                          'Display',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        const SizedBox(height: 14),

                        _twoColumns(
                          _field(
                            controller: _widthController,
                            label: 'Desktop Width',
                            icon: Icons.width_normal_outlined,
                            keyboardType: TextInputType.number,
                          ),
                          _field(
                            controller: _heightController,
                            label: 'Desktop Height',
                            icon: Icons.height_outlined,
                            keyboardType: TextInputType.number,
                          ),
                        ),

                        const SizedBox(height: 8),

                        SwitchListTile(
                          value: _fullScreen,
                          onChanged: (value) {
                            setState(() {
                              _fullScreen = value;
                            });
                          },
                          title: const Text('Full Screen'),
                          subtitle: const Text(
                            'Use the remote desktop in full-screen mode.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),

                        const SizedBox(height: 18),

                        const Text(
                          'Redirection',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        const SizedBox(height: 8),

                        SwitchListTile(
                          value: _redirectDrives,
                          onChanged: (value) {
                            setState(() {
                              _redirectDrives = value;
                              if (_redirectDrives &&
                                  _localSharePathController.text
                                      .trim()
                                      .isEmpty) {
                                _localSharePathController.text =
                                    RdpProfile.defaultLocalSharePath;
                              }
                            });
                          },
                          title: const Text('Drive / File Sharing'),
                          subtitle: const Text(
                            'Share a local folder as PORTIX in the remote session.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),

                        if (_redirectDrives) ...[
                          const SizedBox(height: 8),
                          _field(
                            controller: _localSharePathController,
                            label: 'Local Shared Folder',
                            icon: Icons.folder_shared_outlined,
                            suffixIcon: IconButton(
                              tooltip: 'Choose folder',
                              onPressed: _pickLocalShareFolder,
                              icon: const Icon(Icons.folder_open_outlined),
                            ),
                          ),
                        ],

                        SwitchListTile(
                          value: _redirectClipboard,
                          onChanged: (value) {
                            setState(() {
                              _redirectClipboard = value;
                            });
                          },
                          title: const Text('Clipboard'),
                          subtitle: const Text('Allow clipboard redirection.'),
                          contentPadding: EdgeInsets.zero,
                        ),

                        const SizedBox(height: 18),

                        const Text(
                          'Security',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        SwitchListTile(
                          value: _enableCredSsp,
                          onChanged: (value) {
                            setState(() {
                              _enableCredSsp = value;
                            });
                          },
                          title: const Text('Enable CredSSP / NLA'),
                          subtitle: const Text(
                            'Use Network Level Authentication when available.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),

                        const SizedBox(height: 18),

                        _field(
                          controller: _shellController,
                          label: 'Alternate Shell',
                          icon: Icons.terminal_outlined,
                        ),

                        const SizedBox(height: 24),

                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: AppColors.cyan,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Profile ID: ${widget.profile.id}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _twoColumns(Widget first, Widget second) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();

    final host = _hostController.text.trim();

    final username = _usernameController.text.trim();

    final port = int.tryParse(_portController.text.trim()) ?? 0;

    final width =
        int.tryParse(_widthController.text.trim()) ??
        widget.profile.desktopWidth;

    final height =
        int.tryParse(_heightController.text.trim()) ??
        widget.profile.desktopHeight;

    // ================================================================
    // VALIDATION
    // ================================================================

    if (name.isEmpty) {
      _error('Profile name is required.');
      return;
    }

    if (host.isEmpty) {
      _error('Host / IP is required.');
      return;
    }

    if (port <= 0 || port > 65535) {
      _error('Port must be between 1 and 65535.');
      return;
    }

    if (username.isEmpty) {
      _error('Username is required.');
      return;
    }

    if (width <= 0 || height <= 0) {
      _error('Desktop resolution is invalid.');
      return;
    }

    if (_redirectDrives && _localSharePathController.text.trim().isEmpty) {
      _error('Local shared folder is required when drive sharing is enabled.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // ==============================================================
      // BUILD UPDATED PROFILE
      // ==============================================================

      final updatedProfile = widget.profile.copyWith(
        name: name,
        host: host,
        port: port,
        username: username,
        domain: _domainController.text.trim().isEmpty
            ? null
            : _domainController.text.trim(),
        password: _passwordController.text.isEmpty
            ? widget.profile.password
            : _passwordController.text,
        desktopWidth: width,
        desktopHeight: height,
        fullScreen: _fullScreen,
        redirectDrives: _redirectDrives,
        redirectClipboard: _redirectClipboard,
        localSharePath: _redirectDrives
            ? _localSharePathController.text.trim()
            : null,
        clearLocalSharePath: !_redirectDrives,
        enableCredSsp: _enableCredSsp,
        alternateShell: _shellController.text.trim().isEmpty
            ? null
            : _shellController.text.trim(),
      );

      // ==============================================================
      // SAVE DIRECTLY TO REPOSITORY
      // ==============================================================
      //
      // Kita sengaja save langsung di sini supaya:
      //
      // Edit -> UPDATE
      //
      // bukan:
      //
      // Edit -> create profile baru
      //
      // ID profile lama tetap dipertahankan.
      // ==============================================================

      final result = await sl<RdpProfileRepository>().saveProfile(
        updatedProfile,
      );

      if (!mounted) return;

      result.fold(
        (failure) {
          setState(() {
            _saving = false;
          });

          _error(failure.message);
        },
        (_) {
          // Refresh list dari database.
          context.read<RdpWorkspaceBloc>().add(const RdpProfilesRequested());

          setState(() {
            _saving = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('RDP profile updated successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        },
      );

      // Setelah save berhasil, kembali ke gallery.
      if (result.isRight) {
        context.read<RdpWorkspaceBloc>().add(
          const RdpProfileSelectionCleared(),
        );

        context.read<RdpWorkspaceBloc>().add(
          const RdpNavigationChanged(RdpView.gallery),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _error('Failed to update profile: $e');
    }
  }

  Future<void> _pickLocalShareFolder() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select local folder to share',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _localSharePathController.text = selected;
    });
  }

  void _error(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }
}

// ====================================================================
// EMPTY PROFILES
// ====================================================================

class _EmptyProfiles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
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
              style: TextStyle(color: AppColors.muted, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// NO SELECTION
// ====================================================================

class _NoSelectionPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Klik profil untuk melihat detail dan opsi koneksi.',
        style: TextStyle(color: AppColors.muted, fontSize: 14),
      ),
    );
  }
}

// ====================================================================
// DETAILS PANEL
// ====================================================================

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

              // ======================================================
              // EDIT
              // ======================================================
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

              // ======================================================
              // DELETE
              // ======================================================
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) {
                      return AlertDialog(
                        title: const Text('Delete profile?'),
                        content: const Text(
                          'Are you sure you want to delete this profile?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop(false);
                            },
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop(true);
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      );
                    },
                  );

                  if (ok == true && context.mounted) {
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

// ====================================================================
// DETAIL ROW
// ====================================================================

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
