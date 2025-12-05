import 'package:flutter/material.dart';
import 'package:record/record.dart' as audio;
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' as hp;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';

import '../services/field_extractor.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  audio.Record _recorder = audio.Record();
  final FlutterTts _tts = FlutterTts();

  bool _isRecording = false;
  bool _isTranscribing = false;

  // sequence running flag & step label
  bool _isSequenceRunning = false;
  String _currentStepLabel = '';

  // groove count: change to 3 if you want only 3 grooves
  int grooveCount = 4;

  // controllers for fields
  final TextEditingController _tempController = TextEditingController();
  final TextEditingController _pressureController = TextEditingController();
  final TextEditingController _g1Controller = TextEditingController();
  final TextEditingController _g2Controller = TextEditingController();
  final TextEditingController _g3Controller = TextEditingController();
  final TextEditingController _g4Controller = TextEditingController();

  // FocusNodes that DO NOT request focus so keyboard won't open
  final FocusNode _noFocusTemp = FocusNode(canRequestFocus: false);
  final FocusNode _noFocusPressure = FocusNode(canRequestFocus: false);
  final FocusNode _noFocusG1 = FocusNode(canRequestFocus: false);
  final FocusNode _noFocusG2 = FocusNode(canRequestFocus: false);
  final FocusNode _noFocusG3 = FocusNode(canRequestFocus: false);
  final FocusNode _noFocusG4 = FocusNode(canRequestFocus: false);

  // Field extractor instance (wraps OpenAI call to normalize Hindi numbers)
  FieldExtractor? _extractor;
  bool _extractorAvailable = false;

  @override
  void initState() {
    super.initState();
    _configureTts();

    // create extractor - if it fails (no API key) we'll disable extractor and fallback to regex
    try {
      _extractor = FieldExtractor();
      _extractorAvailable = true;
    } catch (e, s) {
      debugPrint('FieldExtractor init failed: $e\n$s');
      _extractorAvailable = false;
    }
  }

  void _configureTts() {
    _tts.setLanguage("en-IN");
    _tts.setSpeechRate(0.4);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);
    try {
      _tts.awaitSpeakCompletion(true);
    } catch (_) {}
  }

  Future<String?> _getApiKey() async {
    // prefer dart-define first, fallback to dotenv
    const dartDefineKey = String.fromEnvironment(
      'OPENAI_API_KEY',
      defaultValue: '',
    );
    if (dartDefineKey.isNotEmpty) return dartDefineKey;

    final key = dotenv.env["OPENAI_API_KEY"];
    if (key == null || key.isEmpty) {
      return null;
    }
    return key;
  }

  Future<void> _recreateRecorder() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
    _recorder = audio.Record();
  }

  Future<bool> _startRecording() async {
    if (_isTranscribing) {
      // don't start recording while transcribing
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait — transcription in progress'),
        ),
      );
      return false;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Microphone permission denied")),
      );
      return false;
    }

    final tempDir = await getTemporaryDirectory();
    final filePath =
        "${tempDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav";

    try {
      await _recorder.start(path: filePath, encoder: audio.AudioEncoder.wav);
    } on PlatformException catch (_) {
      await _recreateRecorder();
      return false;
    } catch (e) {
      debugPrint('startRecording error: $e');
      await _recreateRecorder();
      return false;
    }

    setState(() {
      _isRecording = true;
    });
    return true;
  }

  Future<String?> _stopAndTranscribe({String language = "hi"}) async {
    // Stop recording first
    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (path == null) return null;

      final apiKey = await _getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('OPENAI_API_KEY not set')));
        return null;
      }

      // set transcribing state
      setState(() => _isTranscribing = true);

      final dio = Dio(
        BaseOptions(
          baseUrl: "https://api.openai.com",
          headers: {"Authorization": "Bearer $apiKey"},
        ),
      );

      /// whisper-1, gpt-4o-transcribe
      final formData = FormData.fromMap({
        "model": "gpt-4o-transcribe",
        "language": language,
        "file": await MultipartFile.fromFile(
          path,
          filename: "audio.wav",
          contentType: hp.MediaType("audio", "wav"),
        ),
      });

      final response = await dio.post(
        "/v1/audio/transcriptions",
        data: formData,
      );

      if (response.statusCode == 200) {
        final text = response.data["text"]?.toString();
        return text;
      } else {
        debugPrint('Whisper error: ${response.statusCode} ${response.data}');
        return null;
      }
    } catch (e, s) {
      debugPrint('Transcription error: $e\n$s');
      return null;
    } finally {
      // always clear loading state
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  /// Ask question, record, transcribe and return transcription (or null).
  /// This returns raw text (not numeric-extracted).
  Future<String?> _askRecordAndExtractRaw({
    required String question,
    String language = "hi",
    int recordSeconds = 5,
  }) async {
    // speak
    await _tts.stop();
    await _tts.speak(question);
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // start recording
    final started = await _startRecording();
    if (!started) return null;

    // record for N seconds (user can cancel sequence)
    int elapsed = 0;
    while (elapsed < recordSeconds && _isSequenceRunning) {
      await Future.delayed(const Duration(seconds: 1));
      elapsed++;
    }

    // stop and transcribe
    final txt = await _stopAndTranscribe(language: language);
    if (txt == null || txt.isEmpty) return null;
    return txt;
  }

  /// Speak what was heard and show Accept / Retry dialog.
  /// Returns true if user accepted, false if retry requested.
  Future<bool> _confirmHeard(String heard, String humanLabel) async {
    // Speak: "I heard {heard}. Do you want to accept or retry?"
    final speakText =
        "I heard $heard for $humanLabel. Tap accept if correct, or retry to record again.";
    try {
      await _tts.stop();
      await _tts.speak(speakText);
      // don't block on awaitSpeakCompletion here — dialog is shown immediately so user can tap
    } catch (_) {}

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Confirm $humanLabel'),
          content: Text('Heard: "$heard"\n\nAccept this value or Retry?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // retry
              },
              child: const Text('Retry'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true); // accept
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  /// Wrapper which will ask, transcribe, confirm with user, and retry up to attempts.
  /// Uses FieldExtractor when available to convert Hindi spoken numbers to numeric strings.
  /// Returns the accepted numeric string or null if user cancels / no value.
  /// Wrapper which will ask, transcribe, extract and retry up to attempts.
  /// Uses FieldExtractor when available to convert Hindi spoken numbers to numeric strings.
  /// Returns the accepted numeric string or null if attempts exhausted / no value.
  Future<String?> _askConfirmAndFill({
    required String question,
    required String humanLabel,
    required TextEditingController controller,
    String language = "hi",
    int recordSeconds = 2,
    int maxAttempts = 3,
  }) async {
    int attempt = 0;
    while (attempt < maxAttempts && _isSequenceRunning) {
      attempt++;

      final raw = await _askRecordAndExtractRaw(
        question: question,
        language: language,
        recordSeconds: recordSeconds,
      );

      if (raw == null || raw.isEmpty) {
        // nothing transcribed — automatically retry until attempts exhausted
        debugPrint('No transcription for $humanLabel (attempt $attempt/$maxAttempts)');
        continue; // retry
      }

      // If extractor available, prefer it.
      String? numeric;
      if (_extractorAvailable && _extractor != null) {
        try {
          // Use first token of label as extractor fieldLabel (e.g. "Temperature")
          final fieldToken = humanLabel.split(' ').first;
          final extracted = await _extractor!.extractField(
            fieldLabel: fieldToken,
            userText: raw,
          );

          if (extracted != null && extracted.toUpperCase() == 'RETRY') {
            // extractor asked to retry -> continue attempts automatically
            debugPrint('Extractor requested RETRY for $humanLabel (raw="$raw")');
            continue;
          }

          if (extracted != null && extracted.isNotEmpty) {
            numeric = extracted;
          }
        } catch (e, s) {
          debugPrint('FieldExtractor failed: $e\n$s');
          numeric = null;
        }
      }

      // fallback to simple regex extraction if extractor not available or returned null
      numeric ??= _extractNumericOnly(raw);

      // If we have a numeric value (or fallback raw), accept it immediately (no dialog)
      if ((numeric != null && numeric.isNotEmpty) || raw.isNotEmpty) {
        final valueToSet = (numeric != null && numeric.isNotEmpty) ? numeric : raw;
        controller.text = valueToSet;
        debugPrint('Auto-accepted $humanLabel => $valueToSet (attempt $attempt/$maxAttempts)');
        return valueToSet;
      }

      // otherwise retry loop
    }

    // attempts exhausted or sequence cancelled
    debugPrint('Attempts exhausted for $humanLabel');
    return null;
  }

  /// Start inspection sequence - iterates through fields one-by-one
  Future<void> _startInspectionSequence() async {
    if (_isTranscribing || _isSequenceRunning) {
      // either already running or uploading
      return;
    }

    setState(() {
      _isSequenceRunning = true;
    });

    // define the ordered list of (label, question, controller, language)
    final List<_FieldSpec> fields = [
      _FieldSpec(
        'Temperature (°C)',
        'Please say the temperature value in degrees Celsius.',
        _tempController,
        'hi',
      ),
      _FieldSpec(
        'Pressure (PSI)',
        'Please say the pressure value in PSI.',
        _pressureController,
        'hi',
      ),
      _FieldSpec(
        'G1 (mm)',
        'Please say G1 reading in millimetres.',
        _g1Controller,
        'hi',
      ),
      _FieldSpec(
        'G2 (mm)',
        'Please say G2 reading in millimetres.',
        _g2Controller,
        'hi',
      ),
      _FieldSpec(
        'G3 (mm)',
        'Please say G3 reading in millimetres.',
        _g3Controller,
        'hi',
      ),
      // G4 is conditional
    ];

    if (grooveCount >= 4) {
      fields.add(
        _FieldSpec(
          'G4 (mm)',
          'Please say G4 reading in millimetres.',
          _g4Controller,
          'hi',
        ),
      );
    }

    try {
      for (int i = 0; i < fields.length; i++) {
        if (!_isSequenceRunning) break; // user cancelled

        final spec = fields[i];

        // show step label on overlay
        setState(() {
          _currentStepLabel = spec.label;
        });

        // ask, record, confirm & fill
        await _askConfirmAndFill(
          question: spec.question,
          humanLabel: spec.label,
          controller: spec.controller,
          language: spec.language,
          recordSeconds: 5,
          maxAttempts: 3,
        );

        // small pause before next
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // completed sequence
      if (_isSequenceRunning) {
        // optional: speak a completion message
        try {
          await _tts.speak("Inspection complete.");
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Inspection sequence error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inspection sequence failed.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSequenceRunning = false;
          _currentStepLabel = '';
        });
      }
    }
  }

  /// Stop/cancel running sequence
  void _stopInspectionSequence() {
    setState(() {
      _isSequenceRunning = false;
      _currentStepLabel = '';
    });

    // also ensure recorder stopped
    try {
      _recorder.stop();
    } catch (_) {}
  }

  String? _extractNumericOnly(String text) {
    // Matches numbers like 89, 60, 4.6, 32.75 etc.
    final regex = RegExp(r'(\d+(\.\d+)?)');
    final match = regex.firstMatch(text);
    if (match != null) {
      return match.group(0);
    }
    return null;
  }

  Widget _voiceField({
    required String label,
    required String question,
    required TextEditingController controller,
    required FocusNode focusNode,
    String language = "hi",
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          readOnly: true,
          showCursor: false,
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.teal, width: 2),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
          onTap: () => _askConfirmAndFill(
            question: question,
            humanLabel: label,
            controller: controller,
            language: language,
            recordSeconds: 2,
            maxAttempts: 3,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _recorder.dispose();
    _tts.stop();
    _tempController.dispose();
    _pressureController.dispose();
    _g1Controller.dispose();
    _g2Controller.dispose();
    _g3Controller.dispose();
    _g4Controller.dispose();
    _noFocusTemp.dispose();
    _noFocusPressure.dispose();
    _noFocusG1.dispose();
    _noFocusG2.dispose();
    _noFocusG3.dispose();
    _noFocusG4.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // build UI with a stack to overlay transcribing loader
    return Scaffold(
      appBar: AppBar(title: const Text("Whisper Voice Inputs")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_isSequenceRunning) {
            _stopInspectionSequence();
          } else {
            // start only if not transcribing
            _startInspectionSequence();
          }
        },
        icon: Icon(_isSequenceRunning ? Icons.stop : Icons.play_arrow),
        label: Text(
          _isSequenceRunning ? 'Stop Inspection' : 'Start Inspection',
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _voiceField(
                          label: "Temperature (°C)",
                          question:
                          "Please say the temperature value in degrees Celsius.",
                          controller: _tempController,
                          focusNode: _noFocusTemp,
                          language: "hi",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _voiceField(
                          label: "Pressure (PSI)",
                          question: "Please say the pressure value in PSI.",
                          controller: _pressureController,
                          focusNode: _noFocusPressure,
                          language: "hi",
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _voiceField(
                          label: "G1 (mm)",
                          question: "Please say G1 reading in millimetres.",
                          controller: _g1Controller,
                          focusNode: _noFocusG1,
                          language: "hi",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _voiceField(
                          label: "G2 (mm)",
                          question: "Please say G2 reading in millimetres.",
                          controller: _g2Controller,
                          focusNode: _noFocusG2,
                          language: "hi",
                        ),
                      ),
                      const SizedBox(width: 12),

                      Expanded(
                        child: _voiceField(
                          label: "G3 (mm)",
                          question: "Please say G3 reading in millimetres.",
                          controller: _g3Controller,
                          focusNode: _noFocusG3,
                          language: "hi",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _voiceField(
                          label: "G4 (mm)",
                          question: "Please say G4 reading in millimetres.",
                          controller: _g4Controller,
                          focusNode: _noFocusG4,
                          language: "hi",
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // translucent overlay while transcribing or during sequence
          AnimatedOpacity(
            opacity: (_isTranscribing || _isSequenceRunning) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !(_isTranscribing || _isSequenceRunning),
              child: Container(
                color: Colors.black.withOpacity(0.35),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isTranscribing) const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      _isTranscribing
                          ? 'Transcribing...'
                          : (_isSequenceRunning ? 'Inspection: $_currentStepLabel' : ''),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isSequenceRunning && !_isRecording)
                      const Text(
                        'Preparing to ask...',
                        style: TextStyle(color: Colors.white70),
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
}

/// small helper container for the sequence
class _FieldSpec {
  final String label;
  final String question;
  final TextEditingController controller;
  final String language;

  _FieldSpec(this.label, this.question, this.controller, this.language);
}
