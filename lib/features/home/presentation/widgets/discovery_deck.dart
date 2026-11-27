import 'package:flutter/material.dart';

/// Shares the drag and button animation, while keeping the card contents cached.
class DiscoveryDeck extends StatefulWidget {
  const DiscoveryDeck({
    required this.itemId,
    required this.child,
    required this.onSwipe,
    this.onBrowse,
    this.canBrowse,
    this.canBrowsePrevious = false,
    this.previousChild,
    this.nextChild,
    this.height = 500,
    this.confirmSwipe,
    this.onDetails,
    this.enabled = true,
    super.key,
  });

  final Object itemId;
  final Widget child;
  final Widget? nextChild;
  final ValueChanged<int> onSwipe;
  final ValueChanged<int>? onBrowse;
  final bool Function(int)? canBrowse;
  final bool canBrowsePrevious;
  final Widget? previousChild;
  final double height;
  final Future<bool> Function(int)? confirmSwipe;
  final VoidCallback? onDetails;
  final bool enabled;

  @override
  State<DiscoveryDeck> createState() => DiscoveryDeckState();
}

class DiscoveryDeckState extends State<DiscoveryDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _offset = ValueNotifier<double>(0);
  Animation<double>? _motion;
  double _width = 1;
  double _verticalDistance = 0;
  bool _settling = false;
  bool _browsing = false;

  bool get isAnimating => _settling;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addListener(() {
        if (_motion != null) _offset.value = _motion!.value;
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _offset.dispose();
    super.dispose();
  }

  Future<void> swipe(int direction) async {
    if (_settling || direction == 0 || !widget.enabled) return;
    _browsing = false;
    await _settle(direction.sign * (_width + 24), commit: direction.sign);
  }

  Future<void> browse(int direction) async {
    if (_settling ||
        direction == 0 ||
        !widget.enabled ||
        widget.onBrowse == null) {
      return;
    }
    _browsing = true;
    if (widget.canBrowse?.call(direction) == false) return;
    if (direction > 0 && !widget.canBrowsePrevious) {
      await _settle(0);
      return;
    }
    await _settle(direction.sign * (_width + 24), commit: direction.sign);
  }

  Future<void> _settle(double target, {int? commit}) async {
    if (_settling) return;
    _settling = true;
    final item = widget.itemId;
    // Browsing commits locally. Only explicit Like/Pass decisions await a save.
    final confirm = _browsing ? null : widget.confirmSwipe;
    final onCommit = _browsing ? widget.onBrowse : widget.onSwipe;
    final confirmation = commit != null && confirm != null
        ? Future<bool>.sync(
            () => confirm(commit!),
          ).catchError((Object _) => false)
        : Future<bool>.value(true);
    if (MediaQuery.disableAnimationsOf(context)) {
      final accepted = await confirmation;
      if (!mounted) return;
      if (commit != null && accepted && widget.itemId == item) {
        onCommit?.call(commit);
      }
      _offset.value = 0;
      _settling = false;
      return;
    }
    _controller.duration = Duration(milliseconds: commit == null ? 240 : 300);
    _motion = Tween<double>(
      begin: _offset.value,
      end: target,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);
    try {
      await _controller.forward(from: 0).orCancel;
      if (!mounted) return;
      _motion = null;
      final accepted = await confirmation;
      if (!mounted) return;
      if (!accepted && commit != null) {
        _controller.duration = const Duration(milliseconds: 240);
        _motion = Tween<double>(
          begin: _offset.value,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);
        await _controller.forward(from: 0).orCancel;
        if (!mounted) return;
        _motion = null;
        commit = null;
      }
      // The next card has already moved into the resting position.
      // Promote it and reset the transform in the same frame.
      if (commit != null && widget.itemId == item) onCommit?.call(commit);
      _offset.value = 0;
    } on TickerCanceled {
      // The route was disposed during a transition.
    } finally {
      if (mounted) {
        _motion = null;
        _offset.value = 0;
      }
      _settling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = constraints.maxWidth;
          return GestureDetector(
            onVerticalDragStart: widget.onDetails == null
                ? null
                : (_) => _verticalDistance = 0,
            onVerticalDragUpdate: widget.onDetails == null
                ? null
                : (details) => _verticalDistance += details.delta.dy,
            onVerticalDragEnd: widget.onDetails == null
                ? null
                : (details) {
                    if (!_settling &&
                        widget.enabled &&
                        (_verticalDistance < -50 ||
                            (details.primaryVelocity ?? 0) < -180)) {
                      widget.onDetails!();
                    }
                  },
            child: ClipRect(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  if (_settling || !widget.enabled) return;
                  _browsing = true;
                  _offset.value = (_offset.value + details.delta.dx).clamp(
                    -_width,
                    _width,
                  );
                },
                onHorizontalDragEnd: (details) {
                  if (_settling || !widget.enabled) return;
                  final velocity = details.primaryVelocity ?? 0;
                  final distance = _offset.value;
                  final fling =
                      velocity.abs() > 700 &&
                      distance.abs() > 12 &&
                      velocity.sign == distance.sign;
                  if (distance.abs() >= _width * .23 || fling) {
                    browse(distance.sign.toInt());
                  } else {
                    _settle(0);
                  }
                },
                onHorizontalDragCancel: () {
                  if (!_settling) _settle(0);
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      bottom: 12,
                      child: AnimatedBuilder(
                        animation: _offset,
                        builder: (context, _) {
                          final adjacent = _browsing && _offset.value > 0
                              ? widget.previousChild
                              : widget.nextChild;
                          final child = ExcludeSemantics(
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: adjacent ?? const SizedBox.shrink(),
                              ),
                            ),
                          );
                          final progress = (_offset.value.abs() / (_width * .8))
                              .clamp(0.0, 1.0);
                          return Transform.translate(
                            offset: Offset(0, 12 * (1 - progress)),
                            child: Transform.scale(
                              scaleX: .965 + .035 * progress,
                              scaleY: 1,
                              alignment: Alignment.topCenter,
                              child: child,
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned.fill(
                      bottom: 12,
                      child: AnimatedBuilder(
                        animation: _offset,
                        child: RepaintBoundary(
                          key: ValueKey(widget.itemId),
                          child: widget.child,
                        ),
                        builder: (context, child) {
                          final progress = (_offset.value.abs() / _width).clamp(
                            0.0,
                            1.0,
                          );
                          return Transform.translate(
                            offset: Offset(_offset.value, 0),
                            child: Opacity(
                              opacity: 1 - Curves.easeIn.transform(progress),
                              child: child,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
