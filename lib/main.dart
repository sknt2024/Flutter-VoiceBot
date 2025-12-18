import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/home_page.dart';

/// Search upward from the current working directory for a filename.
/// Returns the first absolute path found or null.
String? findFileUpwards(String fileName) {
  try {
    Directory dir = Directory.current;
    // Safety: limit loop to avoid infinite root loop
    for (int i = 0; i < 12; i++) {
      final candidate = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (candidate.existsSync()) {
        return candidate.path;
      }
      // move to parent
      final parent = dir.parent;
      if (parent.path == dir.path) break; // reached root
      dir = parent;
    }
  } catch (e) {
    // ignore
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) First try obvious current directory
  String? envPath;
  try {
    // helpful debugging prints
    debugPrint('Current working directory: ${Directory.current.path}');
    // check common locations
    final candidates = [
      '.env',
      'assets/.env',
      'lib/.env',
    ];

    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) {
        envPath = f.path;
        break;
      }
    }

    if (envPath != null) {
      debugPrint('Loading .env from: $envPath');
      await dotenv.load(fileName: envPath);
    } else {
      // Fallback: attempt default load (this will still throw if file not found),
      // but we'll catch it and continue.
      try {
        await dotenv.load();
      } catch (e) {
        debugPrint('dotenv.load() failed: $e — continuing without .env');
      }
    }
  } catch (e, st) {
    debugPrint('Unexpected error while trying to load .env: $e\n$st');
  }

  // After load attempt, log whether key is available
  final key = dotenv.env['OPENAI_API_KEY'];
  if (key == null || key.isEmpty) {
    debugPrint('OPENAI_API_KEY NOT FOUND at runtime. dotenv.env keys: ${dotenv.env.keys.toList()}');
  } else {
    debugPrint('OPENAI_API_KEY loaded (length ${key.length})');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Assisted Inspection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}
