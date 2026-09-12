import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:artist_tag_vault/src/widgets/glass_panel.dart';
import 'package:flutter/gestures.dart';
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
  bool _deleting = false;
  bool _showInfo = false;
  String? _modelId;
  String? _artist;
  SavedSample? _selected;
  Size? _imageSize;
  Size? _viewerSize;
  String? _error;
  bool _fitMode = true;
  Matrix4? _gestureStartTransform;
  Offset? _gestureStartScenePoint;
  Offset _gestureDistance = Offset.zero;
  double _gestureStartScale = 1;
  double _wheelDistance = 0;
  bool _wheelNavigationHandled = false;
  Timer? _wheelResetTimer;
  int? _navigationCue;
  Timer? _navigationCueTimer;

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
    _wheelResetTimer?.cancel();
    _navigationCueTimer?.cancel();
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

  List<String> get _allModelArtists {
    final artists = _modelSamples.map((sample) => sample.artist).toSet().toList();
    artists.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return artists;
  }

  List<String> get _artists {
    final query = _search.text.trim().toLowerCase();
    return _allModelArtists
        .where(
          (artist) => query.isEmpty || artist.toLowerCase().contains(query),
        )
        .toList();
  }

  List<SavedSample> get _artistSamples => _modelSamples
      .where((sample) => _artist == null || sample.artist == _artist)
      .toList();

  void _selectModel(String? value) {
    setState(() {
      _fitMode = true;
      _modelId = value;
      _artist = _modelSamples.isEmpty ? null : _modelSamples.first.artist;
      _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
    });
    unawaited(_readSelectedImageSize());
  }

  void _selectArtist(String artist) {
    setState(() {
      _fitMode = true;
      _artist = artist;
      _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
    });
    unawaited(_readSelectedImageSize());
  }

  void _selectSample(SavedSample sample) {
    setState(() {
      _fitMode = true;
      _selected = sample;
    });
    unawaited(_readSelectedImageSize());
  }

  Future<void> _deleteSelected() async {
    final sample = _selected;
    if (sample == null || _deleting) return;
    final filename = sample.file.uri.pathSegments.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete sample?'),
        content: Text(
          '$filename\n\nThe PNG and its JSON metadata file will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final selectedIndex = _artistSamples.indexOf(sample);
    final artistsBefore = _allModelArtists;
    final modelsBefore = _models;
    setState(() => _deleting = true);
    try {
      await widget.storage.deleteSample(sample);
      if (!mounted) return;
      _selectAfterDeletion(
        sample,
        selectedIndex: selectedIndex,
        artistsBefore: artistsBefore,
        modelsBefore: modelsBefore,
      );
      if (_selected == null) {
        _imageSize = null;
        _transform.value = Matrix4.identity();
      } else {
        unawaited(_readSelectedImageSize());
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $filename and its metadata.')),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete sample: $error')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _selectAfterDeletion(
    SavedSample deleted, {
    required int selectedIndex,
    required List<String> artistsBefore,
    required List<String> modelsBefore,
  }) {
    final remaining = _samples
        .where((sample) => sample.file.path != deleted.file.path)
        .toList();
    String? nextModel = deleted.modelId;
    String? nextArtist = deleted.artist;
    SavedSample? nextSample;

    final sameArtist = remaining
        .where(
          (sample) =>
              sample.modelId == deleted.modelId &&
              sample.artist == deleted.artist,
        )
        .toList();
    if (sameArtist.isNotEmpty) {
      nextSample = sameArtist[math.min(selectedIndex, sameArtist.length - 1)];
    } else {
      final sameModel = remaining
          .where((sample) => sample.modelId == deleted.modelId)
          .toList();
      if (sameModel.isNotEmpty) {
        nextArtist = _adjacentValue(
          current: deleted.artist,
          previousOrder: artistsBefore,
          remaining: sameModel.map((sample) => sample.artist).toSet(),
        );
        nextSample = sameModel.firstWhere(
          (sample) => sample.artist == nextArtist,
        );
      } else if (remaining.isNotEmpty) {
        nextModel = _adjacentValue(
          current: deleted.modelId,
          previousOrder: modelsBefore,
          remaining: remaining.map((sample) => sample.modelId).toSet(),
        );
        nextSample = remaining.firstWhere(
          (sample) => sample.modelId == nextModel,
        );
        nextArtist = nextSample.artist;
      } else {
        nextModel = null;
        nextArtist = null;
      }
    }

    setState(() {
      _samples = remaining;
      _modelId = nextModel;
      _artist = nextArtist;
      _selected = nextSample;
    });
  }

  String _adjacentValue({
    required String current,
    required List<String> previousOrder,
    required Set<String> remaining,
  }) {
    final index = previousOrder.indexOf(current);
    if (index >= 0) {
      for (var i = index + 1; i < previousOrder.length; i++) {
        if (remaining.contains(previousOrder[i])) return previousOrder[i];
      }
      for (var i = index - 1; i >= 0; i--) {
        if (remaining.contains(previousOrder[i])) return previousOrder[i];
      }
    }
    return remaining.first;
  }

  bool _moveSelection(int delta, {bool showCue = false}) {
    final sample = _selected;
    if (sample == null) return false;
    final index = _artistSamples.indexOf(sample);
    final next = index + delta;
    if (next < 0 || next >= _artistSamples.length) return false;
    if (showCue) _showNavigationCue(delta);
    _selectSample(_artistSamples[next]);
    return true;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _artistSamples.length < 2) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;

    _wheelResetTimer?.cancel();
    _wheelResetTimer = Timer(const Duration(milliseconds: 220), () {
      _wheelDistance = 0;
      _wheelNavigationHandled = false;
    });
    if (_wheelNavigationHandled) return;

    _wheelDistance += delta;
    if (_wheelDistance.abs() < 12) return;
    _wheelNavigationHandled = true;
    _wheelDistance = 0;
    _moveSelection(delta > 0 ? 1 : -1, showCue: true);
  }

  void _startImageGesture(ScaleStartDetails details) {
    _gestureStartTransform = Matrix4.copy(_transform.value);
    _gestureStartScenePoint = _transform.toScene(details.localFocalPoint);
    _gestureDistance = Offset.zero;
    _gestureStartScale = _transform.value.getMaxScaleOnAxis();
  }

  void _updateImageGesture(ScaleUpdateDetails details) {
    final start = _gestureStartTransform;
    final scenePoint = _gestureStartScenePoint;
    if (start == null || scenePoint == null) return;
    _gestureDistance += details.focalPointDelta;

    final scaling =
        (details.scale - 1).abs() > .001 || details.pointerCount > 1;
    if (scaling) {
      _fitMode = false;
      final minimumScale = _minimumScale;
      final scale = (_gestureStartScale * details.scale)
          .clamp(minimumScale, 8.0)
          .toDouble();
      final focalPoint = details.localFocalPoint;
      _transform.value = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(0, 3, focalPoint.dx - scenePoint.dx * scale)
        ..setEntry(1, 3, focalPoint.dy - scenePoint.dy * scale);
      return;
    }

    // Fit is anchored to the viewer. Dragging only pans an enlarged image.
    if (_fitMode || !_canPanAtScale(_gestureStartScale)) return;

    final image = _imageSize!;
    final viewer = _viewerSize!;
    final width = image.width * _gestureStartScale;
    final height = image.height * _gestureStartScale;
    _transform.value = Matrix4.copy(start)
      ..setEntry(
        0,
        3,
        start.entry(0, 3) + (width > viewer.width ? _gestureDistance.dx : 0),
      )
      ..setEntry(
        1,
        3,
        start.entry(1, 3) + (height > viewer.height ? _gestureDistance.dy : 0),
      );
  }

  void _endImageGesture(ScaleEndDetails _) {
    _constrainImagePosition();
    _gestureStartTransform = null;
    _gestureStartScenePoint = null;
    _gestureDistance = Offset.zero;
  }

  double get _fitScale {
    final image = _imageSize;
    final viewer = _viewerSize;
    if (image == null || viewer == null) return 1;
    return math
        .min(viewer.width / image.width, viewer.height / image.height)
        .clamp(0.01, 8.0)
        .toDouble();
  }

  double get _minimumScale => math.min(_fitScale, 1);

  bool _canPanAtScale(double scale) {
    final image = _imageSize;
    final viewer = _viewerSize;
    if (image == null || viewer == null) return false;
    return image.width * scale > viewer.width + .5 ||
        image.height * scale > viewer.height + .5;
  }

  void _constrainImagePosition() {
    final image = _imageSize;
    final viewer = _viewerSize;
    if (image == null || viewer == null) return;
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final width = image.width * scale;
    final height = image.height * scale;
    final x = width <= viewer.width
        ? (viewer.width - width) / 2
        : matrix.entry(0, 3).clamp(viewer.width - width, 0).toDouble();
    final y = height <= viewer.height
        ? (viewer.height - height) / 2
        : matrix.entry(1, 3).clamp(viewer.height - height, 0).toDouble();
    if ((matrix.entry(0, 3) - x).abs() <= .5 &&
        (matrix.entry(1, 3) - y).abs() <= .5) {
      return;
    }
    _transform.value = Matrix4.copy(matrix)
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);
  }

  void _updateViewerSize(Size size) {
    if (_viewerSize == size) return;
    _viewerSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewerSize != size) return;
      if (_fitMode) {
        _fit();
      } else {
        _constrainImagePosition();
      }
    });
  }

  void _showNavigationCue(int direction) {
    _navigationCueTimer?.cancel();
    setState(() => _navigationCue = direction);
    _navigationCueTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _navigationCue = null);
    });
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
    _fitMode = true;
    final image = _imageSize;
    final viewer = _viewerSize;
    if (image == null || viewer == null) {
      _transform.value = Matrix4.identity();
      return;
    }
    _setScale(_fitScale);
  }

  void _oneToOne() {
    _fitMode = false;
    _setScale(1);
  }

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
    _fitMode = false;
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(_minimumScale, 8.0);
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
            key: ValueKey(_modelId),
            initialValue: _models.contains(_modelId) ? _modelId : null,
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
              if (_deleting)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Delete image and metadata',
                  onPressed: sample == null ? null : _deleteSelected,
                  color: Colors.redAccent,
                  icon: const Icon(Icons.delete_outline_rounded),
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
                _updateViewerSize(
                  Size(constraints.maxWidth, constraints.maxHeight),
                );
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
                        : Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerSignal: _handlePointerSignal,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              trackpadScrollCausesScale: false,
                              onScaleStart: _startImageGesture,
                              onScaleUpdate: _updateImageGesture,
                              onScaleEnd: _endImageGesture,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    width: _imageSize?.width ?? 0,
                                    height: _imageSize?.height ?? 0,
                                    child: AnimatedBuilder(
                                      animation: _transform,
                                      builder: (context, child) => Transform(
                                        transform: _transform.value,
                                        alignment: Alignment.topLeft,
                                        child: child,
                                      ),
                                      child: Image.file(
                                        sample.file,
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                  ),
                                  IgnorePointer(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      reverseDuration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      child: _navigationCue == null
                                          ? const SizedBox.shrink()
                                          : _NavigationCue(
                                              key: ValueKey(_navigationCue),
                                              direction: _navigationCue!,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
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
                    : () => _moveSelection(-1, showCue: true),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  sample == null
                      ? '0 / 0'
                      : '${_artistSamples.indexOf(sample) + 1} / ${_artistSamples.length}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Next image',
                onPressed:
                    sample == null ||
                        _artistSamples.indexOf(sample) >=
                            _artistSamples.length - 1
                    ? null
                    : () => _moveSelection(1, showCue: true),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 12),
              const SizedBox(
                height: 22,
                child: VerticalDivider(width: 1, thickness: 1),
              ),
              const SizedBox(width: 12),
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

class _NavigationCue extends StatelessWidget {
  const _NavigationCue({required this.direction, super.key});

  final int direction;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: direction < 0 ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              direction < 0
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              size: 38,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
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
