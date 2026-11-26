import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';

final inboxProvider = NotifierProvider.autoDispose<InboxController, InboxState>(
  InboxController.new,
);

class InboxState {
  const InboxState({
    this.page,
    this.likes,
    this.sent,
    this.loading = false,
    this.error,
    this.likesError,
  });
  final MatchPage? page;
  final LikesPage? likes;

  /// Likes you sent that are still waiting; only the count is used here.
  final SentLikesPage? sent;
  final bool loading;
  final String? error;
  final String? likesError;
}

class InboxController extends Notifier<InboxState> {
  Future<void>? _running;
  bool _active = true;
  int _pages = 1;
  int _generation = 0;

  @override
  InboxState build() {
    ref.watch(authControllerProvider.select((value) => value.session?.userId));
    ref.watch(apiClientProvider);
    _pages = 1;
    _generation++;
    _running = null;
    final timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_active) unawaited(refresh());
    });
    ref.onDispose(timer.cancel);
    Future.microtask(() {
      if (ref.mounted) unawaited(refresh());
    });
    return const InboxState(loading: true);
  }

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (value) unawaited(refresh());
  }

  Future<void> refresh() {
    if (_running != null) return _running!;
    late final Future<void> operation;
    operation = _refresh(_generation).whenComplete(() {
      if (identical(_running, operation)) _running = null;
    });
    _running = operation;
    return operation;
  }

  Future<void> _refresh(int generation) async {
    if (!ref.mounted) return;
    final api = ref.read(apiClientProvider);
    // Likes do not depend on the match list or its pagination.
    final likesRequest = () async {
      try {
        final likes = await api.incomingLikes();
        if (ref.mounted && generation == _generation) {
          state = InboxState(
            page: state.page,
            likes: likes,
            sent: state.sent,
            loading: state.loading,
            error: state.error,
          );
        }
      } catch (_) {
        if (ref.mounted && generation == _generation) {
          state = InboxState(
            page: state.page,
            likes: state.likes,
            sent: state.sent,
            loading: state.loading,
            error: state.error,
            likesError: 'Likes are temporarily unavailable.',
          );
        }
      }
      // Sent likes are informational: a failure only leaves the count stale.
      try {
        final sent = await api.sentLikes();
        if (ref.mounted && generation == _generation) {
          state = InboxState(
            page: state.page,
            likes: state.likes,
            sent: sent,
            loading: state.loading,
            error: state.error,
            likesError: state.likesError,
          );
        }
      } catch (_) {}
    }();
    try {
      var page = await api.matchesPage();
      final items = [...page.items];
      var cursor = page.nextCursor;
      for (var i = 1; i < _pages && cursor != null; i++) {
        final next = await api.matchesPage(cursor: cursor);
        items.addAll(next.items);
        cursor = next.nextCursor;
      }
      if (!ref.mounted || generation != _generation) return;
      page = MatchPage(
        items: {for (final item in items) item.matchId: item}.values.toList(),
        nextCursor: cursor,
        totalCount: page.totalCount,
        unreadCount: page.unreadCount,
      );
      state = InboxState(
        page: page,
        likes: state.likes,
        sent: state.sent,
        likesError: state.likesError,
      );
    } on ApiException catch (error) {
      if (ref.mounted && generation == _generation) {
        if (error.statusCode == 401) {
          state = const InboxState(error: 'session_expired');
          _generation++;
          await likesRequest;
          return;
        }
        state = InboxState(
          page: state.page,
          likes: state.likes,
          sent: state.sent,
          error: error.code,
        );
      }
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = InboxState(
          page: state.page,
          likes: state.likes,
          sent: state.sent,
          error: 'network_error',
        );
      }
    }
    await likesRequest;
  }

  Future<void> loadMore() async {
    if (_running != null || state.page?.nextCursor == null) return;
    _pages++;
    await refresh();
  }
}
