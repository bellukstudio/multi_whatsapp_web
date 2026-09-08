import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/utils/chat_blur_css.dart';

class BlurState extends Equatable {
  const BlurState({this.mode = ChatBlurMode.off});

  final ChatBlurMode mode;

  BlurState copyWith({ChatBlurMode? mode}) => BlurState(mode: mode ?? this.mode);

  @override
  List<Object?> get props => [mode];
}

/// Desired chat-privacy blur mode, persisted across launches (via the
/// same secure storage used by the account-lock feature) and applied
/// to the active WebView session by `ChatBlurOverlay`.
///
/// See `chat_blur_css.dart` for the actual CSS built per mode, and
/// `WebViewSessionHandle.supportsChatBlur` for which platforms can
/// currently apply it at all — right now that's Windows, Linux, and
/// (once revived) the same-process Android native-webview path;
/// mobile's current cross-process SlotEmbed path, macOS, and iOS are
/// not wired yet (see the TODOs in their respective session-handle
/// files).
class BlurCubit extends Cubit<BlurState> {
  BlurCubit({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      super(const BlurState()) {
    _restore();
  }

  final FlutterSecureStorage _storage;
  static const _modeKey = 'chat_blur_mode';

  /// Remembers the last non-off mode so the floating button's quick
  /// tap can toggle back to it, independent of whatever mode was last
  /// explicitly picked from the long-press menu.
  ChatBlurMode _lastNonOffMode = ChatBlurMode.all;

  Future<void> _restore() async {
    final saved = await _storage.read(key: _modeKey);
    final mode = ChatBlurMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ChatBlurMode.off,
    );
    if (mode != ChatBlurMode.off) _lastNonOffMode = mode;
    if (!isClosed) emit(BlurState(mode: mode));
  }

  Future<void> setMode(ChatBlurMode mode) async {
    if (mode != ChatBlurMode.off) _lastNonOffMode = mode;
    emit(state.copyWith(mode: mode));
    await _storage.write(key: _modeKey, value: mode.name);
  }

  /// Quick on/off toggle for the floating button's short tap — reuses
  /// whichever non-off mode was last active/picked.
  Future<void> quickToggle() {
    return setMode(
      state.mode == ChatBlurMode.off ? _lastNonOffMode : ChatBlurMode.off,
    );
  }
}
