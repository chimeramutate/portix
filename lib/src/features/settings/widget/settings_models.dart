import 'package:flutter/material.dart';

class SettingsNavigationGroup {
  const SettingsNavigationGroup({required this.label, required this.items});

  final String label;
  final List<SettingsNavigationItem> items;
}

class SettingsNavigationItem {
  const SettingsNavigationItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.profileTitle,
    required this.profileSubtitle,
    required this.sections,
  });

  final String id;
  final String title;
  final IconData icon;
  final String headerTitle;
  final String headerSubtitle;
  final String profileTitle;
  final String profileSubtitle;
  final List<SettingsDetailSection> sections;
}

class SettingsDetailSection {
  const SettingsDetailSection({required this.title, required this.rows});

  final String title;
  final List<SettingsDetailRow> rows;
}

class SettingsDetailRow {
  const SettingsDetailRow(this.label, this.value);

  final String label;
  final String value;

  String keyFor(String itemId) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '$itemId.$normalized';
  }

  List<String> get options {
    final normalized = value.toLowerCase();
    if (normalized == 'on' || normalized == 'off') return const ['ON', 'OFF'];
    if (normalized == 'enabled' || normalized == 'disabled') {
      return const ['Enabled', 'Disabled'];
    }
    if (normalized == 'required' || normalized == 'optional') {
      return const ['Required', 'Optional'];
    }
    return const [];
  }
}
