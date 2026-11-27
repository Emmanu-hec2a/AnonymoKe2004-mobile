import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/network/chat_connection.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/chat_screen.dart';
import 'package:anonymoke/features/home/presentation/profile_device.dart';
import 'package:anonymoke/features/home/presentation/widgets/chat_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'matches_live_test.dart' show MatchesApi, match, message;

class RoomConnection extends NoChatConnection {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool ready = false;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  bool get connected => ready;
  @override
  Future<void> connect() async {
    ready = true;
  }

  @override
  bool send(Map<String, dynamic> value) {
    sent.add(value);
    return ready;
  }

  @override
  Future<void> dispose() async {
    ready = false;
    await controller.close();
  }
}

class RoomDevice extends ProfileDevice {
  final interruptions = StreamController<bool>.broadcast();
  @override
  Stream<bool> get recordingInterruptions => interruptions.stream;
  int picks = 0, starts = 0, stops = 0;
  final image = XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN1sAAAAASUVORK5CYII=',
    ),
    name: 'photo.png',
  );
  @override
  Future<XFile?> pickPhoto(ImageSource source) async {
    picks++;
    return image;
  }

  @override
  Future<void> startRecording() async {
    starts++;
  }

  @override
  Future<XFile?> stopRecording() async {
    stops++;
    return XFile.fromData(Uint8List(100), name: 'note.m4a');
  }

  @override
  Future<void> dispose() async {}
}

class RoomPlayer extends ProfilePlayer {
  final urls = <String>[];
  @override
  Future<void> play(String source, {bool local = false}) async {
    urls.add(source);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
}

class RoomApi extends MatchesApi {
  final replyIds = <String?>[], attachmentIds = <String?>[];
  int tickets = 0, puts = 0, completes = 0, attachmentReads = 0;
  @override
  Future<List<ConsentSummary>> consents() async => const [
    ConsentSummary(type: 'voice', granted: true, version: 'test'),
  ];
  @override
  Future<Map<String, dynamic>> requestChatUpload(
    String id, {
    required String kind,
    required String contentType,
    required int sizeBytes,
  }) async {
    tickets++;
    return {
      'upload_id': 'attachment-1',
      'upload_url': 'https://storage.test/upload',
      'headers': {'Content-Type': contentType},
    };
  }

  @override
  Future<void> putMedia(Map<String, dynamic> ticket, List<int> bytes) async {
    puts++;
  }

  @override
  Future<ChatAttachment> completeChatUpload(String matchId, String id) async {
    completes++;
    return ChatAttachment(id: id, kind: 'image', status: 'processing');
  }

  @override
  Future<ChatAttachment> chatAttachment(String matchId, String id) async {
    attachmentReads++;
    return ChatAttachment(
      id: id,
      kind: 'audio',
      status: 'ready',
      url: 'https://storage.test/fresh',
    );
  }

