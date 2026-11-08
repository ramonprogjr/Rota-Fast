import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/main_shell.dart';
import 'package:rota_max/screens/splash_screen.dart';

class RotaMaxApp extends StatelessWidget {
  const RotaMaxApp({
    super.key,
    required this.state,
    this.showSplash = true,
  });

  final AppState state;
  final bool showSplash;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: showSplash ? const SplashScreen() : const MainShell(),
      ),
    );
  }
}
