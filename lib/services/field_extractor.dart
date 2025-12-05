import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// A small wrapper to call OpenAI and extract numeric values from Hindi input.
/// Returns either numeric string (e.g. "35.6") or the literal string "RETRY".
class FieldExtractor {
  final Dio _dio;

  /// Provide optional Dio instance for testing. Will read OPENAI_API_KEY from dotenv.
  FieldExtractor({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.openai.com',
              connectTimeout: Duration(seconds: 5),
              receiveTimeout: Duration(seconds: 5),
            ),
          ) {
    final apiKey = _findApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'OPENAI_API_KEY is not set. Put it in .env or dart-define.',
      );
    }
    _dio.options.headers['Authorization'] = 'Bearer $apiKey';
    _dio.options.headers['Content-Type'] = 'application/json';
  }

  String? _findApiKey() {
    // prefer dart-define first, then dotenv
    const dartDefine = String.fromEnvironment(
      'OPENAI_API_KEY',
      defaultValue: '',
    );
    if (dartDefine.isNotEmpty) return dartDefine;
    return dotenv.env['OPENAI_API_KEY'];
  }

  /// Generic extractor for any field label (Temperature, Pressure, G1, ...)
  /// userText: the transcription text returned by Whisper (Hindi).
  /// Returns: numeric string (e.g. "35.6") or "RETRY" or null on error.
  Future<String?> extractField({
    required String fieldLabel,
    required String userText,
    String model = 'gpt-4o',
    int timeoutSeconds = 20,
  }) async {
    final systemPrompt = _buildSystemPromptFor(fieldLabel);

    final payload = {
      "model": model,
      "messages": [
        {"role": "system", "content": systemPrompt},
        {"role": "user", "content": userText},
      ],
      // low temperature for deterministic numeric extraction
      "temperature": 0.0,
      "max_tokens": 32,
    };

    try {
      final resp = await _dio
          .post('/v1/chat/completions', data: jsonEncode(payload))
          .timeout(Duration(seconds: timeoutSeconds));

      if (resp.statusCode == 200) {
        final data = resp.data;
        // Chat completions: choices[0].message.content
        final content = _parseChoiceContent(data);
        if (content == null) return null;

        final trimmed = content.trim();

        // The model is instructed to return ONLY numeric value or RETRY.
        // But be defensive: extract numeric pattern if present.
        if (_isRetryValue(trimmed)) return 'RETRY';
        final numeric = _extractNumeric(trimmed);
        if (numeric != null) return numeric;

        // If model returned something else (e.g. words), return RETRY so caller can re-ask.
        return 'RETRY';
      } else {
        // Non-200
        return null;
      }
    } on TimeoutException {
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Batch extractor: calls extractField for each field (concurrent).
  /// fields is list of field labels in the exact wording you want (e.g. ["Temperature", "Pressure", "G1"...])
  /// Returns a map of field -> value (value could be numeric string or "RETRY" or null on error).
  Future<Map<String, String?>> extractFieldsFromText({
    required String userText,
    required List<String> fields,
    String model = 'gpt-4o',
  }) async {
    final futures = <Future<MapEntry<String, String?>>>[];
    for (final f in fields) {
      futures.add(
        extractField(
          fieldLabel: f,
          userText: userText,
          model: model,
        ).then((val) => MapEntry(f, val)),
      );
    }

    final results = await Future.wait(futures);
    return Map.fromEntries(results);
  }

  // ---- helpers ----

  String _buildSystemPromptFor(String fieldLabel) {
    // Keep prompt strict: convert Hindi spoken numbers -> numeric. Return ONLY number or RETRY.
    return '''
You are a helpful assistant. Extract only the $fieldLabel value from the user's input.
The user will speak in Hindi. Convert Hindi spoken numbers into numeric format.
Examples:
  "पैंतीस पॉइंट छह" -> 35.6
  "चौंतीस" -> 34
  "छप्पन दशमलव आठ" -> 56.8
If a clear numeric value for $fieldLabel cannot be found, respond ONLY with the word RETRY (without quotes).
Return ONLY the numeric value (or RETRY), nothing else.
''';
  }

  String? _parseChoiceContent(dynamic data) {
    try {
      // try common chat completion shape
      if (data is Map &&
          data['choices'] != null &&
          data['choices'].isNotEmpty) {
        final first = data['choices'][0];
        if (first != null) {
          // new OpenAI returns {'message': {'role':..., 'content': '...'}}
          if (first['message'] != null && first['message']['content'] != null) {
            return first['message']['content'] as String;
          }
          // some older variants: first['text']
          if (first['text'] != null) return first['text'] as String;
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isRetryValue(String v) {
    return v.toUpperCase() == 'RETRY';
  }

  String? _extractNumeric(String s) {
    final regex = RegExp(r'[-+]?\d+(\.\d+)?');
    final m = regex.firstMatch(s);
    return m?.group(0);
  }
}
