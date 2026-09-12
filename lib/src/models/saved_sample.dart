import 'dart:io';

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
}
