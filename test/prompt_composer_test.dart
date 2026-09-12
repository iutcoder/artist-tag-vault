import 'package:artist_tag_vault/src/services/prompt_composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds the artist prefix before the shared preset', () {
    expect(
      PromptComposer.compose(artist: 'sample_artist', presetPrompt: '1girl, solo'),
      'artist:sample_artist, 1girl, solo',
    );
  });

  test('does not duplicate a prefix supplied by the user', () {
    expect(
      PromptComposer.compose(artist: 'artist:sample_artist', presetPrompt: ''),
      'artist:sample_artist',
    );
  });
}
