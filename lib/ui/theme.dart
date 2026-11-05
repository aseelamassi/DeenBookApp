import 'package:flutter/material.dart';

const navy = Color(0xFF242872),
    orange = Color(0xFFEB5B25),
    canvas = Color(0xFFF3F4F8),
    ink = Color(0xFF15184A),
    muted = Color(0xFF94A3B8),
    secondaryText = Color(0xFF64748B),
    lavender = Color(0xFFEFF1FB),
    lineColor = Color(0xFFE5E7EB),
    green = Color(0xFF059669),
    paleOrange = Color(0xFFFEF2ED);
const brandGradient = LinearGradient(
  begin: Alignment.topRight,
  end: Alignment.bottomLeft,
  colors: [ink, navy, Color(0xFF2A2F85)],
);
TextStyle appText(
  double size, {
  FontWeight weight = FontWeight.w700,
  Color color = ink,
  double height = 1.5,
}) => TextStyle(
  fontFamily: 'Cairo',
  fontFamilyFallback: const ['Money', 'Symbols'],
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  leadingDistribution: TextLeadingDistribution.even,
);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Cairo',
  fontFamilyFallback: const ['Money', 'Symbols'],
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: navy,
    primary: navy,
    secondary: orange,
    surface: Colors.white,
    onSurface: ink,
    surfaceTint: Colors.transparent,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: navy,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    elevation: 0,
    toolbarHeight: 64,
    titleTextStyle: appText(16, weight: FontWeight.w900),
  ),
  textTheme: TextTheme(
    headlineLarge: appText(28, weight: FontWeight.w900, height: 1.25),
    headlineSmall: appText(24, weight: FontWeight.w900, height: 1.35),
    titleLarge: appText(18, weight: FontWeight.w900),
    titleMedium: appText(16, weight: FontWeight.w800),
    titleSmall: appText(14, weight: FontWeight.w800),
    bodyLarge: appText(14),
    bodyMedium: appText(12, weight: FontWeight.w600),
    bodySmall: appText(11, weight: FontWeight.w600, color: secondaryText),
    labelLarge: appText(12, weight: FontWeight.w800),
    labelMedium: appText(11, weight: FontWeight.w800),
    labelSmall: appText(10, weight: FontWeight.w800),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    labelStyle: appText(12, weight: FontWeight.w800),
    hintStyle: appText(12, weight: FontWeight.w600, color: muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: navy, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(44, 50),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: appText(12, weight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      foregroundColor: Colors.white,
      backgroundColor: navy,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: appText(12, weight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      side: const BorderSide(color: Color(0xFFD5DAF3)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      textStyle: appText(12, weight: FontWeight.w800),
      minimumSize: const Size(36, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: Colors.white,
    selectedColor: lavender,
    labelStyle: appText(12, weight: FontWeight.w800),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    side: const BorderSide(color: lineColor),
    showCheckmark: false,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
  ),
  dividerTheme: const DividerThemeData(color: lineColor, thickness: 1),
  drawerTheme: const DrawerThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  ),
);
