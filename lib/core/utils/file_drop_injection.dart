import 'dart:convert';

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

const int fileChunkBase64Size = 500000;

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

String buildInspectAttachMenuIconsScript() {
  return r'''
(function() {
  var icons = document.querySelectorAll('span[data-icon]');
  var out = [];
  icons.forEach(function(el, idx) {
    var clickable = el.closest('li, div[role="button"], button');
    out.push({
      idx: idx,
      dataIcon: el.getAttribute('data-icon'),
      hasClickableAncestor: !!clickable,
      ancestorTag: clickable ? clickable.tagName : null,
      ancestorText: clickable ? (clickable.textContent || '').trim().slice(0, 40) : null
    });
  });
  return { count: out.length, icons: out };
})();
''';
}

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

String buildOpenAttachMenuScript() {
  return r'''
(function() {
  var diag = { ok: false, error: null, clickedAttach: false, rect: null };
  try {
    var attachBtn =
      document.querySelector('button[aria-label="Add file"]') ||
      document.querySelector('span[data-icon="ic-attach-file"]') ||
      document.querySelector('span[data-icon="attach-menu-plus"]') ||
      document.querySelector('span[data-icon="clip"]') ||
      document.querySelector('button[title="Attach"]') ||
      document.querySelector('button[aria-label*="Attach"]');
    if (!attachBtn) throw new Error('attach button not found');

    var target = attachBtn.closest('button') || attachBtn;
    var rect = target.getBoundingClientRect();
    var cx = rect.left + rect.width / 2;
    var cy = rect.top + rect.height / 2;
    diag.rect = { x: cx, y: cy, w: rect.width, h: rect.height };

    function fire(type, Ctor) {
      var opts = {
        bubbles: true,
        cancelable: true,
        view: window,
        clientX: cx,
        clientY: cy,
        button: 0,
        buttons: 1
      };
      target.dispatchEvent(new Ctor(type, opts));
    }

    fire('pointerdown', PointerEvent);
    fire('mousedown', MouseEvent);
    fire('pointerup', PointerEvent);
    fire('mouseup', MouseEvent);
    fire('click', MouseEvent);

    diag.clickedAttach = true;
    diag.ok = true;
  } catch (e) {
    diag.error = String(e && e.stack ? e.stack : e);
  }
  return diag;
})();
''';
}

String buildScanForAttachMenuScript() {
  return r'''
(function() {
  var EXCLUDE_PREFIX = 'document-';
  var EXCLUDE_SUFFIX = '-icon';
  var icons = document.querySelectorAll('span[data-icon]');
  var candidates = [];
  icons.forEach(function(el, idx) {
    var di = el.getAttribute('data-icon') || '';
    if (di.indexOf(EXCLUDE_PREFIX) === 0 && di.indexOf(EXCLUDE_SUFFIX) === di.length - EXCLUDE_SUFFIX.length) {
      return; 
    }
    if (di === 'tail-out' || di === 'wa-wordmark' || di === 'ic-attach-file' || di === 'unknown') {
      return; 
    }
    var clickable = el.closest('li, div[role="button"], button');
    if (!clickable) return;
    var rect = clickable.getBoundingClientRect();
    candidates.push({
      idx: idx,
      dataIcon: di,
      tag: clickable.tagName,
      text: (clickable.textContent || '').trim().slice(0, 40),
      testid: clickable.getAttribute('data-testid'),
      rectW: Math.round(rect.width),
      rectH: Math.round(rect.height)
    });
  });
  return { totalIcons: icons.length, candidates: candidates };
})();
''';
}

