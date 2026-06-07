import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'app_panel.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.controller,
    required this.label,
    super.key,
    this.icon,
    this.hint = '',
    this.onChanged,
    this.readOnly = false,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppColors.muted, size: 15),
                const SizedBox(width: 8),
              ],
              Text(label, style: portixLabel()),
            ],
          ),
          const SizedBox(height: 7),
        ],
        SizedBox(
          height: 40,
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            obscureText: obscureText,
            onChanged: onChanged,
            style: GoogleFonts.inter(
              color: AppColors.text,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: label.isEmpty && icon != null
                  ? Icon(icon, color: AppColors.muted, size: 19)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
