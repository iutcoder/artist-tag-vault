import 'dart:io';

import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:flutter_test/flutter_test.dart';

SavedSample sampleWithPrompt(String prompt) => SavedSample(
  file: File('sample.png'),
  artist: 'sample',
  modelId: 'model',
  createdAt: DateTime(2026),
  metadata: {'prompt': prompt},
);

void main() {
  test('classifies exact 1girl and 1boy prompt tags', () {
    expect(sampleWithPrompt('artist:a, 1girl').subject, SampleSubject.female);
    expect(sampleWithPrompt('artist:a, 1boy').subject, SampleSubject.male);
  });

  test('mixed, absent, and longer tags are others', () {
    expect(
      sampleWithPrompt('1girl, 1boy, artist:a').subject,
      SampleSubject.others,
    );
    expect(sampleWithPrompt('artist:a').subject, SampleSubject.others);
    expect(sampleWithPrompt('11girls, artist:a').subject, SampleSubject.others);
  });

  test('identifies samples saved by Custom generation', () {
    final custom = SavedSample(
      file: File('custom.png'),
      artist: 'Custom',
      modelId: 'model',
      createdAt: DateTime(2026),
      metadata: const {'isCustom': true},
    );
    expect(custom.isCustom, isTrue);
    expect(custom.vaultGroupKey, 'custom:');
    expect(custom.vaultGroupLabel, 'Artist Mixes');
    expect(sampleWithPrompt('artist:a').isCustom, isFalse);
    expect(sampleWithPrompt('artist:a').vaultGroupKey, 'artist:sample');
  });

  test('Custom and an identically named artist use separate Vault groups', () {
    final custom = SavedSample(
      file: File('custom.png'),
      artist: 'Artist Mixes',
      modelId: 'model',
      createdAt: DateTime(2026),
      metadata: const {'isCustom': true},
    );
    final artist = SavedSample(
      file: File('artist.png'),
      artist: 'Artist Mixes',
      modelId: 'model',
      createdAt: DateTime(2026),
      metadata: const {},
    );
    expect(custom.vaultGroupKey, isNot(artist.vaultGroupKey));
  });

  test('groups Danbooru underscore and NovelAI space names together', () {
    final danbooru = SavedSample(
      file: File('underscore.png'),
      artist: 'channel_(caststation)',
      modelId: 'model',
      createdAt: DateTime(2026),
      metadata: const {},
    );
    final novelAi = SavedSample(
      file: File('space.png'),
      artist: 'channel (caststation)',
      modelId: 'model',
      createdAt: DateTime(2026),
      metadata: const {},
    );

    expect(danbooru.vaultGroupKey, novelAi.vaultGroupKey);
    expect(danbooru.vaultGroupLabel, 'channel (caststation)');
    expect(danbooru.artistTags, 'artist:channel (caststation)');
  });

  test('formats a single artist tag for clipboard copying', () {
    final weighted = SavedSample(
      file: File('weighted.png'),
      artist: 'mikozin',
      modelId: 'model',
      createdAt: DateTime(2026),
      metadata: const {'artistWeight': .4},
    );
    expect(weighted.artistTags, '0.40:: artist:mikozin ::');
    expect(sampleWithPrompt('artist:a').artistTags, 'artist:sample');
  });

  test('formats Custom artist tags in the saved generation order', () {
    final custom = SavedSample(
      file: File('mix.png'),
      artist: 'Artist Mixes',
      modelId: 'model',
      createdAt: DateTime(2026),
      metadata: const {
        'isCustom': true,
        'customArtists': [
          {'name': 'mikozin', 'weight': .4, 'fixed': false},
          {'name': 'lack', 'weight': 1.0, 'fixed': true},
        ],
      },
    );
    expect(custom.artistTags, '0.40:: artist:mikozin ::, artist:lack');
  });
}
