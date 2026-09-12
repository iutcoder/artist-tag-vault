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

  /// Numeric emphasis is available from V4 onward.
  bool get supportsNumericalEmphasis => this != animeV3;

  /// Negative numeric emphasis is supported by V4.5 and later models.
  bool get supportsNegativeNumericalEmphasis =>
      isV5 || this == v45Full || this == v45Curated;
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

/// Model-aware automatic quality suffixes shown by NovelAI's image UI.
enum QualityTagPreset {
  off('Off'),
  light('Light'),
  standard('Standard');

  const QualityTagPreset(this.label);
  final String label;
}

/// Automatic text prepended to the user's custom Undesired Content.
enum UndesiredContentPreset {
  heavy('Heavy'),
  light('Light'),
  furryFocus('Furry Focus'),
  humanFocus('Human Focus'),
  none('None');

  const UndesiredContentPreset(this.label);
  final String label;

  int apiCodeFor(NovelAiModel model) {
    if (this == heavy) return 0;
    if (this == light) return 1;
    if (this == furryFocus) return 2;
    if (this == humanFocus) return 3;
    return model == NovelAiModel.animeV3 ||
            model == NovelAiModel.v4Full ||
            model == NovelAiModel.v4Curated
        ? 2
        : 4;
  }
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
  static const int minimumSteps = 1;
  static const int maximumSteps = 50;
  static const double minimumGuidance = 0;
  static const double maximumGuidance = 10;
  static const double minimumGuidanceRescale = 0;
  static const double maximumGuidanceRescale = 1;

