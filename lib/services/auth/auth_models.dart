import 'dart:convert';

class AuthUser {
  const AuthUser({required this.id, required this.email, required this.name});

  final int id;
  final String email;
  final String name;

  static AuthUser? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final email = raw['email'];
    final name = raw['name'];
    if (id is! num || email is! String || name is! String) return null;
    return AuthUser(id: id.toInt(), email: email, name: name);
  }

  Map<String, Object?> toJson() => {'id': id, 'email': email, 'name': name};
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.user,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final AuthUser user;

  AuthSession copyWith({AuthUser? user}) => AuthSession(
        accessToken: accessToken,
        accessExpiresAt: accessExpiresAt,
        refreshToken: refreshToken,
        refreshExpiresAt: refreshExpiresAt,
        user: user ?? this.user,
      );

  /// Membaca bagian `data` dari respons login/register/refresh. null bila
  /// ada field yang hilang atau salah tipe.
  static AuthSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final access = raw['access_token'];
    final refresh = raw['refresh_token'];
    final accessExp = _date(raw['access_expires_at']);
    final refreshExp = _date(raw['refresh_expires_at']);
    final user = AuthUser.fromJson(raw['user']);
    if (access is! String ||
        refresh is! String ||
        access.isEmpty ||
        refresh.isEmpty ||
        accessExp == null ||
        refreshExp == null ||
        user == null) {
      return null;
    }
    return AuthSession(
      accessToken: access,
      accessExpiresAt: accessExp,
      refreshToken: refresh,
      refreshExpiresAt: refreshExp,
      user: user,
    );
  }

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        'access_expires_at': accessExpiresAt.toUtc().toIso8601String(),
        'refresh_token': refreshToken,
        'refresh_expires_at': refreshExpiresAt.toUtc().toIso8601String(),
        'user': user.toJson(),
      };

  String encode() => jsonEncode(toJson());

  static AuthSession? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
}
