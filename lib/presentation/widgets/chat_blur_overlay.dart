import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/utils/chat_blur_css.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/webview_adapter.dart';
import '../bloc/blur/blur_cubit.dart';
import '../bloc/session/session_cubit.dart';
import 'webview_container.dart';

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
          child: WebViewContainer(
            account: account,
            sessionState: sessionState,
          ),
        );
      },
    );
  }
}

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

