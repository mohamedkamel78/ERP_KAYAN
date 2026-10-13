/// The web build's answer to "start the server for me": it cannot be done.
///
/// A page in a browser cannot start a process, and it does not need to: the
/// server that delivered the page is already there. This stub therefore
/// reports `unsupported`, and the program goes straight to its normal screens.
library;

import 'company_setup_data.dart';

/// The outcome of asking a build to start its own server.
class LocalBackendStatus {
  const LocalBackendStatus.unsupported()
    : baseUrl = null,
      problem = null,
      logPath = null,
      databaseProblem = false,
      needsFirstAdministrator = false;
  const LocalBackendStatus.ready(this.baseUrl)
    : problem = null,
      logPath = null,
      databaseProblem = false,
      needsFirstAdministrator = false;
  const LocalBackendStatus.failed(
    this.problem, {
    this.logPath,
    this.databaseProblem = false,
  }) : baseUrl = null,
       needsFirstAdministrator = false;
  const LocalBackendStatus.needsFirstAdministrator()
    : baseUrl = null,
      problem = null,
      logPath = null,
      databaseProblem = false,
      needsFirstAdministrator = true;

  final String? baseUrl;
  final String? problem;
  final String? logPath;
  final bool databaseProblem;

  /// A browser build never starts a server, so it never meets an empty database
  /// either - the pages it loads come from a server that is already set up.
  final bool needsFirstAdministrator;

  /// Ready when a local server baseUrl is available.
  bool get isReady => baseUrl != null;
}

/// Present so the two builds share one shape. On the web there is nothing to
/// start and nothing to stop.
class LocalBackend {
  static LocalBackend? get instance => null;

  String get baseUrl => '';

  static Future<LocalBackendStatus> ensureRunning({
    required String appDisplayName,
  }) async =>
      const LocalBackendStatus.unsupported();

  static Future<void> shutdown() async {}

  /// Nothing to create on the web: the server that delivered this page is
  /// already somebody's running installation.
  static Future<LocalBackendStatus> createFirstAdministrator({
    required String username,
    required String password,
    required String appDisplayName,
    CompanySetupData? company,
  }) async =>
      const LocalBackendStatus.unsupported();
}
