import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:artist_tag_vault/src/services/png_metadata_reader.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Saves and scans the model/artist folder hierarchy used by Vault.
class SampleStorage {
  SampleStorage({PngMetadataReader? metadataReader})
    : _metadataReader = metadataReader ?? const PngMetadataReader();

  final PngMetadataReader _metadataReader;

  Future<Directory> rootDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'ArtistTagVault', 'samples'));
  }

  Future<File> save({
    required Uint8List bytes,
    required String artist,
    required String composedPrompt,
    required String composedUndesiredContent,
    required int seed,
    required double artistWeight,
    required GenerationPreset preset,
  }) async {
    final root = await rootDirectory();
    final artistFolder = _safeSegment(artist);
    final directory = Directory(
      path.join(root.path, preset.model.apiId, artistFolder),
    );
    await directory.create(recursive: true);

    final generatedAt = DateTime.now().toUtc();
    final timestamp = generatedAt.toIso8601String().replaceAll(':', '-');
    final basename = '${timestamp}_seed-$seed';
    final imageFile = File(path.join(directory.path, '$basename.png'));
    await imageFile.writeAsBytes(bytes, flush: true);

    // Embedded PNG metadata remains the primary portable source. The sidecar
    // preserves app-only fields (artist identity and preset choices) and lets
    // Vault recover information from PNGs that omit standard text chunks.
    final metadataFile = File(path.join(directory.path, '$basename.json'));
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'artist': artist.trim(),
        'artistTag': 'artist:${artist.trim()}',
        'artistWeight': artistWeight,
        'generatedAt': generatedAt.toIso8601String(),
        'seed': seed,
        'composedPrompt': composedPrompt,
        'composedUndesiredContent': composedUndesiredContent,
        'preset': preset.toJson(),
        'image': path.basename(imageFile.path),
      }),
      flush: true,
    );
    return imageFile;
  }

  Future<List<SavedSample>> scan() async {
    final root = await rootDirectory();
    if (!await root.exists()) return const [];
    final images = await root
        .list(recursive: true, followLinks: false)
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.png'),
        )
        .cast<File>()
        .toList();

    final samples = <SavedSample>[];
    for (final image in images) {
      final relative = path.relative(image.path, from: root.path);
      final parts = path.split(relative);
      if (parts.length < 3) continue;
      final stat = await image.stat();
      final embedded = await _metadataReader.read(image);
      final sidecar = await _readSidecar(image);
      final metadata = <String, dynamic>{...sidecar, ...embedded};
      final preset = metadata['preset'];
      if (preset is Map<String, dynamic>) {
        metadata.addAll(preset);
      }
      metadata['prompt'] ??= metadata['composedPrompt'];
      metadata['negative_prompt'] ??=
          metadata['composedUndesiredContent'] ?? metadata['undesiredContent'];
      samples.add(
        SavedSample(
          file: image,
          artist: (metadata['artist'] ?? parts[1]).toString(),
          modelId: parts[0],
          createdAt:
              DateTime.tryParse((metadata['generatedAt'] ?? '').toString()) ??
              stat.modified,
          metadata: metadata,
        ),
      );
    }
    samples.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return samples;
  }

  Future<Map<String, dynamic>> _readSidecar(File image) async {
    final sidecar = File(path.setExtension(image.path, '.json'));
    if (!await sidecar.exists()) return const {};
    try {
      final decoded = jsonDecode(await sidecar.readAsString());
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on Exception {
      return const {};
    }
  }

  Future<void> revealFile(File file) async {
    final opened = await launchUrl(Uri.file(file.parent.path));
    if (!opened) {
      throw FileSystemException('이미지 폴더를 열 수 없습니다.', file.path);
    }
  }

  Future<void> openRootDirectory() async {
    final directory = await rootDirectory();
    await directory.create(recursive: true);
    final opened = await launchUrl(Uri.file(directory.path));
    if (!opened) {
      throw FileSystemException('저장 폴더를 열 수 없습니다.', directory.path);
    }
  }

  String _safeSegment(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'unknown-artist' : cleaned;
  }
}
