import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/session.dart';

class SessionStoreChanged implements Exception {}

class SessionStore {
  SessionStore(this._storage);

  final FlutterSecureStorage _storage;
  int _revision = 0;
  Future<void> _writes = Future.value();
  int get revision => _revision;
  void invalidateSession() {
    _revision++;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static const accessTokenKey = 'access_token';
  static const refreshTokenKey = 'refresh_token';
  static const onboardedKey = 'is_onboarded';
  static const userIdKey = 'user_id';

  Future<void> saveSession(Session session) {
    final revision = ++_revision;
    return _enqueue(() async {
      if (revision != _revision) {
        throw SessionStoreChanged();
      }
      await Future.wait([
        _storage.write(key: accessTokenKey, value: session.accessToken),
        _storage.write(key: refreshTokenKey, value: session.refreshToken),
        _storage.write(
          key: onboardedKey,
          value: session.isOnboarded.toString(),
        ),
        _storage.write(key: userIdKey, value: session.userId),
      ]);
    });
  }

  Future<void> saveRefreshedSession(
    Session session, {
    required int expectedRevision,
  }) {
    if (expectedRevision != _revision) {
      throw SessionStoreChanged();
    }
    return saveSession(session);
  }

  Future<String?> accessToken() => _storage.read(key: accessTokenKey);

  Future<String?> refreshToken() => _storage.read(key: refreshTokenKey);

  Future<void> clear() {
    invalidateSession();
    return _enqueue(() => _storage.deleteAll());
  }
}
