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

/// Parses ordered artist lists pasted into the Custom add dialog.
class CustomArtistParser {
  const CustomArtistParser._();

  static final _weightedTag = RegExp(
    r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*::\s*'
    r'(?:artist\s*:\s*)?(.+?)\s*::\s*$',
    caseSensitive: false,
  );
  static final _artistPrefix = RegExp(
    r'^artist\s*:\s*',
    caseSensitive: false,
  );

  static List<CustomArtist> parseMany(
    String source, {
    double defaultWeight = 1,
  }) {
    _validateWeight(defaultWeight, label: 'Default weight');
    final result = <CustomArtist>[];
    final tokens = source.split(RegExp(r'[,\r\n]+'));
    for (final rawToken in tokens) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;

      final weighted = _weightedTag.firstMatch(token);
      if (weighted != null) {
        final weight = double.parse(weighted.group(1)!);
        _validateWeight(weight, label: 'Weight for ${weighted.group(2)}');
        final name = weighted.group(2)!.trim();
        if (name.isNotEmpty) {
          result.add(CustomArtist(name: name, weight: weight));
        }
        continue;
      }

      if (token.contains('::')) {
        throw FormatException('Invalid weighted artist tag: $token');
      }
      final name = token.replaceFirst(_artistPrefix, '').trim();
      if (name.isNotEmpty) {
        result.add(CustomArtist(name: name, weight: defaultWeight));
      }
    }
    return result;
  }

  static void _validateWeight(double weight, {required String label}) {
    if (!weight.isFinite || weight < -5 || weight > 5) {
      throw FormatException('$label must be between -5.00 and 5.00.');
    }
  }
}
