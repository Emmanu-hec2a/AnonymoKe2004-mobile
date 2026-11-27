import 'api_client.dart';
import 'chat_contract.dart';

ChatConnection createChatConnection(ApiClient api, String matchId) =>
    NoChatConnection();
