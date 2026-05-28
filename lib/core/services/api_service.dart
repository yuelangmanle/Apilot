import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_config.dart';

class ApiService {
  Future<Map<String, dynamic>> sendRequest({
    required ApiConfig apiConfig,
    required String model,
    required String endpoint,
    required Map<String, dynamic> requestBody,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final uri = Uri.parse('${apiConfig.baseUrl}$endpoint');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${apiConfig.apiKey}',
        },
        body: jsonEncode(requestBody),
      );

      stopwatch.stop();

      return {
        'statusCode': response.statusCode,
        'body': jsonDecode(response.body),
        'duration': stopwatch.elapsedMilliseconds,
      };
    } catch (e) {
      stopwatch.stop();
      rethrow;
    }
  }

  Future<List<String>> getAvailableModels(ApiConfig apiConfig) async {
    try {
      final uri = Uri.parse('${apiConfig.baseUrl}/models');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${apiConfig.apiKey}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['data'] as List;
        return models.map((m) => m['id'] as String).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
