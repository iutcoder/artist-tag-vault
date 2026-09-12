import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal portrait resolves to the documented base canvas', () {
    final preset = GenerationPreset.defaults();
    expect(preset.width, 832);
    expect(preset.height, 1216);
    expect(preset.exceedsNormalFreeBoundary, isFalse);
  });

  test('large canvas is marked as potentially consuming Anlas', () {
    final preset = GenerationPreset.defaults().copyWith(
      resolution: ImageResolutionPreset.large,
    );
    expect(preset.width, 1024);
    expect(preset.height, 1536);
    expect(preset.exceedsNormalFreeBoundary, isTrue);
  });

  test('old width and height preferences migrate to new selectors', () {
    final preset = GenerationPreset.fromJson({
      'width': 1216,
      'height': 832,
    });
    expect(preset.aspectRatio, ImageAspectRatioPreset.landscape);
    expect(preset.resolution, ImageResolutionPreset.normal);
  });
}
