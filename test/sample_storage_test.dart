import 'dart:io';

import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('deleteSample removes the PNG, sidecar, and empty folders', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-delete-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final root = Directory(path.join(temporary.path, 'samples'));
    final artistDirectory = Directory(
      path.join(root.path, 'model-id', 'artist-name'),
    );
    await artistDirectory.create(recursive: true);
    final image = File(path.join(artistDirectory.path, 'sample.png'));
    final sidecar = File(path.join(artistDirectory.path, 'sample.json'));
    await image.writeAsBytes([1, 2, 3]);
    await sidecar.writeAsString('{}');

    final storage = SampleStorage(rootDirectory: root);
    await storage.deleteSample(
      SavedSample(
        file: image,
        artist: 'artist-name',
        modelId: 'model-id',
        createdAt: DateTime.utc(2026),
        metadata: const {},
      ),
    );

    expect(await image.exists(), isFalse);
    expect(await sidecar.exists(), isFalse);
    expect(await artistDirectory.exists(), isFalse);
    expect(await Directory(path.join(root.path, 'model-id')).exists(), isFalse);
    expect(await root.exists(), isTrue);
  });

  test('deleteSample rejects files outside the Vault root', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-delete-outside-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final root = Directory(path.join(temporary.path, 'samples'));
    await root.create();
    final image = File(path.join(temporary.path, 'outside.png'));
    await image.writeAsBytes([1, 2, 3]);

    final storage = SampleStorage(rootDirectory: root);
    final sample = SavedSample(
      file: image,
      artist: 'artist-name',
      modelId: 'model-id',
      createdAt: DateTime.utc(2026),
      metadata: const {},
    );

    await expectLater(
      storage.deleteSample(sample),
      throwsA(isA<FileSystemException>()),
    );
    expect(await image.exists(), isTrue);
  });
}
