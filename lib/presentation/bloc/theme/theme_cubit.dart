import 'package:flutter_bloc/flutter_bloc.dart';

/// PRD §16: Dark/light theme toggle, shared across desktop and mobile.
enum AppThemeMode { light, dark, system }

class ThemeCubit extends Cubit<AppThemeMode> {
  ThemeCubit() : super(AppThemeMode.system);

  void setMode(AppThemeMode mode) => emit(mode);
}
