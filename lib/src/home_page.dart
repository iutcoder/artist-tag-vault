import 'dart:io';

import 'package:artist_tag_vault/src/models/app_settings.dart';
import 'package:artist_tag_vault/src/services/novelai_api.dart';
import 'package:artist_tag_vault/src/services/prompt_composer.dart';
import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:artist_tag_vault/src/services/settings_store.dart';
import 'package:artist_tag_vault/src/settings_dialog.dart';
import 'package:artist_tag_vault/src/widgets/glass_panel.dart';
import 'package:flutter/material.dart';

/// Main artist entry, generation action, and latest-sample preview.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _artistController = TextEditingController();
  final _settingsStore = SettingsStore();
  final _api = NovelAiApi();
  final _sampleStorage = SampleStorage();

  AppSettings _settings = AppSettings.defaults();
  File? _previewFile;
  String _status = 'Enter an artist name to create a standardized sample.';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final loaded = await _settingsStore.load();
      if (mounted) setState(() => _settings = loaded);
    } on SettingsStoreException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _openSettings() async {
    final updated = await showDialog<AppSettings>(
      context: context,
      builder: (context) => SettingsDialog(
        initialSettings: _settings,
        api: _api,
      ),
    );
    if (updated == null) return;

    try {
      await _settingsStore.save(updated);
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _status = 'Preset saved.';
      });
    } on SettingsStoreException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _generate() async {
    final artist = _artistController.text.trim();
    if (artist.isEmpty) {
      _showError('아티스트 이름을 입력해 주세요.');
      return;
    }
    if (_settings.apiToken.isEmpty) {
      _showError('설정에서 NovelAI API 토큰을 먼저 저장해 주세요.');
      return;
    }

    final prompt = PromptComposer.compose(
      artist: artist,
      presetPrompt: _settings.preset.prompt,
    );
    setState(() {
      _busy = true;
      _status = 'Generating artist:$artist…';
    });

    try {
      final generated = await _api.generate(
        token: _settings.apiToken,
        prompt: prompt,
        preset: _settings.preset,
      );
      final file = await _sampleStorage.save(
        bytes: generated.bytes,
        artist: artist,
        composedPrompt: prompt,
        seed: generated.seed,
        preset: _settings.preset,
      );
      if (!mounted) return;
      setState(() {
        _previewFile = file;
        _status = 'Saved · ${file.path}';
      });
    } on Exception catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFolder() async {
    try {
      await _sampleStorage.openRootDirectory();
    } on Exception catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  void _showError(String message) {
    setState(() => _status = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AmbientBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 860;
                        return compact
                            ? Column(
                                children: [
                                  SizedBox(height: 390, child: _buildControls()),
                                  const SizedBox(height: 18),
                                  Expanded(child: _buildPreview()),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(width: 370, child: _buildControls()),
                                  const SizedBox(width: 22),
                                  Expanded(child: _buildPreview()),
                                ],
                              );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFF8B7CFF), Color(0xFF51D4CB)],
            ),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
        const SizedBox(width: 13),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Artist Tag Vault',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              'NovelAI artist-tag sample catalog',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
        IconButton.filledTonal(
          tooltip: 'Open saved samples',
          onPressed: _openFolder,
          icon: const Icon(Icons.folder_open_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Settings',
          onPressed: _openSettings,
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CREATE SAMPLE',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _artistController,
            enabled: !_busy,
            onSubmitted: (_) => _generate(),
            decoration: const InputDecoration(
              labelText: 'Artist name',
              prefixText: 'artist:',
              hintText: 'artist name',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 17),
            ),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_busy ? 'Generating…' : 'Generate & Save'),
          ),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 14),
          _PresetLine('Model', _settings.preset.model.label),
          _PresetLine('Steps', _settings.preset.steps.toString()),
          _PresetLine('Guidance', _settings.preset.guidance.toString()),
          _PresetLine('Sampler', _settings.preset.sampler.label),
          _PresetLine('Schedule', _settings.preset.noiseSchedule.label),
          const Spacer(),
          Text(
            _status,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _previewFile == null
            ? const _EmptyPreview()
            : Image.file(
                _previewFile!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}

class _PresetLine extends StatelessWidget {
  const _PresetLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: const TextStyle(color: Colors.white38)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.18),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 58, color: Colors.white24),
            SizedBox(height: 13),
            Text('Generated image preview',
                style: TextStyle(color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.75, -0.9),
          radius: 1.3,
          colors: [Color(0x553B2B9D), Color(0xFF090B16)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}
