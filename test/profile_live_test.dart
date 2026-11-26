import 'dart:async';
import 'package:anonymoke/features/home/presentation/profile_controller.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/profile_device.dart';
import 'package:anonymoke/features/home/presentation/profile_screen.dart';
import 'package:anonymoke/features/home/presentation/profile_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'discover_live_test.dart' show MemoryStore, Adapter, jsonResponse;

class VisibilityApi extends ProfileApi {
  Completer<void>? writeGate;
  Completer<ProfileSummary>? readGate;
  bool rejectWrite = false;
  @override
  Future<ProfileSummary> profile() {
    final gate = readGate;
    if (gate == null) return super.profile();
    readGate = null;
    return gate.future;
  }

  @override
  Future<void> updateProfile(Map<String, dynamic> values) async {
    writes.add({...values});
    await writeGate?.future;
    if (rejectWrite) throw const ApiException('network_error');
    raw.addAll(values);
  }
}

class ProfileApi extends ApiClient {
  ProfileApi()
    : super(store: MemoryStore(), baseUrl: 'https://api.test/api/v1');
  final raw = <String, dynamic>{
    'public_id': 'me',
    'alias': 'Quiet Comet',
    'age_years': 27,
    'gender': 'NB',
    'height_cm': 168,
    'interests': ['Tech'],
    'is_discoverable': true,
    'max_distance_km': 15,
    'min_age_pref': 24,
    'max_age_pref': 85,
    'verification_level': 'verified',
    'target_genders': ['ALL'],
    'audio_duration_ms': 12000,
    'audio_disguised': false,
    'audio_url': 'https://storage.test/capsule',
  };
  final consent = <String, bool>{
    'voice': true,
    'location': true,
    'sensitive_data': true,
    'terms': true,
    'privacy': true,
  };
  List<EntitlementSummary> perks = [];
  List<MediaAssetSummary> media = [];
  final writes = <Map<String, dynamic>>[];
  final completed = <String>[];
  final deletes = <String>[];
  int reads = 0, tickets = 0, puts = 0, accountDeletes = 0;
  bool failPerks = false,
      failProfile = false,
      failDelete = false,
      failComplete = false;
  int profileErrorStatus = 503;
  @override
  Future<ProfileSummary> profile() async {
    reads++;
    if (failProfile) throw ApiException('network_error', profileErrorStatus);
    return ProfileSummary.fromJson({...raw});
  }

  @override
  Future<List<EntitlementSummary>> entitlements() async {
    if (failPerks) throw const ApiException('network_error');
    return perks;
  }

  @override
  Future<List<MediaAssetSummary>> mediaStatus() async => media;
  @override
  Future<void> updateProfile(Map<String, dynamic> values) async {
    writes.add(values);
    raw.addAll(values);
  }

  @override
  Future<List<ConsentSummary>> consents() async => consent.entries
      .map(
        (e) => ConsentSummary(type: e.key, granted: e.value, version: 'test'),
      )
      .toList();
  @override
  Future<void> recordConsent({
    required String type,
    required String version,
    required bool granted,
  }) async {
    consent[type] = granted;
    if (type == 'voice' && !granted) raw['audio_url'] = null;
  }

  @override
  Future<Map<String, dynamic>> exportMyData() async => {
    'format_version': 1,
    'account': {'email': 'owner@example.test'},
    'profile': {...raw},
  };
  @override
  Future<void> deleteAccount() async {
    accountDeletes++;
    if (failDelete) throw const ApiException('erasure_temporarily_unavailable');
  }

  @override
  Future<void> deleteMedia(String kind) async {
    deletes.add(kind);
    if (kind == 'audio') {
      raw['audio_duration_ms'] = 0;
      raw['audio_url'] = null;
    }
  }

  @override
  Future<Map<String, dynamic>> requestMediaUpload({
    required String kind,
    required String contentType,
    required int sizeBytes,
    bool disguiseVoice = true,
  }) async {
    tickets++;
    return {
      'upload_id': 'upload-$tickets',
      'upload_url': 'https://storage.test/upload',
      'headers': {'Content-Type': contentType},
    };
  }

