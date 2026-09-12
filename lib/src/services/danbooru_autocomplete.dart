import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class DanbooruArtistSuggestion {
  const DanbooruArtistSuggestion({required this.value, required this.count});

  final String value;
  final int count;

  String get label => value.replaceAll('_', ' ');

  Map<String, Object> toJson() => {'value': value, 'count': count};

  static DanbooruArtistSuggestion? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['value']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    return DanbooruArtistSuggestion(
      value: name,
      count: int.tryParse(value['count']?.toString() ?? '') ?? 0,
    );
  }
}

class DanbooruDictionaryStatus {
  const DanbooruDictionaryStatus({
    required this.artistCount,
    required this.updatedAt,
  });

  const DanbooruDictionaryStatus.empty()
    : artistCount = 0,
      updatedAt = null;

  final int artistCount;
  final DateTime? updatedAt;

  bool get isAvailable => artistCount > 0;
}

class DanbooruAutocompleteService {
  DanbooruAutocompleteService({
    http.Client? client,
    Uri? endpoint,
    Future<File> Function()? dictionaryFile,
    int pageSize = 500,
    Duration pageDelay = const Duration(milliseconds: 500),
    int maxRequestAttempts = 3,
    Duration retryDelay = const Duration(seconds: 1),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = endpoint ?? Uri.https('shima.donmai.us', '/tags.json'),
       _dictionaryFile = dictionaryFile ?? _defaultDictionaryFile,
       _pageSize = pageSize,
       _pageDelay = pageDelay,
       _maxRequestAttempts = maxRequestAttempts,
       _retryDelay = retryDelay;

  final http.Client _client;
  final bool _ownsClient;
  final Uri _endpoint;
  final Future<File> Function() _dictionaryFile;
  final int _pageSize;
  final Duration _pageDelay;
  final int _maxRequestAttempts;
  final Duration _retryDelay;
  List<DanbooruArtistSuggestion> _artists = const [];
  DateTime? _updatedAt;
  Future<void>? _loadOperation;
  bool _updating = false;
  int _operationGeneration = 0;

  Future<DanbooruDictionaryStatus> status() async {
    await (_loadOperation ??= _loadDictionary());
    return DanbooruDictionaryStatus(
      artistCount: _artists.length,
      updatedAt: _updatedAt,
    );
  }

  Future<List<DanbooruArtistSuggestion>> suggestArtists(
    String rawQuery, {
    int limit = 8,
  }) async {
    final query = _normalize(rawQuery);
    if (query.length < 2) return const [];
    await (_loadOperation ??= _loadDictionary());
    if (_artists.isEmpty) return const [];

    final prefix = <DanbooruArtistSuggestion>[];
    final contains = <DanbooruArtistSuggestion>[];
    for (final artist in _artists) {
      final name = artist.value.toLowerCase();
      if (name.startsWith(query)) {
        prefix.add(artist);
      } else if (name.contains(query)) {
        contains.add(artist);
      }
      if (prefix.length >= limit) break;
    }
    if (prefix.length < limit) {
      prefix.addAll(contains.take(limit - prefix.length));
    }
    return prefix.take(limit).toList(growable: false);
  }

  Future<DanbooruDictionaryStatus> updateDictionary({
    void Function(int artistCount)? onProgress,
  }) async {
    if (_updating) {
      throw const DanbooruAutocompleteException(
        'Artist dictionary update is already running.',
      );
    }
    _updating = true;
    final operation = ++_operationGeneration;
    try {
      final downloaded = <String, DanbooruArtistSuggestion>{};
      var cursor = '1';
      final visitedCursors = <String>{};
      while (visitedCursors.add(cursor)) {
        _ensureActive(operation);
        final page = await _downloadPage(cursor);
        _ensureActive(operation);
        for (final entry in page.artists) {
          downloaded[entry.value] = entry;
        }
        onProgress?.call(downloaded.length);
        if (page.recordCount < _pageSize || page.lastId == null) break;
        if (_pageDelay > Duration.zero) await Future<void>.delayed(_pageDelay);
        final nextCursor = 'b${page.lastId}';
        if (visitedCursors.contains(nextCursor)) {
          throw const DanbooruAutocompleteException(
            'Danbooru pagination returned a repeated page.',
          );
        }
        cursor = nextCursor;
      }
      _ensureActive(operation);
      if (downloaded.isEmpty) {
        throw const DanbooruAutocompleteException(
          'Danbooru returned an empty artist dictionary.',
        );
      }

      final artists = downloaded.values.toList()
        ..sort((a, b) {
          final countOrder = b.count.compareTo(a.count);
          return countOrder != 0 ? countOrder : a.value.compareTo(b.value);
        });
      final updatedAt = DateTime.now().toUtc();
      _ensureActive(operation);
      await _saveDictionary(artists, updatedAt);
      _ensureActive(operation);
      _artists = List.unmodifiable(artists);
      _updatedAt = updatedAt;
      return DanbooruDictionaryStatus(
        artistCount: artists.length,
        updatedAt: updatedAt,
      );
    } finally {
      if (_operationGeneration == operation) _updating = false;
    }
  }

  Future<DanbooruDictionaryStatus> importDictionaryJson(String source) async {
    if (_updating) {
      throw const DanbooruAutocompleteException(
        'Artist dictionary update is already running.',
      );
    }
    _updating = true;
    final operation = ++_operationGeneration;
    try {
      final decoded = jsonDecode(source);
      final List entries;
      if (decoded is List) {
        entries = decoded;
      } else if (decoded is Map && decoded['artists'] is List) {
        entries = decoded['artists'] as List;
      } else {
        throw const DanbooruAutocompleteException(
          'The selected JSON file is not a supported tag dictionary.',
        );
      }
      final imported = <String, DanbooruArtistSuggestion>{};
      for (final raw in entries.whereType<Map>()) {
        final isInternalEntry = raw.containsKey('value') &&
            !raw.containsKey('type') &&
            !raw.containsKey('category');
        final type = raw['type']?.toString().toLowerCase();
        final category = int.tryParse(raw['category']?.toString() ?? '');
        final isArtist = isInternalEntry || type == 'artist' || category == 1;
        final isDeprecated = raw['is_deprecated'] == true;
        final count = int.tryParse(
              (raw['count'] ?? raw['post_count'])?.toString() ?? '',
            ) ??
            0;
        final isRedirected = raw['antecedent_alias'] != null ||
            raw['is_alias'] == true ||
            raw['redirect_to'] != null;
        if (!isArtist || isDeprecated || count <= 0 || isRedirected) continue;
        final name = (raw['value'] ?? raw['name'] ?? raw['label'])
            ?.toString()
            .trim();
        if (name == null || name.isEmpty) continue;
        imported[name] = DanbooruArtistSuggestion(value: name, count: count);
      }
      if (imported.isEmpty) {
        throw const DanbooruAutocompleteException(
          'No artist tags were found in the selected JSON file.',
        );
      }
      final artists = imported.values.toList()
        ..sort((a, b) {
          final countOrder = b.count.compareTo(a.count);
          return countOrder != 0 ? countOrder : a.value.compareTo(b.value);
        });
      final updatedAt = DateTime.now().toUtc();
      _ensureActive(operation);
      await _saveDictionary(artists, updatedAt);
      _ensureActive(operation);
      _artists = List.unmodifiable(artists);
      _updatedAt = updatedAt;
      return DanbooruDictionaryStatus(
        artistCount: artists.length,
        updatedAt: updatedAt,
      );
    } on FormatException {
      throw const DanbooruAutocompleteException(
        'The selected file is not valid JSON.',
      );
    } finally {
      if (_operationGeneration == operation) _updating = false;
    }
  }

  void cancelUpdate() {
    if (!_updating) return;
    _operationGeneration++;
    _updating = false;
  }

  void _ensureActive(int operation) {
    if (_operationGeneration != operation) {
      throw const DanbooruAutocompleteException(
        'Artist dictionary update was cancelled.',
      );
    }
  }

  Future<_DanbooruArtistPage> _downloadPage(String page) async {
    final uri = _endpoint.replace(
      queryParameters: {
        ..._endpoint.queryParameters,
        'search[category]': '1',
        'search[hide_empty]': 'true',
        'search[is_deprecated]': 'false',
        'search[order]': 'date',
        'only':
            'id,name,category,post_count,is_deprecated,'
            'antecedent_alias[id]',
        'limit': '$_pageSize',
        'page': '$page',
      },
    );
    http.Response? response;
    Object? lastError;
    for (var attempt = 1; attempt <= _maxRequestAttempts; attempt++) {
      response = null;
      try {
        response = await _client
            .get(
              uri,
              headers: const {
                'Accept': 'application/json',
                'Connection': 'close',
                'User-Agent': 'ArtistTagVault/0.0.1',
              },
            )
            .timeout(const Duration(seconds: 15));
        if (!_isRetryableStatus(response.statusCode) ||
            attempt == _maxRequestAttempts) {
          break;
        }
        lastError = 'HTTP ${response.statusCode}';
      } on Exception catch (error) {
        lastError = error;
        if (attempt == _maxRequestAttempts) break;
      }
      if (_retryDelay > Duration.zero) {
        await Future<void>.delayed(_retryDelay * attempt);
      }
    }
    if (response == null) {
      throw DanbooruAutocompleteException(
        'Could not connect to Danbooru after $_maxRequestAttempts attempts. '
        'If Danbooru HTTPS is blocked on this network, import a tags.json '
        'file instead. ($lastError)',
      );
    }
    if (response.statusCode != 200) {
      throw DanbooruAutocompleteException(
        'Danbooru returned HTTP ${response.statusCode} on page $page.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const DanbooruAutocompleteException(
        'Danbooru returned an unexpected artist response.',
      );
    }
    final records = decoded.whereType<Map>().toList(growable: false);
    final artists = records
        .where((item) {
          final category = int.tryParse(item['category']?.toString() ?? '');
          final postCount =
              int.tryParse(item['post_count']?.toString() ?? '') ?? 0;
          return category == 1 &&
              item['is_deprecated'] != true &&
              postCount > 0 &&
              item['antecedent_alias'] == null;
        })
        .map(
          (item) => DanbooruArtistSuggestion(
            value: item['name']?.toString().trim() ?? '',
            count: int.tryParse(item['post_count']?.toString() ?? '') ?? 0,
          ),
        )
        .where((item) => item.value.isNotEmpty)
        .toList(growable: false);
    return _DanbooruArtistPage(
      artists: artists,
      recordCount: records.length,
      lastId: records.isEmpty
          ? null
          : int.tryParse(records.last['id']?.toString() ?? ''),
    );
  }

  bool _isRetryableStatus(int statusCode) =>
      statusCode == 429 || statusCode >= 500;

  Future<void> _loadDictionary() async {
    try {
      final file = await _dictionaryFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final entries = decoded['artists'];
      if (entries is! List) return;
      _artists = List.unmodifiable(
        entries
            .map(DanbooruArtistSuggestion.fromJson)
            .whereType<DanbooruArtistSuggestion>(),
      );
      _updatedAt = DateTime.tryParse(decoded['updatedAt']?.toString() ?? '');
    } on Exception {
      _artists = const [];
      _updatedAt = null;
    }
  }

  Future<void> _saveDictionary(
    List<DanbooruArtistSuggestion> artists,
    DateTime updatedAt,
  ) async {
    final file = await _dictionaryFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'updatedAt': updatedAt.toIso8601String(),
          'artists': artists.map((artist) => artist.toJson()).toList(),
        }),
        flush: true,
      );
      if (await backup.exists()) await backup.delete();
      final hadExisting = await file.exists();
      if (hadExisting) await file.rename(backup.path);
      try {
        await temporary.rename(file.path);
      } on Exception {
        if (hadExisting && await backup.exists()) {
          await backup.rename(file.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete();
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<File> _defaultDictionaryFile() async {
    final support = await getApplicationSupportDirectory();
    return File(
      path.join(
        support.path,
        'artist_tag_vault',
        'danbooru_artist_dictionary.json',
      ),
    );
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(' ', '_');

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

class _DanbooruArtistPage {
  const _DanbooruArtistPage({
    required this.artists,
    required this.recordCount,
    required this.lastId,
  });

  final List<DanbooruArtistSuggestion> artists;
  final int recordCount;
  final int? lastId;
}