/// Mengklik item menu "Document". PENTING: klik pada item ini akan memicu
/// handler internal React WhatsApp yang memanggil `.click()` pada
/// `<input type="file" accept="*">` tersembunyi — dan memanggil `.click()`
/// pada input file SELALU membuka dialog "Open File" bawaan OS, apa pun
/// sumber klik-nya (asli atau sintetis).
///
/// Kita tetap butuh efek "klik menu" ini (supaya state React ter-update dan
/// input accept="*" ter-mount di DOM — tanpa ini `buildFindDocumentInputScript`
/// tidak akan pernah menemukan inputnya), tapi TIDAK butuh efek sampingnya
/// (dialog native terbuka, karena file sudah kita suntikkan sendiri lewat
/// DataTransfer). Solusinya: nonaktifkan sementara
/// `HTMLInputElement.prototype.click` khusus untuk `type="file"` selama
/// event klik ini diproses, lalu kembalikan seperti semula.
String buildClickDocumentMenuItemScript() {
  return r'''
(function() {
  var diag = {
    ok: false,
    error: null,
    found: false,
    candidateCount: 0,
    patchedClick: false
  };
  var originalClick = null;
  try {
    originalClick = HTMLInputElement.prototype.click;
    HTMLInputElement.prototype.click = function () {
      if (this.type === 'file') {
        // No-op: cegah dialog "Open File" bawaan OS terbuka.
        return;
      }
      return originalClick.apply(this, arguments);
    };
    diag.patchedClick = true;

    // Jaga-jaga: kembalikan prototype asli setelah jeda singkat walau
    // terjadi error di tengah jalan, supaya fitur attach manual milik user
    // (klik tombol lampiran sendiri) tidak ikut ter-nonaktifkan permanen.
    setTimeout(function () {
      HTMLInputElement.prototype.click = originalClick;
    }, 1500);

    var items = document.querySelectorAll('button[role="menuitem"]');
    diag.candidateCount = items.length;
    var target = null;

    for (var i = 0; i < items.length; i++) {
      var txt = (items[i].innerText || '').trim();
      if (txt === 'Document' || txt === 'Dokumen') {
        target = items[i];
        break;
      }
    }

    if (!target) throw new Error('Document menuitem not found among ' + diag.candidateCount + ' candidates');
    diag.found = true;

    var rect = target.getBoundingClientRect();
    var cx = rect.left + rect.width / 2;
    var cy = rect.top + rect.height / 2;

    function fire(type, Ctor) {
      var opts = {
        bubbles: true, cancelable: true, view: window,
        clientX: cx, clientY: cy, button: 0, buttons: 1
      };
      target.dispatchEvent(new Ctor(type, opts));
    }
    fire('pointerdown', PointerEvent);
    fire('mousedown', MouseEvent);
    fire('pointerup', PointerEvent);
    fire('mouseup', MouseEvent);
    fire('click', MouseEvent);

    diag.ok = true;
  } catch (e) {
    diag.error = String(e && e.stack ? e.stack : e);
    // Pastikan tetap dikembalikan segera kalau gagal sebelum setTimeout sempat jalan.
    if (originalClick) {
      HTMLInputElement.prototype.click = originalClick;
    }
  }
  return diag;
})();
''';
}

String buildDumpMenuCandidatesScript() {
  return r'''
(function() {
  var items = document.querySelectorAll('li, div[role="button"]');
  var out = [];
  items.forEach(function(el, idx) {
    var rect = el.getBoundingClientRect();
    out.push({
      idx: idx,
      tag: el.tagName,
      innerText: (el.innerText || '').trim().slice(0, 80),
      testid: el.getAttribute('data-testid'),
      ariaLabel: el.getAttribute('aria-label'),
      rectW: Math.round(rect.width),
      rectH: Math.round(rect.height),
      visible: rect.width > 0 && rect.height > 0
    });
  });
  return { count: out.length, items: out };
})();
''';
}

String buildStartMutationWatchScript() {
  return r'''
(function() {
  window.__mwwAddedNodes = [];
  window.__mwwObserver = new MutationObserver(function(records) {
    records.forEach(function(r) {
      r.addedNodes.forEach(function(n) {
        if (n.nodeType === 1) window.__mwwAddedNodes.push(n);
      });
    });
  });
  window.__mwwObserver.observe(document.body, { childList: true, subtree: true });
  return { ok: true };
})();
''';
}


String buildReadMutationWatchScript() {
  return r'''
(function() {
  var nodes = window.__mwwAddedNodes || [];
  if (window.__mwwObserver) window.__mwwObserver.disconnect();

  var report = [];
  nodes.forEach(function(root, rootIdx) {
    if (!root.isConnected) return; // skip nodes removed again since
    var all = root.querySelectorAll ? root.querySelectorAll('*') : [];
    var all2 = [root].concat(Array.prototype.slice.call(all));
    all2.forEach(function(el) {
      var txt = (el.innerText || '').trim();
      if (txt.length === 0 || txt.length > 40) return;
      var rect = el.getBoundingClientRect();
      report.push({
        rootIdx: rootIdx,
        tag: el.tagName,
        text: txt,
        testid: el.getAttribute('data-testid'),
        role: el.getAttribute('role'),
        dataIcon: el.getAttribute('data-icon'),
        rectW: Math.round(rect.width),
        rectH: Math.round(rect.height)
      });
    });
  });

  window.__mwwObserver = null;
  window.__mwwAddedNodes = null;
  return { ok: true, addedRootCount: nodes.length, report: report };
})();
''';
}