  @override
  Future<void> putMedia(Map<String, dynamic> ticket, List<int> bytes) async {
    puts++;
  }

  @override
  Future<MediaAssetSummary> completeMediaUpload(String id) async {
    completed.add(id);
    if (failComplete) throw const ApiException('network_error');
    return MediaAssetSummary(id: id, kind: 'avatar', status: 'processing');
  }
}

class Device extends ProfileDevice {
  int starts = 0, stops = 0, disposals = 0;
  bool deny = false;
  final file = XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN1sAAAAASUVORK5CYII=',
    ),
    name: 'photo.png',
  );
  @override
  Future<XFile?> pickPhoto(ImageSource source) async => file;
  @override
  Future<void> startRecording() async {
    if (deny) throw const ApiException('microphone_permission_denied');
    starts++;
  }

  @override
  Future<XFile?> stopRecording() async {
    stops++;
    return XFile.fromData(Uint8List(32), name: 'capsule.m4a');
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class Player extends ProfilePlayer {
  final played = <String>[];
  int pauses = 0;
  @override
  Future<void> play(String source, {bool local = false}) async {
    played.add(source);
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> dispose() async {}
}

Future<GoRouter> open(
  WidgetTester tester,
  ProfileApi api, {
  Device? device,
  Player? player,
  Size size = const Size(390, 1100),
  double scale = 1,
  Future<bool> Function(Map<String, dynamic>)? save,
  Widget? home,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/app/profile',
    routes: [
      GoRoute(
        path: '/app/profile',
        builder: (_, _) => Scaffold(body: home ?? const BackendProfileScreen()),
      ),
      GoRoute(
        path: '/app/boost',
        builder: (_, _) => const Scaffold(body: Text('Boost destination')),
      ),
      GoRoute(
        path: '/app/store',
        builder: (_, _) => const Scaffold(body: Text('Plans destination')),
      ),
      GoRoute(
        path: '/auth',
        builder: (_, _) => const Scaffold(body: Text('Signed out')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionStoreProvider.overrideWithValue(api.store),
        profileDeviceProvider.overrideWithValue(() => device ?? Device()),
        profilePlayerProvider.overrideWithValue(() => player ?? Player()),
        if (save != null) profileExportProvider.overrideWithValue(save),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    router.dispose();
  });
  return router;
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 160);
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'pause row saves once and can resume without targeting the small switch',
    (tester) async {
      final api = ProfileApi();
      await open(tester, api);
      await tap(tester, 'Pause my profile');
      expect(api.writes, [
        {'is_discoverable': false},
      ]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      await tap(tester, 'Pause my profile');
      expect(api.writes.last, {'is_discoverable': true});
      expect(api.writes.length, 2);
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    },
  );

  testWidgets('pause updates immediately and rolls back a failed write', (
    tester,
  ) async {
    final api = VisibilityApi()
      ..writeGate = Completer<void>()
      ..rejectWrite = true;
    await open(tester, api);
    await tester.scrollUntilVisible(find.text('Pause my profile'), 180);
    await tester.tap(find.text('Pause my profile'));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    expect(api.raw['is_discoverable'], true);
    expect(api.writes.length, 1);
  });

  testWidgets('a stale profile read cannot undo a newer pause', (tester) async {
    final api = VisibilityApi();
    await open(tester, api);
    final gate = Completer<ProfileSummary>();
    api.readGate = gate;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BackendProfileScreen)),
    );
    final stale = container.read(profileProvider.notifier).refresh();
    await tap(tester, 'Pause my profile');
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    gate.complete(
      ProfileSummary.fromJson({...api.raw, 'is_discoverable': true}),
    );
    await stale;
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    expect(api.raw['is_discoverable'], false);
  });

  testWidgets(
    'expired perks are excluded and Boost opens the real boost route',
    (tester) async {
      final api = ProfileApi()
        ..perks = [
          EntitlementSummary(
            kind: 'premium',
            quantity: 1,
            expiresAt: DateTime.now().add(const Duration(days: 5)),
          ),
          const EntitlementSummary(kind: 'boost', quantity: 2),
          EntitlementSummary(
            kind: 'boost',
            quantity: 9,
            expiresAt: DateTime(2020),
          ),
        ];
      await open(tester, api);
      expect(find.textContaining('2 boosts ready'), findsOneWidget);
      await tester.tap(find.text('Boost'));
      await tester.pumpAndSettle();
      expect(find.text('Boost destination'), findsOneWidget);
    },
  );
  testWidgets('a perks outage leaves profile and account controls usable', (
    tester,
  ) async {
    final api = ProfileApi()..failPerks = true;
    await open(tester, api);
    expect(find.text('Quiet Comet'), findsOneWidget);
    expect(
      find.text('Premium details could not be refreshed.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Delete account and purge data'),
      160,
    );
    expect(find.text('Delete account and purge data'), findsOneWidget);
  });
  testWidgets('pause saves through the API and refreshes the switch', (
    tester,
  ) async {
    final api = ProfileApi();
    await open(tester, api);
    await tester.scrollUntilVisible(find.byType(Switch), 160);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(api.writes.single['is_discoverable'], false);
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
  });
  testWidgets(
    'preferences restore ages above 70 and save gender, age and distance once',
    (tester) async {
      final api = ProfileApi();
      await open(tester, api);
      await tap(tester, 'Discovery preferences');
      expect(find.text('Age range: 24–85'), findsOneWidget);
      await tester.tap(find.text('Women'));
      await tester.pump();
      await tester.tap(find.text('Save preferences'));
      await tester.pumpAndSettle();
      expect(api.writes.single['target_genders'], ['W']);
      expect(api.writes.single['max_age_pref'], 85);
      expect(api.writes.single['max_distance_km'], 15);
    },
  );
  testWidgets('interests validate duplicates and save a typed value', (
    tester,
  ) async {
    final api = ProfileApi();
    await open(tester, api);
    await tap(tester, '+ Add interest');
    await tester.enterText(find.byType(TextFormField), 'tech');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('That interest is already added.'), findsOneWidget);
    expect(api.writes, isEmpty);
    await tester.enterText(find.byType(TextFormField), 'Live music');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.writes.single['interests'], ['Tech', 'Live music']);
  });
  testWidgets('voice playback requests a fresh owner URL', (tester) async {
    final api = ProfileApi();
    final player = Player();
    await open(tester, api, player: player);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
    await tester.pumpAndSettle();
    expect(player.played, ['https://storage.test/capsule']);
    expect(api.reads, greaterThan(1));
    expect(find.textContaining('voice disguise off'), findsOneWidget);
  });
  testWidgets('voice consent withdrawal requires confirmation and persists', (
    tester,
  ) async {
    final api = ProfileApi();
    await open(tester, api);
    await tap(tester, 'Privacy and consents');
    final voice = find.ancestor(
      of: find.text('Voice capsule'),
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(voice);
    await tester.tap(voice);
    await tester.pumpAndSettle();
    expect(api.consent['voice'], true);
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(api.consent['voice'], false);
  });
  testWidgets(
    'data export goes to explicit Save File and cancellation never claims success',
    (tester) async {
      final api = ProfileApi();
      Map<String, dynamic>? captured;
      await open(
        tester,
        api,
        save: (data) async {
          captured = data;
          return false;
        },
      );
      await tap(tester, 'Download my data');
      expect((captured!['account'] as Map)['email'], 'owner@example.test');
      expect(find.text('Your data export was saved.'), findsNothing);
    },
  );
  testWidgets(
    'deletion requires exact confirmation and clears the session after success',
    (tester) async {
      final api = ProfileApi();
      await open(tester, api);
      await tap(tester, 'Delete account and purge data');
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(api.accountDeletes, 0);
      await tester.enterText(find.byType(TextFormField), 'DELETE');
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(api.accountDeletes, 1);
      expect(find.text('Signed out'), findsOneWidget);
      expect((api.store as MemoryStore).token, '');
    },
  );
  testWidgets(
    'failed purge keeps the user in the profile with a retry message',
    (tester) async {
      final api = ProfileApi()..failDelete = true;
      await open(tester, api);
      await tap(tester, 'Delete account and purge data');
      await tester.enterText(find.byType(TextFormField), 'DELETE');
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(find.text('Signed out'), findsNothing);
      expect(
        find.textContaining('Storage is temporarily unavailable'),
        findsOneWidget,
      );
    },
  );
  testWidgets('privacy preview uses only the blurred image', (tester) async {
    final api = ProfileApi()
      ..raw['avatar_url'] = 'https://storage.test/private'
      ..raw['blurred_avatar_url'] = 'https://storage.test/blurred';
    await open(tester, api);
    await tester.tap(find.text('See how others see me'));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Image)),
    );
    var provider = image.image;
    if (provider is ResizeImage) provider = provider.imageProvider;
    expect((provider as NetworkImage).url, 'https://storage.test/blurred');
  });
  testWidgets('recording stops at 15 seconds and on backgrounding', (
    tester,
  ) async {
    final api = ProfileApi();
    final device = Device();
    await open(
      tester,
      api,
      device: device,
      home: const ProfileMediaSheet(kind: 'audio'),
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(device.starts, 1);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(device.stops, 1);
    expect(find.text('0:15'), findsOneWidget);
    await tester.tap(find.text('Re-record'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(device.stops, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets('microphone denial does not start or upload a recording', (
    tester,
  ) async {
    final api = ProfileApi();
    final device = Device()..deny = true;
    await open(
      tester,
      api,
      device: device,
      home: const ProfileMediaSheet(kind: 'audio'),
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(device.starts, 0);
    expect(api.tickets, 0);
    expect(find.textContaining('Allow microphone access'), findsOneWidget);
  });
  testWidgets(
    'camera control opens a real picker and uploads through the API',
    (tester) async {
      final api = ProfileApi();
      await open(tester, api, device: Device(), size: const Size(390, 1400));
      await tester.tap(find.byIcon(Icons.camera_alt_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload photo'));
      await tester.pumpAndSettle();
      expect(api.tickets, 1);
      expect(api.puts, 1);
      expect(api.completed, ['upload-1']);
    },
  );
  test(
    'ambiguous completion retries the same upload without uploading bytes again',
    () async {
      final api = ProfileApi()..failComplete = true;
      final draft = ProfileUpload(file: Device().file, kind: 'avatar');
      await expectLater(draft.send(api), throwsA(isA<ApiException>()));
      api.failComplete = false;
      await draft.send(api);
      expect(api.tickets, 1);
      expect(api.puts, 1);
      expect(api.completed, ['upload-1', 'upload-1']);
    },
  );
  test(
    'presigned upload sends bytes without an Authorization header',
    () async {
      final api = ApiClient(
        store: MemoryStore(),
        baseUrl: 'https://api.test/api/v1',
      );
      final headers = <Map<String, dynamic>>[];
      api.mediaDio.httpClientAdapter = Adapter((o) {
        headers.add(o.headers);
        return jsonResponse({});
      });
      await api.putMedia(
        {
          'upload_url': 'https://storage.test/upload',
          'headers': {'Content-Type': 'image/jpeg'},
        },
        [1, 2, 3],
      );
      expect(headers.single.containsKey('Authorization'), false);
      await expectLater(
        api.putMedia({'upload_url': 'http://evil.test/'}, [1]),
        throwsA(isA<ApiException>()),
      );
    },
  );
  testWidgets(
    'profile polls in foreground, pauses in background and refreshes on resume',
    (tester) async {
      final api = ProfileApi();
      await open(tester, api);
      final initial = api.reads;
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(api.reads, greaterThan(initial));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = api.reads;
      await tester.pump(const Duration(seconds: 31));
      expect(api.reads, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.reads, greaterThan(paused));
    },
  );
  testWidgets('401 clears previously visible profile data', (tester) async {
    final api = ProfileApi();
    await open(tester, api);
    api
      ..failProfile = true
      ..profileErrorStatus = 401;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('Quiet Comet'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });
  testWidgets(
    'live profile retains readable text on narrow screens with larger fonts',
    (tester) async {
      await open(tester, ProfileApi(), size: const Size(320, 800), scale: 1.5);
      await tester.scrollUntilVisible(find.text('My voice capsule'), 130);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.text('My voice capsule')).width,
        greaterThan(70),
      );
    },
  );
}
