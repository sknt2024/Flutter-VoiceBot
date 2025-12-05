import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// A small wrapper to call OpenAI and extract numeric values from Hindi or English (Indian accent) input.
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
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 10),
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
  /// userText: the transcription text returned by Whisper (Hindi or English, Indian accent).
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
      "max_tokens": 40,
    };

    try {
      final resp = await _dio
          .post('/v1/chat/completions', data: jsonEncode(payload))
          .timeout(Duration(seconds: timeoutSeconds));

      if (resp.statusCode == 200) {
        final data = resp.data;
        final content = _parseChoiceContent(data);
        if (content == null) return null;

        final trimmed = content.trim();

        // If model explicitly returned RETRY
        if (_isRetryValue(trimmed)) return 'RETRY';

        // Defensively extract numeric token if model returned extra text
        final numeric = _extractNumeric(trimmed);
        if (numeric != null) return numeric;

        // If response includes spelled-out number words (rare because prompt asks numeric),
        // we still request RETRY so caller can re-ask or fall back.
        return 'RETRY';
      } else {
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
    // Prompt handles Hindi spoken numbers, English words (Indian accent) and numerals.
    // Instruct model to return ONLY numeric value or RETRY.
    return '''
You are a strict extractor. Extract only the ${fieldLabel} numeric value from the user's input.
The user may speak in Hindi OR English (Indian accent). They may say numbers as words ("35 point six", "पैंतीस पॉइंट छह")
or provide numerals ("35.6", "35", "35°C"). Accept both. Convert spoken words to numeric format.

Requirements (be strict):
 - If you can extract a clear numeric value, return ONLY that number (digits, optionally with decimal), e.g. 35 or 35.6
 - If you cannot confidently extract a numeric value, return ONLY the single word RETRY (uppercase)
 - Do NOT return any extra text, punctuation, or explanation.

Examples (valid outputs shown after ->):
  Hindi spoken:
    "पैंतीस पॉइंट छह डिग्री" -> 35.6
    "चौंतीस" -> 34
  English (Indian accent):
    "thirty five point six" -> 35.6
    "thirty five" -> 35
  Mixed / numerals:
    "35.6 degrees" -> 35.6
    "35°C" -> 35

Edge cases:
 - If the user says multiple numbers, try to pick the number that best matches the context for ${fieldLabel}. If ambiguous, respond RETRY.
 - If the user says non-numeric words only, respond RETRY.

Return ONLY the numeric value or RETRY, and nothing else.
''';
  }

  String? _parseChoiceContent(dynamic data) {
    try {
      if (data is Map &&
          data['choices'] != null &&
          data['choices'].isNotEmpty) {
        final first = data['choices'][0];
        if (first != null) {
          if (first['message'] != null && first['message']['content'] != null) {
            return first['message']['content'] as String;
          }
          if (first['text'] != null) return first['text'] as String;
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isRetryValue(String v) {
    return v.toUpperCase().trim() == 'RETRY';
  }

  String? _extractNumeric(String s) {
    // Attempt to pick the first numeric token (handles "35.6", "35", "35°C")
    final regex = RegExp(r'[-+]?\d+(?:\.\d+)?');
    final m = regex.firstMatch(s);
    return m?.group(0);
  }
}
