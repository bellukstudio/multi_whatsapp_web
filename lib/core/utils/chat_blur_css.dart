import 'dart:convert';

enum ChatBlurMode { off, all, namesOnly, chatContentOnly }

String buildChatBlurCss(
  ChatBlurMode mode, {
  double blurPx = 10,
  bool hoverReveal = true,
}) {
  if (mode == ChatBlurMode.off) return '';

  const transition = 'transition: filter 0.15s ease;';

  // Tiap baris chat di sidebar. WhatsApp Web menandai baris list dengan
  // role="listitem" (ARIA) — dipakai karena lebih stabil lintas versi
  // dibanding class/data-testid yang sering berubah tiap update WA.
  String paneSideRule() => '''
#pane-side div[role="listitem"] {
  filter: blur(${blurPx}px) !important;
  $transition
}
${hoverReveal ? '''
#pane-side div[role="listitem"]:hover {
  filter: blur(0px) !important;
}
''' : ''}
''';

  // Nama kontak + status di header chat aktif. Cuma satu elemen per
  // sesi, jadi hover-nya untuk seluruh header (bukan per baris).
  String headerRule() => '''
#main header {
  filter: blur(${blurPx}px) !important;
  $transition
}
${hoverReveal ? '''
#main header:hover {
  filter: blur(0px) !important;
}
''' : ''}
''';

  // Tiap bubble pesan di jendela chat. role="row" dipakai WA untuk
  // setiap baris pesan di dalam role="application".
  String messagesRule() => '''
#main [role="application"] div[role="row"] {
  filter: blur(${blurPx}px) !important;
  $transition
}
${hoverReveal ? '''
#main [role="application"] div[role="row"]:hover {
  filter: blur(0px) !important;
}
''' : ''}
''';

  switch (mode) {
    case ChatBlurMode.off:
      return '';
    case ChatBlurMode.all:
      return paneSideRule() + headerRule() + messagesRule();
    case ChatBlurMode.namesOnly:
      return paneSideRule() + headerRule();
    case ChatBlurMode.chatContentOnly:
      return messagesRule();
  }
}

String buildChatBlurInjectionScript(String css) {
  final encoded = jsonEncode(css);
  return '''
(function() {
  try {
    var old = document.getElementById('mww-chat-blur');
    if (old) old.remove();
    var css = $encoded;
    if (css && css.length > 0) {
      var style = document.createElement('style');
      style.id = 'mww-chat-blur';
      style.textContent = css;
      document.head.appendChild(style);
    }
  } catch (e) {}
})();
''';
}