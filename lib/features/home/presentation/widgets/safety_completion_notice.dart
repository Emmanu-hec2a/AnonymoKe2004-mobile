import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';

class SafetyCompletionNotice extends StatefulWidget {
  const SafetyCompletionNotice({
    required this.notice,
    required this.onDismiss,
    required this.onHistory,
    super.key,
  });
  final SafetyCompletion notice;
  final VoidCallback onDismiss, onHistory;
  @override
  State<SafetyCompletionNotice> createState() => _SafetyCompletionNoticeState();
}

class _SafetyCompletionNoticeState extends State<SafetyCompletionNotice> {
  Timer? _timer;
  bool _expired = false;
  @override
  void initState() {
    super.initState();
    _schedule(reset: true);
  }

  @override
  void didUpdateWidget(covariant SafetyCompletionNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notice.session.id != widget.notice.session.id ||
        widget.notice.expiresInSeconds <= 0) {
      _schedule(reset: true);
    }
  }

  void _schedule({required bool reset}) {
    _timer?.cancel();
    if (reset) {
      _expired = false;
    }
    // Polling or a cached response must never extend a notice's original lifetime.
    final seconds = widget.notice.expiresInSeconds.clamp(0, 300);
    _timer = Timer(Duration(seconds: seconds), () {
      if (!mounted || _expired) return;
      setState(() => _expired = true);
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_expired) return const SizedBox.shrink();
    final session = widget.notice.session;
    final title = session.viewerRole == 'owner'
        ? 'You checked in safe'
        : '${session.ownerAlias} checked in safe';
    final time = session.safeAt == null
        ? ''
        : ' · ${TimeOfDay.fromDateTime(session.safeAt!.toLocal()).format(context)}';
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('safe-completion-notice'),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
        decoration: BoxDecoration(
          color: AppColors.teal.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(
                Icons.verified_user_outlined,
                color: AppColors.teal,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saved in Safety history$time',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onHistory,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text('View history'),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss safe check-in',
              onPressed: widget.onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
