import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/config/build_config.dart';
import 'inbox_controller.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, this.navigationShell, super.key});

  final Widget child;
  final StatefulNavigationShell? navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
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
    if (!demoMode) {
      ref
          .read(inboxProvider.notifier)
          .setActive(state == AppLifecycleState.resumed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = demoMode
        ? 2
        : ref.watch(inboxProvider).page?.unreadCount ?? 0;
    final location = GoRouterState.of(context).uri.path;
    final isStore =
        location.contains('/store') ||
        location.contains('/boost') ||
        location.contains('/matches/');
    final index = switch (location) {
      String path when path.contains('/matches') => 1,
      String path when path.contains('/safety') => 2,
      String path when path.contains('/profile') || path.contains('/store') =>
        3,
      _ => 0,
    };
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: isStore
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) {
                const paths = [
                  '/app/discover',
                  '/app/matches',
                  '/app/safety',
                  '/app/profile',
                ];
                if (widget.navigationShell != null) {
                  widget.navigationShell!.goBranch(value);
                } else {
                  context.go(paths[value]);
                }
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: 'Discover',
                ),
                NavigationDestination(
                  icon: _navIcon(Icons.forum_outlined, unread: unread),
                  selectedIcon: _navIcon(
                    Icons.forum_rounded,
                    selected: true,
                    unread: unread,
                  ),
                  label: 'Matches',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.verified_user_outlined),
                  selectedIcon: Icon(Icons.verified_user_rounded),
                  label: 'Safety',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
            ),
    );
  }

  Widget _navIcon(IconData icon, {bool selected = false, required int unread}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (unread > 0)
          Positioned(
            top: -7,
            right: -12,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.coral,
                shape: BoxShape.circle,
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  int _card = 0;

  @override
  Widget build(BuildContext context) {
    final profiles = [
      (
        'Westlands Nomad',
        '26',
        'Software engineer',
        ['Afrohouse', 'Sunday brunch', 'Hiking', 'Tech'],
      ),
      (
        'Kilimani Sunset',
        '29',
        'Creative director',
        ['Amapiano', 'Coffee', 'Books'],
      ),
      ('Lavington Poet', '27', 'Writer', ['Poetry', 'Art', 'Long walks']),
    ];
    final profile = profiles[_card % profiles.length];
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Discover',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Pill('2-5 km away', icon: Icons.location_on_outlined),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 500,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: AppGradients.blurredAvatar,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 18,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: const ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.white24,
                        BlendMode.modulate,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.person,
                          size: 180,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            profile.$1,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.teal.withValues(alpha: .2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.teal.withValues(alpha: .65),
                              ),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: AppColors.teal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${profile.$2}  ·  ${profile.$3}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: profile.$4
                            .map((tag) => Pill(tag, color: Colors.white70))
                            .toList(),
                      ),
                      const SizedBox(height: 13),
                      const Row(
                        children: [
                          Icon(Icons.graphic_eq, color: AppColors.accent),
                          SizedBox(width: 8),
                          Text(
                            '0:12',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Drag up for more',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roundAction(
                Icons.close,
                AppColors.danger,
                () => setState(() => _card++),
              ),
              const SizedBox(width: 28),
              _roundAction(
                Icons.favorite,
                AppColors.accent,
                () => setState(() => _card++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundAction(IconData icon, Color color, VoidCallback onPressed) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      iconSize: 32,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(18),
        backgroundColor: color.withValues(alpha: .14),
      ),
    );
  }
}

class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final matches = [
      (
        'Westlands Nomad',
        'Wants to reveal',
        'You both need to agree to reveal',
        '12 min',
      ),
      (
        'Kilimani Sunset',
        'Haha that voice note though',
        'Amapiano always.',
        '1 h',
      ),
      (
        'Karen Coffee Snob',
        'What is your go-to order?',
        'Sunday brunch?',
        'Yesterday',
      ),
      ('Runda Runner', 'You: Sunday run?', 'You matched. Say hi.', 'Mon'),
    ];
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Matches',
            subtitle: '5 people · Your connections stay private.',
          ),
          const SizedBox(height: 20),
          ...matches.map(
            (match) => ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 7),
              leading: const CircleAvatar(
                backgroundColor: AppColors.surfaceRaised,
                child: Icon(Icons.person, color: AppColors.muted),
              ),
              title: Text(
                match.$1,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${match.$2}\n${match.$3}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted),
              ),
              trailing: Text(
                match.$4,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              onTap: () => _openChat(context, match.$1),
            ),
          ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context, String name) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.ink,
      builder: (_) => ChatPreview(name: name),
    );
  }
}

