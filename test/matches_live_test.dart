import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/notifications/notification_route.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/matches_screen.dart';
import 'package:anonymoke/features/home/presentation/match_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'discover_live_test.dart' show MemoryStore, Adapter, jsonResponse;

MatchSummary match({
  String reveal = 'none',
  int unread = 0,
  String? preview,
  String alias = 'Quiet Comet',
}) => MatchSummary(
  matchId: 'match-1',
  profileId: 'other',
  viewerProfileId: 'me',
  alias: alias,
  ageYears: 27,
  state: reveal == 'revealed' ? 'unmasked' : 'masked',
  revealStatus: reveal,
  unreadCount: unread,
  lastMessage: preview,
  createdAt: DateTime.utc(2026),
);
ChatMessage message(
  String id, {
  String sender = 'other',
  String body = 'Hello there',
  String status = 'clear',
}) => ChatMessage(
  messageId: id,
  senderProfileId: sender,
  body: body,
  moderationStatus: status,
  createdAt: DateTime.utc(2026, 11, 14, 10, int.tryParse(id) ?? 0),
);

class MatchesApi extends ApiClient {
  MatchesApi()
    : super(store: MemoryStore(), baseUrl: 'https://api.test/api/v1');
  MatchSummary current = match();
  List<ChatMessage> chat = [];
  bool failInbox = false, failChat = false, failSend = false, closed = false;
  String? revealFailure;
  final sentIds = <String?>[];
  final actions = <String>[];
  final reads = <String?>[];
  final cursors = <String?>[];
  int identityReads = 0;

  @override
  Future<MatchPage> matchesPage({String? cursor}) async {
    if (failInbox) throw const ApiException('network_error');
    return MatchPage(
      items: [current],
      totalCount: 42,
      unreadCount: current.unreadCount,
    );
  }

  @override
  Future<LikesPage> incomingLikes({String? cursor}) async =>
      const LikesPage(count: 6);
  @override
  Future<MatchSummary> matchDetail(String id) async {
    if (closed) throw const ApiException('match_not_found', 404);
    if (failChat) throw const ApiException('network_error');
    return current;
  }

  @override
  Future<MessagePage> messagesPage(String id, {String? cursor}) async {
    cursors.add(cursor);
    return cursor == null
        ? MessagePage(items: [...chat], nextCursor: 'older')
        : MessagePage(items: [message('0', body: 'Earlier message')]);
  }

  @override
  Future<ChatMessage> sendMessage({
    required String matchId,
    required String body,
    String? clientMessageId,
  }) async {
    sentIds.add(clientMessageId);
    if (failSend) throw const ApiException('network_error');
    final sent = message('9', sender: 'me', body: body, status: 'queued');
    chat.add(sent);
    return sent;
  }

  @override
  Future<int> markMessagesRead(String id, {String? throughMessageId}) async {
    reads.add(throughMessageId);
    return 1;
  }

  @override
  Future<void> requestReveal(String id) async {
    actions.add('request');
    if (revealFailure != null) throw ApiException(revealFailure!, 403);
    current = match(reveal: 'outgoing');
  }

  @override
  Future<void> respondReveal({
    required String matchId,
    required bool accept,
  }) async {
    actions.add(accept ? 'accept' : 'decline');
    current = match(reveal: accept ? 'revealed' : 'none');
  }

  @override
  Future<void> withdrawReveal(String id) async {
    actions.add('withdraw');
    current = match();
  }

  @override
  Future<Map<String, dynamic>> revealedIdentity(String id) async {
    identityReads++;
    if (closed) throw const ApiException('match_not_found', 403);
    return {'real_first_name': 'Test name'};
  }
}

