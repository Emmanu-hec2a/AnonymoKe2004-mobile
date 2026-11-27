import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'chat_contract.dart';
import 'chat_transport_stub.dart' if (dart.library.io) 'chat_transport_io.dart';
export 'chat_contract.dart';

final chatConnectionProvider =
    Provider<ChatConnection Function(ApiClient, String)>(
      (_) => createChatConnection,
    );
