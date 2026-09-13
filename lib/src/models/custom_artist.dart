import 'dart:math';

import 'package:artist_tag_vault/src/models/artist_name.dart';

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
    final name = normalizeArtistName(value['name']?.toString() ?? '');
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

  static final _weightedBlock = RegExp(
    r'([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*::(.*?)::',
    caseSensitive: false,
    dotAll: true,
  );
  static List<CustomArtist> parseMany(
    String source, {
    double defaultWeight = 1,
  }) {
    _validateWeight(defaultWeight, label: 'Default weight');
    final result = <CustomArtist>[];
    var cursor = 0;
    for (final weighted in _weightedBlock.allMatches(source)) {
      _appendPlainArtists(
        result,
        source.substring(cursor, weighted.start),
        defaultWeight,
      );
      final weight = double.parse(weighted.group(1)!);
      _validateWeight(weight, label: 'Artist weight');
      final before = result.length;
      _appendArtists(result, weighted.group(2)!, weight);
      if (result.length == before) {
        throw const FormatException('A weighted artist block is empty.');
      }
      cursor = weighted.end;
    }
    _appendPlainArtists(result, source.substring(cursor), defaultWeight);
    return result;
  }

  static void _appendPlainArtists(
    List<CustomArtist> result,
    String source,
    double weight,
  ) {
    if (source.contains('::')) {
      final invalid = source.trim();
      throw FormatException('Invalid weighted artist tag: $invalid');
    }
    _appendArtists(result, source, weight);
  }

  static void _appendArtists(
    List<CustomArtist> result,
    String source,
    double weight,
  ) {
    for (final rawName in source.split(RegExp(r'[,\r\n]+'))) {
      final name = normalizeArtistName(rawName);
      if (name.isNotEmpty) {
        result.add(CustomArtist(name: name, weight: weight));
      }
    }
  }

  static void _validateWeight(double weight, {required String label}) {
    if (!weight.isFinite || weight < -5 || weight > 5) {
      throw FormatException('$label must be between -5.00 and 5.00.');
    }
  }
}
