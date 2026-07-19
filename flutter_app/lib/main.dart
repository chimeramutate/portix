import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/theme/app_theme.dart';

import 'src/core/di/injection.dart';
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
  runApp(const PortixApp());
}

class PortixApp extends StatelessWidget {
  const PortixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portix',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
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
        ],
        child: const PortixWorkspacePage(),
      ),
    );
  }
}
