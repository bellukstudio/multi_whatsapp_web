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
/// `document.elementFromPoint` expects). This function only performs
/// the "setup" step (build the `File`s/`DataTransfer`, locate the
/// element under the cursor, and fire `dragenter`); call
/// [buildFileDropAdvanceScript] and [buildFileDropFinishScript]
/// afterward, with real delays between each `executeScript` call from
/// Dart, to complete the sequence. This is deliberately split into
/// multiple synchronous scripts, run from Dart with real delays in
/// between, rather than one script using `await`/`setTimeout`
/// internally: `executeScript` (per `webview_windows`/this WebView2
/// version) does *not* await a returned Promise's resolution — it
/// serializes the Promise object itself, which has no own enumerable
/// properties and comes back as an empty `{}`. Splitting the sequence
/// across calls sidesteps that entirely, and state is threaded
/// between calls via a `window.__mwwDrop` stash (safe because
/// `executeScript` calls all run in the same persistent page context,
/// not a fresh one each time).
///
/// The reason to spread the events out at all: a real OS-driven drag
/// naturally produces a *stream* of dragover events over time, and
/// React-based drop handling commonly reads/writes state across that
/// stream (e.g. show-overlay-on-enter, confirm-still-hovering-on-over)
/// that a single synchronous burst of events may not exercise
/// correctly.
///
/// The dispatch is targeted at the element under the cursor (rather
/// than only on `document.body`/`window`) because dragenter/dragover/
/// drop only bubble *upward* from the dispatch target: a page-specific
/// drop-zone element nested inside the app (e.g. scoped to the open
/// chat panel) can only ever be reached by starting the dispatch at
/// or below it. `document.body`/`window` are still fired once, untimed,
/// by [buildFileDropFinishScript] as a fallback/safety net — WhatsApp
/// Web has been observed (via DevTools `getEventListeners`) to attach
/// generic preventDefault-only `dragover`/`drop` listeners directly to
/// `window` (likely just to stop the browser's default "open the file
/// as a page" behavior), so those are kept for completeness even
/// though they're not expected to trigger the actual attach flow.
String buildFileDropSetupScript(
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

  final pxLiteral = pointX?.toString() ?? 'null';
  final pyLiteral = pointY?.toString() ?? 'null';

  return '''
(function() {
  var diag = {
    ok: false, error: null, fileCount: 0, types: [],
    pointTargetTag: null
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
    dataTransfer.effectAllowed = 'copyMove';
    diag.types = Array.prototype.slice.call(dataTransfer.types);

    var px = $pxLiteral;
    var py = $pyLiteral;
    var pointTarget = (px !== null && py !== null)
      ? document.elementFromPoint(px, py)
      : null;
    if (pointTarget) {
      var cls = pointTarget.className
        ? '.' + String(pointTarget.className).trim().split(/\\s+/).join('.')
        : '';
      diag.pointTargetTag = pointTarget.tagName + cls;
    }

    function label(node) {
      if (node === window) return 'window';
      if (node === document.body) return 'document.body';
      return 'pointTarget';
    }

    function fire(type, node) {
      var opts = { bubbles: true, cancelable: true, dataTransfer: dataTransfer };
      if (px !== null && py !== null) {
        opts.clientX = px;
        opts.clientY = py;
        opts.screenX = px;
        opts.screenY = py;
      }
      var event = new DragEvent(type, opts);
      var notCanceled = node.dispatchEvent(event);
      window.__mwwDrop.results.push({
        type: type,
        target: label(node),
        defaultPrevented: event.defaultPrevented,
        dispatchReturnedTrue: notCanceled
      });
    }

    window.__mwwDrop = {
      dataTransfer: dataTransfer,
      pointTarget: pointTarget,
      pointTargetTag: diag.pointTargetTag,
      types: diag.types,
      fileCount: diag.fileCount,
      results: [],
      fire: fire
    };

    if (pointTarget) fire('dragenter', pointTarget);
    diag.ok = true;
  } catch (e) {
    diag.error = String(e && e.stack ? e.stack : e);
  }
  return diag;
})();
''';
}

