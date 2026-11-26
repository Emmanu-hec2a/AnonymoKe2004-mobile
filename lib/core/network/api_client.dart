import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../auth/session.dart';
import '../storage/session_store.dart';

class ApiException implements Exception {
  const ApiException(this.code, [this.statusCode]);

  final String code;
  final int? statusCode;

  @override
  String toString() => code;
}

class MagicLinkDelivery {
  const MagicLinkDelivery({
    this.resendAfterSeconds = 60,
    this.expiresInSeconds = 600,
  });
  final int resendAfterSeconds, expiresInSeconds;
}

class DiscoveryCard {
  const DiscoveryCard({
    required this.profileId,
    required this.alias,
    required this.ageYears,
    required this.distanceBucket,
    required this.interests,
    required this.isVerified,
    this.blurredAvatarUrl,
    this.audioUrl,
    this.audioDurationSeconds,
    this.bio = '',
    this.heightCm,
  });

  factory DiscoveryCard.fromJson(Map<String, dynamic> json) {
    return DiscoveryCard(
      profileId: json['profile_id'] as String,
      alias: json['alias'] as String? ?? 'Anonymous',
      ageYears: json['age_years'] as int? ?? 18,
      distanceBucket: json['distance_bucket'] as String? ?? 'Nearby',
      interests: (json['interests'] as List<dynamic>? ?? const [])
          .cast<String>(),
      isVerified: json['is_verified'] as bool? ?? false,
      blurredAvatarUrl: json['blurred_avatar_url'] as String?,
      audioUrl: json['audio_url'] as String?,
      audioDurationSeconds: (json['audio_duration_s'] as num?)?.toDouble(),
      bio: json['bio'] as String? ?? '',
      heightCm: json['height_cm'] as int?,
    );
  }

  final String profileId;
  final String alias;
  final int ageYears;
  final String distanceBucket;
  final List<String> interests;
  final bool isVerified;
  final String? blurredAvatarUrl;
  final String? audioUrl;
  final double? audioDurationSeconds;
  final String bio;
  final int? heightCm;
}

class SwipeOutcome {
  const SwipeOutcome({required this.isMatch, this.matchId, this.clientSwipeId});
  final bool isMatch;
  final String? matchId;
  final String? clientSwipeId;
}

class BoostStatus {
  const BoostStatus({this.activeUntil, this.availableBoosts = 0});
  final DateTime? activeUntil;
  final int availableBoosts;
  bool get isActive => activeUntil?.isAfter(DateTime.now()) == true;

  factory BoostStatus.fromJson(Map<String, dynamic> json) => BoostStatus(
    activeUntil: DateTime.tryParse(json['active_until'] as String? ?? ''),
    availableBoosts: json['available_boosts'] as int? ?? 0,
  );
}

class ProfileSummary {
  const ProfileSummary({
    required this.profileId,
    required this.alias,
    required this.ageYears,
    required this.gender,
    required this.heightCm,
    required this.interests,
    required this.isDiscoverable,
    required this.maxDistanceKm,
    required this.minAgePref,
    required this.maxAgePref,
    required this.verificationLevel,
    this.bio = '',
    this.targetGenders = const [],
    this.avatarUrl,
    this.avatarThumbnailUrl,
    this.hasAvatar = false,
    this.blurredAvatarUrl,
    this.audioUrl,
    this.audioDurationMs = 0,
    this.audioDisguised = false,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    return ProfileSummary(
      profileId: json['public_id'] as String,
      alias: json['alias'] as String? ?? 'Anonymous',
      ageYears: json['age_years'] as int? ?? 18,
      gender: json['gender'] as String? ?? '',
      heightCm: json['height_cm'] as int?,
      interests: (json['interests'] as List<dynamic>? ?? const [])
          .cast<String>(),
      isDiscoverable: json['is_discoverable'] as bool? ?? true,
      maxDistanceKm: json['max_distance_km'] as int? ?? 15,
      minAgePref: json['min_age_pref'] as int? ?? 18,
      maxAgePref: json['max_age_pref'] as int? ?? 35,
      verificationLevel: json['verification_level'] as String? ?? 'none',
      bio: json['bio'] as String? ?? '',
      targetGenders: (json['target_genders'] as List? ?? []).cast<String>(),
      avatarUrl: json['avatar_url'] as String?,
      avatarThumbnailUrl: json['avatar_thumbnail_url'] as String?,
      hasAvatar: json['has_avatar'] as bool? ?? (json['avatar_url'] != null),
      blurredAvatarUrl: json['blurred_avatar_url'] as String?,
      audioUrl: json['audio_url'] as String?,
      audioDurationMs: json['audio_duration_ms'] as int? ?? 0,
      audioDisguised: json['audio_disguised'] as bool? ?? false,
    );
  }

  ProfileSummary withDiscoverability(bool visible) => ProfileSummary(
    profileId: profileId,
    alias: alias,
    ageYears: ageYears,
    gender: gender,
    heightCm: heightCm,
    interests: interests,
    isDiscoverable: visible,
    maxDistanceKm: maxDistanceKm,
    minAgePref: minAgePref,
    maxAgePref: maxAgePref,
    verificationLevel: verificationLevel,
    bio: bio,
    targetGenders: targetGenders,
    avatarUrl: avatarUrl,
    avatarThumbnailUrl: avatarThumbnailUrl,
    hasAvatar: hasAvatar,
    blurredAvatarUrl: blurredAvatarUrl,
    audioUrl: audioUrl,
    audioDurationMs: audioDurationMs,
    audioDisguised: audioDisguised,
  );

  final String profileId;
  final String alias;
  final int ageYears;
  final String gender;
  final int? heightCm;
  final List<String> interests;
  final bool isDiscoverable;
  final int maxDistanceKm;
  final int minAgePref;
  final int maxAgePref;
  final String verificationLevel;
  final String bio;
  final List<String> targetGenders;
  final String? avatarUrl, avatarThumbnailUrl, blurredAvatarUrl, audioUrl;
  final int audioDurationMs;
  final bool audioDisguised;
  final bool hasAvatar;
}

class EntitlementSummary {
  const EntitlementSummary({
    required this.kind,
    required this.quantity,
    this.expiresAt,
  });

