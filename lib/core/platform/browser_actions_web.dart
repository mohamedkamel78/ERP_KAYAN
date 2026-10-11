import 'dart:async';
import 'dart:typed_data';
// The browser's own API, used on purpose: a file the user chooses, a tab
// opened for a print page and a download started behind the scenes are things
// only the page itself can do. This file is compiled for the web build and
// nothing else - see browser_actions.dart.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'picked_file.dart';

/// Saves the file behind [url], which the server sends as an attachment.
///
/// A hidden frame navigating to an attachment URL is a download, not a tab
/// and not a popup: it works at the top level and inside embedded frames
/// that permit downloads, and it never covers the app with an empty tab.
/// The file bytes travel through the browser's own download handling, so a
/// large backup archive never passes through page memory.
void downloadFile(String url) {
  final frame = html.IFrameElement()
    ..setAttribute('aria-hidden', 'true')
    ..style.border = '0'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.position = 'fixed'
    ..style.left = '-9999px'
    ..src = url;
  html.document.body?.append(frame);
  // The frame must stay until the browser has taken the download over;
  // after ten minutes it is safe to drop.
  Timer(const Duration(minutes: 10), frame.remove);
}

/// Opens [url] in a new tab. The browser keeps or prints what the server
/// sends.
///
/// Used for the print page: a new tab is what lets the person look at the
/// page before printing it. Where a new tab is refused - a popup blocker, or
/// a page running inside a sandboxed frame such as a preview embed - the
/// page is printed from a hidden frame instead, so the button still produces
/// a printout rather than doing nothing. In that fallback the page is asked
/// to auto-print, because there is no tab for anyone to look at first.
void openInNewTab(String url) {
  // The declared return type of window.open is not nullable, but the browser
  // returns null when it refuses the tab - hence the dynamic, which is the
  // only honest way to ask "was a tab opened?".
  final dynamic tab = html.window.open(url, '_blank');
  if (tab != null) return;
  _printFromHiddenFrame(_withAutoPrint(url));
}

/// The same page, told to open the print dialogue by itself.
///
/// Only meaningful for the print routes; any other URL simply ignores the
/// parameter.
String _withAutoPrint(String url) {
  try {
    final uri = Uri.parse(url);
    if (!uri.path.contains('/print')) return url;
    return uri.replace(queryParameters: {...uri.queryParameters, 'auto': '1'}).toString();
  } catch (_) {
    return url;
  }
}

void _printFromHiddenFrame(String url) {
  final frame = html.IFrameElement()
    ..setAttribute('aria-hidden', 'true')
    ..style.border = '0'
    // Not display:none: a frame that is not laid out prints blank. Offscreen
    // but laid out is what the print-from-frame technique needs.
    ..style.position = 'fixed'
    ..style.left = '-10000px'
    ..style.width = '1100px'
    ..style.height = '1400px'
    ..src = url;
  html.document.body?.append(frame);
  frame.onLoad.listen((_) {
    // The print page calls window.print() by itself once loaded with auto=1.
    // For anything else that lands here, print what arrived - a call across
    // origins can be refused, which is fine: the frame did what it could.
    Timer(const Duration(milliseconds: 300), () {
      // window.print() across frames: the type of a frame's window does not
      // carry print(), so the call goes through - which is what the browser
      // understands, and what is refused across origins can be caught.
      final dynamic window = frame.contentWindow;
      if (window == null) return;
      try {
        window.print();
      } catch (_) {
        /* cross-origin or already printed: nothing more to do */
      }
    });
    Timer(const Duration(minutes: 10), frame.remove);
  });
}

/// Asks the user for a file and reads it.
///
/// Returns null when the dialogue is closed without choosing anything, which
/// is a normal thing to do and not an error. Throws [StateError] only when a
/// chosen file could not be read.
Future<PickedFile?> pickFile({List<String> extensions = const []}) async {
  final input = html.FileUploadInputElement();
  if (extensions.isNotEmpty) {
    input.accept = extensions.join(',');
  }
  // Attached to the page: some browsers ignore the click on an element that
  // is not in the document.
  input.style.display = 'none';
  html.document.body?.append(input);

  final completer = Completer<PickedFile?>();
  var finished = false;
  StreamSubscription<html.Event>? focusSubscription;

  void finish(PickedFile? file) {
    if (finished) return;
    finished = true;
    focusSubscription?.cancel();
    input.remove();
    completer.complete(file);
  }

  void fail(Object error) {
    if (finished) return;
    finished = true;
    focusSubscription?.cancel();
    input.remove();
    completer.completeError(error);
  }

  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      // 'change' with no file is the dialogue closing without a choice.
      finish(null);
      return;
    }
    final file = files.first;
    final reader = html.FileReader();
    reader.onLoad.listen((_) {
      try {
        final bytes = _bytesOf(reader.result);
        finish(
          PickedFile(
            name: file.name,
            bytes: bytes,
            mimeType: file.type.isEmpty ? 'application/octet-stream' : file.type,
          ),
        );
      } catch (error) {
        fail(StateError('The file could not be read: ${file.name} ($error)'));
      }
    });
    reader.onError.listen((_) {
      fail(StateError('The file could not be read: ${file.name}'));
    });
    reader.readAsArrayBuffer(file);
  });

  // Closing the dialogue without choosing fires 'cancel' in current
  // browsers. Older ones fire nothing at all - for those the window taking
  // focus again, with no file on the input, means the same thing. Both paths
  // end with null; a second attempt to finish is ignored.
  input.addEventListener('cancel', (_) => finish(null));
  focusSubscription = html.window.onFocus.listen((_) {
    Timer(const Duration(milliseconds: 400), () {
      if (!finished && (input.files == null || input.files!.isEmpty)) {
        finish(null);
      }
    });
  });

  try {
    input.click();
  } catch (error) {
    fail(StateError('The file dialogue could not be opened: $error'));
  }
  return completer.future;
}

/// Whatever shape the platform hands back after `readAsArrayBuffer`.
Uint8List _bytesOf(Object? result) {
  if (result is Uint8List) return result;
  if (result is ByteBuffer) return result.asUint8List();
  if (result is List<int>) return Uint8List.fromList(result);
  throw StateError('unexpected file data (${result.runtimeType})');
}
