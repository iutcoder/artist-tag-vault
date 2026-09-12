/// Builds the deterministic prompt used to compare artists.
class PromptComposer {
  const PromptComposer._();

  /// Adds exactly one `artist:` prefix and then appends the shared preset.
  static String compose({required String artist, required String presetPrompt}) {
    final trimmed = artist.trim();
    final withoutPrefix = trimmed.toLowerCase().startsWith('artist:')
        ? trimmed.substring('artist:'.length).trim()
        : trimmed;
    final artistTag = 'artist:$withoutPrefix';
    final preset = presetPrompt.trim();
    return preset.isEmpty ? artistTag : '$artistTag, $preset';
  }
}
