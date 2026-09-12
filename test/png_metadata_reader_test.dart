import 'dart:convert';
import 'dart:io';

import 'package:artist_tag_vault/src/services/png_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads text and flattened NovelAI Comment JSON', () async {
    final directory = await Directory.systemTemp.createTemp('atv-png-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/sample.png');
    await file.writeAsBytes([
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      ..._chunk('tEXt', [
        ...latin1.encode('Description'),
        0,
        ...utf8.encode('artist:test'),
      ]),
      ..._chunk('tEXt', [
        ...latin1.encode('Comment'),
        0,
        ...utf8.encode('{"seed":42,"steps":28}'),
      ]),
      ..._chunk('IEND', const []),
    ]);

    final metadata = await const PngMetadataReader().read(file);
    expect(metadata['Description'], 'artist:test');
    expect(metadata['seed'], 42);
    expect(metadata['steps'], 28);
  });
}

List<int> _chunk(String type, List<int> data) => [
  (data.length >> 24) & 0xff,
  (data.length >> 16) & 0xff,
  (data.length >> 8) & 0xff,
  data.length & 0xff,
  ...ascii.encode(type),
  ...data,
  0,
  0,
  0,
  0,
];
