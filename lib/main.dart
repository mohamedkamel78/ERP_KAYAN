import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/backend/backend_gate.dart';
import 'core/logging/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init(verbose: true);
  _publishSemanticsWhenAsked();

  // On the web, and on a developer's machine, the gate does nothing at all and
  // the program starts exactly as it always has. In a packaged desktop copy it
  // starts the API server this machine owns, waits for it to answer, and hands
  // the program the address it ended up on.
  runApp(const ProviderScope(child: BackendGate(child: ErpApp())));
}

/// On the web Flutter only publishes its accessibility tree when something
/// asks for one - a screen reader, usually. Everything else about the
/// program behaves identically either way, including the picture on the
/// screen.
///
/// The checks that click the program's buttons need the tree: they follow
/// the wording of a button rather than its position on the screen, so that
/// they keep working when the layout moves. Asking with `?a11y=1` turns the
/// tree on for that one visit, and nothing else changes.
void _publishSemanticsWhenAsked() {
  if (!kIsWeb) return;
  if (Uri.base.queryParameters['a11y'] != '1') return;
  SemanticsBinding.instance.ensureSemantics();
}
