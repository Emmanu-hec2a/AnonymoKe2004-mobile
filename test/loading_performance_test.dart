import 'dart:async';
import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/auth/session.dart';
import 'package:anonymoke/core/location_service.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/routing/app_router.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/core/widgets/profile_image.dart';
import 'package:anonymoke/features/home/presentation/discover_screen.dart';
import 'package:anonymoke/features/home/presentation/inbox_controller.dart';
import 'package:anonymoke/features/home/presentation/profile_controller.dart';
import 'package:anonymoke/features/home/presentation/widgets/discovery_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'discover_live_test.dart'
    show FakeApi, FakeGeo, FakeLocation, firstCard, secondCard, pumpDiscover;

class LoadingApi extends FakeApi {
  Completer<ProfileSummary>? profileGate;
  Completer<List<EntitlementSummary>>? perksGate;
  Completer<List<MediaAssetSummary>>? mediaGate;
  Completer<MatchPage>? matchesGate;
  Completer<SwipeOutcome>? swipeGate;
  bool consentStarted = false, likesStarted = false;
  int profileReads = 0;
  @override
  Future<ProfileSummary> profile() async {
    profileReads++;
    return profileGate == null ? super.profile() : profileGate!.future;
  }

  @override
  Future<List<ConsentSummary>> consents() {
    consentStarted = true;
    return super.consents();
  }

  @override
  Future<List<EntitlementSummary>> entitlements() async =>
      perksGate == null ? [] : perksGate!.future;
  @override
  Future<List<MediaAssetSummary>> mediaStatus() async =>
      mediaGate == null ? [] : mediaGate!.future;
  @override
  Future<MatchPage> matchesPage({String? cursor}) async =>
      matchesGate == null ? const MatchPage(items: []) : matchesGate!.future;
  @override
  Future<LikesPage> incomingLikes({String? cursor}) async {
    likesStarted = true;
    return const LikesPage(count: 6);
  }

  @override
  Future<SwipeOutcome> swipe({
    required String profileId,
    required String action,
    String? clientSwipeId,
  }) {
    if (swipeGate == null) {
      return super.swipe(
        profileId: profileId,
        action: action,
        clientSwipeId: clientSwipeId,
      );
    }
    swipes.add(clientSwipeId!);
    return swipeGate!.future;
  }
}

class CachedGeo extends FakeGeo {
  Completer<Position>? gpsGate;
  Position? recent;
  int gpsReads = 0;
  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => recent;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    gpsReads++;
    return gpsGate?.future ??
        super.getCurrentPosition(locationSettings: locationSettings);
  }
}

class CacheAuth extends AuthController {
  @override
  AuthState build() => const AuthState();
  void signIn(String user) => state = AuthState(
    session: Session(
      userId: user,
      accessToken: 'test-access',
      refreshToken: 'test-refresh',
      accessExpiresAt: DateTime.utc(2030),
      refreshExpiresAt: DateTime.utc(2030),
      isOnboarded: true,
    ),
  );
}

class NewerLocationApi extends FakeApi {
  @override
  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
    bool isMock = false,
  }) async {
    locationWrites++;
    throw const ApiException('location_timestamp_older_than_last');
  }
}

