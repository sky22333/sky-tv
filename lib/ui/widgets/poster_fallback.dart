import 'package:flutter/material.dart';

class PosterFallback extends StatelessWidget {
  const PosterFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surfaceContainerHigh, scheme.surfaceContainerHighest],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}
