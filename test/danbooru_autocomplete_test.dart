import 'package:artist_tag_vault/src/services/danbooru_autocomplete.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('requests artist autocomplete and parses canonical values', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        '[{"label":"Some Artist","value":"some_artist"},'
        '{"label":"Duplicate","value":"some_artist"}]',
        200,
      );
    });
    final service = DanbooruAutocompleteService(
      client: client,
      endpoint: Uri.parse('https://example.test/autocomplete.json'),
      persistentCache: false,
    );

    final results = await service.suggestArtists('some', limit: 5);

    expect(requestedUri.queryParameters['search[query]'], 'some');
    expect(requestedUri.queryParameters['search[type]'], 'artist');
    expect(requestedUri.queryParameters['limit'], '5');
    expect(results, hasLength(1));
    expect(results.single.label, 'Some Artist');
    expect(results.single.value, 'some_artist');
  });

  test('does not make a request for fewer than two characters', () async {
    var requested = false;
    final service = DanbooruAutocompleteService(
      client: MockClient((request) async {
        requested = true;
        return http.Response('[]', 200);
      }),
      persistentCache: false,
    );

    expect(await service.suggestArtists('a'), isEmpty);
    expect(requested, isFalse);
  });

  test('reports non-success responses', () async {
    final service = DanbooruAutocompleteService(
      client: MockClient((request) async => http.Response('unavailable', 503)),
      persistentCache: false,
    );

    await expectLater(
      service.suggestArtists('artist'),
      throwsA(isA<DanbooruAutocompleteException>()),
    );
  });
}
