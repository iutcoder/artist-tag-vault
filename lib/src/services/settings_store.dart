import 'dart:convert';

import 'package:artist_tag_vault/src/models/app_settings.dart';
import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists non-secret presets and the API token in separate platform stores.
class SettingsStore {
  SettingsStore({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? preferences,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _preferences = preferences ?? SharedPreferences.getInstance;

  static const _presetKey = 'generation_preset_v1';
  static const _tokenKey = 'novelai_api_token';

  final FlutterSecureStorage _secureStorage;
  final Future<SharedPreferences> Function() _preferences;

  Future<AppSettings> load() async {
    final preferences = await _preferences();
    final encoded = preferences.getString(_presetKey);
    final preset = encoded == null
        ? GenerationPreset.defaults()
        : GenerationPreset.fromJson(
            jsonDecode(encoded) as Map<String, dynamic>,
          );

    try {
      final token = await _secureStorage.read(key: _tokenKey) ?? '';
      return AppSettings(apiToken: token, preset: preset);
    } on PlatformException catch (error) {
      throw SettingsStoreException(_keychainMessage(error));
    }
  }

  Future<void> save(AppSettings settings) async {
    final preferences = await _preferences();
    await preferences.setString(_presetKey, jsonEncode(settings.preset.toJson()));

    try {
      if (settings.apiToken.trim().isEmpty) {
        await _secureStorage.delete(key: _tokenKey);
      } else {
        await _secureStorage.write(
          key: _tokenKey,
          value: settings.apiToken.trim(),
        );
      }
    } on PlatformException catch (error) {
      throw SettingsStoreException(_keychainMessage(error));
    }
  }

  String _keychainMessage(PlatformException error) {
    if (error.message?.contains('-34018') ?? false) {
      return 'macOS Keychain entitlement가 없습니다. README의 macOS 서명 설정을 확인해 주세요.';
    }
    return '보안 저장소를 사용할 수 없습니다: ${error.message ?? error.code}';
  }
}

class SettingsStoreException implements Exception {
  const SettingsStoreException(this.message);
  final String message;

  @override
  String toString() => message;
}
