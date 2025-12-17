import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIImageTextExtractor {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: "https://api.openai.com/v1",
      headers: {
        "Authorization": "Bearer ${dotenv.env['OPENAI_API_KEY']}",
        "Content-Type": "application/json",
      },
    ),
  );

  Future<String> extractTextFromImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await _dio.post(
      "/chat/completions",
      data: {
        "model": "gpt-4o-mini",
        "messages": [
          {
            "role": "system",
            "content":
            "You are an OCR engine. Extract ALL visible text exactly as it appears. Do not explain."
          },
          {
            "role": "user",
            "content": [
              {
                "type": "text",
                "text": "Extract all readable text from this image."
              },
              {
                "type": "image_url",
                "image_url": {
                  "url": "data:image/jpeg;base64,$base64Image"
                }
              }
            ]
          }
        ],
        "temperature": 0
      },
    );

    return response
        .data["choices"]?[0]?["message"]?["content"]
        ?.toString()
        .trim() ??
        "";
  }
}
