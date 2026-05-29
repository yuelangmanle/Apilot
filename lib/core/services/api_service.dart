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
      String baseUrl = apiConfig.baseUrl.trim();
      
      // 移除末尾的斜杠
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      
      // 构建正确的 models URL
      // 对于 OpenAI 兼容的 API，models 端点通常在 /v1/models
      String modelsUrl;
      
      // 如果已经以 /models 结尾，直接使用
      if (baseUrl.endsWith('/models')) {
        modelsUrl = baseUrl;
      }
      // 如果已经包含版本号（如 /v1, /v2, /v3），直接添加 /models
      else if (baseUrl.endsWith('/v1') || baseUrl.endsWith('/v2') || baseUrl.endsWith('/v3') || 
               baseUrl.contains('/v1/') || baseUrl.contains('/v2/') || baseUrl.contains('/v3/')) {
        modelsUrl = '$baseUrl/models';
      }
      // 对于没有版本号的基础URL，需要添加 /v1/models
      // 这是 OpenAI 兼容 API 的标准路径
      else {
        modelsUrl = '$baseUrl/v1/models';
      }
      
      print('尝试获取模型列表: $modelsUrl');  // 调试日志
      
      final uri = Uri.parse(modelsUrl);
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${apiConfig.apiKey}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      print('响应状态码: ${response.statusCode}');  // 调试日志

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
      
      // 如果第一次尝试失败，尝试不带版本号的路径
      if (!baseUrl.endsWith('/models') && !baseUrl.contains('/v1') && !baseUrl.contains('/v2') && !baseUrl.contains('/v3')) {
        final fallbackUrl = '$baseUrl/models';
        print('尝试备用URL: $fallbackUrl');
        
        final fallbackResponse = await http.get(
          Uri.parse(fallbackUrl),
          headers: {
            'Authorization': 'Bearer ${apiConfig.apiKey}',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 15));
        
        if (fallbackResponse.statusCode == 200) {
          final data = jsonDecode(fallbackResponse.body);
          
          if (data is Map && data.containsKey('data')) {
            final models = data['data'] as List;
            return models.map((m) {
              if (m is Map && m.containsKey('id')) return m['id'] as String;
              return m.toString();
            }).toList();
          }
          
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
        }
      }
      
      return [];
    } catch (e) {
      print('获取模型失败: $e');
      return [];
    }
  }
}
