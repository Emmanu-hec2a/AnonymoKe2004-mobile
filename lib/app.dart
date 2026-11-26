import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/auth/magic_link_intent.dart';
import 'core/config/build_config.dart';
import 'core/notifications/notification_route.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/inbox_controller.dart';
import 'features/home/presentation/safety_controller.dart';

class AnonymoKEApp extends ConsumerStatefulWidget {
  const AnonymoKEApp({super.key});

  @override
  ConsumerState<AnonymoKEApp> createState() => _AnonymoKEAppState();
}

class _AnonymoKEAppState extends ConsumerState<AnonymoKEApp> {
  String? _pendingPath;
  StreamSubscription<Uri>? _authLinks;
  @override
  void initState() {
    super.initState();
    try {
      _authLinks = ref.read(authLinkStreamProvider).listen((uri) {
        if (mounted &&
            ref.read(magicLinkIntentProvider.notifier).receive(uri)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) ref.read(routerProvider).go('/auth/verify');
          });
          WidgetsBinding.instance.scheduleFrame();
        }
      }, onError: (Object _) {});
    } catch (_) {
      // Unsupported hosts can still use social authentication or Demo preview.
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _initializeNotifications(),
    );
  }

  @override
  void dispose() {
    unawaited(_authLinks?.cancel());
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    try {
      await ref
          .read(pushNotificationServiceProvider)
          .initialize(
            onTap: _handleNotificationTap,
            onEvent: (message) {
              if (mounted &&
                  !demoMode &&
                  ref.read(authControllerProvider).session != null) {
                ref.read(inboxProvider.notifier).refresh();
                if ((message.data['type'] as String? ?? '').startsWith(
                  'safety.',
                )) {
                  ref.read(safetyRefreshSignal.notifier).notify();
                }
              }
            },
          );
    } catch (_) {
      // Notification setup must not prevent the app from opening.
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    if (!mounted) return;
    final path = notificationRoute(message.data);
    if (!demoMode && path == '/app/safety') {
      ref.read(safetyRefreshSignal.notifier).notify();
    }
    if (!demoMode &&
        ref.read(authControllerProvider).session?.isOnboarded != true) {
      _pendingPath = path;
      return;
    }
    if (!demoMode) ref.read(inboxProvider.notifier).refresh();
    ref
        .read(routerProvider)
        .go(
          demoMode && path.startsWith('/app/matches/') ? '/app/matches' : path,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.session?.isOnboarded == true && _pendingPath != null) {
        final path = _pendingPath!;
        _pendingPath = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(routerProvider).go(path);
        });
      }
    });
    return MaterialApp.router(
      title: 'AnonymoKE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
