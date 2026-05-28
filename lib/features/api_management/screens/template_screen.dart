import 'package:flutter/material.dart';
import '../../../core/data/api_templates.dart';
import '../../../core/models/api_config.dart';
import '../../../shared/theme/color_scheme.dart';
import 'api_form_screen.dart';

class TemplateScreen extends StatelessWidget {
  const TemplateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final templates = ApiTemplates.templates;

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择API模板'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final template = templates[index];
          return _buildTemplateCard(context, template);
        },
      ),
    );
  }

  Widget _buildTemplateCard(BuildContext context, ApiConfig template) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.api, color: AppColors.primary),
        ),
        title: Text(
          template.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              template.baseUrl,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: template.models.take(3).map((model) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    model,
                    style: const TextStyle(fontSize: 10, color: AppColors.secondary),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ApiFormScreen(apiConfig: template),
            ),
          );
          if (result == true && context.mounted) {
            Navigator.pop(context, true);
          }
        },
      ),
    );
  }
}
