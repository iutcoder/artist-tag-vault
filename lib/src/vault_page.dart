import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:artist_tag_vault/src/widgets/glass_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({
    required this.storage,
    required this.onUseSample,
    super.key,
  });

  final SampleStorage storage;
  final ValueChanged<SavedSample> onUseSample;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _search = TextEditingController();
  final _transform = TransformationController();
  List<SavedSample> _samples = const [];
  bool _loading = true;
  bool _showInfo = false;
  String? _modelId;
  String? _artist;
  SavedSample? _selected;
  Size? _imageSize;
  Size? _viewerSize;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final samples = await widget.storage.scan();
      if (!mounted) return;
      setState(() {
        _samples = samples;
        _modelId ??= samples.isEmpty ? null : samples.first.modelId;
        final visible = _modelSamples;
        _artist = visible.isEmpty ? null : visible.first.artist;
        _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
      });
      unawaited(_readSelectedImageSize());
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _models =>
      _samples.map((sample) => sample.modelId).toSet().toList()..sort();

  List<SavedSample> get _modelSamples => _samples
      .where((sample) => _modelId == null || sample.modelId == _modelId)
      .toList();

  List<String> get _artists {
    final query = _search.text.trim().toLowerCase();
    final artists = _modelSamples
        .map((sample) => sample.artist)
        .where(
          (artist) => query.isEmpty || artist.toLowerCase().contains(query),
        )
        .toSet()
        .toList();
    artists.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return artists;
  }

  List<SavedSample> get _artistSamples => _modelSamples
      .where((sample) => _artist == null || sample.artist == _artist)
      .toList();

  void _selectModel(String? value) {
    setState(() {
      _modelId = value;
      _artist = _modelSamples.isEmpty ? null : _modelSamples.first.artist;
      _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
    });
    unawaited(_readSelectedImageSize());
  }

  void _selectArtist(String artist) {
    setState(() {
      _artist = artist;
      _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
    });
    unawaited(_readSelectedImageSize());
  }

  void _selectSample(SavedSample sample) {
    setState(() => _selected = sample);
    unawaited(_readSelectedImageSize());
  }

  void _moveSelection(int delta) {
    final sample = _selected;
    if (sample == null) return;
    final index = _artistSamples.indexOf(sample);
    final next = index + delta;
    if (next < 0 || next >= _artistSamples.length) return;
    _selectSample(_artistSamples[next]);
  }

  Future<void> _readSelectedImageSize() async {
    final sample = _selected;
    if (sample == null) return;
    try {
      final codec = await ui.instantiateImageCodec(
        await sample.file.readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || sample != _selected) {
        frame.image.dispose();
        return;
      }
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    } on Exception {
      _imageSize = null;
      _transform.value = Matrix4.identity();
    }
  }

  void _fit() {
    final image = _imageSize;
    final viewer = _viewerSize;
    if (image == null || viewer == null) {
      _transform.value = Matrix4.identity();
      return;
    }
    final scale = math
        .min(viewer.width / image.width, viewer.height / image.height)
        .clamp(0.01, 8.0)
        .toDouble();
    _setScale(scale);
  }

  void _oneToOne() => _setScale(1);

  void _setScale(double scale) {
    final image = _imageSize;
    final viewer = _viewerSize;
    if (image == null || viewer == null) return;
    final x = (viewer.width - image.width * scale) / 2;
    final y = (viewer.height - image.height * scale) / 2;
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.25, 8.0);
    _setScale(next.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('Reload · $_error'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideInfo = constraints.maxWidth >= 1080;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 240, child: _buildCatalog()),
            const SizedBox(width: 16),
            Expanded(child: _buildViewer(wideInfo: wideInfo)),
            if (wideInfo && _showInfo) ...[
              const SizedBox(width: 16),
              SizedBox(width: 340, child: _buildInfo()),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCatalog() {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('CATALOG', style: _sectionStyle),
              const Spacer(),
              IconButton(
                tooltip: 'Rescan samples',
                visualDensity: VisualDensity.compact,
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _models.contains(_modelId) ? _modelId : null,
            decoration: const InputDecoration(labelText: 'Version'),
            isExpanded: true,
            items: _models
                .map(
                  (model) => DropdownMenuItem(
                    value: model,
                    child: Text(model, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _selectModel,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Artist search',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _artists.isEmpty
                ? const Center(
                    child: Text(
                      'No samples',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: _artists.length,
                    itemBuilder: (context, index) {
                      final artist = _artists[index];
                      final count = _modelSamples
                          .where((sample) => sample.artist == artist)
                          .length;
                      return ListTile(
                        selected: artist == _artist,
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        title: Text(artist, overflow: TextOverflow.ellipsis),
                        trailing: Text('$count'),
                        onTap: () => _selectArtist(artist),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewer({required bool wideInfo}) {
    final sample = _selected;
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.image_outlined, size: 18, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sample?.artist ?? 'IMAGE',
                  overflow: TextOverflow.ellipsis,
                  style: _sectionStyle,
                ),
              ),
              IconButton(
                tooltip: 'Generation info',
                onPressed: sample == null
                    ? null
                    : () {
                        if (wideInfo) {
                          setState(() => _showInfo = !_showInfo);
                        } else {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => SizedBox(
                              height: MediaQuery.sizeOf(context).height * .75,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: _buildInfo(panel: false),
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewerSize = Size(constraints.maxWidth, constraints.maxHeight);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: Colors.black26,
                    child: sample == null
                        ? const Center(
                            child: Text(
                              'Select an artist sample',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : InteractiveViewer(
                            transformationController: _transform,
                            constrained: false,
                            boundaryMargin: const EdgeInsets.all(
                              double.infinity,
                            ),
                            minScale: .01,
                            maxScale: 8,
                            child: SizedBox(
                              width: _imageSize?.width,
                              height: _imageSize?.height,
                              child: Image.file(sample.file, fit: BoxFit.fill),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous image',
                onPressed: sample == null || _artistSamples.indexOf(sample) <= 0
                    ? null
                    : () => _moveSelection(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: sample == null ? null : () => _zoom(.8),
                icon: const Icon(Icons.remove_rounded),
              ),
              TextButton(
                onPressed: sample == null ? null : _fit,
                child: const Text('Fit'),
              ),
              TextButton(
                onPressed: sample == null ? null : _oneToOne,
                child: const Text('1:1'),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: sample == null ? null : () => _zoom(1.25),
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 12),
              Text(
                sample == null
                    ? '0 / 0'
                    : '${_artistSamples.indexOf(sample) + 1} / ${_artistSamples.length}',
              ),
              IconButton(
                tooltip: 'Next image',
                onPressed:
                    sample == null ||
                        _artistSamples.indexOf(sample) >=
                            _artistSamples.length - 1
                    ? null
                    : () => _moveSelection(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          if (_artistSamples.length > 1) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _artistSamples.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = _artistSamples[index];
                  return InkWell(
                    onTap: () => _selectSample(item),
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: item == sample
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white12,
                          width: item == sample ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(item.file, fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfo({bool panel = true}) {
    final sample = _selected;
    final content = sample == null
        ? const Center(child: Text('No generation data'))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('GENERATION INFO', style: _sectionStyle),
                  ),
                  if (panel)
                    IconButton(
                      onPressed: () => setState(() => _showInfo = false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    _InfoLine('Artist', sample.artist),
                    _InfoLine('Model', sample.modelId),
                    _InfoLine('Seed', sample.seed?.toString() ?? '—'),
                    _InfoLine('Created', sample.createdAt.toLocal().toString()),
                    _InfoLine('Steps', _value(sample, 'steps')),
                    _InfoLine(
                      'Guidance',
                      _value(sample, 'scale', fallback: 'guidance'),
                    ),
                    _InfoLine(
                      'Rescale',
                      _value(
                        sample,
                        'cfg_rescale',
                        fallback: 'guidanceRescale',
                      ),
                    ),
                    _InfoLine('Sampler', _value(sample, 'sampler')),
                    _InfoLine(
                      'Schedule',
                      _value(
                        sample,
                        'noise_schedule',
                        fallback: 'noiseSchedule',
                      ),
                    ),
                    _InfoLine(
                      'Canvas',
                      '${_value(sample, 'width')} × ${_value(sample, 'height')}',
                    ),
                    const SizedBox(height: 12),
                    _CopyBlock(label: 'Prompt', value: sample.prompt),
                    const SizedBox(height: 12),
                    _CopyBlock(
                      label: 'Undesired content',
                      value: sample.undesiredContent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () => widget.onUseSample(sample),
                icon: const Icon(Icons.input_rounded),
                label: const Text('Load in Generate'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => widget.storage.revealFile(sample.file),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Show in Finder'),
              ),
            ],
          );
    return panel
        ? GlassPanel(padding: const EdgeInsets.all(16), child: content)
        : content;
  }

  String _value(SavedSample sample, String key, {String? fallback}) =>
      (sample.metadata[key] ??
              (fallback == null ? null : sample.metadata[fallback]) ??
              '—')
          .toString();
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: const TextStyle(color: Colors.white38)),
        ),
        Expanded(child: SelectableText(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}

class _CopyBlock extends StatelessWidget {
  const _CopyBlock({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(color: Colors.white54)),
              const Spacer(),
              IconButton(
                tooltip: 'Copy $label',
                visualDensity: VisualDensity.compact,
                onPressed: value.isEmpty
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: value)),
                icon: const Icon(Icons.copy_rounded, size: 17),
              ),
            ],
          ),
          SelectableText(
            value.isEmpty ? '—' : value,
            maxLines: 8,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

const _sectionStyle = TextStyle(
  color: Colors.white60,
  fontSize: 11,
  letterSpacing: 1.4,
  fontWeight: FontWeight.w700,
);
