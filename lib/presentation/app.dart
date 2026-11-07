import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'views/initiative_matrix_screen.dart';

/// Root application widget for HeroTrak.
///
/// Presentation-layer entry point only; all tracker logic lives in the
/// domain and controller layers. Provides the Riverpod [ProviderScope] so
/// the app (and tests pumping [HeroTrakApp] directly) are self-contained.
class HeroTrakApp extends StatelessWidget {
  const HeroTrakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'HeroTrak',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        home: const InitiativeMatrixScreen(),
      ),
    );
  }
}
