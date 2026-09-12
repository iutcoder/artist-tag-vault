import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:artist_tag_vault/src/models/account_usage.dart';
import 'package:artist_tag_vault/src/models/generation_preset.dart';
import 'package:http/http.dart' as http;

/// Result returned by NovelAI's JSON image response.
class GeneratedImage {
  const GeneratedImage({required this.bytes, required this.seed});

  final Uint8List bytes;
  final int seed;
}

/// Small HTTP client based on NovelAI's public Image API OpenAPI document.
class NovelAiApi {
  NovelAiApi({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _generationUri =
      Uri.parse('https://image.novelai.net/ai/generate-image');
  static final Uri _subscriptionUri =
      Uri.parse('https://image.novelai.net/user/subscription');

  final http.Client _client;

  /// Performs a non-generation account request so testing does not spend Anlas.
  Future<TokenTestResult> testToken(String token) async {
    if (token.trim().isEmpty) {
      return const TokenTestResult(false, '토큰을 먼저 입력해 주세요.');
    }

    try {
      final response = await _client.get(
        _subscriptionUri,
        headers: _headers(token),
      ).timeout(const Duration(seconds: 20));

      return switch (response.statusCode) {
        200 => const TokenTestResult(true, 'NovelAI 연결에 성공했습니다.'),
        401 => const TokenTestResult(false, '토큰이 유효하지 않습니다.'),
        _ => TokenTestResult(
            false,
            '연결 확인 실패 (HTTP ${response.statusCode})',
          ),
      };
    } on Exception catch (error) {
      return TokenTestResult(false, '네트워크 오류: $error');
    }
  }

  /// Reads both Image Anlas balances and the rechargeable V5 allowance.
  Future<AccountUsage> fetchAccountUsage(String token) async {
    if (token.trim().isEmpty) {
      throw const NovelAiApiException('NovelAI API 토큰이 없습니다.');
    }

    final response = await _client.get(
      _subscriptionUri,
      headers: _headers(token),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NovelAiApiException(_readError(response));
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return AccountUsage.fromJson(decoded as Map<String, dynamic>);
    } on Exception catch (error) {
      throw NovelAiApiException('사용량 응답을 해석하지 못했습니다: $error');
    }
  }

  /// Requests one PNG using the standardized artist-comparison preset.
  Future<GeneratedImage> generate({
    required String token,
    required String prompt,
    required GenerationPreset preset,
  }) async {
    final seed = Random.secure().nextInt(0x7fffffff);
    final parameters = <String, Object>{
      'params_version': 3,
      'width': preset.width,
      'height': preset.height,
      'steps': preset.steps,
      'scale': preset.guidance,
      'cfg_rescale': preset.guidanceRescale,
      'sampler': preset.sampler.apiId,
      'noise_schedule': preset.noiseSchedule.apiId,
      'seed': seed,
      'n_samples': 1,
      'prompt': prompt,
      'negative_prompt': preset.undesiredContent,
      'image_format': 'png',
    };

    // V4+ structured captions are part of the public request schema. Character
    // captions stay empty because this app deliberately compares one base tag.
    if (preset.model != NovelAiModel.animeV3) {
      parameters.addAll({
        'v4_prompt': {
          'caption': {'base_caption': prompt, 'char_captions': <Object>[]},
          'use_coords': false,
          'use_order': true,
        },
        'v4_negative_prompt': {
          'caption': {
            'base_caption': preset.undesiredContent,
            'char_captions': <Object>[],
          },
          'legacy_uc': false,
        },
      });
    }

    final response = await _client
        .post(
          _generationUri,
          headers: _headers(token),
          body: jsonEncode({
            'action': 'generate',
            'input': prompt,
            'model': preset.model.apiId,
            'parameters': parameters,
          }),
        )
        .timeout(const Duration(minutes: 3));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NovelAiApiException(_readError(response));
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final images = (decoded as Map<String, dynamic>)['images'] as List<dynamic>;
      final image = images.first as Map<String, dynamic>;
      final encoded = image['image'] as String;
      final base64Value = encoded.contains(',') ? encoded.split(',').last : encoded;
      return GeneratedImage(
        bytes: base64Decode(base64Value),
        seed: (image['seed'] as num?)?.toInt() ?? seed,
      );
    } on Exception catch (error) {
      throw NovelAiApiException('이미지 응답을 해석하지 못했습니다: $error');
    }
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  String _readError(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic>) {
        final message = body['message'] ?? body['error'];
        if (message != null) {
          return 'NovelAI 요청 실패 (HTTP ${response.statusCode}): $message';
        }
      }
    } on Exception {
      // Fall through to a stable message when the server returns non-JSON text.
    }
    return 'NovelAI 요청 실패 (HTTP ${response.statusCode})';
  }
}

class TokenTestResult {
  const TokenTestResult(this.success, this.message);
  final bool success;
  final String message;
}

class NovelAiApiException implements Exception {
  const NovelAiApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
