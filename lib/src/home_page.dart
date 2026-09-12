import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:artist_tag_vault/src/models/account_usage.dart';
import 'package:artist_tag_vault/src/models/app_settings.dart';
import 'package:artist_tag_vault/src/models/custom_artist.dart';
import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:artist_tag_vault/src/services/danbooru_autocomplete.dart';
import 'package:artist_tag_vault/src/services/novelai_api.dart';
import 'package:artist_tag_vault/src/services/prompt_composer.dart';
import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:artist_tag_vault/src/services/settings_store.dart';
import 'package:artist_tag_vault/src/settings_dialog.dart';
import 'package:artist_tag_vault/src/vault_page.dart';
import 'package:artist_tag_vault/src/widgets/danbooru_artist_field.dart';
import 'package:artist_tag_vault/src/widgets/glass_panel.dart';
import 'package:artist_tag_vault/src/widgets/numeric_stepper_field.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

enum _Workspace { generate, custom, vault }

/// Main artist entry, generation action, and latest-sample preview.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _maximumSeed = 0xffffffff;

  final _artistController = TextEditingController();
  final _artistFocusNode = FocusNode();
  final _promptController = TextEditingController();
  final _undesiredController = TextEditingController();
  final _advancedScrollController = ScrollController();
  final _compactScrollController = ScrollController();
  final _settingsStore = SettingsStore();
  final _api = NovelAiApi();
  final _sampleStorage = SampleStorage();
  final _danbooruAutocomplete = DanbooruAutocompleteService();
  final _random = Random.secure();

  AppSettings _settings = AppSettings.defaults();
  File? _previewFile;
  Uint8List? _previewBytes;
  String _status = 'Enter an artist name to create a standardized sample.';
  bool _busy = false;
  bool _previewExpanded = true;
  bool _advancedExpanded = false;
  bool _usageExpanded = false;
  _Workspace _workspace = _Workspace.generate;
  AccountUsage? _accountUsage;
  bool _usageLoading = false;
  String? _usageError;
  late int _seed;
  bool _seedLocked = false;
  double _artistWeight = 1;
  int _generationCount = 1;
  final List<CustomArtist> _customArtists = [];
  bool _randomizeCustomOrder = false;
  bool _randomizeCustomWeights = false;

  @override
  void initState() {
    super.initState();
    _seed = _createRandomSeed();
    final defaults = GenerationPreset.defaults();
    _promptController.text = defaults.prompt;
    _undesiredController.text = defaults.undesiredContent;
    _loadSettings();
  }

  @override
  void dispose() {
    _artistController.dispose();
    _artistFocusNode.dispose();
    _promptController.dispose();
    _undesiredController.dispose();
    _advancedScrollController.dispose();
    _compactScrollController.dispose();
    _danbooruAutocomplete.close();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final loaded = await _settingsStore.load();
      if (!mounted) return;
      setState(() {
        _settings = loaded;
        _promptController.text = loaded.preset.prompt;
        _undesiredController.text = loaded.preset.undesiredContent;
      });
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
        artistDictionary: _danbooruAutocomplete,
      ),
    );
    if (updated == null) return;

    try {
      await _settingsStore.save(updated);
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _status = 'App settings saved.';
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

    final custom = _workspace == _Workspace.custom;
    final artist = _artistController.text.trim();
    if (!custom && artist.isEmpty) {
      _showError('아티스트 이름을 입력해 주세요.');
      return;
    }
    if (custom && _customArtists.isEmpty) {
      _showError('Custom 목록에 아티스트를 한 명 이상 추가해 주세요.');
      return;
    }
    if (_settings.apiToken.isEmpty) {
      _showError('설정에서 NovelAI API 토큰을 먼저 저장해 주세요.');
      return;
    }

    final model = _settings.preset.model;
    final configuredWeights = custom
        ? _customArtists.map((entry) => entry.weight)
        : [_artistWeight];
    final usesWeights = (_randomizeCustomWeights && custom) ||
        configuredWeights.any((weight) => (weight - 1).abs() >= 0.000001);
    if (usesWeights &&
        !model.supportsNumericalEmphasis) {
      _showError('이 모델은 숫자 가중치를 지원하지 않습니다. 가중치를 1.00으로 설정해 주세요.');
      return;
    }
    if (configuredWeights.any((weight) => weight < 0) &&
        !model.supportsNegativeNumericalEmphasis) {
      _showError('음수 가중치는 NovelAI Diffusion V4.5 이상에서 사용할 수 있습니다.');
      return;
    }

    final negativePrompt = _settings.preset.composedUndesiredContent;
    setState(() {
      _busy = true;
      _status = 'Preparing $_generationCount generation(s)…';
    });

    try {
      for (var index = 0; index < _generationCount; index++) {
        final requestSeed = _seedLocked ? _seed : _createRandomSeed();
        final preparedArtists = custom
            ? CustomArtistRandomizer.prepare(
                _customArtists,
                randomizeOrder: _randomizeCustomOrder,
                randomizeWeights: _randomizeCustomWeights,
                random: _random,
              )
            : <CustomArtist>[];
        final artistPrompt = custom
            ? PromptComposer.composeMultiple(
                artists: preparedArtists
                    .map((entry) => (artist: entry.name, weight: entry.weight)),
                presetPrompt: _settings.preset.prompt,
              )
            : PromptComposer.compose(
                artist: artist,
                presetPrompt: _settings.preset.prompt,
                artistWeight: _artistWeight,
              );
        final prompt = _settings.preset.composePrompt(artistPrompt);
        if (mounted) {
          setState(() {
            _seed = requestSeed;
            _status = 'Generating ${index + 1} / $_generationCount…';
          });
        }
        final generated = await _api.generate(
          token: _settings.apiToken,
          prompt: prompt,
          negativePrompt: negativePrompt,
          preset: _settings.preset,
          seed: requestSeed,
        );
        if (custom) {
          if (!mounted) return;
          setState(() {
            _previewFile = null;
            _previewBytes = generated.bytes;
            _seed = generated.seed;
            _status = 'Generated ${index + 1} / $_generationCount · not saved';
          });
        } else {
          final file = await _sampleStorage.save(
            bytes: generated.bytes,
            artist: artist,
            composedPrompt: prompt,
            composedUndesiredContent: negativePrompt,
            seed: generated.seed,
            artistWeight: _artistWeight,
            preset: _settings.preset,
          );
          if (!mounted) return;
          setState(() {
            _previewBytes = null;
            _previewFile = file;
            _seed = generated.seed;
            _status = 'Saved ${index + 1} / $_generationCount · ${file.path}';
          });
        }
      }
      unawaited(_refreshUsage());
    } on Exception catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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

  Future<void> _openFolder() async {
    try {
      await _sampleStorage.openRootDirectory();
    } on Exception catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  void _showError(String message) {
    setState(() => _status = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  int _createRandomSeed() {
    // Joining two 16-bit values covers NovelAI's unsigned 32-bit seed range
    // without relying on a platform-specific nextInt upper-bound behavior.
    return (_random.nextInt(1 << 16) << 16) | _random.nextInt(1 << 16);
  }

  void _updatePreset(GenerationPreset preset) {
    setState(() => _settings = _settings.copyWith(preset: preset));
  }

  Future<void> _savePreset() async {
    try {
      await _settingsStore.save(_settings);
      if (mounted) {
        setState(() => _status = 'Generation preset saved as default.');
      }
    } on SettingsStoreException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  void _resetPreset() {
    final defaults = GenerationPreset.defaults();
    setState(() {
      _settings = _settings.copyWith(preset: defaults);
      _promptController.text = defaults.prompt;
      _undesiredController.text = defaults.undesiredContent;
      _status = 'Generation preset reset. Save as default to keep it.';
    });
  }

  void _loadSample(SavedSample sample) {
    final rawPreset = sample.metadata['preset'];
    final preset = rawPreset is Map<String, dynamic>
        ? GenerationPreset.fromJson(rawPreset)
        : _settings.preset;
    setState(() {
      _workspace = _Workspace.generate;
      _settings = _settings.copyWith(preset: preset);
      _artistController.text = sample.artist;
      _promptController.text = preset.prompt;
      _undesiredController.text = preset.undesiredContent;
      _seed = sample.seed ?? _seed;
      _seedLocked = sample.seed != null;
      _artistWeight =
          (sample.metadata['artistWeight'] as num?)?.toDouble() ?? 1;
      _advancedExpanded = true;
      _status = 'Loaded settings from ${path.basename(sample.file.path)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AmbientBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, windowConstraints) {
                final compactHeader = windowConstraints.maxWidth < 1050;
                final edge = windowConstraints.maxWidth < 700 ? 16.0 : 28.0;
                return Padding(
                  padding: EdgeInsets.all(edge),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(compact: compactHeader),
                      SizedBox(height: compactHeader ? 16 : 24),
                      Expanded(
                        child: _workspace == _Workspace.vault
                            ? VaultPage(
                                storage: _sampleStorage,
                                onUseSample: _loadSample,
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact =
                                      constraints.maxWidth < 860 ||
                                      constraints.maxHeight < 620;
                                  return compact
                                      ? _buildCompactLayout(constraints)
                                      : _buildWideLayout();
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Uses vertical folding for narrow windows such as the macOS screenshot.
  Widget _buildCompactLayout(BoxConstraints constraints) {
    final advancedHeight = (constraints.maxHeight * .72).clamp(360.0, 560.0);
    final previewHeight = _previewExpanded
        ? (constraints.maxHeight * .62).clamp(280.0, 520.0)
        : 64.0;

    return Scrollbar(
      controller: _compactScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _compactScrollController,
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildGenerateSection(),
            const SizedBox(height: 12),
            if (_advancedExpanded)
              SizedBox(height: advancedHeight, child: _buildAdvanced())
            else
              _buildAdvanced(),
            const SizedBox(height: 14),
            SizedBox(
              height: previewHeight,
              child: _buildPreview(compact: true),
            ),
            const SizedBox(height: 14),
            _buildAccountUsageSection(),
          ],
        ),
      ),
    );
  }

  /// On wide windows the closed preview becomes a slim rail on the right.
  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _advancedExpanded ? 450 : 370, child: _buildControls()),
        const SizedBox(width: 22),
        if (_previewExpanded)
          Expanded(child: _buildPreview(compact: false))
        else
          SizedBox(width: 64, child: _buildPreview(compact: false)),
      ],
    );
  }

  Widget _buildHeader({required bool compact}) {
    final brand = Row(
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
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
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Artist Tag Vault',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              Text(
                'NovelAI artist-tag sample catalog',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
    final workspace = SegmentedButton<_Workspace>(
      segments: const [
        ButtonSegment(
          value: _Workspace.generate,
          icon: Icon(Icons.auto_awesome_rounded),
          label: Text('Generate'),
        ),
        ButtonSegment(
          value: _Workspace.custom,
          icon: Icon(Icons.tune_rounded),
          label: Text('Custom'),
        ),
        ButtonSegment(
          value: _Workspace.vault,
          icon: Icon(Icons.photo_library_outlined),
          label: Text('Vault'),
        ),
      ],
      selected: {_workspace},
      onSelectionChanged: (selection) =>
          setState(() => _workspace = selection.first),
    );
    final actions = <Widget>[
      IconButton.filledTonal(
        tooltip: 'Open storage folder',
        onPressed: _openFolder,
        icon: const Icon(Icons.folder_open_rounded),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        tooltip: 'Settings',
        onPressed: _openSettings,
        icon: const Icon(Icons.tune_rounded),
      ),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          brand,
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: workspace),
              const SizedBox(width: 12),
              ...actions,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: brand),
        workspace,
        const SizedBox(width: 12),
        ...actions,
      ],
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGenerateSection(),
        const SizedBox(height: 12),
        if (_advancedExpanded)
          Expanded(child: _buildAdvanced())
        else
          _buildAdvanced(),
        const SizedBox(height: 12),
        _buildAccountUsageSection(),
      ],
    );
  }

  Widget _buildGenerateSection() {
    final custom = _workspace == _Workspace.custom;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            custom ? 'CUSTOM GENERATION' : 'CREATE SAMPLE',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (custom)
            _buildCustomArtistList()
          else
            DanbooruArtistField(
              controller: _artistController,
              focusNode: _artistFocusNode,
              service: _danbooruAutocomplete,
              enabled: !_busy,
              onSubmitted: (_) => _generate(),
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
                  onChanged: (value) => setState(() => _seed = value.round()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _seedLocked ? 'Unlock seed' : 'Lock seed',
                style: _seedLocked
                    ? IconButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      )
                    : null,
                onPressed: _busy
                    ? null
                    : () => setState(() => _seedLocked = !_seedLocked),
                icon: Icon(
                  _seedLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                ),
              ),
            ],
          ),
          if (!custom) ...[
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
          ] else ...[
            const SizedBox(height: 10),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Random artist order'),
              value: _randomizeCustomOrder,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _randomizeCustomOrder = value ?? false,
                    ),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Random weights  ·  0.50–1.50'),
              value: _randomizeCustomWeights,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _randomizeCustomWeights = value ?? false,
                    ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FilledButton.icon(
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
                  label: Text(
                    _busy
                        ? 'Generating…'
                        : custom
                        ? 'Generate'
                        : 'Generate & Save',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: NumericStepperField(
                  value: _generationCount.toDouble(),
                  minimum: 1,
                  maximum: 99,
                  step: 1,
                  decimalPlaces: 0,
                  enabled: !_busy,
                  labelText: 'Count',
                  onChanged: (value) =>
                      setState(() => _generationCount = value.round()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomArtistList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _editCustomArtist(),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add artist'),
        ),
        if (_customArtists.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'No artists added yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          )
        else
          Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(34, 8, 88, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('ARTIST', style: _customColumnStyle),
                    ),
                    SizedBox(
                      width: 58,
                      child: Text('WEIGHT', style: _customColumnStyle),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text('FIX', style: _customColumnStyle),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: _customArtists.length,
                  // ignore: deprecated_member_use
                  onReorder: _busy ? (_, __) {} : _reorderCustomArtist,
                  itemBuilder: (context, index) {
                    final artist = _customArtists[index];
                    return ListTile(
                  key: ObjectKey(artist),
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 4),
                  leading: ReorderableDragStartListener(
                    index: index,
                    enabled: !_busy,
                    child: const Icon(Icons.drag_handle_rounded, size: 18),
                  ),
                  title: Text(artist.name, overflow: TextOverflow.ellipsis),
                  trailing: SizedBox(
                    width: 158,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(artist.weight.toStringAsFixed(2)),
                        ),
                        Checkbox(
                          value: artist.fixed,
                          visualDensity: VisualDensity.compact,
                          onChanged: _busy
                              ? null
                              : (value) => setState(
                                  () => _customArtists[index] = artist.copyWith(
                                    fixed: value ?? false,
                                  ),
                                ),
                        ),
                      IconButton(
                        tooltip: 'Edit artist',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _editCustomArtist(index: index),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Remove artist',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _customArtists.removeAt(index),
                              ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                      ],
                    ),
                  ),
                );
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _reorderCustomArtist(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final artist = _customArtists.removeAt(oldIndex);
      _customArtists.insert(newIndex, artist);
    });
  }

  Future<void> _editCustomArtist({int? index}) async {
    final result = await showDialog<CustomArtist>(
      context: context,
      builder: (context) => _CustomArtistDialog(
        initialValue: index == null ? null : _customArtists[index],
        service: _danbooruAutocomplete,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _customArtists.add(result);
      } else {
        _customArtists[index] = result;
      }
    });
  }

  Widget _buildAccountUsageSection() {
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: 20,
      child: _UsageCard(
        usage: _accountUsage,
        loading: _usageLoading,
        error: _usageError,
        showV5Allowance: _settings.preset.model.isV5,
        mayConsumeAnlas: _settings.preset.exceedsNormalFreeBoundary,
        expanded: _usageExpanded,
        status: _status,
        onToggle: () => setState(() => _usageExpanded = !_usageExpanded),
        onRefresh: _usageLoading ? null : _refreshUsage,
      ),
    );
  }

  Widget _buildAdvanced() {
    final preset = _settings.preset;
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: 20,
      child: Column(
        mainAxisSize: _advancedExpanded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _advancedExpanded = !_advancedExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ADVANCED',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${preset.model.label.replaceFirst('NovelAI Diffusion ', '')} · '
                          '${preset.steps} steps · ${preset.dimensions.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _advancedExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.white60,
                  ),
                ],
              ),
            ),
          ),
          if (_advancedExpanded)
            Expanded(
              child: Scrollbar(
                controller: _advancedScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _advancedScrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 28, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<NovelAiModel>(
                        key: ValueKey(preset.model),
                        initialValue: preset.model,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Version'),
                        items: NovelAiModel.values
                            .map(
                              (model) => DropdownMenuItem(
                                value: model,
                                child: Text(model.label),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => _changeModel(value),
                      ),
                      const SizedBox(height: 10),
                      _ResponsiveSettingPair(
                        first: DropdownButtonFormField<ImageAspectRatioPreset>(
                          key: ValueKey(preset.aspectRatio),
                          initialValue: preset.aspectRatio,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Image ratio',
                          ),
                          items: ImageAspectRatioPreset.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    '${value.label} · ${value.ratioLabel}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _updatePreset(
                                      preset.copyWith(aspectRatio: value),
                                    );
                                  }
                                },
                        ),
                        second: DropdownButtonFormField<ImageResolutionPreset>(
                          key: ValueKey(preset.resolution),
                          initialValue: preset.resolution,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Resolution',
                          ),
                          items: ImageResolutionPreset.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _updatePreset(
                                      preset.copyWith(resolution: value),
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Canvas · ${preset.dimensions.label}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      _SliderSettingRow(
                        label: 'Steps',
                        value: preset.steps.toDouble(),
                        minimum: GenerationPreset.minimumSteps.toDouble(),
                        maximum: GenerationPreset.maximumSteps.toDouble(),
                        divisions: 49,
                        step: 1,
                        decimalPlaces: 0,
                        enabled: !_busy,
                        onChanged: (value) => _updatePreset(
                          preset.copyWith(steps: value.round()),
                        ),
                      ),
                      _SliderSettingRow(
                        label: 'Guidance',
                        value: preset.guidance,
                        minimum: GenerationPreset.minimumGuidance,
                        maximum: GenerationPreset.maximumGuidance,
                        divisions: 100,
                        step: .1,
                        decimalPlaces: 2,
                        enabled: !_busy,
                        onChanged: (value) =>
                            _updatePreset(preset.copyWith(guidance: value)),
                      ),
                      _SliderSettingRow(
                        label: 'Rescale',
                        value: preset.guidanceRescale,
                        minimum: GenerationPreset.minimumGuidanceRescale,
                        maximum: GenerationPreset.maximumGuidanceRescale,
                        divisions: 100,
                        step: .01,
                        decimalPlaces: 2,
                        enabled: !_busy,
                        onChanged: (value) => _updatePreset(
                          preset.copyWith(guidanceRescale: value),
                        ),
                      ),
                      _ResponsiveSettingPair(
                        first: DropdownButtonFormField<NovelAiSampler>(
                          key: ValueKey(preset.sampler),
                          initialValue: preset.sampler,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Sampler',
                          ),
                          items: NovelAiSampler.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _updatePreset(
                                      preset.copyWith(sampler: value),
                                    );
                                  }
                                },
                        ),
                        second: DropdownButtonFormField<NoiseSchedule>(
                          key: ValueKey(preset.noiseSchedule),
                          initialValue: preset.noiseSchedule,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Schedule',
                          ),
                          items: NoiseSchedule.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _updatePreset(
                                      preset.copyWith(noiseSchedule: value),
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _promptController,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Preset prompt',
                        ),
                        onChanged: (value) => _updatePreset(
                          preset.copyWith(prompt: value.trim()),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _undesiredController,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Additional undesired content',
                        ),
                        onChanged: (value) => _updatePreset(
                          preset.copyWith(undesiredContent: value.trim()),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _ResponsiveSettingPair(
                        first: DropdownButtonFormField<QualityTagPreset>(
                          key: ValueKey(preset.qualityTagPreset),
                          initialValue: preset.qualityTagPreset,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Automatic quality',
                          ),
                          items: preset.availableQualityTagPresets
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _updatePreset(
                                      preset.copyWith(qualityTagPreset: value),
                                    );
                                  }
                                },
                        ),
                        second: DropdownButtonFormField<UndesiredContentPreset>(
                          key: ValueKey(preset.undesiredContentPreset),
                          initialValue: preset.undesiredContentPreset,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Negative preset',
                          ),
                          items: preset.availableUndesiredContentPresets
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _updatePreset(
                                      preset.copyWith(
                                        undesiredContentPreset: value,
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : _resetPreset,
                            child: const Text('Reset'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _busy ? null : _savePreset,
                            child: const Text('Save as default'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _changeModel(NovelAiModel? model) {
    if (model == null) return;
    var preset = _settings.preset.copyWith(model: model);
    if (!preset.availableQualityTagPresets.contains(preset.qualityTagPreset)) {
      preset = preset.copyWith(qualityTagPreset: QualityTagPreset.standard);
    }
    if (!preset.availableUndesiredContentPresets.contains(
      preset.undesiredContentPreset,
    )) {
      preset = preset.copyWith(
        undesiredContentPreset: UndesiredContentPreset.heavy,
      );
    }
    _updatePreset(preset);
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
                    child: _previewFile == null && _previewBytes == null
                        ? const _EmptyPreview()
                        : _previewBytes != null
                        ? Image.memory(
                            _previewBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
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

const _customColumnStyle = TextStyle(
  color: Colors.white38,
  fontSize: 9,
  letterSpacing: .8,
  fontWeight: FontWeight.w700,
);

class _CustomArtistDialog extends StatefulWidget {
  const _CustomArtistDialog({
    required this.initialValue,
    required this.service,
  });

  final CustomArtist? initialValue;
  final DanbooruAutocompleteService service;

  @override
  State<_CustomArtistDialog> createState() => _CustomArtistDialogState();
}

class _CustomArtistDialogState extends State<_CustomArtistDialog> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  late double _weight;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue?.name ?? '');
    _weight = widget.initialValue?.weight ?? 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      CustomArtist(
        name: name,
        weight: _weight,
        fixed: widget.initialValue?.fixed ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialValue == null ? 'Add artist' : 'Edit artist'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DanbooruArtistField(
              controller: _controller,
              focusNode: _focusNode,
              service: widget.service,
              enabled: true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            NumericStepperField(
              value: _weight,
              minimum: -5,
              maximum: 5,
              step: .01,
              decimalPlaces: 2,
              labelText: 'Weight',
              onChanged: (value) => setState(() => _weight = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.usage,
    required this.loading,
    required this.error,
    required this.showV5Allowance,
    required this.mayConsumeAnlas,
    required this.expanded,
    required this.status,
    required this.onToggle,
    required this.onRefresh,
  });

  final AccountUsage? usage;
  final bool loading;
  final String? error;
  final bool showV5Allowance;
  final bool mayConsumeAnlas;
  final bool expanded;
  final String status;
  final VoidCallback onToggle;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final percent = usage?.v5Percent;
    final showBoundaryGauge = !expanded && showV5Allowance && percent != null;
    final showCostWarning = !expanded && mayConsumeAnlas;
    final summary = usage == null
        ? (error ?? 'Usage unavailable')
        : '${usage!.totalAnlas} Anlas'
              '${showV5Allowance && percent != null ? ' · V5 $percent%' : ''}';

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  9,
                  8,
                  showBoundaryGauge ? 12 : 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      showCostWarning
                          ? Icons.warning_amber_rounded
                          : Icons.bolt_rounded,
                      size: 18,
                      color: showCostWarning
                          ? Colors.amberAccent
                          : const Color(0xFF68D9D0),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'ACCOUNT USAGE',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: showCostWarning
                            ? Colors.amberAccent
                            : Colors.white60,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        loading
                            ? 'Refreshing…'
                            : showCostWarning
                            ? 'May use Anlas · $summary'
                            : summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: showCostWarning
                              ? Colors.amberAccent
                              : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Colors.white60,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (usage != null)
                          Expanded(
                            child: Text(
                              '${usage!.totalAnlas} Anlas · ${usage!.tierLabel}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
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
                        'Subscription ${usage!.subscriptionAnlas}  ·  '
                        'Paid ${usage!.paidAnlas}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
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
                          color: error == null
                              ? Colors.white54
                              : Colors.redAccent,
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
                        color: mayConsumeAnlas
                            ? Colors.amberAccent
                            : Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (showBoundaryGauge)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: (percent.clamp(0, 100) / 100).toDouble(),
              minHeight: 4,
              color: usage?.v5Unavailable == true
                  ? Colors.redAccent
                  : showCostWarning
                  ? Colors.amberAccent
                  : const Color(0xFF68D9D0),
              backgroundColor: Colors.white10,
            ),
          ),
      ],
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

class _ResponsiveSettingPair extends StatelessWidget {
  const _ResponsiveSettingPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 10), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _SliderSettingRow extends StatelessWidget {
  const _SliderSettingRow({
    required this.label,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.step,
    required this.decimalPlaces,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double minimum;
  final double maximum;
  final int divisions;
  final double step;
  final int decimalPlaces;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slider = Slider(
            value: value.clamp(minimum, maximum).toDouble(),
            min: minimum,
            max: maximum,
            divisions: divisions,
            label: value.toStringAsFixed(decimalPlaces),
            onChanged: enabled ? onChanged : null,
          );
          final input = SizedBox(
            width: 94,
            child: NumericStepperField(
              value: value,
              minimum: minimum,
              maximum: maximum,
              step: step,
              decimalPlaces: decimalPlaces,
              enabled: enabled,
              onChanged: onChanged,
            ),
          );

          if (constraints.maxWidth < 350) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70)),
                Row(
                  children: [
                    Expanded(child: slider),
                    input,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(child: slider),
              const SizedBox(width: 6),
              input,
            ],
          );
        },
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
            Text(
              'Generated image preview',
              style: TextStyle(color: Colors.white38),
            ),
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
