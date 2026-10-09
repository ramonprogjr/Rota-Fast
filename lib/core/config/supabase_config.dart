import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  const SupabaseConfig._();

  static const String _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String _anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String _serviceRoleKey = String.fromEnvironment(
    'SUPABASE_SERVICE_ROLE_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  static String get url => _url;

  static String get anonKey => _anonKey;

  static String get serviceRoleKey => _serviceRoleKey;

  static Future<void> initialize() async {
    if (!isConfigured) {
      return;
    }

    await Supabase.initialize(
      url: _url,
      anonKey: _anonKey,
    );
  }
}