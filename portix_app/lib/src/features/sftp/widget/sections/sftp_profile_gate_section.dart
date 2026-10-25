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

  List<SshProfile> get _filteredProfiles {
    final query = _searchQuery.toLowerCase();
    final matches = query.isEmpty
        ? widget.profiles
        : widget.profiles.where(
            (p) =>
                p.name.toLowerCase().contains(query) ||
                p.address.toLowerCase().contains(query) ||
                (p.username.isNotEmpty &&
                    p.username.toLowerCase().contains(query)),
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

/// Square sort button matching the search field: A–Z icon with an arrow
/// that turns over for Z → A.
class _SortToggle extends StatefulWidget {
  const _SortToggle({required this.ascending, required this.onTap});

  final bool ascending;
  final VoidCallback onTap;

  @override
  State<_SortToggle> createState() => _SortToggleState();
}

class _SortToggleState extends State<_SortToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = _hover ? AppColors.accent : AppColors.muted;
    return Tooltip(
      message: widget.ascending ? 'Sorted A → Z' : 'Sorted Z → A',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          key: const ValueKey('sftp-sort-order'),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hover ? AppColors.accent : AppColors.inputBorder,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sort_by_alpha_rounded, size: 16, color: color),
                AnimatedRotation(
                  turns: widget.ascending ? 0 : .5,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 12,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
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
