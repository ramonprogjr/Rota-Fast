enum AuthProvider { email, google, apple }

enum AppRole { driver, manager, admin }

class AppUser {
  AppUser({
    this.id,
    required this.companyId,
    required this.fullName,
    required this.email,
    required this.role,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String? id;
  final String companyId;
  final String fullName;
  final String email;
  final AppRole role;
  final bool isActive;
  final DateTime createdAt;

  bool get canManageTeam => role == AppRole.manager || role == AppRole.admin;

  AppUser copyWith({
    String? id,
    String? companyId,
    String? fullName,
    String? email,
    AppRole? role,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'full_name': fullName,
      'email': email,
      'role': role.name,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AppUser.fromMap(Map<String, Object?> map) {
    return AppUser(
      id: map['id'] as String?,
      companyId: map['company_id'] as String? ?? '',
      fullName: map['full_name'] as String? ?? 'Usuário',
      email: map['email'] as String? ?? '',
      role: AppRole.values.firstWhere(
        (item) => item.name == map['role'],
        orElse: () => AppRole.driver,
      ),
      isActive: (map['is_active'] as int?) == 1 ||
          (map['is_active'] as bool? ?? false),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class UserSession {
  UserSession({
    this.id,
    required this.user,
    required this.provider,
    required this.token,
    required this.expiresAt,
  });

  final String? id;
  final AppUser user;
  final AuthProvider provider;
  final String token;
  final DateTime expiresAt;

  bool get isValid => expiresAt.isAfter(DateTime.now());

  UserSession copyWith({
    String? id,
    AppUser? user,
    AuthProvider? provider,
    String? token,
    DateTime? expiresAt,
  }) {
    return UserSession(
      id: id ?? this.id,
      user: user ?? this.user,
      provider: provider ?? this.provider,
      token: token ?? this.token,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'user_id': user.id,
      'provider': provider.name,
      'token': token,
      'expires_at': expiresAt.toIso8601String(),
    };
  }
}
