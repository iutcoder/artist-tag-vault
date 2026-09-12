import 'package:artist_tag_vault/src/home_page.dart';
import 'package:flutter/material.dart';

/// Root widget and shared visual theme for the desktop application.
class ArtistTagVaultApp extends StatelessWidget {
  const ArtistTagVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF8C7BFF);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Artist Tag Vault',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF090B16),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}
