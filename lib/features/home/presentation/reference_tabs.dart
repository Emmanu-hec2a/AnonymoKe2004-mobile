import '../../../core/widgets/app_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/build_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/verified_badge.dart';
import 'widgets/discovery_deck.dart';
import '../../legal/presentation/consent_document_links.dart';

final demoProfilePausedProvider =
    NotifierProvider<DemoProfilePauseController, bool>(
      DemoProfilePauseController.new,
    );

class DemoProfilePauseController extends Notifier<bool> {
  @override
  bool build() => false;
  void setPaused(bool value) => state = value;
}

class ReferenceDiscoverScreen extends ConsumerStatefulWidget {
  const ReferenceDiscoverScreen({super.key});

  @override
  ConsumerState<ReferenceDiscoverScreen> createState() =>
      _ReferenceDiscoverScreenState();
}

class _ReferenceDiscoverScreenState
    extends ConsumerState<ReferenceDiscoverScreen> {
  var _cardIndex = 0;
  double _distanceKm = 5;
  RangeValues _ageRange = const RangeValues(24, 34);
  final _deckKey = GlobalKey<DiscoveryDeckState>();

  @override
  Widget build(BuildContext context) {
    if (ref.watch(demoProfilePausedProvider)) {
      return AppPage(
        child: Column(
          children: [
            _topBar(),
            const SizedBox(height: 80),
            const Icon(
              Icons.pause_circle_outline,
              color: AppColors.accentSoft,
              size: 48,
            ),
            const SizedBox(height: 18),
            const Text(
              'Your profile is paused.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () =>
                  ref.read(demoProfilePausedProvider.notifier).setPaused(false),
              child: const Text('Resume my profile'),
            ),
          ],
        ),
      );
    }
    final names = ['Westlands Nomad', 'Kilimani Sunset', 'Karen Coffee Snob'];
    final name = names[_cardIndex % names.length];
    final nextName = names[(_cardIndex + 1) % names.length];
    return AppPage(
      child: Column(
        children: [
          _topBar(),
          const SizedBox(height: 14),
          _swipeDeck(name, nextName),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _circleAction(Icons.undo_rounded, AppColors.gold, _undo),
              const SizedBox(width: 22),
              _circleAction(
                Icons.close_rounded,
                AppColors.text,
                () => _deckKey.currentState?.swipe(-1),
                large: true,
              ),
              const SizedBox(width: 22),
              _circleAction(
                Icons.favorite_rounded,
                AppColors.ink,
                () => _deckKey.currentState?.swipe(1),
                large: true,
                background: AppColors.coral,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swipeDeck(String name, String nextName) {
    return DiscoveryDeck(
      key: _deckKey,
      itemId: _cardIndex,
      nextChild: _discoverCard(nextName),
      onSwipe: (_) => setState(() => _cardIndex++),
      canBrowsePrevious: _cardIndex > 0,
      onBrowse: (direction) =>
          setState(() => _cardIndex += direction < 0 ? 1 : -1),
      previousChild: _cardIndex > 0
          ? _discoverCard(
              [
                'Westlands Nomad',
                'Kilimani Sunset',
                'Karen Coffee Snob',
              ][(_cardIndex - 1) % 3],
            )
          : null,
      child: _discoverCard(name),
    );
  }

  void _undo() {
    if (_deckKey.currentState?.isAnimating == true || _cardIndex == 0) return;
    setState(() => _cardIndex--);
  }

  Widget _topBar() {
    return Row(
      children: [
        const Expanded(child: BrandHeaderLogo()),
        const SizedBox(width: 10),
        _squareAction(
          Icons.tune_rounded,
          AppColors.surface,
          onTap: _showFilters,
        ),
        const SizedBox(width: 10),
        _squareAction(
          Icons.bolt_rounded,
          AppColors.gold,
          onTap: () => context.push('/app/boost'),
        ),
      ],
    );
  }

  Widget _squareAction(IconData icon, Color background, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(
          icon,
          color: background == AppColors.gold ? AppColors.ink : AppColors.text,
        ),
      ),
    );
  }

  Future<void> _showFilters() async {
    var distanceKm = _distanceKm;
    var ageRange = _ageRange;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.strongLine,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filters',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Location',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          'Within ${distanceKm.round()} km',
                          style: const TextStyle(color: AppColors.accentSoft),
                        ),
                      ],
                    ),
                    Slider(
                      value: distanceKm,
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: '${distanceKm.round()} km',
                      onChanged: (value) =>
                          setModalState(() => distanceKm = value),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Age range',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${ageRange.start.round()}–${ageRange.end.round()}',
                          style: const TextStyle(color: AppColors.accentSoft),
                        ),
                      ],
                    ),
                    RangeSlider(
                      values: ageRange,
                      min: 18,
                      max: 40,
                      divisions: 22,
                      labels: RangeLabels(
                        '${ageRange.start.round()}',
                        '${ageRange.end.round()}',
                      ),
                      onChanged: (value) =>
                          setModalState(() => ageRange = value),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _distanceKm = 5;
                              _ageRange = const RangeValues(18, 40);
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Clear filters'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _distanceKm = distanceKm;
                                _ageRange = ageRange;
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('Apply filters'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _discoverCard(String name) {
    return Container(
      height: 500,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppGradients.blurredAvatar),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.12),
                  radius: .62,
                  colors: [
                    Color(0xD9FFD8B5),
                    Color(0x66FFD8B5),
                    Color(0x00FFD8B5),
                  ],
                  stops: [0, .3, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.ink.withValues(alpha: .12),
                    AppColors.ink.withValues(alpha: .95),
                  ],
                  stops: const [.35, .65, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: _glassPill(Icons.location_on_outlined, _distanceLabel()),
          ),
          Positioned(top: 14, right: 14, child: _voicePill()),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const VerifiedBadge(),
                  ],
                ),
                const SizedBox(height: 5),
                const Text(
                  '26 · Software engineer',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: const [
                    Pill('Afrohouse', color: AppColors.secondaryText),
                    Pill('Sunday brunch', color: AppColors.secondaryText),
                    Pill('Hiking', color: AppColors.secondaryText),
                    Pill('Tech', color: AppColors.secondaryText),
                  ],
                ),
                const SizedBox(height: 34),
                const Center(
                  child: Text(
                    'Drag up for more',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassPill(IconData icon, String label, {bool play = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (play) ...[
            const Icon(
              Icons.play_arrow_rounded,
              color: AppColors.text,
              size: 16,
            ),
            const SizedBox(width: 5),
          ],
          Icon(
            icon,
            color: play ? AppColors.accentSoft : AppColors.text,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _voicePill() {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 27,
            height: 27,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: AppColors.text,
              size: 17,
            ),
          ),
          const SizedBox(width: 7),
          const Icon(Icons.graphic_eq, color: AppColors.accentSoft, size: 18),
          const SizedBox(width: 5),
          const Text(
            '0:12',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  String _distanceLabel() {
    return _distanceKm.round() == 5
        ? '2-5 km away'
        : 'Within ${_distanceKm.round()} km';
  }

  Widget _circleAction(
    IconData icon,
    Color iconColor,
    VoidCallback onPressed, {
    bool large = false,
    Color? background,
  }) {
    final size = large ? 68.0 : 50.0;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(icon, color: iconColor, size: large ? 30 : 22),
      ),
    );
  }
}

class ReferenceMatchesScreen extends StatelessWidget {
  const ReferenceMatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PinnedTabBody(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Matches',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const Text(
            '5 people',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
        ],
      ),
      child: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New matches',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 95,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  _NewMatch(
                    label: '6 likes',
                    locked: true,
                    colors: [AppColors.gold, AppColors.coral],
                  ),
                  _NewMatch(
                    label: 'Lavington',
                    colors: [AppColors.accentSoft, AppColors.coral],
                  ),
                  _NewMatch(
                    label: 'South B',
                    colors: [AppColors.teal, AppColors.accent],
                  ),
                  _NewMatch(
                    label: 'Ngong',
                    colors: [AppColors.coral, AppColors.gold],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Messages',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _message(
              'Westlands Nomad',
              'You both need to agree to reveal',
              '12 min',
              badge: 'Wants to reveal',
              highlight: true,
              colors: [AppColors.accent, AppColors.coral],
            ),
            _message(
              'Kilimani Sunset',
              'Haha that voice note though',
              '1h',
              unread: true,
              colors: [AppColors.teal, AppColors.accent],
            ),
            _message(
              'Karen Coffee Snob',
              'What is your go-to order?',
              'Yesterday',
              colors: [AppColors.coral, AppColors.gold],
            ),
            _message(
              'Runda Runner',
              'You: Sunday run?',
              'Mon',
              colors: [AppColors.teal, AppColors.accent],
            ),
            _message(
              'Lavington Poet',
              'You matched. Say hi.',
              'Mon',
              badge: 'New',
              colors: [AppColors.accent, AppColors.coral],
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(
    String name,
    String preview,
    String time, {
    required List<Color> colors,
    String? badge,
    bool unread = false,
    bool highlight = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
      decoration: BoxDecoration(
        color: highlight ? AppColors.coral.withValues(alpha: .08) : null,
        border: Border(
          bottom: BorderSide(color: AppColors.line.withValues(alpha: .45)),
        ),
      ),
      child: Row(
        children: [
          _GradientAvatar(colors: colors),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 7),
                      Pill(
                        badge,
                        color: badge == 'New'
                            ? AppColors.accentSoft
                            : AppColors.coral,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  preview,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                time,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              if (unread) ...[
                const SizedBox(height: 8),
                const CircleAvatar(radius: 4, backgroundColor: AppColors.coral),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _NewMatch extends StatelessWidget {
  const _NewMatch({
    required this.label,
    required this.colors,
    this.locked = false,
  });

  final String label;
  final List<Color> colors;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              _GradientAvatar(colors: colors, size: 58),
              if (locked)
                const Icon(Icons.lock_outline, color: Colors.white, size: 21),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class ReferenceSafetyScreen extends StatelessWidget {
  const ReferenceSafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PinnedTabBody(
      header: const SectionTitle(
        'Safety center',
        subtitle: 'Tools to help you meet safely.',
      ),
      child: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: .45),
                ),
              ),
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
                              'Alerts your trusted contact with your date\ndetails.',
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Hold to send alert'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _dateCard(),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: AppGradients.premium,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: .28),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.accentSoft,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Get verified',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Needed before your first reveal.',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CardActionButton(label: 'Start', onPressed: () {}),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick safety tips',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 10),
                  _Tip(
                    number: '1',
                    text: 'Meet in a public place the first few times.',
                  ),
                  _Tip(number: '2', text: 'Never send money, fare or airtime.'),
                  _Tip(number: '3', text: 'Tell a friend where you are going.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
              ),
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
          ],
        ),
      ),
    );
  }

  Widget _dateCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
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
              Pill('Active', color: AppColors.teal),
            ],
          ),
          const SizedBox(height: 12),
          const _DateRow('When', 'Saturday, 8:00 pm'),
          const _DateRow('Where', 'Rooftop lounge'),
          const _DateRow('Trusted contact', 'Wanjiru'),
          const _DateRow('Check-in due', '10:30 pm'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: AppColors.ink,
                  ),
                  child: const Text('I am safe'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Edit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _solidIcon(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.ink),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
}

