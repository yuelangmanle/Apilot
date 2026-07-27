import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_config.dart';

class ModelListFetchResult {
  final List<String> models;
  final String? sourceUrl;
  final String? errorMessage;

  const ModelListFetchResult._({
    required this.models,
    required this.sourceUrl,
    required this.errorMessage,
  });

  const ModelListFetchResult.success({
    required List<String> models,
    required String sourceUrl,
  }) : this._(
          models: models,
          sourceUrl: sourceUrl,
          errorMessage: null,
        );

  const ModelListFetchResult.failure(String message)
      : this._(
          models: const [],
          sourceUrl: null,
          errorMessage: message,
        );

  bool get isSuccess => errorMessage == null;
}

class ApiService {
  /// 智能拼接 URL，避免重复路径段
  static String buildUrl(String baseUrl, String endpoint) {
    String base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);

    String ep = endpoint.trim();
    if (ep.isEmpty) return base;
    if (!ep.startsWith('/')) ep = '/$ep';

    // 提取 base 的路径部分
    final baseUri = Uri.parse(base);
    final basePath = baseUri.path; // e.g. "/v1"

    // 如果 endpoint 以 basePath 结尾，说明重复了，去掉
    // 例如 base="/v1", endpoint="/v1/chat/completions" → 只用 base + "/chat/completions"
    if (basePath.isNotEmpty && ep.startsWith(basePath)) {
      final remainder = ep.substring(basePath.length);
      if (remainder.isEmpty || remainder.startsWith('/')) {
        return '$base$remainder';
      }
    }

    return '$base$ep';
  }

  /// 验证API是否有效
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
    return (await fetchAvailableModels(apiConfig)).models;
  }

  Future<ModelListFetchResult> fetchAvailableModels(ApiConfig apiConfig) async {
    try {
      String baseUrl = apiConfig.baseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      List<String> urlsToTry = [];

      if (baseUrl.endsWith('/models')) {
        urlsToTry.add(baseUrl);
      } else {
        if (baseUrl.endsWith('/v1') ||
            baseUrl.endsWith('/v2') ||
            baseUrl.endsWith('/v3')) {
          urlsToTry.add('$baseUrl/models');
        }
        urlsToTry.add('$baseUrl/v1/models');
        urlsToTry.add('$baseUrl/models');
      }

      String? lastError;
      for (final modelsUrl in urlsToTry) {
        try {
          final uri = Uri.parse(modelsUrl);
          final response = await http.get(
            uri,
            headers: {
              'Authorization': 'Bearer ${apiConfig.apiKey}',
              'Content-Type': 'application/json',
            },
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode != 200) {
            lastError = '$modelsUrl 返回状态码 ${response.statusCode}';
            continue;
          }

          final models = _parseModels(jsonDecode(response.body));
          if (models != null) {
            return ModelListFetchResult.success(
              models: models,
              sourceUrl: modelsUrl,
            );
          }
          lastError = '$modelsUrl 未返回可识别的模型列表';
        } catch (e) {
          lastError = '$modelsUrl 请求失败: $e';
          continue;
        }
      }

      return ModelListFetchResult.failure(lastError ?? '未获取到模型列表');
    } catch (e) {
      return ModelListFetchResult.failure('获取模型列表失败: $e');
    }
  }

  List<String>? _parseModels(Object? data) {
    final Object? modelsList;
    if (data is Map && data['data'] is List) {
      modelsList = data['data'];
    } else if (data is Map && data['models'] is List) {
      modelsList = data['models'];
    } else if (data is List) {
      modelsList = data;
    } else {
      return null;
    }

    final models = <String>[];
    for (final item in modelsList as List) {
      final model = item is Map
          ? (item['id'] ?? item['name'])?.toString()
          : item?.toString();
      final trimmed = model?.trim();
      if (trimmed != null && trimmed.isNotEmpty && !models.contains(trimmed)) {
        models.add(trimmed);
      }
    }
    return models;
  }

  Future<Map<String, dynamic>> sendRequest({
    required ApiConfig apiConfig,
    required String model,
    required String endpoint,
    required Map<String, dynamic> requestBody,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final url = buildUrl(apiConfig.baseUrl, endpoint);
      final uri = Uri.parse(url);

      // 确保 model 在请求体中
      final body = Map<String, dynamic>.from(requestBody);
      if (!body.containsKey('model')) {
        body['model'] = model;
      }

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiConfig.apiKey}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      stopwatch.stop();

      Map<String, dynamic> responseBody;
      try {
        responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        responseBody = {'raw': response.body};
      }

      return {
        'statusCode': response.statusCode,
        'body': responseBody,
        'duration': stopwatch.elapsedMilliseconds,
      };
    } catch (e) {
      stopwatch.stop();
      rethrow;
    }
  }

  /// 发送请求并返回完整响应（包含headers）
  Future<Map<String, dynamic>> sendRequestWithHeaders({
    required ApiConfig apiConfig,
    required String model,
    required String endpoint,
    required Map<String, dynamic> requestBody,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final url = buildUrl(apiConfig.baseUrl, endpoint);
      final uri = Uri.parse(url);

      final body = Map<String, dynamic>.from(requestBody);
      if (!body.containsKey('model')) {
        body['model'] = model;
      }

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiConfig.apiKey}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      stopwatch.stop();

      Map<String, dynamic> responseBody;
      try {
        responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        responseBody = {'raw': response.body};
      }

      final headers = <String, String>{};
      response.headers.forEach((key, value) {
        headers[key] = value;
      });

      return {
        'statusCode': response.statusCode,
        'body': responseBody,
        'headers': headers,
        'duration': stopwatch.elapsedMilliseconds,
      };
    } catch (e) {
      stopwatch.stop();
      rethrow;
    }
  }
}
