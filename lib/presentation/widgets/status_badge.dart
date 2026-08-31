import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.size = 10});

  final AccountConnectionStatus status;
  final double size;

  Color _color(BuildContext context) {
    switch (status) {
      case AccountConnectionStatus.connected:
        return Colors.green;
      case AccountConnectionStatus.connecting:
        return Colors.amber;
      case AccountConnectionStatus.disconnected:
      case AccountConnectionStatus.loggedOut:
        return Colors.red;
      case AccountConnectionStatus.error:
        return Colors.redAccent.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _color(context), shape: BoxShape.circle),
    );
  }
}
