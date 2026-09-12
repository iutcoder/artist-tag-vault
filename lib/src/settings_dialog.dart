import 'package:artist_tag_vault/src/models/app_settings.dart';
import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:artist_tag_vault/src/services/novelai_api.dart';
import 'package:artist_tag_vault/src/widgets/numeric_stepper_field.dart';
import 'package:flutter/material.dart';

/// Edits a complete preset and tests the token before the caller persists it.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    required this.initialSettings,
    required this.api,
    super.key,
  });

  final AppSettings initialSettings;
  final NovelAiApi api;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _token;
  late final TextEditingController _prompt;
  late final TextEditingController _undesired;
  late int _steps;
  late double _guidance;
  late double _rescale;
  late NovelAiModel _model;
  late NovelAiSampler _sampler;
  late NoiseSchedule _noiseSchedule;
  late ImageAspectRatioPreset _aspectRatio;
  late ImageResolutionPreset _resolution;
  bool _testing = false;
  TokenTestResult? _testResult;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    _token = TextEditingController(text: settings.apiToken);
    _steps = settings.preset.steps;
    _guidance = settings.preset.guidance;
    _rescale = settings.preset.guidanceRescale;
    _prompt = TextEditingController(text: settings.preset.prompt);
    _undesired = TextEditingController(text: settings.preset.undesiredContent);
    _model = settings.preset.model;
    _sampler = settings.preset.sampler;
    _noiseSchedule = settings.preset.noiseSchedule;
    _aspectRatio = settings.preset.aspectRatio;
    _resolution = settings.preset.resolution;
  }

  @override
  void dispose() {
    _token.dispose();
    _prompt.dispose();
    _undesired.dispose();
    super.dispose();
  }

  Future<void> _testToken() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await widget.api.testToken(_token.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  void _save() {
    Navigator.of(context).pop(
      AppSettings(
        apiToken: _token.text.trim(),
        preset: widget.initialSettings.preset.copyWith(
          model: _model,
          steps: _steps,
          guidance: _guidance,
          guidanceRescale: _rescale,
          sampler: _sampler,
          noiseSchedule: _noiseSchedule,
          aspectRatio: _aspectRatio,
          resolution: _resolution,
          prompt: _prompt.text.trim(),
          undesiredContent: _undesired.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _testResult?.success == true
        ? Colors.greenAccent
        : _testResult == null
            ? Colors.white54
            : Colors.redAccent;

    return AlertDialog(
      title: const Text('Generation preset'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _token,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'NovelAI API token',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _testing ? null : _testToken,
                    icon: _testing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cable_rounded),
                    label: const Text('Test'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _testResult?.success == true
                        ? Icons.check_circle_rounded
                        : _testResult == null
                            ? Icons.info_outline_rounded
                            : Icons.error_rounded,
                    size: 17,
                    color: statusColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _testResult?.message ??
                          '토큰은 Keychain 또는 Windows Credential Manager에 저장됩니다.',
                      style: TextStyle(color: statusColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<NovelAiModel>(
                initialValue: _model,
                decoration: const InputDecoration(labelText: 'Version'),
                items: NovelAiModel.values
                    .map((model) => DropdownMenuItem(
                          value: model,
                          child: Text(model.label),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _model = value ?? _model),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ImageAspectRatioPreset>(
                      initialValue: _aspectRatio,
                      decoration: const InputDecoration(
                        labelText: 'Image ratio',
                      ),
                      items: ImageAspectRatioPreset.values
                          .map((ratio) => DropdownMenuItem(
                                value: ratio,
                                child: Text(
                                  '${ratio.label} · ${ratio.ratioLabel}',
                                ),
                              ))
                          .toList(),
                      onChanged: (value) => setState(
                        () => _aspectRatio = value ?? _aspectRatio,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<ImageResolutionPreset>(
                      initialValue: _resolution,
                      decoration:
                          const InputDecoration(labelText: 'Resolution'),
                      items: ImageResolutionPreset.values
                          .map((resolution) => DropdownMenuItem(
                                value: resolution,
                                child: Text(resolution.label),
                              ))
                          .toList(),
                      onChanged: (value) => setState(
                        () => _resolution = value ?? _resolution,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Canvas · ${_selectedDimensions.label}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              _SliderSettingRow(
                label: 'Steps',
                value: _steps.toDouble(),
                minimum: GenerationPreset.minimumSteps.toDouble(),
                maximum: GenerationPreset.maximumSteps.toDouble(),
                divisions: GenerationPreset.maximumSteps -
                    GenerationPreset.minimumSteps,
                step: 1,
                decimalPlaces: 0,
                onChanged: (value) => setState(() => _steps = value.round()),
              ),
              _SliderSettingRow(
                label: 'Prompt guidance',
                value: _guidance,
                minimum: GenerationPreset.minimumGuidance,
                maximum: GenerationPreset.maximumGuidance,
                divisions: 100,
                step: 0.1,
                decimalPlaces: 2,
                onChanged: (value) => setState(() => _guidance = value),
              ),
              _SliderSettingRow(
                label: 'Guidance rescale',
                value: _rescale,
                minimum: GenerationPreset.minimumGuidanceRescale,
                maximum: GenerationPreset.maximumGuidanceRescale,
                divisions: 100,
                step: 0.01,
                decimalPlaces: 2,
                onChanged: (value) => setState(() => _rescale = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<NovelAiSampler>(
                      initialValue: _sampler,
                      decoration: const InputDecoration(labelText: 'Sampler'),
                      items: NovelAiSampler.values
                          .map((sampler) => DropdownMenuItem(
                                value: sampler,
                                child: Text(sampler.label),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _sampler = value ?? _sampler),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<NoiseSchedule>(
                      initialValue: _noiseSchedule,
                      decoration:
                          const InputDecoration(labelText: 'Noise schedule'),
                      items: NoiseSchedule.values
                          .map((schedule) => DropdownMenuItem(
                                value: schedule,
                                child: Text(schedule.label),
                              ))
                          .toList(),
                      onChanged: (value) => setState(
                        () => _noiseSchedule = value ?? _noiseSchedule,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prompt,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Preset prompt'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _undesired,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Undesired content'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  ImageDimensions get _selectedDimensions => GenerationPreset.defaults()
      .copyWith(aspectRatio: _aspectRatio, resolution: _resolution)
      .dimensions;
}

/// Keeps a precise spin box and a quick slider in sync on one readable row.
class _SliderSettingRow extends StatelessWidget {
  const _SliderSettingRow({
    required this.label,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.step,
    required this.decimalPlaces,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double minimum;
  final double maximum;
  final int divisions;
  final double step;
  final int decimalPlaces;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 126,
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(minimum, maximum).toDouble(),
              min: minimum,
              max: maximum,
              divisions: divisions,
              label: value.toStringAsFixed(decimalPlaces),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 112,
            child: NumericStepperField(
              value: value,
              minimum: minimum,
              maximum: maximum,
              step: step,
              decimalPlaces: decimalPlaces,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
