import 'dart:async';
import 'dart:ui' as ui;

import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/features/home/presentation/profile_device.dart';
import 'package:anonymoke/features/onboarding/application/onboarding_controller.dart';
import 'package:anonymoke/features/onboarding/application/photo_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'discover_live_test.dart' show Adapter, jsonResponse, MemoryStore;
import 'onboarding_about_you_test.dart'
    show OnboardingApi, OnboardingAuth, fixturePixel, openAbout;

const replacementId = '00000000-0000-4000-8000-000000000002';
const photoId = '00000000-0000-4000-8000-000000000001';

class Draft extends PhotoDraft {
  Draft() : super(privateBytes: fixturePixel(), blurredBytes: fixturePixel());
  int released = 0;
  @override
  Future<void> release() async {
    released++;
  }
}

class Picker extends ProfileDevice {
  final sources = <ImageSource>[];
  bool cancel = false, deny = false;
  XFile? lost;
  int recoveries = 0;
  @override
  Future<XFile?> recoverPhoto() async {
    recoveries++;
    final file = lost;
    lost = null;
    return file;
  }

  Completer<XFile?>? pending;
  @override
  Future<XFile?> pickPhoto(ImageSource source) async {
    sources.add(source);
    if (deny) throw PlatformException(code: 'camera_access_denied');
    if (pending != null) return pending!.future;
    return cancel ? null : XFile.fromData(fixturePixel());
  }

  @override
  Future<void> startRecording() async {}
  @override
  Future<XFile?> stopRecording() async => null;
  @override
  Future<void> dispose() async {}
}

class PhotoApi extends OnboardingApi {
  int tickets = 0, puts = 0, completions = 0, reads = 0;
  String initialStatus = 'processing';
  List<String> statuses = ['ready'];
  String rejection = 'exactly_one_face_required';
  bool failComplete = false, wrongId = false;
  Completer<void>? ticketWait;
  Completer<MediaAssetSummary>? statusWait;
  Map<String, dynamic>? ticketBody;
  MediaAssetSummary summary(String status) => MediaAssetSummary(
    id: wrongId
        ? '00000000-0000-4000-8000-000000000099'
        : tickets > 1
        ? replacementId
        : photoId,
    kind: 'avatar',
    status: status,
    rejectionCode: status == 'rejected' ? rejection : '',
  );
  @override
  Future<Map<String, dynamic>> requestMediaUpload({
    required String kind,
    required String contentType,
    required int sizeBytes,
    bool disguiseVoice = true,
  }) async {
    tickets++;
    calls.add('ticket');
    ticketBody = {
      'kind': kind,
      'content_type': contentType,
      'size_bytes': sizeBytes,
    };
    await ticketWait?.future;
    return {
      'upload_id': tickets > 1 ? replacementId : photoId,
      'upload_url': 'https://storage.test/photo',
    };
  }

  @override
  Future<void> putMedia(Map<String, dynamic> ticket, List<int> bytes) async {
    puts++;
    calls.add('put');
  }

  @override
  Future<MediaAssetSummary> completeMediaUpload(String id) async {
    completions++;
    calls.add('complete');
    if (failComplete) throw const ApiException('network_error', 503);
    return summary(initialStatus);
  }

  @override
  Future<MediaAssetSummary> mediaUploadStatus(String id) async {
    reads++;
    calls.add('status');
    if (statusWait != null) return statusWait!.future;
    return summary(
      statuses.length > 1 ? statuses.removeAt(0) : statuses.single,
    );
  }
}

class Harness {
  Harness(this.container, this.api, this.picker, this.router, this.drafts);
  final ProviderContainer container;
  final PhotoApi api;
  final Picker picker;
  final GoRouter router;
  final List<Draft> drafts;
  OnboardingPhotoController get photo =>
      container.read(onboardingPhotoProvider.notifier);
  OnboardingPhotoState get state => container.read(onboardingPhotoProvider);
  OnboardingController get onboarding =>
      container.read(onboardingControllerProvider.notifier);
}

