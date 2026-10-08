import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/screens/home_screen.dart';
import 'package:rota_pizza/screens/splash_screen.dart';

class RotaPizzaApp extends StatelessWidget {
  const RotaPizzaApp({
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
        home: showSplash ? const SplashScreen() : const HomeScreen(),
      ),
    );
  }
}
