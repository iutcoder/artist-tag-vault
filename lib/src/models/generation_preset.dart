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
    required this.width,
    required this.height,
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
        width: 832,
        height: 1216,
      );

  final NovelAiModel model;
  final int steps;
  final double guidance;
  final double guidanceRescale;
  final NovelAiSampler sampler;
  final NoiseSchedule noiseSchedule;
  final String prompt;
  final String undesiredContent;
  final int width;
  final int height;

  GenerationPreset copyWith({
    NovelAiModel? model,
    int? steps,
    double? guidance,
    double? guidanceRescale,
    NovelAiSampler? sampler,
    NoiseSchedule? noiseSchedule,
    String? prompt,
    String? undesiredContent,
    int? width,
    int? height,
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
        width: width ?? this.width,
        height: height ?? this.height,
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
      width: (json['width'] as num?)?.toInt() ?? defaults.width,
      height: (json['height'] as num?)?.toInt() ?? defaults.height,
    );
  }
}

T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
