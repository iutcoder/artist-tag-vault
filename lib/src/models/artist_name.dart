final _artistPrefix = RegExp(r'^artist\s*:\s*', caseSensitive: false);

/// Returns the NovelAI-friendly display form of an artist name.
///
/// Danbooru stores spaces as underscores, while NovelAI recommends ordinary
/// spaces. Treating both separators identically also keeps legacy Vault
/// folders grouped with newly generated samples.
String normalizeArtistName(String value) {
  return value
      .trim()
      .replaceFirst(_artistPrefix, '')
      .replaceAll(RegExp(r'[_\s]+'), ' ')
      .trim();
}

/// Stable case-insensitive identity used for grouping and de-duplication.
String artistIdentityKey(String value) =>
    normalizeArtistName(value).toLowerCase();
