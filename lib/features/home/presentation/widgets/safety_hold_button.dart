import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class SafetyHoldButton extends StatefulWidget {
  const SafetyHoldButton({
    required this.enabled,
    required this.busy,
    required this.onSend,
    super.key,
  });
  final bool enabled, busy;
  final VoidCallback onSend;
  @override
  State<SafetyHoldButton> createState() => _SafetyHoldButtonState();
}

class _SafetyHoldButtonState extends State<SafetyHoldButton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _hold;
  bool _fired = false;
  Offset? _holdOrigin;
  int? _pointer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hold =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed &&
                !_fired &&
                widget.enabled &&
                !widget.busy) {
              _fired = true;
              widget.onSend();
            }
          });
  }

  void _cancel() {
    // Pointer-up can arrive after a successful send has replaced this list child.
    if (!mounted) return;
    _hold.stop();
    _hold.value = 0;
    _fired = false;
    _holdOrigin = null;
    _pointer = null;
  }

  @override
  void didUpdateWidget(covariant SafetyHoldButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.busy) _cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hold.dispose();
    super.dispose();
  }

  Future<void> _accessibleSend() async {
    if (!widget.enabled || widget.busy) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send safety alert?'),
        content: const Text(
          'Your trusted contact will receive an in-app alert with your date details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send alert'),
          ),
        ],
      ),
    );
    if (send == true && mounted && widget.enabled && !widget.busy) {
      widget.onSend();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled && !widget.busy,
    label: 'Send safety alert',
    onTap: _accessibleSend,
    child: ExcludeSemantics(
      child: Listener(
        onPointerDown: widget.enabled && !widget.busy
            ? (event) {
                if (_pointer != null) {
                  _cancel();
                  return;
                }
                _pointer = event.pointer;
                _holdOrigin = event.position;
                _fired = false;
                _hold.forward(from: 0);
              }
            : null,
        onPointerUp: (_) => _cancel(),
        onPointerCancel: (_) => _cancel(),
        onPointerMove: (event) {
          if (_pointer == event.pointer &&
              _holdOrigin != null &&
              (event.position - _holdOrigin!).distance > 20) {
            _cancel();
          }
        },
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) => ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: widget.enabled
                          ? AppColors.danger
                          : AppColors.danger.withValues(alpha: .45),
                    ),
                  ),
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _hold.value,
                        child: const ColoredBox(
                          color: Colors.white24,
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      widget.busy
                          ? 'Saving alert…'
                          : widget.enabled
                          ? 'Hold to send alert'
                          : 'Set up a date to enable',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
