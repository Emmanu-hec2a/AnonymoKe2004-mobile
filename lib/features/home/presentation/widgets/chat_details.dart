import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';

class MessageTicks extends StatelessWidget {
  const MessageTicks(this.message, {super.key});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final blocked =
        message.moderationStatus == 'blocked' ||
        message.moderationStatus == 'flagged';
    final pending = message.moderationStatus == 'queued';
    final read = message.readAt != null,
        delivered = message.deliveredAt != null;
    final label = blocked
        ? 'Not delivered'
        : pending
        ? 'Checking message'
        : read
        ? 'Read'
        : delivered
        ? 'Delivered'
        : 'Sent';
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Icon(
          blocked
              ? Icons.error_outline_rounded
              : pending
              ? Icons.schedule_rounded
              : read || delivered
              ? Icons.done_all_rounded
              : Icons.done_rounded,
          key: ValueKey('message-status-${message.messageId}'),
          size: 16,
          color: blocked
              ? AppColors.coral
              : read
              ? const Color(0xFF59B5FF)
              : Colors.white70,
        ),
      ),
    );
  }
}

class SwipeReply extends StatefulWidget {
  const SwipeReply({required this.child, required this.onReply, super.key});
  final Widget child;
  final VoidCallback? onReply;
  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply>
    with SingleTickerProviderStateMixin {
  late final _reset = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  double _offset = 0, _from = 0;
  @override
  void initState() {
    super.initState();
    _reset.addListener(
      () => setState(
        () => _offset = _from * (1 - Curves.easeOut.transform(_reset.value)),
      ),
    );
  }

  @override
  void dispose() {
    _reset.dispose();
    super.dispose();
  }

  void _finish({bool commit = true}) {
    if (commit && _offset >= 42) {
      HapticFeedback.selectionClick();
      widget.onReply?.call();
    }
    _from = _offset;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _offset = 0);
    } else {
      _reset.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: widget.onReply,
    onHorizontalDragUpdate: widget.onReply == null
        ? null
        : (event) {
            _reset.stop();
            setState(() => _offset = (_offset + event.delta.dx).clamp(0, 68));
          },
    onHorizontalDragEnd: widget.onReply == null ? null : (_) => _finish(),
    onHorizontalDragCancel: widget.onReply == null
        ? null
        : () => _finish(commit: false),
    child: Stack(
      alignment: Alignment.centerLeft,
      children: [
        if (_offset > 4)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.reply_rounded,
              color: AppColors.accentSoft.withValues(
                alpha: (_offset / 42).clamp(0, 1),
              ),
            ),
          ),
        Transform.translate(offset: Offset(_offset, 0), child: widget.child),
      ],
    ),
  );
}

class DatingTypingIndicator extends StatefulWidget {
  const DatingTypingIndicator({required this.alias, super.key});
  final String alias;
  @override
  State<DatingTypingIndicator> createState() => _DatingTypingIndicatorState();
}

class _DatingTypingIndicatorState extends State<DatingTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '${widget.alias} is typing',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _animation,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  final beat =
                      (math.sin(
                            (_animation.value - index * .18) * 2 * math.pi,
                          ) +
                          1) /
                      2;
                  return Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Transform.scale(
                      scale: .75 + beat * .25,
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 10,
                        color: index == 1
                            ? AppColors.coral
                            : AppColors.accentSoft,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 7),
            const Flexible(
              child: Text(
                'Finding the right words…',
                style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
