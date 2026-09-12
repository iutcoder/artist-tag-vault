/// NovelAI model choices exposed by the first desktop prototype.
enum NovelAiModel {
  v5Full('NovelAI Diffusion V5 Full', 'nai-diffusion-5-full'),
  v5Curated('NovelAI Diffusion V5 Curated', 'nai-diffusion-5-curated'),
  v45Full('NovelAI Diffusion V4.5 Full', 'nai-diffusion-4-5-full'),
  v45Curated('NovelAI Diffusion V4.5 Curated', 'nai-diffusion-4-5-curated'),
  v4Full('NovelAI Diffusion V4 Full', 'nai-diffusion-4-full'),
  v4Curated('NovelAI Diffusion V4 Curated', 'nai-diffusion-4-curated-preview'),
  animeV3('NovelAI Diffusion Anime V3', 'nai-diffusion-3');

  const NovelAiModel(this.label, this.apiId);

  final String label;
  final String apiId;

  bool get isV5 => this == v5Full || this == v5Curated;
}

/// Human-readable sampler entry paired with its API identifier.
enum NovelAiSampler {
  euler('Euler', 'k_euler'),
  eulerAncestral('Euler Ancestral', 'k_euler_ancestral'),
  dpmpp2m('DPM++ 2M', 'k_dpmpp_2m'),
  dpmpp2sAncestral('DPM++ 2S Ancestral', 'k_dpmpp_2s_ancestral'),
  dpmppSde('DPM++ SDE', 'k_dpmpp_sde'),
  ddim('DDIM', 'ddim_v3');

  const NovelAiSampler(this.label, this.apiId);

  final String label;
  final String apiId;
}

enum NoiseSchedule {
  karras('Karras', 'karras'),
  native('Native', 'native'),
  exponential('Exponential', 'exponential'),
  polyexponential('Polyexponential', 'polyexponential');

  const NoiseSchedule(this.label, this.apiId);

  final String label;
  final String apiId;
}

/// Canvas orientation shown separately from its resolution tier in settings.
enum ImageAspectRatioPreset {
  portrait('Portrait', '≈2:3'),
  square('Square', '1:1'),
  landscape('Landscape', '≈3:2');

  const ImageAspectRatioPreset(this.label, this.ratioLabel);

  final String label;
  final String ratioLabel;
}

/// NovelAI-compatible size tiers. Large canvases can consume Anlas even when
/// smaller single-image generations are covered by an Opus subscription.
enum ImageResolutionPreset {
  small('Small'),
  normal('Normal'),
  large('Large');

  const ImageResolutionPreset(this.label);

  final String label;
}

class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;

  String get label => '$width × $height';
}

/// Reusable generation values applied consistently to every artist sample.
class GenerationPreset {
  const GenerationPreset({
    required this.model,
    required this.steps,
    required this.guidance,
    required this.guidanceRescale,
    required this.sampler,
    required this.noiseSchedule,
    required this.prompt,
    required this.undesiredContent,
    required this.aspectRatio,
    required this.resolution,
  });

  factory GenerationPreset.defaults() => const GenerationPreset(
        model: NovelAiModel.v45Full,
        steps: 28,
        guidance: 5,
        guidanceRescale: 0,
        sampler: NovelAiSampler.euler,
        noiseSchedule: NoiseSchedule.karras,
        prompt: '1girl, solo, portrait, simple background, looking at viewer',
        undesiredContent:
            'lowres, worst quality, bad quality, jpeg artifacts, watermark, text',
        aspectRatio: ImageAspectRatioPreset.portrait,
        resolution: ImageResolutionPreset.normal,
      );

  final NovelAiModel model;
  final int steps;
  final double guidance;
  final double guidanceRescale;
  final NovelAiSampler sampler;
  final NoiseSchedule noiseSchedule;
  final String prompt;
  final String undesiredContent;
  final ImageAspectRatioPreset aspectRatio;
  final ImageResolutionPreset resolution;

  ImageDimensions get dimensions {
    return switch ((resolution, aspectRatio)) {
      (ImageResolutionPreset.small, ImageAspectRatioPreset.portrait) =>
        const ImageDimensions(512, 768),
      (ImageResolutionPreset.small, ImageAspectRatioPreset.square) =>
        const ImageDimensions(640, 640),
      (ImageResolutionPreset.small, ImageAspectRatioPreset.landscape) =>
        const ImageDimensions(768, 512),
      (ImageResolutionPreset.normal, ImageAspectRatioPreset.portrait) =>
        const ImageDimensions(832, 1216),
      (ImageResolutionPreset.normal, ImageAspectRatioPreset.square) =>
        const ImageDimensions(1024, 1024),
      (ImageResolutionPreset.normal, ImageAspectRatioPreset.landscape) =>
        const ImageDimensions(1216, 832),
      (ImageResolutionPreset.large, ImageAspectRatioPreset.portrait) =>
        const ImageDimensions(1024, 1536),
      (ImageResolutionPreset.large, ImageAspectRatioPreset.square) =>
        const ImageDimensions(1472, 1472),
      (ImageResolutionPreset.large, ImageAspectRatioPreset.landscape) =>
        const ImageDimensions(1536, 1024),
    };
  }

