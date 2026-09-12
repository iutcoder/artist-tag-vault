import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DanbooruArtistSuggestion {
  const DanbooruArtistSuggestion({required this.label, required this.value});

  final String label;
  final String value;
}

class DanbooruAutocompleteService {
  DanbooruAutocompleteService({
    http.Client? client,
    Uri? endpoint,
    bool persistentCache = true,
  }) : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _endpoint =
          endpoint ?? Uri.https('danbooru.donmai.us', '/autocomplete.json'),
      _persistentCache = persistentCache;

  static const _cacheKey = 'danbooru_artist_autocomplete_cache_v1';
  static const _cacheLifetime = Duration(days: 7);

  final http.Client _client;
  final bool _ownsClient;
  final Uri _endpoint;
  final bool _persistentCache;
  final Map<String, List<DanbooruArtistSuggestion>> _cache = {};
  final Map<String, DateTime> _cachedAt = {};
  Future<void>? _cacheLoad;

  Future<List<DanbooruArtistSuggestion>> suggestArtists(
    String rawQuery, {
    int limit = 8,
  }) async {
    final query = rawQuery.trim();
    if (query.length < 2) return const [];

    await (_cacheLoad ??= _loadPersistentCache());

    final cacheKey = '${query.toLowerCase()}|$limit';
    final cached = _cache[cacheKey];
    final cachedAt = _cachedAt[cacheKey];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheLifetime) {
      return cached;
    }

    final uri = _endpoint.replace(
      queryParameters: {
        ..._endpoint.queryParameters,
        'search[query]': query,
        'search[type]': 'artist',
        'limit': '$limit',
      },
    );
    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'ArtistTagVault/0.1.0',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        throw DanbooruAutocompleteException(
          'Danbooru autocomplete returned HTTP ${response.statusCode}.',
        );
      }
    } on Exception {
      if (cached != null) return cached;
      rethrow;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const DanbooruAutocompleteException(
        'Danbooru autocomplete returned an unexpected response.',
      );
    }

    final seen = <String>{};
    final suggestions = <DanbooruArtistSuggestion>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final value = item['value']?.toString().trim() ?? '';
      if (value.isEmpty || !seen.add(value)) continue;
      final rawLabel = item['label']?.toString().trim() ?? '';
      suggestions.add(
        DanbooruArtistSuggestion(
          label: rawLabel.isEmpty ? value.replaceAll('_', ' ') : rawLabel,
          value: value,
        ),
      );
    }

    if (_cache.length >= 100) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      _cachedAt.remove(oldestKey);
    }
    final result = List<DanbooruArtistSuggestion>.unmodifiable(suggestions);
    _cache[cacheKey] = result;
    _cachedAt[cacheKey] = DateTime.now();
    await _savePersistentCache();
    return result;
  }

  Future<void> _loadPersistentCache() async {
    if (!_persistentCache) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_cacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final timestamp = DateTime.tryParse(value['cachedAt']?.toString() ?? '');
        final items = value['items'];
        if (timestamp == null || items is! List) continue;
        final suggestions = items
            .whereType<Map>()
            .map(
              (item) => DanbooruArtistSuggestion(
                label: item['label']?.toString() ?? '',
                value: item['value']?.toString() ?? '',
              ),
            )
            .where((item) => item.value.isNotEmpty)
            .toList(growable: false);
        _cache[entry.key.toString()] = suggestions;
        _cachedAt[entry.key.toString()] = timestamp;
      }
    } on Exception {
      // A corrupt or unavailable cache must never block manual artist entry.
    }
  }

  Future<void> _savePersistentCache() async {
    if (!_persistentCache) return;
    try {
      final keys = _cache.keys.toList();
      if (keys.length > 100) {
        keys.sort(
          (a, b) => (_cachedAt[b] ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                _cachedAt[a] ?? DateTime.fromMillisecondsSinceEpoch(0),
              ),
        );
      }
      final encoded = <String, Object?>{};
      for (final key in keys.take(100)) {
        encoded[key] = {
          'cachedAt': _cachedAt[key]?.toIso8601String(),
          'items': _cache[key]
              ?.map((item) => {'label': item.label, 'value': item.value})
              .toList(),
        };
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_cacheKey, jsonEncode(encoded));
    } on Exception {
      // Network results are still usable even when the cache cannot be saved.
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class DanbooruAutocompleteException implements Exception {
  const DanbooruAutocompleteException(this.message);

  final String message;

  @override
  String toString() => message;
}
