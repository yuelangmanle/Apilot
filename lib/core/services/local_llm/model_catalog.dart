
/// 社区仓库中的一个可下载文件（真实文件名/大小/下载地址）。
class ModelFileVariant {
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;
  final String quantization;

  const ModelFileVariant({
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.quantization,
  });

  String get sizeMb => sizeBytes <= 0
      ? '大小未知'
      : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  String get sizeLabel => sizeBytes <= 0
      ? '大小未知'
      : sizeBytes >= 1024 * 1024 * 1024
          ? '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
          : sizeMb;

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'quantization': quantization,
      };

  static ModelFileVariant fromJson(Map<String, dynamic> json) =>
      ModelFileVariant(
        fileName: json['fileName'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        quantization: json['quantization'] as String? ?? 'Q4_K_M',
      );
}

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

  /// 仓库内全部可选文件（社区模型才有；内置目录为空）。
  final List<ModelFileVariant> variants;

  /// 视觉投影文件（多模态模型需要它才能看图，可空）。
  final String? mmProjUrl;

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
    this.variants = const [],
    this.mmProjUrl,
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
        if (mmProjUrl != null) 'mmProjUrl': mmProjUrl,
        if (variants.isNotEmpty)
          'variants': variants.map((v) => v.toJson()).toList(),
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
        mmProjUrl: json['mmProjUrl'] as String?,
        variants: (json['variants'] as List?)
                ?.whereType<Map>()
                .map((v) =>
                    ModelFileVariant.fromJson(Map<String, dynamic>.from(v)))
                .toList() ??
            const [],
      );
}

/// 内置模型目录。
class LocalModelCatalog {
  LocalModelCatalog._();

