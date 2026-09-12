/// Builds the deterministic prompt used to compare artists.
class PromptComposer {
  const PromptComposer._();

  /// Adds exactly one `artist:` prefix and then appends the shared preset.
  ///
  /// A weight of 1 is intentionally emitted as an ordinary tag. Other values
  /// use NovelAI's numeric emphasis syntax and affect only the artist tag.
  static String compose({
    required String artist,
    required String presetPrompt,
    double artistWeight = 1,
  }) {
    final artistTag = formatArtistTag(artist, artistWeight);
    final preset = presetPrompt.trim();
    return preset.isEmpty ? artistTag : '$artistTag, $preset';
  }

  /// Composes an ordered list of artist tags before the shared preset.
  static String composeMultiple({
    required Iterable<({String artist, double weight})> artists,
    required String presetPrompt,
  }) {
    final artistTags = artists
        .map((entry) => formatArtistTag(entry.artist, entry.weight))
        .join(', ');
    final preset = presetPrompt.trim();
    return preset.isEmpty ? artistTags : '$artistTags, $preset';
  }

  static String formatArtistTag(String artist, double weight) {
    final trimmed = artist.trim();
    final withoutPrefix = trimmed.toLowerCase().startsWith('artist:')
        ? trimmed.substring('artist:'.length).trim()
        : trimmed;
    final plainArtistTag = 'artist:$withoutPrefix';
    return (weight - 1).abs() < 0.000001
        ? plainArtistTag
        : '${weight.toStringAsFixed(2)}:: $plainArtistTag ::';
  }
}
