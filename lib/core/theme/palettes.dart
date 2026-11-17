import 'package:flutter/material.dart';

/// Hub background gradients (index persisted in settings).
abstract final class HubBackgrounds {
  static const List<({String name, List<Color> colors})> all = [
    (name: 'Blue & Green', colors: [Color(0xFF1A237E), Color(0xFF004D40)]),
    (name: 'Midnight', colors: [Color(0xFF121212), Color(0xFF232526)]),
    (name: 'Purple Night', colors: [Color(0xFF41295A), Color(0xFF2F0743)]),
    (name: 'Sunset', colors: [Color(0xFFF2994A), Color(0xFFD9455F)]),
    (name: 'Ocean', colors: [Color(0xFF2193B0), Color(0xFF6DD5ED)]),
    (name: 'Deep Space', colors: [Color(0xFF000428), Color(0xFF004E92)]),
    (name: 'Emerald', colors: [Color(0xFF11998E), Color(0xFF38EF7D)]),
    (name: 'Cherry', colors: [Color(0xFFCB2D3E), Color(0xFFEF473A)]),
    (name: 'Totally Dark', colors: [Color(0xFF000000), Color(0xFF0A0A0A)]),
  ];

  static ({String name, List<Color> colors}) at(int index) =>
      all[index.clamp(0, all.length - 1)];

  static BoxDecoration decoration(int index) => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: at(index).colors,
        ),
      );
}

abstract final class AccentColors {
  static const Color fallback = Color(0xFF2196F3);

  static const List<Color> all = [
    Color(0xFF2196F3),
    Color(0xFF3F51B5),
    Color(0xFF9C27B0),
    Color(0xFFE91E63),
    Color(0xFFF44336),
    Color(0xFFFF9800),
    Color(0xFF4CAF50),
    Color(0xFF009688),
  ];
}

/// Fixed colors of the player chrome (always dark, like the video itself).
abstract final class PlayerColors {
  static const Color sheet = Color(0xFF1C1C1E);
  static const Color chip = Color(0xFF2D2D2D);
  static const Color progress = Colors.red;
}
