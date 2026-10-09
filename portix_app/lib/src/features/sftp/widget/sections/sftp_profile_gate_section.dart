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

  /// When true, a **Local** entry is rendered as the first (topmost) pick in
  /// the list, so the picker always offers "local" as the primary choice —
  /// matching the requirement that the top-most pick is Local even once a
  /// remote profile has been attached.
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

  @override
  Widget build(BuildContext context) {
    final filteredProfiles = _filteredProfiles;
    final hasProfiles = widget.profiles.isNotEmpty;
    final hasMatches = filteredProfiles.isNotEmpty;

    return Center(
      child: AppPanel(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.all(24),
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
                // Search field
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: AppColors.muted,
                        size: 18,
                      ),
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
                            hintText:
                                'Search profiles (name, address or username)',
                            hintStyle: portixMuted(12),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: portixTitle(13),
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
                          constraints: const BoxConstraints.tightFor(
                            width: 24,
                            height: 24,
                          ),
                          icon: Icon(
                            Icons.close_rounded,
                            color: AppColors.muted,
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Filter: sort tags A → Z / Z → A
                Row(
                  children: [
                    _SortChip(
                      label: 'A → Z',
                      selected: _sortAscending,
                      onTap: () => setState(() => _sortAscending = true),
                    ),
                    const SizedBox(width: 8),
                    _SortChip(
                      label: 'Z → A',
                      selected: !_sortAscending,
                      onTap: () => setState(() => _sortAscending = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => widget.onSelected(profile),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceDark,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.dns_rounded,
                                    color: AppColors.muted,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          profile.name,
                                          style: portixTitle(14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
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

/// A small filter "tag" used to toggle profile sort order (A → Z / Z → A).
class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cyan.withValues(alpha: .10)
                : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.cyan : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: (selected ? portixTitle(12) : portixMuted(11)).copyWith(
              color: selected ? AppColors.cyan : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A leading picker row that represents the **Local** filesystem root.
///
/// Rendered as the first (topmost) entry whenever [_SftpProfileGate.includeLocal]
/// is set, so the picker always offers "Local" as the primary choice — keeping
/// the local root pinned at the top of the server list.
class _LocalProfileTile extends StatelessWidget {
  const _LocalProfileTile({required this.selected, this.onTap});

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cyan.withValues(alpha: .10)
                : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.cyan : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.computer_rounded, color: AppColors.cyan, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Local', style: portixTitle(14)),
                    const SizedBox(height: 2),
                    Text(
                      'Local filesystem',
                      overflow: TextOverflow.ellipsis,
                      style: portixMuted(12),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, color: AppColors.cyan, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text label for a profile's [ConnectionStatus], shown in the picker tile.
