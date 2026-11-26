import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/auth/session.dart';
import 'package:anonymoke/core/location_service.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/storage/session_store.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/discover_screen.dart';
import 'package:anonymoke/features/home/presentation/widgets/discovery_deck.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class MemoryStore extends SessionStore {
  MemoryStore() : super(const FlutterSecureStorage());
  String token = 'expired';
  @override
  Future<String?> accessToken() async => token;
  @override
  Future<String?> refreshToken() async => 'refresh';
  @override
  Future<void> saveSession(Session session) async {
    token = session.accessToken;
  }

  @override
  Future<void> clear() async {
    token = '';
  }
}

class Adapter implements HttpClientAdapter {
  Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object body, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

const firstCard = DiscoveryCard(
  profileId: 'first',
  alias: 'Quiet Comet',
  ageYears: 27,
  distanceBucket: '2-5 km',
  interests: [],
  isVerified: true,
  bio: 'Coffee and live music.',
);
const secondCard = DiscoveryCard(
  profileId: 'second',
  alias: 'Velvet Echo',
  ageYears: 28,
  distanceBucket: '1-2 km',
  interests: [],
  isVerified: false,
);

class FakeApi extends ApiClient {
  FakeApi() : super(store: MemoryStore(), baseUrl: 'https://api.test/api/v1');
  final swipes = <String>[];
  final updates = <Map<String, dynamic>>[];
  bool grantConsents = true;
  bool failSwipe = false;
  bool matched = false;
  int locationWrites = 0;
  int undoCalls = 0;
  @override
  Future<ProfileSummary> profile() async => const ProfileSummary(
    profileId: 'me',
    alias: 'Me',
    ageYears: 27,
    gender: 'W',
    heightCm: 168,
    interests: [],
    isDiscoverable: true,
    maxDistanceKm: 15,
    minAgePref: 18,
    maxAgePref: 35,
    verificationLevel: 'none',
  );
  @override
  Future<List<ConsentSummary>> consents() async => [
    ConsentSummary(type: 'location', granted: grantConsents, version: 'test'),
    ConsentSummary(
      type: 'sensitive_data',
      granted: grantConsents,
      version: 'test',
    ),
  ];
  @override
  Future<List<DiscoveryCard>> discovery({
    String? cursor,
    int? maxDistanceKm,
    int? minAge,
    int? maxAge,
  }) async => [firstCard, secondCard];
  @override
  Future<DiscoveryCard> discoveryProfile(String id) async =>
      id == firstCard.profileId ? firstCard : secondCard;
  @override
  Future<SwipeOutcome> swipe({
    required String profileId,
    required String action,
    String? clientSwipeId,
  }) async {
    swipes.add(clientSwipeId!);
    if (failSwipe) throw const ApiException('network_error');
    return SwipeOutcome(
      isMatch: matched,
      matchId: matched ? 'match-id' : null,
      clientSwipeId: clientSwipeId,
    );
  }

  @override
  Future<void> updateProfile(Map<String, dynamic> data) async {
    updates.add(data);
  }

  @override
  Future<void> undoPass(String id) async {
    undoCalls++;
  }

  @override
  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
    bool isMock = false,
  }) async {
    locationWrites++;
  }
}

class FakeLocation extends DiscoveryLocationService {
  int calls = 0;
  @override
  Future<void> sync(ApiClient api, {required String profileId}) async {
    calls++;
  }
}

class FakeGeo extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  bool enabled = true;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position.fromMap({
    'latitude': -1.28,
    'longitude': 36.82,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'accuracy': 20.0,
    'altitude': 0.0,
    'heading': 0.0,
    'speed': 0.0,
    'speed_accuracy': 0.0,
    'altitude_accuracy': 0.0,
    'heading_accuracy': 0.0,
  });
}

