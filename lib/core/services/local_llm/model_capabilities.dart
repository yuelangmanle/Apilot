/// 本地模型能力识别（按文件名/家族启发式判断）。
///
/// GGUF 文件本身不带"是否多模态/是否支持深度思考"的元数据标记，
/// 这里按业界通用命名约定判断，宁可保守（不确定就当纯文本）。
class ModelCapabilities {
  ModelCapabilities._();

  /// 多模态（视觉）模型家族关键字。
  static const _visionFamilies = [
    'qwen3.5', 'qwen3-5', 'mimo-vl', 'gemma-3n', 'gemma3n', 'lfm2-vl',
    'gemma-3', 'gemma3', 'qwen2-vl', 'qwen2.5-vl', 'qwen3-vl',
    'llava', 'bakllava', 'moondream', 'minicpm-v', 'minicpm-o',
    'phi-3.5-vision', 'phi-4-multimodal', 'smolvlm', 'internvl',
    'pixtral', 'llama-3.2-11b-vision', 'llama-3.2-90b-vision',
    'idefics', 'granite-vision', 'glm-4v', 'glm-4.1v', 'ovis',
    'nanovlm', 'fastvlm', 'lfm2-vl', 'mistral-small-3.1',
  ];

  /// 支持"深度思考"（显式推理链）的模型家族关键字。
  static const _thinkingFamilies = [
    'qwen3', 'qwq', 'deepseek-r1', 'deepseek-v3.1', 'deepseek-v3.2',
    'reasoner', 'reasoning', 'magistral', 'glm-z1', 'glm-4.5', 'glm-4.6',
    'phi-4-reasoning', 'exaone-deep', 'hunyuan-a13b', 'seed-oss',
    'granite-4', 'nemotron', 'minimax-m', 'spark-x', 'spark2',
    'gpt-oss', 'kimi-k2', 'step-3', 'ernie-4.5', 'ling-', 'ring-',
    'gemma-4', 'qwen3.5',
  ];

  /// 只有这些家族认得 `/no_think` 指令（Qwen3 系）。
  /// 给别的模型硬塞这个字符串会让它反复琢磨"这是不是格式错误"，
  /// 于是思考打转停不下来（真机实测：Spark-X2.5 就是这样死循环的）。
  static const _noThinkFamilies = ['qwen3', 'qwen3.5', 'qwq'];

  /// 该模型是否支持 `/no_think` 关闭思考指令。
  static bool supportsNoThinkDirective(String modelNameOrPath) {
    final name = _normalize(_baseName(modelNameOrPath));
    return _noThinkFamilies.any((family) => name.contains(_normalize(family)));
  }

  /// 归一化：小写，并把 `.`/`_`/`-` 统一成 `-`。
  /// 这样 `Qwen2_5_VL`、`qwen2.5-vl`、`qwen2-5-vl` 三种写法都能匹配同一族。
  static String _normalize(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[._]'), '-');

  /// 文件名是否为视觉投影文件（mmproj）——它不是可独立对话的模型。
  static bool isProjectorFile(String fileName) {
    final name = fileName.toLowerCase();
    return name.contains('mmproj') && name.endsWith('.gguf');
  }

  /// 是否为分片文件（需要多文件合并，App 内不支持）。
  static bool isShardedFile(String fileName) =>
      RegExp(r'-\d{5}-of-\d{5}\.gguf$', caseSensitive: false)
          .hasMatch(fileName);

  /// 该模型（按名称判断）是否属于多模态家族。
  /// 注意：真正能否看图还取决于是否加载了 mmproj（见 LocalLlmEngine.supportsVision）。
  static bool isVisionFamily(String modelNameOrPath) {
    final name = _normalize(_baseName(modelNameOrPath));
    // 明确的例外：Gemma 3 只有 4B 及以上是多模态，1B / 270M 是纯文本。
    if (name.contains('gemma-3-1b') ||
        name.contains('gemma-3-270m') ||
        name.contains('gemma3-1b')) {
      return false;
    }
    return _visionFamilies.any((family) => name.contains(_normalize(family)));
  }

  /// 该模型是否支持深度思考开关。
  static bool supportsThinking(String modelNameOrPath) {
    final name = _normalize(_baseName(modelNameOrPath));
    return _thinkingFamilies
        .any((family) => name.contains(_normalize(family)));
  }

  /// 取模型名的"核心词"：去掉 .gguf 与量化后缀。
  /// 例：`gemma-3-4b-it-Q4_K_M.gguf` → `gemma-3-4b-it`。
  /// 用于判断视觉投影是否与主模型同系列（mmproj 不通用，必须配对）。
  static String coreToken(String fileName) {
    var name = fileName.replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');
    // 从第一个量化标记处截断（-Q4_K_M / -IQ4_XS / -q8_0 / -f16 ...）。
    name = name.split(RegExp(r'-(?=(?:[Ii]?Q\d|[Ff](?:16|32)|[Bb][Ff]16))')).first;
    name = name.replaceAll(RegExp(r'[-_.]+$'), '');
    return name.toLowerCase();
  }

  static String _baseName(String path) {
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.isEmpty ? path : segments.last;
  }

  /// 面向界面的能力描述。
  static String describe(String modelNameOrPath, {bool? visionLoaded}) {
    final parts = <String>[];
    if (visionLoaded == true) {
      parts.add('多模态（可看图）');
    } else if (isVisionFamily(modelNameOrPath)) {
      parts.add('多模态家族（需视觉投影文件才能看图）');
    } else {
      parts.add('纯文本');
    }
    parts.add(supportsThinking(modelNameOrPath) ? '支持深度思考' : '无深度思考');
    return parts.join(' · ');
  }
}
