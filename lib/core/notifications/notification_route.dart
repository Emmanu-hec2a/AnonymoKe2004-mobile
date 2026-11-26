String notificationRoute(Map<String, dynamic> data) {
  final type = data['type'];
  if (type is String && type.startsWith('safety.')) return '/app/safety';
  if (type == 'like.received' || type == 'match.closed') return '/app/matches';
  if (type is String &&
      (type.startsWith('reveal.') ||
          type == 'chat.message' ||
          type == 'match.created')) {
    final id = data['match_id'];
    if (id is String &&
        RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id)) {
      return '/app/matches/$id';
    }
    return '/app/matches';
  }
  return '/app/discover';
}
