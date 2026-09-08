import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/utils/chat_blur_css.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/webview_adapter.dart';
import '../bloc/blur/blur_cubit.dart';
import '../bloc/session/session_cubit.dart';
import 'webview_container.dart';

/// Wraps [WebViewContainer], (re)injecting the chat-privacy blur CSS
/// into the loaded page whenever the desired [BlurCubit] mode changes,
/// or the active session's [WebViewSessionHandle] changes (new account
/// selected, reconnect, etc.) — and shows the floating blur-mode
/// toggle button (bottom-left, tap to quick-toggle, long-press to pick
/// a specific mode).
class ChatBlurOverlay extends StatelessWidget {
  const ChatBlurOverlay({
    super.key,
    required this.account,
    required this.sessionState,
  });

  final Account? account;
  final SessionState sessionState;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BlurCubit, BlurState>(
      listenWhen: (previous, current) => previous.mode != current.mode,
      listener: (context, state) {
        sessionState.handle?.setChatBlurCss(buildChatBlurCss(state.mode));
      },
      builder: (context, state) {
        return _ApplyOnHandleChange(
          handle: sessionState.handle,
          mode: state.mode,
          child: Stack(
            children: [
              Positioned.fill(
                child: WebViewContainer(
                  account: account,
                  sessionState: sessionState,
                ),
              ),
              if (account != null && (sessionState.handle?.supportsChatBlur ?? false))
                const Positioned(left: 16, bottom: 16, child: _BlurToggleButton()),
            ],
          ),
        );
      },
    );
  }
}

/// Re-applies the current mode's CSS whenever [handle] changes
/// identity — new account selected, session recreated after a
/// reconnect, etc. The [BlocConsumer] in [ChatBlurOverlay] only reacts
/// to the blur *mode* changing, not to the session handle changing
/// while the mode stays the same, so this covers the other case.
class _ApplyOnHandleChange extends StatefulWidget {
  const _ApplyOnHandleChange({
    required this.handle,
    required this.mode,
    required this.child,
  });

  final WebViewSessionHandle? handle;
  final ChatBlurMode mode;
  final Widget child;

  @override
  State<_ApplyOnHandleChange> createState() => _ApplyOnHandleChangeState();
}

class _ApplyOnHandleChangeState extends State<_ApplyOnHandleChange> {
  @override
  void initState() {
    super.initState();
    widget.handle?.setChatBlurCss(buildChatBlurCss(widget.mode));
  }

  @override
  void didUpdateWidget(covariant _ApplyOnHandleChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.handle, widget.handle)) {
      widget.handle?.setChatBlurCss(buildChatBlurCss(widget.mode));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _BlurToggleButton extends StatelessWidget {
  const _BlurToggleButton();

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<BlurCubit>().state.mode;
    final isOn = mode != ChatBlurMode.off;

    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.read<BlurCubit>().quickToggle(),
        onLongPress: () => _showModePicker(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            isOn ? Icons.blur_on : Icons.blur_off,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  void _showModePicker(BuildContext context) {
    final cubit = context.read<BlurCubit>();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Blur Chat'),
            ),
            _ModeTile(
              cubit: cubit,
              mode: ChatBlurMode.off,
              label: 'Nonaktif',
              icon: Icons.blur_off,
            ),
            _ModeTile(
              cubit: cubit,
              mode: ChatBlurMode.all,
              label: 'Blur Semua',
              icon: Icons.blur_on,
            ),
            _ModeTile(
              cubit: cubit,
              mode: ChatBlurMode.namesOnly,
              label: 'Blur Nama Saja',
              icon: Icons.badge_outlined,
            ),
            _ModeTile(
              cubit: cubit,
              mode: ChatBlurMode.chatContentOnly,
              label: 'Blur Isi Chat Saja',
              icon: Icons.chat_bubble_outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.cubit,
    required this.mode,
    required this.label,
    required this.icon,
  });

  final BlurCubit cubit;
  final ChatBlurMode mode;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final selected = cubit.state.mode == mode;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: selected ? const Icon(Icons.check, size: 18) : null,
      onTap: () {
        Navigator.pop(context);
        cubit.setMode(mode);
      },
    );
  }
}
