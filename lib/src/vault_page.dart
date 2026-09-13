import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:artist_tag_vault/src/services/sample_storage.dart';
import 'package:artist_tag_vault/src/widgets/glass_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _SubjectFilter { all, female, male, others }

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
  final _pageScroll = ScrollController();
  final _thumbnailScroll = ScrollController();
  final _keyboardFocus = FocusNode(debugLabel: 'Vault keyboard navigation');
  List<SavedSample> _samples = const [];
  bool _loading = true;
  bool _deleting = false;
  bool _showInfo = false;
  String? _modelId;
  String? _artist;
  _SubjectFilter _subjectFilter = _SubjectFilter.all;
  SavedSample? _selected;
  Size? _imageSize;
  Size? _viewerSize;
  String? _error;
  bool _searchFocused = false;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};
  String? _selectionAnchorPath;
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
    _pageScroll.dispose();
    _thumbnailScroll.dispose();
    _keyboardFocus.dispose();
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
        _selectionMode = false;
        _selectedPaths.clear();
        _selectionAnchorPath = null;
        _modelId ??= samples.isEmpty ? null : samples.first.modelId;
        final visible = _modelSamples;
        _artist = visible.isEmpty ? null : visible.first.vaultGroupKey;
        _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
      });
      unawaited(_readSelectedImageSize());
      _revealSelectedThumbnail(jump: true);
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
    final artists = _modelSamples
        .map((sample) => sample.vaultGroupKey)
        .toSet()
        .toList();
    artists.sort((a, b) {
      if (a == 'custom:' && b != 'custom:') return -1;
      if (b == 'custom:' && a != 'custom:') return 1;
      return _artistLabel(a).toLowerCase().compareTo(
        _artistLabel(b).toLowerCase(),
      );
    });
    return artists;
  }

  List<String> get _artists {
    final query = _search.text.trim().toLowerCase();
    return _allModelArtists
        .where(
          (artist) =>
              query.isEmpty ||
              _artistLabel(artist).toLowerCase().contains(query),
        )
        .toList();
  }

  List<SavedSample> get _allArtistSamples => _modelSamples
      .where((sample) => _artist == null || sample.vaultGroupKey == _artist)
      .toList();

  String _artistLabel(String groupKey) => _modelSamples
      .firstWhere((sample) => sample.vaultGroupKey == groupKey)
      .vaultGroupLabel;

  List<SavedSample> get _artistSamples =>
      _allArtistSamples.where(_matchesSubjectFilter).toList();

  bool _matchesSubjectFilter(SavedSample sample) => switch (_subjectFilter) {
    _SubjectFilter.all => true,
    _SubjectFilter.female => sample.subject == SampleSubject.female,
    _SubjectFilter.male => sample.subject == SampleSubject.male,
    _SubjectFilter.others => sample.subject == SampleSubject.others,
  };

  void _selectModel(String? value) {
    setState(() {
      _fitMode = true;
      _selectionMode = false;
      _selectedPaths.clear();
      _selectionAnchorPath = null;
      _modelId = value;
      _artist = _modelSamples.isEmpty
          ? null
          : _modelSamples.first.vaultGroupKey;
      _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
    });
    unawaited(_readSelectedImageSize());
    _revealSelectedThumbnail(jump: true);
  }

  void _selectArtist(String artist) {
    setState(() {
      _fitMode = true;
      _selectionMode = false;
      _selectedPaths.clear();
      _selectionAnchorPath = null;
      _artist = artist;
      _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
    });
    unawaited(_readSelectedImageSize());
    _revealSelectedThumbnail(jump: true);
  }

  void _selectSubject(_SubjectFilter? subject) {
    if (subject == null) return;
    setState(() {
      _fitMode = true;
      _selectionMode = false;
      _selectedPaths.clear();
      _selectionAnchorPath = null;
      _subjectFilter = subject;
      _selected = _artistSamples.isEmpty ? null : _artistSamples.first;
    });
    unawaited(_readSelectedImageSize());
    _revealSelectedThumbnail(jump: true);
  }

  void _selectSample(SavedSample sample) {
    setState(() {
      _fitMode = true;
      _selected = sample;
    });
    unawaited(_readSelectedImageSize());
    _revealSelectedThumbnail();
  }

  void _revealSelectedThumbnail({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_thumbnailScroll.hasClients || _selected == null) {
        return;
      }
      final index = _artistSamples.indexOf(_selected!);
      if (index < 0) return;

      const itemExtent = 72.0;
      final position = _thumbnailScroll.position;
      final itemStart = index * itemExtent;
      const thumbnailWidth = 64.0;
      final itemCenter = itemStart + thumbnailWidth / 2;
      final target = itemCenter - position.viewportDimension / 2;
      final offset = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ).toDouble();
      if ((offset - position.pixels).abs() < 0.5) return;
      if (jump) {
        _thumbnailScroll.jumpTo(offset);
      } else {
        _thumbnailScroll.animateTo(
          offset,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _scrollThumbnails(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_thumbnailScroll.hasClients) return;
    final delta = event.scrollDelta;
    // Horizontal trackpad/Magic Mouse input is handled by the ListView itself.
    // Map a conventional vertical mouse wheel to the horizontal thumbnail strip.
    if (delta.dy == 0 || delta.dx.abs() > delta.dy.abs()) return;
    final amount = delta.dy;
    final position = _thumbnailScroll.position;
    _thumbnailScroll.jumpTo(
      (position.pixels + amount).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ).toDouble(),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedPaths.clear();
      _selectionAnchorPath = null;
      if (_selectionMode && _selected != null) {
        final path = _selected!.file.path;
        _selectedPaths.add(path);
        _selectionAnchorPath = path;
      }
    });
    _keyboardFocus.requestFocus();
  }

  void _selectAllArtistSamples() {
    if (_artistSamples.isEmpty) return;
    setState(() {
      _selectionMode = true;
      _selectedPaths
        ..clear()
        ..addAll(_artistSamples.map((sample) => sample.file.path));
      _selectionAnchorPath = _selected?.file.path;
    });
  }

  void _handleThumbnailTap(SavedSample sample, int index) {
    final keyboard = HardwareKeyboard.instance;
    final additive = keyboard.isMetaPressed || keyboard.isControlPressed;
    final ranged = keyboard.isShiftPressed;
    if (!_selectionMode && !additive && !ranged) {
      _selectSample(sample);
      _keyboardFocus.requestFocus();
      return;
    }

    setState(() {
      _selectionMode = true;
      _fitMode = true;
      _selected = sample;
      final anchorIndex = _artistSamples.indexWhere(
        (item) => item.file.path == _selectionAnchorPath,
      );
      if (ranged && anchorIndex >= 0) {
        final start = math.min(anchorIndex, index);
        final end = math.max(anchorIndex, index);
        _selectedPaths.addAll(
          _artistSamples
              .sublist(start, end + 1)
              .map((item) => item.file.path),
        );
      } else {
        final path = sample.file.path;
        if (!_selectedPaths.remove(path)) _selectedPaths.add(path);
        _selectionAnchorPath = path;
      }
    });
    _keyboardFocus.requestFocus();
    unawaited(_readSelectedImageSize());
    _revealSelectedThumbnail();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || _searchFocused || _deleting) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if ((keyboard.isMetaPressed || keyboard.isControlPressed) &&
        key == LogicalKeyboardKey.keyA) {
      _selectAllArtistSamples();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _selectionMode) {
      _toggleSelectionMode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      unawaited(_deleteSelected());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(-1, showCue: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveSelection(1, showCue: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home && _artistSamples.isNotEmpty) {
      _selectSample(_artistSamples.first);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end && _artistSamples.isNotEmpty) {
      _selectSample(_artistSamples.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _deleteSelected() async {
    final sample = _selected;
    if (sample == null || _deleting) return;
    final targets = _selectionMode
        ? _artistSamples
              .where((item) => _selectedPaths.contains(item.file.path))
              .toList()
        : [sample];
    if (targets.isEmpty) return;
    final filenames = targets
        .map((item) => item.file.uri.pathSegments.last)
        .toList();
    final count = targets.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(count == 1 ? 'Delete sample?' : 'Delete $count samples?'),
        content: Text(
          count == 1
              ? '${filenames.first}\n\nThe PNG and its JSON metadata file will be permanently deleted.'
              : '$count selected PNG files and their JSON metadata files will be permanently deleted.',
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
    final deletedPaths = <String>{};
    final failures = <Exception>[];
    try {
      for (final target in targets) {
        try {
          await widget.storage.deleteSample(target);
          deletedPaths.add(target.file.path);
        } on Exception catch (error) {
          failures.add(error);
        }
      }
      if (!mounted) return;
      if (deletedPaths.isEmpty) {
        throw failures.first;
      }
      _selectAfterDeletion(
        sample,
        deletedPaths: deletedPaths,
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
        SnackBar(
          content: Text(
            failures.isEmpty
                ? 'Deleted ${deletedPaths.length} sample${deletedPaths.length == 1 ? '' : 's'} and metadata.'
                : 'Deleted ${deletedPaths.length}; ${failures.length} could not be deleted.',
          ),
        ),
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
    SavedSample reference, {
    required Set<String> deletedPaths,
    required int selectedIndex,
    required List<String> artistsBefore,
    required List<String> modelsBefore,
  }) {
    final remaining = _samples
        .where((sample) => !deletedPaths.contains(sample.file.path))
        .toList();
    String? nextModel = reference.modelId;
    String? nextArtist = reference.vaultGroupKey;
    SavedSample? nextSample;

    SavedSample? preserved;
    for (final sample in remaining) {
      if (sample.file.path == reference.file.path) {
        preserved = sample;
        break;
      }
    }
    if (preserved != null) nextSample = preserved;

    final sameArtist = remaining
        .where(
          (sample) =>
              sample.modelId == reference.modelId &&
              sample.vaultGroupKey == reference.vaultGroupKey &&
              _matchesSubjectFilter(sample),
        )
        .toList();
    if (nextSample == null) {
      if (sameArtist.isNotEmpty) {
        nextSample = sameArtist[math.min(selectedIndex, sameArtist.length - 1)];
      } else {
        final sameModel = remaining
            .where((sample) => sample.modelId == reference.modelId)
            .toList();
        if (sameModel.isNotEmpty) {
          nextArtist = _adjacentValue(
            current: reference.vaultGroupKey,
            previousOrder: artistsBefore,
            remaining: sameModel
                .map((sample) => sample.vaultGroupKey)
                .toSet(),
          );
          nextSample = sameModel.firstWhere(
            (sample) => sample.vaultGroupKey == nextArtist,
          );
        } else if (remaining.isNotEmpty) {
          nextModel = _adjacentValue(
            current: reference.modelId,
            previousOrder: modelsBefore,
            remaining: remaining.map((sample) => sample.modelId).toSet(),
          );
          nextSample = remaining.firstWhere(
            (sample) => sample.modelId == nextModel,
          );
          nextArtist = nextSample.vaultGroupKey;
        } else {
          nextModel = null;
          nextArtist = null;
        }
      }
    }

    setState(() {
      _samples = remaining;
      _selectionMode = false;
      _selectedPaths.clear();
      _selectionAnchorPath = null;
      _modelId = nextModel;
      _artist = nextArtist;
      _selected = nextSample;
    });
    _revealSelectedThumbnail();
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
    setState(() => _imageSize = null);
    _transform.value = Matrix4.identity();
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
      final imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      setState(() => _imageSize = imageSize);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    } on Exception {
      if (!mounted || sample != _selected) return;
      setState(() => _imageSize = null);
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

    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final minimumHeight = compact ? 920.0 : 460.0;
          final contentHeight = math.max(constraints.maxHeight, minimumHeight);
          return Scrollbar(
            controller: _pageScroll,
            thumbVisibility: constraints.maxHeight < minimumHeight,
            child: SingleChildScrollView(
              controller: _pageScroll,
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                height: contentHeight,
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 330, child: _buildCatalog()),
                          const SizedBox(height: 16),
                          Expanded(child: _buildViewer(wideInfo: false)),
                        ],
                      )
                    : _buildWideVault(constraints.maxWidth),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideVault(double width) {
    final wideInfo = width >= 1080;
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
          Focus(
            onFocusChange: (focused) => _searchFocused = focused,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Artist search',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<_SubjectFilter>(
            key: ValueKey(_subjectFilter),
            initialValue: _subjectFilter,
            decoration: const InputDecoration(labelText: 'Sample type'),
            isExpanded: true,
            items: _SubjectFilter.values
                .map(
                  (subject) => DropdownMenuItem(
                    value: subject,
                    child: Text(_subjectFilterLabel(subject)),
                  ),
                )
                .toList(),
            onChanged: _selectSubject,
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
                          .where((sample) => sample.vaultGroupKey == artist)
                          .length;
                      return ListTile(
                        selected: artist == _artist,
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        title: Text(
                          _artistLabel(artist),
                          overflow: TextOverflow.ellipsis,
                        ),
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

  String _subjectFilterLabel(_SubjectFilter subject) {
    final count = switch (subject) {
      _SubjectFilter.all => _allArtistSamples.length,
      _SubjectFilter.female => _allArtistSamples
          .where((sample) => sample.subject == SampleSubject.female)
          .length,
      _SubjectFilter.male => _allArtistSamples
          .where((sample) => sample.subject == SampleSubject.male)
          .length,
      _SubjectFilter.others => _allArtistSamples
          .where((sample) => sample.subject == SampleSubject.others)
          .length,
    };
    final label = switch (subject) {
      _SubjectFilter.all => 'All',
      _SubjectFilter.female => 'Female · 1girl',
      _SubjectFilter.male => 'Male · 1boy',
      _SubjectFilter.others => 'Others',
    };
    return '$label  ($count)';
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
                  _selectionMode
                      ? '${_selectedPaths.length} selected'
                      : sample?.vaultGroupLabel ?? 'IMAGE',
                  overflow: TextOverflow.ellipsis,
                  style: _sectionStyle,
                ),
              ),
              IconButton(
                tooltip: _selectionMode
                    ? 'Cancel multiple selection (Esc)'
                    : 'Select multiple images',
                onPressed: sample == null ? null : _toggleSelectionMode,
                color: _selectionMode
                    ? Theme.of(context).colorScheme.primary
                    : null,
                icon: Icon(
                  _selectionMode
                      ? Icons.library_add_check_rounded
                      : Icons.library_add_outlined,
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
                  tooltip: _selectionMode
                      ? 'Delete selected images and metadata'
                      : 'Delete image and metadata',
                  onPressed:
                      sample == null ||
                          (_selectionMode && _selectedPaths.isEmpty)
                      ? null
                      : _deleteSelected,
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
                        : _imageSize == null
                        ? const Center(child: CircularProgressIndicator())
                        : Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerSignal: _handlePointerSignal,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              trackpadScrollCausesScale: false,
                              onScaleStart: _startImageGesture,
                              onScaleUpdate: _updateImageGesture,
                              onScaleEnd: _endImageGesture,
                              onTap: _keyboardFocus.requestFocus,
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
                                        key: const Key('vault-main-image'),
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
          _buildViewerControls(sample),
          if (_artistSamples.length > 1) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 80,
              child: Scrollbar(
                controller: _thumbnailScroll,
                thumbVisibility: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Listener(
                    onPointerSignal: _scrollThumbnails,
                    child: ScrollConfiguration(
                      behavior: const _ThumbnailScrollBehavior(),
                      child: ListView.separated(
                        controller: _thumbnailScroll,
                        scrollDirection: Axis.horizontal,
                        itemCount: _artistSamples.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = _artistSamples[index];
                          final selected = _selectedPaths.contains(
                            item.file.path,
                          );
                          return InkWell(
                            onTap: () => _handleThumbnailTap(item, index),
                            child: SizedBox(
                              width: 64,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: selected || item == sample
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.white12,
                                        width: selected || item == sample
                                            ? 2
                                            : 1,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Image.file(
                                      item.file,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (selected)
                                    Positioned(
                                      top: 5,
                                      right: 5,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Padding(
                                          padding: EdgeInsets.all(3),
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewerControls(SavedSample? sample) {
    final index = sample == null ? -1 : _artistSamples.indexOf(sample);
    final navigation = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous image',
          onPressed: index <= 0
              ? null
              : () => _moveSelection(-1, showCue: true),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        SizedBox(
          width: 54,
          child: Text(
            sample == null
                ? '0 / 0'
                : '${index + 1} / ${_artistSamples.length}',
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          tooltip: 'Next image',
          onPressed: index < 0 || index >= _artistSamples.length - 1
              ? null
              : () => _moveSelection(1, showCue: true),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
    final zoom = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 400) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [navigation, zoom],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            navigation,
            const SizedBox(width: 12),
            const SizedBox(
              height: 22,
              child: VerticalDivider(width: 1, thickness: 1),
            ),
            const SizedBox(width: 12),
            zoom,
          ],
        );
      },
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
                    _InfoLine(
                      'Artist',
                      sample.artist,
                      copyValue: sample.isCustom ? null : sample.artistTags,
                    ),
                    if (sample.isCustom)
                      _InfoLine(
                        'Artists',
                        _customArtistSummary(sample) ?? 'See final prompt below',
                        copyValue: sample.artistTags,
                      ),
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
                label: Text(
                  sample.isCustom ? 'Load in Custom' : 'Load in Generate',
                ),
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

  String? _customArtistSummary(SavedSample sample) {
    final rawArtists = sample.metadata['customArtists'];
    if (rawArtists is! List) return null;
    final labels = rawArtists.map((raw) {
      if (raw is! Map) return null;
      final name = raw['name']?.toString().trim() ?? '';
      final weight = double.tryParse(raw['weight']?.toString() ?? '');
      if (name.isEmpty || weight == null) return null;
      return '$name (${weight.toStringAsFixed(2)})';
    }).whereType<String>();
    return labels.isEmpty ? null : labels.join(', ');
  }
}

class _ThumbnailScrollBehavior extends MaterialScrollBehavior {
  const _ThumbnailScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
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
  const _InfoLine(this.label, this.value, {this.copyValue});
  final String label;
  final String value;
  final String? copyValue;

  @override
  Widget build(BuildContext context) {
    final copyText = copyValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: const TextStyle(color: Colors.white38)),
          ),
          Expanded(child: SelectableText(value, textAlign: TextAlign.right)),
          if (copyText != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Copy artist tags',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(
                width: 28,
                height: 28,
              ),
              padding: EdgeInsets.zero,
              onPressed: copyText.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: copyText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Artist tags copied.')),
                      );
                    },
              icon: const Icon(Icons.copy_rounded, size: 15),
            ),
          ],
        ],
      ),
    );
  }
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