  factory EntitlementSummary.fromJson(Map<String, dynamic> json) {
    return EntitlementSummary(
      kind: json['kind'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
    );
  }

  final String kind;
  final int quantity;
  final DateTime? expiresAt;
}

class ConsentSummary {
  const ConsentSummary({
    required this.type,
    required this.granted,
    required this.version,
  });

  factory ConsentSummary.fromJson(Map<String, dynamic> json) {
    return ConsentSummary(
      type: json['type'] as String? ?? '',
      granted: json['granted'] as bool? ?? false,
      version: json['version'] as String? ?? '',
    );
  }

  final String type;
  final bool granted;
  final String version;
}

class MediaAssetSummary {
  const MediaAssetSummary({
    required this.kind,
    required this.status,
    this.durationMs,
    this.id = '',
    this.rejectionCode = '',
  });

  factory MediaAssetSummary.fromJson(Map<String, dynamic> json) {
    return MediaAssetSummary(
      kind: json['kind'] as String? ?? '',
      status: json['status'] as String? ?? '',
      durationMs: json['duration_ms'] as int?,
      id: json['upload_id'] as String? ?? '',
      rejectionCode: json['rejection_code'] as String? ?? '',
    );
  }

  final String kind;
  final String status;
  final int? durationMs;
  final String id, rejectionCode;
}

class StoreProduct {
  const StoreProduct({
    required this.code,
    required this.name,
    required this.priceKes,
    required this.kind,
    this.durationDays,
  });

  factory StoreProduct.fromJson(Map<String, dynamic> json) {
    return StoreProduct(
      code: json['code'] as String,
      name: json['name'] as String? ?? 'AnonymoKE product',
      priceKes: json['price_kes'] as int? ?? 0,
      kind: json['kind'] as String? ?? '',
      durationDays: json['duration_days'] as int?,
    );
  }

  final String code;
  final String name;
  final int priceKes;
  final String kind;
  final int? durationDays;
}

class MatchSummary {
  const MatchSummary({
    required this.matchId,
    required this.profileId,
    required this.alias,
    required this.ageYears,
    required this.state,
    required this.createdAt,
    this.viewerProfileId,
    this.lastMessage,
    this.activityAt,
    this.unreadCount = 0,
    this.revealStatus = 'none',
    this.revealCooldownUntil,
    this.blurredAvatarUrl,
    this.isVerified = false,
  });

