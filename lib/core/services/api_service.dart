import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_config.dart';

class ApiService {
  // 验证API是否有效
  Future<Map<String, dynamic>> validateApi(ApiConfig apiConfig) async {
    try {
      final models = await getAvailableModels(apiConfig);
      if (models.isNotEmpty) {
        return {
          'valid': true,
          'message': 'API有效，发现 ${models.length} 个模型',
          'models': models,
        };
      }
      
      // 尝试发送一个简单的请求来验证
      final testResult = await _testConnection(apiConfig);
      return testResult;
    } catch (e) {
      return {
        'valid': false,
        'message': 'API验证失败: $e',
      };
    }
  }

  Future<Map<String, dynamic>> _testConnection(ApiConfig apiConfig) async {
    try {
      String baseUrl = apiConfig.baseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      
      // 尝试访问根路径
      final uri = Uri.parse(baseUrl);
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${apiConfig.apiKey}',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode < 500) {
        return {
          'valid': true,
          'message': 'API可达，状态码: ${response.statusCode}',
        };
      }
      return {
        'valid': false,
        'message': 'API返回错误，状态码: ${response.statusCode}',
      };
    } catch (e) {
      return {
        'valid': false,
        'message': '无法连接到API: $e',
      };
    }
  }

  Future<List<String>> getAvailableModels(ApiConfig apiConfig) async {
    try {
      String baseUrl = apiConfig.baseUrl.trim();
      
      // 移除末尾的斜杠
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      
      // 构建 models URL - 尝试多种路径
      List<String> urlsToTry = [];
      
      if (baseUrl.endsWith('/models')) {
        urlsToTry.add(baseUrl);
      } else {
        // 如果已经有版本号，直接加 /models
        if (baseUrl.endsWith('/v1') || baseUrl.endsWith('/v2') || baseUrl.endsWith('/v3')) {
          urlsToTry.add('$baseUrl/models');
        }
        // 否则尝试 /v1/models 和 /models
        urlsToTry.add('$baseUrl/v1/models');
        urlsToTry.add('$baseUrl/models');
      }
      
      for (final modelsUrl in urlsToTry) {
        try {
          print('尝试获取模型: $modelsUrl');
          final uri = Uri.parse(modelsUrl);
          
          final response = await http.get(
            uri,
            headers: {
              'Authorization': 'Bearer ${apiConfig.apiKey}',
              'Content-Type': 'application/json',
            },
          ).timeout(const Duration(seconds: 15));

          print('响应状态码: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            List<String> models = [];
            
            // 处理 OpenAI 格式 {"data": [{"id": "model-name"}]}
            if (data is Map && data.containsKey('data')) {
              final modelsList = data['data'] as List;
              models = modelsList.map((m) {
                if (m is Map && m.containsKey('id')) {
                  return m['id'] as String;
                }
                return m.toString();
              }).toList();
            }
            // 处理 {"models": [{"name": "model-name"}]}
            else if (data is Map && data.containsKey('models')) {
              final modelsList = data['models'] as List;
              models = modelsList.map((m) {
                if (m is Map) {
                  if (m.containsKey('id')) return m['id'] as String;
                  if (m.containsKey('name')) return m['name'] as String;
                }
                return m.toString();
              }).toList();
            }
            // 处理数组格式
            else if (data is List) {
              models = data.map((m) {
                if (m is Map) {
                  if (m.containsKey('id')) return m['id'] as String;
                  if (m.containsKey('name')) return m['name'] as String;
                }
                return m.toString();
              }).toList();
            }
            
            if (models.isNotEmpty) {
              print('成功获取 ${models.length} 个模型');
              return models;
            }
          }
        } catch (e) {
          print('尝试 $modelsUrl 失败: $e');
          continue;
        }
      }
      
      return [];
    } catch (e) {
      print('获取模型失败: $e');
      return [];
    }
  }

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
}
