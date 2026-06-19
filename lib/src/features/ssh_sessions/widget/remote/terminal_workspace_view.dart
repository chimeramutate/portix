import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;
import 'package:xterm/xterm.dart';

import '../../controller/index.dart';
import 'terminal_shortcuts.dart';

part 'sections/empty_section.dart';
part 'sections/workspace_tree_section.dart';
part 'sections/terminal_pane_section.dart';
part 'sections/overlay_section.dart';
part 'sections/tab_option_section.dart';
part 'sections/theme_section.dart';