Position fix({int age = 10, bool mock = false, double accuracy = 30}) =>
    Position.fromMap({
      'latitude': -1.28,
      'longitude': 36.82,
      'timestamp': DateTime.now()
          .subtract(Duration(seconds: age))
          .millisecondsSinceEpoch,
      'accuracy': accuracy,
      'altitude': 0.0,
      'heading': 0.0,
      'speed': 0.0,
      'speed_accuracy': 0.0,
      'altitude_accuracy': 0.0,
      'heading_accuracy': 0.0,
      'is_mocked': mock,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account changes clear the old account image cache', () {
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(CacheAuth.new)],
    );
    final auth = container.read(authControllerProvider.notifier) as CacheAuth;
    auth.signIn('one');
    final previous = container.read(profileImageCacheProvider);
    previous.resolve('https://media.test/a.jpg?X-Amz-Signature=old');
    auth.signIn('two');
    final current = container.read(profileImageCacheProvider);
    expect(identical(previous, current), false);
    const fresh = 'https://media.test/a.jpg?X-Amz-Signature=fresh';
    expect(previous.resolve(fresh), fresh);
    container.dispose();
  });

  test('concurrent location requests share one validated update', () async {
    final previous = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = CachedGeo()..recent = fix();
    addTearDown(() => GeolocatorPlatform.instance = previous);
    final api = FakeApi(), service = DiscoveryLocationService();
    await Future.wait([
      service.sync(api, profileId: 'one'),
      service.sync(api, profileId: 'one'),
    ]);
    expect(api.locationWrites, 1);
  });

  test(
    'invalidating a pending GPS request prevents sending its coordinates',
    () async {
      final previous = GeolocatorPlatform.instance;
      final geo = CachedGeo()..gpsGate = Completer();
      GeolocatorPlatform.instance = geo;
      addTearDown(() => GeolocatorPlatform.instance = previous);
      final api = FakeApi(), service = DiscoveryLocationService();
      final pending = service.sync(api, profileId: 'one');
      await Future<void>.delayed(Duration.zero);
      expect(geo.gpsReads, 1);
      service.invalidate();
      geo.gpsGate!.complete(fix());
      await pending;
      expect(api.locationWrites, 0);
    },
  );

  test(
    'a newer server location avoids repeating a valid cached update',
    () async {
      final previous = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = CachedGeo()..recent = fix();
      addTearDown(() => GeolocatorPlatform.instance = previous);
      final api = NewerLocationApi(), service = DiscoveryLocationService();
      await service.sync(api, profileId: 'one');
      await service.sync(api, profileId: 'one');
      expect(api.locationWrites, 1);
    },
  );

  test('signed image URLs reuse cache identity within a bounded lifetime', () {
    var now = DateTime.utc(2026, 11, 18, 12);
    final cache = ProfileImageCache(now: () => now);
    const first =
        'https://media.test/photo.jpg?X-Amz-Date=20261118T120000Z&X-Amz-Expires=300&X-Amz-Signature=one';
    const next =
        'https://media.test/photo.jpg?X-Amz-Date=20261118T120030Z&X-Amz-Expires=300&X-Amz-Signature=two';
    expect(cache.resolve(first), first);
    now = now.add(const Duration(seconds: 30));
    expect(cache.resolve(next), first);
    now = now.add(const Duration(minutes: 3));
    expect(cache.resolve(next), next);
    cache.clear();
  });

  test(
    'cache keeps image variants separate and does not share account state',
    () {
      final one = ProfileImageCache(), two = ProfileImageCache();
      const a = 'https://media.test/a.jpg?X-Amz-Signature=one';
      const b = 'https://media.test/a.jpg?X-Amz-Signature=two';
      one.resolve(a);
      expect(two.resolve(b), b);
      expect(
        ProfileImageCache.identity('$a&version=2'),
        isNot(ProfileImageCache.identity(a)),
      );
      one.clear();
      expect(one.resolve(b), b);
    },
  );

  test('Profile publishes before premium and media requests finish', () async {
    final api = LoadingApi()
      ..perksGate = Completer()
      ..mediaGate = Completer();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    final subscription = container.listen(profileProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(profileProvider).profile?.alias, 'Me');
    expect(api.perksGate!.isCompleted, false);
    api.perksGate!.complete([]);
    api.mediaGate!.complete([]);
    await container.read(profileProvider.notifier).refresh();
    subscription.close();
    container.dispose();
  });

  test('likes load while the matches request is still pending', () async {
    final api = LoadingApi()..matchesGate = Completer();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    final subscription = container.listen(inboxProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(api.likesStarted, true);
    expect(container.read(inboxProvider).likes?.count, 6);
    expect(container.read(inboxProvider).loading, true);
    api.matchesGate!.complete(const MatchPage(items: []));
    await container.read(inboxProvider.notifier).refresh();
    subscription.close();
    container.dispose();
  });

  testWidgets(
    'Discover requests consents before the profile request finishes',
    (tester) async {
      final api = LoadingApi()..profileGate = Completer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            discoveryLocationProvider.overrideWithValue(FakeLocation()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: BackendDiscoverScreen()),
          ),
        ),
      );
      await tester.pump();
      expect(api.consentStarted, true);
      api.profileGate!.complete(await FakeApi().profile());
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryDeck), findsOneWidget);
    },
  );

  testWidgets('swipe moves before acknowledgement and restores a failed card', (
    tester,
  ) async {
    final api = LoadingApi();
    await pumpDiscover(tester, api, FakeLocation());
    api.swipeGate = Completer();
    final deck = tester.state<DiscoveryDeckState>(find.byType(DiscoveryDeck));
    final label = find.text(firstCard.alias).first;
    final resting = tester.getTopLeft(label).dx;
    unawaited(deck.swipe(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(label).dx, greaterThan(resting + 20));
    expect(api.swipes.length, 1);
    api.swipeGate!.completeError(const ApiException('network_error'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DiscoveryDeck>(find.byType(DiscoveryDeck)).itemId,
      firstCard.profileId,
    );
    expect(
      tester.getTopLeft(find.text(firstCard.alias).first).dx,
      closeTo(resting, .1),
    );
  });

  testWidgets('tab navigation preserves the Discover deck and loaded data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = LoadingApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          discoveryLocationProvider.overrideWithValue(FakeLocation()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(routerProvider);
            return MaterialApp.router(
              theme: AppTheme.dark(),
              routerConfig: router,
            );
          },
        ),
      ),
    );
    final element = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(element);
    container.read(routerProvider).go('/app/discover');
    await tester.pumpAndSettle();
    unawaited(
      tester.state<DiscoveryDeckState>(find.byType(DiscoveryDeck)).browse(-1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    final reads = api.profileReads;
    await tester.tap(find.text('Discover').last);
    await tester.pumpAndSettle();
    expect(api.profileReads, reads);
    expect(
      tester.widget<DiscoveryDeck>(find.byType(DiscoveryDeck)).itemId,
      secondCard.profileId,
    );
    expect(tester.takeException(), isNull);
  });

  for (final scenario in ['recent', 'stale', 'mock', 'inaccurate']) {
    test('location reuse validates $scenario cached fix', () async {
      final previous = GeolocatorPlatform.instance;
      final geo = CachedGeo()
        ..recent = fix(
          age: scenario == 'stale' ? 120 : 10,
          mock: scenario == 'mock',
          accuracy: scenario == 'inaccurate' ? 3000 : 30,
        );
      GeolocatorPlatform.instance = geo;
      addTearDown(() => GeolocatorPlatform.instance = previous);
      final api = FakeApi();
      await DiscoveryLocationService().sync(api, profileId: 'one');
      expect(geo.gpsReads, scenario == 'recent' ? 0 : 1);
      expect(api.locationWrites, 1);
    });
  }

  test('location reuse still detects revoked device permission', () async {
    final previous = GeolocatorPlatform.instance;
    final geo = CachedGeo()..recent = fix();
    GeolocatorPlatform.instance = geo;
    addTearDown(() => GeolocatorPlatform.instance = previous);
    final api = FakeApi(), service = DiscoveryLocationService();
    await service.sync(api, profileId: 'one');
    geo.permission = LocationPermission.deniedForever;
    await expectLater(
      service.sync(api, profileId: 'one'),
      throwsA(isA<ApiException>()),
    );
    expect(api.locationWrites, 1);
  });
}
