import 'package:rota_pizza/data/repositories/auth_repository.dart';
import 'package:rota_pizza/models/auth.dart';

class MemoryAuthRepository implements AuthRepository {
  MemoryAuthRepository({List<AppUser>? seedUsers})
      : _users = {
          for (final user in (seedUsers ?? <AppUser>[]))
            if (user.id != null) user.id!: user,
        };

  final Map<String, AppUser> _users;
  UserSession? _session;

  @override
  Future<UserSession?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final user = _users.values.firstWhere(
      (item) => item.email.trim().toLowerCase() == email.trim().toLowerCase(),
      orElse: () => throw StateError('Usuário não encontrado'),
    );

    if (password.isEmpty) {
      throw StateError('Senha inválida');
    }

    final session = UserSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      user: user,
      provider: AuthProvider.email,
      token: 'token_${DateTime.now().millisecondsSinceEpoch}',
      expiresAt: DateTime.now().add(const Duration(hours: 8)),
    );
    _session = session;
    return session;
  }

  @override
  Future<UserSession?> signInWithProvider({
    required AuthProvider provider,
    required String providerId,
  }) async {
    final user = _users.values.firstWhere(
      (item) => item.id == providerId || item.email == providerId,
      orElse: () => throw StateError('Usuário não encontrado'),
    );

    final session = UserSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      user: user,
      provider: provider,
      token: 'provider_${DateTime.now().millisecondsSinceEpoch}',
      expiresAt: DateTime.now().add(const Duration(hours: 8)),
    );
    _session = session;
    return session;
  }

  @override
  Future<UserSession?> currentSession() async => _session;

  @override
  Future<void> signOut(String userId) async {
    if (_session != null && _session!.user.id == userId) {
      _session = null;
    }
  }
}