class ChatPreview extends StatelessWidget {
  const ChatPreview({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.surfaceRaised,
                  child: Icon(Icons.person),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const Text(
                      'Identity hidden · active recently',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'You matched today',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            const _Bubble(
              text: 'Your voice note made me laugh. Afrohouse or amapiano?',
              mine: false,
            ),
            const _Bubble(text: 'Afrohouse, always. You?', mine: true),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Stay safe\nNever send money, airtime or fare to someone you have not met. Meet in a public place.',
                style: TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Report'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    child: const Text('Request reveal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          color: mine ? AppColors.accent : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(color: mine ? AppColors.ink : AppColors.text),
        ),
      ),
    );
  }
}

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Safety center',
            subtitle: 'Tools to help you meet safely.',
          ),
          const SizedBox(height: 24),
          _SafetyCard(
            icon: Icons.warning_amber_rounded,
            title: 'Panic button',
            body: 'Alerts your trusted contact with your date details.',
            action: 'Hold to send alert',
            color: AppColors.danger,
          ),
          const SizedBox(height: 12),
          _SafetyCard(
            icon: Icons.share_location_outlined,
            title: 'Share my date',
            body: 'Saturday, 8:00 pm  ·  Rooftop lounge',
            action: 'Check-in due 10:30 pm',
            color: AppColors.success,
          ),
          const SizedBox(height: 22),
          const Text(
            'Get verified',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 7),
          const Text(
            'Needed before your first reveal. Start with a quick selfie check.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          const Text(
            'Quick safety tips',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            '1  Meet in a public place the first few times.\n2  Never send money, fare or airtime.\n3  Tell a friend where you are going.',
            style: TextStyle(color: AppColors.muted, height: 1.8),
          ),
          const SizedBox(height: 22),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block, color: AppColors.muted),
            title: const Text('Blocked people and my reports'),
            trailing: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(body, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 10),
                Pill(action, color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 35,
                backgroundColor: AppColors.surfaceRaised,
                child: Icon(Icons.person, size: 34, color: AppColors.muted),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Westlands Nomad',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '27  ·  168 cm',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 6),
                  const Pill('Verified', icon: Icons.verified),
                ],
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Text(
            'My voice capsule',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.graphic_eq, color: AppColors.accent),
            title: Text('0:12  ·  voice disguise on'),
            trailing: Text(
              'Re-record',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Afrohouse',
              'Sunday brunch',
              'Hiking',
              'Tech',
            ].map((tag) => Pill(tag, color: AppColors.muted)).toList(),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Weekly Premium'),
            subtitle: const Text(
              '5 days left  ·  1 boost ready',
              style: TextStyle(color: AppColors.muted),
            ),
            trailing: ElevatedButton(
              onPressed: () => context.push('/app/store'),
              child: const Text('Boost'),
            ),
          ),
          const Divider(height: 30),
          const Text(
            'Discovery preferences',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.tune),
            title: Text('Privacy and consents'),
            trailing: Icon(Icons.chevron_right),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.pause_circle_outline),
            title: Text('Pause my profile'),
            trailing: Icon(Icons.chevron_right),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_outlined),
            title: Text('Download my data'),
            trailing: Icon(Icons.chevron_right),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            title: const Text(
              'Delete account and purge data',
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Get seen. Stay in control.',
            subtitle: 'Pick what you need. Pay only when you want to.',
          ),
          const SizedBox(height: 22),
          _ProductCard(
            title: 'Weekly Premium',
            description: 'Unlimited swipes, see who likes you, undo a pass.',
            price: 'KES 150',
            duration: '7 days',
            popular: true,
          ),
          _ProductCard(
            title: 'Profile Boost',
            description: 'Top of your area for 30 minutes.',
            price: 'KES 50',
            duration: 'one-off',
          ),
          _ProductCard(
            title: 'Early reveal request',
            description: 'Ask sooner. They still have to agree.',
            price: 'KES 50',
            duration: 'one-off',
          ),
          const SizedBox(height: 12),
          const Text(
            'M-PESA number',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const TextField(
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              prefixText: 'KE  ',
              hintText: '07XX XXX XXX',
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Pay with M-PESA'),
          ),
          const SizedBox(height: 10),
          const Text(
            'You will get a prompt on your phone. Enter your M-PESA PIN to confirm. No auto-renewal.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.title,
    required this.description,
    required this.price,
    required this.duration,
    this.popular = false,
  });

  final String title;
  final String description;
  final String price;
  final String duration;
  final bool popular;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: popular ? Border.all(color: AppColors.accent) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (popular) ...[
                      const SizedBox(width: 8),
                      const Pill('Popular'),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  style: const TextStyle(color: AppColors.muted, height: 1.35),
                ),
                const SizedBox(height: 8),
                Text(
                  duration,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            price,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
