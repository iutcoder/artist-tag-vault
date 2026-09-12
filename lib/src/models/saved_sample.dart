import 'dart:io';

enum SampleSubject { female, male, others }

/// One PNG discovered in the sample vault with its embedded generation data.
class SavedSample {
  const SavedSample({
    required this.file,
    required this.artist,
    required this.modelId,
    required this.createdAt,
    required this.metadata,
  });

  final File file;
  final String artist;
  final String modelId;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  int? get seed => (metadata['seed'] as num?)?.toInt();
  String get prompt =>
      (metadata['prompt'] ?? metadata['Description'] ?? '').toString();
  String get undesiredContent =>
      (metadata['negative_prompt'] ?? metadata['uc'] ?? '').toString();

  SampleSubject get subject {
    final normalized = prompt.toLowerCase();
    final hasGirl = _containsPromptTag(normalized, '1girl');
    final hasBoy = _containsPromptTag(normalized, '1boy');
    if (hasGirl && !hasBoy) return SampleSubject.female;
    if (hasBoy && !hasGirl) return SampleSubject.male;
    return SampleSubject.others;
  }

  bool _containsPromptTag(String value, String tag) {
    return RegExp('(^|[^a-z0-9_])$tag(?=\$|[^a-z0-9_])').hasMatch(value);
  }
}
