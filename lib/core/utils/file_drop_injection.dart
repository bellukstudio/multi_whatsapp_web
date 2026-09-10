import 'dart:convert';

/// One file to be "dropped" into the page via synthetic DOM events.
class DroppedFilePayload {
  const DroppedFilePayload({
    required this.name,
    required this.mimeType,
    required this.bytesBase64,
  });

  final String name;
  final String mimeType;
  final String bytesBase64;
}

/// Builds a script that reconstructs each dropped file as a real
/// in-page `File` object built directly from bytes we already read via
/// Dart's filesystem access, wraps them in a `DataTransfer`, and
/// dispatches synthetic dragenter/dragover/drop events carrying that
/// DataTransfer on `document.body` so WhatsApp Web's own drop-zone
/// listener picks it up as if the files had been dragged in from
/// Windows Explorer.
///
/// Why this is needed at all: on Windows, `webview_windows` renders
/// WebView2 off-screen via `ICoreWebView2CompositionController` and
/// streams it into Flutter as a texture — the actual WebView2 HWND
/// used internally is a message-only window (`HWND_MESSAGE`), which
/// has no screen position and can never be a real OS drag-and-drop
/// target. So a real file dragged from Explorer has nowhere valid to
/// land natively. This sidesteps that entirely: `desktop_drop` catches
/// the drop on Flutter's own (real) window, we read the bytes in Dart,
/// and re-inject them into the page as a synthetic-but-fully-
/// functional drop, without needing any native changes to the
/// WebView2 plugin itself.
///
/// NOTE: dispatches on both `document.body` and `window` rather than a
/// specific drop-zone element, since WhatsApp Web's own drop handling
/// responds to a drop anywhere over the app (it shows a full-window
/// "Drop here" overlay). `window` is included explicitly because
/// WhatsApp Web has been observed (via DevTools `getEventListeners`)
/// to attach its `dragover`/`drop` listeners directly to `window`
/// rather than `document` or `document.body` — those two elements had
/// no listeners at all. Dispatching on `document.body` alone should
/// still bubble up to `window`, but firing on both is cheap insurance.
/// If a future WhatsApp Web redesign narrows this to a more specific
/// container, retarget accordingly — same pattern as the chat-blur
/// selectors in chat_blur_css.dart.
///
/// [pointX]/[pointY], when provided, are the drop position in CSS
/// pixels local to the webview surface (i.e. the same space
/// `document.elementFromPoint` expects). The script uses them to find
/// the actual DOM element that was under the cursor at drop time and
/// dispatches there first — critical because dragenter/dragover/drop
/// only bubble *upward* from the dispatch target, so a page-specific
/// drop-zone element nested inside the app (e.g. scoped to the open
/// chat panel) can only ever be reached by starting the dispatch at
/// or below it, never by dispatching on `document.body`/`window`
/// (which sit above it in the tree). `document.body` and `window` are
/// still dispatched to afterward as a fallback/safety net.
///
/// Returns a diagnostics object (auto-serialized to JSON by
/// `executeScript`) instead of nothing, so the caller can `debugPrint`
/// it and see which element was actually targeted (`pointTargetTag`)
/// and, per (event type, target) pair, whether any page listener
/// called `preventDefault()` — the standard signal that a drop
/// handler actually processed the synthetic event — without needing
/// to open WebView2 DevTools separately.
String buildFileDropInjectionScript(
  List<DroppedFilePayload> files, {
  double? pointX,
  double? pointY,
}) {
  final filesJson = jsonEncode(files
      .map((f) => {
            'name': f.name,
            'type': f.mimeType,
            'bytesBase64': f.bytesBase64,
          })
      .toList());

  final pointLookup = (pointX != null && pointY != null)
      ? 'pointTarget = document.elementFromPoint($pointX, $pointY);'
      : '';

  return '''
(function() {
  var diag = {
    ok: false, error: null, fileCount: 0, types: [],
    results: [], pointTargetTag: null
  };
  try {
    var payload = $filesJson;
    diag.fileCount = payload.length;
    var fileObjects = payload.map(function(f) {
      var binary = atob(f.bytesBase64);
      var bytes = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      return new File([bytes], f.name, { type: f.type });
    });

    var dataTransfer = new DataTransfer();
    fileObjects.forEach(function(f) { dataTransfer.items.add(f); });
    diag.types = Array.prototype.slice.call(dataTransfer.types);

    var pointTarget = null;
    $pointLookup
    if (pointTarget) {
      var cls = pointTarget.className
        ? '.' + String(pointTarget.className).trim().split(/\\s+/).join('.')
        : '';
      diag.pointTargetTag = pointTarget.tagName + cls;
    }

    var targets = [];
    if (pointTarget) targets.push({ label: 'pointTarget', node: pointTarget });
    targets.push({ label: 'document.body', node: document.body });
    targets.push({ label: 'window', node: window });

    ['dragenter', 'dragover', 'drop'].forEach(function(type) {
      targets.forEach(function(t) {
        var event = new DragEvent(type, {
          bubbles: true,
          cancelable: true,
          dataTransfer: dataTransfer,
        });
        var notCanceled = t.node.dispatchEvent(event);
        diag.results.push({
          type: type,
          target: t.label,
          defaultPrevented: event.defaultPrevented,
          dispatchReturnedTrue: notCanceled
        });
      });
    });
    diag.ok = true;
  } catch (e) {
    diag.error = String(e && e.stack ? e.stack : e);
  }
  return diag;
})();
''';
}

/// Best-effort MIME type guess for common WhatsApp attachment types.
/// `XFile.mimeType` is often null on the Windows implementation of
/// `desktop_drop`, and WhatsApp Web uses the MIME type (not just the
/// extension) to decide how to preview/handle the attachment (image
/// grid vs. generic document, etc.), so a reasonable guess here matters
/// more than it would for a purely cosmetic feature.
String guessMimeType(String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip': 'application/zip',
    'txt': 'text/plain',
  };
  return map[ext] ?? 'application/octet-stream';
}