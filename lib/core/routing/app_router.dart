import '../widgets/app_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/build_config.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/home/presentation/app_shell.dart';
import '../../features/home/presentation/discover_screen.dart';
import '../../features/home/presentation/boost_screen.dart';
import '../../features/home/presentation/matches_screen.dart';
import '../../features/home/presentation/reference_tabs.dart';
import '../../features/home/presentation/safety_screen.dart';
import '../../features/home/presentation/safety_management_screen.dart';
import '../../features/home/presentation/profile_screen.dart';
import '../../features/onboarding/presentation/onboarding_shell.dart';
import '../../features/legal/domain/legal_document.dart';
import '../../features/legal/presentation/legal_document_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/auth',
    routes: [
      _screenRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      _screenRoute(
        path: '/auth/verify',
        builder: (context, state) => const MagicLinkVerifyScreen(),
      ),
      for (final document in LegalDocumentKind.values)
        _screenRoute(
          path: document.path,
          builder: (context, state) => LegalDocumentScreen(document: document),
        ),
      _screenRoute(
        path: '/onboarding/:step',
        builder: (context, state) => OnboardingShell(
          step: (int.tryParse(state.pathParameters['step'] ?? '1') ?? 1).clamp(
            1,
            5,
          ),
        ),
      ),
      _screenRoute(path: '/app', redirect: (_, _) => '/app/discover'),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppShell(navigationShell: shell, child: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              _screenRoute(
                path: '/app/discover',
                builder: (context, state) => demoMode
                    ? const ReferenceDiscoverScreen()
                    : const BackendDiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _screenRoute(
                path: '/app/matches',
                builder: (context, state) => demoMode
                    ? const ReferenceMatchesScreen()
                    : const BackendMatchesScreen(),
                routes: [
                  _screenRoute(
                    path: ':matchId',
                    builder: (context, state) => BackendChatScreen(
                      key: ValueKey(state.pathParameters['matchId']),
                      matchId: state.pathParameters['matchId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _screenRoute(
                path: '/app/safety',
                builder: (context, state) => demoMode
                    ? const ReferenceSafetyScreen()
                    : const BackendSafetyScreen(),
                routes: [
                  _screenRoute(
                    path: 'management',
                    builder: (context, state) => const SafetyManagementScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _screenRoute(
                path: '/app/profile',
                builder: (context, state) => demoMode
                    ? const ReferenceProfileScreen()
                    : const BackendProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      _screenRoute(
        path: '/app/store',
        builder: (context, state) => Scaffold(
          body: ReferenceStoreScreen(
            initialProduct: state.extra is int ? state.extra as int : 0,
          ),
        ),
      ),
      _screenRoute(
        path: '/app/boost',
        builder: (context, state) => Scaffold(
          body: demoMode
              ? const ReferenceBoostScreen()
              : const BackendBoostScreen(),
        ),
      ),
    ],
  );
});

GoRoute _screenRoute({
  required String path,
  Widget Function(BuildContext, GoRouterState)? builder,
  GoRouterRedirect? redirect,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  redirect: redirect,
  routes: routes,
  builder: builder == null
      ? null
      : (context, state) => AppRouteSurface(child: builder(context, state)),
);