/// Fires one more `dragover` on the cached point target (see
/// [buildFileDropSetupScript]). Call this once or twice, with a real
/// Dart-side delay before each call, to simulate the natural stream
/// of dragover events a real drag produces before [buildFileDropFinishScript].
String buildFileDropAdvanceScript() {
  return '''
(function() {
  try {
    var st = window.__mwwDrop;
    if (st && st.pointTarget) {
      st.dataTransfer.dropEffect = 'copy';
      st.fire('dragover', st.pointTarget);
    }
    return { ok: !!st };
  } catch (e) {
    return { ok: false, error: String(e && e.stack ? e.stack : e) };
  }
})();
''';
}

/// Fires `drop` on the cached point target, then fires the untimed
/// `document.body`/`window` fallback sequence, and returns the full
/// diagnostics object accumulated across every call in the sequence
/// (auto-serialized to JSON by `executeScript`, since this script is
/// synchronous — see [buildFileDropSetupScript] for why that matters).
/// Cleans up the `window.__mwwDrop` stash afterward.
String buildFileDropFinishScript() {
  return '''
(function() {
  var diag = { ok: false, error: null, results: [], pointTargetTag: null };
  try {
    var st = window.__mwwDrop;
    if (st) {
      if (st.pointTarget) st.fire('drop', st.pointTarget);
      ['dragenter', 'dragover', 'drop'].forEach(function(type) {
        st.fire(type, document.body);
        st.fire(type, window);
      });
      diag.results = st.results;
      diag.pointTargetTag = st.pointTargetTag;
      diag.fileCount = st.fileCount;
      diag.types = st.types;
    }
    diag.ok = true;
    delete window.__mwwDrop;
  } catch (e) {
    diag.error = String(e && e.stack ? e.stack : e);
  } finally {
    delete window.__mwwDrop;
  }
  return diag;
})();
''';
}

/// Alternative to the drag/drop simulation above: populates a real
/// `<input type="file">` element already present in the page directly
/// with the dropped files (via `input.files = dataTransfer.files`)
/// and fires `input`/`change` on it, instead of simulating drag
/// events. Modeled on a working fix from a Selenium-based WhatsApp
/// automation script the user had previously built: that script
/// selects the file through WhatsApp's real "Attach → Document" OS
/// file dialog (so it's a fully native, trusted file selection — not
/// a synthetic event at all), and the fix for the exact "preview
/// flashes then disappears" symptom seen here was to strip the
/// `accept` attribute off every `input[type="file"]` on the page
/// (`removeAttribute('accept')`), presumably because WhatsApp Web (or
/// the browser) was silently rejecting the file against an `accept`
/// whitelist. This mirrors that fix for our drag-free path: strip
/// `accept`, then assign the files directly.
///
/// We can't reproduce the "click Attach → Document" step that script
/// uses to open that dialog — `input.click()` on a real `<input
/// type="file">` opens the native OS Open-File dialog, which blocks
/// the WebView2 renderer thread until dismissed, hanging our
/// synchronous script. So instead this assumes WhatsApp Web keeps its
/// file input(s) mounted in the DOM (just hidden) once a chat is
/// open, and populates them without ever opening that dialog — the
/// same technique browser automation tools (e.g. Playwright's
/// `setInputFiles`) use. If `inputCount` in the returned diagnostics
/// is 0, that assumption is wrong and the input only gets mounted
/// after actually opening the attach menu, which would need a
/// different approach.
String buildFileInputPopulateScript(List<DroppedFilePayload> files) {
  final filesJson = jsonEncode(files
      .map((f) => {
            'name': f.name,
            'type': f.mimeType,
            'bytesBase64': f.bytesBase64,
          })
      .toList());

  return '''
(function() {
  var diag = { ok: false, error: null, inputCount: 0, results: [] };
  try {
    var payload = $filesJson;
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

    var inputs = document.querySelectorAll('input[type="file"]');
    diag.inputCount = inputs.length;
    inputs.forEach(function(input, idx) {
      var beforeAccept = input.getAttribute('accept');
      try {
        input.removeAttribute('accept');
        input.files = dataTransfer.files;
        var setCount = input.files ? input.files.length : -1;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        diag.results.push({
          index: idx,
          beforeAccept: beforeAccept,
          filesSetCount: setCount,
          ok: true
        });
      } catch (e) {
        diag.results.push({
          index: idx,
          beforeAccept: beforeAccept,
          ok: false,
          error: String(e && e.stack ? e.stack : e)
        });
      }
    });
    diag.ok = true;
  } catch (e) {
    diag.error = String(e && e.stack ? e.stack : e);
  }
  return diag;
})();
''';
}

