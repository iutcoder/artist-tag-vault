import 'package:artist_tag_vault/src/models/app_settings.dart';
import 'package:artist_tag_vault/src/services/danbooru_autocomplete.dart';
import 'package:artist_tag_vault/src/services/novelai_api.dart';
import 'package:flutter/material.dart';

/// Stores account-level settings. Generation controls live in Advanced.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    required this.initialSettings,
    required this.api,
    required this.artistDictionary,
    super.key,
  });

  final AppSettings initialSettings;
  final NovelAiApi api;
  final DanbooruAutocompleteService artistDictionary;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _token;
  bool _testing = false;
  bool _obscureToken = true;
  TokenTestResult? _testResult;
  DanbooruDictionaryStatus? _dictionaryStatus;
  bool _updatingDictionary = false;
  int _downloadedArtists = 0;
  String? _dictionaryError;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.initialSettings.apiToken);
    _loadDictionaryStatus();
  }

  @override
  void dispose() {
    _token.dispose();
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

  Future<void> _loadDictionaryStatus() async {
    final status = await widget.artistDictionary.status();
    if (mounted) setState(() => _dictionaryStatus = status);
  }

  Future<void> _updateDictionary() async {
    setState(() {
      _updatingDictionary = true;
      _downloadedArtists = 0;
      _dictionaryError = null;
    });
    try {
      final status = await widget.artistDictionary.updateDictionary(
        onProgress: (count) {
          if (mounted) setState(() => _downloadedArtists = count);
        },
      );
      if (!mounted) return;
      setState(() => _dictionaryStatus = status);
    } on Exception catch (error) {
      if (mounted) setState(() => _dictionaryError = error.toString());
    } finally {
      if (mounted) setState(() => _updatingDictionary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _testResult?.success == true
        ? Colors.greenAccent
        : _testResult == null
        ? Colors.white54
        : Colors.redAccent;

    return AlertDialog(
      title: const Text('App settings'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _token,
              obscureText: _obscureToken,
              decoration: InputDecoration(
                labelText: 'NovelAI API token',
                suffixIcon: IconButton(
                  tooltip: _obscureToken ? 'Show token' : 'Hide token',
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                  icon: Icon(
                    _obscureToken
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _testing ? null : _testToken,
              icon: _testing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cable_rounded),
              label: const Text('Test connection'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _testResult?.success == true
                      ? Icons.check_circle_rounded
                      : _testResult == null
                      ? Icons.lock_outline_rounded
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
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              'DANBOORU ARTIST DICTIONARY',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _updatingDictionary ? null : _updateDictionary,
              icon: _updatingDictionary
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(
                _updatingDictionary
                    ? 'Downloading… $_downloadedArtists artists'
                    : _dictionaryStatus?.isAvailable == true
                    ? 'Update artist dictionary'
                    : 'Download artist dictionary',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _dictionaryError != null
                      ? Icons.error_outline_rounded
                      : _dictionaryStatus?.isAvailable == true
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 17,
                  color: _dictionaryError != null
                      ? Colors.redAccent
                      : _dictionaryStatus?.isAvailable == true
                      ? Colors.greenAccent
                      : Colors.white54,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _dictionaryError ?? _dictionaryStatusLabel(),
                    style: TextStyle(
                      color: _dictionaryError != null
                          ? Colors.redAccent
                          : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(widget.initialSettings.copyWith(apiToken: _token.text.trim())),
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _dictionaryStatusLabel() {
    final status = _dictionaryStatus;
    if (status == null) return 'Checking the local dictionary…';
    if (!status.isAvailable) {
      return 'Not downloaded · artist autocomplete is disabled.';
    }
    final updatedAt = status.updatedAt?.toLocal();
    final date = updatedAt == null
        ? 'update time unknown'
        : '${updatedAt.year.toString().padLeft(4, '0')}-'
              '${updatedAt.month.toString().padLeft(2, '0')}-'
              '${updatedAt.day.toString().padLeft(2, '0')} '
              '${updatedAt.hour.toString().padLeft(2, '0')}:'
              '${updatedAt.minute.toString().padLeft(2, '0')}';
    return '${status.artistCount} artists · updated $date';
  }
}
