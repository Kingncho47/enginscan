import 'package:flutter/material.dart';

import '../../features/j1939/domain/models.dart';

/// Theme applicatif Material Design 3.
///
/// Choix terrain : theme sombre par defaut (lisibilite en exterieur), gros
/// boutons (56 dp minimum) pour l'utilisation avec gants, contrastes forts.
class AppTheme {
  AppTheme._();

  static const Color seedColor = Color(0xFF1565C0);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData _base(Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          brightness == Brightness.dark ? const Color(0xFF0B1220) : null,
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(72, 56),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 56),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  /// Couleur associee a la severite d'un code defaut.
  static Color severityColor(DtcSeverity severity) {
    switch (severity) {
      case DtcSeverity.critique:
        return const Color(0xFFE53935);
      case DtcSeverity.majeur:
        return const Color(0xFFFF8F00);
      case DtcSeverity.mineur:
        return const Color(0xFFFBC02D);
      case DtcSeverity.info:
        return const Color(0xFF42A5F5);
    }
  }
}
