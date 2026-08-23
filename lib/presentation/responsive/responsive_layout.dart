import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../pages/desktop/dashboard_desktop_page.dart';
import '../pages/mobile/dashboard_mobile_page.dart';

/// PRD §6: chooses sidebar-based desktop layout vs. switcher/drawer-based
/// mobile layout. Width breakpoint is a pragmatic proxy — on real
/// desktop/mobile builds this also naturally follows `Platform.isX`, but
/// keeping it width-based additionally makes the two layouts previewable
/// side-by-side on a single desktop window during development.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({super.key});

  static const double _mobileBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final formFactor = constraints.maxWidth < _mobileBreakpoint
            ? FormFactor.mobile
            : FormFactor.desktop;

        return formFactor == FormFactor.desktop
            ? const DashboardDesktopPage()
            : const DashboardMobilePage();
      },
    );
  }
}