class _DateRow extends StatelessWidget {
  const _DateRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ReferenceProfileScreen extends ConsumerWidget {
  const ReferenceProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PinnedTabBody(
      header: Row(
        children: [
          Stack(
            children: [
              _GradientAvatar(
                size: 92,
                colors: const [Color(0xFFD89964), Color(0xFFF4C18D)],
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: _solidRoundIcon(
                  Icons.camera_alt_outlined,
                  AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Westlands Nomad',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 5),
                Text(
                  '27 · 168 cm',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
                SizedBox(height: 6),
                VerifiedBadge(),
              ],
            ),
          ),
        ],
      ),
      child: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(
                  Icons.visibility_outlined,
                  color: AppColors.accentSoft,
                ),
                label: const Text('See how others see me'),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: AppGradients.premium,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.coral.withValues(alpha: .25),
                ),
              ),
              child: Row(
                children: [
                  _solidRoundIcon(Icons.star_rounded, AppColors.accent),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekly Premium',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '5 days left · 1 boost ready',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CardActionButton(
                    label: 'Boost',
                    gold: true,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  _solidRoundIcon(Icons.play_arrow_rounded, AppColors.accent),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My voice capsule',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '0:12 · voice disguise on',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CardActionButton(
                    label: 'Re-record',
                    outlined: true,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: const [
                Pill('Afrohouse', color: AppColors.secondaryText),
                Pill('Sunday brunch', color: AppColors.secondaryText),
                Pill('Hiking', color: AppColors.secondaryText),
                Pill('Tech', color: AppColors.secondaryText),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () {}, child: const Text('+ Add interest')),
            const SizedBox(height: 6),
            _settingsGroup(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _settingsGroup(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _setting('Discovery preferences', Icons.chevron_right),
          InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => const SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Privacy and consents',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      ConsentDocumentLinks(),
                    ],
                  ),
                ),
              ),
            ),
            child: _setting('Privacy and consents', Icons.chevron_right),
          ),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              title: const Text('Pause my profile'),
              value: ref.watch(demoProfilePausedProvider),
              onChanged: ref.read(demoProfilePausedProvider.notifier).setPaused,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          _setting('Download my data', Icons.chevron_right),
          _setting('Delete account and purge data', null, danger: true),
        ],
      ),
    );
  }

  Widget _setting(String title, IconData? trailing, {bool danger = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.line.withValues(alpha: .7)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: danger ? AppColors.coral : AppColors.text,
                fontWeight: danger ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null)
            Icon(
              trailing,
              color: danger ? AppColors.coral : AppColors.secondaryText,
            ),
        ],
      ),
    );
  }

  Widget _solidRoundIcon(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: color == AppColors.gold ? AppColors.ink : Colors.white,
      ),
    );
  }
}

