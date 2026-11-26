import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF0F1115);
  static const surface = Color(0xFF171A21);
  static const surfaceRaised = Color(0xFF1E222C);
  static const line = Color(0xFF262B38);
  static const strongLine = Color(0xFF3A3F52);
  static const text = Color(0xFFF2F4F8);
  static const secondaryText = Color(0xFFB4BBC8);
  static const muted = Color(0xFF9AA3B2);

  static const accent = Color(0xFF6A4AF0);
  static const accentBright = Color(0xFF7C5CFF);
  static const accentSoft = Color(0xFF9D86FF);
  static const accentDeep = accentBright;
  static const coral = Color(0xFFFF6B81);
  static const gold = Color(0xFFF5B83D);
  static const teal = Color(0xFF2EC4B6);
  static const success = teal;
  static const danger = Color(0xFFE5484D);

  static const pageLight = Color(0xFFF6F5FB);
  static const coralLight = Color(0xFFE5486A);
  static const violetLight = Color(0xFF6A4AF0);
}

abstract final class AppGradients {
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.accent, AppColors.coral],
  );

  static const progress = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.accent, AppColors.coral],
  );

  static const blurredAvatar = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF5B3FD6), Color(0xFFB04BA8), AppColors.coral],
    stops: [0, .55, 1],
  );

  static const revealRing = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.coral, AppColors.gold],
  );

  static const coralLens = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFB36B), Color(0xFFFF4F7A)],
  );

  static const premium = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x476A4AF0), Color(0x2EFF6B81)],
  );
}

abstract final class AppTheme {
  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
          surface: AppColors.surface,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.ink,
          secondary: AppColors.coral,
          surface: AppColors.surface,
          onSurface: AppColors.text,
          outline: AppColors.line,
          error: AppColors.danger,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.ink,
      fontFamily: 'Roboto',
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          ...const PageTransitionsTheme().builders,
          TargetPlatform.android: const FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accentSoft, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.text,
          minimumSize: const Size(64, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(64, 52),
          side: const BorderSide(color: AppColors.strongLine),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        height: 76,
        indicatorColor: Colors.transparent,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.accentSoft
                : AppColors.secondaryText,
            size: 22,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.accentSoft
                : AppColors.secondaryText,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line),
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class BrandHeaderLogo extends StatelessWidget {
  const BrandHeaderLogo({this.width = 168, this.height = 42, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          'assets/branding/anonymoke-header-logo.jpeg',
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}

/// Compact trailing actions leave room for the summary text beside them.
class CardActionButton extends StatelessWidget {
  const CardActionButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.gold = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      backgroundColor: outlined
          ? Colors.transparent
          : gold
          ? AppColors.gold
          : AppColors.accent,
      foregroundColor: gold ? AppColors.ink : AppColors.text,
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: style,
              child: Text(label),
            )
          : ElevatedButton(
              onPressed: onPressed,
              style: style,
              child: Text(label),
            ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {this.icon, this.color, super.key});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tint.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: tint),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: tint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
