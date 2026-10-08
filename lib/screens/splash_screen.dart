import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/screens/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(AppConstants.splashDuration, _goHome);
  }

  void _goHome() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('RF', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: AppColors.cream)),
              SizedBox(height: 12),
              Text(
                'ROTA FOOD',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppColors.cream,
                ),
              ),
              SizedBox(height: 8),
              Text(
                AppConstants.tagline,
                style: TextStyle(fontSize: 18, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
