import 'package:flutter/services.dart';

const _channel = MethodChannel('portix/updater');

/// Opens Sparkle's "Check for Updates" window (macOS; see AppDelegate.swift).
/// Builds without the updater explain that themselves.
Future<void> checkForUpdates() =>
    _channel.invokeMethod<void>('checkForUpdates');
