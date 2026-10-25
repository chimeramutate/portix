part of '../../page/sftp_workspace_page.dart';

class _SftpProfileGate extends StatefulWidget {
  const _SftpProfileGate({
    required this.profiles,
    required this.onSelected,
    this.includeLocal = false,
    this.onLocalSelected,
    this.localSelected = false,
  });

  final List<SshProfile> profiles;
  final ValueChanged<SshProfile> onSelected;

  /// Puts a **Local** entry first in the list, even once a remote profile
  /// is attached.
  final bool includeLocal;
  final VoidCallback? onLocalSelected;
  final bool localSelected;

  @override
  State<_SftpProfileGate> createState() => _SftpProfileGateState();
}

class _SftpProfileGateState extends State<_SftpProfileGate> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _sortAscending = true; // A → Z by default
  String? _group; // null = all groups
  bool _onlineOnly = false;

  bool get _filtering => _group != null || _onlineOnly;

  List<String> get _groups => {
    for (final p in widget.profiles)
      if (p.group.trim().isNotEmpty) p.group.trim(),
  }.toList()..sort();

  List<SshProfile> get _filteredProfiles {
    final query = _searchQuery.toLowerCase();
    final matches = widget.profiles.where(
      (p) =>
          (_group == null || p.group.trim() == _group) &&
          (!_onlineOnly || p.status == ConnectionStatus.online) &&
          (query.isEmpty ||
              p.name.toLowerCase().contains(query) ||
              p.address.toLowerCase().contains(query) ||
              (p.username.isNotEmpty &&
                  p.username.toLowerCase().contains(query))),
    );
    final sorted = matches.toList(growable: false)
      ..sort(
        (a, b) => _sortAscending
            ? a.name.compareTo(b.name)
            : b.name.compareTo(a.name),
      );
    return sorted;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _searchField() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.inputBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: AppColors.muted, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search profiles (name, address or username)',
                hintStyle: portixMuted(13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: appFieldTextStyle(),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              icon: Icon(Icons.close_rounded, color: AppColors.muted, size: 16),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProfiles = _filteredProfiles;
    final hasProfiles = widget.profiles.isNotEmpty;
    final hasMatches = filteredProfiles.isNotEmpty;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hasProfiles)
                AppPanel(
                  padding: const EdgeInsets.all(14),
                  color: AppColors.surfaceDark,
                  child: Text(
                    'No usable profiles yet. Create or complete an SSH profile first.',
                    style: portixMuted(12),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(child: _searchField()),
                    const SizedBox(width: 8),
                    _SortToggle(
                      ascending: _sortAscending,
                      onTap: () =>
                          setState(() => _sortAscending = !_sortAscending),
                    ),
                    const SizedBox(width: 8),
                    _FilterMenu(
                      groups: _groups,
                      group: _group,
                      onlineOnly: _onlineOnly,
                      onGroup: (group) => setState(() => _group = group),
                      onOnlineOnly: (value) =>
                          setState(() => _onlineOnly = value),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Results count and clear button
                if (_searchQuery.isNotEmpty && !hasMatches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No results for "$_searchQuery"',
                      style: portixMuted(12),
                    ),
                  ),
                if (_filtering)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (_group case final group?)
                          _FilterChip(
                            label: group,
                            onRemove: () => setState(() => _group = null),
                          ),
                        if (_onlineOnly)
                          _FilterChip(
                            label: 'Online',
                            onRemove: () => setState(() => _onlineOnly = false),
                          ),
                      ],
                    ),
                  ),
                if (hasMatches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      filteredProfiles.length == 1
                          ? '1 profile found'
                          : '${filteredProfiles.length} profiles found',
                      style: portixMuted(11),
                    ),
                  ),
                // Profile list
                if (!hasMatches && hasProfiles)
                  AppPanel(
                    padding: const EdgeInsets.all(14),
                    color: AppColors.surfaceDark,
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          color: AppColors.muted,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text('No matching profiles', style: portixMuted(12)),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount:
                          filteredProfiles.length +
                          (widget.includeLocal ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        if (widget.includeLocal && index == 0) {
                          return _LocalProfileTile(
                            selected: widget.localSelected,
                            onTap: widget.onLocalSelected,
                          );
                        }
                        final profileIndex = widget.includeLocal
                            ? index - 1
                            : index;
                        final profile = filteredProfiles[profileIndex];
                        return _GateRow(
                          leading: ProfileOsIcon(profile: profile, size: 24),
                          title: profile.name,
                          subtitle: profile.address,
                          onTap: () => widget.onSelected(profile),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Sort order button: arrow and "A–Z" / "Z–A", flipped on tap.
class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.ascending, required this.onTap});

  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ToolbarBox(
      key: const ValueKey('sftp-sort-order'),
      tooltip: ascending ? 'Sorted A → Z' : 'Sorted Z → A',
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedRotation(
            turns: ascending ? 0 : .5,
            duration: const Duration(milliseconds: 160),
            child: Icon(
              Icons.arrow_upward_rounded,
              size: 14,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            ascending ? 'A–Z' : 'Z–A',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "more" menu next to sort: filter by group and by online status.
/// A dot on the button shows a filter is on.
class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.groups,
    required this.group,
    required this.onlineOnly,
    required this.onGroup,
    required this.onOnlineOnly,
  });

  final List<String> groups;
  final String? group;
  final bool onlineOnly;
  final ValueChanged<String?> onGroup;
  final ValueChanged<bool> onOnlineOnly;

  static const _all = '\u0000all';
  static const _online = '\u0000online';
  static const _clear = '\u0000clear';

  PopupMenuItem<String> _item(String value, String label, bool checked) {
    return PopupMenuItem(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: checked
                ? Icon(Icons.check_rounded, size: 16, color: AppColors.accent)
                : null,
          ),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _heading(String label) {
    return PopupMenuItem(
      enabled: false,
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(label.toUpperCase(), style: portixMuted(11)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtering = group != null || onlineOnly;
    return PopupMenuButton<String>(
      tooltip: 'Filter profiles',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      onSelected: (value) {
        switch (value) {
          case _all:
            onGroup(null);
          case _online:
            onOnlineOnly(!onlineOnly);
          case _clear:
            onGroup(null);
            onOnlineOnly(false);
          default:
            onGroup(value);
        }
      },
      itemBuilder: (context) => [
        _heading('Status'),
        _item(_online, 'Online only', onlineOnly),
        if (groups.isNotEmpty) ...[
          const PopupMenuDivider(height: 9),
          _heading('Group'),
          _item(_all, 'All groups', group == null),
          for (final g in groups) _item(g, g, group == g),
        ],
        if (filtering) ...[
          const PopupMenuDivider(height: 9),
          _item(_clear, 'Clear filters', false),
        ],
      ],
      child: _ToolbarBox(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.more_horiz_rounded, size: 18, color: AppColors.muted),
            if (filtering)
              Positioned(
                right: -3,
                top: -2,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A 32px bordered box matching the search field. With [onTap] it is a
/// button; without, it only draws (a parent such as a popup handles taps).
class _ToolbarBox extends StatelessWidget {
  const _ToolbarBox({required this.child, this.onTap, this.tooltip, super.key});

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: 32,
      constraints: const BoxConstraints(minWidth: 32),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A tappable box gets its fill from the Material below so the
        // hover ink shows.
        color: onTap == null ? AppColors.surfaceDark : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.selectedSoft,
          child: box,
        ),
      ),
    );
  }
}

/// An active filter, removable with its ×.
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: AppColors.selectedSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: AppColors.text, fontSize: 12)),
          IconButton(
            tooltip: 'Remove filter',
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 20, height: 20),
            icon: Icon(Icons.close_rounded, size: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The leading **Local** row, shown when [_SftpProfileGate.includeLocal]
/// is set.
class _LocalProfileTile extends StatelessWidget {
  const _LocalProfileTile({required this.selected, this.onTap});

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _GateRow(
      leading: Icon(Icons.computer_rounded, color: AppColors.muted, size: 20),
      title: 'Local',
      subtitle: 'Local filesystem',
      selected: selected,
      onTap: onTap,
    );
  }
}

/// One row of the profile picker: [leading] icon, name and address, a
/// check when [selected].
class _GateRow extends StatelessWidget {
  const _GateRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: AppColors.selectedSoft,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                SizedBox.square(dimension: 24, child: Center(child: leading)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: portixMuted(11),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_rounded : Icons.chevron_right_rounded,
                  color: selected ? AppColors.accent : AppColors.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text label for a profile's [ConnectionStatus], shown in the picker tile.
