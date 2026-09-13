import 'dart:math';

import 'package:artist_tag_vault/src/models/custom_artist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes the generated Custom artist list', () {
    const artist = CustomArtist(name: 'ningen_mame', weight: 1.25, fixed: true);
    expect(CustomArtist.fromJson(artist.toJson())?.name, 'ningen mame');
    expect(CustomArtist.fromJson(artist.toJson())?.weight, artist.weight);
    expect(CustomArtist.fromJson(artist.toJson())?.fixed, isTrue);
    expect(CustomArtist.fromJson({'name': ''}), isNull);
  });

  test('parses comma and newline separated artists in order', () {
    final artists = CustomArtistParser.parseMany(
      'ningen mame, wanke\nlack, artist:oshioshio',
      defaultWeight: .75,
    );
    expect(
      artists.map((artist) => artist.name),
      ['ningen mame', 'wanke', 'lack', 'oshioshio'],
    );
    expect(artists.every((artist) => artist.weight == .75), isTrue);
  });

  test('weighted artist tags override the default weight', () {
    final artists = CustomArtistParser.parseMany(
      '1.25:: artist:ningen_mame ::, '
      '-0.50:: artist:wanke ::, lack',
      defaultWeight: 1,
    );
    expect(artists.map((artist) => artist.name), [
      'ningen mame',
      'wanke',
      'lack',
    ]);
    expect(artists.map((artist) => artist.weight), [1.25, -.5, 1]);
  });

  test('accepts a comma immediately before the closing weight marker', () {
    final artists = CustomArtistParser.parseMany(
      '0.5::artist:ratatatatat74,::, ningen mame',
    );
    expect(artists.map((artist) => artist.name), [
      'ratatatatat74',
      'ningen mame',
    ]);
    expect(artists.map((artist) => artist.weight), [.5, 1]);
  });

  test('applies one weight block to multiple artist tags', () {
    final artists = CustomArtistParser.parseMany(
      '0.75::artist:first, artist:second,::, third',
    );
    expect(artists.map((artist) => artist.name), ['first', 'second', 'third']);
    expect(artists.map((artist) => artist.weight), [.75, .75, 1]);
  });

  test('rejects malformed and out-of-range weighted tags', () {
    expect(
      () => CustomArtistParser.parseMany('1.25:: artist:name'),
      throwsFormatException,
    );
    expect(
      () => CustomArtistParser.parseMany('6.00:: artist:name ::'),
      throwsFormatException,
    );
  });

  test('fixed artists keep their position and weight', () {
    const artists = [
      CustomArtist(name: 'a', weight: .7),
      CustomArtist(name: 'fixed', weight: 1.23, fixed: true),
      CustomArtist(name: 'b', weight: 1.4),
    ];

    final prepared = CustomArtistRandomizer.prepare(
      artists,
      randomizeOrder: true,
      randomizeWeights: true,
      random: Random(7),
    );

    expect(prepared[1].name, 'fixed');
    expect(prepared[1].weight, 1.23);
    expect(
      prepared.where((artist) => !artist.fixed).map((artist) => artist.name),
      containsAll(['a', 'b']),
    );
    expect(
      prepared.where((artist) => !artist.fixed).every(
            (artist) => artist.weight >= .5 && artist.weight <= 1.5,
          ),
      isTrue,
    );
  });
}