  factory MatchSummary.fromJson(Map<String, dynamic> json) {
    return MatchSummary(
      matchId: json['match_id'] as String,
      profileId: json['profile_id'] as String,
      alias: json['alias'] as String? ?? 'Anonymous',
      ageYears: json['age_years'] as int? ?? 18,
      state: json['state'] as String? ?? 'masked',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      viewerProfileId: json['viewer_profile_id'] as String?,
      lastMessage: json['last_message'] as String?,
      activityAt: DateTime.tryParse(json['activity_at'] as String? ?? ''),
      unreadCount: json['unread_count'] as int? ?? 0,
      revealStatus: json['reveal_status'] as String? ?? 'none',
      revealCooldownUntil: DateTime.tryParse(
        json['reveal_cooldown_until'] as String? ?? '',
      ),
      blurredAvatarUrl: json['blurred_avatar_url'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
    );
  }

  final String matchId;
  final String profileId;
  final String alias;
  final int ageYears;
  final String state;
  final DateTime? createdAt;
  final String? viewerProfileId;
  final String? lastMessage;
  final DateTime? activityAt;
  final int unreadCount;
  final String revealStatus;
  final DateTime? revealCooldownUntil;
  final String? blurredAvatarUrl;
  final bool isVerified;
}

class MatchPage {
  const MatchPage({
    this.items = const [],
    this.nextCursor,
    this.totalCount = 0,
    this.unreadCount = 0,
  });
  final List<MatchSummary> items;
  final String? nextCursor;
  final int totalCount;
  final int unreadCount;
  factory MatchPage.fromJson(Map<String, dynamic> json) => MatchPage(
    items: (json['items'] as List? ?? [])
        .map(
          (item) =>
              MatchSummary.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    nextCursor: json['next_cursor'] as String?,
    totalCount: json['total_count'] as int? ?? 0,
    unreadCount: json['unread_count'] as int? ?? 0,
  );
}

class MessagePage {
  const MessagePage({this.items = const [], this.nextCursor});
  final List<ChatMessage> items;
  final String? nextCursor;
  factory MessagePage.fromJson(Map<String, dynamic> json) => MessagePage(
    items: (json['items'] as List? ?? [])
        .map(
          (item) =>
              ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );
}

class LikesPage {
  const LikesPage({
    this.items = const [],
    this.count = 0,
    this.canView = false,
    this.nextCursor,
    this.unavailableReason,
  });
  final List<DiscoveryCard> items;
  final int count;
  final bool canView;
  final String? nextCursor;
  final String? unavailableReason;
  factory LikesPage.fromJson(Map<String, dynamic> json) => LikesPage(
    items: (json['items'] as List? ?? [])
        .map(
          (item) =>
              DiscoveryCard.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    count: json['count'] as int? ?? 0,
    canView: json['can_view'] as bool? ?? false,
    nextCursor: json['next_cursor'] as String?,
    unavailableReason: json['unavailable_reason'] as String?,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.senderProfileId,
    required this.body,
    required this.moderationStatus,
    required this.createdAt,
    this.readAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: json['message_id'] as String,
      senderProfileId: json['sender_profile_id'] as String,
      body: json['body'] as String? ?? '',
      moderationStatus: json['moderation_status'] as String? ?? 'queued',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      readAt: DateTime.tryParse(json['read_at'] as String? ?? ''),
    );
  }

  final String messageId;
  final String senderProfileId;
  final String body;
  final String moderationStatus;
  final DateTime? createdAt;
  final DateTime? readAt;
}

class TrustedContact {
  const TrustedContact({
    required this.name,
    required this.phoneMasked,
    required this.isVerified,
    required this.isLinked,
    this.linkedAlias,
  });

  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    return TrustedContact(
      name: json['contact_name'] as String? ?? '',
      phoneMasked: json['phone_masked'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      isLinked: json['is_linked'] as bool? ?? false,
      linkedAlias: json['linked_alias'] as String?,
    );
  }

  final String name;
  final String phoneMasked;
  final bool isVerified;
  final bool isLinked;
  final String? linkedAlias;
}

class DateSafetySession {
  const DateSafetySession({
    required this.id,
    required this.status,
    required this.startsAt,
    required this.venueLabel,
    required this.checkInDueAt,
    required this.shareApproximateLocation,
    required this.trustedContactName,
    this.safeAt,
    this.panicAt,
    this.ownerAlias = 'Someone you trust',
    this.approximateArea,
    this.overdueAt,
  });

  factory DateSafetySession.fromJson(Map<String, dynamic> json) {
    return DateSafetySession(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'active',
      startsAt: DateTime.parse(json['starts_at'] as String),
      venueLabel: json['venue_label'] as String? ?? '',
      checkInDueAt: DateTime.parse(json['check_in_due_at'] as String),
      shareApproximateLocation:
          json['share_approximate_location'] as bool? ?? false,
      trustedContactName: json['trusted_contact_name'] as String? ?? '',
      safeAt: DateTime.tryParse(json['safe_at'] as String? ?? ''),
      panicAt: DateTime.tryParse(json['panic_at'] as String? ?? ''),
      ownerAlias: json['owner_alias'] as String? ?? 'Someone you trust',
      approximateArea: json['approximate_area'] as Map<String, dynamic>?,
      overdueAt: DateTime.tryParse(json['overdue_at'] as String? ?? ''),
    );
  }

  final String id;
  final String status;
  final DateTime startsAt;
  final String venueLabel;
  final DateTime checkInDueAt;
  final bool shareApproximateLocation;
  final String trustedContactName;
  final DateTime? safeAt;
  final DateTime? panicAt;
  final String ownerAlias;
  final Map<String, dynamic>? approximateArea;
  final DateTime? overdueAt;
}

class PanicAlert {
  const PanicAlert({
    required this.id,
    required this.status,
    required this.dateSessionId,
    this.errorCode,
    this.pushStatus = 'unavailable',
    this.acknowledgedAt,
    this.sessionStatus = 'panic',
  });

