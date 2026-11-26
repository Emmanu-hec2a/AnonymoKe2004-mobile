import '../../../core/widgets/app_surfaces.dart';
import '../../../core/widgets/loading_skeleton.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'safety_controller.dart';
import 'widgets/safety_hold_button.dart';

final verificationLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

class BackendSafetyScreen extends ConsumerStatefulWidget {
  const BackendSafetyScreen({super.key});
  @override
  ConsumerState<BackendSafetyScreen> createState() =>
      _BackendSafetyScreenState();
}

class _BackendSafetyScreenState extends ConsumerState<BackendSafetyScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _visible = true, _foreground = true;
  ApiClient get _api => ref.read(apiClientProvider);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    ref.read(safetyProvider.notifier).setActive(_foreground && _visible);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    ref.read(safetyProvider.notifier).setActive(visible && _foreground);
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) await ref.read(safetyProvider.notifier).afterMutation();
    } on ApiException catch (error) {
      _notice(safetyError(error.code), error: true);
      // Reconcile an ambiguous response against the durable server records.
      if (mounted) unawaited(ref.read(safetyProvider.notifier).afterMutation());
    } catch (_) {
      _notice(
        'Could not complete this request. Check your connection and try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.danger : AppColors.teal,
        ),
      );
  }

  Future<void> _sendAlert(DateSafetySession session) => _perform(() async {
    final key = const Uuid().v5(
      Namespace.url.value,
      'https://anonymoke.co.ke/safety/panic/${session.id}',
    );
    await _api.triggerPanicAlert(key);
    _notice(
      'Alert saved in-app. Delivery and acknowledgement status are shown below.',
    );
  });

  Future<void> _editContact(TrustedContact? current) => _perform(() async {
    if (current?.linkedAlias != null || current?.isLinked == true) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change trusted contact?'),
          content: Text(
            'This will unlink ${current!.linkedAlias ?? current.name}. Finish or cancel your current date plan first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep contact'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unlink and change'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
      await _api.unlinkTrustedContact();
      if (!mounted) return;
    }
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ContactEditor(current: current),
    );
    if (result == null || !mounted) return;
    await _api.saveTrustedContact(
      name: result['name']!,
      phone: result['phone']!,
    );
    _notice('Contact saved. Link their account before sharing a date plan.');
  });

  Future<void> _editDate(DateSafetySession? current) => _perform(() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlanEditor(current: current),
    );
    if (result == null || !mounted) return;
    if (current == null) {
      await _api.createDateSession(
        startsAt: result['startsAt'] as DateTime,
        venueLabel: result['venue'] as String,
        checkInDueAt: result['dueAt'] as DateTime,
        shareApproximateLocation: result['share'] as bool,
      );
    } else {
      await _api.updateDateSession(
        sessionId: current.id,
        startsAt: result['startsAt'] as DateTime,
        venueLabel: result['venue'] as String,
        checkInDueAt: result['dueAt'] as DateTime,
        shareApproximateLocation: result['share'] as bool,
      );
    }
    _notice('Date plan saved and shared with your linked trusted contact.');
  });

  Future<void> _invite() => _perform(() async {
    final code = await _api.createTrustedContactInvite();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite trusted contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your contact needs an AnonymoKE account. Ask them to enter this one-time code in Safety. It expires in 24 hours.',
            ),
            const SizedBox(height: 18),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 23,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copy code'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  });

  Future<void> _acceptInvite() => _perform(() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
    if (code == null || !mounted) return;
    await _api.acceptTrustedContactInvite(code);
    _notice('Account linked. Shared date plans and alerts will appear here.');
  });

  Future<void> _cancelPlan(DateSafetySession session) => _perform(() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this date plan?'),
        content: const Text(
          'Your trusted contact will see that the plan was cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep plan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel plan'),
          ),
        ],
      ),
    );
    if (cancel == true && mounted) await _api.cancelDateSession(session.id);
  });

  Future<void> _verify() => _perform(() async {
    final notice = Uri.tryParse(
      ref.read(safetyProvider).verification?['privacy_url'] as String? ?? '',
    );
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify with Smile ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smile ID will collect a live selfie and identity document to check your identity and that you are 18 or older. Your ID and original photos are never shown in discovery. Continue only if you agree to this verification.',
            ),
            if (notice != null &&
                notice.scheme == 'https' &&
                notice.host.isNotEmpty &&
                notice.userInfo.isEmpty)
              TextButton(
                onPressed: () async {
                  try {
                    if (!await ref.read(verificationLauncherProvider)(notice)) {
                      _notice(
                        'Could not open the privacy notice.',
                        error: true,
                      );
                    }
                  } catch (_) {
                    _notice('Could not open the privacy notice.', error: true);
                  }
                },
                child: const Text('Read verification privacy notice'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agree and continue'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    final result = await _api.startIdentityVerification();
    final uri = Uri.tryParse(result['launch_url'] as String? ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      _notice(
        'Verification could not be opened. Try again later.',
        error: true,
      );
      return;
    }
    if (!await ref.read(verificationLauncherProvider)(uri)) {
      _notice(
        'Could not open verification. Check that a browser is available.',
        error: true,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(safetyProvider);
    final overview = state.overview;
    return PinnedTabBody(
      header: Row(
        children: [
          const Expanded(
            child: SectionTitle(
              'Safety center',
              subtitle: 'Tools to help you meet safely.',
            ),
          ),
          IconButton(
            tooltip: 'Refresh safety',
            onPressed: () => ref.read(safetyProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: () => ref.read(safetyProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          children: [
            if (state.error != null) ...[
              Text(
                state.error == 'session_expired'
                    ? 'Your session has expired. Please sign in again.'
                    : state.error!,
                style: const TextStyle(color: AppColors.coral),
              ),
              TextButton(
                onPressed: state.error == 'session_expired'
                    ? () => context.go('/auth')
                    : () => ref.read(safetyProvider.notifier).refresh(),
                child: Text(
                  state.error == 'session_expired' ? 'Sign in' : 'Try again',
                ),
              ),
            ],
            if (overview == null && state.error == null)
              const ContentSkeleton(content: SkeletonContent.safety),
            if (overview != null) ...[
              for (final alert in overview.incomingAlerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IncomingAlertCard(
                    alert: alert,
                    busy: _busy,
                    onAcknowledge: () =>
                        _perform(() => _api.acknowledgeSafetyAlert(alert.id)),
                  ),
                ),
              if (overview.incomingAlertCount > overview.incomingAlerts.length)
                TextButton(
                  onPressed: () => _openHistory(false),
                  child: Text('View all ${overview.incomingAlertCount} alerts'),
                ),
              _panicCard(overview),
              const SizedBox(height: 12),
              if (overview.activeDate case final session?)
                _planCard(session)
              else
                _setupCard(overview.contact),
              const SizedBox(height: 12),
              _verificationCard(state),
              const SizedBox(height: 12),
              _tips(),
              const SizedBox(height: 12),
              _contactCard(overview.contact),
              for (final plan in overview.sharedPlans)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SharedPlanCard(plan: plan),
                ),
              if (overview.sharedPlanCount > overview.sharedPlans.length)
                TextButton(
                  onPressed: () => _openHistory(true),
                  child: Text(
                    'View all ${overview.sharedPlanCount} shared plans',
                  ),
                ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  await context.push('/app/safety/management');
                  if (mounted) {
                    await ref.read(safetyProvider.notifier).refresh();
                  }
                },
                borderRadius: BorderRadius.circular(18),
                child: _panel(
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Blocked people and my reports',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppColors.secondaryText),
                    ],
                  ),
                ),
              ),
              for (final alert in overview.recentAlerts)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _deliveryCard(alert),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _openHistory(bool plans) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafetyHistorySheet(plans: plans),
  );

  Widget _panicCard(SafetyOverview overview) {
    final session = overview.activeDate;
    final enabled =
        session != null && overview.contact?.isLinked == true && !_busy;
    return _panel(
      color: AppColors.danger.withValues(alpha: .12),
      border: AppColors.danger.withValues(alpha: .45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _solidIcon(Icons.warning_amber_rounded, AppColors.danger),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panic button',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Saves an in-app alert for your trusted contact with your date details.',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (session?.status == 'panic')
            const Text(
              'Your alert is saved. You can mark yourself safe below.',
              style: TextStyle(
                color: AppColors.coral,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            SafetyHoldButton(
              enabled: enabled,
              busy: _busy,
              onSend: () => _sendAlert(session!),
            ),
          if (!enabled && !_busy && session?.status != 'panic')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                overview.contact?.isLinked != true
                    ? 'Link an AnonymoKE trusted contact first.'
                    : 'Create a date plan to enable the alert.',
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _planCard(DateSafetySession session) => _panel(
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Share my date',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Pill(
              session.status == 'panic'
                  ? 'Alert active'
                  : session.overdueAt != null
                  ? 'Overdue'
                  : 'Active',
              color: session.status == 'panic'
                  ? AppColors.coral
                  : AppColors.teal,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _dateRow('When', safetyDate(context, session.startsAt)),
        _dateRow('Where', session.venueLabel),
        _dateRow('Trusted contact', session.trustedContactName),
        _dateRow('Check-in due', safetyDate(context, session.checkInDueAt)),
        if (session.approximateArea != null)
          _dateRow('Shared area', areaLabel(session.approximateArea!)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _perform(() async {
                        await _api.markDateSafe(session.id);
                        _notice('Safe check-in saved.');
                      }),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: AppColors.ink,
                ),
                child: const Text('I am safe'),
              ),
            ),
            if (session.status == 'active') ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _editDate(session),
                  child: const Text('Edit'),
                ),
              ),
            ],
          ],
        ),
        if (session.status == 'active')
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : () => _cancelPlan(session),
              child: const Text('Cancel plan'),
            ),
          ),
      ],
    ),
  );

  Widget _setupCard(TrustedContact? contact) => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share my date',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          contact == null
              ? 'Add someone who can check on you.'
              : contact.isLinked
              ? 'Share when and where you are meeting. Check-in reminders use your selected time.'
              : 'Link your contact’s AnonymoKE account using an invite code.',
          style: const TextStyle(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy
                ? null
                : contact == null
                ? () => _editContact(null)
                : contact.isLinked
                ? () => _editDate(null)
                : _invite,
            child: Text(
              contact == null
                  ? 'Add trusted contact'
                  : contact.isLinked
                  ? 'Create date plan'
                  : 'Generate invite code',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _verificationCard(SafetyState state) {
    final status = state.verification;
    final verified =
        status?['verification_level'] == 'verified' ||
        status?['verification_level'] == 'age_verified';
    final attempts = status?['attempts'] as List? ?? const [];
    final latest = attempts.isEmpty ? null : (attempts.first as Map)['status'];
    final available = status?['available'] == true;
    return _panel(
      gradient: AppGradients.premium,
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: verified ? AppColors.teal : AppColors.accentSoft,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verified
                      ? 'Verified'
                      : latest == 'review'
                      ? 'Verification in review'
                      : latest == 'pending'
                      ? 'Verification pending'
                      : 'Get verified',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  state.verificationError ??
                      (verified
                          ? 'Your verification is complete.'
                          : !available
                          ? 'Verification is currently unavailable.'
                          : latest == 'pending'
                          ? 'Finish in your browser, then return here.'
                          : 'Smile ID checks your identity and that you are 18 or older before your first reveal.'),
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!verified && available && latest != 'review') ...[
            const SizedBox(width: 8),
            CardActionButton(
              label: latest == 'pending' ? 'Continue' : 'Start',
              onPressed: _busy ? null : _verify,
            ),
          ],
        ],
      ),
    );
  }

  Widget _tips() => _panel(
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick safety tips',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 10),
        _Tip(number: '1', text: 'Meet in a public place the first few times.'),
        _Tip(number: '2', text: 'Never send money, fare or airtime.'),
        _Tip(number: '3', text: 'Tell a friend where you are going.'),
      ],
    ),
  );

  Widget _contactCard(TrustedContact? contact) => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trusted contact',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contact?.name ?? 'Not set',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                  if (contact?.isLinked == true)
                    Text(
                      'Linked account: ${contact!.linkedAlias ?? contact.name}',
                      style: const TextStyle(
                        color: AppColors.teal,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: contact?.isLinked == true
                  ? 'Change trusted contact'
                  : 'Edit trusted contact',
              onPressed: _busy ? null : () => _editContact(contact),
              icon: Icon(
                contact?.isLinked == true
                    ? Icons.swap_horiz
                    : Icons.edit_outlined,
                color: AppColors.accentSoft,
              ),
            ),
          ],
        ),
        if (contact != null && !contact.isLinked)
          TextButton.icon(
            onPressed: _busy ? null : _invite,
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Generate in-app invite code'),
          ),
        TextButton.icon(
          onPressed: _busy ? null : _acceptInvite,
          icon: const Icon(Icons.input, size: 16),
          label: const Text('Enter someone else’s invite code'),
        ),
      ],
    ),
  );

  Widget _deliveryCard(PanicAlert alert) {
    final resolved = alert.sessionStatus == 'safe';
    final acknowledged =
        alert.acknowledgedAt != null || alert.status == 'acknowledged';
    final text = resolved
        ? 'Safe check-in shared with your trusted contact.'
        : acknowledged
        ? 'Your trusted contact acknowledged your alert.'
        : switch (alert.pushStatus) {
            'push_accepted' =>
              'Push accepted. Waiting for your contact to acknowledge.',
            'queued' ||
            'processing' => 'Alert saved in-app. Push notification pending.',
            'unavailable' =>
              'Alert saved in-app. Push is unavailable; your contact can view it in Safety.',
            'failed' =>
              'Alert saved in-app. Push attempts failed. You can retry.',
            _ => 'Alert saved in-app. Push delivery is not confirmed.',
          };
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(color: AppColors.secondaryText)),
          if (!resolved &&
              !acknowledged &&
              ['failed', 'unavailable'].contains(alert.pushStatus))
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _perform(() => _api.retrySafetyPush(alert.id)),
              child: const Text('Retry push notification'),
            ),
        ],
      ),
    );
  }
}

