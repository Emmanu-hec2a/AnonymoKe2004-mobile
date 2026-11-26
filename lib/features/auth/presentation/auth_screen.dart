import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/magic_link_intent.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/social_authenticator.dart';
import '../../../core/config/build_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/application/consent_documents.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _error;
  bool _submitting = false, _openingDocument = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    final session = await ref
        .read(authControllerProvider.notifier)
        .restoreSession();
    if (mounted &&
        session == null &&
        ref.read(authControllerProvider).error != null) {
      setState(
        () => _error = authErrorMessage(ref.read(authControllerProvider).error),
      );
    }
    if (!mounted ||
        session == null ||
        ref.read(magicLinkIntentProvider) != null ||
        _submitting) {
      return;
    }
    _route(session);
  }

  void _route(Session session) {
    final active = ref.read(authControllerProvider).session;
    if (active != null &&
        active.userId == session.userId &&
        active.accessToken == session.accessToken) {
      context.go(active.isOnboarded ? '/app/discover' : '/onboarding/1');
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _signIn({String? provider}) async {
    if (_submitting || ref.read(authControllerProvider).isLoading) return;
    if (provider == null && !_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final auth = ref.read(authControllerProvider.notifier);
      if (provider == null) {
        await auth.requestMagicLink(_email.text);
        if (mounted) context.go('/auth/verify');
      } else {
        final session = await auth.signInWithSocial(provider);
        if (mounted) _route(session);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = authErrorMessage(
            error is ApiException ? error.code : null,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _document(bool terms) async {
    if (_openingDocument) return;
    _openingDocument = true;
    final documents = ref.read(consentDocumentsProvider);
    final uri = terms ? documents.terms : documents.privacy;
    try {
      if (uri == null || !await openConsentDocument(context, ref, uri)) {
        if (mounted) {
          setState(
            () => _error =
                'This document is unavailable. Please try again later.',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open the document. Please try again.',
        );
      }
    } finally {
      _openingDocument = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final social = ref.watch(socialAuthenticatorProvider);
    final enabled = !state.isLoading && !_submitting;
    return Scaffold(
      body: _AuthPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _AuthBrand(),
            const SizedBox(height: 30),
            Text(
              'Meet the person\nfirst.',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Photos stay blurred until you both say yes.',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            const _Promise(
              Icons.blur_on_rounded,
              'Discover privately',
              'Blurred photos. Your alias. Your voice.',
              AppColors.accentSoft,
            ),
            const SizedBox(height: 12),
            const _Promise(
              Icons.chat_bubble_outline_rounded,
              'Connect on your terms',
              'Chat when you both like each other.',
              AppColors.coral,
            ),
            const SizedBox(height: 12),
            const _Promise(
              Icons.verified_user_outlined,
              'Reveal when you’re ready',
              'Verified people. Mutual consent.',
              AppColors.teal,
            ),
            const SizedBox(height: 26),
            if (social.supportsGoogle) ...[
              OutlinedButton.icon(
                key: const Key('auth-google'),
                onPressed: enabled ? () => _signIn(provider: 'google') : null,
                icon: ClipOval(
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Image.asset(
                        'assets/branding/google-g.png',
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
                label: _BusyLabel(
                  busy: state.action == AuthAction.google,
                  label: 'Continue with Google',
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (social.supportsApple) ...[
              OutlinedButton.icon(
                key: const Key('auth-apple'),
                onPressed: enabled ? () => _signIn(provider: 'apple') : null,
                icon: const Icon(Icons.apple, size: 24),
                label: _BusyLabel(
                  busy: state.action == AuthAction.apple,
                  label: 'Continue with Apple',
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (social.supportsGoogle || social.supportsApple) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      const Expanded(child: Divider()),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * .7,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            'or use email',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Form(
              key: _form,
              child: AutofillGroup(
                child: TextFormField(
                  key: const Key('auth-email'),
                  controller: _email,
                  enabled: enabled,
                  validator: (value) => authEmailError(value ?? ''),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.send,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 254,
                  textCapitalization: TextCapitalization.none,
                  onFieldSubmitted: (_) => _signIn(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    hintText: 'you@example.com',
                    counterText: '',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              key: const Key('auth-send'),
              onPressed: enabled ? () => _signIn() : null,
              child: _BusyLabel(
                busy: state.action == AuthAction.email,
                label: state.action == AuthAction.email
                    ? 'Sending link...'
                    : 'Send magic link',
              ),
            ),
            if (state.action == AuthAction.restore) ...[
              const SizedBox(height: 12),
              const _BusyLabel(busy: true, label: 'Restoring your session...'),
            ],
            if (_error != null && _error!.isNotEmpty) ...[
              const SizedBox(height: 14),
              _AuthError(_error!),
            ],
            const SizedBox(height: 22),
            const Text(
              '18+ only. You’ll make your privacy choices during setup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            Center(
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: enabled ? () => _document(true) : null,
                    child: const Text('Terms'),
                  ),
                  TextButton(
                    onPressed: enabled ? () => _document(false) : null,
                    child: const Text('Privacy Policy'),
                  ),
                ],
              ),
            ),
            if (demoMode)
              Center(
                child: TextButton.icon(
                  key: const Key('auth-demo'),
                  onPressed: enabled ? () => context.go('/onboarding/1') : null,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text(
                    'Preview app without an account',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MagicLinkVerifyScreen extends ConsumerStatefulWidget {
  const MagicLinkVerifyScreen({super.key});
  @override
  ConsumerState<MagicLinkVerifyScreen> createState() =>
      _MagicLinkVerifyScreenState();
}

class _MagicLinkVerifyScreenState extends ConsumerState<MagicLinkVerifyScreen> {
  Timer? _timer;
  String? _error, _failedToken, _notice;
  bool _processing = false,
      _verifying = false,
      _confirmSwitch = false,
      _scheduled = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_process());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _process() async {
    if (_confirmSwitch ||
        _processing ||
        _verifying ||
        ref.read(magicLinkIntentProvider) == null) {
      return;
    }
    _processing = true;
    try {
      await ref.read(authControllerProvider.notifier).restoreSession();
      if (!mounted ||
          ref.read(authControllerProvider).isLoading ||
          ref.read(magicLinkIntentProvider) == null) {
        return;
      }
      if (ref.read(authControllerProvider).session != null) {
        setState(() => _confirmSwitch = true);
        return;
      }
      await _verify();
    } finally {
      _processing = false;
    }
  }

  Future<void> _verify({String? retryToken}) async {
    if (_verifying || ref.read(authControllerProvider).isLoading) return;
    final token =
        retryToken ?? ref.read(magicLinkIntentProvider.notifier).take()?.token;
    if (token == null) return;
    setState(() {
      _verifying = true;
      _confirmSwitch = false;
      _error = null;
      _notice = null;
    });
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .verifyMagicLink(token);
      if (!mounted) return;
      if (ref.read(magicLinkIntentProvider) != null) {
        _schedule();
      } else {
        context.go(session.isOnboarded ? '/app/discover' : '/onboarding/1');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          final code = error is ApiException ? error.code : 'network_error';
          _error = authErrorMessage(code);
          _failedToken = {'network_error', 'rate_limited'}.contains(code)
              ? token
              : null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
        if (ref.read(magicLinkIntentProvider) != null && !_confirmSwitch) {
          _schedule();
        }
      }
    }
  }

  Future<void> _resend() async {
    final email = ref.read(authControllerProvider).pendingEmail;
    if (email == null) return;
    try {
      await ref.read(authControllerProvider.notifier).requestMagicLink(email);
      if (mounted) {
        setState(() {
          _error = null;
          _failedToken = null;
          _notice = 'Another link requested. Check your inbox and spam folder.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = authErrorMessage(
            error is ApiException ? error.code : null,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(magicLinkIntentProvider, (_, next) {
      if (next != null) _schedule();
    });
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.isLoading == true &&
          !next.isLoading &&
          ref.read(magicLinkIntentProvider) != null) {
        _schedule();
      }
    });
    final state = ref.watch(authControllerProvider);
    final busy = state.isLoading || _verifying;
    final seconds = state.resendSeconds(ref.read(authClockProvider)());
    final expiry = state.linkExpiresSeconds % 60 == 0
        ? '${state.linkExpiresSeconds ~/ 60} minutes'
        : '${state.linkExpiresSeconds} seconds';
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        body: _AuthPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('auth-email-back'),
                  tooltip: 'Use a different email',
                  onPressed: busy ? null : () => context.go('/auth'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const SizedBox(height: 26),
              const _AuthBrand(),
              const SizedBox(height: 34),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _confirmSwitch
                          ? Icons.switch_account_outlined
                          : Icons.mark_email_read_outlined,
                      color: AppColors.accentSoft,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _confirmSwitch
                          ? 'Use this sign-in link?'
                          : 'Check your email',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _confirmSwitch
                    ? 'You’re already signed in on this device. Continuing with this link may switch your account.'
                    : state.pendingEmail == null
                    ? 'Open your latest AnonymoKE sign-in email on this device.'
                    : 'We requested a sign-in link for',
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (!_confirmSwitch && state.pendingEmail != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.pendingEmail!,
                  key: const Key('auth-pending-email'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (!_confirmSwitch)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tap the link to come back here',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'It expires in $expiry and works once. Check spam or junk if you don’t see it.',
                        style: const TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              if (busy) ...[
                const SizedBox(height: 24),
                const _BusyLabel(
                  busy: true,
                  label: 'Signing you in securely...',
                ),
              ],
              if (_confirmSwitch) ...[
                ElevatedButton(
                  key: const Key('auth-confirm-link'),
                  onPressed: busy ? null : _verify,
                  child: const Text('Continue with link'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          ref.read(magicLinkIntentProvider.notifier).take();
                          final session = ref
                              .read(authControllerProvider)
                              .session;
                          context.go(
                            session?.isOnboarded == true
                                ? '/app/discover'
                                : '/onboarding/1',
                          );
                        },
                  child: const Text('Keep current account'),
                ),
              ] else ...[
                const SizedBox(height: 24),
                if (_error != null && _error!.isNotEmpty) ...[
                  _AuthError(_error!),
                  const SizedBox(height: 12),
                  if (_failedToken != null)
                    OutlinedButton(
                      key: const Key('auth-retry-link'),
                      onPressed: busy
                          ? null
                          : () => _verify(retryToken: _failedToken),
                      child: const Text('Try sign-in again'),
                    ),
                ],
                if (_notice != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _notice!,
                      style: const TextStyle(
                        color: AppColors.teal,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (state.pendingEmail != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('auth-resend'),
                    onPressed: !busy && seconds == 0 ? _resend : null,
                    child: _BusyLabel(
                      busy: state.action == AuthAction.email,
                      label: seconds > 0
                          ? 'Resend link in ${seconds}s'
                          : 'Resend sign-in link',
                    ),
                  ),
                ],
                TextButton(
                  key: const Key('auth-change-email'),
                  onPressed: busy ? null : () => context.go('/auth'),
                  child: const Text('Use a different email'),
                ),
              ],
              const SizedBox(height: 22),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.teal,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Keep your sign-in link private. We’ll never ask you to share it.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthPage extends StatelessWidget {
  const _AuthPage({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Theme(
            data: Theme.of(context).copyWith(
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentSoft,
                ),
              ),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(
          'assets/branding/anonymoke-launcher-icon.png',
          width: 50,
          height: 50,
          semanticLabel: 'AnonymoKE AK logo',
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          'AnonymoKE',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _Promise extends StatelessWidget {
  const _Promise(this.icon, this.title, this.body, this.color);
  final IconData icon;
  final String title, body;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 21, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              body,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _BusyLabel extends StatelessWidget {
  const _BusyLabel({required this.busy, required this.label});
  final bool busy;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: busy,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) ...[
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.text,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    ),
  );
}

class _AuthError extends StatelessWidget {
  const _AuthError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      key: const Key('auth-error'),
      style: const TextStyle(color: AppColors.coral, fontSize: 13, height: 1.4),
    ),
  );
}
