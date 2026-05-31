import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/theme/app_theme.dart';

import 'src/core/di/injection.dart';
import 'src/features/ssh_profiles/bloc/index.dart';
import 'src/features/ssh_profiles/page/index.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: BlocProvider(
        create: (_) => sl<SshWorkspaceBloc>()..add(const ProfilesRequested()),
        child: const PortixWorkspacePage(),
      ),
    );
  }
}
