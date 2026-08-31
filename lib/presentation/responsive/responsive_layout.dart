import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../pages/desktop/dashboard_desktop_page.dart';
import '../pages/mobile/dashboard_mobile_page.dart';

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