  factory PanicAlert.fromJson(Map<String, dynamic> json) {
    return PanicAlert(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'queued',
      dateSessionId: json['date_session'] as String,
      errorCode: json['error_code'] as String?,
      pushStatus: json['push_status'] as String? ?? 'unavailable',
      acknowledgedAt: DateTime.tryParse(
        json['acknowledged_at'] as String? ?? '',
      ),
      sessionStatus: json['session_status'] as String? ?? 'panic',
    );
  }

  final String id;
  final String status;
  final String dateSessionId;
  final String? errorCode;
  final String pushStatus;
  final DateTime? acknowledgedAt;
  final String sessionStatus;
}

class IncomingSafetyAlert {
  const IncomingSafetyAlert({
    required this.id,
    required this.status,
    required this.ownerAlias,
    required this.venueLabel,
    required this.startsAt,
    required this.checkInDueAt,
    required this.shareApproximateLocation,
    this.sessionStatus = 'panic',
    this.safeAt,
    this.approximateArea,
  });

  factory IncomingSafetyAlert.fromJson(Map<String, dynamic> json) {
    return IncomingSafetyAlert(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'unread',
      ownerAlias: json['owner_alias'] as String? ?? 'Someone you trust',
      venueLabel: json['venue_label'] as String? ?? '',
      startsAt: DateTime.parse(json['starts_at'] as String),
      checkInDueAt: DateTime.parse(json['check_in_due_at'] as String),
      shareApproximateLocation:
          json['share_approximate_location'] as bool? ?? false,
      sessionStatus: json['session_status'] as String? ?? 'panic',
      safeAt: DateTime.tryParse(json['safe_at'] as String? ?? ''),
      approximateArea: json['approximate_area'] as Map<String, dynamic>?,
    );
  }

  final String id;
  final String status;
  final String ownerAlias;
  final String venueLabel;
  final DateTime startsAt;
  final DateTime checkInDueAt;
  final bool shareApproximateLocation;
  final String sessionStatus;
  final DateTime? safeAt;
  final Map<String, dynamic>? approximateArea;
}

class BlockedProfile {
  const BlockedProfile({
    required this.blockId,
    required this.profileId,
    required this.alias,
    required this.createdAt,
  });

  factory BlockedProfile.fromJson(Map<String, dynamic> json) {
    return BlockedProfile(
      blockId: json['id'] as String,
      profileId: json['profile_id'] as String,
      alias: json['alias'] as String? ?? 'Anonymous',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String blockId;
  final String profileId;
  final String alias;
  final DateTime? createdAt;
}

class SafetyReport {
  const SafetyReport({
    required this.reportId,
    required this.profileId,
    required this.alias,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  factory SafetyReport.fromJson(Map<String, dynamic> json) {
    return SafetyReport(
      reportId: json['report_id'] as String,
      profileId: json['reported_profile_id'] as String,
      alias: json['reported_alias'] as String? ?? 'Anonymous',
      reason: json['reason'] as String? ?? 'other',
      status: json['status'] as String? ?? 'open',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String reportId;
  final String profileId;
  final String alias;
  final String reason;
  final String status;
  final DateTime? createdAt;
}

class SafetyOverview {
  const SafetyOverview({
    this.contact,
    this.activeDate,
    this.recentAlerts = const [],
    this.incomingAlerts = const [],
    this.sharedPlans = const [],
    this.incomingAlertCount = 0,
    this.sharedPlanCount = 0,
  });

  factory SafetyOverview.fromJson(Map<String, dynamic> json) {
    final rawAlerts = json['panic_alerts'] as List<dynamic>? ?? const [];
    final rawIncoming = json['incoming_alerts'] as List<dynamic>? ?? const [];
    return SafetyOverview(
      sharedPlans: (json['shared_plans'] as List? ?? [])
          .map(
            (item) => DateSafetySession.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      incomingAlertCount:
          json['incoming_alert_count'] as int? ?? rawIncoming.length,
      sharedPlanCount: json['shared_plan_count'] as int? ?? 0,
      contact: json['trusted_contact'] is Map<String, dynamic>
          ? TrustedContact.fromJson(
              json['trusted_contact'] as Map<String, dynamic>,
            )
          : null,
      activeDate: json['active_date'] is Map<String, dynamic>
          ? DateSafetySession.fromJson(
              json['active_date'] as Map<String, dynamic>,
            )
          : null,
      recentAlerts: rawAlerts
          .map((item) => PanicAlert.fromJson(item as Map<String, dynamic>))
          .toList(),
      incomingAlerts: rawIncoming
          .map(
            (item) =>
                IncomingSafetyAlert.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final TrustedContact? contact;
  final DateSafetySession? activeDate;
  final List<PanicAlert> recentAlerts;
  final List<IncomingSafetyAlert> incomingAlerts;
  final List<DateSafetySession> sharedPlans;
  final int incomingAlertCount;
  final int sharedPlanCount;
}

class RecordPage<T> {
  const RecordPage({
    this.items = const [],
    this.nextCursor,
    this.totalCount = 0,
  });
  final List<T> items;
  final String? nextCursor;
  final int totalCount;
  factory RecordPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) decode,
  ) => RecordPage(
    items: (json['items'] as List? ?? [])
        .map((item) => decode(Map<String, dynamic>.from(item as Map)))
        .toList(),
    nextCursor: json['next_cursor'] as String?,
    totalCount: json['total_count'] as int? ?? 0,
  );
}

class ApiClient {
  // Presigned uploads use a separate transport with no session interceptor.
  final mediaDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  ApiClient({SessionStore? store, String? baseUrl})
    : store =
          store ??
          SessionStore(
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                migrateWithBackup: true,
                resetOnError: false,
              ),
            ),
          ),
      dio = Dio(
        BaseOptions(
          baseUrl:
              baseUrl ??
              const String.fromEnvironment(
                'API_BASE_URL',
                defaultValue: 'https://api.anonymoke.co.ke/api/v1',
              ),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: const {'Accept': 'application/json'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.path.startsWith('/auth/')) {
            handler.next(options);
            return;
          }
          final token = await this.store.accessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          if (request.path.startsWith('/auth/') ||
              error.response?.statusCode != 401 ||
              request.extra['retried'] == true) {
            handler.next(error);
            return;
          }
          try {
            final session = await _refreshSession();
            request
              ..extra['retried'] = true
              ..headers['Authorization'] = 'Bearer ${session.accessToken}';
            handler.resolve(await dio.fetch(request));
          } catch (_) {
            handler.next(error);
          }
        },
      ),
    );
  }

  final SessionStore store;
  final Dio dio;
  Future<Session>? _refreshing;

  Future<MagicLinkDelivery> requestMagicLink(String email) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/auth/magic-link/request/',
        data: {'email': email},
      ),
    );
    final resend = response.data?['resend_after_seconds'] ?? 60;
    final expires = response.data?['expires_in_seconds'] ?? 600;
    if (response.data?['accepted'] != true ||
        resend is! int ||
        expires is! int ||
        resend < 1 ||
        resend > 3600 ||
        expires < 60 ||
        expires > 86400) {
      throw const ApiException('auth_response_invalid');
    }
    return MagicLinkDelivery(
      resendAfterSeconds: resend,
      expiresInSeconds: expires,
    );
  }

  Future<Session> verifyMagicLink(String token) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/auth/magic-link/verify/',
        data: {'token': token},
      ),
    );
    return Session.fromJson(response.data ?? const {});
  }