  @override
  Future<ChatMessage> sendMessage({
    required String matchId,
    required String body,
    String? clientMessageId,
    String? replyToId,
    String? attachmentId,
  }) {
    replyIds.add(replyToId);
    attachmentIds.add(attachmentId);
    return super.sendMessage(
      matchId: matchId,
      body: body,
      clientMessageId: clientMessageId,
      replyToId: replyToId,
      attachmentId: attachmentId,
    );
  }
}

Future<void> openRoom(
  WidgetTester tester,
  RoomApi api, {
  RoomDevice? device,
  RoomPlayer? player,
  List<RoomConnection>? connections,
}) async {
  tester.view.physicalSize = const Size(390, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        profileDeviceProvider.overrideWithValue(() => device ?? RoomDevice()),
        profilePlayerProvider.overrideWithValue(() => player ?? RoomPlayer()),
        chatConnectionProvider.overrideWithValue((_, _) {
          if (connections == null) return NoChatConnection();
          final c = RoomConnection();
          connections.add(c);
          return c;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const BackendChatScreen(matchId: 'match-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

void main() {
  testWidgets('a microphone interruption discards the unfinished voice note', (
    tester,
  ) async {
    final device = RoomDevice();
    final api = RoomApi();
    await openRoom(tester, api, device: device);
    await tester.tap(find.byTooltip('Record voice note'));
    await tester.pump();
    device.interruptions.add(true);
    await tester.pumpAndSettle();
    expect(device.stops, 1);
    expect(api.tickets, 0);
    expect(find.text('Voice note ready to send'), findsNothing);
    expect(find.textContaining('Recording interrupted'), findsOneWidget);
  });
  testWidgets('an older polling response cannot replace a realtime approval', (
    tester,
  ) async {
    final api = RoomApi()
      ..chat = [
        ChatMessage(
          messageId: '1',
          senderProfileId: 'me',
          body: 'Hello',
          moderationStatus: 'queued',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ];
    final connections = <RoomConnection>[];
    await openRoom(tester, api, connections: connections);
    connections.last.controller.add({
      'type': 'message.new',
      'message_id': '1',
      'sender_profile_id': 'me',
      'body': 'Hello',
      'moderation_status': 'clear',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:01Z',
    });
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sent'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sent'), findsOneWidget);
    expect(find.byTooltip('Checking message'), findsNothing);
  });
  testWidgets('reply and attachment controls fit above a phone keyboard', (
    tester,
  ) async {
    final api = RoomApi()..chat = [message('1', body: 'Hello there')];
    await openRoom(tester, api);
    tester.view.physicalSize = const Size(360, 700);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.drag(find.text('Hello there'), const Offset(75, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Send message'), findsOneWidget);
  });
  testWidgets('delivery states use compact ticks with accessible labels', (
    tester,
  ) async {
    final api = RoomApi()
      ..chat = [
        ChatMessage(
          messageId: '1',
          senderProfileId: 'me',
          body: 'One',
          moderationStatus: 'clear',
          createdAt: DateTime.utc(2026),
        ),
        ChatMessage(
          messageId: '2',
          senderProfileId: 'me',
          body: 'Two',
          moderationStatus: 'clear',
          createdAt: DateTime.utc(2026),
          deliveredAt: DateTime.utc(2026),
        ),
        ChatMessage(
          messageId: '3',
          senderProfileId: 'me',
          body: 'Three',
          moderationStatus: 'clear',
          createdAt: DateTime.utc(2026),
          readAt: DateTime.utc(2026),
        ),
      ];
    await openRoom(tester, api);
    expect(find.byType(MessageTicks), findsNWidgets(3));
    expect(find.byTooltip('Sent'), findsOneWidget);
    expect(find.byTooltip('Delivered'), findsOneWidget);
    expect(find.byTooltip('Read'), findsOneWidget);
    expect(find.text('Sent'), findsNothing);
    expect(find.text('Read'), findsNothing);
    expect(find.byIcon(Icons.done_all_rounded), findsNWidgets(2));
  });
  testWidgets(
    'dating typing cue and active status expire without exact last seen',
    (tester) async {
      final connections = <RoomConnection>[];
      await openRoom(tester, RoomApi(), connections: connections);
      connections.last.controller.add({
        'type': 'activity',
        'active': true,
        'typing': true,
        'active_ttl': 45,
        'typing_ttl': 6,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Finding the right words…'), findsOneWidget);
      expect(find.text('Active in this chat'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.byType(DatingTypingIndicator), findsNothing);
    },
  );
  testWidgets('typing events never transmit the draft text', (tester) async {
    final connections = <RoomConnection>[];
    await openRoom(tester, RoomApi(), connections: connections);
    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'Private unfinished words',
    );
    await tester.pump();
    expect(connections.last.sent.any((value) => value['typing'] == true), true);
    expect(
      jsonEncode(connections.last.sent).contains('Private unfinished words'),
      false,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(connections.last.sent.last['typing'], false);
  });
  testWidgets('swiping a message adds a reply and sends its target ID', (
    tester,
  ) async {
    final api = RoomApi()..chat = [message('1', body: 'A thoughtful hello')];
    await openRoom(tester, api);
    await tester.drag(find.text('A thoughtful hello'), const Offset(75, 0));
    await tester.pumpAndSettle();
    expect(find.text('Replying to Quiet Comet'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'Hello back',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(api.replyIds, ['1']);
    expect(find.byTooltip('Cancel reply'), findsNothing);
  });
  testWidgets('photo picker is locked before mutual reveal', (tester) async {
    final device = RoomDevice();
    final api = RoomApi();
    await openRoom(tester, api, device: device);
    await tester.tap(find.byTooltip('Share photo'));
    await tester.pumpAndSettle();
    expect(device.picks, 0);
    expect(api.tickets, 0);
    expect(find.textContaining('Photo sharing unlocks'), findsOneWidget);
  });
  testWidgets('photo send retries one upload and one stable message identity', (
    tester,
  ) async {
    final api = RoomApi()
      ..current = match(reveal: 'revealed')
      ..failSend = true;
    await openRoom(tester, api, device: RoomDevice());
    await tester.tap(find.byTooltip('Share photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Photo ready to send'), findsOneWidget);
    api.failSend = false;
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(api.tickets, 1);
    expect(api.puts, 1);
    expect(api.completes, 1);
    expect(api.attachmentIds, ['attachment-1', 'attachment-1']);
    expect(api.sentIds[0], api.sentIds[1]);
  });
  testWidgets('voice note recording is capped and cancellation cannot send', (
    tester,
  ) async {
    final api = RoomApi();
    final device = RoomDevice();
    await openRoom(tester, api, device: device);
    await tester.tap(find.byTooltip('Record voice note'));
    await tester.pump();
    expect(device.starts, 1);
    expect(find.byTooltip('Finish recording'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(device.stops, 1);
    expect(find.text('Voice note ready to send'), findsOneWidget);
    expect(api.tickets, 0);
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Record voice note'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(device.stops, 2);
    expect(find.text('Voice note ready to send'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });
  testWidgets('voice playback fetches fresh authorized media access', (
    tester,
  ) async {
    final api = RoomApi()
      ..chat = [
        ChatMessage(
          messageId: '1',
          senderProfileId: 'other',
          body: '',
          moderationStatus: 'clear',
          createdAt: DateTime.utc(2026),
          attachment: const ChatAttachment(
            id: 'voice',
            kind: 'audio',
            status: 'ready',
            url: 'https://storage.test/old',
            durationMs: 5000,
            voiceDisguised: true,
          ),
        ),
      ];
    final player = RoomPlayer();
    await openRoom(tester, api, player: player);
    await tester.tap(find.byTooltip('Play voice note'));
    await tester.pumpAndSettle();
    expect(api.attachmentReads, 1);
    expect(player.urls, ['https://storage.test/fresh']);
  });
}
