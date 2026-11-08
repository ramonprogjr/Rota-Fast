import 'package:flutter/material.dart';
import 'package:rota_max/app.dart';
import 'package:rota_max/core/errors/app_error.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/providers/app_state.dart';

/// Abre o banco e carrega o estado. Se falhar, mostra uma tela simples com
/// "Tentar de novo" em vez de fechar o app.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, required this.open, this.showSplash = true});

  /// Abre o banco e devolve o estado já carregado.
  final Future<AppState> Function() open;
  final bool showSplash;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  AppState? _state;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _failed = false);
    try {
      final state = await widget.open();
      if (mounted) {
        setState(() => _state = state);
      }
    } catch (error, stack) {
      await ErrorReporter.report(error, stack, source: 'startup');
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state != null) {
      return RotaMaxApp(state: state, showSplash: widget.showSplash);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: _failed
          ? StartupErrorScreen(onRetry: _start)
          : const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.storage_outlined,
                size: 64,
                color: AppColors.warning,
              ),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível abrir os dados',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Suas entregas continuam guardadas no celular. Feche outros '
                'apps, confira se há espaço livre e tente de novo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
