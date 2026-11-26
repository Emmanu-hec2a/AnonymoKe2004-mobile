class Session {
  const Session({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.isOnboarded,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      userId: json['user_id'] as String,
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      accessExpiresAt: DateTime.parse(json['access_expires_at'] as String),
      refreshExpiresAt: DateTime.parse(json['refresh_expires_at'] as String),
      isOnboarded: json['is_onboarded'] as bool? ?? false,
    );
  }

  final String userId;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final bool isOnboarded;

  Session withOnboarded(bool value) => Session(
    userId: userId,
    accessToken: accessToken,
    refreshToken: refreshToken,
    accessExpiresAt: accessExpiresAt,
    refreshExpiresAt: refreshExpiresAt,
    isOnboarded: value,
  );
}
