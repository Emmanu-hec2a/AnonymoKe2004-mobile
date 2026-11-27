import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'api_client.dart';
import 'chat_contract.dart';

ChatConnection createChatConnection(ApiClient api, String matchId) =>
    NativeChatConnection(api, matchId);

class NativeChatConnection implements ChatConnection {
  NativeChatConnection(this.api, this.matchId);
  final ApiClient api;
  final String matchId;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get connected => _socket?.readyState == WebSocket.open;
  @override
  Future<void> connect() async {
    final revision = api.store.revision;
    final token = await api.store.accessToken();
    if (_disposed || revision != api.store.revision || token == null) return;
    final base = Uri.parse(api.dio.options.baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/v1/matches/$matchId/',
      query: '',
      fragment: '',
    );
    final pending = WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer $token'},
    );
    final socket = await pending.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        // A platform connection can complete after Future.timeout has returned.
        // Close that late socket instead of leaving an authenticated room open.
        unawaited(
          pending.then<void>((lateSocket) async {
            await lateSocket.close();
          }, onError: (Object _) {}),
        );
        throw TimeoutException('Chat connection timed out');
      },
    );
    if (_disposed || revision != api.store.revision) {
      await socket.close();
      return;
    }
    _socket = socket;
    socket.pingInterval = const Duration(seconds: 20);
    _subscription = socket.listen(
      (raw) {
        if (_disposed || raw is! String) return;
        if (raw.length > 262144) {
          unawaited(socket.close(1009));
          return;
        }
        try {
          final value = jsonDecode(raw);
          if (value is Map<String, dynamic>) _events.add(value);
        } catch (_) {
          /* Invalid events do not become messages. */
        }
      },
      onDone: _closed,
      onError: (Object _) => _closed(),
    );
  }

  void _closed() {
    _socket = null;
    if (!_disposed) _events.add({'type': 'connection.closed'});
  }

  @override
  bool send(Map<String, dynamic> event) {
    if (!connected || _disposed) return false;
    try {
      _socket!.add(jsonEncode(event));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    await _socket?.close();
    await _events.close();
  }
}
