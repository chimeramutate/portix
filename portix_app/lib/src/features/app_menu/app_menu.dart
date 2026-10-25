import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/repositories/settings/settings_repository.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_settings.dart';

import 'keyboard_shortcuts_dialog.dart';

/// Writes one setting ([value] null restores the default) and tells open
/// terminals to reload.
Future<void> saveTerminalSetting(String key, String? value) async {
  final repository = sl<SettingsRepository>();
  final values = {...await repository.loadSettings()};
  if (value == null) {
    values.remove(key);
  } else {
    values[key] = value;
  }
  await repository.saveSettings(values);
  terminalSettingsRevision.value++;
}

/// Current font and size for the menu checkmarks.
mixin _TerminalPrefs<T extends StatefulWidget> on State<T> {
  String font = terminalFonts.first;
  String size = '13 px';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    terminalSettingsRevision.addListener(_load);
  }

  @override
  void dispose() {
    terminalSettingsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final Map<String, String> values;
    try {
      values = await sl<SettingsRepository>().loadSettings();
    } catch (_) {
      return; // no settings yet (or no DI in tests): keep the defaults
    }
    if (!mounted) return;
    setState(() {
      font = values[terminalFontSettingKey] ?? font;
      size = values[terminalFontSizeSettingKey] ?? size;
    });
  }

  void pick(String key, String value) =>
      unawaited(saveTerminalSetting(key, value));
}

/// The app's preferences live in the menu bar, as in VS Code:
/// Terminal > Font, Font Size and Keyboard Shortcuts. On macOS this is the
/// native menu bar; elsewhere [AppMenuBar] draws the menu in the title bar.
class AppMenus extends StatefulWidget {
  const AppMenus({required this.child, super.key});

  final Widget child;

  @override
  State<AppMenus> createState() => _AppMenusState();
}

class _AppMenusState extends State<AppMenus> with _TerminalPrefs {
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return widget.child;
    PlatformMenuItem choice(String key, String value, String current) =>
        PlatformMenuItem(
          // PlatformMenuItem has no checked state.
          label: value == current ? '✓ $value' : '    $value',
          onSelected: () => pick(key, value),
        );
    final shortcuts = PlatformMenuItem(
      label: 'Keyboard Shortcuts…',
      onSelected: () => unawaited(showKeyboardShortcutsDialog(context)),
    );
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Portix',
          menus: [
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.about,
                ),
              ],
            ),
            PlatformMenuItemGroup(members: [shortcuts]),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Terminal',
          menus: [
            PlatformMenu(
              label: 'Font',
              menus: [
                for (final value in terminalFonts)
                  choice(terminalFontSettingKey, value, font),
              ],
            ),
            PlatformMenu(
              label: 'Font Size',
              menus: [
                for (final value in terminalFontSizes)
                  choice(terminalFontSizeSettingKey, value, size),
              ],
            ),
            PlatformMenuItemGroup(members: [shortcuts]),
          ],
        ),
        const PlatformMenu(
          label: 'Window',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
          ],
        ),
      ],
      child: widget.child,
    );
  }
}

/// The Terminal menu drawn in the title bar where there is no native menu
/// bar (Linux, Windows).
class AppMenuBar extends StatefulWidget {
  const AppMenuBar({super.key});

  @override
  State<AppMenuBar> createState() => _AppMenuBarState();
}

class _AppMenuBarState extends State<AppMenuBar> with _TerminalPrefs {
  @override
  Widget build(BuildContext context) {
    Widget choice(String key, String value, String current) => MenuItemButton(
      leadingIcon: SizedBox(
        width: 18,
        child: value == current
            ? Icon(Icons.check_rounded, size: 16, color: AppColors.accent)
            : null,
      ),
      onPressed: () => pick(key, value),
      child: Text(value),
    );
    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          menuChildren: [
            for (final value in terminalFonts)
              choice(terminalFontSettingKey, value, font),
          ],
          child: const Text('Font'),
        ),
        SubmenuButton(
          menuChildren: [
            for (final value in terminalFontSizes)
              choice(terminalFontSizeSettingKey, value, size),
          ],
          child: const Text('Font Size'),
        ),
        const Divider(height: 1),
        MenuItemButton(
          onPressed: () => unawaited(showKeyboardShortcutsDialog(context)),
          child: const Text('Keyboard Shortcuts…'),
        ),
      ],
      builder: (context, controller, _) => TextButton(
        key: const ValueKey('app-menu-terminal'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        ),
        child: const Text('Terminal'),
      ),
    );
  }
}