Future<void> open(
  WidgetTester tester,
  MatchesApi api,
  Widget screen, {
  Size? size,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: screen),
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
  test('notification routes validate IDs and open the exact conversation', () {
    const id = '00000000-0000-4000-8000-000000000001';
    expect(
      notificationRoute({'type': 'chat.message', 'match_id': id}),
      '/app/matches/$id',
    );
    expect(
      notificationRoute({
        'type': 'reveal.requested',
        'match_id': '../../profile',
      }),
      '/app/matches',
    );
    expect(notificationRoute({'type': 'like.received'}), '/app/matches');
    expect(notificationRoute({'type': 'safety.panic'}), '/app/safety');
  });

  test(
    'API sends stable IDs, read anchors and signed pagination cursors',
    () async {
      final api = ApiClient(
        store: MemoryStore(),
        baseUrl: 'https://api.test/api/v1',
      );
      final requests = <Map<String, dynamic>>[];
      api.dio.httpClientAdapter = Adapter((options) {
        requests.add({
          'path': options.path,
          'query': options.queryParameters,
          'data': options.data,
        });
        if (options.path.endsWith('/read/')) {
          return jsonResponse({'marked_read': 1});
        }
        if (options.method == 'POST') {
          return jsonResponse({
            'message_id': '1',
            'sender_profile_id': 'me',
            'body': 'Hello',
          });
        }
        return jsonResponse({'items': [], 'total_count': 0, 'unread_count': 0});
      });
      await api.sendMessage(
        matchId: 'm',
        body: 'Hello',
        clientMessageId: 'stable-id',
      );
      await api.markMessagesRead('m', throughMessageId: 'visible-id');
      await api.messagesPage('m', cursor: 'signed-cursor');
      await api.matchesPage(cursor: 'inbox-cursor');
      expect((requests[0]['data'] as Map)['client_message_id'], 'stable-id');
      expect((requests[1]['data'] as Map)['through_message_id'], 'visible-id');
      expect((requests[2]['query'] as Map)['cursor'], 'signed-cursor');
      expect((requests[3]['query'] as Map)['paged'], '1');
    },
  );

  testWidgets('inbox shows real counts, previews and incoming reveal only', (
    tester,
  ) async {
    final api = MatchesApi()
      ..current = match(preview: 'A real message', unread: 3);
    await open(tester, api, const BackendMatchesScreen());
    expect(find.text('42 people'), findsOneWidget);
    expect(find.text('A real message'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('6 likes'), findsOneWidget);
    expect(find.text('Wants to reveal'), findsNothing);
    api.current = match(preview: 'A real message', reveal: 'incoming');
    await tester.tap(find.byTooltip('Refresh matches'));
    await tester.pumpAndSettle();
    expect(find.text('Wants to reveal'), findsOneWidget);
  });

  testWidgets('inbox failure offers retry and recovers', (tester) async {
    final api = MatchesApi()..failInbox = true;
    await open(tester, api, const BackendMatchesScreen());
    expect(find.text('Try again'), findsOneWidget);
    api.failInbox = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Quiet Comet'), findsWidgets);
  });

  testWidgets('long aliases and incoming reveal fit a narrow inbox', (
    tester,
  ) async {
    final api = MatchesApi()
      ..current = match(
        alias: 'A very long anonymous alias that must wrap safely',
        preview: 'A long message preview',
        reveal: 'incoming',
        unread: 100,
      );
    await open(
      tester,
      api,
      const BackendMatchesScreen(),
      size: const Size(320, 720),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat failure has retry instead of an endless spinner', (
    tester,
  ) async {
    final api = MatchesApi()..failChat = true;
    await open(tester, api, const BackendChatScreen(matchId: 'match-1'));
    expect(find.text('Retry'), findsOneWidget);
    api.failChat = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-composer')), findsOneWidget);
  });

  testWidgets(
    'failed send retains draft and retries the same ID without duplicates',
    (tester) async {
      final api = MatchesApi()..failSend = true;
      await open(tester, api, const BackendChatScreen(matchId: 'match-1'));
      await tester.enterText(
        find.byKey(const Key('chat-composer')),
        'Kind hello',
      );
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat-composer')))
            .controller!
            .text,
        'Kind hello',
      );
      api.failSend = false;
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(api.sentIds.length, 2);
      expect(api.sentIds[0], api.sentIds[1]);
      expect(api.sentIds[0], isNotNull);
      expect(find.text('Kind hello'), findsOneWidget);
      expect(find.text('Checking…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Kind hello'), findsOneWidget);
    },
  );

  testWidgets(
    'foreground chat polls and marks the displayed incoming message read',
    (tester) async {
      final api = MatchesApi()..chat = [message('1')];
      await open(tester, api, const BackendChatScreen(matchId: 'match-1'));
      expect(api.reads, contains('1'));
      api.chat.add(message('2', body: 'A new incoming message'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('A new incoming message'), findsOneWidget);
      expect(api.reads, contains('2'));
      await tester.tap(find.text('Load earlier messages'));
      await tester.pumpAndSettle();
      expect(api.cursors, contains('older'));
      expect(find.text('Earlier message'), findsOneWidget);
    },
  );

  testWidgets('incoming reveal can be accepted', (tester) async {
    final api = MatchesApi()..current = match(reveal: 'incoming');
    await open(tester, api, const BackendChatScreen(matchId: 'match-1'));
    await tester.tap(find.text('Accept reveal'));
    await tester.pumpAndSettle();
    expect(api.actions, ['accept']);
    expect(find.text('View revealed profile'), findsOneWidget);
    expect(api.identityReads, 0);
  });

  testWidgets(
    'incoming reveal can be declined and outgoing request withdrawn',
    (tester) async {
      final api = MatchesApi()..current = match(reveal: 'incoming');
      await open(tester, api, const BackendChatScreen(matchId: 'match-1'));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request reveal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Withdraw request'));
      await tester.pumpAndSettle();
      expect(api.actions, ['decline', 'request', 'withdraw']);
    },
  );

  testWidgets(
    'verification failure explains the gate without fetching private identity',
    (tester) async {
      final api = MatchesApi()
        ..revealFailure = 'verification_required_before_unmask';
      await open(tester, api, const BackendChatScreen(matchId: 'match-1'));
      await tester.tap(find.text('Request reveal'));
      await tester.pumpAndSettle();
      expect(find.text('Verification needed'), findsOneWidget);
      expect(api.identityReads, 0);
    },
  );

  testWidgets(
    'closing a match clears messages and disables the composer on refresh',
    (tester) async {
      final api = MatchesApi()..chat = [message('1')];
      await open(tester, api, const BackendChatScreen(matchId: 'match-1'));
      api.closed = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-composer')), findsNothing);
      expect(find.text('Hello there'), findsNothing);
      expect(
        find.text('This conversation is no longer available.'),
        findsWidgets,
      );
    },
  );

  testWidgets('locked likes show real count and explain Premium access', (
    tester,
  ) async {
    await open(
      tester,
      MatchesApi(),
      const Scaffold(body: IncomingLikesSheet()),
    );
    expect(find.text('6 likes'), findsOneWidget);
    expect(find.text('View Weekly Premium'), findsOneWidget);
    expect(find.text('Quiet Comet'), findsNothing);
  });

  testWidgets('revealed profile is cleared when permission is revoked', (
    tester,
  ) async {
    final api = MatchesApi();
    await open(
      tester,
      api,
      const Scaffold(
        body: RevealedProfileSheet(matchId: 'match-1', alias: 'Quiet Comet'),
      ),
    );
    expect(find.text('Test name'), findsOneWidget);
    api.closed = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Test name'), findsNothing);
    expect(
      find.textContaining('revealed profile is unavailable'),
      findsOneWidget,
    );
  });
}
