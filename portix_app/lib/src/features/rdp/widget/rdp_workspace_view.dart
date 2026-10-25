import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/domain/repositories/rdp/rdp_profile_repository.dart';
import 'package:portix/src/features/rdp/bloc/rdp_workspace_bloc.dart';
import 'package:portix/src/features/rdp/page/rdp_session_page.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';
import 'package:portix/src/features/rdp/service/rdp_window_service.dart';
import 'package:portix/src/features/rdp/widget/rdp_file_import_dialog.dart';
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

        if (state.activeView == RdpView.form && state.editingProfile != null) {
          return _RdpEditView(
            key: ValueKey(state.editingProfile!.id),
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

        final profiles = state.filteredProfiles;
        final selectedProfile = state.selectedProfile;

        return LayoutBuilder(
          builder: (context, constraints) {
            final showDetails =
                selectedProfile != null && constraints.maxWidth >= 880;
            final list = Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        profiles.length == 1
                            ? '1 profile'
                            : '${profiles.length} profiles',
                        style: portixMuted(12),
                      ),
                      if (state.message.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            state.message,
                            overflow: TextOverflow.ellipsis,
                            style: portixMuted(12),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      const SizedBox(width: 12),
                      AppButton(
                        icon: Icons.upload_file_rounded,
                        label: 'Import .rdp',
                        onPressed: () => _openRdpImportDialog(context),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        icon: Icons.add_rounded,
                        label: 'New Profile',
                        primary: true,
                        onPressed: () => context.read<RdpWorkspaceBloc>().add(
                          const RdpNewProfileRequested(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: profiles.isEmpty
                        ? _EmptyProfiles()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount =
                                  constraints.maxWidth >= 1100
                                  ? 3
                                  : constraints.maxWidth >= 640
                                  ? 2
                                  : 1;
                              return GridView.builder(
                                padding: EdgeInsets.zero,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      mainAxisExtent: 52,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                    ),
                                itemCount: profiles.length,
                                itemBuilder: (context, index) {
                                  final profile = profiles[index];
                                  return RdpProfileCard(
                                    profile: profile,
                                    selected: selectedProfile?.id == profile.id,
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  // Narrow windows: details under the grid.
                  if (selectedProfile != null && !showDetails) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 280,
                      child: _RdpDetailsPanel(profile: selectedProfile),
                    ),
                  ],
                ],
              ),
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: list),
                if (showDetails)
                  SizedBox(
                    width: 320,
                    child: _RdpDetailsPanel(profile: selectedProfile),
                  ),
              ],
            );
          },
        );
      },
    );
  }

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

  void _scheduleSessionCleanup(String profileId) {}
}

class _RdpEditView extends StatefulWidget {
  const _RdpEditView({
    required this.profile,
    required this.onCancel,
    super.key,
  });

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
  late final TextEditingController _localShareNameController;

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

    _localShareNameController = TextEditingController(
      text: p.localShareName.isNotEmpty
          ? p.localShareName
          : RdpProfile.defaultLocalShareName,
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
    _localShareNameController.dispose();

    super.dispose();
  }

  bool get _isNew => widget.profile.status == RdpProfileStatus.draft;