  const GenerationPreset({
    required this.model,
    required this.steps,
    required this.guidance,
    required this.guidanceRescale,
    required this.sampler,
    required this.noiseSchedule,
    required this.qualityTagPreset,
    required this.undesiredContentPreset,
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
    qualityTagPreset: QualityTagPreset.standard,
    undesiredContentPreset: UndesiredContentPreset.heavy,
    prompt: '1girl, solo, portrait, simple background, looking at viewer',
    undesiredContent: '',
    aspectRatio: ImageAspectRatioPreset.portrait,
    resolution: ImageResolutionPreset.normal,
  );

  final NovelAiModel model;
  final int steps;
  final double guidance;
  final double guidanceRescale;
  final NovelAiSampler sampler;
  final NoiseSchedule noiseSchedule;
  final QualityTagPreset qualityTagPreset;
  final UndesiredContentPreset undesiredContentPreset;
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

  List<QualityTagPreset> get availableQualityTagPresets =>
      _availableQualityPresets(model);

  List<UndesiredContentPreset> get availableUndesiredContentPresets =>
      _availableUndesiredPresets(model);

  String composePrompt(String basePrompt) {
    final base = basePrompt.trim();
    final tags = _qualityTags(model, qualityTagPreset);
    if (tags.isEmpty) return base;
    return base.isEmpty ? tags : '$base, $tags';
  }

  String get composedUndesiredContent {
    final automatic = _undesiredTags(model, undesiredContentPreset);
    final custom = undesiredContent.trim();
    if (automatic.isEmpty) return custom;
    return custom.isEmpty ? automatic : '$automatic, $custom';
  }

  GenerationPreset copyWith({
    NovelAiModel? model,
    int? steps,
    double? guidance,
    double? guidanceRescale,
    NovelAiSampler? sampler,
    NoiseSchedule? noiseSchedule,
    QualityTagPreset? qualityTagPreset,
    UndesiredContentPreset? undesiredContentPreset,
    String? prompt,
    String? undesiredContent,
    ImageAspectRatioPreset? aspectRatio,
    ImageResolutionPreset? resolution,
  }) => GenerationPreset(
    model: model ?? this.model,
    steps: steps ?? this.steps,
    guidance: guidance ?? this.guidance,
    guidanceRescale: guidanceRescale ?? this.guidanceRescale,
    sampler: sampler ?? this.sampler,
    noiseSchedule: noiseSchedule ?? this.noiseSchedule,
    qualityTagPreset: qualityTagPreset ?? this.qualityTagPreset,
    undesiredContentPreset:
        undesiredContentPreset ?? this.undesiredContentPreset,
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
    'qualityTagPreset': qualityTagPreset.name,
    'undesiredContentPreset': undesiredContentPreset.name,
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
    final model = _modelFromJson(json['model']) ?? defaults.model;
    final loadedQuality =
        _enumByName(QualityTagPreset.values, json['qualityTagPreset']) ??
        QualityTagPreset.off;
    final loadedUndesired =
        _enumByName(
          UndesiredContentPreset.values,
          json['undesiredContentPreset'],
        ) ??
        UndesiredContentPreset.none;
    final steps = (json['steps'] as num?)?.toInt() ?? defaults.steps;
    final guidance =
        (json['guidance'] as num?)?.toDouble() ?? defaults.guidance;
    final guidanceRescale =
        (json['guidanceRescale'] as num?)?.toDouble() ??
        defaults.guidanceRescale;
    return GenerationPreset(
      model: model,
      // Clamp older preferences as they are loaded so invalid values cannot
      // bypass the current UI limits.
      steps: steps.clamp(minimumSteps, maximumSteps).toInt(),
      guidance: guidance.clamp(minimumGuidance, maximumGuidance).toDouble(),
      guidanceRescale: guidanceRescale
          .clamp(minimumGuidanceRescale, maximumGuidanceRescale)
          .toDouble(),
      sampler: _samplerFromJson(json['sampler']) ?? defaults.sampler,
      noiseSchedule:
          _scheduleFromJson(json['noiseSchedule'] ?? json['noise_schedule']) ??
          defaults.noiseSchedule,
      // Older saved presets already contained their effective prompt text.
      // Defaulting new selectors to Off/None preserves those results exactly.
      qualityTagPreset: _availableQualityPresets(model).contains(loadedQuality)
          ? loadedQuality
          : QualityTagPreset.standard,
      undesiredContentPreset:
          _availableUndesiredPresets(model).contains(loadedUndesired)
          ? loadedUndesired
          : UndesiredContentPreset.heavy,
      prompt: json['prompt'] as String? ?? defaults.prompt,
      undesiredContent:
          json['undesiredContent'] as String? ?? defaults.undesiredContent,
      aspectRatio:
          _enumByName(ImageAspectRatioPreset.values, json['aspectRatio']) ??
          _legacyAspectRatio(json) ??
          defaults.aspectRatio,
      resolution:
          _enumByName(ImageResolutionPreset.values, json['resolution']) ??
          _legacyResolution(json) ??
          defaults.resolution,
    );
  }
}

List<QualityTagPreset> _availableQualityPresets(NovelAiModel model) =>
    model.isV5
    ? QualityTagPreset.values
    : const [QualityTagPreset.off, QualityTagPreset.standard];

List<UndesiredContentPreset> _availableUndesiredPresets(NovelAiModel model) {
  return switch (model) {
    NovelAiModel.v5Full ||
    NovelAiModel.v5Curated ||
    NovelAiModel.v45Full => UndesiredContentPreset.values,
    NovelAiModel.v45Curated => const [
      UndesiredContentPreset.heavy,
      UndesiredContentPreset.light,
      UndesiredContentPreset.humanFocus,
      UndesiredContentPreset.none,
    ],
    NovelAiModel.v4Full || NovelAiModel.v4Curated => const [
      UndesiredContentPreset.heavy,
      UndesiredContentPreset.light,
      UndesiredContentPreset.none,
    ],
    NovelAiModel.animeV3 => const [
      UndesiredContentPreset.heavy,
      UndesiredContentPreset.light,
      UndesiredContentPreset.humanFocus,
      UndesiredContentPreset.none,
    ],
  };
}

String _qualityTags(NovelAiModel model, QualityTagPreset preset) {
  if (preset == QualityTagPreset.off) return '';
  return switch (model) {
    NovelAiModel.v5Full || NovelAiModel.v5Curated =>
      preset == QualityTagPreset.light
          ? 'very aesthetic, amazing quality, no text'
          : 'very aesthetic, masterpiece, no text',
    NovelAiModel.v45Full => 'location, very aesthetic, masterpiece, no text',
    NovelAiModel.v45Curated =>
      'location, masterpiece, no text, -0.8:: feet ::, rating:general',
    NovelAiModel.v4Full => 'no text, best quality, very aesthetic, absurdres',
    NovelAiModel.v4Curated =>
      'rating:general, amazing quality, very aesthetic, absurdres',
    NovelAiModel.animeV3 =>
      'best quality, amazing quality, very aesthetic, absurdres',
  };
}

String _undesiredTags(NovelAiModel model, UndesiredContentPreset preset) {
  if (preset == UndesiredContentPreset.none) return '';

  const modernHeavy =
      'lowres, artistic error, film grain, scan artifacts, worst quality, '
      'bad quality, jpeg artifacts, very displeasing, chromatic aberration, '
      'dithering, halftone, screentone, multiple views, logo, too many '
      'watermarks, negative space, blank page';
  const modernHuman =
      '$modernHeavy, @_@, mismatched pupils, glowing eyes, bad anatomy';
  const furryFocus =
      '{worst quality}, distracting watermark, unfinished, bad quality, '
      '{widescreen}, upscale, {sequence}, {{grandfathered content}}, blurred '
      'foreground, chromatic aberration, sketch, everyone, [sketch background], '
      'simple, [flat colors], ych (character), outline, multiple scenes, '
      '[[horror (theme)]], comic';

  return switch ((model, preset)) {
    (_, UndesiredContentPreset.none) => '',
    (
      NovelAiModel.v5Full || NovelAiModel.v5Curated,
      UndesiredContentPreset.heavy,
    ) =>
      modernHeavy,
    (
      NovelAiModel.v5Full || NovelAiModel.v5Curated,
      UndesiredContentPreset.light,
    ) =>
      'lowres, bad hands, bad anatomy, artistic error, sepia, white haze, '
          'worst quality, very displeasing, jpeg artifacts, 0:: ai-generated ::',
    (
      NovelAiModel.v5Full || NovelAiModel.v5Curated,
      UndesiredContentPreset.furryFocus,
    ) =>
      furryFocus,
    (
      NovelAiModel.v5Full || NovelAiModel.v5Curated,
      UndesiredContentPreset.humanFocus,
    ) =>
      modernHuman,
    (NovelAiModel.v45Full, UndesiredContentPreset.heavy) => modernHeavy,
    (NovelAiModel.v45Full, UndesiredContentPreset.light) =>
      'lowres, artistic error, scan artifacts, worst quality, bad quality, '
          'jpeg artifacts, multiple views, very displeasing, too many watermarks, '
          'negative space, blank page',
    (NovelAiModel.v45Full, UndesiredContentPreset.furryFocus) => furryFocus,
    (NovelAiModel.v45Full, UndesiredContentPreset.humanFocus) => modernHuman,
    (NovelAiModel.v45Curated, UndesiredContentPreset.heavy) =>
      'blurry, lowres, upscaled, artistic error, film grain, scan artifacts, '
          'worst quality, bad quality, jpeg artifacts, very displeasing, chromatic '
          'aberration, halftone, multiple views, logo, too many watermarks, '
          'negative space, blank page',
    (NovelAiModel.v45Curated, UndesiredContentPreset.light) =>
      'blurry, lowres, upscaled, artistic error, scan artifacts, jpeg artifacts, '
          'logo, too many watermarks, negative space, blank page',
    (NovelAiModel.v45Curated, UndesiredContentPreset.humanFocus) =>
      'blurry, lowres, upscaled, artistic error, film grain, scan artifacts, '
          'bad anatomy, bad hands, worst quality, bad quality, jpeg artifacts, '
          'very displeasing, chromatic aberration, halftone, multiple views, logo, '
          'too many watermarks, @_@, mismatched pupils, glowing eyes, negative '
          'space, blank page',
    (NovelAiModel.v4Full, UndesiredContentPreset.heavy) =>
      'blurry, lowres, error, film grain, scan artifacts, worst quality, bad '
          'quality, jpeg artifacts, very displeasing, chromatic aberration, '
          'multiple views, logo, too many watermarks',
    (NovelAiModel.v4Full, UndesiredContentPreset.light) =>
      'blurry, lowres, error, worst quality, bad quality, jpeg artifacts, '
          'very displeasing',
    (NovelAiModel.v4Curated, UndesiredContentPreset.heavy) =>
      'blurry, lowres, error, film grain, scan artifacts, worst quality, bad '
          'quality, jpeg artifacts, very displeasing, chromatic aberration, logo, '
          'dated, signature, multiple views, gigantic breasts',
    (NovelAiModel.v4Curated, UndesiredContentPreset.light) =>
      'blurry, lowres, error, worst quality, bad quality, jpeg artifacts, '
          'very displeasing, logo, dated, signature',
    (NovelAiModel.animeV3, UndesiredContentPreset.heavy) =>
      'lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg '
          'artifacts, bad quality, watermark, unfinished, displeasing, chromatic '
          'aberration, signature, extra digits, artistic error, username, scan, '
          '[abstract]',
    (NovelAiModel.animeV3, UndesiredContentPreset.light) => 'lowres, jpeg artifacts, worst quality, watermark, blurry, very displeasing',
    (NovelAiModel.animeV3, UndesiredContentPreset.humanFocus) =>
      'lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg '
          'artifacts, bad quality, watermark, unfinished, displeasing, chromatic '
          'aberration, signature, extra digits, artistic error, username, scan, '
          '[abstract], bad anatomy, bad hands, @_@, mismatched pupils, '
          'heart-shaped pupils, glowing eyes',
    _ => '',
  };
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

NovelAiModel? _modelFromJson(Object? value) {
  for (final model in NovelAiModel.values) {
    if (model.name == value || model.apiId == value) return model;
  }
  return null;
}

NovelAiSampler? _samplerFromJson(Object? value) {
  for (final sampler in NovelAiSampler.values) {
    if (sampler.name == value || sampler.apiId == value) return sampler;
  }
  return null;
}

NoiseSchedule? _scheduleFromJson(Object? value) {
  for (final schedule in NoiseSchedule.values) {
    if (schedule.name == value || schedule.apiId == value) return schedule;
  }
  return null;
}
