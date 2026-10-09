import 'package:rota_pizza/models/auth.dart';

abstract class AuthRepository {
  Future<UserSession?> signInWithEmail({
    required String email,
    required String password,
  });

  Future<UserSession?> signInWithProvider({
    required AuthProvider provider,
    required String providerId,
  });

  Future<UserSession?> currentSession();
  Future<void> signOut(String userId);
}
