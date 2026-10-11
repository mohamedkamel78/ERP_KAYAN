/// Used when the program is built for something that is not a browser.
///
/// The desktop copy does not need to give up here: a download or a print
/// page opens in the machine's own browser - the address already carries
/// everything the server needs - and choosing a file uses the system's own
/// dialogue. Only builds with neither (a bare library import) fail, and they
/// say so plainly instead of doing nothing.
library;

import 'dart:async';
import 'dart:io';

import 'picked_file.dart';

/// Opens [url] in the machine's default browser.
///
/// The browser then downloads the file into its own downloads folder, or
/// shows the print page and its print dialogue. The server listens on this
/// machine, so the browser can reach the address as-is.
void openInNewTab(String url) => _openInBrowser(url);

/// Saves the file behind [url]. On the desktop this is the same trip through
/// the machine's browser: its download handling takes over from there.
void downloadFile(String url) => _openInBrowser(url);

void _openInBrowser(String url) {
  final Future<Process> started;
  if (Platform.isWindows) {
    // The documented Windows way to open a URL with the user's own browser,
    // with no shell involved and therefore no quoting traps in the address.
    started = Process.start(
      'rundll32',
      ['url.dll,FileProtocolHandler', url],
      mode: ProcessStartMode.detached,
    );
  } else if (Platform.isMacOS) {
    started = Process.start('open', [url], mode: ProcessStartMode.detached);
  } else {
    started = Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
  }
  // Fire and forget: these calls are the void "open/download" buttons. If
  // the machine's browser cannot be started there is no screen to tell -
  // that is a machine problem, not a silent one, because the browser itself
  // is what reports the next step.
  unawaited(started.then<void>((_) {}).catchError((Object _) {}));
}

/// Asks the user for a spreadsheet or a backup file.
///
/// On Windows this is the system's own file dialogue. Cancellation returns
/// null - the normal way to change one's mind - and only a real failure to
/// read the chosen file throws.
Future<PickedFile?> pickFile({List<String> extensions = const []}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Choosing a file needs the web build on this platform. On Windows the '
      'desktop program opens the system file dialogue.',
    );
  }

  // One PowerShell command for the system file dialogue: the desktop program
  // ships no extra package for it, and a real dialogue is what people expect.
  final filter = extensions.isEmpty
      ? 'All files (*.*)|*.*'
      : 'Files (${extensions.join(';')})|${extensions.join(';')}|All files (*.*)|*.*';
  final script = 'Add-Type -AssemblyName System.Windows.Forms\n'
      r'$dialog = New-Object System.Windows.Forms.OpenFileDialog' '\n'
      r'$dialog.Multiselect = $false' '\n'
      "\$dialog.Filter = '${filter.replaceAll("'", "''")}'\n"
      r'if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) '
      r'{ [Console]::Out.Write($dialog.FileName) }';

  final result = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    script,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'The file dialogue could not be opened: ${result.stderr}'.trim(),
    );
  }
  final path = ('${result.stdout}').trim();
  if (path.isEmpty) return null; // the dialogue was closed without a choice

  final file = File(path);
  if (!await file.exists()) {
    throw StateError('The chosen file is gone: $path');
  }
  final bytes = await file.readAsBytes();
  final name = path.split(Platform.pathSeparator).last;
  return PickedFile(
    name: name,
    bytes: Uint8List.fromList(bytes),
    mimeType: 'application/octet-stream',
  );
}
