import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model_catalog.dart';

/// 从 HuggingFace / ModelScope 等社区实时获取模型列表。
/// 使用公开 API，无需鉴权。失败时回退内置目录。
class CommunityModelService {
  CommunityModelService._();

  static const Duration _timeout = Duration(seconds: 15);

  /// 从 HuggingFace API 搜索 GGUF 模型。
  /// https://huggingface.co/api/models?search=gguf&sort=downloads&limit=20
  static Future<List<LocalModelInfo>> fetchHuggingFaceModels({
    String query = 'gguf',
    int limit = 20,
  }) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://huggingface.co/api/models?search=$query&sort=downloads&limit=$limit&filter=text-generation',
      );
      final request = await client.getUrl(uri);
      final response =
          await request.close().timeout(_timeout);
      if (response.statusCode != 200) return [];
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(body);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => _parseHfModel(Map<String, dynamic>.from(item)))
          .where((m) => m != null)
          .cast<LocalModelInfo>()
          .toList();
    } catch (e) {
      debugPrint('[CommunityModels] HF 拉取失败: $e');
      return [];
    }
  }

  static LocalModelInfo? _parseHfModel(Map<String, dynamic> item) {
    final id = item['id'] as String? ?? '';
    if (id.isEmpty || !id.toLowerCase().contains('gguf')) return null;
    final downloads = (item['downloads'] as num?)?.toInt() ?? 0;
    final likes = (item['likes'] as num?)?.toInt() ?? 0;
    return LocalModelInfo(
      id: 'hf_$id',
      name: id.split('/').last,
      description: 'HuggingFace · $downloads 次下载 · $likes 赞',
      downloadUrl:
          'https://huggingface.co/$id/resolve/main/${id.split('/').last}-Q4_K_M.gguf',
      sizeBytes: 0, // API 不一定返回大小，下载时自动检测
      quantization: 'Q4_K_M',
      ramRequired: '',
      tags: ['HuggingFace'],
    );
  }

  /// 从 ModelScope API 搜索 GGUF 模型。
  static Future<List<LocalModelInfo>> fetchModelScopeModels({
    String query = 'gguf',
    int limit = 20,
  }) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://modelscope.cn/api/v1/models?Search=$query&PageSize=$limit',
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) return [];
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return [];
      final data = decoded['Data'];
      if (data is! Map) return [];
      final models = data['Models'];
      if (models is! List) return [];
      return models
          .whereType<Map>()
          .map((item) => _parseModelScopeModel(
              Map<String, dynamic>.from(item)))
          .where((m) => m != null)
          .cast<LocalModelInfo>()
          .toList();
    } catch (e) {
      debugPrint('[CommunityModels] ModelScope 拉取失败: $e');
      return [];
    }
  }

  static LocalModelInfo? _parseModelScopeModel(Map<String, dynamic> item) {
    final name = item['Name'] as String? ?? '';
    final path = item['Path'] as String? ?? '';
    if (name.isEmpty || path.isEmpty) return null;
    return LocalModelInfo(
      id: 'ms_$path',
      name: name,
      description: 'ModelScope · ${item['Downloads'] ?? ''}次下载',
      downloadUrl:
          'https://modelscope.cn/api/v1/models/$path/repo?FilePath=$name-Q4_K_M.gguf',
      sizeBytes: 0,
      quantization: 'Q4_K_M',
      ramRequired: '',
      tags: ['ModelScope'],
    );
  }
}
