import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/update/update_cubit.dart';
import 'update_reminder_dialogs.dart';

/// Wraps the app's home screen and triggers the cross-platform update
/// check once, right after the first frame, showing an optional
/// "update available" reminder or a non-dismissible "update required"
/// dialog as appropriate.
///
/// See `UpdateCubit` for the platform-agnostic Firestore-via-firedart
/// check that backs this — it behaves identically on Android, iOS,
/// macOS, Windows and Linux.
class UpdateReminderGate extends StatefulWidget {
  const UpdateReminderGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateReminderGate> createState() => _UpdateReminderGateState();
}

class _UpdateReminderGateState extends State<UpdateReminderGate> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<UpdateCubit>().checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<UpdateCubit, UpdateState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) async {
        if (_dialogShown) return;
        final cubit = context.read<UpdateCubit>();

        if (state.status == UpdateStatus.required && state.info != null) {
          _dialogShown = true;
          await showMandatoryUpdateDialog(
            context,
            info: state.info!,
            currentVersion: state.currentVersion,
            updateUrl: cubit.updateUrlForThisPlatform(),
          );
          _dialogShown = false;
        } else if (state.status == UpdateStatus.available &&
            state.info != null) {
          _dialogShown = true;
          await showOptionalUpdateDialog(
            context,
            info: state.info!,
            currentVersion: state.currentVersion,
            updateUrl: cubit.updateUrlForThisPlatform(),
            onLater: () => cubit.skipCurrentVersion(),
          );
          _dialogShown = false;
        }
      },
      child: widget.child,
    );
  }
}