Future<void> pumpDiscover(
  WidgetTester tester,
  FakeApi api,
  FakeLocation location,
) async {
  tester.view.physicalSize = const Size(390, 920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        discoveryLocationProvider.overrideWithValue(location),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: BackendDiscoverScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('401 refresh rotates the token and retries exactly once', () async {
    final store = MemoryStore();
    final api = ApiClient(store: store, baseUrl: 'https://api.test/api/v1');
    var refreshes = 0;
    var feeds = 0;
    api.dio.httpClientAdapter = Adapter((options) {
      if (options.path == '/auth/token/refresh/') {
        refreshes++;
        return jsonResponse({
          'user_id': 'me',
          'access_token': 'new',
          'refresh_token': 'rotated',
          'is_onboarded': true,
          'access_expires_at': '2030-01-01T00:00:00Z',
          'refresh_expires_at': '2030-02-01T00:00:00Z',
        });
      }
      feeds++;
      return options.headers['Authorization'] == 'Bearer new'
          ? jsonResponse({'items': []})
          : jsonResponse({'detail': 'invalid_access_token'}, 401);
    });
    await api.discovery();
    expect(refreshes, 1);
    expect(feeds, 2);
    expect(store.token, 'new');
  });

  test('expired refresh has a recoverable session error', () async {
    final api = ApiClient(
      store: MemoryStore(),
      baseUrl: 'https://api.test/api/v1',
    );
    api.dio.httpClientAdapter = Adapter(
      (_) => jsonResponse({'detail': 'invalid'}, 401),
    );
    await expectLater(
      api.discovery(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'session_expired',
        ),
      ),
    );
  });

  test(
    'swipe request preserves retry identity and parses match response',
    () async {
      final api = ApiClient(
        store: MemoryStore(),
        baseUrl: 'https://api.test/api/v1',
      );
      api.dio.httpClientAdapter = Adapter((options) {
        expect(options.path, '/swipes/');
        expect(options.data['client_swipe_id'], 'stable-id');
        return jsonResponse({
          'is_match': true,
          'match_id': 'match',
          'client_swipe_id': 'stable-id',
        });
      });
      final result = await api.swipe(
        profileId: 'target',
        action: 'like',
        clientSwipeId: 'stable-id',
      );
      expect(result.isMatch, true);
      expect(result.matchId, 'match');
    },
  );

  test(
    'location sync submits coordinates once per account after permission',
    () async {
      final original = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = FakeGeo();
      addTearDown(() => GeolocatorPlatform.instance = original);
      final api = FakeApi();
      final location = DiscoveryLocationService();
      await location.sync(api, profileId: 'one');
      await location.sync(api, profileId: 'one');
      await location.sync(api, profileId: 'two');
      expect(api.locationWrites, 2);
    },
  );

  test('location denial never sends coordinates', () async {
    final original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = FakeGeo()
      ..permission = LocationPermission.deniedForever;
    addTearDown(() => GeolocatorPlatform.instance = original);
    final api = FakeApi();
    await expectLater(
      DiscoveryLocationService().sync(api, profileId: 'one'),
      throwsA(isA<ApiException>()),
    );
    expect(api.locationWrites, 0);
  });

  testWidgets('consent is checked before native location is requested', (
    tester,
  ) async {
    final api = FakeApi()..grantConsents = false;
    final location = FakeLocation();
    await pumpDiscover(tester, api, location);
    expect(location.calls, 0);
    expect(find.text('Review privacy choices'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed swipe keeps the card and reuses its ID on retry', (
    tester,
  ) async {
    final api = FakeApi()..failSwipe = true;
    await pumpDiscover(tester, api, FakeLocation());
    var deck = tester.state<DiscoveryDeckState>(find.byType(DiscoveryDeck));
    unawaited(deck.swipe(1));
    await tester.pumpAndSettle();
    expect(api.swipes.length, 1);
    expect(
      tester.widget<DiscoveryDeck>(find.byType(DiscoveryDeck)).itemId,
      firstCard.profileId,
    );
    api.failSwipe = false;
    deck = tester.state<DiscoveryDeckState>(find.byType(DiscoveryDeck));
    unawaited(deck.swipe(1));
    await tester.pumpAndSettle();
    expect(api.swipes[0], api.swipes[1]);
    expect(
      tester.widget<DiscoveryDeck>(find.byType(DiscoveryDeck)).itemId,
      secondCard.profileId,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mutual like displays match feedback', (tester) async {
    final api = FakeApi()..matched = true;
    await pumpDiscover(tester, api, FakeLocation());
    unawaited(
      tester.state<DiscoveryDeckState>(find.byType(DiscoveryDeck)).swipe(1),
    );
    await tester.pumpAndSettle();
    expect(find.text("It's a match!"), findsOneWidget);
    expect(find.text('Send a message'), findsOneWidget);
  });

  testWidgets('accepted pass can be undone through the server', (tester) async {
    final api = FakeApi();
    await pumpDiscover(tester, api, FakeLocation());
    unawaited(
      tester.state<DiscoveryDeckState>(find.byType(DiscoveryDeck)).swipe(-1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();
    expect(api.undoCalls, 1);
    expect(
      tester.widget<DiscoveryDeck>(find.byType(DiscoveryDeck)).itemId,
      firstCard.profileId,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter apply saves preferences before refreshing discovery', (
    tester,
  ) async {
    final api = FakeApi();
    await pumpDiscover(tester, api, FakeLocation());
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(api.updates.single, {
      'max_distance_km': 15,
      'min_age_pref': 18,
      'max_age_pref': 35,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile detail control shows server profile information', (
    tester,
  ) async {
    await pumpDiscover(tester, FakeApi(), FakeLocation());
    final button = find.widgetWithText(TextButton, 'Drag up for more').last;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Coffee and live music.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
