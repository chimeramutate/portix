import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';
import 'package:portix/src/domain/repositories/ssh/ssh_profile_repository.dart';

void main() {
  testWidgets(
    'BlocListener<SshSessionBloc> inside MultiBlocListener should find the provider',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider(
                  create: (_) =>
                      SshWorkspaceBloc(repository: SshProfileRepository()),
                ),
                BlocProvider(create: (_) => SshSessionBloc()),
              ],
              child: MultiBlocListener(
                listeners: [
                  BlocListener<SshWorkspaceBloc, SshWorkspaceState>(
                    listenWhen: (previous, current) => false,
                    listener: (context, state) {},
                  ),
                  BlocListener<SshWorkspaceBloc, SshWorkspaceState>(
                    listenWhen: (previous, current) => false,
                    listener: (context, state) {},
                  ),
                  BlocListener<SshSessionBloc, SshSessionState>(
                    listenWhen: (previous, current) => false,
                    listener: (context, state) {},
                  ),
                  BlocListener<SshSessionBloc, SshSessionState>(
                    listenWhen: (previous, current) => false,
                    listener: (context, state) {},
                  ),
                ],
                child: const SizedBox(key: Key('child')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('child')), findsOneWidget);
    },
  );

  testWidgets(
    'BlocListener<SshSessionBloc> with explicit bloc param should find the bloc',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider(
                  create: (_) =>
                      SshWorkspaceBloc(repository: SshProfileRepository()),
                ),
                BlocProvider(create: (_) => SshSessionBloc()),
              ],
              child: Builder(
                builder: (context) {
                  final bloc = context.read<SshSessionBloc>();
                  return MultiBlocListener(
                    listeners: [
                      BlocListener<SshSessionBloc, SshSessionState>(
                        bloc: bloc,
                        listenWhen: (previous, current) => false,
                        listener: (context, state) {},
                      ),
                      BlocListener<SshSessionBloc, SshSessionState>(
                        bloc: bloc,
                        listenWhen: (previous, current) => false,
                        listener: (context, state) {},
                      ),
                    ],
                    child: const SizedBox(key: Key('child')),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('child')), findsOneWidget);
    },
  );
}
