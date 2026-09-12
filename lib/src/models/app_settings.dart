import 'package:artist_tag_vault/src/models/generation_preset.dart';

/// Settings are split so the API token can be stored separately in Keychain or
/// Windows Credential Manager while ordinary preset data stays in preferences.
class AppSettings {
  const AppSettings({required this.apiToken, required this.preset});

  factory AppSettings.defaults() => AppSettings(
        apiToken: '',
        preset: GenerationPreset.defaults(),
      );

  final String apiToken;
  final GenerationPreset preset;

  AppSettings copyWith({String? apiToken, GenerationPreset? preset}) =>
      AppSettings(
        apiToken: apiToken ?? this.apiToken,
        preset: preset ?? this.preset,
      );
}
