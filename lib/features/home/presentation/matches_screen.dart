import '../../../core/widgets/app_surfaces.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/profile_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'inbox_controller.dart';
import 'match_sheets.dart';
export 'chat_screen.dart' show BackendChatScreen;

class BackendMatchesScreen extends ConsumerWidget {
  const BackendMatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final controller = ref.read(inboxProvider.notifier);
    final page = inbox.page;
    final matches = page?.items ?? const <MatchSummary>[];
    return PinnedTabBody(
      header: Row(
        children: [
          const Expanded(
            child: Text(
              'Matches',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
          ),
          if (page != null)
            Text(
              '${page.totalCount} ${page.totalCount == 1 ? 'person' : 'people'}',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
              ),
            ),
          IconButton(
            tooltip: 'Refresh matches',
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          children: [
            if (inbox.loading && page == null)
              const ContentSkeleton(content: SkeletonContent.matches),
            if (inbox.error != null) ...[
              Text(
                inbox.error == 'session_expired'
                    ? 'Your session has expired. Sign in again.'
                    : 'Could not update your matches. Pull down to retry.',
                style: const TextStyle(color: AppColors.coral),
              ),
              TextButton(
                onPressed: inbox.error == 'session_expired'
                    ? () => context.go('/auth')
                    : controller.refresh,
                child: Text(
                  inbox.error == 'session_expired' ? 'Sign in' : 'Try again',
                ),
              ),
            ],
            if (page != null) ...[
              const SizedBox(height: 12),
              const Text(
                'New matches',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 86,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _NewMatch(
                      label: inbox.likes == null
                          ? 'Likes'
                          : '${inbox.likes!.count} likes',
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppGradients.blurredAvatar,
                          border: Border.all(color: AppColors.gold, width: 2),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const IncomingLikesSheet(),
                      ),
                    ),
                    ...matches
                        .where((match) => match.lastMessage == null)
                        .map(
                          (match) => _NewMatch(
                            label: match.alias,
                            child: MatchAvatar(
                              id: match.profileId,
                              url: match.blurredAvatarUrl,
                              size: 60,
                            ),
                            onTap: () =>
                                context.push('/app/matches/${match.matchId}'),
                          ),
                        ),
                  ],
                ),
              ),
              if (inbox.likesError != null)
                Text(
                  inbox.likesError!,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              const SizedBox(height: 16),
              const Text(
                'Messages',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 70),
                  child: Column(
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 50,
                        color: AppColors.accentSoft,
                      ),
                      SizedBox(height: 18),
                      Text('Your matches will appear here.'),
                      SizedBox(height: 8),
                      Text(
                        'Keep discovering people nearby.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ...matches.map((match) => _MatchRow(match: match)),
              if (page.nextCursor != null)
                TextButton(
                  onPressed: controller.loadMore,
                  child: const Text('Load more matches'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match});
  final MatchSummary match;
  @override
  Widget build(BuildContext context) {
    final incoming = match.revealStatus == 'incoming';
    return InkWell(
      onTap: () => context.push('/app/matches/${match.matchId}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        color: incoming ? AppColors.coral.withValues(alpha: .08) : null,
        child: Row(
          children: [
            MatchAvatar(id: match.profileId, url: match.blurredAvatarUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.alias,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (incoming)
                    const Text(
                      'Wants to reveal',
                      style: TextStyle(
                        color: AppColors.coral,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    match.lastMessage ??
                        (incoming
                            ? 'You both need to agree to reveal'
                            : 'You matched. Say hi.'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: match.unreadCount > 0
                          ? AppColors.text
                          : AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  relativeMatchTime(match.activityAt ?? match.createdAt),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                if (match.unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Badge(
                      label: Text(
                        match.unreadCount > 99 ? '99+' : '${match.unreadCount}',
                      ),
                      backgroundColor: AppColors.coral,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewMatch extends StatelessWidget {
  const _NewMatch({
    required this.label,
    required this.child,
    required this.onTap,
  });
  final String label;
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      width: 78,
      child: Column(
        children: [
          child,
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}

class MatchAvatar extends StatefulWidget {
  const MatchAvatar({required this.id, this.url, this.size = 52, super.key});
  final String id;
  final String? url;
  final double size;
  @override
  State<MatchAvatar> createState() => _MatchAvatarState();
}

class _MatchAvatarState extends State<MatchAvatar> {
  String? _url;
  DateTime _loaded = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  Widget build(BuildContext context) {
    // Reuse a valid signed URL across inbox polls to avoid repeated downloads.
    if (_url == null ||
        DateTime.now().difference(_loaded).inMinutes >= 4 ||
        (_url?.split('?').first != widget.url?.split('?').first)) {
      _url = widget.url;
      _loaded = DateTime.now();
    }
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.id.hashCode.isEven
              ? [AppColors.accent, AppColors.coral]
              : [AppColors.teal, AppColors.accent],
        ),
      ),
      child: const Icon(Icons.person, color: Colors.white30),
    );
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipOval(
        child: _url == null
            ? fallback
            : ProfileImage(
                _url!,
                decodeSize:
                    (widget.size * MediaQuery.devicePixelRatioOf(context))
                        .ceil()
                        .clamp(64, 512),
                fit: BoxFit.cover,
                fallback: fallback,
              ),
      ),
    );
  }
}

String relativeMatchTime(DateTime? date) {
  if (date == null) return 'New';
  final difference = DateTime.now().toUtc().difference(date.toUtc());
  if (difference.inMinutes < 1) return 'Now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays == 1) return 'Yesterday';
  return '${difference.inDays}d';
}
