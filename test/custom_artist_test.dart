import 'dart:math';

import 'package:artist_tag_vault/src/models/custom_artist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes the generated Custom artist list', () {
    const artist = CustomArtist(name: 'ningen_mame', weight: 1.25, fixed: true);
    expect(CustomArtist.fromJson(artist.toJson())?.name, artist.name);
    expect(CustomArtist.fromJson(artist.toJson())?.weight, artist.weight);
    expect(CustomArtist.fromJson(artist.toJson())?.fixed, isTrue);
    expect(CustomArtist.fromJson({'name': ''}), isNull);
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