/// Mencari input[type="file"] dengan accept="*" (slot untuk "Document"),
/// lalu MENANDAI elemen tersebut secara langsung lewat atribut
/// `data-mww-doc-target`. Ini penting karena WhatsApp Web (React SPA)
/// bisa remount/reorder node input di antara panggilan executeScript,
/// sehingga index numerik (`docIndex`) saja tidak boleh dipercaya lagi
/// saat file benar-benar di-assign nanti di
/// [buildChunkedTransferFinishScript].
String buildFindDocumentInputScript() {
  return r'''
(function() {
  // Bersihkan tag lama kalau ada sisa dari percobaan sebelumnya yang gagal.
  document.querySelectorAll('input[type="file"][data-mww-doc-target]').forEach(function(el) {
    el.removeAttribute('data-mww-doc-target');
  });

  var inputs = document.querySelectorAll('input[type="file"]');
  var out = [];
  var docIndex = -1;
  var docInput = null;
  inputs.forEach(function(inp, idx) {
    var accept = inp.getAttribute('accept');
    out.push({
      idx: idx,
      accept: accept,
      multiple: inp.multiple,
      hidden: inp.hidden || inp.style.display === 'none'
    });
    if (accept === '*' && docIndex === -1) {
      docIndex = idx;
      docInput = inp;
    }
  });

  // Tandai elemen aslinya (bukan cuma index-nya) supaya bisa ditemukan lagi
  // dengan pasti walau DOM di-reorder/di-remount di antara sini dan
  // finish-script.
  if (docInput) {
    docInput.setAttribute('data-mww-doc-target', '1');
  }

  return { count: inputs.length, inputs: out, docIndex: docIndex, tagged: !!docInput };
})();
''';
}

String buildChunkedTransferFinishScript({int? targetInputIndex}) {
  final targetLiteral = targetInputIndex?.toString() ?? 'null';
  return '''
(function() {
  var diag = {
    ok: false,
    error: null,
    inputCount: 0,
    results: [],
    fileInfo: [],
    targetStrategy: null
  };
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

    var allInputs = document.querySelectorAll('input[type="file"]');
    diag.inputCount = allInputs.length;

    var inputs = null;

    // Strategi 1: elemen persis yang sudah ditandai oleh
    // buildFindDocumentInputScript — kebal terhadap reorder DOM karena kita
    // mencari elemen itu sendiri, bukan posisinya di NodeList.
    var tagged = document.querySelector('input[type="file"][data-mww-doc-target]');
    if (tagged) {
      inputs = [tagged];
      diag.targetStrategy = 'tagged';
    }

    // Strategi 2: kalau tag sudah hilang (node lama sudah diganti total oleh
    // React), scan ulang input dengan accept="*" secara segar.
    if (!inputs) {
      for (var i = 0; i < allInputs.length; i++) {
        if (allInputs[i].getAttribute('accept') === '*') {
          inputs = [allInputs[i]];
          diag.targetStrategy = 'rescan-accept-star';
          break;
        }
      }
    }

    // Strategi 3: fallback ke index lama yang dikirim dari Dart (bisa saja
    // sudah basi kalau DOM berubah, tapi lebih baik daripada tidak ada).
    var targetIdx = $targetLiteral;
    if (!inputs && targetIdx !== null && allInputs[targetIdx]) {
      inputs = [allInputs[targetIdx]];
      diag.targetStrategy = 'stale-index';
    }

    // Strategi 4: tidak ada target spesifik sama sekali (kasus drop
    // gambar/video biasa, targetInputIndex memang null dari awal) —
    // broadcast ke semua input file yang ada.
    if (!inputs) {
      inputs = Array.prototype.slice.call(allInputs);
      diag.targetStrategy = 'broadcast-all';
    }

    inputs.forEach(function(input) {
      var idx = Array.prototype.indexOf.call(allInputs, input);
      var beforeAccept = input.getAttribute('accept');
      try {
        input.removeAttribute('accept');
        input.removeAttribute('data-mww-doc-target');
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