  Future<Session> verifySocialCredential({
    required String provider,
    required String credential,
  }) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/auth/social/$provider/verify/',
        data: {'credential': credential},
      ),
    );
    return Session.fromJson(response.data ?? const {});
  }

  Future<Session> refreshSession() => _refreshSession();

  Future<Session> refreshSessionForRestore() => _performRefresh(persist: false);

  Future<void> logout(String refreshToken) async {
    await _send(
      () => dio.post<void>(
        '/auth/logout/',
        data: {'refresh_token': refreshToken},
      ),
    );
  }

  Future<void> recordConsent({
    required String type,
    required String version,
    required bool granted,
  }) async {
    await _send(
      () => dio.post<void>(
        '/me/consents/',
        data: {'type': type, 'version': version, 'granted': granted},
      ),
    );
  }

  Future<void> updateProfile(Map<String, dynamic> profile) async {
    await _send(() => dio.patch<void>('/me/profile/', data: profile));
  }

  Future<Map<String, dynamic>> requestMediaUpload({
    required String kind,
    required String contentType,
    required int sizeBytes,
    bool disguiseVoice = true,
  }) async {
    final result = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/me/media/upload-url/',
        data: {
          'kind': kind,
          'content_type': contentType,
          'size_bytes': sizeBytes,
          'disguise_voice': disguiseVoice,
        },
      ),
    );
    return result.data ?? {};
  }

  Future<void> putMedia(Map<String, dynamic> ticket, List<int> bytes) async {
    final uri = Uri.tryParse(ticket['upload_url'] as String? ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const ApiException('media_upload_url_invalid');
    }
    try {
      await mediaDio.putUri(
        uri,
        data: Stream.value(bytes),
        options: Options(
          headers: {
            'Content-Type': (ticket['headers'] as Map?)?['Content-Type'],
            'Content-Length': bytes.length,
          },
          followRedirects: false,
        ),
      );
    } on DioException catch (error) {
      throw ApiException(
        error.response?.statusCode == 403
            ? 'media_upload_expired'
            : 'media_upload_failed',
      );
    }
  }

  Future<MediaAssetSummary> completeMediaUpload(String id) async {
    final result = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/me/media/complete/',
        data: {'upload_id': id},
      ),
    );
    return MediaAssetSummary.fromJson(result.data ?? {});
  }

  Future<void> deleteMedia(String kind) async {
    await _send(() => dio.delete<void>('/me/media/$kind/'));
  }

  Future<MediaAssetSummary> mediaUploadStatus(String id) async {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (!uuid.hasMatch(id)) throw const ApiException('media_upload_not_found');
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/me/media/status/$id/'),
    );
    return MediaAssetSummary.fromJson(response.data ?? {});
  }

  Future<ProfileSummary> profile() async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/me/profile/'),
    );
    return ProfileSummary.fromJson(response.data ?? const {});
  }

  Future<List<ConsentSummary>> consents() async {
    final response = await _send(() => dio.get<List<dynamic>>('/me/consents/'));
    return (response.data ?? const [])
        .map((item) => ConsentSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<MediaAssetSummary>> mediaStatus() async {
    final response = await _send(
      () => dio.get<List<dynamic>>('/me/media/status/'),
    );
    return (response.data ?? const [])
        .map((item) => MediaAssetSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<EntitlementSummary>> entitlements() async {
    final response = await _send(
      () => dio.get<List<dynamic>>('/me/entitlements/'),
    );
    return (response.data ?? const [])
        .map(
          (item) => EntitlementSummary.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<Map<String, dynamic>> exportMyData() async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>('/me/data-export/'),
    );
    return response.data ?? const {};
  }

  Future<void> deleteAccount() async {
    await _send(
      () => dio.delete<void>('/me/account/', data: {'confirm': true}),
    );
    await store.clear();
  }

  Future<void> updatePreferences(List<String> targetGenders) async {
    await _send(
      () => dio.put<void>(
        '/me/preferences/',
        data: {'target_genders': targetGenders},
      ),
    );
  }

  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
    bool isMock = false,
  }) async {
    await _send(
      () => dio.put<void>(
        '/me/location/',
        data: {
          'lat': latitude,
          'lon': longitude,
          'accuracy_m': accuracyMeters,
          'is_mock': isMock,
          'captured_at': capturedAt.toUtc().toIso8601String(),
        },
      ),
    );
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? appVersion,
  }) async {
    await _send(
      () => dio.post<void>(
        '/me/notifications/devices/',
        data: {
          'token': token,
          'platform': platform,
          'app_version': ?appVersion,
        },
      ),
    );
  }

  Future<void> unregisterDeviceToken(String token) async {
    await _send(
      () => dio.delete<void>(
        '/me/notifications/devices/',
        data: {'token': token},
      ),
    );
  }

  Future<void> startAgeVerification() async {
    await _send(
      () => dio.post<void>(
        '/me/verification/start/',
        data: {'purpose': 'age_check', 'consent': true},
      ),
    );
  }

  Future<Map<String, dynamic>> startIdentityVerification() async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/me/verification/start/',
        data: {'purpose': 'identity_check', 'consent': true},
      ),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> verificationStatus() async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/me/verification/status/'),
    );
    return response.data ?? const {};
  }

  Future<void> unlinkTrustedContact() async {
    await _send(() => dio.post<void>('/me/safety/trusted-contact/unlink/'));
  }

  Future<void> retrySafetyPush(String alertId) async {
    await _send(() => dio.post<void>('/me/safety/panic/$alertId/retry/'));
  }

  Future<RecordPage<T>> _recordPage<T>(
    String path,
    T Function(Map<String, dynamic>) decode, {
    String? cursor,
  }) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {'paged': '1', 'cursor': ?cursor},
      ),
    );
    return RecordPage.fromJson(response.data ?? const {}, decode);
  }

  Future<RecordPage<IncomingSafetyAlert>> incomingSafetyAlerts({
    String? cursor,
  }) => _recordPage(
    '/me/safety/alerts/',
    IncomingSafetyAlert.fromJson,
    cursor: cursor,
  );
  Future<RecordPage<DateSafetySession>> sharedSafetyPlans({String? cursor}) =>
      _recordPage(
        '/me/safety/shared-plans/',
        DateSafetySession.fromJson,
        cursor: cursor,
      );
  Future<RecordPage<BlockedProfile>> blockedPage({String? cursor}) =>
      _recordPage('/blocks/', BlockedProfile.fromJson, cursor: cursor);
  Future<RecordPage<SafetyReport>> reportsPage({String? cursor}) =>
      _recordPage('/reports/', SafetyReport.fromJson, cursor: cursor);

  Future<List<StoreProduct>> storeProducts() async {
    final response = await _send(
      () => dio.get<List<dynamic>>('/store/products/'),
    );
    return (response.data ?? const [])
        .map((item) => StoreProduct.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createPurchase({
    required String productCode,
    required String phone,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/purchases/',
        data: {'product_code': productCode, 'phone': phone},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      ),
    );
    return response.data ?? const {};
  }

  Future<List<MatchSummary>> matches() async {
    final response = await _send(() => dio.get<List<dynamic>>('/matches/'));
    return (response.data ?? const [])
        .map((item) => MatchSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MatchPage> matchesPage({String? cursor}) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>(
        '/matches/',
        queryParameters: {'paged': '1', 'cursor': ?cursor},
      ),
    );
    return MatchPage.fromJson(response.data ?? const {});
  }

  Future<LikesPage> incomingLikes({String? cursor}) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>(
        '/likes/',
        queryParameters: {'cursor': ?cursor},
      ),
    );
    return LikesPage.fromJson(response.data ?? const {});
  }

  Future<MatchSummary> matchDetail(String matchId) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/matches/$matchId/'),
    );
    return MatchSummary.fromJson(response.data ?? const {});
  }

  Future<List<ChatMessage>> messages(String matchId) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/matches/$matchId/messages/'),
    );
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String matchId,
    required String body,
    String? clientMessageId,
  }) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/matches/$matchId/messages/',
        data: {'body': body, 'client_message_id': ?clientMessageId},
      ),
    );
    return ChatMessage.fromJson(response.data ?? const {});
  }

  Future<MessagePage> messagesPage(String matchId, {String? cursor}) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>(
        '/matches/$matchId/messages/',
        queryParameters: {'paged': '1', 'cursor': ?cursor},
      ),
    );
    return MessagePage.fromJson(response.data ?? const {});
  }

  Future<int> markMessagesRead(
    String matchId, {
    String? throughMessageId,
  }) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/matches/$matchId/read/',
        data: {'through_message_id': ?throughMessageId},
      ),
    );
    return response.data?['marked_read'] as int? ?? 0;
  }

  Future<void> requestReveal(String matchId) async {
    await _send(() => dio.post<void>('/matches/$matchId/unmask/request/'));
  }

  Future<void> respondReveal({
    required String matchId,
    required bool accept,
  }) async {
    await _send(
      () => dio.post<void>(
        '/matches/$matchId/unmask/respond/',
        data: {'accept': accept},
      ),
    );
  }

  Future<void> withdrawReveal(String matchId) async {
    await _send(() => dio.post<void>('/matches/$matchId/unmask/withdraw/'));
  }

  Future<Map<String, dynamic>> revealedIdentity(String matchId) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/matches/$matchId/revealed/'),
    );
    return response.data ?? const {};
  }

  Future<void> unmatch(String matchId) async {
    await _send(() => dio.delete<void>('/matches/$matchId/'));
  }

  Future<SafetyOverview> safetyOverview() async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/me/safety/'),
    );
    return SafetyOverview.fromJson(response.data ?? const {});
  }

  Future<TrustedContact> saveTrustedContact({
    required String name,
    required String phone,
  }) async {
    final response = await _send(
      () => dio.put<Map<String, dynamic>>(
        '/me/safety/trusted-contact/',
        data: {'contact_name': name, 'phone': phone},
      ),
    );
    return TrustedContact.fromJson(response.data ?? const {});
  }

  Future<String> createTrustedContactInvite() async {
    final response = await _send(
      () =>
          dio.post<Map<String, dynamic>>('/me/safety/trusted-contact/invite/'),
    );
    return response.data?['invite_code'] as String? ?? '';
  }

  Future<void> acceptTrustedContactInvite(String inviteCode) async {
    await _send(
      () => dio.post<void>(
        '/me/safety/trusted-contact/accept/',
        data: {'invite_code': inviteCode},
      ),
    );
  }

  Future<void> acknowledgeSafetyAlert(String recipientId) async {
    await _send(() => dio.post<void>('/me/safety/alerts/$recipientId/ack/'));
  }

  Future<List<BlockedProfile>> blockedProfiles() async {
    final response = await _send(() => dio.get<List<dynamic>>('/blocks/'));
    return (response.data ?? const [])
        .map((item) => BlockedProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SafetyReport>> safetyReports() async {
    final response = await _send(() => dio.get<List<dynamic>>('/reports/'));
    return (response.data ?? const [])
        .map((item) => SafetyReport.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> unblockProfile(String profileId) async {
    await _send(() => dio.delete<void>('/blocks/$profileId/'));
  }

  Future<void> blockProfile(String profileId) async {
    await _send(
      () => dio.post<void>('/blocks/', data: {'profile_id': profileId}),
    );
  }

  Future<void> reportProfile({
    required String profileId,
    required String reason,
    String note = '',
    List<String> messageIds = const [],
  }) async {
    await _send(
      () => dio.post<void>(
        '/reports/',
        data: {
          'profile_id': profileId,
          'reason': reason,
          if (note.isNotEmpty) 'note': note,
          if (messageIds.isNotEmpty) 'message_ids': messageIds,
        },
      ),
    );
  }

  Future<DateSafetySession> createDateSession({
    required DateTime startsAt,
    required String venueLabel,
    required DateTime checkInDueAt,
    required bool shareApproximateLocation,
  }) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/me/safety/dates/',
        data: {
          'starts_at': startsAt.toUtc().toIso8601String(),
          'venue_label': venueLabel,
          'check_in_due_at': checkInDueAt.toUtc().toIso8601String(),
          'share_approximate_location': shareApproximateLocation,
        },
      ),
    );
    return DateSafetySession.fromJson(response.data ?? const {});
  }

  Future<DateSafetySession> updateDateSession({
    required String sessionId,
    required DateTime startsAt,
    required String venueLabel,
    required DateTime checkInDueAt,
    required bool shareApproximateLocation,
  }) async {
    final response = await _send(
      () => dio.patch<Map<String, dynamic>>(
        '/me/safety/dates/$sessionId/',
        data: {
          'starts_at': startsAt.toUtc().toIso8601String(),
          'venue_label': venueLabel,
          'check_in_due_at': checkInDueAt.toUtc().toIso8601String(),
          'share_approximate_location': shareApproximateLocation,
        },
      ),
    );
    return DateSafetySession.fromJson(response.data ?? const {});
  }

  Future<void> cancelDateSession(String sessionId) async {
    await _send(() => dio.delete<void>('/me/safety/dates/$sessionId/'));
  }

  Future<DateSafetySession> markDateSafe(String sessionId) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>('/me/safety/dates/$sessionId/safe/'),
    );
    return DateSafetySession.fromJson(response.data ?? const {});
  }

  Future<PanicAlert> triggerPanicAlert(String idempotencyKey) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/me/safety/panic/',
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      ),
    );
    return PanicAlert.fromJson(response.data ?? const {});
  }

  Future<PanicAlert> panicAlertStatus(String alertId) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/me/safety/panic/$alertId/'),
    );
    return PanicAlert.fromJson(response.data ?? const {});
  }

  Future<List<DiscoveryCard>> discovery({
    String? cursor,
    int? maxDistanceKm,
    int? minAge,
    int? maxAge,
  }) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>(
        '/discover/',
        queryParameters: {
          'cursor': ?cursor,
          'max_distance_km': ?maxDistanceKm,
          'min_age': ?minAge,
          'max_age': ?maxAge,
        },
      ),
    );
    final raw = response.data?['items'] as List<dynamic>? ?? const [];
    return raw
        .map((item) => DiscoveryCard.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DiscoveryCard> discoveryProfile(String profileId) async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/discover/$profileId/'),
    );
    return DiscoveryCard.fromJson(response.data!);
  }

  Future<BoostStatus> boostStatus() async {
    final response = await _send(
      () => dio.get<Map<String, dynamic>>('/me/boost/'),
    );
    return BoostStatus.fromJson(response.data!);
  }

  Future<BoostStatus> activateBoost(String activationId) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/me/boost/',
        data: {'client_activation_id': activationId},
      ),
    );
    return BoostStatus.fromJson(response.data!);
  }

  /// Withdraws the swipe with [clientSwipeId]: the latest pass (premium) or
  /// any like that has not become a match.
  Future<void> undoPass(String clientSwipeId) async {
    await _send(
      () => dio.post<void>(
        '/swipes/undo/',
        data: {'client_swipe_id': clientSwipeId},
      ),
    );
  }

  Future<SwipeOutcome> swipe({
    required String profileId,
    required String action,
    String? clientSwipeId,
  }) async {
    final response = await _send(
      () => dio.post<Map<String, dynamic>>(
        '/swipes/',
        data: {
          'profile_id': profileId,
          'action': action,
          'client_swipe_id': clientSwipeId ?? const Uuid().v4(),
        },
      ),
    );
    return SwipeOutcome(
      isMatch: response.data?['is_match'] == true,
      matchId: response.data?['match_id'] as String?,
      clientSwipeId: response.data?['client_swipe_id'] as String?,
    );
  }

  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      final data = error.response?.data;
      final errorMap = data is Map<String, dynamic> ? data['error'] : null;
      final code = errorMap is Map<String, dynamic> ? errorMap['code'] : null;
      final status = error.response?.statusCode;
      throw ApiException(
        code as String? ??
            (status == 401
                ? 'session_expired'
                : status == 429
                ? 'rate_limited'
                : 'network_error'),
        status,
      );
    }
  }

  Future<Session> _refreshSession() {
    return _refreshing ??= _performRefresh().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<Session> _performRefresh({bool persist = true}) async {
    final revision = store.revision;
    final refreshToken = await store.refreshToken();
    if (store.revision != revision) {
      throw const ApiException('auth_operation_cancelled');
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException('refresh_token_missing');
    }
    try {
      final refreshDio = Dio(dio.options.copyWith(baseUrl: dio.options.baseUrl))
        ..httpClientAdapter = dio.httpClientAdapter;
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/auth/token/refresh/',
        data: {'refresh_token': refreshToken},
      );
      final session = Session.fromJson(response.data ?? const {});
      if (store.revision != revision) {
        throw const ApiException('auth_operation_cancelled');
      }
      if (persist) {
        await store.saveRefreshedSession(session, expectedRevision: revision);
      }
      return session;
    } on SessionStoreChanged {
      throw const ApiException('auth_operation_cancelled');
    } on DioException catch (error) {
      throw ApiException(
        error.response?.statusCode == 401
            ? 'refresh_token_invalid'
            : 'network_error',
        error.response?.statusCode,
      );
    }
  }
}
