import 'dart:convert';

/// The three configurable blur scopes for the chat-privacy feature,
/// plus [off].
enum ChatBlurMode { off, all, namesOnly, chatContentOnly }

/// Builds the CSS injected into the loaded WhatsApp Web page for a
/// given [mode].
///
/// ⚠️ IMPORTANT CAVEAT: this app doesn't control WhatsApp Web's
/// markup, and I (the assistant that wrote this) had no way to open
/// the live page and inspect its current DOM while writing it. The
/// selectors below are chosen for being WhatsApp Web's long-standing
/// *structural* landmarks (`#pane-side` for the contact list, `header`
/// elements, ARIA `role="application"` for the message list) rather
/// than its internal component class names (which are hashed/
/// obfuscated and change on nearly every WhatsApp Web deploy) — but
/// "long-standing" is based on training knowledge, not a live check,
/// and WhatsApp can restructure the page at any time.
///
/// If a mode blurs the wrong region (or nothing) after a WhatsApp Web
/// update: open web.whatsapp.com, DevTools → Inspect Element on the
/// area that should be blurred, find its nearest stable
/// `id`/`data-testid`/`role`, and swap the selector below — the rest
/// of the feature (persistence, the toggle button, per-platform JS
/// injection) doesn't need to change.
String buildChatBlurCss(ChatBlurMode mode, {double blurPx = 10}) {
  switch (mode) {
    case ChatBlurMode.off:
      return '';

    case ChatBlurMode.all:
      return '''
#app { filter: blur(${blurPx}px) !important; }
''';

    case ChatBlurMode.namesOnly:
      return '''
/* Left pane: contact/group list — avatars, names, last-message preview */
#pane-side { filter: blur(${blurPx}px) !important; }
/* Right pane header: the currently-open chat's contact name/status */
#main header { filter: blur(${blurPx}px) !important; }
''';

    case ChatBlurMode.chatContentOnly:
      return '''
/* Message list only — not the header, not the composer/input bar */
#main [role="application"] { filter: blur(${blurPx}px) !important; }
''';
  }
}

/// Wraps [css] into a small, idempotent JS snippet that (re)installs a
/// single `<style id="mww-chat-blur">` tag in the loaded page. Always
/// removes any previously-injected tag first, so this is safe to call
/// repeatedly — e.g. every time the mode changes, or right after a
/// fresh page load. Passing an empty/blank [css] clears the blur.
String buildChatBlurInjectionScript(String css) {
  // jsonEncode gives us a correctly-escaped JS string literal (quotes,
  // newlines, backslashes) without hand-rolling escaping rules.
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
