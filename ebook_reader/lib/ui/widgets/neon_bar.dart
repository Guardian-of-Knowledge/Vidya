// lib/ui/widgets/neon_bar.dart
import 'package:flutter/material.dart';

/// A semi-transparent gradient AppBar background for Neon theme.
class NeonBar extends StatelessWidget {
  final Color accent;
  const NeonBar({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18), // was withOpacity(0.18)
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
