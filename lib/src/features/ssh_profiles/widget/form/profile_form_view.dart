import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import '../../bloc/index.dart';
import 'form_steps.dart';
import 'profile_preview.dart';

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
        final groupOptions = state.profiles
            .map((p) => p.group)
            .where((g) => g.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final tagOptions = state.profiles
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

            // --- Sections ---

            final identitySection = _FormSection(
              title: 'Profile Identity',
              subtitle: 'Nama dan group wajib. Tag opsional untuk filter.',
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
              title: 'Connection Endpoint',
              subtitle:
                  'Host, port, username, dan metode autentikasi SSH session.',
              children: [
                AppTextField(
                  controller: _host,
                  label: 'Host / IP',
                  icon: Icons.language_rounded,
                  onChanged: (_) => _changed(context),
                ),
                AppTextField(
                  controller: _port,
                  label: 'Port',
                  icon: Icons.tag_rounded,
                  onChanged: (_) => _changed(context),
                ),
                AppTextField(
                  controller: _username,
                  label: 'Username',
                  icon: Icons.person_outline,
                  onChanged: (_) => _changed(context),
                ),
                // Auth inline – full-width inside the endpoint card
                _AuthSegments(profile: profile),
                if (profile?.authMethod == AuthMethod.password)
                  AppTextField(
                    controller: _credential,
                    label: 'Password',
                    icon: Icons.lock_outline_rounded,
                    obscureText: true,
                    onChanged: (_) => _changed(context),
                  )
                else ...[
                  AppTextField(
                    controller: _credential,
                    label: 'SSH key label / path',
                    icon: Icons.key_rounded,
                    onChanged: (_) => _changed(context),
                  ),
                  _UploadBox(
                    onTap: () {
                      _credential.text = 'id_prod_ed25519';
                      _changed(context);
                    },
                  ),
                ],
              ],
            );

            // Advanced section with ^ toggle header
            final advancedSection = _AdvancedSection(
              expanded: _advancedExpanded,
              onToggle: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              children: [
                AppTextField(
                  controller: _startup,
                  label: 'Startup command',
                  icon: Icons.terminal_rounded,
                  onChanged: (_) => _changed(context),
                ),
                AppTextField(
                  controller: _fontSize,
                  label: 'Terminal font size',
                  icon: Icons.text_fields_rounded,
                  onChanged: (_) => _changed(context),
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
                    // Footer – Save only (no Test Connection)
                    AppPanel(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(18),
                      child: LayoutBuilder(
                        builder: (context, footerConstraints) {
                          final stackActions =
                              footerConstraints.maxWidth < 760;
                          final summary = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Review and save profile',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: portixTitle(16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pastikan host, port, username, dan auth sudah benar sebelum menyimpan.',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: portixMuted(),
                              ),
                            ],
                          );
                          final actions = Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
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
                              AppButton(
                                icon: Icons.save_outlined,
                                label: stackActions ? 'Save' : 'Save Profile',
                                primary: true,
                                onPressed: () =>
                                    context.read<SshWorkspaceBloc>().add(
                                      const ProfileSaved(),
                                    ),
                              ),
                            ],
                          );

                          if (stackActions) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                summary,
                                const SizedBox(height: 14),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: actions,
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: summary),
                              const SizedBox(width: 16),
                              actions,
                            ],
                          );
                        },
                      ),
                    ),
                    if (!showSidePanel && state.isProfileFormComplete) ...[
                      const SizedBox(height: 16),
                      ProfilePreview(state: state),
                    ],
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
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMaxWidth),
                        child: form,
                      ),
                    ),
                  ),
                  if (showSidePanel)
                    SizedBox(
                      width: 340,
                      height: availableHeight,
                      child: _AnimatedSidePanel(state: state),
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

// ---------------------------------------------------------------------------
// Side panel (no TestConnectionPanel)
// ---------------------------------------------------------------------------

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
              child: ProfilePreview(state: state),
            )
          : const SizedBox(key: ValueKey('empty-side-panel')),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact header with step pills
