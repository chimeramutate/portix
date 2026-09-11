part of '../../page/sftp_workspace_page.dart';

class _FilePane extends StatelessWidget {
  const _FilePane({
    required this.title,
    required this.path,
    required this.items,
    required this.countLabel,
    required this.onTransferDropped,
    required this.onFileAction,
    required this.onPathSubmitted,
    required this.onOpenFolder,
    required this.selectedPaths,
    required this.onItemSelected,
    required this.selectedTransferEntries,
    this.footerLeft,
    this.footerRight,
    this.loading = false,
    this.error,
    this.isRemote = false,
    this.showActions = true,
    this.showPathBar = true,
    this.contentOverride,
    this.onCreateFileRequested,
    this.onCreateFolderRequested,
    this.onRefreshRequested,
    this.inlineCreateKind,
    this.inlineCreateController,
    this.inlineCreateFocusNode,
    this.onInlineCreateSubmit,
    this.onInlineCreateCancel,
    this.inlineRenameFile,
    this.inlineRenameController,
    this.inlineRenameFocusNode,
    this.onInlineRenameSubmit,
    this.onInlineRenameCancel,
    this.findQuery = '',
    this.findBase = '/',
    this.findActive = false,
    this.findSearching = false,
    this.findError,
    this.onFindSubmitted,
    this.onFindCleared,
    this.statusTitle,
    this.statusMessage,
    this.remoteStatus,
    this.profileName,
    this.remoteOsIconAsset,
    this.inputForm,
    this.showPasswordStep = false,
    this.showSteps = true,
    this.onTitleTap,
  });

