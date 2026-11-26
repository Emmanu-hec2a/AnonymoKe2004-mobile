import 'package:flutter/material.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({this.size = 20, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Verified',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.verified_rounded,
            color: const Color(0xFF1D9BF0),
            size: size,
          ),
          Icon(Icons.check_rounded, color: Colors.white, size: size * .63),
        ],
      ),
    ),
  );
}
