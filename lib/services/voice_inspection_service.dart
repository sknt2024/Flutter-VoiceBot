// lib/services/voice_inspection_service.dart

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart' as audio;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http_parser/http_parser.dart' as hp;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'field_extractor.dart';


/// VoiceInspectionService: controls recorder, TTS, Whisper upload, sequence flow,
/// transcripts and field extraction. Use by UI to start/stop sequence or single field asks.
class VoiceInspectionService {
  final audio.Record _recorder = audio.Record();
  final FlutterTts _tts = FlutterTts();
  final Dio _dio;

  // Optional model-based field extractor (calls OpenAI chat completions)
  final FieldExtractor? extractor;

  // Notifiers for UI
  final ValueNotifier<bool> isRecording = ValueNotifier(false);
  final ValueNotifier<bool> isTranscribing = ValueNotifier(false);
  final ValueNotifier<bool> isSequenceRunning = ValueNotifier(false);
  final ValueNotifier<String> currentStepLabel = ValueNotifier('');
  final ValueNotifier<List<Map<String, dynamic>>> transcripts =
  ValueNotifier(<Map<String, dynamic>>[]);

  // selected whisper language (e.g. 'hi', 'en')
  String language = 'hi';

  VoiceInspectionService({Dio? dio, this.extractor})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://api.openai.com')) {
    _configureTts();
    final apiKey = _findApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $apiKey';
    }
  }

  String? _findApiKey() {
    const dartDefine = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
    if (dartDefine.isNotEmpty) return dartDefine;
    return dotenv.env['OPENAI_API_KEY'];
  }

  void _configureTts({String ttsLocale = 'en-IN'}) {
    try {
      _tts.setLanguage(ttsLocale);
      _tts.setSpeechRate(0.40);
      _tts.setPitch(1.0);
      _tts.setVolume(1.0);
      _tts.awaitSpeakCompletion(true);
    } catch (_) {}
  }

  /// Change whisper language and optionally TTS locale
  Future<void> setLanguage(String whisperCode, {String? ttsLocale}) async {
    language = whisperCode;
    if (ttsLocale != null) {
      try {
        await _tts.setLanguage(ttsLocale);
      } catch (_) {}
    }
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> recreateRecorder() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
    // new instance is created on startRecordingToFile when needed
  }

  /// Start recording into a temp file. Returns file path or null.
  Future<String?> startRecordingToFile() async {
    if (!await _ensureMicPermission()) return null;

    final tmp = await getTemporaryDirectory();
    final fname = 'rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    final path = '${tmp.path}/$fname';

    try {
      await _recorder.start(path: path, encoder: audio.AudioEncoder.wav);
    } catch (e) {
      await recreateRecorder();
      return null;
    }

    isRecording.value = true;
    return path;
  }

  /// Stops recorder and uploads to Whisper. Returns transcript string or null.
  Future<String?> stopAndTranscribe({String? overrideLanguage}) async {
    final path = await _recorder.stop();
    isRecording.value = false;

    if (path == null) return null;

    final apiKey = _findApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      // No key configured; can't transcribe
      return null;
    }

    isTranscribing.value = true;
    try {
      final formData = FormData.fromMap({
        "model": "whisper-1",
        "language": overrideLanguage ?? language,
        "file": await MultipartFile.fromFile(
          path,
          filename: "audio.wav",
          contentType: hp.MediaType("audio", "wav"),
        ),
      });

      final resp = await _dio.post('/v1/audio/transcriptions', data: formData);

      if (resp.statusCode == 200) {
        final text = resp.data['text']?.toString() ?? '';
        if (text.isNotEmpty) {
          final entry = {
            'text': text,
            'time': DateTime.now(),
            'language': overrideLanguage ?? language
          };
          final list = List<Map<String, dynamic>>.from(transcripts.value);
          list.insert(0, entry);
          transcripts.value = list;
        }
        return resp.data['text']?.toString();
      } else {
        return null;
      }
    } catch (e) {
      return null;
    } finally {
      isTranscribing.value = false;
      // cleanup file
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  /// Ask question via TTS, record for recordSeconds, transcribe and return raw transcript.
  Future<String?> askRecordAndTranscribe({
    required String question,
    int recordSeconds = 4,
    String? overrideLanguage,
  }) async {
    await speak(question);
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}

    final started = await startRecordingToFile();
    if (started == null) return null;

    int elapsed = 0;
    while (elapsed < recordSeconds && isSequenceRunning.value) {
      await Future.delayed(const Duration(seconds: 1));
      elapsed++;
    }

    final txt = await stopAndTranscribe(overrideLanguage: overrideLanguage);
    return txt;
  }

  /// Primary method used by UI: asks and tries to extract numeric value for a named field.
  /// Logic:
  /// 1) Ask + transcribe using Whisper -> rawTranscript
  /// 2) If extractor is provided: call extractor.extractField(fieldLabel, rawTranscript)
  ///    - if extractor returns numeric string -> use it
  ///    - if extractor returns 'RETRY' -> returns null so caller can retry
  /// 3) If extractor not provided or returned null -> fallback to regex numeric extraction from rawTranscript
  Future<String?> askAndExtractField({
    required String fieldLabel,
    required String question,
    int recordSeconds = 4,
    String? overrideLanguage,
    String extractorModel = 'gpt-4o',
  }) async {
    final raw = await askRecordAndTranscribe(
      question: question,
      recordSeconds: recordSeconds,
      overrideLanguage: overrideLanguage,
    );

    if (raw == null || raw.isEmpty) return null;

    // If extractor provided, prefer model extraction
    if (extractor != null) {
      try {
        final extracted = await extractor!.extractField(
          fieldLabel: fieldLabel,
          userText: raw,
          model: extractorModel,
        );
        if (extracted == null) {
          // extractor error -> fallback to regex
        } else if (extracted.toUpperCase().trim() == 'RETRY') {
          // signal caller to re-ask (we return null)
          return null;
        } else {
          // numeric extracted
          return extracted;
        }
      } catch (e) {
        // log or ignore, fallback to regex extraction
      }
    }

    // fallback: regex numeric extraction
    final fallback = _extractNumeric(raw);
    return fallback ?? raw.trim();
  }

  String? _extractNumeric(String s) {
    final regex = RegExp(r'[-+]?\d+(?:\.\d+)?');
    final m = regex.firstMatch(s);
    return m?.group(0);
  }

  /// Sequence runner: fields is list of pairs (label, question). For each field:
  /// - askAndExtractField is called
  /// - onFieldFilled(label, value) is invoked when a value is obtained
  /// - if a field returns null (meaning extractor said RETRY or nothing), the sequence will continue
  Future<void> startSequence({
    required List<FieldSpec> fields,
    int recordSecondsPerField = 4,
    void Function(String label)? onStepStart,
    void Function(String label, String value)? onFieldFilled,
    void Function()? onComplete,
    String extractorModel = 'gpt-4o',
  }) async {
    if (isTranscribing.value || isSequenceRunning.value) return;
    isSequenceRunning.value = true;

    try {
      for (final f in fields) {
        if (!isSequenceRunning.value) break;

        currentStepLabel.value = f.label;
        if (onStepStart != null) onStepStart(f.label);

        final val = await askAndExtractField(
          fieldLabel: f.label,
          question: f.question,
          recordSeconds: recordSecondsPerField,
          extractorModel: extractorModel,
        );

        if (val != null && val.isNotEmpty) {
          if (onFieldFilled != null) onFieldFilled(f.label, val);
        }

        // tiny pause between fields
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (isSequenceRunning.value) {
        await speak("Inspection complete.");
        if (onComplete != null) onComplete();
      }
    } finally {
      isSequenceRunning.value = false;
      currentStepLabel.value = '';
    }
  }

  void stopSequence() {
    isSequenceRunning.value = false;
    currentStepLabel.value = '';
    try {
      _recorder.stop();
    } catch (_) {}
  }

  void dispose() {
    try {
      _recorder.dispose();
    } catch (_) {}
    _tts.stop();
    isRecording.dispose();
    isTranscribing.dispose();
    isSequenceRunning.dispose();
    currentStepLabel.dispose();
    transcripts.dispose();
  }
}

/// Lightweight field spec used by the service
class FieldSpec {
  final String label;
  final String question;
  const FieldSpec(this.label, this.question);
}
