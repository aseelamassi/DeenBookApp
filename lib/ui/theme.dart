import 'package:flutter/material.dart';

const navy = Color(0xFF292669),
    orange = Color(0xFFF26522),
    canvas = Color(0xFFF6F7FB),
    muted = Color(0xFF71758B);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Cairo',
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: navy,
    primary: navy,
    secondary: orange,
    surface: Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: navy,
    centerTitle: false,
    elevation: 0,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE2E4EE)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE2E4EE)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(44, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  textTheme: const TextTheme(
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.bold,
      color: navy,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: navy,
    ),
    bodyMedium: TextStyle(fontSize: 14, height: 1.7, color: navy),
  ),
);
