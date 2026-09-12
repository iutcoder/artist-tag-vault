import 'package:artist_tag_vault/src/models/app_settings.dart';
import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:artist_tag_vault/src/services/novelai_api.dart';
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
  late final TextEditingController _steps;
  late final TextEditingController _guidance;
  late final TextEditingController _rescale;
  late final TextEditingController _prompt;
  late final TextEditingController _undesired;
  late NovelAiModel _model;
  late NovelAiSampler _sampler;
  late NoiseSchedule _noiseSchedule;
  bool _testing = false;
  TokenTestResult? _testResult;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    _token = TextEditingController(text: settings.apiToken);
    _steps = TextEditingController(text: settings.preset.steps.toString());
    _guidance = TextEditingController(text: settings.preset.guidance.toString());
    _rescale =
        TextEditingController(text: settings.preset.guidanceRescale.toString());
    _prompt = TextEditingController(text: settings.preset.prompt);
    _undesired = TextEditingController(text: settings.preset.undesiredContent);
    _model = settings.preset.model;
    _sampler = settings.preset.sampler;
    _noiseSchedule = settings.preset.noiseSchedule;
  }

  @override
  void dispose() {
    _token.dispose();
    _steps.dispose();
    _guidance.dispose();
    _rescale.dispose();
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
    final steps = int.tryParse(_steps.text);
    final guidance = double.tryParse(_guidance.text);
    final rescale = double.tryParse(_rescale.text);
    if (steps == null || steps < 1 || steps > 50 || guidance == null ||
        rescale == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('숫자 설정을 확인해 주세요. Steps는 1–50입니다.')),
      );
      return;
    }

    Navigator.of(context).pop(
      AppSettings(
        apiToken: _token.text.trim(),
        preset: widget.initialSettings.preset.copyWith(
          model: _model,
          steps: steps,
          guidance: guidance,
          guidanceRescale: rescale,
          sampler: _sampler,
          noiseSchedule: _noiseSchedule,
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
                  Expanded(child: _numberField(_steps, 'Steps')),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField(_guidance, 'Prompt guidance')),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField(_rescale, 'Guidance rescale')),
                ],
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

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }
}
