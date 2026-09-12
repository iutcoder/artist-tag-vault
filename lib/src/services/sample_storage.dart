import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Saves samples in model/artist folders so a future gallery can scan them.
class SampleStorage {
  Future<Directory> rootDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'ArtistTagVault', 'samples'));
  }

  Future<File> save({
    required Uint8List bytes,
    required String artist,
    required String composedPrompt,
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

    // A sidecar keeps enough provenance for gallery filters and reproducibility.
    final metadataFile = File(path.join(directory.path, '$basename.json'));
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'artist': artist.trim(),
        'artistTag': 'artist:${artist.trim()}',
        'artistWeight': artistWeight,
        'generatedAt': generatedAt.toIso8601String(),
        'seed': seed,
        'composedPrompt': composedPrompt,
        'preset': preset.toJson(),
        'image': path.basename(imageFile.path),
      }),
      flush: true,
    );
    return imageFile;
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
