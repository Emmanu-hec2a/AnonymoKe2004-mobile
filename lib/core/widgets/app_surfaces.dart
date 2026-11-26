import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An opaque canvas for every page in the tab navigator, including transitions.
class AppRouteSurface extends StatelessWidget {
  const AppRouteSurface({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.ink,
    child: SizedBox.expand(child: child),
  );
}

/// Keeps each tab's existing identity/header above its independently scrolling body.
class PinnedTabBody extends StatelessWidget {
  const PinnedTabBody({required this.header, required this.child, super.key});
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.ink,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          key: const Key('pinned-tab-header'),
          decoration: const BoxDecoration(
            color: AppColors.ink,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
              child: Semantics(header: true, child: header),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    ),
  );
}
