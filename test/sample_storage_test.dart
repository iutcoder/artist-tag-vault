import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artist_tag_vault/src/models/custom_artist.dart';
import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('normalizes Danbooru underscores when saving artist samples', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'artist-tag-vault-normalized-save-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final root = Directory(path.join(temporary.path, 'samples'));
    final preset = GenerationPreset.defaults();
    final storage = SampleStorage(rootDirectory: root);

    final image = await storage.save(
      bytes: Uint8List.fromList([1, 2, 3]),
      artist: 'channel_(caststation)',
      composedPrompt: 'artist:channel (caststation)',
      composedUndesiredContent: '',
      seed: 123,
      artistWeight: 1,
      preset: preset,
    );

    expect(
      image.parent.path,
      path.join(root.path, preset.model.apiId, 'channel (caststation)'),
    );
    final sidecar = jsonDecode(
      await File(path.setExtension(image.path, '.json')).readAsString(),
    ) as Map<String, dynamic>;
    expect(sidecar['artist'], 'channel (caststation)');
    expect(sidecar['artistTag'], 'artist:channel (caststation)');
  });

  test(
    'saves Custom samples under the model custom folder with artists',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'artist-tag-vault-custom-save-',
      );
      addTearDown(() async {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final root = Directory(path.join(temporary.path, 'samples'));
      final preset = GenerationPreset.defaults();
      final storage = SampleStorage(rootDirectory: root);

      final image = await storage.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        artist: 'Custom',
        composedPrompt: 'artist:first, 1.25:: artist:second ::, 1girl',
        composedUndesiredContent: 'lowres',
        seed: 123,
        artistWeight: 1,
        preset: preset,
        customArtists: const [
          CustomArtist(name: 'first'),
          CustomArtist(name: 'second', weight: 1.25, fixed: true),
        ],
        randomizeCustomOrder: true,
        randomizeCustomWeights: true,
      );

      expect(
        image.parent.path,
        path.join(root.path, preset.model.apiId, '_artist-mixes'),
      );
      final sidecar = jsonDecode(
        await File(path.setExtension(image.path, '.json')).readAsString(),
      ) as Map<String, dynamic>;
      expect(sidecar['artist'], 'Artist Mixes');
      expect(sidecar['isCustom'], isTrue);
      expect(sidecar['randomizeCustomOrder'], isTrue);
      expect(sidecar['randomizeCustomWeights'], isTrue);
      expect(sidecar['customArtists'], hasLength(2));
      expect(sidecar['artistTags'], [
        'artist:first',
        '1.25:: artist:second ::',
      ]);
      expect((sidecar['customArtists'] as List).last['fixed'], isTrue);
      expect(sidecar['composedPrompt'], contains('artist:second'));
    },
  );

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