Widget _panel({
  required Widget child,
  Color? color,
  Color? border,
  Gradient? gradient,
}) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: gradient == null ? color ?? AppColors.surfaceRaised : null,
    gradient: gradient,
    borderRadius: BorderRadius.circular(20),
    border: border == null ? null : Border.all(color: border),
  ),
  child: child,
);
Widget _solidIcon(IconData icon, Color color) => Container(
  width: 44,
  height: 44,
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Icon(icon, color: AppColors.ink),
);
Widget _dateRow(String label, String value) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 104,
        child: Text(
          label,
          style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
        ),
      ),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
    ],
  ),
);
String safetyDate(BuildContext context, DateTime date) {
  final value = date.toLocal();
  return '${value.day}/${value.month}/${value.year} · ${TimeOfDay.fromDateTime(value).format(context)}';
}

String areaLabel(Map<String, dynamic> area) =>
    'Around ${area['latitude']}, ${area['longitude']} (≈${area['radius_km']} km)';

class IncomingAlertCard extends StatelessWidget {
  const IncomingAlertCard({
    required this.alert,
    required this.busy,
    required this.onAcknowledge,
    super.key,
  });
  final IncomingSafetyAlert alert;
  final bool busy;
  final VoidCallback onAcknowledge;
  @override
  Widget build(BuildContext context) {
    final safe = alert.sessionStatus == 'safe';
    return _panel(
      color: safe
          ? AppColors.teal.withValues(alpha: .1)
          : AppColors.danger.withValues(alpha: .12),
      border: safe
          ? AppColors.teal.withValues(alpha: .4)
          : AppColors.danger.withValues(alpha: .45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            safe
                ? '${alert.ownerAlias} checked in safe'
                : '${alert.ownerAlias} needs a check-in',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _dateRow('Where', alert.venueLabel),
          _dateRow('When', safetyDate(context, alert.startsAt)),
          _dateRow('Check-in due', safetyDate(context, alert.checkInDueAt)),
          if (alert.approximateArea != null)
            _dateRow('Shared area', areaLabel(alert.approximateArea!)),
          if (!safe && alert.status == 'unread')
            FilledButton(
              onPressed: busy ? null : onAcknowledge,
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('I can help'),
            )
          else if (!safe)
            const Text(
              'You acknowledged this alert.',
              style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class SharedPlanCard extends StatelessWidget {
  const SharedPlanCard({required this.plan, super.key});
  final DateSafetySession plan;
  @override
  Widget build(BuildContext context) => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${plan.ownerAlias} · ${plan.status == 'safe'
              ? 'Checked in safe'
              : plan.status == 'cancelled'
              ? 'Plan cancelled'
              : plan.status == 'expired'
              ? 'Plan expired without check-in'
              : plan.status == 'panic'
              ? 'Safety alert active'
              : plan.overdueAt != null
              ? 'Missed check-in'
              : 'Shared date plan'}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _dateRow('Where', plan.venueLabel),
        _dateRow('When', safetyDate(context, plan.startsAt)),
        _dateRow('Check-in due', safetyDate(context, plan.checkInDueAt)),
        if (plan.approximateArea != null)
          _dateRow('Shared area', areaLabel(plan.approximateArea!)),
        if (plan.overdueAt != null && plan.status == 'active')
          const Text(
            'This is a missed check-in, not a confirmed emergency.',
            style: TextStyle(color: AppColors.gold, fontSize: 12),
          ),
      ],
    ),
  );
}

class _Tip extends StatelessWidget {
  const _Tip({required this.number, required this.text});
  final String number, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Text(
          number,
          style: const TextStyle(
            color: AppColors.teal,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ContactEditor extends StatefulWidget {
  const _ContactEditor({this.current});
  final TrustedContact? current;
  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<_ContactEditor> {
  late final _name = TextEditingController(text: widget.current?.name ?? '');
  final _phone = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trusted contact',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose someone with an AnonymoKE account who can check on you. After saving, generate an invite code and share it with them.',
              style: TextStyle(color: AppColors.secondaryText),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? 'Enter at least two characters.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number (optional)',
                helperText:
                    'Alerts arrive in the app. No SMS or WhatsApp is sent.',
                helperMaxLines: 2,
              ),
              validator: (value) =>
                  value == null ||
                      value.trim().isEmpty ||
                      RegExp(
                        r'^(?:0[17]\d{8}|\+?254[17]\d{8})$',
                      ).hasMatch(value.trim().replaceAll(' ', ''))
                  ? null
                  : 'Enter a valid Kenyan phone number.',
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(context, {
                      'name': _name.text.trim(),
                      'phone': _phone.text.trim().replaceAll(' ', ''),
                    });
                  }
                },
                child: const Text('Save trusted contact'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _code = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter invite code'),
    content: TextField(
      controller: _code,
      textCapitalization: TextCapitalization.characters,
      maxLength: 12,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
      ],
      decoration: InputDecoration(
        labelText: 'One-time code',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          final code = _code.text.toUpperCase();
          if (![8, 12].contains(code.length)) {
            setState(() => _error = 'Enter the complete invite code.');
          } else {
            Navigator.pop(context, code);
          }
        },
        child: const Text('Link account'),
      ),
    ],
  );
}

class _PlanEditor extends StatefulWidget {
  const _PlanEditor({this.current});
  final DateSafetySession? current;
  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  late final _venue = TextEditingController(
    text: widget.current?.venueLabel ?? '',
  );
  late DateTime _start =
      widget.current?.startsAt.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  late DateTime _due =
      widget.current?.checkInDueAt.toLocal() ??
      DateTime.now().add(const Duration(hours: 3));
  late bool _share = widget.current?.shareApproximateLocation ?? false;
  String? _error;
  @override
  void dispose() {
    _venue.dispose();
    super.dispose();
  }

