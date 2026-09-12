import 'dart:io';

import 'package:artist_tag_vault/src/services/danbooru_autocomplete.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;

void main() {
  test('downloads every artist page and searches the saved dictionary', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-dictionary-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final dictionary = File(path.join(temporary.path, 'artists.json'));
    final requestedPages = <String>[];
    final client = MockClient((request) async {
      requestedPages.add(request.url.queryParameters['page']!);
      expect(request.url.queryParameters['search[category]'], '1');
      expect(request.url.queryParameters['search[hide_empty]'], 'true');
      expect(request.url.queryParameters['search[is_deprecated]'], 'false');
      expect(request.url.queryParameters['search[order]'], 'date');
      if (request.url.queryParameters['page'] == '1') {
        return http.Response(
          '[{"id":30,"name":"popular_artist","post_count":500},'
          '{"id":20,"name":"oshioshio","post_count":400}]',
          200,
        );
      }
      return http.Response(
        '[{"id":10,"name":"another_oshio","post_count":100}]',
        200,
      );
    });
    final service = DanbooruAutocompleteService(
      client: client,
      endpoint: Uri.parse('https://example.test/tags.json'),
      dictionaryFile: () async => dictionary,
      pageSize: 2,
      pageDelay: Duration.zero,
    );

    expect((await service.status()).isAvailable, isFalse);
    final status = await service.updateDictionary();
    final results = await service.suggestArtists('oshio');

    expect(requestedPages, ['1', 'b20']);
    expect(status.artistCount, 3);
    expect(await dictionary.exists(), isTrue);
    expect(results.map((item) => item.value), ['oshioshio', 'another_oshio']);
    expect(results.first.count, 400);
  });

  test('loads the dictionary from disk without making an API request', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-local-dictionary-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final dictionary = File(path.join(temporary.path, 'artists.json'));
    await dictionary.writeAsString(
      '{"updatedAt":"2026-09-12T00:00:00Z","artists":['
      '{"value":"ningen_mame","count":123}]}',
    );
    var requested = false;
    final service = DanbooruAutocompleteService(
      client: MockClient((request) async {
        requested = true;
        return http.Response('[]', 200);
      }),
      dictionaryFile: () async => dictionary,
    );

    final results = await service.suggestArtists('ningen m');

    expect(requested, isFalse);
    expect(results.single.value, 'ningen_mame');
    expect((await service.status()).artistCount, 1);
  });

  test('failed update leaves an existing dictionary available', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-preserve-dictionary-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final dictionary = File(path.join(temporary.path, 'artists.json'));
    await dictionary.writeAsString(
      '{"updatedAt":"2026-09-12T00:00:00Z","artists":['
      '{"value":"saved_artist","count":50}]}',
    );
    final service = DanbooruAutocompleteService(
      client: MockClient((request) async => http.Response('unavailable', 503)),
      dictionaryFile: () async => dictionary,
      pageDelay: Duration.zero,
    );

    await expectLater(
      service.updateDictionary(),
      throwsA(isA<DanbooruAutocompleteException>()),
    );

    expect((await service.suggestArtists('saved')).single.value, 'saved_artist');
    expect(await dictionary.readAsString(), contains('saved_artist'));
  });

  test('does not search for fewer than two characters', () async {
    final service = DanbooruAutocompleteService(
      client: MockClient((request) async => http.Response('[]', 200)),
      dictionaryFile: () async => File('unused.json'),
    );

    expect(await service.suggestArtists('a'), isEmpty);
  });
}
