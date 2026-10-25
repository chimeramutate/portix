import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'form_steps.dart';
import 'profile_preview.dart';
import 'ssh_key_manager_dialog.dart';

class ProfileFormView extends StatefulWidget {
  const ProfileFormView({super.key});

  @override
  State<ProfileFormView> createState() => _ProfileFormViewState();
}

class _ProfileFormViewState extends State<ProfileFormView> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _group = TextEditingController(text: 'Production');
  final _tags = TextEditingController();
  final _credential = TextEditingController();
  final _startup = TextEditingController();
  final _fontSize = TextEditingController(text: '14');
  String? _syncedId;
  AuthMethod? _syncedAuthMethod;

  // Advanced section toggle – collapsed by default
  bool _advancedExpanded = false;

  final _identityKey = GlobalKey();
  final _endpointKey = GlobalKey();
  final _authKey = GlobalKey();
  final _advancedKey = GlobalKey();
  final _saveKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => showTutorialOnce(context, 'new_profile', [
        (
          key: _identityKey,
          title: '1. Profile identity',
          body:
              'Enter a profile name and group. Tags and color are optional and help with filtering.',
        ),
        (
          key: _endpointKey,
          title: '2. Endpoint',
          body:
              'Enter the host or IP, port (default 22) and the server username.',
        ),
        (
          key: _authKey,
          title: '3. Authentication',
          body:
              'Choose Password or SSH key. Passwords are kept in the system credential store.',
        ),
        (
          key: _advancedKey,
          title: 'Advanced (optional)',
          body:
              'A startup command to run at login, and the terminal font size.',
        ),
        (
          key: _saveKey,
          title: '4. Save',
          body:
              'Click Save Profile. The profile appears in the gallery, ready to open over SSH or SFTP.',
        ),
      ]),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _host,
      _port,
      _username,
      _group,
      _tags,
      _credential,
      _startup,
      _fontSize,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _sync(SshProfile? profile) {
    if (profile == null) return;
    if (_syncedId == profile.id && _syncedAuthMethod == profile.authMethod) {
      return;
    }
    final isSameProfile = _syncedId == profile.id;
    _syncedId = profile.id;
    _syncedAuthMethod = profile.authMethod;
    if (!isSameProfile) {
      _name.text = profile.name;
      _host.text = profile.host;
      _port.text = '${profile.port}';
      _username.text = profile.username;
      _group.text = profile.group;
      _tags.text = profile.tags.join(', ');
      _startup.text = profile.startupCommand;
      _fontSize.text = '${profile.terminalFontSize}';
    }
    _credential.text = profile.credentialLabel;
  }

  void _changed(BuildContext context) {
    context.read<SshWorkspaceBloc>().add(
      ProfileFormChanged(
        name: _name.text,
        host: _host.text,
        port: _port.text,
        username: _username.text,
        group: _group.text,
        tags: _tags.text,
        credentialLabel: _credential.text,
        defaultPath: '',
        startupCommand: _startup.text,
        terminalFontSize: _fontSize.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshWorkspaceBloc, SshWorkspaceState>(
      builder: (context, state) {
        _sync(state.editingProfile);
        final profile = state.editingProfile;
        final groupOptions =
            state.profiles
                .map((p) => p.group)
                .where((g) => g.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        final tagOptions =
            state.profiles
                .expand((p) => p.tags)
                .where((t) => t.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort();

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenSize = MediaQuery.sizeOf(context);
            final availableWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : screenSize.width;
            final availableHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : screenSize.height;
            final compact = availableWidth < 920;
            final twoColumn = availableWidth >= 1080;
            final showSidePanel =
                availableWidth >= 1320 && state.isProfileFormComplete;
            final contentMaxWidth = showSidePanel ? 920.0 : 1080.0;

            final identitySection = _FormSection(
              key: _identityKey,
              icon: Icons.badge_outlined,
              title: 'Identity',
              subtitle: 'Name and group are required. Tags help filtering.',
              children: [
                AppTextField(
                  controller: _name,
                  label: 'Profile name',
                  icon: Icons.dns_outlined,
                  onChanged: (_) => _changed(context),
                ),
                _AutocompleteTextField(
                  controller: _group,
                  label: 'Group',
                  icon: Icons.layers_outlined,
                  options: groupOptions,
                  onChanged: (_) => _changed(context),
                ),
                _TagSelector(
                  controller: _tags,
                  options: tagOptions,
                  onChanged: () => _changed(context),
                ),
                _ProfileColorPicker(
                  color: profile?.color ?? ProfileColor.green,
                ),
              ],
            );

            // Authentication is now embedded inside the endpoint section.
            final endpointSection = _FormSection(
              key: _endpointKey,
              icon: Icons.lan_outlined,
              title: 'Connection',
              subtitle: 'Where to connect and how to sign in.',
              children: [
                _FullWidth(
                  child: Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _host,
                          label: 'Host / IP',
                          hint: 'example.com or 10.0.0.5',
                          icon: Icons.language_rounded,
                          onChanged: (_) => _changed(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 96,
                        child: AppTextField(
                          controller: _port,
                          label: 'Port',
                          hint: '22',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(5),
                          ],
                          onChanged: (_) => _changed(context),
                        ),
                      ),
                    ],
                  ),
                ),
                _FullWidth(
                  child: AppTextField(
                    controller: _username,
                    label: 'Username',
                    hint: 'root',
                    icon: Icons.person_outline,
                    onChanged: (_) => _changed(context),
                  ),
                ),
                // Auth inline – full-width inside the endpoint card
                _AuthSegments(key: _authKey, profile: profile),
                if (profile?.authMethod == AuthMethod.password)
                  _FullWidth(
                    child: AppTextField(
                      controller: _credential,
                      label: 'Password',
                      icon: Icons.lock_outline_rounded,
                      obscureText: true,
                      onChanged: (_) => _changed(context),
                    ),
                  )
                else ...[
                  _FullWidth(
                    child: AppTextField(
                      controller: _credential,
                      label: 'SSH key path',
                      hint: 'Empty uses ssh-agent',
                      icon: Icons.key_rounded,
                      onChanged: (_) => _changed(context),
                    ),
                  ),
                  _UploadBox(
                    onTap: () async {
                      final path = await showSshKeyManager(context);
                      if (path == null || !context.mounted) return;
                      _credential.text = path;
                      _changed(context);
                    },
                  ),
                ],
              ],
            );

            // Advanced section with ^ toggle header
            final advancedSection = _AdvancedSection(
              key: _advancedKey,
              expanded: _advancedExpanded,
              onToggle: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              children: [
                AppTextField(
                  controller: _startup,
                  label: 'Startup command',
                  hint: 'e.g. cd /var/www && ls',
                  icon: Icons.terminal_rounded,
                  onChanged: (_) => _changed(context),
                ),
                AppTextField(
                  controller: _fontSize,
                  label: 'Terminal font size',
                  icon: Icons.text_fields_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  onChanged: (_) => _changed(context),
                ),
                _JumpHostPicker(
                  selectedId: profile?.jumpProfileId ?? '',
                  candidates: [
                    for (final other in state.profiles)
                      if (other.id != profile?.id) other,
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: profile?.forwardAgent ?? false,
                  onChanged: (value) => context.read<SshWorkspaceBloc>().add(
                    ForwardAgentChanged(value),
                  ),
                  secondary: const Icon(Icons.vpn_key_outlined),
                  title: const Text('Forward SSH agent'),
                  subtitle: Text(
                    'Like ssh -A: lets this server use your local keys '
                    '(git, ssh to other hosts). Only for servers you trust.',
                    style: portixMuted(11),
                  ),
                ),
              ],
            );

            final form = SizedBox(
              height: availableHeight,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 20,
                  compact ? 14 : 20,
                  compact ? 14 : 16,
                  28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CompactFormHeader(state: state),
                    const SizedBox(height: 14),
                    if (!showSidePanel && state.isProfileFormComplete) ...[
                      ProfilePreview(state: state),
                      const SizedBox(height: 14),
                    ],
                    if (compact) ...[
                      AppPanel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: FormSteps(state: state),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (twoColumn) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identitySection),
                          const SizedBox(width: 14),
                          Expanded(child: endpointSection),
                        ],
                      ),
                    ] else ...[
                      identitySection,
                      endpointSection,
                    ],
                    advancedSection,
                    // Footer: hint left, actions right.
                    AppPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              compact
                                  ? 'Check before saving.'
                                  : 'Check the host, port, username and authentication before saving.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _subtitleStyle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          AppButton(
                            icon: Icons.close_rounded,
                            label: 'Cancel',
                            onPressed: () =>
                                context.read<SshWorkspaceBloc>().add(
                                  const NavigationChanged(
                                    WorkspaceView.gallery,
                                  ),
                                ),
                          ),
                          const SizedBox(width: 8),
                          AppButton(
                            key: _saveKey,
                            icon: Icons.save_outlined,
                            label: compact ? 'Save' : 'Save Profile',
                            primary: true,
                            onPressed: () => context
                                .read<SshWorkspaceBloc>()
                                .add(const ProfileSaved()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            return SizedBox(
              width: availableWidth,
              height: availableHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Form – aligned to left (near the nav sidebar), not centred
                  Expanded(
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMaxWidth),
                        child: form,
                      ),
                    ),
                  ),
                  if (showSidePanel)
                    SizedBox(
                      width: 320,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: _AnimatedSidePanel(state: state),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// Side panel

class _AnimatedSidePanel extends StatelessWidget {
  const _AnimatedSidePanel({required this.state});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: state.isProfileFormComplete
          ? SingleChildScrollView(
              key: const ValueKey('complete-side-panel'),
              padding: const EdgeInsets.fromLTRB(0, 20, 20, 24),
              child: Align(
                alignment: Alignment.topLeft,
                child: ProfilePreview(state: state),
              ),
            )
          : const SizedBox(key: ValueKey('empty-side-panel')),
    );
  }
}

// Compact header with step pills

class _CompactFormHeader extends StatelessWidget {
  const _CompactFormHeader({required this.state});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        label: 'Identity',
        done: state.isIdentityComplete,
        active: !state.isIdentityComplete,
      ),
      (
        label: 'Endpoint',
        done: state.isEndpointComplete,
        active: state.isIdentityComplete && !state.isEndpointComplete,
      ),
      (
        label: 'Auth',
        done: state.isAuthComplete,
        active: state.isEndpointComplete && !state.isAuthComplete,
      ),
    ];
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              SizedBox(
                width: narrow ? constraints.maxWidth : 330,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SSH Profile', style: _titleStyle),
                    const SizedBox(height: 2),
                    Text(
                      'Fill in the required fields. Advanced settings can stay at their defaults.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _subtitleStyle,
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final step in steps)
                    AppPill(
                      label: step.label,
                      color: step.done
                          ? AppColors.green
                          : step.active
                          ? AppColors.amber
                          : AppColors.muted,
                      icon: step.done
                          ? Icons.check_rounded
                          : Icons.circle_rounded,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// Form section card

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(icon: icon, title: title, subtitle: subtitle),
          const SizedBox(height: 16),
          Divider(height: 1, color: AppColors.border.withValues(alpha: .6)),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth > 640;
              return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: children.map((child) {
                  final fullWidth =
                      child is _FullWidth ||
                      child is _UploadBox ||
                      child is _AuthSegments ||
                      child is _TagSelector;
                  return SizedBox(
                    width: fullWidth || !twoColumns
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2,
                    child: child,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Marks a section child that spans the whole row.
class _FullWidth extends StatelessWidget {
  const _FullWidth({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Icon badge, title and one-line description of a form card.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _titleStyle,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _subtitleStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Label above a custom field, matching [AppTextField]'s label.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.icon, this.label, {this.trailing});

  final IconData icon;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appFieldLabelStyle(),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Text(
              trailing!,
              style: appFieldLabelStyle().copyWith(
                fontWeight: FontWeight.w400,
                color: AppColors.muted.withValues(alpha: .7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

TextStyle get _titleStyle =>
    TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w500);

TextStyle get _subtitleStyle => TextStyle(
  color: AppColors.muted,
  fontSize: 12,
  fontWeight: FontWeight.w500,
);

// Advanced section with ^ toggle

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.expanded,
    required this.onToggle,
    required this.children,
    super.key,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Expanded(
                    child: _SectionHeader(
                      icon: Icons.tune_rounded,
                      title: 'Advanced',
                      subtitle:
                          'Optional: startup command, font size and jump host.',
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: expanded ? 0.5 : 0.0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.muted,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            firstCurve: Curves.easeOutCubic,
            secondCurve: Curves.easeInCubic,
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth > 640;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: children.map((child) {
                      return SizedBox(
                        width: twoColumns
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth,
                        child: child,
                      );
                    }).toList(),
                  );
                },
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// Autocomplete text field

class _AutocompleteTextField extends StatefulWidget {
  const _AutocompleteTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.options,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  State<_AutocompleteTextField> createState() => _AutocompleteTextFieldState();
}

class _AutocompleteTextFieldState extends State<_AutocompleteTextField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return widget.options;
        return widget.options.where(
          (option) => option.toLowerCase().contains(query),
        );
      },
      onSelected: (value) {
        widget.controller.text = value;
        widget.onChanged(value);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel(widget.icon, widget.label),
            SizedBox(
              height: 38,
              child: TextField(
                controller: textController,
                focusNode: focusNode,
                onChanged: widget.onChanged,
                style: appFieldTextStyle(),
                decoration: InputDecoration(
                  hintText: 'Pick or type a group',
                  suffixIcon: Icon(
                    Icons.unfold_more_rounded,
                    color: AppColors.muted,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      optionsViewBuilder: (context, onSelected, values) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: AppPanel(
              fillWidth: false,
              padding: const EdgeInsets.all(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 180,
                  maxWidth: 360,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final value in values)
                      ListTile(
                        dense: true,
                        title: Text(value, style: appFieldTextStyle()),
                        onTap: () => onSelected(value),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Tag selector

class _TagSelector extends StatefulWidget {
  const _TagSelector({
    required this.controller,
    required this.options,
    required this.onChanged,
  });

  final TextEditingController controller;
  final List<String> options;
  final VoidCallback onChanged;

  @override
  State<_TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends State<_TagSelector> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> get _selected => widget.controller.text
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList();

  void _setTags(List<String> tags) {
    widget.controller.text = tags.join(', ');
    widget.onChanged();
    setState(() {});
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim();
    if (tag.isEmpty) return;
    final tags = _selected;
    if (!tags.contains(tag)) tags.add(tag);
    _input.clear();
    _setTags(tags);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final available = widget.options
        .where((tag) => !selected.contains(tag))
        .take(12)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(Icons.sell_outlined, 'Tags', trailing: 'optional'),
        // Chips and the input share one field, like a token input.
        GestureDetector(
          onTap: _focus.requestFocus,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tag in selected)
                  _TagChip(
                    label: tag,
                    selected: true,
                    onTap: () => _setTags(
                      selected.where((item) => item != tag).toList(),
                    ),
                  ),
                SizedBox(
                  width: 160,
                  height: 24,
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    onSubmitted: (value) {
                      _addTag(value);
                      _focus.requestFocus();
                    },
                    style: appFieldTextStyle(),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: selected.isEmpty
                          ? 'Type a tag, press Enter'
                          : 'Add tag…',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Suggestions', style: _subtitleStyle.copyWith(fontSize: 11)),
              for (final tag in available)
                _TagChip(label: tag, onTap: () => _addTag(tag)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Small tag token: selected ones carry an ×, suggestions a +.
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.muted;
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: .12)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected
              ? AppColors.accent.withValues(alpha: .45)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            selected ? 8 : 6,
            3,
            selected ? 4 : 8,
            3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!selected) ...[
                Icon(Icons.add_rounded, size: 13, color: color),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.text : color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 3),
                Tooltip(
                  message: 'Remove $label',
                  child: Icon(Icons.close_rounded, size: 13, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Profile color picker

class _ProfileColorPicker extends StatelessWidget {
  const _ProfileColorPicker({required this.color});

  final ProfileColor color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(Icons.palette_outlined, 'Accent color'),
        SizedBox(
          height: 38,
          child: Row(
            children: [
              for (final item in ProfileColor.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ColorSwatch(
                    color: _profileColorValue(item),
                    label: _profileColorLabel(item),
                    selected: item == color,
                    onTap: () => context.read<SshWorkspaceBloc>().add(
                      ProfileColorChanged(item),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label accent',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 2,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: Colors.black,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Saved profile to connect through (`ssh -J`).
class _JumpHostPicker extends StatelessWidget {
  const _JumpHostPicker({required this.selectedId, required this.candidates});

  final String selectedId;
  final List<SshProfile> candidates;

  @override
  Widget build(BuildContext context) {
    // A deleted jump profile shows as "direct" until the form is saved.
    final selected = candidates.any((p) => p.id == selectedId)
        ? selectedId
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(Icons.alt_route_rounded, 'Jump host (ProxyJump)'),
        SizedBox(
          height: 38,
          child: DropdownButtonFormField<String>(
            key: ValueKey(selected),
            initialValue: selected,
            isExpanded: true,
            dropdownColor: AppColors.surface,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('None (direct)')),
              for (final candidate in candidates)
                DropdownMenuItem(
                  value: candidate.id,
                  child: Text(
                    '${candidate.name} (${candidate.address})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => context.read<SshWorkspaceBloc>().add(
              JumpProfileChanged(value ?? ''),
            ),
          ),
        ),
      ],
    );
  }
}

// Auth method segmented control

class _AuthSegments extends StatelessWidget {
  const _AuthSegments({required this.profile, super.key});
  final SshProfile? profile;

  @override
  Widget build(BuildContext context) {
    final password = profile?.authMethod == AuthMethod.password;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(Icons.verified_user_outlined, 'Authentication'),
        // One segmented control: the selected half is lifted.
        Container(
          height: 38,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: _Segment(
                  selected: !password,
                  icon: Icons.key_rounded,
                  label: 'SSH Key',
                  onTap: () => context.read<SshWorkspaceBloc>().add(
                    const AuthMethodChanged(AuthMethod.sshKey),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: _Segment(
                  selected: password,
                  icon: Icons.lock_outline_rounded,
                  label: 'Password',
                  onTap: () => context.read<SshWorkspaceBloc>().add(
                    const AuthMethodChanged(AuthMethod.password),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? AppColors.accent : AppColors.muted,
                size: 15,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppColors.text : AppColors.muted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w400 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// SSH key upload box

class _UploadBox extends StatelessWidget {
  const _UploadBox({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _UploadIconBox(),
                          const SizedBox(width: 12),
                          const Expanded(child: _UploadBoxText()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: AppButton(
                          icon: Icons.folder_open_rounded,
                          label: 'Select Key',
                          onPressed: onTap,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _UploadIconBox(),
                      const SizedBox(width: 14),
                      const Expanded(child: _UploadBoxText()),
                      const SizedBox(width: 12),
                      AppButton(
                        icon: Icons.folder_open_rounded,
                        label: 'Select Key',
                        onPressed: onTap,
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _UploadIconBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.vpn_key_outlined, color: AppColors.accent, size: 18),
    );
  }
}

class _UploadBoxText extends StatelessWidget {
  const _UploadBoxText();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select or generate an SSH key',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _titleStyle.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'Pick a key from ~/.ssh, browse for a file, or generate a new ed25519 keypair.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _subtitleStyle,
        ),
      ],
    );
  }
}

String _profileColorLabel(ProfileColor color) {
  return switch (color) {
    ProfileColor.green => 'Green',
    ProfileColor.cyan => 'Cyan',
    ProfileColor.blue => 'Blue',
    ProfileColor.pink => 'Pink',
    ProfileColor.amber => 'Amber',
  };
}

Color _profileColorValue(ProfileColor color) {
  return switch (color) {
    ProfileColor.green => AppColors.green,
    ProfileColor.cyan => AppColors.cyan,
    ProfileColor.blue => AppColors.muted,
    ProfileColor.pink => AppColors.danger,
    ProfileColor.amber => AppColors.amber,
  };
}
