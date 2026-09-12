import 'dart:math';

/// One artist participating in a custom multi-artist prompt.
class CustomArtist {
  const CustomArtist({
    required this.name,
    this.weight = 1,
    this.fixed = false,
  });

  final String name;
  final double weight;
  final bool fixed;

  Map<String, dynamic> toJson() => {
    'name': name,
    'weight': weight,
    'fixed': fixed,
  };

  static CustomArtist? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name']?.toString().trim() ?? '';
    final weight = double.tryParse(value['weight']?.toString() ?? '');
    if (name.isEmpty || weight == null) return null;
    return CustomArtist(
      name: name,
      weight: weight,
      fixed: value['fixed'] == true,
    );
  }

  CustomArtist copyWith({String? name, double? weight, bool? fixed}) {
    return CustomArtist(
      name: name ?? this.name,
      weight: weight ?? this.weight,
      fixed: fixed ?? this.fixed,
    );
  }
}

/// Produces one generation's artist order and weights.
class CustomArtistRandomizer {
  const CustomArtistRandomizer._();

  static List<CustomArtist> prepare(
    List<CustomArtist> source, {
    required bool randomizeOrder,
    required bool randomizeWeights,
    required Random random,
  }) {
    final result = List<CustomArtist>.of(source);

    if (randomizeOrder) {
      final movable = source.where((artist) => !artist.fixed).toList()..shuffle(random);
      var movableIndex = 0;
      for (var index = 0; index < result.length; index++) {
        if (!source[index].fixed) result[index] = movable[movableIndex++];
      }
    }

    if (randomizeWeights) {
      for (var index = 0; index < result.length; index++) {
        final artist = result[index];
        if (!artist.fixed) {
          final weight = (50 + random.nextInt(101)) / 100;
          result[index] = artist.copyWith(weight: weight);
        }
      }
    }

    return result;
  }
}
