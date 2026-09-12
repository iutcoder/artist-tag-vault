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
    final preset = GenerationPreset.fromJson({'width': 1216, 'height': 832});
    expect(preset.aspectRatio, ImageAspectRatioPreset.landscape);
    expect(preset.resolution, ImageResolutionPreset.normal);
  });

  test('out-of-range numeric preferences are clamped while loading', () {
    final preset = GenerationPreset.fromJson({
      'steps': 99,
      'guidance': -3,
      'guidanceRescale': 2.5,
    });
    expect(preset.steps, 50);
    expect(preset.guidance, 0);
    expect(preset.guidanceRescale, 1);
  });

  test('negative emphasis is enabled only for V4.5 and newer models', () {
    expect(NovelAiModel.animeV3.supportsNumericalEmphasis, isFalse);
    expect(NovelAiModel.v4Full.supportsNumericalEmphasis, isTrue);
    expect(NovelAiModel.v4Full.supportsNegativeNumericalEmphasis, isFalse);
    expect(NovelAiModel.v45Full.supportsNegativeNumericalEmphasis, isTrue);
    expect(NovelAiModel.v5Full.supportsNegativeNumericalEmphasis, isTrue);
  });

  test('V5 quality selections append the documented suffix', () {
    final light = GenerationPreset.defaults().copyWith(
      model: NovelAiModel.v5Full,
      qualityTagPreset: QualityTagPreset.light,
    );
    final standard = light.copyWith(
      qualityTagPreset: QualityTagPreset.standard,
    );
    expect(
      light.composePrompt('1girl'),
      '1girl, very aesthetic, amazing quality, no text',
    );
    expect(
      standard.composePrompt('1girl'),
      '1girl, very aesthetic, masterpiece, no text',
    );
  });

  test('automatic UC and custom UC are combined once', () {
    final preset = GenerationPreset.defaults().copyWith(
      model: NovelAiModel.v5Full,
      undesiredContentPreset: UndesiredContentPreset.humanFocus,
      undesiredContent: 'extra fingers',
    );
    expect(preset.composedUndesiredContent, contains('mismatched pupils'));
    expect(preset.composedUndesiredContent, endsWith(', extra fingers'));
  });

  test('legacy preferences preserve their previous effective text', () {
    final preset = GenerationPreset.fromJson({
      'prompt': 'portrait',
      'undesiredContent': 'lowres',
    });
    expect(preset.qualityTagPreset, QualityTagPreset.off);
    expect(preset.undesiredContentPreset, UndesiredContentPreset.none);
    expect(preset.composePrompt('artist:test'), 'artist:test');
    expect(preset.composedUndesiredContent, 'lowres');
  });
}
