import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/auth/session.dart';
import 'package:anonymoke/core/widgets/profile_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ImageAuth extends AuthController {
  @override
  AuthState build() => AuthState(session: session('first'));
  Session session(String id) => Session(
    userId: id,
    accessToken: 'test',
    refreshToken: 'test',
    accessExpiresAt: DateTime.utc(2040),
    refreshExpiresAt: DateTime.utc(2040),
    isOnboarded: true,
  );
  void switchAccount() => state = AuthState(session: session('second'));
}

// Delay image completion without using a live network endpoint.
class ControlledImage extends ImageProvider<ControlledImage> {
  ControlledImage(this.identity, this.bytes);
  final Object identity;
  final Future<Uint8List> bytes;
  @override
  Future<ControlledImage> obtainKey(ImageConfiguration configuration) async =>
      this;
  @override
  ImageStreamCompleter loadImage(
    ControlledImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: bytes.then((data) async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      return decode(buffer);
    }),
    scale: 1,
  );
  @override
  bool operator ==(Object other) =>
      other is ControlledImage && other.identity == identity;
  @override
  int get hashCode => identity.hashCode;
}

class ControlledCache extends ProfileImageCache {
  final pending = Completer<Uint8List>();
  bool renewed = false;
  static final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==',
  );
  @override
  ImageProvider image(String url, int size) => ControlledImage((
    url,
    renewed,
  ), renewed ? pending.future : Future.value(pixel));
}

void main() {
  test(
    'canonical identities ignore both signing schemes but retain asset versions',
    () {
      const a =
          'https://media.test/p.jpg?AWSAccessKeyId=one&Signature=abc&Expires=123&version=2';
      const b =
          'https://media.test/p.jpg?AWSAccessKeyId=two&Signature=xyz&Expires=456&version=2';
      expect(ProfileImageCache.identity(a), ProfileImageCache.identity(b));
      expect(
        ProfileImageCache.identity(a),
        isNot(
          ProfileImageCache.identity(b.replaceFirst('version=2', 'version=3')),
        ),
      );
    },
  );

  testWidgets(
    'renewed signed URL keeps pixels while loading and account changes reset state',
    (tester) async {
      final cache = ControlledCache();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(ImageAuth.new),
          profileImageCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      var url = 'https://media.test/p.jpg?X-Amz-Signature=first';
      Future<void> render() => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ProfileImage(url, fallback: const Icon(Icons.person)),
          ),
        ),
      );
      await render();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final first = tester.state(find.byType(Image));
      cache.renewed = true;
      url = 'https://media.test/p.jpg?X-Amz-Signature=renewed';
      await render();
      expect(identical(tester.state(find.byType(Image)), first), isTrue);
      expect(tester.widget<Image>(find.byType(Image)).gaplessPlayback, isTrue);
      (container.read(authControllerProvider.notifier) as ImageAuth)
          .switchAccount();
      await tester.pump();
      expect(identical(tester.state(find.byType(Image)), first), isFalse);
      cache.pending.complete(ControlledCache.pixel);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    },
  );

  testWidgets('a different asset resets image state immediately', (
    tester,
  ) async {
    final cache = ControlledCache();
    Future<void> render(String url) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(ImageAuth.new),
          profileImageCacheProvider.overrideWithValue(cache),
        ],
        child: MaterialApp(
          home: ProfileImage(url, fallback: const Icon(Icons.person)),
        ),
      ),
    );
    await render('https://media.test/first.jpg');
    final first = tester.state(find.byType(Image));
    await render('https://media.test/replacement.jpg');
    expect(identical(tester.state(find.byType(Image)), first), isFalse);
  });
}
