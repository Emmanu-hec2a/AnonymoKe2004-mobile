abstract class ChatConnection {
  Stream<Map<String, dynamic>> get events;
  bool get connected;
  Future<void> connect();
  bool send(Map<String, dynamic> event);
  Future<void> dispose();
}

class NoChatConnection implements ChatConnection {
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  bool get connected => false;
  @override
  Future<void> connect() async {}
  @override
  bool send(Map<String, dynamic> event) => false;
  @override
  Future<void> dispose() async {}
}
