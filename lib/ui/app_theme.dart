import 'package:flutter/material.dart';

const neonCyan = Color(0xFF60E8EF);
const neonViolet = Color(0xFFAA94FF);
const panelColor = Color(0xFF141D30);
const edgeColor = Color(0xFF2A3853);

ThemeData nextEpisodeTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: neonCyan,
    brightness: Brightness.dark,
  ).copyWith(
    primary: neonCyan,
    onPrimary: const Color(0xFF042A30),
    secondary: neonViolet,
    surface: panelColor,
    onSurface: const Color(0xFFF1F5FF),
    onSurfaceVariant: const Color(0xFFAAB8D1),
    outline: edgeColor,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.7),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      bodySmall: base.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF0C1222),
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: scheme.onSurface, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0C1222),
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0xFF193D49),
      height: 78,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? neonCyan : scheme.onSurfaceVariant,
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? neonCyan : scheme.onSurfaceVariant,
      )),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF121B2D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      prefixIconColor: neonCyan,
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: edgeColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: neonCyan, width: 1.5)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
    ),
    cardTheme: CardThemeData(
      color: panelColor,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: edgeColor)),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      iconColor: neonCyan,
      shape: rounded,
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: rounded,
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: rounded,
    )),
    dialogTheme: DialogThemeData(
      backgroundColor: panelColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: const BorderSide(color: edgeColor)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: neonCyan,
      linearTrackColor: Color(0xFF28344D),
      linearMinHeight: 6,
      borderRadius: BorderRadius.all(Radius.circular(6)),
    ),
    dividerTheme: const DividerThemeData(color: edgeColor, space: 28),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color(0xFF20243D),
      side: const BorderSide(color: edgeColor),
      shape: rounded,
    ),
  );
}

class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF121C35), Color(0xFF080D19), Color(0xFF19132D)],
      ),
    ),
    child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: child,
    )),
  );
}
