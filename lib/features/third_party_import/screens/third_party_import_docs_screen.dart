import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/color_scheme.dart';

class ThirdPartyImportDocsScreen extends StatelessWidget {
  const ThirdPartyImportDocsScreen({super.key});

  static const githubDocPath = 'docs/android-third-party-import.md';
  static const githubDocUrl =
      'https://github.com/yuelangmanle/Apilot/blob/main/docs/android-third-party-import.md';
  static const action = 'com.apilot.intent.action.IMPORT_API_CONFIGS';
  static const pickAction = 'com.apilot.intent.action.PICK_API_CONFIG';
  static const mimeType = 'application/vnd.apilot.api-configs+json';
  static const jsonExtra = 'com.apilot.extra.API_CONFIGS_JSON';
  static const apiConfigJsonExtra = 'com.apilot.extra.API_CONFIG_JSON';
  static const sourceNameExtra = 'com.apilot.extra.SOURCE_NAME';
  static const requestIdExtra = 'com.apilot.extra.REQUEST_ID';
  static const modelModeExtra = 'com.apilot.extra.MODEL_MODE';
  static const schemaVersionExtra = 'com.apilot.extra.SCHEMA_VERSION';
  static const requestedScopesExtra = 'com.apilot.extra.REQUESTED_SCOPES';
  static const returnTransportExtra = 'com.apilot.extra.RETURN_TRANSPORT';

  static const kotlinExample = '''
val intent = Intent("com.apilot.intent.action.IMPORT_API_CONFIGS").apply {
    setPackage("com.example.api_manager")
    setDataAndType(uri, "application/vnd.apilot.api-configs+json")
    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    putExtra("com.apilot.extra.SOURCE_NAME", "Example Client")
    putExtra("com.apilot.extra.REQUEST_ID", requestId)
}
startActivity(intent)
''';

  static const jsonExample = '''
{
  "schemaVersion": 2,
  "source": {
    "appName": "Example Client",
    "packageName": "com.example.client",
    "signatureSha256": "AA:BB:CC"
  },
  "apiProfiles": [
    {
      "connection": {
        "name": "DeepSeek Production",
        "baseUrl": "https://api.deepseek.com/v1"
      },
      "provider": {"id": "deepseek"},
      "protocol": {"id": "openai_compatible"},
      "models": {"selectedModel": "deepseek-chat"},
      "secrets": {"apiKey": "sk-..."}
    }
  ]
}
''';

  static const pickExample = '''
val launcher = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
) { result ->
    if (result.resultCode != Activity.RESULT_OK) return@registerForActivityResult
    val data = result.data ?: return@registerForActivityResult
    val payload = data.getStringExtra("com.apilot.extra.API_CONFIG_JSON")
        ?: data.data?.let { uri ->
            contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        } ?: return@registerForActivityResult
    // V2: provider/protocol 保留服务商语义；密钥仅在用户授权后出现。
}

launcher.launch(Intent("com.apilot.intent.action.PICK_API_CONFIG").apply {
    setPackage("com.example.api_manager")
    putExtra("com.apilot.extra.SOURCE_NAME", "Example Client")
    putExtra("com.apilot.extra.SCHEMA_VERSION", 2)
    putStringArrayListExtra(
        "com.apilot.extra.REQUESTED_SCOPES",
        arrayListOf("connection", "models.default", "models.all", "secret.api_key")
    )
    putExtra("com.apilot.extra.RETURN_TRANSPORT", "auto")
})
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('第三方接入文档'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '第三方 Android App 可以向 Apilot 导入配置，或让用户授权一条已保存的 API 方案。',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('接口常量'),
          _CopyableBlock(
            text: [
              'Action: $action',
              '选择已保存方案: $pickAction',
              'MIME: $mimeType',
              'JSON Extra: $jsonExtra',
              '回传 JSON: $apiConfigJsonExtra',
              'Source Extra: $sourceNameExtra',
              'Request ID Extra: $requestIdExtra',
              'V1 模型模式 Extra: $modelModeExtra',
              'V2 Schema Extra: $schemaVersionExtra',
              'V2 Scopes Extra: $requestedScopesExtra',
              'V2 回传方式 Extra: $returnTransportExtra',
              'Deep Link: apilot://import',
            ].join('\n'),
          ),
          const _SectionTitle('推荐 Kotlin 调用'),
          const _CopyableBlock(text: kotlinExample),
          const _SectionTitle('V2 JSON 最小格式'),
          const _CopyableBlock(text: jsonExample),
          const _SectionTitle('读取已保存方案'),
          const _CopyableBlock(text: pickExample),
          const _BulletList(
            items: [
              'MODEL_MODE=all：返回 apiConfig.models 完整列表，selectedModel 是列表第一个模型。',
              'MODEL_MODE=default_only：只返回 selectedModel，不返回模型列表，供调用方自行联网刷新。',
              'V2 默认只授权 connection 和 models.default；models.all 与 secret.api_key 必须由用户勾选。',
              'V2 结果可能通过 JSON extra 或临时 content:// URI 返回，调用方必须同时支持两者。',
              'provider.id 会保留 DeepSeek 等服务商身份；无法识别的服务才使用 custom。',
            ],
          ),
          const _SectionTitle('安全规则'),
          const _BulletList(
            items: [
              '推荐使用 content:// URI 传输 JSON 文件。',
              '不要把 API Key 放进 URL 或 Deep Link。',
              'apiKey 可缺省；缺省时导入为待补 Key 配置。',
              'Apilot 会先展示来源说明页，再展示导入确认页。',
              '第三方导入永远不会覆盖现有配置。',
              'V1 保留旧 Key 回传行为；V2 默认绝不回传 API Key。',
              'V2 只有用户明确勾选 secret.api_key 后才会回传密钥。',
            ],
          ),
          const _SectionTitle('GitHub 完整文档'),
          const _CopyableBlock(text: '$githubDocPath\n$githubDocUrl'),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _CopyableBlock extends StatelessWidget {
  final String text;

  const _CopyableBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('复制'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;

  const _BulletList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
