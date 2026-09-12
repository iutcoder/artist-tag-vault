import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:artist_tag_vault/src/models/account_usage.dart';
import 'package:artist_tag_vault/src/models/app_settings.dart';
import 'package:artist_tag_vault/src/services/novelai_api.dart';
import 'package:artist_tag_vault/src/services/prompt_composer.dart';
import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:artist_tag_vault/src/services/settings_store.dart';
import 'package:artist_tag_vault/src/settings_dialog.dart';
import 'package:artist_tag_vault/src/widgets/glass_panel.dart';
import 'package:artist_tag_vault/src/widgets/numeric_stepper_field.dart';
import 'package:flutter/material.dart';

/// Main artist entry, generation action, and latest-sample preview.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _maximumSeed = 0xffffffff;

  final _artistController = TextEditingController();
  final _settingsStore = SettingsStore();
  final _api = NovelAiApi();
  final _sampleStorage = SampleStorage();
  final _random = Random.secure();

  AppSettings _settings = AppSettings.defaults();
  File? _previewFile;
  String _status = 'Enter an artist name to create a standardized sample.';
  bool _busy = false;
  bool _previewExpanded = true;
  AccountUsage? _accountUsage;
  bool _usageLoading = false;
  String? _usageError;
  late int _seed;
  bool _seedLocked = false;
  double _artistWeight = 1;

  @override
  void initState() {
    super.initState();
    _seed = _createRandomSeed();
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
      if (!mounted) return;
      setState(() => _settings = loaded);
      if (loaded.apiToken.isNotEmpty) unawaited(_refreshUsage());
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
      unawaited(_refreshUsage());
    } on SettingsStoreException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _generate() async {
    // Generating always reveals the preview, even when the user previously
    // collapsed it to make more room for the controls.
    if (!_previewExpanded) {
      setState(() => _previewExpanded = true);
    }

    final artist = _artistController.text.trim();
    if (artist.isEmpty) {
      _showError('아티스트 이름을 입력해 주세요.');
      return;
    }
    if (_settings.apiToken.isEmpty) {
      _showError('설정에서 NovelAI API 토큰을 먼저 저장해 주세요.');
      return;
    }

    final model = _settings.preset.model;
    if ((_artistWeight - 1).abs() >= 0.000001 &&
        !model.supportsNumericalEmphasis) {
      _showError('이 모델은 숫자 가중치를 지원하지 않습니다. 가중치를 1.00으로 설정해 주세요.');
      return;
    }
    if (_artistWeight < 0 && !model.supportsNegativeNumericalEmphasis) {
      _showError('음수 가중치는 NovelAI Diffusion V4.5 이상에서 사용할 수 있습니다.');
      return;
    }

    // An unlocked seed advances immediately before each request. A locked
    // seed remains unchanged so artists can be compared under the same noise.
    final requestSeed = _seedLocked ? _seed : _createRandomSeed();

    final prompt = PromptComposer.compose(
      artist: artist,
      presetPrompt: _settings.preset.prompt,
      artistWeight: _artistWeight,
    );
    setState(() {
      _busy = true;
      _seed = requestSeed;
      _status = 'Generating artist:$artist…';
    });

    try {
      final generated = await _api.generate(
        token: _settings.apiToken,
        prompt: prompt,
        preset: _settings.preset,
        seed: requestSeed,
      );
      final file = await _sampleStorage.save(
        bytes: generated.bytes,
        artist: artist,
        composedPrompt: prompt,
        seed: generated.seed,
        artistWeight: _artistWeight,
        preset: _settings.preset,
      );
      if (!mounted) return;
      setState(() {
        _previewFile = file;
        _seed = generated.seed;
        _status = 'Saved · ${file.path}';
      });
      unawaited(_refreshUsage());
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

  Future<void> _refreshUsage() async {
    if (_settings.apiToken.isEmpty) {
      if (mounted) {
        setState(() {
          _accountUsage = null;
          _usageError = 'Save an API token to view usage.';
        });
      }
      return;
    }

    setState(() {
      _usageLoading = true;
      _usageError = null;
    });
    try {
      final usage = await _api.fetchAccountUsage(_settings.apiToken);
      if (!mounted) return;
      setState(() => _accountUsage = usage);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _accountUsage = null;
        _usageError = error.toString();
      });
    } finally {
      if (mounted) setState(() => _usageLoading = false);
    }
  }

  void _showError(String message) {
    setState(() => _status = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int _createRandomSeed() {
    // Joining two 16-bit values covers NovelAI's unsigned 32-bit seed range
    // without relying on a platform-specific nextInt upper-bound behavior.
    return (_random.nextInt(1 << 16) << 16) | _random.nextInt(1 << 16);
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
                            ? _buildCompactLayout()
                            : _buildWideLayout();
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

  /// Uses vertical folding for narrow windows such as the macOS screenshot.
  Widget _buildCompactLayout() {
    if (!_previewExpanded) {
      return Column(
        children: [
          Expanded(child: _buildControls()),
          const SizedBox(height: 14),
          SizedBox(height: 64, child: _buildPreview(compact: true)),
        ],
      );
    }

    return Column(
      children: [
        Flexible(flex: 5, child: _buildControls()),
        const SizedBox(height: 14),
        Flexible(flex: 4, child: _buildPreview(compact: true)),
      ],
    );
  }

  /// On wide windows the closed preview becomes a slim rail on the right.
  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 370, child: _buildControls()),
        const SizedBox(width: 22),
        if (_previewExpanded)
          Expanded(child: _buildPreview(compact: false))
        else
          SizedBox(width: 64, child: _buildPreview(compact: false)),
      ],
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
      // A short desktop window must scroll instead of producing a RenderFlex
      // overflow stripe at the bottom of the preset summary.
      child: SingleChildScrollView(
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
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: NumericStepperField(
                  value: _seed.toDouble(),
                  minimum: 0,
                  maximum: _maximumSeed.toDouble(),
                  step: 1,
                  decimalPlaces: 0,
                  enabled: !_busy,
                  labelText: 'Seed',
                  onChanged: (value) =>
                      setState(() => _seed = value.round()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _seedLocked ? 'Unlock seed' : 'Lock seed',
                style: _seedLocked
                    ? IconButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      )
                    : null,
                onPressed: _busy
                    ? null
                    : () => setState(() => _seedLocked = !_seedLocked),
                icon: Icon(
                  _seedLocked
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          NumericStepperField(
            value: _artistWeight,
            minimum: -5,
            maximum: 5,
            step: 0.01,
            decimalPlaces: 2,
            enabled: !_busy,
            labelText: 'Artist weight  ·  −5.00 to +5.00',
            onChanged: (value) => setState(() => _artistWeight = value),
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
          const SizedBox(height: 12),
          _UsageCard(
            usage: _accountUsage,
            loading: _usageLoading,
            error: _usageError,
            showV5Allowance: _settings.preset.model.isV5,
            mayConsumeAnlas: _settings.preset.exceedsNormalFreeBoundary,
            onRefresh: _usageLoading ? null : _refreshUsage,
          ),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 14),
          _PresetLine('Model', _settings.preset.model.label),
          _PresetLine('Steps', _settings.preset.steps.toString()),
          _PresetLine('Guidance', _settings.preset.guidance.toString()),
          _PresetLine('Sampler', _settings.preset.sampler.label),
          _PresetLine('Schedule', _settings.preset.noiseSchedule.label),
          _PresetLine(
            'Canvas',
            '${_settings.preset.aspectRatio.ratioLabel} · '
                '${_settings.preset.dimensions.label}',
          ),
          const SizedBox(height: 20),
          Text(
            _status,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview({required bool compact}) {
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: _previewExpanded
          ? Column(
              children: [
                _PreviewHeader(
                  compact: compact,
                  expanded: true,
                  onPressed: _togglePreview,
                ),
                const SizedBox(height: 8),
                Expanded(
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
                ),
              ],
            )
          : _PreviewHeader(
              compact: compact,
              expanded: false,
              onPressed: _togglePreview,
            ),
    );
  }

  void _togglePreview() {
    setState(() => _previewExpanded = !_previewExpanded);
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.usage,
    required this.loading,
    required this.error,
    required this.showV5Allowance,
    required this.mayConsumeAnlas,
    required this.onRefresh,
  });

  final AccountUsage? usage;
  final bool loading;
  final String? error;
  final bool showV5Allowance;
  final bool mayConsumeAnlas;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  size: 18,
                  color: Color(0xFF68D9D0),
                ),
                const SizedBox(width: 7),
                const Text(
                  'ACCOUNT USAGE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Colors.white60,
                  ),
                ),
                const Spacer(),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Refresh usage',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
              ],
            ),
            if (usage != null) ...[
              Text(
                '${usage!.totalAnlas} Anlas · ${usage!.tierLabel}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                'Subscription ${usage!.subscriptionAnlas}  ·  '
                'Paid ${usage!.paidAnlas}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              if (showV5Allowance) ...[
                const SizedBox(height: 11),
                _V5Allowance(usage: usage!),
              ],
            ] else
              Text(
                error ?? 'Usage has not been loaded.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: error == null ? Colors.white54 : Colors.redAccent,
                  fontSize: 11,
                ),
              ),
            const SizedBox(height: 9),
            Text(
              mayConsumeAnlas
                  ? 'Large canvas or more than 28 steps may consume Anlas.'
                  : showV5Allowance
                      ? 'V5 uses its allowance first when generation is eligible.'
                      : 'Charge depends on your subscription conditions.',
              style: TextStyle(
                color: mayConsumeAnlas ? Colors.amberAccent : Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _V5Allowance extends StatelessWidget {
  const _V5Allowance({required this.usage});

  final AccountUsage usage;

  @override
  Widget build(BuildContext context) {
    final percent = usage.v5Percent;
    if (percent == null) {
      return const Text(
        'V5 allowance is not available for this account.',
        style: TextStyle(color: Colors.white54, fontSize: 11),
      );
    }

    final normalized = (percent.clamp(0, 100) / 100).toDouble();
    final unavailable = usage.v5Unavailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('V5 allowance', style: TextStyle(fontSize: 11)),
            const Spacer(),
            Text(
              '$percent%',
              style: TextStyle(
                color: unavailable ? Colors.redAccent : Colors.greenAccent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: normalized,
          minHeight: 6,
          borderRadius: BorderRadius.circular(99),
          color: unavailable ? Colors.redAccent : const Color(0xFF68D9D0),
          backgroundColor: Colors.white10,
        ),
        const SizedBox(height: 5),
        Text(
          unavailable
              ? 'Allowance depleted · Anlas will be used.'
              : _nextRefillLabel(usage.secondsUntilNextPercent),
          style: TextStyle(
            color: unavailable ? Colors.redAccent : Colors.white38,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  String _nextRefillLabel(int? seconds) {
    if (seconds == null || seconds <= 0) return 'Allowance is fully charged.';
    final duration = Duration(seconds: seconds);
    if (duration.inHours > 0) {
      return 'Next +1% in ${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    return 'Next +1% in ${duration.inMinutes + 1}m';
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.compact,
    required this.expanded,
    required this.onPressed,
  });

  final bool compact;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: expanded ? 'Collapse preview' : 'Expand preview',
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      icon: Icon(
        compact
            ? (expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded)
            : (expanded
                ? Icons.chevron_right_rounded
                : Icons.chevron_left_rounded),
      ),
    );

    if (!compact) {
      if (!expanded) return Center(child: button);

      // In the right-hand preview, keep the folding control next to the panel
      // title instead of sending it to the distant upper-right corner.
      return Row(
        children: [
          button,
          const SizedBox(width: 2),
          const Icon(Icons.image_outlined, size: 18, color: Colors.white54),
          const SizedBox(width: 8),
          const Text(
            'PREVIEW',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        const SizedBox(width: 6),
        const Icon(Icons.image_outlined, size: 18, color: Colors.white54),
        const SizedBox(width: 8),
        const Text(
          'PREVIEW',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        button,
      ],
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
