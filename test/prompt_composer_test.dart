import 'package:artist_tag_vault/src/services/prompt_composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds the artist prefix before the shared preset', () {
    expect(
      PromptComposer.compose(
        artist: 'sample_artist',
        presetPrompt: '1girl, solo',
      ),
      'artist:sample_artist, 1girl, solo',
    );
  });

  test('does not duplicate a prefix supplied by the user', () {
    expect(
      PromptComposer.compose(artist: 'artist:sample_artist', presetPrompt: ''),
      'artist:sample_artist',
    );
  });

  test('numeric emphasis wraps only the artist tag', () {
    expect(
      PromptComposer.compose(
        artist: 'sample_artist',
        presetPrompt: '1girl, solo',
        artistWeight: 1.5,
      ),
      '1.50:: artist:sample_artist ::, 1girl, solo',
    );
  });

  test('numeric emphasis separates an artist name ending in digits', () {
    expect(
      PromptComposer.compose(
        artist: 'artist:ratatatat74',
        presetPrompt: '',
        artistWeight: -1,
      ),
      '-1.00:: artist:ratatatat74 ::',
    );
  });

  test('negative numeric emphasis keeps two decimal places', () {
    expect(
      PromptComposer.compose(
        artist: 'sample_artist',
        presetPrompt: '',
        artistWeight: -0.25,
      ),
      '-0.25:: artist:sample_artist ::',
    );
  });

  test('multiple artists preserve their input order and weights', () {
    expect(
      PromptComposer.composeMultiple(
        artists: [
          (artist: 'first', weight: 1.0),
          (artist: 'artist:second2', weight: 1.25),
        ],
        presetPrompt: '1girl',
      ),
      'artist:first, 1.25:: artist:second2 ::, 1girl',
    );
  });
}
