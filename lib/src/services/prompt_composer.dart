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
    final trimmed = artist.trim();
    final withoutPrefix = trimmed.toLowerCase().startsWith('artist:')
        ? trimmed.substring('artist:'.length).trim()
        : trimmed;
    final plainArtistTag = 'artist:$withoutPrefix';
    final artistTag = (artistWeight - 1).abs() < 0.000001
        ? plainArtistTag
        : '${artistWeight.toStringAsFixed(2)}:: $plainArtistTag ::';
    final preset = presetPrompt.trim();
    return preset.isEmpty ? artistTag : '$artistTag, $preset';
  }
}