// ---------------------------------------------------------------------------

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
                    Text('New SSH Profile', style: portixTitle(16)),
                    const SizedBox(height: 2),
                    Text(
                      'Isi yang wajib saja dulu. Advanced boleh dibiarkan default.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: portixMuted(11),
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

// ---------------------------------------------------------------------------
// Generic form section card
// ---------------------------------------------------------------------------

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final titleSize = constraints.maxWidth < 340 ? 16.0 : 18.0;
              return Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(titleSize),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: portixMuted(),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth > 640;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: children.map((child) {
                  final fullWidth =
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

// ---------------------------------------------------------------------------
// Advanced section with ^ toggle
// ---------------------------------------------------------------------------

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.expanded,
    required this.onToggle,
    required this.children,
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.settings_outlined,
                    color: AppColors.muted,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Advanced', style: portixTitle(16)),
                        Text(
                          'Startup command, font size, dan konfigurasi lanjutan.',
                          style: portixMuted(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: expanded ? 0.5 : 0.0,
                    child: const Icon(
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth > 640;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 14,
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

// ---------------------------------------------------------------------------
// Autocomplete text field
// ---------------------------------------------------------------------------

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
        return widget.options
            .where((option) => option.toLowerCase().contains(query));
      },
      onSelected: (value) {
        widget.controller.text = value;
        widget.onChanged(value);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: AppColors.muted, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: portixLabel(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 40,
              child: TextField(
                controller: textController,
                focusNode: focusNode,
                onChanged: widget.onChanged,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  suffixIcon: Icon(
                    Icons.search_rounded,
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
                        title: Text(value, style: portixTitle(13)),
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

// ---------------------------------------------------------------------------
// Tag selector
// ---------------------------------------------------------------------------

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

  @override
  void dispose() {
    _input.dispose();
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
        .take(10)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.sell_outlined, color: AppColors.muted, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tags',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: portixLabel(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        AppPanel(
          padding: const EdgeInsets.all(10),
          color: AppColors.surfaceDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in selected)
                    InputChip(
                      label: Text(tag),
                      onDeleted: () => _setTags(
                        selected.where((item) => item != tag).toList(),
                      ),
                    ),
                  for (final tag in available)
                    ActionChip(
                      label: Text(tag),
                      onPressed: () => _addTag(tag),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: TextField(
                  controller: _input,
                  onSubmitted: _addTag,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Add tag and press Enter',
                    prefixIcon: Icon(
                      Icons.add_rounded,
                      color: AppColors.muted,
                      size: 18,
                    ),
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

// ---------------------------------------------------------------------------
// Profile color picker
// ---------------------------------------------------------------------------

class _ProfileColorPicker extends StatelessWidget {
  const _ProfileColorPicker({required this.color});

  final ProfileColor color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.palette_outlined,
              color: AppColors.muted,
              size: 15,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Terminal color',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: portixLabel(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 40,
          child: DropdownButtonFormField<ProfileColor>(
            initialValue: color,
            dropdownColor: AppColors.surface,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            items: [
              for (final item in ProfileColor.values)
                DropdownMenuItem(
                  value: item,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _profileColorValue(item),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _profileColorLabel(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              context.read<SshWorkspaceBloc>().add(ProfileColorChanged(value));
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Auth method segmented control
// ---------------------------------------------------------------------------

class _AuthSegments extends StatelessWidget {
  const _AuthSegments({required this.profile});
  final SshProfile? profile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 360;
        final keySegment = _Segment(
          selected: profile?.authMethod != AuthMethod.password,
          icon: Icons.key_rounded,
          label: 'SSH Key',
          onTap: () => context.read<SshWorkspaceBloc>().add(
            const AuthMethodChanged(AuthMethod.sshKey),
          ),
        );
        final passwordSegment = _Segment(
          selected: profile?.authMethod == AuthMethod.password,
          icon: Icons.lock_outline_rounded,
          label: 'Password',
          onTap: () => context.read<SshWorkspaceBloc>().add(
            const AuthMethodChanged(AuthMethod.password),
          ),
        );
        if (stack) {
          return Column(
            children: [
              SizedBox(height: 40, child: keySegment),
              const SizedBox(height: 8),
              SizedBox(height: 40, child: passwordSegment),
            ],
          );
        }
        return SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(child: keySegment),
              const SizedBox(width: 10),
              Expanded(child: passwordSegment),
            ],
          ),
        );
      },
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF143B63) : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? AppColors.cyan : AppColors.muted,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.text : AppColors.muted,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SSH key upload box
// ---------------------------------------------------------------------------

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
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.all(14),
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
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cyan),
      ),
      child: const Icon(Icons.upload_rounded, color: AppColors.cyan),
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
          'Drop SSH key here or select from vault',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: portixTitle(14),
        ),
        const SizedBox(height: 4),
        Text(
          'Supported: ed25519, rsa, pem. You can type the key label above or choose a vault key.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: portixMuted(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
