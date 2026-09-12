import 'package:artist_tag_vault/src/models/app_settings.dart';
import 'package:artist_tag_vault/src/services/novelai_api.dart';
import 'package:flutter/material.dart';

/// Stores account-level settings. Generation controls live in Advanced.
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
  bool _testing = false;
  bool _obscureToken = true;
  TokenTestResult? _testResult;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.initialSettings.apiToken);
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
}
