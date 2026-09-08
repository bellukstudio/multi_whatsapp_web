import 'dart:convert';

enum ChatBlurMode { off, all, namesOnly, chatContentOnly }

String buildChatBlurCss(
  ChatBlurMode mode, {
  double blurPx = 10,
  bool hoverReveal = true,
}) {
  if (mode == ChatBlurMode.off) return '';

  const transition = 'transition: filter 0.15s ease;';

  // Tiap baris chat di sidebar. Dikonfirmasi lewat DevTools:
  // data-testid="cell-frame-container" -> 20 match di list chat aktif.
  // (role="listitem" TIDAK dipakai WA Web versi sekarang — dulu sempat
  // dipakai tapi sudah diganti data-testid custom.)
  String paneSideRule() => '''
#pane-side div[data-testid="cell-frame-container"] {
  filter: blur(${blurPx}px) !important;
  $transition
}
${hoverReveal ? '''
#pane-side div[data-testid="cell-frame-container"]:hover {
  filter: blur(0px) !important;
}
''' : ''}
''';

  // Nama kontak + status di header chat aktif. Selector ini yang sudah
  // terbukti jalan dari awal — tidak diubah.
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

  // Tiap bubble pesan di jendela chat. Dikonfirmasi lewat DevTools:
  // data-testid="msg-container" -> 10 match (persis jumlah bubble
  // pesan yang ke-render, lebih presisi dibanding [role="row"] yang
  // ikut nangkep date-separator/system message).
  String messagesRule() => '''
#main div[data-testid="msg-container"] {
  filter: blur(${blurPx}px) !important;
  $transition
}
${hoverReveal ? '''
#main div[data-testid="msg-container"]:hover {
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