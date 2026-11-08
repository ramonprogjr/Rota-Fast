import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/data/repositories/error_log_repository.dart';
import 'package:rota_max/services/geocoding_service.dart';
import 'package:sqflite/sqflite.dart';

/// Erro com mensagem pronta para o motorista.
class AppError implements Exception {
  const AppError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Converte qualquer erro numa frase curta em português. Nunca mostra
/// detalhe técnico: o detalhe vai para o [ErrorReporter].
String friendlyMessage(Object error, {String? fallback}) {
  final generic = fallback ?? 'Algo deu errado. Tente de novo.';
  if (error is AppError) {
    return error.message;
  }
  if (error is GeocodingException) {
    return error.message;
  }
  if (error is InvalidTransition) {
    return error.toString();
  }
  if (error is ArgumentError) {
    final text = error.message;
    return text is String && text.isNotEmpty ? text : generic;
  }
  if (error is StateError) {
    // As mensagens de StateError do app já são para o motorista.
    return error.message.isEmpty ? generic : error.message;
  }
  if (error is DatabaseException) {
    return 'Não foi possível gravar no aparelho. Tente de novo.';
  }
  if (error is TimeoutException) {
    return 'Demorou demais para responder. Tente de novo.';
  }
  if (error is SocketException || error is HttpException) {
    return 'Sem internet agora. O que já está salvo continua funcionando.';
  }
  return generic;
}

/// Liga os ganchos globais: erro de widget, erro assíncrono fora de zona e
/// (em produção) troca a tela vermelha por um aviso simples. Nada derruba o
/// app; tudo vai para o [ErrorReporter].
void installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorReporter.report(
      details.exception,
      details.stack,
      source: 'flutter',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReporter.report(error, stack, source: 'platform');
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const Material(
          color: Color(0xFF1A2233),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Esta parte da tela não carregou. Volte e tente de novo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFEAF0FF)),
              ),
            ),
          ),
        );
  }
}

/// Guarda os últimos erros no aparelho (sem dados pessoais) e nunca deixa
/// o registro derrubar o app.
class ErrorReporter {
  ErrorReporter._();

  static ErrorLogRepository? sink;

  /// Para testes: quantos erros chegaram aqui desde o início.
  static int reported = 0;

  static Future<void> report(
    Object error,
    StackTrace? stack, {
    String source = 'app',
  }) async {
    reported++;
    if (kDebugMode) {
      debugPrint('[$source] ${error.runtimeType}: $error');
    }
    try {
      await sink?.record(
        source: source,
        errorType: error.runtimeType.toString(),
        location: _location(stack),
      );
    } catch (_) {
      // O registro de erro não pode gerar outro erro.
    }
  }

  /// Primeiro trecho do código do app na pilha (arquivo:linha). Não leva
  /// mensagens, que podem conter nome ou endereço de cliente.
  static String? _location(StackTrace? stack) {
    if (stack == null) {
      return null;
    }
    final match = RegExp(r'package:rota_max/[^\s)]+')
        .firstMatch(stack.toString());
    return match?.group(0);
  }
}
