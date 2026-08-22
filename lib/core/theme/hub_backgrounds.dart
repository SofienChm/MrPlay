import 'package:flutter/material.dart';
import 'app_colors.dart';

class HubBackgrounds {
  static const List<String> names = [
    'Blue & Green',
    'Midnight',
    'Purple Night',
    'Sunset',
    'Ocean',
    'Deep Space',
    'Emerald',
    'Cherry',
    'Totally Dark',
  ];

  static const List<List<Color>> palettes = [
    [AppColors.hubGradientStart, AppColors.hubGradientEnd],
    [Color(0xFF121212), Color(0xFF232526)],
    [Color(0xFF41295A), Color(0xFF2F0743)],
    [Color(0xFFF2994A), Color(0xFFD9455F)],
    [Color(0xFF2193B0), Color(0xFF6DD5ED)],
    [Color(0xFF000428), Color(0xFF004E92)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFFCB2D3E), Color(0xFFEF473A)],
    [Color(0xFF000000), Color(0xFF0A0A0A)],
  ];

  static Decoration decorationFor(int index) {
    final i = index.clamp(0, palettes.length - 1);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: palettes[i],
      ),
    );
  }
}
