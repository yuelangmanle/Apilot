import 'dart:convert';

import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/models/group.dart';
import 'package:api_manager/core/services/import_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports and imports groups, configs, and snapshot time', () async {
    final service = ImportExportService();
    final backup = await service.exportConfigs(
      [
        ApiConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'sk-test',
          models: const ['deepseek-chat'],
          group: 'LLM',
          environment: 'production',
        ),
      ],
      [Group(id: 'llm', name: 'LLM')],
    );

    final rawBackup = jsonDecode(backup) as Map<String, dynamic>;
    expect(rawBackup['exportedAt'], isA<String>());

    final imported = await service.importConfigs(backup);
    expect((imported['apiConfigs'] as List<ApiConfig>).single.group, 'LLM');
    expect((imported['groups'] as List<Group>).single.name, 'LLM');
    expect(imported['exportedAt'], isA<DateTime>());
  });
}
