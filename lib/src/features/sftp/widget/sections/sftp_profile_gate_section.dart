part of '../../page/sftp_workspace_page.dart';

class _SftpProfileGate extends StatelessWidget {
  const _SftpProfileGate({required this.profiles, required this.onSelected});

  final List<SshProfile> profiles;
  final ValueChanged<SshProfile> onSelected;

  @override
  Widget build(BuildContext context) {
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
              if (profiles.isEmpty)
                AppPanel(
                  padding: const EdgeInsets.all(14),
                  color: AppColors.surfaceDark,
                  child: Text(
                    'Belum ada profile yang bisa dipakai. Buat atau lengkapi profile SSH terlebih dahulu.',
                    style: portixMuted(12),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: profiles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onSelected(profile),
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
                                        profile.address,
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
          ),
        ),
      ),
    );
  }
}

class _OperationBar extends StatelessWidget {
  const _OperationBar({
    required this.profile,
    required this.remotePath,
    required this.hasProfiles,
    required this.onChangeProfile,
  });

  final SshProfile? profile;
  final String remotePath;
  final bool hasProfiles;
  final VoidCallback? onChangeProfile;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.folder_open_rounded,
            color: AppColors.cyan,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text('SFTP Workspace', style: portixTitle(14)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              profile == null
                  ? hasProfiles
                        ? 'Select a profile to load the remote side · $remotePath'
                        : 'Local browser is ready · create an SSH profile to enable remote'
                  : '${profile!.name} · ${profile!.address} · $remotePath',
              overflow: TextOverflow.ellipsis,
              style: portixMuted(),
            ),
          ),
          if (onChangeProfile != null)
            AppButton(
              icon: Icons.swap_horiz_rounded,
              label: 'Change profile',
              onPressed: onChangeProfile!,
            ),
          if (profile != null) ...[
            const SizedBox(width: 8),
            AppButton(
              icon: Icons.upload_rounded,
              label: 'Upload',
              onPressed: () {},
            ),
            const SizedBox(width: 8),
            AppButton(
              icon: Icons.download_rounded,
              label: 'Download',
              onPressed: () {},
            ),
          ],
        ],
      ),
    );
  }
}