  Future<void> _choose(bool start) async {
    final value = start ? _start : _due;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: value.isBefore(today) ? today : value,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null || !mounted) return;
    setState(() {
      final chosen = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = chosen;
      } else {
        _due = chosen;
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Share my date',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your linked contact can see this plan. A reminder is sent near check-in time, and a missed check-in notice after a 15-minute grace period.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _venue,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Where',
              hintText: 'e.g. Rooftop lounge',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('When'),
            subtitle: Text(safetyDate(context, _start)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _choose(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Check-in due'),
            subtitle: Text(safetyDate(context, _due)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _choose(false),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _share,
            onChanged: (value) => setState(() => _share = value),
            title: const Text('Share approximate area'),
            subtitle: const Text(
              'Shares a broad area of about 12 km using your saved location, never your exact spot.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.coral),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                if (_venue.text.trim().length < 2 ||
                    !_due.isAfter(_start) ||
                    !_due.isAfter(DateTime.now()) ||
                    _due.difference(_start) > const Duration(hours: 24)) {
                  setState(
                    () => _error =
                        'Enter a venue and a future check-in within 24 hours of the start.',
                  );
                  return;
                }
                Navigator.pop(context, {
                  'venue': _venue.text.trim(),
                  'startsAt': _start,
                  'dueAt': _due,
                  'share': _share,
                });
              },
              child: Text(
                widget.current == null ? 'Share date plan' : 'Save changes',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class SafetyHistorySheet extends ConsumerStatefulWidget {
  const SafetyHistorySheet({required this.plans, super.key});
  final bool plans;
  @override
  ConsumerState<SafetyHistorySheet> createState() => _SafetyHistorySheetState();
}

class _SafetyHistorySheetState extends ConsumerState<SafetyHistorySheet>
    with WidgetsBindingObserver {
  final _alerts = <IncomingSafetyAlert>[];
  final _plans = <DateSafetySession>[];
  String? _cursor, _error;
  bool _loading = false, _more = true, _acting = false;
  Timer? _timer;
  bool _active = true, _browsingOlder = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_active && !_acting && !_browsingOlder) unawaited(_load(reset: true));
    });
    unawaited(_load());
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
    if (_active) unawaited(_load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loadingOlder = !reset && _cursor != null;
      final api = ref.read(apiClientProvider);
      if (widget.plans) {
        final page = await api.sharedSafetyPlans(
          cursor: reset ? null : _cursor,
        );
        if (!mounted) return;
        if (reset) _plans.clear();
        _plans.addAll(
          page.items.where((item) => !_plans.any((old) => old.id == item.id)),
        );
        _cursor = page.nextCursor;
      } else {
        final page = await api.incomingSafetyAlerts(
          cursor: reset ? null : _cursor,
        );
        if (!mounted) return;
        if (reset) _alerts.clear();
        _alerts.addAll(
          page.items.where((item) => !_alerts.any((old) => old.id == item.id)),
        );
        _cursor = page.nextCursor;
      }
      _more = _cursor != null;
      _browsingOlder = reset ? false : _browsingOlder || loadingOlder;
    } catch (_) {
      if (mounted) _error = 'Could not load safety history. Try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ack(String id) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await ref.read(apiClientProvider).acknowledgeSafetyAlert(id);
      if (mounted) {
        await _load(reset: true);
        if (mounted) ref.read(safetyRefreshSignal.notifier).notify();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not acknowledge this alert. Try again.');
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.plans ? 'Shared date plans' : 'Safety alerts',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.coral),
                    ),
                    TextButton(
                      onPressed: () => _load(reset: true),
                      child: const Text('Try again'),
                    ),
                  ],
                  for (final alert in _alerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: IncomingAlertCard(
                        alert: alert,
                        busy: _acting,
                        onAcknowledge: () => _ack(alert.id),
                      ),
                    ),
                  for (final plan in _plans)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SharedPlanCard(plan: plan),
                    ),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                  if (!_loading && _more)
                    TextButton(
                      onPressed: _load,
                      child: const Text('Load more'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