class ReferenceStoreScreen extends ConsumerStatefulWidget {
  const ReferenceStoreScreen({this.initialProduct = 0, super.key});

  final int initialProduct;

  @override
  ConsumerState<ReferenceStoreScreen> createState() =>
      _ReferenceStoreScreenState();
}

class _ReferenceStoreScreenState extends ConsumerState<ReferenceStoreScreen> {
  late final TextEditingController _phoneController;
  var _selectedProduct = 0;
  bool _isPaying = false;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct.clamp(0, 2).toInt();
    _phoneController = TextEditingController(
      text: demoMode ? '0712 345 678' : '',
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.close_rounded),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Get seen. Stay in control.',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            'Pick what you need. Pay only when you want to.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 22),
          _product(
            index: 0,
            title: 'Weekly Premium',
            description: 'Unlimited swipes, see who\nlikes you, undo a pass.',
            price: 'KES 150',
            detail: '7 days',
            icon: Icons.star_outline_rounded,
            color: AppColors.accent,
            popular: true,
          ),
          _product(
            index: 1,
            title: 'Profile Boost',
            description: 'Top of your area for 30\nminutes.',
            price: 'KES 50',
            detail: 'one-off',
            icon: Icons.bolt_rounded,
            color: AppColors.gold,
          ),
          _product(
            index: 2,
            title: 'Early reveal request',
            description: 'Ask sooner. They still have\nto agree.',
            price: 'KES 50',
            detail: 'one-off',
            icon: Icons.visibility_outlined,
            color: AppColors.coral,
          ),
          const SizedBox(height: 92),
          const Text(
            'M-PESA number',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '0712 345 678'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isPaying ? null : _startPurchase,
              child: Text(
                _isPaying
                    ? 'Starting M-PESA...'
                    : 'Pay ${_selectedProduct == 0 ? 'KES 150' : 'KES 50'} with M-PESA',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'You will get a prompt on your phone. Enter your M-PESA PIN to\nconfirm. No auto-renewal.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startPurchase() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your M-PESA number first.')),
      );
      return;
    }
    setState(() => _isPaying = true);
    try {
      final kind = switch (_selectedProduct) {
        0 => 'premium',
        1 => 'boost',
        _ => 'unmask_fast_track',
      };
      final products = await ref.read(apiClientProvider).storeProducts();
      StoreProduct? product;
      for (final candidate in products) {
        if (candidate.kind == kind) {
          product = candidate;
          break;
        }
      }
      if (product == null) throw const ApiException('product_not_found');
      await ref
          .read(apiClientProvider)
          .createPurchase(
            productCode: product.code,
            phone: phone,
            idempotencyKey: const Uuid().v4(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('M-PESA prompt sent to your phone.')),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment could not start: ${error.code}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  Widget _product({
    required int index,
    required String title,
    required String description,
    required String price,
    required String detail,
    required IconData icon,
    required Color color,
    bool popular = false,
  }) {
    final selected = _selectedProduct == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedProduct = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
        decoration: BoxDecoration(
          gradient: selected ? AppGradients.premium : null,
          color: selected ? null : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (popular) ...[
                        const SizedBox(width: 7),
                        const Pill('Popular', color: AppColors.coral),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accentSoft : AppColors.text,
                  width: selected ? 3 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReferenceBoostScreen extends StatelessWidget {
  const ReferenceBoostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.close_rounded),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: .16),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold.withValues(alpha: .5)),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: AppColors.gold,
                size: 44,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Center(
            child: Text(
              'Boost your profile',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 7),
          const Center(
            child: Text(
              'Be seen by more people nearby for 30 minutes.',
              style: TextStyle(color: AppColors.secondaryText),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppGradients.premium,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.gold.withValues(alpha: .38)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Profile Boost',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 6),
                Text(
                  'Move your profile to the front of nearby discovery cards.',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 18),
                _BoostBenefit(text: 'More visibility in your area'),
                _BoostBenefit(text: 'Active for 30 minutes'),
                _BoostBenefit(text: 'No automatic renewal'),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push('/app/store', extra: 1),
              child: const Text('Boost for KES 50'),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'You will confirm securely with M-PESA.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoostBenefit extends StatelessWidget {
  const _BoostBenefit({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.gold, size: 18),
          const SizedBox(width: 9),
          Text(text, style: const TextStyle(color: AppColors.secondaryText)),
        ],
      ),
    );
  }
}

class _GradientAvatar extends StatelessWidget {
  const _GradientAvatar({required this.colors, this.size = 52});

  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accentSoft.withValues(alpha: .35)),
      ),
      child: Icon(Icons.person, size: size * .62, color: Colors.white38),
    );
  }
}
