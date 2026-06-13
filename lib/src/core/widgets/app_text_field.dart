import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_panel.dart';

class AppTextField extends StatefulWidget {
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
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: AppColors.muted, size: 15),
                const SizedBox(width: 8),
              ],
              Text(widget.label, style: portixLabel()),
            ],
          ),
          const SizedBox(height: 7),
        ],
        SizedBox(
          height: 40,
          child: TextField(
            controller: widget.controller,
            readOnly: widget.readOnly,
            obscureText: _obscured,
            onChanged: widget.onChanged,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.text,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: widget.label.isEmpty && widget.icon != null
                  ? Icon(widget.icon, color: AppColors.muted, size: 19)
                  : null,
              suffixIcon: widget.obscureText
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.muted,
                        size: 18,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
