import 'dart:async';
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
      expect(request.url.queryParameters['only'], contains('antecedent_alias'));
      if (request.url.queryParameters['page'] == '1') {
        return http.Response(
          '[{"id":30,"name":"popular_artist","post_count":500,'
          '"category":1},{"id":20,"name":"oshioshio",'
          '"post_count":400,"category":1}]',
          200,
        );
      }
      return http.Response(
        '[{"id":10,"name":"another_oshio","post_count":100,'
        '"category":1}]',
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
      maxRequestAttempts: 1,
    );

    await expectLater(
      service.updateDictionary(),
      throwsA(isA<DanbooruAutocompleteException>()),
    );

    expect((await service.suggestArtists('saved')).single.value, 'saved_artist');
    expect(await dictionary.readAsString(), contains('saved_artist'));
  });

  test('retries a transient connection failure', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-retry-dictionary-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    var attempts = 0;
    final service = DanbooruAutocompleteService(
      client: MockClient((request) async {
        attempts++;
        if (attempts == 1) throw http.ClientException('connection reset');
        return http.Response(
          '[{"id":1,"name":"recovered_artist","post_count":20,'
          '"category":1}]',
          200,
        );
      }),
      dictionaryFile: () async => File(
        path.join(temporary.path, 'artists.json'),
      ),
      retryDelay: Duration.zero,
    );

    final status = await service.updateDictionary();

    expect(attempts, 2);
    expect(status.artistCount, 1);
  });

  test('filters empty, deprecated, and redirected online artist tags', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-filter-dictionary-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final service = DanbooruAutocompleteService(
      client: MockClient(
        (request) async => http.Response(
          '[{"id":4,"name":"kept_artist","post_count":1,"category":1,'
          '"is_deprecated":false,"antecedent_alias":null},'
          '{"id":3,"name":"empty_artist","post_count":0,"category":1},'
          '{"id":2,"name":"old_artist","post_count":5,"category":1,'
          '"is_deprecated":true},'
          '{"id":1,"name":"redirected_artist","post_count":5,'
          '"category":1,"antecedent_alias":{"id":99}}]',
          200,
        ),
      ),
      dictionaryFile: () async => File(
        path.join(temporary.path, 'artists.json'),
      ),
    );

    final status = await service.updateDictionary();

    expect(status.artistCount, 1);
    expect((await service.suggestArtists('kept')).single.value, 'kept_artist');
  });

  test('downloads more than two hundred pages without a fixed limit', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-large-dictionary-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    var remaining = 205;
    final service = DanbooruAutocompleteService(
      client: MockClient((request) async {
        if (remaining == 0) return http.Response('[]', 200);
        final id = remaining--;
        return http.Response(
          '[{"id":$id,"name":"artist_$id","post_count":1,'
          '"category":1}]',
          200,
        );
      }),
      dictionaryFile: () async => File(
        path.join(temporary.path, 'artists.json'),
      ),
      pageSize: 1,
      pageDelay: Duration.zero,
    );

    final status = await service.updateDictionary();

    expect(status.artistCount, 205);
  });

  test('can start an import immediately after cancelling a download', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-cancel-dictionary-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final dictionary = File(path.join(temporary.path, 'artists.json'));
    final requestStarted = Completer<void>();
    final response = Completer<http.Response>();
    final service = DanbooruAutocompleteService(
      client: MockClient((request) {
        requestStarted.complete();
        return response.future;
      }),
      dictionaryFile: () async => dictionary,
      pageDelay: Duration.zero,
    );

    final download = service.updateDictionary();
    await requestStarted.future;
    service.cancelUpdate();
    final imported = await service.importDictionaryJson(
      '[{"value":"local_artist","count":10,"type":"artist"}]',
    );
    response.complete(
      http.Response(
        '[{"id":1,"name":"remote_artist","post_count":20,"category":1}]',
        200,
      ),
    );

    await expectLater(
      download,
      throwsA(isA<DanbooruAutocompleteException>()),
    );
    expect(imported.artistCount, 1);
    expect((await service.suggestArtists('local')).single.value, 'local_artist');
    expect(await dictionary.readAsString(), isNot(contains('remote_artist')));
  });

  test(
    'imports Pheropix and Danbooru tag JSON as an artist dictionary',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'artist-tag-vault-import-dictionary-',
      );
      addTearDown(() async => temporary.delete(recursive: true));
      final dictionary = File(path.join(temporary.path, 'artists.json'));
      final service = DanbooruAutocompleteService(
        client: MockClient((request) async => http.Response('[]', 200)),
        dictionaryFile: () async => dictionary,
      );

      final status = await service.importDictionaryJson(
        '[{"value":"oshioshio","count":400,"type":"artist",'
        '"category":1,"aliases":[]},'
        '{"name":"ningen_mame","post_count":300,"category":1},'
        '{"value":"empty_artist","count":0,"type":"artist"},'
        '{"value":"redirected_artist","count":20,"type":"artist",'
        '"antecedent_alias":{"id":99}},'
        '{"value":"1girl","count":1000,"type":"general","category":0}]',
      );

      expect(status.artistCount, 2);
      expect(
        (await service.suggestArtists('ningen')).single.value,
        'ningen_mame',
      );
      expect(await dictionary.readAsString(), isNot(contains('1girl')));
      expect(await dictionary.readAsString(), isNot(contains('empty_artist')));
      expect(
        await dictionary.readAsString(),
        isNot(contains('redirected_artist')),
      );
    },
  );

  test('does not search for fewer than two characters', () async {
    final service = DanbooruAutocompleteService(
      client: MockClient((request) async => http.Response('[]', 200)),
      dictionaryFile: () async => File('unused.json'),
    );

    expect(await service.suggestArtists('a'), isEmpty);
  });
}
