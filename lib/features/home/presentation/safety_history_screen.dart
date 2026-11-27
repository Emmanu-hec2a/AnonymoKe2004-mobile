import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/loading_skeleton.dart';
import 'safety_screen.dart' show safetyDate;

class SafetyHistoryScreen extends ConsumerStatefulWidget {
  const SafetyHistoryScreen({super.key});
  @override
  ConsumerState<SafetyHistoryScreen> createState() =>
      _SafetyHistoryScreenState();
}

class _SafetyHistoryScreenState extends ConsumerState<SafetyHistoryScreen>
    with WidgetsBindingObserver {
  final _items = <DateSafetySession>[];
  String? _cursor, _error;
  bool _loading = false,
      _loaded = false,
      _active = true,
      _older = false,
      _retryReset = true;
  int _total = 0, _epoch = 0;
  String? _owner;
  Timer? _timer;
  bool get _current =>
      mounted && _owner == ref.read(authControllerProvider).session?.userId;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(authControllerProvider).session?.userId;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load(reset: true));
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_current &&
          _active &&
          !_older &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(_load(reset: true));
      }
    });
  }

  @override
  void dispose() {
    _epoch++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (!_current || _loading || (!reset && _cursor == null)) return;
    final epoch = _epoch;
    final cursor = reset ? null : _cursor;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(apiClientProvider)
          .safetyHistory(cursor: cursor);
      if (!_current || epoch != _epoch) return;
      if (page.nextCursor != null && page.nextCursor == cursor) {
        throw const ApiException('cursor_invalid');
      }
      setState(() {
        if (reset) _items.clear();
        final seen = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => seen.add(item.id)));
        _cursor = page.nextCursor;
        _total = page.totalCount;
        _loaded = true;
        _older = !reset;
      });
    } catch (error) {
      if (_current && epoch == _epoch) {
        setState(() {
          final unauthorized = error is ApiException && error.statusCode == 401;
          if (unauthorized) {
            _items.clear();
            _cursor = null;
            _loaded = false;
          }
          _retryReset =
              reset ||
              (error is ApiException && error.code == 'cursor_invalid');
          _error = unauthorized
              ? 'Your session has expired. Sign in again.'
              : 'Could not load Safety history. Your place is kept; try again.';
        });
      }
    } finally {
      if (_current && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authControllerProvider.select((state) => state.session?.userId),
      (_, user) {
        if (user != _owner) {
          _epoch++;
          setState(() {
            _items.clear();
            _cursor = null;
            _loading = false;
            _loaded = false;
            _error = 'Your session changed. Return to Safety to continue.';
          });
        }
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety history'),
        actions: [
          IconButton(
            tooltip: 'Refresh history',
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const Text(
              'Completed plans and check-ins. One entry for each date plan.',
              style: TextStyle(color: AppColors.secondaryText, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.coral)),
              TextButton(
                onPressed: _loading ? null : () => _load(reset: _retryReset),
                child: const Text('Try again'),
              ),
            ],
            if (_loading && !_loaded)
              const ContentSkeleton(content: SkeletonContent.safety),
            if (_loaded && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Column(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: AppColors.accentSoft,
                      size: 44,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No completed plans yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your completed plans and safe check-ins will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '$_total completed ${_total == 1 ? 'plan' : 'plans'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            for (final plan in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SafetyHistoryCard(key: ValueKey(plan.id), plan: plan),
              ),
            if (_loading && _loaded)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_cursor != null)
              TextButton(
                onPressed: _loading ? null : () => _load(),
                child: const Text('Load older plans'),
              ),
          ],
        ),
      ),
    );
  }
}

class SafetyHistoryCard extends StatelessWidget {
  const SafetyHistoryCard({required this.plan, super.key});
  final DateSafetySession plan;
  @override
  Widget build(BuildContext context) {
    final safe = plan.status == 'safe';
    final label = safe
        ? 'Checked in safe'
        : plan.status == 'cancelled'
        ? 'Plan cancelled'
        : 'Ended without a check-in';
    final color = safe
        ? AppColors.teal
        : plan.status == 'expired'
        ? AppColors.gold
        : AppColors.muted;
    final when = plan.safeAt ?? plan.updatedAt ?? plan.startsAt;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Icon(
          safe ? Icons.check_circle_outline_rounded : Icons.history_rounded,
          color: color,
        ),
        title: Text(
          plan.viewerRole == 'owner' ? 'Your date plan' : plan.ownerAlias,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 12)),
            const SizedBox(height: 3),
            Text(
              safetyDate(context, when),
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
        children: [
          _row('Where', plan.venueLabel),
          _row('Date', safetyDate(context, plan.startsAt)),
          if (plan.safeAt != null)
            _row('Safe check-in', safetyDate(context, plan.safeAt!)),
          if (plan.panicAt != null)
            _row('Alert raised', safetyDate(context, plan.panicAt!)),
          if (plan.viewerRole == 'owner' && plan.trustedContactName.isNotEmpty)
            _row('Shared with', plan.trustedContactName),
          if (plan.viewerRole != 'owner')
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Shared with you',
                style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 95,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
