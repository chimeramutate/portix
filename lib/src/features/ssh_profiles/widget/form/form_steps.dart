import 'package:flutter/material.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import '../../bloc/index.dart';
import 'package:portix/src/core/widgets/index.dart';

enum FormStepVisualState { completed, current, pending }

class FormSteps extends StatelessWidget {
  const FormSteps({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _StepVm(
        title: 'Profile identity',
        subtitle: 'Name, group, tags',
        state: state.isIdentityComplete
            ? FormStepVisualState.completed
            : FormStepVisualState.current,
      ),
      _StepVm(
        title: 'Endpoint',
        subtitle: 'Host, port, username',
        state: state.isIdentityComplete
            ? state.isEndpointComplete
                  ? FormStepVisualState.completed
                  : FormStepVisualState.current
            : FormStepVisualState.pending,
      ),
      _StepVm(
        title: 'Authentication',
        subtitle: 'Password or SSH key',
        state: state.isEndpointComplete
            ? state.isAuthComplete
                  ? FormStepVisualState.completed
                  : FormStepVisualState.current
            : FormStepVisualState.pending,
      ),
      _StepVm(
        title: 'Connection test',
        subtitle: 'Verify before saving',
        state: state.isAuthComplete
            ? state.isProfileTested
                  ? FormStepVisualState.completed
                  : FormStepVisualState.current
            : FormStepVisualState.pending,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text('New Profile', style: portixTitle(23)),
        const SizedBox(height: 24),
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepIcon(state: step.state),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title, style: portixTitle(13)),
                      const SizedBox(height: 4),
                      Text(step.subtitle, style: portixMuted()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const AppPanel(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.green, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Security default',
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'Credentials are stored encrypted. SSH key passphrase is requested only when needed.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepVm {
  const _StepVm({
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final String title;
  final String subtitle;
  final FormStepVisualState state;
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.state});
  final FormStepVisualState state;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      FormStepVisualState.completed => Icons.check_circle_outline_rounded,
      FormStepVisualState.current => Icons.timelapse_rounded,
      FormStepVisualState.pending => Icons.radio_button_unchecked_rounded,
    };
    final color = switch (state) {
      FormStepVisualState.completed => AppColors.green,
      FormStepVisualState.current => AppColors.amber,
      FormStepVisualState.pending => AppColors.muted,
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .65)),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}
