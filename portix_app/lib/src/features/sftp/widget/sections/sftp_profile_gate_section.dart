part of '../../page/sftp_workspace_page.dart';

class _SftpProfileGate extends StatefulWidget {
  const _SftpProfileGate({required this.profiles, required this.onSelected});

  final List<SshProfile> profiles;
  final ValueChanged<SshProfile> onSelected;

  @override
  State<_SftpProfileGate> createState() => _SftpProfileGateState();
}

class _SftpProfileGateState extends State<_SftpProfileGate> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<SshProfile> get _filteredProfiles {
    if (_searchQuery.isEmpty) return widget.profiles;
    final query = _searchQuery.toLowerCase();
    return widget.profiles
        .where(
          (p) =>
              p.name.toLowerCase().contains(query) ||
              p.address.toLowerCase().contains(query) ||
              (p.username.isNotEmpty &&
                  p.username.toLowerCase().contains(query)),
        )
        .toList(growable: false);
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
              Row(
                children: [
                  const Icon(
                    Icons.folder_open_rounded,
                    color: AppColors.cyan,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Select SFTP profile', style: portixTitle(18)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Pilih profile SSH dulu untuk membuka remote SFTP workspace.',
                style: portixMuted(13),
              ),
              const SizedBox(height: 16),
              if (!hasProfiles)
                AppPanel(
                  padding: const EdgeInsets.all(14),
                  color: AppColors.surfaceDark,
                  child: Text(
                    'Belum ada profile yang bisa dipakai. Buat atau lengkapi profile SSH terlebih dahulu.',
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
                      const Icon(
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
                                'Cari profile (nama, alamat, atau username)...',
                            hintStyle: portixMuted(12),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: portixTitle(13),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            color: AppColors.muted,
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Results count and clear button
                if (_searchQuery.isNotEmpty && !hasMatches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Tidak ada hasil untuk "$_searchQuery"',
                      style: portixMuted(12),
                    ),
                  ),
                if (hasMatches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      filteredProfiles.length == 1
                          ? '1 profile ditemukan'
                          : '${filteredProfiles.length} profile ditemukan',
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
                        const Icon(
                          Icons.search_off_rounded,
                          color: AppColors.muted,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tidak ada profile yang cocok',
                          style: portixMuted(12),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredProfiles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final profile = filteredProfiles[index];
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
                                  const Icon(
                                    Icons.dns_rounded,
                                    color: AppColors.green,
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
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${profile.address}:${profile.port} (${profile.username})',
                                          overflow: TextOverflow.ellipsis,
                                          style: portixMuted(12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
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