  static const List<LocalModelInfo> builtin = [
    LocalModelInfo(
      id: 'qwen3-0.6b-q4km',
      name: 'Qwen3-0.6B (Q4_K_M)',
      description: '通义千问 3 超轻量版（0.37GB）。几乎任何手机都能跑，'
          '适合快速问答与低配设备；支持深度思考开关。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
      sizeBytes: 397284474,
      quantization: 'Q4_K_M',
      ramRequired: '~0.8 GB',
      tags: ['中文', '超轻量', '可深度思考'],
      license: 'Apache-2.0',
    ),
    LocalModelInfo(
      id: 'qwen3-1.7b-q4km',
      name: 'Qwen3-1.7B (Q4_K_M)',
      description: '通义千问 3（1.03GB）。中文能力强、体积小，'
          '日常问答和轻量任务的首选；支持深度思考开关。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
      sizeBytes: 1105734656,
      quantization: 'Q4_K_M',
      ramRequired: '~1.6 GB',
      tags: ['中文', '轻量', '可深度思考'],
      recommended: true,
      license: 'Apache-2.0',
    ),
    LocalModelInfo(
      id: 'qwen3-4b-q4km',
      name: 'Qwen3-4B (Q4_K_M)',
      description: '通义千问 3 4B（2.33GB）。中文与推理的平衡点，'
          '适合主力使用；支持深度思考开关。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
      sizeBytes: 2502239232,
      quantization: 'Q4_K_M',
      ramRequired: '~3.5 GB',
      tags: ['中文', '推理', '可深度思考'],
      recommended: true,
      license: 'Apache-2.0',
    ),
    // ── Qwen3.5 系列（会思考 + 能看图） ─────────────────────────
    LocalModelInfo(
      id: 'qwen3.5-0.8b-q4km',
      name: 'Qwen3.5 0.8B (Q4_K_M)',
      description: '通义千问 3.5 超小杯（0.5GB）。会思考、能看图（含视觉投影），'
          '低配手机的救星。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf',
      sizeBytes: 536870912,
      quantization: 'Q4_K_M',
      ramRequired: '~1.0 GB',
      tags: ['中文', '超轻量', '多模态', '可深度思考', '最新'],
      recommended: true,
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/mmproj-BF16.gguf',
    ),
    LocalModelInfo(
      id: 'qwen3.5-2b-q4km',
      name: 'Qwen3.5 2B (Q4_K_M)',
      description: '通义千问 3.5 2B（1.19GB）。会思考 + 能看图，'
          '2B 档最均衡的选择。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
      sizeBytes: 1277752771,
      quantization: 'Q4_K_M',
      ramRequired: '~1.8 GB',
      tags: ['中文', '多模态', '可深度思考', '最新'],
      recommended: true,
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/mmproj-BF16.gguf',
    ),
    LocalModelInfo(
      id: 'qwen3.5-4b-q4km',
      name: 'Qwen3.5 4B (Q4_K_M)',
      description: '通义千问 3.5 4B（2.55GB）。会思考 + 能看图，'
          '主力机首选。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf',
      sizeBytes: 2738041651,
      quantization: 'Q4_K_M',
      ramRequired: '~3.7 GB',
      tags: ['中文', '多模态', '可深度思考', '最新'],
      recommended: true,
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/mmproj-BF16.gguf',
    ),
    LocalModelInfo(
      id: 'qwen3.5-9b-q4km',
      name: 'Qwen3.5 9B (Q4_K_M)',
      description: '通义千问 3.5 9B（5.29GB）。旗舰小杯：会思考 + 能看图，'
          '适合 13GB+ 内存设备。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf',
      sizeBytes: 5680046080,
      quantization: 'Q4_K_M',
      ramRequired: '~7.7 GB',
      tags: ['中文', '多模态', '可深度思考', '最新'],
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/mmproj-BF16.gguf',
    ),
    // ── MiMo 蒸馏 / 扩展系列 ───────────────────────────────────
    LocalModelInfo(
      id: 'mimo-v2.6-distill-qwen-9b-q4km',
      name: 'MiMo-V2.6-Distill-Qwen-9B (Q4_K_M)',
      description: '小米 MiMo 用 Qwen3.5 蒸馏的 9B（5.44GB）。'
          '推理与中文表达比原版更利落，带视觉投影可看图。',
      downloadUrl:
          'https://huggingface.co/bartowski/MiMo-V2.6-Distill-Qwen-9B-GGUF/resolve/main/MiMo-V2.6-Distill-Qwen-9B-Q4_K_M.gguf',
      sizeBytes: 5841155523,
      quantization: 'Q4_K_M',
      ramRequired: '~7.9 GB',
      tags: ['中文', '推理', '多模态', 'MiMo'],
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/bartowski/MiMo-V2.6-Distill-Qwen-9B-GGUF/resolve/main/mmproj-MiMo-V2.6-Distill-Qwen-9B-bf16.gguf',
    ),
    // ── 视觉专项（小体积优先） ──────────────────────────────────
    LocalModelInfo(
      id: 'qwen3-vl-2b-instruct-q4km',
      name: 'Qwen3-VL 2B Instruct (Q4_K_M)',
      description: '通义千问 3 视觉 2B（1.03GB）。手机上最小最好用的中文视觉模型，'
          '看图、识别截图文字都行。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-VL-2B-Instruct-GGUF/resolve/main/Qwen3-VL-2B-Instruct-Q4_K_M.gguf',
      sizeBytes: 1105956864,
      quantization: 'Q4_K_M',
      ramRequired: '~1.6 GB',
      tags: ['中文', '多模态', '视觉', '轻量', '最新'],
      recommended: true,
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/unsloth/Qwen3-VL-2B-Instruct-GGUF/resolve/main/mmproj-BF16.gguf',
    ),
    LocalModelInfo(
      id: 'qwen3-vl-4b-instruct-q4km',
      name: 'Qwen3-VL 4B Instruct (Q4_K_M)',
      description: '通义千问 3 视觉 4B（2.33GB）。图文理解更细，'
          '适合看图表、长截图。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-VL-4B-Instruct-GGUF/resolve/main/Qwen3-VL-4B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2501820416,
      quantization: 'Q4_K_M',
      ramRequired: '~3.4 GB',
      tags: ['中文', '多模态', '视觉', '最新'],
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/unsloth/Qwen3-VL-4B-Instruct-GGUF/resolve/main/mmproj-BF16.gguf',
    ),
    LocalModelInfo(
      id: 'smolvlm2-2.2b-q4km',
      name: 'SmolVLM2 2.2B (Q4_K_M)',
      description: 'HuggingFace 出品的小视觉模型（1.04GB）。英文为主，'
          '极致轻量的看图选择。',
      downloadUrl:
          'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/SmolVLM2-2.2B-Instruct-Q4_K_M.gguf',
      sizeBytes: 1116691496,
      quantization: 'Q4_K_M',
      ramRequired: '~1.7 GB',
      tags: ['英文', '多模态', '视觉', '轻量'],
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-2.2B-Instruct-Q8_0.gguf',
    ),
    LocalModelInfo(
      id: 'minicpm-v-4.5-q4km',
      name: 'MiniCPM-V 4.5 (Q4_K_M)',
      description: '面壁智能 MiniCPM-V 4.5（4.68GB）。中文图文/OCR 口碑极好，'
          '适合拍文档、表格识别。',
      downloadUrl:
          'https://huggingface.co/openbmb/MiniCPM-V-4_5-gguf/resolve/main/MiniCPM-V-4_5-Q4_K_M.gguf',
      sizeBytes: 5025116160,
      quantization: 'Q4_K_M',
      ramRequired: '~6.8 GB',
      tags: ['中文', '多模态', '视觉', 'OCR'],
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/openbmb/MiniCPM-V-4_5-gguf/resolve/main/mmproj-MiniCPM-V-4_5-f16.gguf',
    ),
    // ── 通用大杯 ────────────────────────────────────────────────
    LocalModelInfo(
      id: 'qwen3-8b-q4km',
      name: 'Qwen3 8B (Q4_K_M)',
      description: '通义千问 3 8B（4.68GB）。纯文本主力：中文写作、'
          '推理、代码都够用，适合 12GB+ 内存。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf',
      sizeBytes: 5025116160,
      quantization: 'Q4_K_M',
      ramRequired: '~6.8 GB',
      tags: ['中文', '推理', '可深度思考'],
      license: 'Apache-2.0',
    ),
    LocalModelInfo(
      id: 'deepseek-r1-0528-qwen3-8b-q4km',
      name: 'DeepSeek-R1-0528-Qwen3-8B (Q4_K_M)',
      description: 'DeepSeek R1-0528 蒸馏到 Qwen3 8B（4.68GB）。'
          '中文数学与多步推理强，思考过程可折叠查看。',
      downloadUrl:
          'https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf',
      sizeBytes: 5025116160,
      quantization: 'Q4_K_M',
      ramRequired: '~6.8 GB',
      tags: ['中文', '推理', '可深度思考'],
      license: 'MIT',
    ),
    LocalModelInfo(
      id: 'gemma-3-4b-qat-q4km',
      name: 'Gemma 3 4B QAT (Q4_K_M)',
      description: 'Google 官方量化感知训练的 Gemma 3 4B（2.32GB）。'
          '量化损失更小、能看图（带视觉投影）。',
      downloadUrl:
          'https://huggingface.co/unsloth/gemma-3-4b-it-qat-GGUF/resolve/main/gemma-3-4b-it-qat-Q4_K_M.gguf',
      sizeBytes: 2491081032,
      quantization: 'Q4_K_M',
      ramRequired: '~3.4 GB',
      tags: ['英文', '多模态', 'Google', 'QAT'],
      license: 'Gemma Terms',
      mmProjUrl:
          'https://huggingface.co/unsloth/gemma-3-4b-it-qat-GGUF/resolve/main/mmproj-BF16.gguf',
    ),
    LocalModelInfo(
      id: 'spark-x2.5-1.7b-q4km',
      name: 'Spark-X2.5 1.7B (Q4_K_M)',
      description: '芯火端侧智能体模型（1.03GB，Apache-2.0）。'
          '专为手机端"会调用工具、多步执行"调优，配合本应用件系统效果最好。',
      downloadUrl:
          'https://huggingface.co/XHToken/Spark-X2.5-1.7B-GGUF/resolve/main/Spark-X2.5-1.7B-Q4_K_M.gguf',
      sizeBytes: 1105734656,
      quantization: 'Q4_K_M',
      ramRequired: '~1.6 GB',
      tags: ['中文', '智能体', '端侧', '推荐'],
      recommended: true,
      license: 'Apache-2.0',
    ),
    LocalModelInfo(
      id: 'spark-x2.5-4b-q4km',
      name: 'Spark-X2.5 4B (Q4_K_M)',
      description: '芯火端侧智能体模型 4B（2.42GB，Apache-2.0）。'
          '端侧智能体能力更强，工具调用/多步任务更稳，适合主力机。',
      downloadUrl:
          'https://huggingface.co/XHToken/Spark-X2.5-4B-GGUF/resolve/main/Spark-X2.5-4B-Q4_K_M.gguf',
      sizeBytes: 2598119424,
      quantization: 'Q4_K_M',
      ramRequired: '~3.5 GB',
      tags: ['中文', '智能体', '端侧'],
      recommended: true,
      license: 'Apache-2.0',
    ),
    LocalModelInfo(
      id: 'qwen3-4b-thinking-q4km',
      name: 'Qwen3-4B-Thinking-2507 (Q4_K_M)',
      description: '专为"深度思考"调优的 Qwen3 4B（2.33GB）。'
          '数学、代码、多步推理更强，思考过程可折叠查看。',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q4_K_M.gguf',
      sizeBytes: 2502239232,
      quantization: 'Q4_K_M',
      ramRequired: '~3.5 GB',
      tags: ['中文', '推理', '可深度思考'],
      license: 'Apache-2.0',
    ),
    LocalModelInfo(
      id: 'gemma-3-1b-it-q4km',
      name: 'Gemma 3 1B IT (Q4_K_M)',
      description: 'Google Gemma 3 1B（0.75GB）。英文与多语言表现好，'
          '轻快省电，适合英文对话。',
      downloadUrl:
          'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf',
      sizeBytes: 806546048,
      quantization: 'Q4_K_M',
      ramRequired: '~1.4 GB',
      tags: ['英文', '轻量', 'Google'],
      license: 'Gemma Terms',
    ),
    LocalModelInfo(
      id: 'gemma-3-4b-it-q4km',
      name: 'Gemma 3 4B IT (Q4_K_M)',
      description: 'Gemma 3 4B（2.32GB）多模态版：可看图。'
          '下载后如需看图，再补装"视觉投影"文件（0.79GB）。',
      downloadUrl:
          'https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf',
      sizeBytes: 2491081032,
      quantization: 'Q4_K_M',
      ramRequired: '~3.4 GB',
      tags: ['多模态', '英文', 'Google'],
      license: 'Gemma Terms',
      mmProjUrl:
          'https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/mmproj-F16.gguf',
    ),
    LocalModelInfo(
      id: 'llama-3.2-3b-q4km',
      name: 'Llama 3.2 3B (Q4_K_M)',
      description: 'Meta Llama 3.2 3B（1.88GB）。英文对话与通用任务扎实，'
          '生态成熟。',
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2018634854,
      quantization: 'Q4_K_M',
      ramRequired: '~2.7 GB',
      tags: ['英文', 'Meta'],
      license: 'Llama 3.2 Community',
    ),
    LocalModelInfo(
      id: 'qwen2.5-vl-7b-q4km',
      name: 'Qwen2.5-VL 7B (Q4_K_M)',
      description: '通义千问视觉理解模型（4.36GB）多模态：能看图、读图表、'
          '识别截图文字。需补装视觉投影文件（0.79GB）。',
      downloadUrl:
          'https://huggingface.co/ggml-org/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf',
      sizeBytes: 4681513472,
      quantization: 'Q4_K_M',
      ramRequired: '~6.3 GB',
      tags: ['多模态', '中文', '视觉'],
      license: 'Apache-2.0',
      mmProjUrl:
          'https://huggingface.co/ggml-org/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf',
    ),
    LocalModelInfo(
      id: 'deepseek-r1-distill-qwen-7b-q4km',
      name: 'DeepSeek-R1-Distill-Qwen-7B (Q4_K_M)',
      description: 'DeepSeek R1 蒸馏的 7B 推理模型（4.36GB）。'
          '中文推理、数学解题强，会先输出思考过程。',
      downloadUrl:
          'https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf',
      sizeBytes: 4681513472,
      quantization: 'Q4_K_M',
      ramRequired: '~6.3 GB',
      tags: ['中文', '推理', '可深度思考'],
      license: 'MIT',
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
