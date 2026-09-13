import 'dart:io';
import 'dart:ui' as ui;

import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:artist_tag_vault/src/vault_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  testWidgets('renders the initially selected Vault image', (tester) async {
    final root = await Directory.systemTemp.createTemp('vault_page_test_');
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      if (await root.exists()) await root.delete(recursive: true);
    });

    final sampleDirectory = Directory(
      path.join(root.path, 'nai-diffusion-4-5-full', 'test artist'),
    );
    await sampleDirectory.create(recursive: true);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 8, 8),
      ui.Paint()..color = Colors.cyan,
    );
    final image = await recorder.endRecording().toImage(8, 8);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(path.join(sampleDirectory.path, 'sample.png')).writeAsBytes(
      png!.buffer.asUint8List(),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultPage(
            storage: SampleStorage(rootDirectory: root),
            onUseSample: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mainImage = find.byKey(const Key('vault-main-image'));
    expect(mainImage, findsOneWidget);
    expect(tester.getSize(mainImage).width, greaterThan(0));
    expect(tester.getSize(mainImage).height, greaterThan(0));
  });
}
