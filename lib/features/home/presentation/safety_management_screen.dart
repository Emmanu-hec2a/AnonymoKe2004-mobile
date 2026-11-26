import '../../../core/widgets/app_surfaces.dart';
import '../../../core/widgets/loading_skeleton.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'safety_controller.dart';

class SafetyManagementScreen extends ConsumerStatefulWidget {
  const SafetyManagementScreen({super.key});
  @override
  ConsumerState<SafetyManagementScreen> createState() =>
      _SafetyManagementScreenState();
}

class _SafetyManagementScreenState extends ConsumerState<SafetyManagementScreen>
    with WidgetsBindingObserver {
  RecordPage<BlockedProfile>? _blocked;
  RecordPage<SafetyReport>? _reports;
  String? _error;
  bool _loading = false, _active = true, _browsingOlder = false;
  String? _unblocking;
  Timer? _timer;
  ApiClient get _api => ref.read(apiClientProvider);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_active &&
          !_browsingOlder &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await Future.wait<Object>([
        _api.blockedPage(),
        _api.reportsPage(),
      ]);
      if (!mounted) return;
      setState(() {
        _blocked = result[0] as RecordPage<BlockedProfile>;
        _reports = result[1] as RecordPage<SafetyReport>;
        _error = null;
        _browsingOlder = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = safetyError(error.code);
          if (error.statusCode == 401) {
            _blocked = null;
            _reports = null;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not update your safety records. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more(bool blocks) async {
    if (_loading) return;
    final cursor = blocks ? _blocked?.nextCursor : _reports?.nextCursor;
    if (cursor == null) return;
    setState(() => _loading = true);
    try {
      _browsingOlder = true;
      if (blocks) {
        final page = await _api.blockedPage(cursor: cursor);
        if (mounted) {
          setState(
            () => _blocked = RecordPage(
              items: {
                for (final item in [...?_blocked?.items, ...page.items])
                  item.blockId: item,
              }.values.toList(),
              nextCursor: page.nextCursor,
              totalCount: page.totalCount,
            ),
          );
        }
      } else {
        final page = await _api.reportsPage(cursor: cursor);
        if (mounted) {
          setState(
            () => _reports = RecordPage(
              items: {
                for (final item in [...?_reports?.items, ...page.items])
                  item.reportId: item,
              }.values.toList(),
              nextCursor: page.nextCursor,
              totalCount: page.totalCount,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load more records. Pull down to refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(BlockedProfile blocked) async {
    if (_unblocking != null) return;
    setState(() => _unblocking = blocked.profileId);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Unblock ${blocked.alias}?'),
          content: const Text(
            'This removes the block. Your previous conversation stays closed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unblock'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _api.unblockProfile(blocked.profileId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Person unblocked.')));
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not unblock this person. Try again.');
      }
    } finally {
      if (mounted) setState(() => _unblocking = null);
    }
  }

  @override
  Widget build(BuildContext context) => PinnedTabBody(
    header: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/app/safety'),
          icon: const Icon(Icons.arrow_back),
        ),
        const Expanded(
          child: SectionTitle(
            'Blocked & reports',
            subtitle: 'Manage your safety decisions.',
          ),
        ),
      ],
    ),
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        children: [
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.coral)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
          _title('Blocked people', _blocked?.totalCount ?? 0),
          const SizedBox(height: 10),
          if (_blocked != null && _blocked!.items.isEmpty)
            const Text(
              'No blocked people.',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          for (final blocked in _blocked?.items ?? <BlockedProfile>[])
            _card(
              Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: AppColors.accentSoft,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      blocked.alias,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _unblocking == null
                        ? () => _unblock(blocked)
                        : null,
                    child: Text(
                      _unblocking == blocked.profileId
                          ? 'Unblocking…'
                          : 'Unblock',
                    ),
                  ),
                ],
              ),
            ),
          if (_blocked?.nextCursor != null)
            TextButton(
              onPressed: _loading ? null : () => _more(true),
              child: const Text('Load more blocked people'),
            ),
          const SizedBox(height: 24),
          _title('My reports', _reports?.totalCount ?? 0),
          const SizedBox(height: 10),
          if (_reports != null && _reports!.items.isEmpty)
            const Text(
              'No reports submitted.',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          for (final report in _reports?.items ?? <SafetyReport>[])
            _card(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_outlined, color: AppColors.coral),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.alias,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _reason(report.reason),
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(
                    _status(report.status),
                    color: report.status == 'resolved'
                        ? AppColors.teal
                        : AppColors.gold,
                  ),
                ],
              ),
            ),
          if (_reports?.nextCursor != null)
            TextButton(
              onPressed: _loading ? null : () => _more(false),
              child: const Text('Load more reports'),
            ),
          if (_loading && _blocked == null && _reports == null)
            const ContentSkeleton(content: SkeletonContent.cards)
          else if (_loading)
            const LinearProgressIndicator(),
        ],
      ),
    ),
  );

  Widget _title(String label, int count) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
      Text('$count', style: const TextStyle(color: AppColors.secondaryText)),
    ],
  );
  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );
  String _reason(String value) =>
      const {
        'solicitation': 'Commercial solicitation',
        'scam': 'Scam or fraud',
        'harassment': 'Harassment',
        'fake': 'Fake profile',
        'underage': 'Underage concern',
      }[value] ??
      'Other concern';
  String _status(String value) =>
      const {
        'review': 'In review',
        'resolved': 'Resolved',
        'dismissed': 'Dismissed',
      }[value] ??
      'Open';
}