  @override
  Widget build(BuildContext context) {
    final shareName = _localShareNameController.text.trim().isEmpty
        ? RdpProfile.defaultLocalShareName
        : _localShareNameController.text.trim();
    final form = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isNew ? 'New RDP Profile' : 'Edit RDP Profile',
                    style: portixTitle(15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _section('Connection', [
                _twoColumns(
                  AppTextField(
                    controller: _nameController,
                    label: 'Profile name',
                  ),
                  AppTextField(
                    controller: _hostController,
                    label: 'Host / IP',
                    hint: 'server.example.com or 10.0.0.5',
                  ),
                ),
                _twoColumns(
                  AppTextField(
                    controller: _portController,
                    label: 'Port',
                    keyboardType: TextInputType.number,
                  ),
                  AppTextField(
                    controller: _usernameController,
                    label: 'Username',
                  ),
                ),
                _twoColumns(
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: _isNew ? '' : 'Unchanged when empty',
                    obscureText: true,
                  ),
                  AppTextField(
                    controller: _domainController,
                    label: 'Domain',
                    hint: 'optional',
                  ),
                ),
              ]),
              _section('Display', [
                _twoColumns(
                  AppTextField(
                    controller: _widthController,
                    label: 'Width',
                    keyboardType: TextInputType.number,
                  ),
                  AppTextField(
                    controller: _heightController,
                    label: 'Height',
                    keyboardType: TextInputType.number,
                  ),
                ),
                _switch(
                  title: 'Full screen',
                  subtitle: 'Open the remote desktop full screen.',
                  value: _fullScreen,
                  onChanged: (value) => setState(() => _fullScreen = value),
                ),
              ]),
              _section('Redirection', [
                _switch(
                  title: 'Drive sharing',
                  subtitle: _redirectDrives
                      ? 'Shared as \\\\tsclient\\$shareName in the remote session.'
                      : 'Share a local folder in the remote session.',
                  value: _redirectDrives,
                  onChanged: (value) => setState(() {
                    _redirectDrives = value;
                    if (value &&
                        _localSharePathController.text.trim().isEmpty) {
                      _localSharePathController.text =
                          RdpProfile.defaultLocalSharePath;
                    }
                  }),
                ),
                if (_redirectDrives)
                  _twoColumns(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _localSharePathController,
                            label: 'Local folder',
                          ),
                        ),
                        const SizedBox(width: 6),
                        AppIconButton(
                          icon: Icons.folder_open_outlined,
                          tooltip: 'Choose folder',
                          color: AppColors.text,
                          onPressed: _pickLocalShareFolder,
                        ),
                      ],
                    ),
                    AppTextField(
                      controller: _localShareNameController,
                      label: 'Share name',
                      hint: RdpProfile.defaultLocalShareName,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                _switch(
                  title: 'Clipboard',
                  subtitle:
                      'Copy and paste between this computer and the remote.',
                  value: _redirectClipboard,
                  onChanged: (value) =>
                      setState(() => _redirectClipboard = value),
                ),
              ]),
              _section('Security', [
                _switch(
                  title: 'CredSSP / NLA',
                  subtitle: 'Use Network Level Authentication when available.',
                  value: _enableCredSsp,
                  onChanged: (value) => setState(() => _enableCredSsp = value),
                ),
                AppTextField(
                  controller: _shellController,
                  label: 'Alternate shell',
                  hint: 'optional',
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    // Pinned under the scrolling form so Save is always in reach.
    final footer = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            icon: Icons.close_rounded,
            label: 'Cancel',
            onPressed: _saving ? null : widget.onCancel,
          ),
          const SizedBox(width: 8),
          AppButton(
            icon: Icons.save_outlined,
            label: _saving ? 'Saving...' : 'Save',
            primary: true,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
    return Column(
      children: [
        Expanded(child: form),
        footer,
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return AppPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: portixTitle(14)),
          for (final child in children) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }

  Widget _switch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: portixMuted(12)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(value: value, onChanged: onChanged),
      ],
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
      final updatedProfile = widget.profile.copyWith(
        status: _isNew ? RdpProfileStatus.offline : null,
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
        localShareName: _localShareNameController.text.trim().isEmpty
            ? RdpProfile.defaultLocalShareName
            : _localShareNameController.text.trim(),
        enableCredSsp: _enableCredSsp,
        alternateShell: _shellController.text.trim().isEmpty
            ? null
            : _shellController.text.trim(),
      );

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

class _EmptyProfiles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.desktop_windows_outlined,
              size: 40,
              color: AppColors.muted,
            ),
            SizedBox(height: 18),
            Text(
              'No RDP profiles yet.',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add a profile with New Profile, or import a .rdp file.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RdpDetailsPanel extends StatelessWidget {
  const _RdpDetailsPanel({required this.profile});

  final RdpProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.name.isEmpty ? 'Unnamed' : profile.name,
                    overflow: TextOverflow.ellipsis,
                    style: portixTitle(15),
                  ),
                ),
                IconButton(
                  onPressed: () => context.read<RdpWorkspaceBloc>().add(
                    const RdpProfileSelectionCleared(),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.muted,
                  tooltip: 'Clear selection',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    icon: Icons.play_arrow_rounded,
                    label: 'Connect',
                    primary: true,
                    onPressed: profile.isConnectable
                        ? () => context.read<RdpWorkspaceBloc>().add(
                            RdpLaunchRequested(profile.id),
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          icon: Icons.edit_outlined,
                          label: 'Edit',
                          onPressed: () => context.read<RdpWorkspaceBloc>().add(
                            RdpProfileEditRequested(profile.id),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete',
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
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SelectionArea(
                    child: Column(
                      children: [
                        _DetailRow(label: 'Host', value: profile.address),
                        _DetailRow(label: 'User', value: profile.username),
                        _DetailRow(label: 'Group', value: profile.group),
                        _DetailRow(
                          label: 'Screen',
                          value:
                              '${profile.desktopWidth}×${profile.desktopHeight}',
                        ),
                        _DetailRow(label: 'Status', value: profile.status.name),
                        if (profile.sourceRdpFilePath != null)
                          _DetailRow(
                            label: 'From',
                            value: profile.sourceRdpFilePath!,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: Text(label, style: portixMuted(12))),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