  int get width => dimensions.width;
  int get height => dimensions.height;

  /// Mirrors the documented Opus boundary for a single image. Actual charging
  /// still depends on the account tier, model, and current V5 usage allowance.
  bool get exceedsNormalFreeBoundary =>
      width * height > 1024 * 1024 || steps > 28;

  GenerationPreset copyWith({
    NovelAiModel? model,
    int? steps,
    double? guidance,
    double? guidanceRescale,
    NovelAiSampler? sampler,
    NoiseSchedule? noiseSchedule,
    String? prompt,
    String? undesiredContent,
    ImageAspectRatioPreset? aspectRatio,
    ImageResolutionPreset? resolution,
  }) =>
      GenerationPreset(
        model: model ?? this.model,
        steps: steps ?? this.steps,
        guidance: guidance ?? this.guidance,
        guidanceRescale: guidanceRescale ?? this.guidanceRescale,
        sampler: sampler ?? this.sampler,
        noiseSchedule: noiseSchedule ?? this.noiseSchedule,
        prompt: prompt ?? this.prompt,
        undesiredContent: undesiredContent ?? this.undesiredContent,
        aspectRatio: aspectRatio ?? this.aspectRatio,
        resolution: resolution ?? this.resolution,
      );

  Map<String, Object> toJson() => {
        'model': model.name,
        'steps': steps,
        'guidance': guidance,
        'guidanceRescale': guidanceRescale,
        'sampler': sampler.name,
        'noiseSchedule': noiseSchedule.name,
        'prompt': prompt,
        'undesiredContent': undesiredContent,
        'aspectRatio': aspectRatio.name,
        'resolution': resolution.name,
        // Keeping the resolved dimensions makes each JSON sidecar readable
        // without duplicating the preset lookup table in future tools.
        'width': width,
        'height': height,
      };

  factory GenerationPreset.fromJson(Map<String, dynamic> json) {
    final defaults = GenerationPreset.defaults();
    return GenerationPreset(
      model: _enumByName(NovelAiModel.values, json['model']) ?? defaults.model,
      steps: (json['steps'] as num?)?.toInt() ?? defaults.steps,
      guidance: (json['guidance'] as num?)?.toDouble() ?? defaults.guidance,
      guidanceRescale: (json['guidanceRescale'] as num?)?.toDouble() ??
          defaults.guidanceRescale,
      sampler:
          _enumByName(NovelAiSampler.values, json['sampler']) ?? defaults.sampler,
      noiseSchedule:
          _enumByName(NoiseSchedule.values, json['noiseSchedule']) ??
              defaults.noiseSchedule,
      prompt: json['prompt'] as String? ?? defaults.prompt,
      undesiredContent:
          json['undesiredContent'] as String? ?? defaults.undesiredContent,
      aspectRatio: _enumByName(
            ImageAspectRatioPreset.values,
            json['aspectRatio'],
          ) ??
          _legacyAspectRatio(json) ??
          defaults.aspectRatio,
      resolution: _enumByName(
            ImageResolutionPreset.values,
            json['resolution'],
          ) ??
          _legacyResolution(json) ??
          defaults.resolution,
    );
  }
}

ImageAspectRatioPreset? _legacyAspectRatio(Map<String, dynamic> json) {
  final width = (json['width'] as num?)?.toInt();
  final height = (json['height'] as num?)?.toInt();
  if (width == null || height == null) return null;
  if (width == height) return ImageAspectRatioPreset.square;
  return width < height
      ? ImageAspectRatioPreset.portrait
      : ImageAspectRatioPreset.landscape;
}

ImageResolutionPreset? _legacyResolution(Map<String, dynamic> json) {
  final width = (json['width'] as num?)?.toInt();
  final height = (json['height'] as num?)?.toInt();
  if (width == null || height == null) return null;
  final pixels = width * height;
  if (pixels <= 768 * 512) return ImageResolutionPreset.small;
  if (pixels <= 1024 * 1024) return ImageResolutionPreset.normal;
  return ImageResolutionPreset.large;
}

T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