Future<Harness> openPhoto(
  WidgetTester tester, {
  Picker? picker,
  PhotoApi? api,
  String? error,
  double width = 390,
  double scale = 1,
  Completer<PhotoDraft>? preparing,
}) async {
  picker ??= Picker();
  api ??= PhotoApi();
  final device = picker;
  final drafts = <Draft>[];
  final (container, _, router) = await openAbout(
    tester,
    readyPhoto: false,
    apiOverride: api,
    device: () => device,
    width: width,
    scale: scale,
    prepare: (_) async {
      if (error != null) throw ApiException(error);
      if (preparing != null) return preparing.future;
      final result = Draft();
      drafts.add(result);
      return result;
    },
    photoDelay: (_) async {},
  );
  router.go('/onboarding/4');
  await tester.pumpAndSettle();
  return Harness(container, api, picker, router, drafts);
}

Future<void> choose(
  WidgetTester tester, {
  String action = 'Choose from gallery',
  bool wait = true,
}) async {
  await tester.ensureVisible(find.byKey(const Key('photo-choose')));
  await tester.tap(find.byKey(const Key('photo-choose')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  if (wait) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<Uint8List> imageBytes({int width = 400, int height = 300}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    ui.Paint()..color = Colors.black,
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    ui.Paint()..color = Colors.white,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<(int, int, double)> pixelStats(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  try {
    final data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    double total = 0, squared = 0;
    for (var i = 0; i < data.length; i += 4) {
      total += data[i];
      squared += data[i] * data[i];
    }
    final count = data.length / 4, mean = total / (data.length / 4);
    return (image.width, image.height, squared / count - mean * mean);
  } finally {
    image.dispose();
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a rejected photo can be replaced and accepted without clearing app data',
    (tester) async {
      final h = await openPhoto(
        tester,
        api: PhotoApi()..statuses = ['rejected'],
      );
      await choose(tester);
      h.photo.saveDraft();
      await expectLater(h.onboarding.complete(), throwsA(isA<ApiException>()));
      final old = h.state.draft!;
      expect(h.state.rejected, true);
      await choose(tester);
      expect(identical(h.state.draft, old), false);
      expect(h.state.rejected, false);
      expect(h.state.error, isNull);
      h.api.statuses = ['ready'];
      h.photo.saveDraft();
      await h.onboarding.complete();
      await tester.pumpAndSettle();
      expect(h.api.tickets, 2);
      expect(h.api.puts, 2);
      expect(
        h.api.profiles.single['onboarding_photo_upload_id'],
        replacementId,
      );
    },
  );
  testWidgets(
    'a connection failure on the old photo cannot poison a new photo',
    (tester) async {
      final h = await openPhoto(tester, api: PhotoApi()..failComplete = true);
      await choose(tester);
      h.photo.saveDraft();
      await expectLater(h.onboarding.complete(), throwsA(isA<ApiException>()));
      await choose(tester);
      h.api.failComplete = false;
      h.photo.saveDraft();
      await h.onboarding.complete();
      await tester.pumpAndSettle();
      expect(h.api.tickets, 2);
      expect(h.api.puts, 2);
      expect(
        h.api.profiles.single['onboarding_photo_upload_id'],
        replacementId,
      );
    },
  );
  testWidgets(
    'late rejection from an old photo cannot mark its replacement rejected',
    (tester) async {
      final h = await openPhoto(
        tester,
        api: PhotoApi()..statusWait = Completer(),
      );
      await choose(tester);
      h.photo.saveDraft();
      final operation = h.onboarding.complete();
      final check = expectLater(
        operation,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'photo_changed'),
        ),
      );
      await tester.pump();
      await tester.pump();
      await choose(tester);
      h.api.statusWait!.complete(h.api.summary('rejected'));
      await check;
      await tester.pumpAndSettle();
      expect(h.state.rejected, false);
      expect(h.state.error, isNull);
    },
  );
  testWidgets(
    'recovering an interrupted picker does not replace an explicit new selection',
    (tester) async {
      final picker = Picker()..lost = XFile.fromData(fixturePixel());
      final h = await openPhoto(tester, picker: picker);
      expect(h.state.draft, isNotNull);
      expect(picker.recoveries, 1);
      final recovered = h.state.draft;
      await choose(tester);
      expect(identical(h.state.draft, recovered), false);
      expect(picker.recoveries, 1);
      expect(picker.sources, [ImageSource.gallery]);
    },
  );

  testWidgets('a mismatched upload receipt cannot finalize a different photo', (
    tester,
  ) async {
    final h = await openPhoto(tester, api: PhotoApi()..wrongId = true);
    await choose(tester);
    h.photo.saveDraft();
    await expectLater(
      h.onboarding.complete(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'photo_validation_failed',
        ),
      ),
    );
    expect(h.api.profiles, isEmpty);
    expect(h.state.rejected, isTrue);
  });

  testWidgets('removing a photo during consent requests prevents its upload', (
    tester,
  ) async {
    final h = await openPhoto(
      tester,
      api: PhotoApi()..firstConsent = Completer<void>(),
    );
    await choose(tester);
    h.photo.saveDraft();
    final saving = h.onboarding.complete();
    final check = expectLater(
      saving,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'photo_changed'),
      ),
    );
    await tester.pump();
    await h.photo.remove();
    h.api.firstConsent!.complete();
    await check;
    expect(h.api.tickets, 0);
    expect(h.api.profiles, isEmpty);
  });

  testWidgets(
    'camera and gallery controls are discoverable and cards are square',
    (tester) async {
      final h = await openPhoto(tester);
      final left = tester.getSize(find.byKey(const Key('photo-private-card'))),
          right = tester.getSize(find.byKey(const Key('photo-blurred-card')));
      expect(left.width, left.height);
      expect(right, left);
      expect(find.byIcon(Icons.person_rounded), findsNWidgets(2));
      expect(find.byKey(const Key('photo-continue')), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('photo-choose')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('photo-private-card')));
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(h.api.calls, isEmpty);
    },
  );

  for (final source in [ImageSource.camera, ImageSource.gallery]) {
    testWidgets(
      'choosing ${source.name} produces a local private image and a separate blurred preview',
      (tester) async {
        final h = await openPhoto(tester);
        await choose(
          tester,
          action: source == ImageSource.camera
              ? 'Take a photo'
              : 'Choose from gallery',
        );
        expect(h.picker.sources, [source]);
        final private =
            tester
                    .widget<Image>(find.byKey(const Key('photo-private-image')))
                    .image
                as MemoryImage;
        final blurred =
            tester
                    .widget<Image>(find.byKey(const Key('photo-blurred-image')))
                    .image
                as MemoryImage;
        expect(identical(private.bytes, h.state.draft!.privateBytes), isTrue);
        expect(identical(blurred.bytes, h.state.draft!.blurredBytes), isTrue);
        expect(identical(private.bytes, blurred.bytes), isFalse);
        expect(find.text('Selected'), findsOneWidget);
        expect(find.text('Accepted'), findsNothing);
        expect(h.api.calls, isEmpty);
      },
    );
  }

  testWidgets('cancelling a replacement keeps the previous photo', (
    tester,
  ) async {
    final h = await openPhoto(tester);
    await choose(tester);
    final old = h.state.draft;
    h.picker.cancel = true;
    await choose(tester);
    expect(identical(h.state.draft, old), isTrue);
    expect(h.drafts.single.released, 0);
  });

  testWidgets('replacing and removing a photo release only the local draft', (
    tester,
  ) async {
    final h = await openPhoto(tester);
    await choose(tester);
    await choose(tester);
    expect(h.drafts.first.released, 1);
    await choose(tester, action: 'Remove photo');
    expect(h.state.draft, isNull);
    expect(h.drafts.last.released, 1);
    expect(h.api.calls, isEmpty);
  });

  testWidgets('Continue retains the draft through privacy choices and back', (
    tester,
  ) async {
    final h = await openPhoto(tester);
    await choose(tester);
    await tester.ensureVisible(find.byKey(const Key('photo-continue')));
    await tester.tap(find.byKey(const Key('photo-continue')));
    await tester.pumpAndSettle();
    expect(h.router.routeInformationProvider.value.uri.path, '/onboarding/5');
    expect(h.state.saved, isTrue);
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-private-image')), findsOneWidget);
    expect(h.api.calls, isEmpty);
  });

  testWidgets(
    'permission denial shows recovery guidance without inventing a selected photo',
    (tester) async {
      final h = await openPhoto(tester, picker: Picker()..deny = true);
      await choose(tester, action: 'Take a photo');
      expect(
        find.textContaining('Allow camera or photo access'),
        findsOneWidget,
      );
      expect(h.state.draft, isNull);
    },
  );

  for (final code in [
    'photo_size_invalid',
    'photo_invalid',
    'avatar_dimensions_invalid',
    'avatar_still_photo_required',
  ]) {
    testWidgets('invalid photo $code cannot advance', (tester) async {
      final h = await openPhoto(tester, error: code);
      await choose(tester);
      expect(h.state.error, code);
      expect(h.state.draft, isNull);
      expect(find.byKey(const Key('photo-continue')), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('photo-choose')))
            .onPressed,
        isNotNull,
      );
      expect(h.api.calls, isEmpty);
    });
  }

  testWidgets('an account switch ignores a late picker result', (tester) async {
    final pending = Completer<XFile?>();
    final h = await openPhoto(tester, picker: Picker()..pending = pending);
    await choose(tester, wait: false);
    (h.container.read(authControllerProvider.notifier) as OnboardingAuth)
        .switchAccount();
    await tester.pump();
    pending.complete(XFile.fromData(fixturePixel()));
    await tester.pumpAndSettle();
    expect(h.state.draft, isNull);
    expect(h.state.busy, isFalse);
    expect(h.drafts, isEmpty);
  });

  testWidgets(
    'leaving and returning while a picker is pending does not leave the screen busy',
    (tester) async {
      final pending = Completer<XFile?>();
      final h = await openPhoto(tester, picker: Picker()..pending = pending);
      await choose(tester, wait: false);
      h.router.go('/onboarding/3');
      await tester.pumpAndSettle();
      h.router.go('/onboarding/4');
      await tester.pumpAndSettle();
      pending.complete(XFile.fromData(fixturePixel()));
      await tester.pumpAndSettle();
      expect(h.state.busy, isFalse);
      expect(h.state.draft, isNull);
    },
  );

  testWidgets(
    'a late decode after account change is released and never displayed',
    (tester) async {
      final pending = Completer<PhotoDraft>();
      final draft = Draft();
      final h = await openPhoto(tester, preparing: pending);
      await choose(tester, wait: false);
      (h.container.read(authControllerProvider.notifier) as OnboardingAuth)
          .switchAccount();
      await tester.pump();
      pending.complete(draft);
      await tester.pumpAndSettle();
      expect(h.state.draft, isNull);
      expect(draft.released, 1);
    },
  );

  testWidgets('account changes clear a selected photo', (tester) async {
    final h = await openPhoto(tester);
    await choose(tester);
    (h.container.read(authControllerProvider.notifier) as OnboardingAuth)
        .switchAccount();
    await tester.pumpAndSettle();
    expect(h.state.draft, isNull);
    expect(h.drafts.single.released, 1);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'photo cards and actions remain usable at 320 width and text scale $scale',
      (tester) async {
        await openPhoto(tester, width: 320, scale: scale);
        await choose(tester);
        await tester.ensureVisible(find.byKey(const Key('photo-continue')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('photo-continue')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'server photo approval is required before the final profile request',
    (tester) async {
      final h = await openPhoto(
        tester,
        api: PhotoApi()..statuses = ['processing', 'ready'],
      );
      await choose(tester);
      h.photo.saveDraft();
      await h.onboarding.complete();
      await tester.pumpAndSettle();
      expect(h.api.calls, [
        'consent:terms',
        'consent:privacy',
        'consent:sensitive_data',
        'consent:location',
        'consent:voice',
        'ticket',
        'put',
        'complete',
        'status',
        'status',
        'profile',
      ]);
      expect(h.api.profiles.single['onboarding_photo_upload_id'], photoId);
      expect(h.api.ticketBody!['content_type'], 'image/png');
      expect(h.state.draft, isNull);
      expect(h.drafts.single.released, 1);
    },
  );

  testWidgets(
    'missing or unsaved photos cannot complete onboarding or record consent',
    (tester) async {
      final h = await openPhoto(tester);
      await expectLater(
        h.onboarding.complete(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'photo_required'),
        ),
      );
      await choose(tester);
      await expectLater(
        h.onboarding.complete(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'photo_required'),
        ),
      );
      expect(h.api.calls, isEmpty);
    },
  );

  testWidgets(
    'face rejection preserves the photo for replacement and never completes the profile',
    (tester) async {
      final h = await openPhoto(
        tester,
        api: PhotoApi()..statuses = ['rejected'],
      );
      await choose(tester);
      h.photo.saveDraft();
      await expectLater(
        h.onboarding.complete(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'exactly_one_face_required',
          ),
        ),
      );
      expect(h.api.profiles, isEmpty);
      expect(h.state.draft, isNotNull);
    },
  );

  testWidgets(
    'slow validation has a bounded wait and retry keeps the same upload',
    (tester) async {
      final h = await openPhoto(
        tester,
        api: PhotoApi()..statuses = ['processing'],
      );
      await choose(tester);
      h.photo.saveDraft();
      await expectLater(
        h.onboarding.complete(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'photo_processing_pending',
          ),
        ),
      );
      expect(h.api.reads, 15);
      expect(h.api.profiles, isEmpty);
      h.api.statuses = ['ready'];
      await h.onboarding.complete();
      await tester.pumpAndSettle();
      expect(h.api.tickets, 1);
      expect(h.api.puts, 1);
      expect(h.api.profiles, hasLength(1));
    },
  );

  testWidgets(
    'ambiguous completion failure retries without uploading the bytes again',
    (tester) async {
      final h = await openPhoto(tester, api: PhotoApi()..failComplete = true);
      await choose(tester);
      h.photo.saveDraft();
      await expectLater(h.onboarding.complete(), throwsA(isA<ApiException>()));
      h.api.failComplete = false;
      await h.onboarding.complete();
      await tester.pumpAndSettle();
      expect(h.api.tickets, 1);
      expect(h.api.puts, 1);
      expect(h.api.completions, 2);
    },
  );

  testWidgets(
    'changing accounts before a ticket returns prevents the photo PUT',
    (tester) async {
      final h = await openPhoto(
        tester,
        api: PhotoApi()..ticketWait = Completer<void>(),
      );
      await choose(tester);
      h.photo.saveDraft();
      final saving = h.onboarding.complete();
      final check = expectLater(
        saving,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'session_changed'),
        ),
      );
      await tester.pump();
      (h.container.read(authControllerProvider.notifier) as OnboardingAuth)
          .switchAccount();
      h.api.ticketWait!.complete();
      await check;
      await tester.pumpAndSettle();
      expect(h.api.puts, 0);
      expect(h.api.profiles, isEmpty);
    },
  );

  test(
    'media status endpoint uses an owner-scoped UUID path and rejects invalid paths',
    () async {
      final api = ApiClient(
        store: MemoryStore(),
        baseUrl: 'https://api.test/api/v1',
      );
      String? path;
      api.dio.httpClientAdapter = Adapter((request) {
        path = request.path;
        return jsonResponse({
          'upload_id': photoId,
          'kind': 'avatar',
          'status': 'ready',
        });
      });
      expect((await api.mediaUploadStatus(photoId)).status, 'ready');
      expect(path, '/me/media/status/$photoId/');
      await expectLater(
        api.mediaUploadStatus('../other-account'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'real photo preparation keeps a normalized private image and removes identifying detail from the blur',
    () async {
      final draft = await preparePhoto(XFile.fromData(await imageBytes()));
      final private = await pixelStats(draft.privateBytes),
          blurred = await pixelStats(draft.blurredBytes);
      expect((private.$1, private.$2), (400, 300));
      expect((blurred.$1, blurred.$2), (48, 48));
      expect(blurred.$3, lessThan(private.$3 * .95));
      expect(draft.privateBytes, isNot(orderedEquals(draft.blurredBytes)));
    },
  );

  test(
    'real preparation bounds the upload size by reducing large images',
    () async {
      final draft = await preparePhoto(
        XFile.fromData(await imageBytes(width: 2000, height: 500)),
      );
      final result = await pixelStats(draft.privateBytes);
      expect((result.$1, result.$2), (1600, 400));
    },
  );

  test('real preparation rejects corrupt, small and oversized files', () async {
    for (final bytes in [
      Uint8List.fromList([1, 2, 3]),
      fixturePixel(),
      Uint8List(10485761),
    ]) {
      await expectLater(
        preparePhoto(XFile.fromData(bytes)),
        throwsA(isA<ApiException>()),
      );
    }
  });
}
