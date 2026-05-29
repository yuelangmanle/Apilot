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
      // 构建 models URL
      String baseUrl = apiConfig.baseUrl;
      
      // 移除末尾的斜杠
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      
      // 如果已经包含 /models，直接使用
      // 否则添加 /models
      String modelsUrl;
      if (baseUrl.endsWith('/models')) {
        modelsUrl = baseUrl;
      } else if (baseUrl.endsWith('/v1') || baseUrl.endsWith('/v2') || baseUrl.endsWith('/v3')) {
        modelsUrl = '$baseUrl/models';
      } else {
        modelsUrl = '$baseUrl/models';
      }
      
      final uri = Uri.parse(modelsUrl);
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${apiConfig.apiKey}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // 处理 OpenAI 格式 {"data": [{"id": "model-name"}]}
        if (data is Map && data.containsKey('data')) {
          final models = data['data'] as List;
          return models.map((m) {
            if (m is Map && m.containsKey('id')) {
              return m['id'] as String;
            }
            return m.toString();
          }).toList();
        }
        
        // 处理其他格式 {"models": [{"name": "model-name"}]}
        if (data is Map && data.containsKey('models')) {
          final models = data['models'] as List;
          return models.map((m) {
            if (m is Map) {
              if (m.containsKey('id')) return m['id'] as String;
              if (m.containsKey('name')) return m['name'] as String;
            }
            return m.toString();
          }).toList();
        }
        
        // 处理数组格式
        if (data is List) {
          return data.map((m) {
            if (m is Map) {
              if (m.containsKey('id')) return m['id'] as String;
              if (m.containsKey('name')) return m['name'] as String;
            }
            return m.toString();
          }).toList();
        }
      }
      
      return [];
    } catch (e) {
      print('获取模型失败: $e');
      return [];
    }
  }
}
