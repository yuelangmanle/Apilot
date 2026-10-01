
/// 内置本地模型目录：名称/描述/下载地址/量化等级/内存需求。
/// 数据来自 HuggingFace 公开 GGUF 镜像，中国网络可直连或走镜像站。
class LocalModelInfo {
  final String id;
  final String name;
  final String description;
  final String downloadUrl;
  final int sizeBytes;
  final String quantization;
  final String ramRequired;
  final List<String> tags;
  final bool recommended;
  final String? license;

  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.quantization,
    required this.ramRequired,
    this.tags = const [],
    this.recommended = false,
    this.license,
  });

  String get sizeMb => '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'quantization': quantization,
        'ramRequired': ramRequired,
        'tags': tags,
      };

  static LocalModelInfo fromJson(Map<String, dynamic> json) => LocalModelInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        quantization: json['quantization'] as String? ?? 'Q4_K_M',
        ramRequired: json['ramRequired'] as String? ?? '',
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        recommended: json['recommended'] == true,
      );
}

/// 内置模型目录。
class LocalModelCatalog {
  LocalModelCatalog._();

  static const List<LocalModelInfo> builtin = [
    LocalModelInfo(
      id: 'qwen3-1.7b-q4km',
      name: 'Qwen3-1.7B (Q4_K_M)',
      description: '通义千问 1.7B 量化版。中文最强小模型，支持思考模式开关，'
          '适合日常问答和轻量任务。约 1.4GB。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
      sizeBytes: 1400000000,
      quantization: 'Q4_K_M',
      ramRequired: '~2 GB',
      tags: ['中文', '轻量', '推荐'],
      recommended: true,
      license: 'Apache-2.0',
    ),
    LocalModelInfo(
      id: 'qwen3-4b-q4km',
      name: 'Qwen3-4B (Q4_K_M)',
      description: '通义千问 4B 量化版。能力更强，支持思考模式开关，'
          '适合需要更好推理质量的场景。约 2.5GB。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
      sizeBytes: 2500000000,
      quantization: 'Q4_K_M',
      ramRequired: '~3.5 GB',
      tags: ['中文', '推理', '推荐'],
      recommended: true,
      license: 'Apache-2.0',
    ),
    LocalModelInfo(
      id: 'gemma-3-1b-it-q4km',
      name: 'Gemma 3 1B IT (Q4_K_M)',
      description: 'Google Gemma 3 1B 指令调优版。英文能力优秀，多语言支持好。',
      downloadUrl:
          'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf',
      sizeBytes: 800000000,
      quantization: 'Q4_K_M',
      ramRequired: '~1.5 GB',
      tags: ['英文', '轻量', 'Google'],
      license: 'Gemma Terms',
    ),
    LocalModelInfo(
      id: 'llama-3.2-3b-q4km',
      name: 'Llama 3.2 3B (Q4_K_M)',
      description: 'Meta Llama 3.2 3B 量化版。Meta 官方小模型，'
          '英文对话和通用任务能力强。',
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2000000000,
      quantization: 'Q4_K_M',
      ramRequired: '~2.5 GB',
      tags: ['英文', 'Meta'],
      license: 'Llama 3.2 Community',
    ),
  ];

  /// 按 id 查找内置模型。
  static LocalModelInfo? findById(String id) {
    for (final model in builtin) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// 根据设备可用内存（MB）推荐适合的模型。
  static List<LocalModelInfo> recommendForRam(int ramMb) {
    return builtin.where((m) {
      final requiredMb = (m.sizeBytes / (1024 * 1024)).ceil() + 800;
      return requiredMb <= ramMb;
    }).toList();
  }
}
