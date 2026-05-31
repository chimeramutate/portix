import 'package:flutter/material.dart';

class LocalEditor {
  const LocalEditor(
    this.name,
    this.command, {
    this.arguments = const [],
    this.icon,
    this.svgAsset,
  });

  final String name;
  final String command;
  final List<String> arguments;
  final IconData? icon;
  final String? svgAsset;
}