/// Number of base64 characters sent per chunk by the
/// `buildChunkedTransfer*` functions (~375 KB of decoded file data
/// per chunk). Kept moderate so a large file (e.g. a big .apk) still
/// completes in a reasonable number of round trips without any single
/// `executeScript` call carrying enough data to risk hitting a
/// message-size limit.
const int fileChunkBase64Size = 500000;

/// First step of the chunked variant of [buildFileInputPopulateScript],
/// needed for large files: embedding a big file's *entire* base64
/// content directly into one `executeScript` call (as the
/// non-chunked functions above do) can silently fail or hang for
/// large files — the script string has to cross the Flutter↔native↔
/// WebView2 boundary in one piece, and that has practical size
/// limits well below what e.g. a large .apk needs. This splits the
/// transfer across many small `executeScript` calls instead: call
/// this once to declare which files are coming, then
/// [buildChunkedTransferAppendScript] repeatedly (once per chunk, for
/// each file) to stream in their base64 content piece by piece, then
/// [buildChunkedTransferFinishScript] once to assemble everything and
/// populate the page's `<input type="file">` (same mechanism as
/// [buildFileInputPopulateScript]). State is threaded between calls
/// via a `window.__mwwChunkBuffer` stash, safe because all these
/// `executeScript` calls run in the same persistent page context.
String buildChunkedTransferInitScript(List<DroppedFilePayload> files) {
  final metaJson = jsonEncode(
    files.map((f) => {'name': f.name, 'type': f.mimeType}).toList(),
  );
  return '''
(function() {
  var meta = $metaJson;
  window.__mwwChunkBuffer = {
    files: meta.map(function(m) {
      return { name: m.name, type: m.type, parts: [] };
    })
  };
  return { ok: true, fileCount: meta.length };
})();
''';
}

/// Appends one chunk of base64 data to file [fileIndex] (its position
/// in the list passed to [buildChunkedTransferInitScript]). Call this
/// repeatedly, in order, for each ~[fileChunkBase64Size]-character
/// slice of that file's base64 content.
String buildChunkedTransferAppendScript(int fileIndex, String chunkBase64) {
  final chunkJson = jsonEncode(chunkBase64);
  return '''
(function() {
  try {
    window.__mwwChunkBuffer.files[$fileIndex].parts.push($chunkJson);
    return { ok: true };
  } catch (e) {
    return { ok: false, error: String(e && e.stack ? e.stack : e) };
  }
})();
''';
}

/// Assembles every file's chunks back into `File` objects, then
/// populates the page's `<input type="file">` element(s) with them —
/// identical logic to [buildFileInputPopulateScript]'s second half.
/// Cleans up `window.__mwwChunkBuffer` afterward either way.
String buildChunkedTransferFinishScript() {
  return '''
(function() {
  var diag = { ok: false, error: null, inputCount: 0, results: [], fileInfo: [] };
  try {
    var buf = window.__mwwChunkBuffer;
    if (!buf) throw new Error('no chunk buffer — init script never ran?');

    var fileObjects = buf.files.map(function(f) {
      var binary = atob(f.parts.join(''));
      var bytes = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      return new File([bytes], f.name, { type: f.type });
    });

    diag.fileInfo = fileObjects.map(function(f) {
      return { name: f.name, type: f.type, size: f.size };
    });

    var dataTransfer = new DataTransfer();
    fileObjects.forEach(function(f) { dataTransfer.items.add(f); });

    var inputs = document.querySelectorAll('input[type="file"]');
    diag.inputCount = inputs.length;
    inputs.forEach(function(input, idx) {
      var beforeAccept = input.getAttribute('accept');
      try {
        input.removeAttribute('accept');
        input.files = dataTransfer.files;
        var setCount = input.files ? input.files.length : -1;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        diag.results.push({
          index: idx,
          beforeAccept: beforeAccept,
          filesSetCount: setCount,
          ok: true
        });
      } catch (e) {
        diag.results.push({
          index: idx,
          beforeAccept: beforeAccept,
          ok: false,
          error: String(e && e.stack ? e.stack : e)
        });
      }
    });
    diag.ok = true;
  } catch (e) {
    diag.error = String(e && e.stack ? e.stack : e);
  } finally {
    delete window.__mwwChunkBuffer;
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
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip': 'application/zip',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'xml': 'application/xml',
    'html': 'text/html',
    'htm': 'text/html',
    'rtf': 'application/rtf',
  };
  return map[ext] ?? 'application/octet-stream';
}
