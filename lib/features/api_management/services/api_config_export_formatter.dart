/// 把 API 配置渲染成其他工具可直接使用的文本格式。
///
/// 纯字符串模板，零外部依赖；供详情页"复制为…"使用，
/// 完成"在别的工具里用这套配置"的最后一公里。
class ApiConfigExportFormatter {
  const ApiConfigExportFormatter._();

  static String toCurl({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) {
    final endpoint = _chatCompletionsEndpoint(baseUrl);
    return "curl '$endpoint' \\\n"
        "  -H 'Content-Type: application/json' \\\n"
        "  -H 'Authorization: Bearer $apiKey' \\\n"
        "  -d '{\n"
        '    "model": "$model",\n'
        '    "messages": [{"role": "user", "content": "Hello"}]\n'
        "  }'";
  }

  static String toEnv({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String? model,
  }) {
    final key = _envKey(name);
    return 'export ${key}_BASE_URL="$baseUrl"\n'
        'export ${key}_API_KEY="$apiKey"'
        '${model == null || model.isEmpty ? '' : '\nexport ${key}_MODEL="$model"'}';
  }

  static String toOpenAiClientSnippet({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) {
    return 'from openai import OpenAI\n'
        '\n'
        'client = OpenAI(\n'
        '    base_url="$baseUrl",\n'
        '    api_key="$apiKey",\n'
        ')\n'
        '\n'
        'response = client.chat.completions.create(\n'
        '    model="$model",\n'
        '    messages=[{"role": "user", "content": "Hello"}],\n'
        ')\n'
        'print(response.choices[0].message.content)';
  }

  static String _chatCompletionsEndpoint(String baseUrl) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) return base;
    if (base.endsWith('/v1') ||
        base.endsWith('/v2') ||
        base.endsWith('/v3') ||
        base.endsWith('/api/v3')) {
      return '$base/chat/completions';
    }
    return '$base/v1/chat/completions';
  }

  static String _envKey(String name) {
    var key = name.trim().toUpperCase().replaceAll(
          RegExp(r'[^A-Z0-9]+'),
          '_',
        );
    key = key.replaceAll(RegExp(r'_+'), '_');
    key = key.replaceAll(RegExp(r'^_+|_+$'), '');
    if (key.isEmpty) return 'API_CONFIG';
    if (RegExp(r'^[0-9]').hasMatch(key)) key = 'API_$key';
    return key;
  }
}
