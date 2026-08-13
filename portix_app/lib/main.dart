import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/rdp/bloc/index.dart';
import 'package:portix/src/features/rdp/page/rdp_frame_test_page.dart';
import 'package:portix/src/features/rdp/service/rdp_window_service.dart';
import 'package:window_manager/window_manager.dart';

import 'src/core/di/injection.dart';
import 'src/features/rdp/window/main_window_bootstrap.dart';
import 'src/features/ssh_profiles/bloc/index.dart';
import 'src/features/ssh_profiles/page/index.dart';
import 'src/features/ssh_sessions/bloc/index.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    try {
      await FilePicker.skipEntitlementsChecks();
    } catch (_) {}
  }
  await configureDependencies();
  if (await runPortixWindowIfNeeded()) {
    return;
  }
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  runApp(const PortixApp());
}

class PortixApp extends StatefulWidget {
  const PortixApp({super.key});

  @override
  State<PortixApp> createState() => _PortixAppState();
}

class _PortixAppState extends State<PortixApp> with WindowListener {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;

    await RdpWindowService.closeAllSessions();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portix',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      routes: {'/rdp-frame-test': (_) => const RdpFrameTestPage()},
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = media.textScaler
            .scale(1)
            .clamp(0.85, media.size.width >= 900 ? 0.95 : 1.05);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) =>
                sl<SshWorkspaceBloc>()..add(const ProfilesRequested()),
          ),
          BlocProvider(create: (_) => sl<SshSessionBloc>()),
          BlocProvider(
            create: (_) =>
                sl<RdpWorkspaceBloc>()..add(const RdpProfilesRequested()),
          ),
        ],
        child: const PortixWorkspacePage(),
      ),
    );
  }
}
