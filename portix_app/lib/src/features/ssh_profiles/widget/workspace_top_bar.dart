import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/features/sftp/bloc/index.dart';
import 'package:window_manager/window_manager.dart';

import '../bloc/index.dart';

const workspaceTitleBarHeight = 38.0;

/// Room for the macOS traffic lights, which stay native over the hidden
/// title bar.
const _macTrafficLightInset = 78.0;

/// The app header merged into the window title bar: drag to move, double-click
/// to maximize, window buttons drawn here on Linux and Windows.
class WorkspaceTopBar extends StatelessWidget {
  const WorkspaceTopBar({required this.state, this.platform, super.key});

  final SshWorkspaceState state;

  /// Overrides [defaultTargetPlatform] in tests.
  final TargetPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final target = platform ?? defaultTargetPlatform;
    final isMac = target == TargetPlatform.macOS;
    final desktop =
        isMac ||
        target == TargetPlatform.linux ||
        target == TargetPlatform.windows;
    final (center, actions) = switch (state.activeView) {
      WorkspaceView.form => (
        const _FormBreadcrumb(compact: false),
        <Widget>[
          AppPill(
            label: 'Unsaved draft',
            color: AppColors.amber,
            background: AppColors.amberTint,
          ),
          AppButton(
            icon: Icons.save_outlined,
            label: 'Save Profile',
            primary: true,
            onPressed: () =>
                context.read<SshWorkspaceBloc>().add(const ProfileSaved()),
          ),
        ],
      ),
      WorkspaceView.sftp => (const _SftpStatus(), const <Widget>[]),
      WorkspaceView.remoteFolder => (
        _Title(state.selectedProfile?.name ?? 'Terminal'),
        const <Widget>[],
      ),
      WorkspaceView.settings => (const _Title('Settings'), const <Widget>[]),
      WorkspaceView.rdp => (const _Title('Remote Desktop'), const <Widget>[]),
      _ => (_GallerySearch(state: state), const <Widget>[_NewProfileButton()]),
    };

    return Container(
      height: workspaceTitleBarHeight,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Stack(
        children: [
          // Empty parts of the bar fall through to this drag area.
          if (desktop)
            const Positioned.fill(
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
          Row(
            children: [
              SizedBox(width: isMac ? _macTrafficLightInset : 14),
              Expanded(child: Center(child: center)),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
              const SizedBox(width: 12),
              if (desktop && !isMac) const _CaptionButtons(),
            ],
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: portixTitle(13),
  );
}

class _GallerySearch extends StatefulWidget {
  const _GallerySearch({required this.state});
  final SshWorkspaceState state;

  @override
  State<_GallerySearch> createState() => _GallerySearchState();
}

class _GallerySearchState extends State<_GallerySearch> {
  late final TextEditingController _search = TextEditingController(
    text: widget.state.searchQuery,
  );
  final _searchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => showTutorialOnce(context, 'gallery', [
        (
          key: _NewProfileButton.tutorialKey,
          title: 'Create an SSH profile',
          body:
              'Click here to add a server: name, host, port, username, then a password or SSH key.',
        ),
        (
          key: _searchKey,
          title: 'Search profiles',
          body: 'Filter profiles by name, host, tag or group.',
        ),
      ]),
    );
  }

  @override
  void didUpdateWidget(covariant _GallerySearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_search.text != widget.state.searchQuery) {
      _search.text = widget.state.searchQuery;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: _searchKey,
      constraints: const BoxConstraints(maxWidth: 460),
      // expands: the field fills exactly 30px, so its outline never overflows.
      child: SizedBox(
        height: 30,
        child: TextField(
          controller: _search,
          expands: true,
          maxLines: null,
          // expands needs maxLines: null; keep the search a single line.
          inputFormatters: [FilteringTextInputFormatter.deny('\n')],
          onChanged: (value) =>
              context.read<SshWorkspaceBloc>().add(SearchChanged(value)),
          style: TextStyle(color: AppColors.text, fontSize: 13),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search profile, host, tag, or group',
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            hintStyle: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            // A 1px focus border: the 2px form default is too heavy in the bar.
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppColors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppColors.cyan),
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: AppColors.muted,
              size: 16,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 30,
              minHeight: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _NewProfileButton extends StatelessWidget {
  const _NewProfileButton();

  /// Anchors the gallery tutorial step.
  static final tutorialKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: tutorialKey,
      child: IconButton(
        tooltip: 'New SSH Profile',
        onPressed: () =>
            context.read<SshWorkspaceBloc>().add(const NewProfileRequested()),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        icon: Icon(Icons.add_rounded, size: 18, color: AppColors.text),
      ),
    );
  }
}

class _SftpStatus extends StatelessWidget {
  const _SftpStatus();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<SftpWorkspaceBloc>().state.selectedProfile;
    final hasSession = profile != null;
    return _ConnectionBadge(
      osIconAsset: profile?.osIconAsset,
      iconColor: hasSession ? AppColors.green : AppColors.muted,
      title: profile?.name ?? 'SFTP Workspace',
      trailing: AppPill(
        label: hasSession ? 'Ready' : 'No session',
        color: hasSession ? AppColors.green : AppColors.muted,
        background: hasSession ? AppColors.greenTint : AppColors.surface,
      ),
    );
  }
}

/// Minimize, maximize/restore and close for platforms without native
/// buttons over the hidden title bar.
class _CaptionButtons extends StatefulWidget {
  const _CaptionButtons();

  @override
  State<_CaptionButtons> createState() => _CaptionButtonsState();
}

class _CaptionButtonsState extends State<_CaptionButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then(
      (value) {
        if (mounted) setState(() => _maximized = value);
      },
      onError: (Object _) {}, // no native window (tests): keep "maximize"
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowCaptionButton.minimize(
          brightness: brightness,
          onPressed: windowManager.minimize,
        ),
        _maximized
            ? WindowCaptionButton.unmaximize(
                brightness: brightness,
                onPressed: windowManager.unmaximize,
              )
            : WindowCaptionButton.maximize(
                brightness: brightness,
                onPressed: windowManager.maximize,
              ),
        WindowCaptionButton.close(
          brightness: brightness,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _FormBreadcrumb extends StatelessWidget {
  const _FormBreadcrumb({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.format_list_bulleted_rounded,
            color: AppColors.muted,
            size: 16,
          ),
          const SizedBox(width: 10),
          if (!compact)
            Flexible(
              child: Text(
                'List SSH Profiles',
                overflow: TextOverflow.ellipsis,
                style: portixMuted().copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          if (!compact) ...[
            const SizedBox(width: 12),
            Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              'New SSH Profile',
              overflow: TextOverflow.ellipsis,
              style: portixTitle(13),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({
    this.osIconAsset,
    required this.title,
    this.trailing,
    Color? iconColor,
  }) : _iconColor = iconColor;

  /// Path to an OS-specific SVG icon asset (e.g. 'assets/icons/os/ubuntu-linux.svg').
  /// When non-empty, the badge renders this SVG with its own colors.
  /// Falls back to [Icons.dns_outlined] when empty.
  final String? osIconAsset;
  final String title;
  final Widget? trailing;
  final Color? _iconColor;
  Color get iconColor => _iconColor ?? AppColors.green;

  @override
  Widget build(BuildContext context) {
    final asset = (osIconAsset ?? '').trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (asset.isNotEmpty)
              SizedBox(
                width: 16,
                height: 16,
                child: SvgPicture.asset(asset, fit: BoxFit.contain),
              )
            else
              Icon(Icons.dns_outlined, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(12),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}
