import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'network/api_client.dart';
import 'auth/auth_controller.dart';

final discoveryLocationProvider = Provider((ref) {
  ref.watch(authControllerProvider.select((state) => state.session?.userId));
  final service = DiscoveryLocationService();
  ref.onDispose(service.invalidate);
  return service;
});

class DiscoveryLocationService {
  DateTime? _lastSent;
  String? _profileId;
  Future<void>? _pending;
  int _generation = 0;

  Future<void> sync(ApiClient api, {required String profileId}) {
    if (_profileId != profileId) {
      _lastSent = null;
      _profileId = profileId;
      _pending = null;
      _generation++;
    }
    if (_pending != null) return _pending!;
    late final Future<void> operation;
    operation = _sync(api, profileId, _generation).whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
    return _pending = operation;
  }

  Future<void> _sync(ApiClient api, String profileId, int generation) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiException('location_services_disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ApiException('location_permission_denied_forever');
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const ApiException('location_permission_denied');
    }
    if (generation != _generation) return;
    if (_lastSent != null &&
        DateTime.now().difference(_lastSent!) < const Duration(minutes: 2)) {
      return;
    }
    var reusedRecent = false;
    try {
      Position? recent;
      try {
        recent = await Geolocator.getLastKnownPosition().timeout(
          const Duration(milliseconds: 500),
        );
      } catch (_) {
        // A missing or unsupported last-known fix falls back to fresh GPS.
      }
      final now = DateTime.now();
      final validRecent =
          recent != null &&
          !recent.isMocked &&
          recent.accuracy.isFinite &&
          recent.accuracy >= 0 &&
          recent.accuracy <= 2000 &&
          now.difference(recent.timestamp) <= const Duration(seconds: 60) &&
          !recent.timestamp.isAfter(now) &&
          recent.latitude.isFinite &&
          recent.longitude.isFinite &&
          recent.latitude.abs() <= 90 &&
          recent.longitude.abs() <= 180;
      reusedRecent = validRecent;
      final position = validRecent
          ? recent
          : await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 20),
              ),
            );
      if (generation != _generation || profileId != _profileId) return;
      if (!position.accuracy.isFinite ||
          position.accuracy < 0 ||
          position.accuracy > 2000) {
        throw const ApiException('location_accuracy_too_low');
      }
      await api.updateLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        capturedAt: position.timestamp,
        isMock: position.isMocked,
      );
      if (generation == _generation) _lastSent = DateTime.now();
    } on TimeoutException {
      throw const ApiException('location_timeout');
    } on ApiException catch (error) {
      if (error.code != 'location_rate_limited' &&
          !(reusedRecent &&
              error.code == 'location_timestamp_older_than_last')) {
        rethrow;
      }
      if (generation == _generation) _lastSent = DateTime.now();
    }
  }

  void invalidate() {
    _lastSent = null;
    _pending = null;
    _generation++;
  }
}
