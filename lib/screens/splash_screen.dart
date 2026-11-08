import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/main_shell.dart';

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
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
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
              _Logo(),
              SizedBox(height: 20),
              Text(
                'ROTA MAX',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppColors.text,
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

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Image.asset(
        'assets/app_icon_rm.png',
        width: 128,
        height: 128,
        semanticLabel: 'Rota Max',
      ),
    );
  }
}