  final String title;
  final String path;
  final List<SftpFileEntry> items;
  final String countLabel;
  final String? footerLeft;
  final String? footerRight;
  final bool loading;
  final String? error;
  final bool isRemote;
  final bool showActions;
  final bool showPathBar;
  final Widget? contentOverride;
  final VoidCallback? onCreateFileRequested;
  final VoidCallback? onCreateFolderRequested;
  final VoidCallback? onRefreshRequested;
  final _SftpInlineCreateKind? inlineCreateKind;
  final TextEditingController? inlineCreateController;
  final FocusNode? inlineCreateFocusNode;
  final Future<void> Function()? onInlineCreateSubmit;
  final VoidCallback? onInlineCreateCancel;
  final SftpFileEntry? inlineRenameFile;
  final TextEditingController? inlineRenameController;
  final FocusNode? inlineRenameFocusNode;
  final Future<void> Function()? onInlineRenameSubmit;
  final VoidCallback? onInlineRenameCancel;
  final String findQuery;
  final String findBase;
  final bool findActive;
  final bool findSearching;
  final String? findError;
  final ValueChanged<String>? onFindSubmitted;
  final VoidCallback? onFindCleared;
  final String? statusTitle;
  final String? statusMessage;
  final String? remoteStatus;
  final String? profileName;
  final String? remoteOsIconAsset;
  final Widget? inputForm;
  final bool showPasswordStep;
  final bool showSteps;
  final VoidCallback? onTitleTap;
  final ValueChanged<SftpFileTransfer> onTransferDropped;
  final void Function(_FileAction action, SftpFileEntry file) onFileAction;
  final ValueChanged<String> onPathSubmitted;
  final Set<String> selectedPaths;
  final void Function(SftpFileEntry file, int index, List<SftpFileEntry> rows)
  onItemSelected;
  final List<SftpFileEntry> Function(SftpFileEntry file)
  selectedTransferEntries;
  // final ValueChanged<String> onOpenFolder;
  final void Function(SftpFileEntry data) onOpenFolder;
  @override
  Widget build(BuildContext context) {
    return DragTarget<SftpFileTransfer>(
      onWillAcceptWithDetails: (details) => details.data.fromRemote != isRemote,
      onAcceptWithDetails: (details) => onTransferDropped(details.data),
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;
        return AppPanel(
          padding: const EdgeInsets.all(14),
          borderColor: isDropTarget ? AppColors.cyan : AppColors.border,
          color: isDropTarget
              ? AppColors.surfaceCard.withValues(alpha: .78)
              : AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MouseRegion(
                cursor: onTitleTap == null
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTitleTap,
                  behavior: HitTestBehavior.translucent,
                  child: Row(
                    children: [
                      if (isRemote &&
                          (remoteOsIconAsset ?? '').trim().isNotEmpty)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: SvgPicture.asset(
                            remoteOsIconAsset!,
                            fit: BoxFit.contain,
                          ),
                        )
                      else
                        Icon(
                          isRemote
                              ? Icons.dns_outlined
                              : Icons.computer_rounded,
                          color: isRemote ? AppColors.green : AppColors.cyan,
                          size: 18,
                        ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: portixTitle(16),
                        ),
                      ),
                      AppPill(
                        label: countLabel,
                        color: isRemote ? AppColors.green : AppColors.cyan,
                      ),
                    ],
                  ),
                ),
              ),
              // Show skeleton placeholders while loading instead of
              // hiding the path bar, actions, and find bar entirely.
              // This keeps the layout structure visible so the user
              // sees the frame of the UI rather than a bare step
              // indicator with empty space around it.
              if (showSteps) ...[
                const SizedBox(height: 12),
              ] else ...[
                if (showPathBar)
                  Skeletonizer(
                    enabled: loading,
                    child: _PathBar(path: path, onSubmitted: onPathSubmitted),
                  ),
                if (showActions) ...[
                  const SizedBox(height: 12),
                  Skeletonizer(
                    enabled: loading,
                    child: _PaneActions(
                      isRemote: isRemote,
                      onCreateFileRequested: onCreateFileRequested,
                      onCreateFolderRequested: onCreateFolderRequested,
                      onRefreshRequested: onRefreshRequested,
                    ),
                  ),
                ],
                if (onFindSubmitted != null) ...[
                  const SizedBox(height: 10),
                  Skeletonizer(
                    enabled: loading,
                    child: _RemoteFindBar(
                      query: findQuery,
                      base: findBase,
                      active: findActive,
                      searching: findSearching,
                      error: findError,
                      remote: isRemote,
                      onSubmitted: onFindSubmitted!,
                      onCleared: onFindCleared,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: showSteps
                        ? AppColors.surfaceDark
                        : AppColors.surfaceDark.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDropTarget ? AppColors.cyan : AppColors.border,
                    ),
                  ),
                  child: contentOverride != null
                      ? contentOverride
                      : loading
                      ? showSteps
                            ? _PaneStatus(
                                icon: isRemote
                                    ? Icons.dns_outlined
                                    : Icons.folder_open_rounded,
                                loading: true,
                                loadingSteps: isRemote
                                    ? _buildConnectionSteps(
                                        titles: showPasswordStep
                                            ? [
                                                profileName ?? '',
                                                'Loading',
                                                'Connecting...',
                                                'Connected',
                                              ]
                                            : [
                                                profileName ?? '',
                                                'Connecting...',
                                                'Connected',
                                              ],
                                        showPasswordStep: showPasswordStep,
                                        osIconAsset: remoteOsIconAsset,
                                      )
                                    : null,
                                currentStep: isRemote
                                    ? _remoteLoadStep(
                                        remoteStatus,
                                        showPasswordStep: showPasswordStep,
                                      )
                                    : null,
                                title:
                                    statusTitle ??
                                    (isRemote
                                        ? 'Connecting to server'
                                        : 'Loading local folder'),
                                message:
                                    statusMessage ??
                                    _defaultStatusMessage(
                                      isRemote,
                                      remoteStatus,
                                    ),
                                inputForm: inputForm,
                              )
                            : Skeletonizer(
                                child: _SkeletonFileTable(isRemote: isRemote),
                              )
                      : error != null
                      ? _PaneStatus(
                          icon: Icons.error_outline_rounded,
                          title:
                              statusTitle ??
                              (isRemote
                                  ? 'Remote unavailable'
                                  : 'Local folder unavailable'),
                          message: statusMessage ?? error!,
                        )
                      : Column(
                          children: [
                            _TableHeader(isRemote: isRemote),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final createActive =
                                      inlineCreateKind != null &&
                                      inlineCreateController != null &&
                                      inlineCreateFocusNode != null &&
                                      onInlineCreateSubmit != null &&
                                      onInlineCreateCancel != null;
                                  final renameActive =
                                      inlineRenameFile != null &&
                                      inlineRenameController != null &&
                                      inlineRenameFocusNode != null &&
                                      onInlineRenameSubmit != null &&
                                      onInlineRenameCancel != null;
                                  return ListView.builder(
                                    itemCount:
                                        items.length + (createActive ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (createActive && index == 0) {
                                        return _SftpInlineCreateItem(
                                          kind: inlineCreateKind!,
                                          controller: inlineCreateController!,
                                          focusNode: inlineCreateFocusNode!,
                                          onSubmit: onInlineCreateSubmit!,
                                          onCancel: onInlineCreateCancel!,
                                        );
                                      }
                                      final item =
                                          items[index - (createActive ? 1 : 0)];
                                      final itemIndex =
                                          index - (createActive ? 1 : 0);
                                      if (renameActive &&
                                          item.path == inlineRenameFile!.path) {
                                        return _SftpInlineRenameItem(
                                          file: item,
                                          controller: inlineRenameController!,
                                          focusNode: inlineRenameFocusNode!,
                                          onSubmit: onInlineRenameSubmit!,
                                          onCancel: onInlineRenameCancel!,
                                        );
                                      }
                                      return _FileRow(
                                        data: item,
                                        selected:
                                            item.path != null &&
                                            selectedPaths.contains(item.path),
                                        isRemote: isRemote,
                                        onOpenFolder: onOpenFolder,
                                        onAction: onFileAction,
                                        onSelected: () => onItemSelected(
                                          item,
                                          itemIndex,
                                          items,
                                        ),
                                        dragEntries: selectedTransferEntries(
                                          item,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            _PaneFooter(
                              left: footerLeft ?? '${items.length} items',
                              right: footerRight ?? '',
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Labels for each remote-load step. The first element ('Pick profile') is
/// replaced at runtime with the selected profile name.
const kRemoteLoadSteps = [
  'Pick profile',
  'Loading',
  'Connecting...',
  'Connected',
];

/// Maps a [remoteStatus] string to a step index for the loading indicator.
/// Returns -1 when the status doesn't correspond to an active step.
///
/// When [showPasswordStep] is true, a 4-step layout is used:
///   0 Pick profile → 1 Loading → 2 Connecting... → 3 Connected
/// When false, a 3-step layout is used:
///   0 Pick profile → 1 Connecting... → 2 Connected
int _remoteLoadStep(String? status, {bool showPasswordStep = true}) {
  if (showPasswordStep) {
    switch (status) {
      case 'authenticating':
        return 1; // Loading — waiting for inline password input
      case 'connecting':
        return 2; // Connecting... — SFTP channel being established
      case 'listing':
        return 2; // Connecting... — resolving path + listing directory
      case 'connected':
        return 3; // Connected — all done
      default:
        return -1;
    }
  }
  switch (status) {
    case 'connecting':
      return 1; // Connecting... — SFTP channel being established
    case 'listing':
      return 1; // Connecting... — resolving path + listing directory
    case 'connected':
      return 2; // Connected — all done
    default:
      return -1;
  }
}

/// Returns a human-readable status message for the given [remoteStatus].
/// Used as the default (sub-title) text inside [_PaneStatus] when the
/// parent does not supply its own [statusMessage].
String? _defaultStatusMessage(bool isRemote, String? remoteStatus) {
  if (!isRemote) return null; // local folders have no step-specific messages
  return switch (remoteStatus) {
    'authenticating' => 'Enter your password to continue',
    'connecting' => 'Establishing SFTP connection...',
    'listing' => 'Listing remote directory...',
    'connected' => 'Connected',
    'failed' => 'Connection failed',
    _ => null,
  };
}

/// Builds the list of [EasyStep] objects for the remote connection flow.
///
/// Each step gets a custom icon:
///   - Step 0: OS icon from the profile's [osIconAsset] (SVG image).
///   - Step 1 (4-step): lock icon (secure password input).
///   - Step 1 (3-step): cable icon (connecting).
///   - Step 2 (4-step): wifi icon (connecting).
///   - Step 2/3 (3-step/4-step): wifi tower icon (connected).
///
/// All steps receive a check-mark [finishIcon] so EasyStepper renders ✓
/// for completed steps. When [showLoadingAnimation] is enabled by the
/// parent, the active step automatically shows a Lottie loading animation.
List<EasyStep> _buildConnectionSteps({
  required List<String> titles,
  required bool showPasswordStep,
  required String? osIconAsset,
}) {
  final asset = (osIconAsset ?? '').trim();
  final osIconWidget = asset.isNotEmpty
      ? SizedBox(
          width: 28,
          height: 28,
          child: SvgPicture.asset(asset, fit: BoxFit.contain),
        )
      : Icon(Icons.dns_outlined, size: 28);

  final finishIcon = Icon(Icons.check_circle_rounded, size: 18);

  return titles.asMap().entries.map((entry) {
    final idx = entry.key;
    final title = entry.value;

    if (idx == 0) {
      // Step 0: OS icon from asset (uses customStep because SvgPicture
      // is a Widget, not an IconData).
      return EasyStep(
        title: title,
        customStep: osIconWidget,
        finishIcon: finishIcon,
      );
    }

    // Steps 1+: Icon-based icons
    final IconData iconData;
    if (showPasswordStep) {
      // 4-step flow: 0 Profile → 1 Password → 2 Connecting → 3 Connected
      switch (idx) {
        case 1:
          iconData = Icons.lock_rounded; // secure password
        case 2:
          iconData = Icons.wifi_rounded; // connecting
        case 3:
          iconData = Icons.wifi_rounded; // connected
        default:
          iconData = Icons.circle_outlined;
      }
    } else {
      // 3-step flow: 0 Profile → 1 Connecting → 2 Connected
      switch (idx) {
        case 1:
          iconData = Icons.cable_rounded; // connecting
        case 2:
          iconData = Icons.wifi_rounded; // connected
        default:
          iconData = Icons.circle_outlined;
      }
    }

    return EasyStep(
      title: title,
      icon: Icon(iconData, size: 16),
      finishIcon: finishIcon,
    );
  }).toList();
}

class _PaneStatus extends StatelessWidget {
  const _PaneStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.loadingSteps,
    this.currentStep,
    this.inputForm,
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool loading;

  /// When non-null, shows a step-based loading indicator with the loading
  /// animation integrated into the step line (at the active step position)
  /// rather than above the steps.
  final List<EasyStep>? loadingSteps;
  final int? currentStep;

  /// Optional inline input widget (e.g. a password form) shown below the
  /// step indicator when [loading] is true.
  final Widget? inputForm;

  @override
  Widget build(BuildContext context) {
    final stepCount = loadingSteps?.length ?? 0;
    final stepValue = currentStep ?? 0;
    final isLastStep = stepCount > 0 && stepValue >= stepCount - 1;
    final effectiveActiveStep = isLastStep ? stepCount : stepValue;
    final reachedSteps = isLastStep && stepCount > 0
        ? Set<int>.from(List.generate(stepCount, (i) => i))
        : null;

    return Center(
      child: SizedBox(
        width: 640,
        child: AppPanel(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(16),
          color: AppColors.surfaceDark,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Loading: EasyStepper step indicator with integrated loading
              // animation in the active step, or plain loading dots for
              // non-remote loading.
              if (loading)
                loadingSteps != null
                    ? EasyStepper(
                        activeStep: effectiveActiveStep,
                        reachedSteps: reachedSteps,
                        steps: loadingSteps!,
                        direction: Axis.horizontal,
                        enableStepTapping: false,
                        disableScroll: true,
                        showTitle: true,
                        showLoadingAnimation: !isLastStep,
                        stepRadius: 32,
                        internalPadding: 12,
                        borderThickness: 0,
                        showStepBorder: false,
                        activeStepBackgroundColor: AppColors.surfaceDark,
                        finishedStepBackgroundColor: Colors.transparent,
                        unreachedStepBackgroundColor: Colors.transparent,
                        unreachedStepBorderColor: AppColors.border,
                        activeStepBorderColor: AppColors.cyan,
                        finishedStepBorderColor: AppColors.cyan,
                        finishedStepIconColor: AppColors.cyan,
                        unreachedStepIconColor: AppColors.muted,
                        activeStepIconColor: AppColors.cyan,
                        unreachedStepTextColor: AppColors.muted,
                        activeStepTextColor: AppColors.cyan,
                        finishedStepTextColor: AppColors.cyan,
                        lineStyle: LineStyle(
                          lineLength: 40,
                          lineThickness: 1,
                          defaultLineColor: AppColors.border,
                          activeLineColor: AppColors.cyan,
                          finishedLineColor: AppColors.cyan,
                          unreachedLineColor: AppColors.border,
                          lineType: LineType.normal,
                        ),
                        maxTitleLines: 1,
                      )
                    : LoadingAnimationWidget.fourRotatingDots(
                        color: AppColors.cyan,
                        size: 28,
                      )
              else
                Icon(icon, color: AppColors.muted, size: 28),
              // Title + message (message only if non-empty)
              if (loading || loadingSteps == null)
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: portixTitle(14),
                ),
              if (message?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: portixMuted(12),
                ),
              ],
              // Inline input form (e.g. password field) shown only during
              // the 'authenticating' loading step (step 1 of the 4-step
              // remote flow). After the password is submitted and the
              // status advances to 'connecting' (step 2), the form is hidden.
              if (loading && inputForm != null && currentStep == 1) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: inputForm!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline password input form shown inside [_PaneStatus] when the remote
/// status is 'authenticating'. Collects a password that cannot be found in
/// local secure storage, then submits it via [onSubmit].
class _SftpSecurePasswordInput extends StatefulWidget {
  const _SftpSecurePasswordInput({
    required this.onSubmit,
    this.errorText,
    this.profile,
  });

  final ValueChanged<String> onSubmit;
  final String? errorText;
  final SshProfile? profile;

  @override
  State<_SftpSecurePasswordInput> createState() =>
      _SftpSecurePasswordInputState();
}

class _SftpSecurePasswordInputState extends State<_SftpSecurePasswordInput> {
  final _controller = TextEditingController();
  String? _fieldError;

  void _submit() {
    final password = _controller.text.trim();
    if (password.isEmpty) {
      setState(() => _fieldError = 'Password is required');
      return;
    }
    _fieldError = null;
    widget.onSubmit(password);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          profile != null
              ? 'No secure password for "${profile.name}". '
                    'Enter password to connect.'
              : 'Secure password not found on this device.',
          style: portixTitle(14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'The password will be saved to local secure storage.',
          style: portixMuted(11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: TextFormField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Enter SFTP password',
              errorText: _fieldError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        if (widget.errorText?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: portixMuted(11).copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: Text('Connect', style: portixTitle(13)),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _PathBar extends StatefulWidget {
  const _PathBar({required this.path, required this.onSubmitted});
  final String path;
  final ValueChanged<String> onSubmitted;

  @override
  State<_PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<_PathBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.path,
  );

  @override
  void didUpdateWidget(covariant _PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller.text = widget.path;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, color: AppColors.muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: widget.onSubmitted,
              style: portixTitle(12),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Open path',
            onPressed: () => widget.onSubmitted(_controller.text),
            icon: const Icon(
              Icons.keyboard_return_rounded,
              color: AppColors.muted,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteFindBar extends StatefulWidget {
  const _RemoteFindBar({
    required this.query,
    required this.base,
    required this.active,
    required this.searching,
    required this.remote,
    required this.onSubmitted,
    this.error,
    this.onCleared,
  });

  final String query;
  final String base;
  final bool active;
  final bool searching;
  final bool remote;
  final String? error;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onCleared;

  @override
  State<_RemoteFindBar> createState() => _RemoteFindBarState();
}

class _RemoteFindBarState extends State<_RemoteFindBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(covariant _RemoteFindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _controller.text != widget.query) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.active ? AppColors.cyan : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          widget.searching
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.search_rounded,
                  color: widget.error == null
                      ? AppColors.cyan
                      : AppColors.danger,
                  size: 17,
                ),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: widget.onSubmitted,
              style: portixTitle(12),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                hintText:
                    widget.error ??
                    (widget.remote
                        ? 'Find remote file or folder'
                        : 'Find local file or folder'),
                hintStyle: portixMuted(12).copyWith(
                  color: widget.error == null
                      ? AppColors.muted
                      : AppColors.danger,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (widget.active || widget.error != null)
            IconButton(
              tooltip: widget.searching ? 'Cancel find' : 'Clear find',
              onPressed: widget.onCleared,
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.muted,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}

class _PaneActions extends StatelessWidget {
  const _PaneActions({
    required this.isRemote,
    this.onCreateFileRequested,
    this.onCreateFolderRequested,
    this.onRefreshRequested,
  });

  final bool isRemote;
  final VoidCallback? onCreateFileRequested;
  final VoidCallback? onCreateFolderRequested;
  final VoidCallback? onRefreshRequested;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.note_add_outlined, 'New file', onCreateFileRequested),
      (Icons.create_new_folder_outlined, 'New folder', onCreateFolderRequested),
      (Icons.refresh_rounded, 'Reload', onRefreshRequested),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return Tooltip(
            message: action.$2,
            child: SizedBox.square(
              dimension: 34,
              child: OutlinedButton(
                onPressed: action.$3,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: AppColors.text,
                  side: BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Icon(action.$1, size: 16),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SftpInlineCreateItem extends StatelessWidget {
  const _SftpInlineCreateItem({
    required this.kind,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
  });

  final _SftpInlineCreateKind kind;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isFolder = kind == _SftpInlineCreateKind.folder;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: .58),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: .9),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            color: isFolder ? AppColors.amber : AppColors.muted,
            size: 17,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  onCancel();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                onSubmitted: (_) => unawaited(onSubmit()),
                style: portixTitle(12),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  hintText: isFolder ? 'New folder name' : 'New file name',
                  hintStyle: portixMuted(12),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.muted,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _SftpInlineRenameItem extends StatelessWidget {
  const _SftpInlineRenameItem({
    required this.file,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
  });

  final SftpFileEntry file;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF143B63),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryBlue),
      ),
      child: Row(
        children: [
          Icon(
            file.folder
                ? Icons.folder_outlined
                : Icons.insert_drive_file_outlined,
            color: file.folder ? AppColors.amber : AppColors.muted,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  onCancel();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                onSubmitted: (_) => unawaited(onSubmit()),
                style: portixTitle(12),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  hintText: file.folder ? 'Rename folder' : 'Rename file',
                  hintStyle: portixMuted(12),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Cancel rename',
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.muted,
              size: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.isRemote});
  final bool isRemote;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Name', style: portixLabel(12))),
          Expanded(
            flex: 2,
            child: Text(isRemote ? 'Type' : 'Size', style: portixLabel(12)),
          ),
          Expanded(
            flex: 2,
            child: Text(isRemote ? 'Size' : 'Modified', style: portixLabel(12)),
          ),
          Expanded(
            flex: 2,
            child: Text(isRemote ? 'Updated' : '', style: portixLabel(12)),
          ),
        ],
      ),
    );
  }
}

/// Skeleton placeholder for the file table (header + rows + footer)
/// shown beneath the step indicator while [loading] is true.
/// Wrapped in [Skeletonizer] for the shimmer animation.
class _SkeletonFileTable extends StatelessWidget {
  const _SkeletonFileTable({required this.isRemote});
  final bool isRemote;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header — mirrors _TableHeader layout
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(flex: 5, child: Bone(height: 12)),
              const SizedBox(width: 8),
              if (isRemote) ...[
                Expanded(flex: 2, child: Bone(height: 12)),
                const SizedBox(width: 8),
              ],
              Expanded(flex: 2, child: Bone(height: 12)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: Bone(height: 12)),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.separated(
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(height: 1),
            itemBuilder: (_, index) => _SkeletonFileRow(isRemote: isRemote),
          ),
        ),
        // Footer — mirrors _PaneFooter layout
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Bone(width: 70, height: 12),
              const Spacer(),
              Bone(width: 40, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonFileRow extends StatelessWidget {
  const _SkeletonFileRow({required this.isRemote});
  final bool isRemote;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: .65)),
        ),
      ),
      child: Row(
        children: [
          Bone.icon(size: 18),
          const SizedBox(width: 9),
          // Name column (flex 5)
          Expanded(flex: 5, child: Bone(height: 14)),
          const SizedBox(width: 8),
          // Type / Size column (flex 2)
          if (isRemote) ...[
            Expanded(flex: 2, child: Bone(height: 14)),
            const SizedBox(width: 8),
          ],
          // Size / Modified column (flex 2)
          Expanded(flex: 2, child: Bone(height: 14)),
          const SizedBox(width: 8),
          // Updated / empty column (flex 2)
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isRemote) Bone(width: 50, height: 14),
                const SizedBox(width: 4),
                Bone.icon(size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
